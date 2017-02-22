###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Olaf Schnicke
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################


package main;

use strict;
use warnings;
use JSON qw(decode_json);
use Encode qw(encode_utf8);


my $version = "0.1.57";




# Declare functions
sub HEOSGroup_Initialize($);
sub HEOSGroup_Define($$);
sub HEOSGroup_Undef($$);
sub HEOSGroup_Attr(@);
sub HEOSGroup_Parse($$);
sub HEOSGroup_WriteReadings($$);
sub HEOSGroup_Set($$@);
sub HEOSGroup_PreProcessingReadings($$);
sub HEOSGroup_GetGroupInfo($);
sub HEOSGroup_GetGroupVolume($);
sub HEOSGroup_GetGroupMute($);





sub HEOSGroup_Initialize($) {

    my ($hash) = @_;

    $hash->{Match}          = '.*{"command":."group.*|.*{"command":."event\/group.*';
    
    # Provider
    $hash->{SetFn}          = "HEOSGroup_Set";
    $hash->{DefFn}          = "HEOSGroup_Define";
    $hash->{UndefFn}        = "HEOSGroup_Undef";
    $hash->{AttrFn}         = "HEOSGroup_Attr";
    $hash->{ParseFn}        = "HEOSGroup_Parse";
    
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              "mute2play:1 ".
                              $readingFnAttributes;



    foreach my $d(sort keys %{$modules{HEOSGroup}{defptr}}) {
        my $hash = $modules{HEOSGroup}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub HEOSGroup_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t]+", $def );
    splice( @a, 1, 1 );
    my $iodev;
    my $i = 0;
    
    foreach my $param ( @a ) {
        if( $param =~ m/IODev=([^\s]*)/ ) {
            $iodev = $1;
            splice( @a, $i, 3 );
            last;
        }
        
        $i++;
    }

    return "too few parameters: define <name> HEOSGroup <gid>" if( @a < 2 );

    my ($name,$gid)     = @a;

    $hash->{GID}        = $gid;
    $hash->{VERSION}    = $version;
    
    
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "HEOSGroup ($name) - I/O device is " . $hash->{IODev}->{NAME};
    } else {
    
        Log3 $name, 1, "HEOSGroup ($name) - no I/O device";
    }
    
    $iodev = $hash->{IODev}->{NAME};

    
    my $code = abs($gid);
    $code = $iodev."-".$code if( defined($iodev) );
    my $d = $modules{HEOSGroup}{defptr}{$code};
    return "HEOSGroup device $hash->{GID} on HEOSMaster $iodev already defined as $d->{NAME}."
        if( defined($d)
            && $d->{IODev} == $hash->{IODev}
            && $d->{NAME} ne $name );
  
  
    Log3 $name, 3, "HEOSGroup ($name) - defined with Code: $code";

    $attr{$name}{room}          = "HEOS" if( !defined( $attr{$name}{room} ) );
    $attr{$name}{devStateIcon}  = "on:10px-kreis-gruen off:10px-kreis-rot" if( !defined( $attr{$name}{devStateIcon} ) );
    
    
    if( $init_done ) {
        InternalTimer( gettimeofday()+int(rand(2)), "HEOSGroup_GetGroupInfo", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(4)), "HEOSGroup_GetGroupVolume", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(6)), "HEOSGroup_GetGroupMute", $hash, 0 );
    } else {
        InternalTimer( gettimeofday()+15+int(rand(2)), "HEOSGroup_GetGroupInfo", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(4)), "HEOSGroup_GetGroupVolume", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(6)), "HEOSGroup_GetGroupMute", $hash, 0 );
    }
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state','Initialized');
    readingsBulkUpdate($hash, 'volumeUp', 5);
    readingsBulkUpdate($hash, 'volumeDown', 5);
    readingsEndUpdate($hash, 1);
    
    
    $modules{HEOSGroup}{defptr}{$code} = $hash;
    
    return undef;
}

sub HEOSGroup_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $gid = $hash->{GID};
    my $name = $hash->{NAME};

    
    RemoveInternalTimer($hash);

    my $code = abs($gid);
    $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
    delete($modules{HEOSGroup}{defptr}{$code});
    
    Log3 $name, 3, "HEOSGroup ($name) - device $name deleted with Code: $code";

    return undef;
}

