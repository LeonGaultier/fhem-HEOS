###############################################################################
# 
# Developed with Kate
#
#  (c) 2016-2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
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
use JSON;


my $version = "0.1.35";




# Declare functions
sub HEOSPlayer_Initialize($);
sub HEOSPlayer_Define($$);
sub HEOSPlayer_Undef($$);
sub HEOSPlayer_Attr(@);
sub HEOSPlayer_Parse($$);
sub HEOSPlayer_WriteReadings($$);
sub HEOSPlayer_Set($$@);
sub HEOSPlayer_PreProcessingReadings($$);
sub HEOSPlayer_GetPlayerInfo($);
sub HEOSPlayer_GetPlayState($);
sub HEOSPlayer_GetNowPlayingMedia($);





sub HEOSPlayer_Initialize($) {

    my ($hash) = @_;

    $hash->{Match}          = '.*{"command":."player.*|.*{"command":."event/player.*';
    
    # Provider
    $hash->{SetFn}          = "HEOSPlayer_Set";
    $hash->{DefFn}          = "HEOSPlayer_Define";
    $hash->{UndefFn}        = "HEOSPlayer_Undef";
    $hash->{AttrFn}         = "HEOSPlayer_Attr";
    $hash->{ParseFn}        = "HEOSPlayer_Parse";
    
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              $readingFnAttributes;



    foreach my $d(sort keys %{$modules{HEOSPlayer}{defptr}}) {
        my $hash = $modules{HEOSPlayer}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub HEOSPlayer_Define($$) {

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

    return "too few parameters: define <name> HEOSPlayer <pid>" if( @a < 2 );

    my ($name,$pid)     = @a;

    $hash->{PID}        = $pid;
    $hash->{VERSION}    = $version;
    $hash->{STATE}      = 'Initialized';
    
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "HEOSPlayer ($name) - I/O device is " . $hash->{IODev}->{NAME};
    } else {
    
        Log3 $name, 1, "HEOSPlayer ($name) - no I/O device";
    }
    
    $iodev = $hash->{IODev}->{NAME};

    
    my $code = abs($pid);
    $code = $iodev."-".$code if( defined($iodev) );
    my $d = $modules{HEOSPlayer}{defptr}{$code};
    return "HEOSPlayer device $hash->{pid} on HEOSMaster $iodev already defined as $d->{NAME}."
        if( defined($d)
            && $d->{IODev} == $hash->{IODev}
            && $d->{NAME} ne $name );

    $modules{HEOSPlayer}{defptr}{$code} = $hash;
  
  
    Log3 $name, 3, "HEOSPlayer ($name) - defined with Code: $code";

    $attr{$name}{room} = "HEOS" if( !defined( $attr{$name}{room} ) );
    
    
    if( $init_done ) {
        InternalTimer( gettimeofday()+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
   } else {
        InternalTimer( gettimeofday()+15+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
    }

    return undef;
}

sub HEOSPlayer_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $pid = $hash->{PID};
    my $name = $hash->{NAME};

    
    RemoveInternalTimer($hash);

    my $code = abs($pid);
    $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
    delete($modules{HEOSPlayer}{defptr}{$code});
    
    Log3 $name, 3, "HEOSPlayer ($name) - device $name deleted with Code: $code";

    return undef;
}

sub HEOSPlayer_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "HEOSPlayer ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - delete disabledForIntervals";
        }
    }
}

sub HEOSPlayer_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    
    my $pid     = $hash->{PID};
    my $action;
    my $heosCmd;
    my $string  = "pid=$pid";


    if( $cmd eq 'getPlayerInfo' ) {
        return "usage: getPlayerInfo" if( @args != 0 );

        $heosCmd    = 'getPlayerInfo';
        
    } elsif( $cmd eq 'getPlayState' ) {
        return "usage: getPlayState" if( @args != 0 );
        
        $heosCmd    = 'getPlayState';
        
    } elsif( $cmd eq 'getNowPlayingMedia' ) {
        return "usage: getNowPlayingMedia" if( @args != 0 );
        
        $heosCmd    = 'getNowPlayingMedia';
        
    } elsif( $cmd eq 'play' ) {
        return "usage: play" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'stop' ) {
        return "usage: stop" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'pause' ) {
        return "usage: pause" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'mute' ) {
        return "usage: mute on/off" if( @args != 1 );
        
        $heosCmd    = 'setMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: volume 0-100" if( @args != 1 );
        
        $heosCmd    = 'setVolume';
        $action     = "level=$args[0]";

    } else {
        my  $list = "getPlayerInfo:noArg getPlayState:noArg getNowPlayingMedia:noArg play:noArg stop:noArg pause:noArg mute:on,off volume:slider,0,5,100";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    
    $string     .= "&$action" if( defined($action));
    
    IOWrite($hash,"$heosCmd","$string");
    Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd${string} IODevHash=$hash->{IODev}";
    
    return undef;
}

sub HEOSPlayer_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $pid;
    my $decode_json;
    
    
    $decode_json    = decode_json($json);

    Log3 $name, 4, "HEOSPlayer ($name) - ParseFn wurde aufgerufen";




    if( defined($decode_json->{pid}) ) {
    
        $pid            = $decode_json->{pid};
        my $code        = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {
            my $name    = $hash->{NAME};
            HEOSPlayer_GetUpdate($hash);
            Log3 $name, 4, "HEOSPlayer ($name) - find logical device: $hash->{NAME}";
        
            return $hash->{NAME};
        
        } else {
        
            my $devname = "HEOSPlayer".abs($pid);
            return "UNDEFINED $devname HEOSPlayer $pid IODev=$name";
        }
        
    } else {
    
        #return Log3 $name, 3, "result not success"
        #unless($decode_json->{heos}{result} eq "success");         # Klappt bei Events nicht!! Lieber Fehlermeldung im Reading

        
        if( defined($decode_json->{payload}{pid}) ) {
            $pid        = $decode_json->{payload}{pid};
            
        } elsif ( $decode_json->{heos}{message} =~ /^pid=/ ) {
            my @pid     = split('&', $decode_json->{heos}{message});
            $pid        = substr($pid[0],4);
            Log3 $name, 4, "HEOSPlayer ($name) - PID[0]: $pid[0] and PID: $pid";
        
        }
        
        
        my $code        = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {
            my $name    = $hash->{NAME};
            HEOSPlayer_WriteReadings($hash,$decode_json);
            Log3 $name, 4, "HEOSPlayer ($name) - find logical device: $hash->{NAME}";
        
            return $hash->{NAME};
        
        } else {
        
            my $devname = "HEOSPlayer".abs($pid);
            return "UNDEFINED $devname HEOSPlayer $pid IODev=$name";
        }
    }
}

sub HEOSPlayer_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    
    Log3 $name, 3, "HEOSPlayer ($name) - processing data to write readings";
    
    
    
    
    ############################
    #### Aufbereiten der Daten soweit nötig (bei Events zum Beispiel)
    
    my $readingsHash    = HEOSPlayer_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{message} =~ /^pid=/ );
    
    
    ############################
    #### schreiben der Readings
    
    readingsBeginUpdate($hash);
    
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
        
        Log3 $name, 4, "HEOSPlayer ($name) - response json Hash back from HEOSPlayer_PreProcessingReadings";
        
        my $t;
        my $v;
        while( ( $t, $v ) = each $readingsHash ) {
            if( defined( $v ) ) {
            
                readingsBulkUpdate( $hash, $t, $v );
            }
        }
    }
    
    
    ### PlayerInfos
    readingsBulkUpdate( $hash, 'name', $decode_json->{payload}{name} );
    readingsBulkUpdate( $hash, 'gid', $decode_json->{payload}{gid} );
    readingsBulkUpdate( $hash, 'model', $decode_json->{payload}{model} );
    readingsBulkUpdate( $hash, 'version', $decode_json->{payload}{version} );
    readingsBulkUpdate( $hash, 'network', $decode_json->{payload}{network} );
    readingsBulkUpdate( $hash, 'lineout', $decode_json->{payload}{lineout} );
    readingsBulkUpdate( $hash, 'control', $decode_json->{payload}{control} );
    readingsBulkUpdate( $hash, 'ip-address', $decode_json->{payload}{ip} );
    
    ### playing Infos
    readingsBulkUpdate( $hash, 'currentMedia', $decode_json->{payload}{type} );
    readingsBulkUpdate( $hash, 'currentTitle', $decode_json->{payload}{song} );
    readingsBulkUpdate( $hash, 'currentAlbum', $decode_json->{payload}{album} );
    readingsBulkUpdate( $hash, 'currentArtist', $decode_json->{payload}{artist} );
    readingsBulkUpdate( $hash, 'currentImageUrl', $decode_json->{payload}{image_url} );
    readingsBulkUpdate( $hash, 'currentMid', $decode_json->{payload}{mid} );
    readingsBulkUpdate( $hash, 'currentQid', $decode_json->{payload}{qid} );
    readingsBulkUpdate( $hash, 'currentSid', $decode_json->{payload}{sid} );
    readingsBulkUpdate( $hash, 'currentStation', $decode_json->{payload}{station} );
    
    
    readingsBulkUpdate( $hash, 'state', 'on' );
    readingsEndUpdate( $hash, 1 );
    
    Log3 $name, 5, "HEOSPlayer ($name) - readings set for $name";
    return undef;
}


###############
### my little Helpers

sub HEOSPlayer_PreProcessingReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    my $reading;
    my $value;
    my %buffer;
    
    
    Log3 $name, 4, "HEOSPlayer ($name) - preprocessing readings";
    
    if ( $decode_json->{heos}{command} =~ /play_state/ or $decode_json->{heos}{command} =~ /player_state_changed/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'playStatus'}   = substr($value[1],6);
        
    } elsif ( $decode_json->{heos}{command} =~ /set_volume/ ) {
    
        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = substr($value[1],6);
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_changed/ ) {
    
        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = substr($value[1],6);
        $buffer{'mute'}     = substr($value[2],5);
        
    } elsif ( $decode_json->{heos}{command} =~ /player_now_playing_changed/ ) {
        
        IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}");
        
    } else {
    
        Log3 $name, 3, "HEOSPlayer ($name) - no match found";
    }
    
    
    Log3 $name, 4, "HEOSPlayer ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSPlayer_GetPlayerInfo($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayerInfo');
    IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}");
    
}

sub HEOSPlayer_GetPlayState($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayState');
    IOWrite($hash,'getPlayState',"pid=$hash->{PID}");
    
}

sub HEOSPlayer_GetNowPlayingMedia($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetNowPlayingMedia');
    IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}");
    
}









1;