sub HEOSGroup_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "HEOSGroup ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSGroup ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "HEOSGroup ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSGroup ($name) - delete disabledForIntervals";
        }
    }
}

sub HEOSGroup_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    
    my $gid         = $hash->{GID};
    my $action;
    my $heosCmd;
    my $rvalue;
    my $favcount    = 1;
    my $string      = "gid=$gid";


    if( $cmd eq 'getGroupInfo' ) {
        return "usage: getGroupInfo" if( @args != 0 );

        $heosCmd    = $cmd;

    } elsif( $cmd eq 'mute' ) {
        return "usage: mute on/off" if( @args != 1 );
        
        $heosCmd    = 'setGroupMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: volume 0-100" if( @args != 1 );
        
        $heosCmd    = 'setGroupVolume';
        $action     = "level=$args[0]";
        
    } elsif( $cmd eq 'volumeUp' ) {
        return "usage: volumeUp 0-10" if( @args != 1 );
        
        $heosCmd    = 'GroupVolumeUp';
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'volumeDown' ) {
        return "usage: volumeDown 0-10" if( @args != 1 );
        
        $heosCmd    = 'groupVolumeDown';
        $action     = "step=$args[0]";

    } elsif( $cmd eq 'clearGroup' ) {
        return "usage: clearGroup" if( @args != 0 );
        
        $heosCmd    = 'createGroup';
        $string     = "pid=$gid";

    #ab hier Playerbefehle emuliert
    } elsif( $cmd eq 'play' ) {
        return "usage: play" if( @args != 0 );
 
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";

    } elsif( $cmd eq 'stop' ) {
        return "usage: stop" if( @args != 0 );
 
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        $string     = "pid=$gid";
 
    } elsif( $cmd eq 'pause' ) {
        return "usage: pause" if( @args != 0 );

        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        $string     = "pid=$gid";
 
    } elsif( $cmd eq 'next' ) {

        return "usage: next" if( @args != 0 );        
        $heosCmd    = 'playNext';        
        $string     = "pid=$gid";

    } elsif( $cmd eq 'prev' ) {
        return "usage: prev" if( @args != 0 );        
        
        $heosCmd    = 'playPrev';
        $string     = "pid=$gid";
        
    } elsif ( $cmd eq 'channel' ) {

        $favcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );        
        return "usage: channel 1-$favcount" if( @args != 1 );
 
        $heosCmd    = 'playPresetStation';
        $action     = "preset=$args[0]";
        $string     = "pid=$gid";
 
    } elsif( $cmd eq 'channelUp' ) {

        return "usage: channelUp" if( @args != 0 );        
        $favcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
 
        $heosCmd    = 'playPresetStation';
        my $fav = ReadingsVal($name,"channel", 0) + 1;
        $fav = $favcount if ( $fav > $favcount);
        $action     = "preset=".$fav;
        $string     = "pid=$gid";
 
    } elsif( $cmd eq 'channelDown' ) {

        return "usage: channelDown" if( @args != 0 );

        $heosCmd    = 'playPresetStation';
        my $fav = ReadingsVal($name,"channel", 0) - 1;
        $fav = 1 if ($fav <= 0);
        $action     = "preset=".$fav;
        $string     = "pid=$gid";
 
    } elsif ( $cmd eq 'playlist' ) {

        my @cids =  map { $_->{cid} } grep { $_->{name} =~ /$args[0]/i } (@{ $hash->{IODev}{helper}{playlists} });
 
        if ( scalar @args == 1 && scalar @cids == 1 ) {
 
            $heosCmd    = 'playPlaylist';
            $action     = "sid=1025&cid=$cids[0]&aid=4";	
            $string     = "pid=$gid";
 
        } else {
 
            my @playlists = map { $_->{name} } (@{ $hash->{IODev}{helper}{playlists}});				
            return "usage: playlist ".join(",",@playlists); 

        }

    } else {

        my @playlists;
        my  $list = "getGroupInfo:noArg mute:on,off volume:slider,0,5,100 volumeUp:slider,0,1,10 volumeDown:slider,0,1,10 clearGroup:noArg play:noArg stop:noArg pause:noArg next:noArg prev:noArg channelUp:noArg channelDown:noArg ";

        $list .= " channel:slider,1,1,".scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );		

        if ( defined $hash->{IODev}{helper}{playlists} ) {
     
            @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
            $list .= " playlist:".join(",",@playlists) if( scalar @playlists > 0 );
        }
        
        return "Unknown argument $cmd, choose one of $list";
    }


    #senden von Befehlen unterdrücken solange state nicht on ist
    if ( ReadingsVal($name, "state", "off") eq "on" ) {
        $string     .= "&$action" if( defined($action));

        IOWrite($hash,"$heosCmd","$string");
        Log3 $name, 4, "HEOSGroup ($name) - IOWrite: $heosCmd $string IODevHash=$hash->{IODev}";
    }
    
    return undef;
}

sub HEOSGroup_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $gid;
    my $decode_json;
    
    
    $decode_json    = decode_json(encode_utf8($json));

    Log3 $name, 4, "HEOSGroup ($name) - ParseFn wurde aufgerufen";




    if( defined($decode_json->{gid}) ) {
    
        $gid            = $decode_json->{gid};
        my $code        = abs($gid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
    
        #print "code #######################################################################\n".Dumper($code);
    
        if( my $hash    = $modules{HEOSGroup}{defptr}{$code} ) {
        
            my $name    = $hash->{NAME};
            
            #print "hash #######################################################################\n".Dumper($hash);
            
            IOWrite($hash,'getGroupInfo',"gid=$hash->{GID}");
            Log3 $name, 4, "HEOSGroup ($name) - find logical device: $hash->{NAME}";
            Log3 $name, 4, "HEOSGroup ($name) - find GID in root from decode_json";
            
            return $hash->{NAME};
        
        } else {
        
            my $devname = "HEOSGroup".abs($gid);
            return "UNDEFINED $devname HEOSGroup $gid IODev=$name";
        }
        
    } else {
    
        #return Log3 $name, 3, "result not success"
        #unless($decode_json->{heos}{result} eq "success");         # Klappt bei Events nicht!! Lieber Fehlermeldung im Reading

        
        if( defined($decode_json->{payload}{gid}) ) {
            $gid        = $decode_json->{payload}{gid};
            
        } elsif ( $decode_json->{heos}{message} =~ /^gid=/ or $decode_json->{heos}{message} =~ /^pid=/ ) {      # das mit dem PID wird nicht klappen, da solche Telegramme erst gar nicht an das Groupmodul gesendet werden
        
            #pid wird bei leerer gruppe zurück gegeben
            my @gid     = split('&', $decode_json->{heos}{message});
            $gid        = substr($gid[0],4);
            Log3 $name, 4, "HEOSGroup ($name) - gid[0]: $gid[0] and gid: $gid";
        
        }
        
        
        my $code        = abs($gid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
        if( my $hash    = $modules{HEOSGroup}{defptr}{$code} ) {
            my $name    = $hash->{NAME};
            HEOSGroup_WriteReadings($hash,$decode_json);
            Log3 $name, 4, "HEOSGroup ($name) - find logical device: $hash->{NAME}";
        
            return $hash->{NAME};
        
        } else {
        
            my $devname = "HEOSGroup".abs($gid);
            return "UNDEFINED $devname HEOSGroup $gid IODev=$name";
        }
    }
}

sub HEOSGroup_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    my $leaderchannel;
    my $leaderStation;
    my $leaderStatus;
    
    Log3 $name, 3, "HEOSGroup ($name) - processing data to write readings";
    
    
    
    
    ############################
    #### Aufbereiten der Daten soweit nötig (bei Events zum Beispiel)
    
    my $readingsHash    = HEOSGroup_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{message} =~ /^gid=/ );
    
    my $code        = abs($hash->{GID});
    $code           = $hash->{IODev}{NAME} ."-". $code if( defined($hash->{IODev}{NAME}) );
    #print "code #######################################################################\n".Dumper($code);

    if( my $leaderhash    = $modules{HEOSPlayer}{defptr}{$code} ) {
        
        my $leadername    = $leaderhash->{NAME};
        #print "hash #######################################################################\n".Dumper($leaderhash);		
        $leaderchannel = ReadingsVal($leadername, 'channel', '');
        $leaderStation = ReadingsVal($leadername, 'currentStation', '');
        $leaderStatus  = ReadingsVal($leadername, 'playStatus', 'stop');

        Log3 $name, 4, "HEOSGroup ($name) - read readings from $leadername";
    }
    
    
    ############################
    #### schreiben der Readings
    
    readingsBeginUpdate($hash);
    
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
        
        Log3 $name, 4, "HEOSGroup ($name) - response json Hash back from HEOSGroup_PreProcessingReadings";
        
        my $t;
        my $v;
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
            if( defined( $v ) ) {
            
                readingsBulkUpdate( $hash, $t, $v );
            }
        }
    }
    
    
    ### GroupInfos
    readingsBulkUpdate( $hash, 'name', $decode_json->{payload}{name} );
    readingsBulkUpdate( $hash, 'gid', $decode_json->{payload}{gid} );
    
    readingsBulkUpdate( $hash, 'state', 'on' );

    readingsBulkUpdate( $hash, 'channel', $leaderchannel );
    readingsBulkUpdate( $hash, 'currentStation', $leaderStation );
    readingsBulkUpdate( $hash, 'playStatus', $leaderStatus );
    
    #gruppe wurde geleert	
    if ( $decode_json->{heos}{message} =~ /^pid=/ ) {

        readingsBulkUpdate( $hash, 'member', "" );
        readingsBulkUpdate( $hash, 'name', "" );		   
        readingsBulkUpdate( $hash, 'state', "off" );

    } elsif ( ref($decode_json->{payload}{players}) eq "ARRAY" ) {

        my @members;

        foreach my $player (@{ $decode_json->{payload}{players} }) {

            readingsBulkUpdate( $hash, 'leader', $player->{name} ) if ( $player->{role} eq "leader" );
            push( @members, $player->{name}) if ( $player->{role} eq "member" );

        }

        if ( scalar @members > 1 ) {

            readingsBulkUpdate( $hash, 'member', join(",",@members) );		

        } else {

            readingsBulkUpdate( $hash, 'member', $members[0] );

        }

    }

    readingsEndUpdate( $hash, 1 );
    
    Log3 $name, 5, "HEOSGroup ($name) - readings set for $name";
    return undef;
}


###############
### my little Helpers

sub HEOSGroup_PreProcessingReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    my $reading;
    my %buffer;
    
    
    Log3 $name, 4, "HEOSGroup ($name) - preprocessing readings";
    
    if ( $decode_json->{heos}{command} =~ /volume_changed/ or $decode_json->{heos}{command} =~ /set_volume/ or $decode_json->{heos}{command} =~ /get_volume/ ) {
    
        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = substr($value[1],6);
        $buffer{'mute'}     = substr($value[2],5) if( $decode_json->{heos}{command} =~ /volume_changed/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_up/ or $decode_json->{heos}{command} =~ /volume_down/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'volumeUp'}     = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_up/ );
        $buffer{'volumeDown'}   = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_down/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /get_mute/ ) {
        my @value           = split('&', $decode_json->{heos}{message});        
        $buffer{'mute'}     = substr($value[1],6);
        
    } else {
    
        Log3 $name, 3, "HEOSGroup ($name) - no match found";
        return undef;
    }
    
    
    Log3 $name, 4, "HEOSGroup ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSGroup_GetGroupInfo($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSGroup_GetGroupInfo');
    IOWrite($hash,'getGroupInfo',"gid=$hash->{GID}");
    
}

sub HEOSGroup_GetGroupVolume($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSGroup_GetGroupVolume');
    IOWrite($hash,'getGroupVolume',"gid=$hash->{GID}");
    
}

sub HEOSGroup_GetGroupMute($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSGroup_GetGroupMute');
    IOWrite($hash,'getGroupMute',"gid=$hash->{GID}");
    
}









1;
