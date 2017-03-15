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


my $version = "0.1.71";




# Declare functions
sub HEOSGroup_Initialize($);
sub HEOSGroup_Define($$);
sub HEOSGroup_Undef($$);
sub HEOSGroup_Attr(@);
sub HEOSGroup_Notify($$);
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
    $hash->{NotifyFn}       = "HEOSGroup_Notify";
    $hash->{AttrFn}         = "HEOSGroup_Attr";
    $hash->{ParseFn}        = "HEOSGroup_Parse";
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HEOSGroup}{defptr}}) {
    
        my $hash = $modules{HEOSGroup}{defptr}{$d};
        $hash->{VERSION}    = $version;
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
    $hash->{NOTIFYDEV} = "HEOSPlayer".abs($gid);
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
    if( defined($d) && $d->{IODev} == $hash->{IODev} && $d->{NAME} ne $name );

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
    my $name = $hash->{NAME};

    
    RemoveInternalTimer($hash);
    my $code = abs($hash->{GID});
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
            
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSGroup ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
        
            Log3 $name, 3, "HEOSGroup ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSGroup ($name) - delete disabledForIntervals";
        }
    }
}

sub HEOSGroup_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};


    return undef if(IsDisabled($name));

    my $events = deviceEvents($dev,1);

    return if( !$events );
    readingsBeginUpdate($hash);

    my %playerEevents = map { my ( $key, $value ) = split /:\s/; ( $key, $value ) } @$events; 

    foreach my $key ( keys %playerEevents ) {
    
        #### playing Infos
        readingsBulkUpdate( $hash, $key, $playerEevents{$key} ) if( grep { $_ =~ /$key/ } ("channel", "currentAlbum", "currentArtist", "currentImageUrl", "currentMedia", "currentMid", "currentQid", "currentSid", "currentStation", "currentTitle", "error", "playStatus", "repeat", "shuffle" ) );
    }
    
    readingsEndUpdate( $hash, 1 );
}

sub HEOSGroup_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $gid          = $hash->{GID};
    my $action;
    my $heosCmd;
    my $rvalue;
    my $favorit;
    my $favoritcount = 1;
    my $string       = "gid=$gid";

    
    #senden von Befehlen unterdrücken solange state nicht on ist
    return undef unless ( ReadingsVal($name, "state", "off") eq "on" );
    
    if( $cmd eq 'getGroupInfo' ) {
        return "usage: getGroupInfo" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'mute' ) {
        return "usage: mute on/off" if( @args != 1 );
        
        $heosCmd    = 'setGroupMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: volume 0-100" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 100 || $args[0] < 0 );
        
        $heosCmd    = 'setGroupVolume';
        $action     = "level=$args[0]";
        
    } elsif( $cmd eq 'volumeUp' ) {
        return "usage: volumeUp 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 0 );
        
        $heosCmd    = 'GroupVolumeUp';
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'volumeDown' ) {
        return "usage: volumeDown 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 0 );
        
        $heosCmd    = 'groupVolumeDown';
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'clearGroup' ) {
        return "usage: clearGroup" if( @args != 0 );
        
        $heosCmd    = 'createGroup';
        $string     = "pid=$gid";
        
    } elsif( grep { $_ eq $cmd } ("play", "stop", "pause", "next", "prev", "channel", "channelUp", "channelDown", "playlist" ) ) {
        
        #ab hier Playerbefehle emuliert
        $string     = "pid=$gid";
        
        if( $cmd eq 'repeat' ) {
            return "usage: repeat one,all,off" if( @args != 1 );
            
            $heosCmd    = 'setPlayMode';
            $rvalue     = 'on_'.$args[0];
            $rvalue     = 'off' if($rvalue eq 'on_off'); 
            $action     = "repeat=$rvalue&shuffle=".ReadingsVal($name,'shuffle','off');
            
        } elsif( $cmd eq 'shuffle' ) {
            return "usage: shuffle on,off" if( @args != 1 );

            $heosCmd    = 'setPlayMode';
            $rvalue     = 'on_'.ReadingsVal($name,'repeat','off');
            $rvalue     = 'off' if($rvalue eq 'on_off');         
            $action     = "repeat=$rvalue&shuffle=$args[0]";
            
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
        } elsif( $cmd eq 'next' ) {
            return "usage: next" if( @args != 0 );
            
            $heosCmd    = 'playNext';
            
        } elsif( $cmd eq 'prev' ) {
            return "usage: prev" if( @args != 0 );
            
            $heosCmd    = 'playPrev';
            
        } elsif ( $cmd =~ /channel/ ) {

            my $favorit = ReadingsVal($name,"channel", 1);
            
            $favoritcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
            $heosCmd    = 'playPresetStation';
            
            if ( $cmd eq 'channel' ) {
                return "usage: $cmd 1-$favoritcount" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > $favoritcount || $args[0] < 1);

                $action  = "preset=$args[0]";

            } elsif( $cmd eq 'channelUp' ) {
                return "usage: $cmd" if( @args != 0 );

                ++$favorit;
                if ( $favorit > $favoritcount ) {
                    if ( AttrVal($name, 'channelring', 0) == 1 ) {
                    
                        $favorit = 1;
                        
                    } else {
                    
                        $favorit = $favoritcount;
                        
                    }
                }
                
                $action  = "preset=".$favorit;

            } elsif( $cmd eq 'channelDown' ) {
                return "usage: $cmd" if( @args != 0 );

                --$favorit;
                if ( $favorit <= 0 ) {
                    if ( AttrVal($name, 'channelring', 0) == 1 ) {
                    
                        $favorit = $favoritcount;
                        
                    } else {
                    
                        $favorit = 1;
                    }
                }
                
                $action  = "preset=".$favorit;
            }
            
        } elsif ( $cmd =~ /Playlist/ ) {
        
            my @cids =  map { $_->{cid} } grep { $_->{name} =~ /\Q$args[0]\E/i } (@{ $hash->{IODev}{helper}{playlists} });

            if ( scalar @args == 1 && scalar @cids > 0 ) {
                if ( $cmd eq 'playPlaylist' ) {

                    $heosCmd    = $cmd;
                    $action     = "sid=1025&cid=$cids[0]&aid=4";
                    
                } elsif ( $cmd eq 'deletePlaylist' ) {
                
                    $heosCmd    = $cmd;
                    $action     = "cid=$cids[0]";
                    $string     = "sid=1025";
                }
            } else {
            
                IOWrite($hash,'browseSource','sid=1025');
                my @playlists = map { $_->{name} } (@{ $hash->{IODev}{helper}{playlists}});
                return "usage: $cmd ".join(",",@playlists);
            }
        }
    } else {
    
        my  $list = "getGroupInfo:noArg mute:on,off volume:slider,0,5,100 volumeUp:slider,0,1,10 volumeDown:slider,0,1,10 clearGroup:noArg repeat:one,all,off shuffle:on,off play:noArg stop:noArg pause:noArg next:noArg prev:noArg channelUp:noArg channelDown:noArg ";

        $list .= " channel:slider,1,1,".scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
    
        if ( defined $hash->{IODev}{helper}{playlists} ) {
        
            my @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
            $list .= " playlist:".join(",",@playlists) if( scalar @playlists > 0 );
        }
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    $string     .= "&$action" if( defined($action));
    IOWrite($hash,"$heosCmd","$string");
    Log3 $name, 4, "HEOSGroup ($name) - IOWrite: $heosCmd $string IODevHash=$hash->{IODev}";
    return undef;
}

sub HEOSGroup_Parse($$) {
    
    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $gid;
    my $decode_json;
    my $code;

    
    $decode_json    = decode_json(encode_utf8($json));
    Log3 $name, 4, "HEOSGroup ($name) - ParseFn wurde aufgerufen";

    if( defined($decode_json->{gid}) ) {
    
        $gid            = $decode_json->{gid};
        $code           = abs($gid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
        
        
        if( my $hash    = $modules{HEOSGroup}{defptr}{$code} ) {
        
            IOWrite($hash,'getGroupInfo',"gid=$hash->{GID}");
            Log3 $hash->{NAME}, 4, "HEOSGroup ($hash->{NAME}) - find logical device: $hash->{NAME}";
            Log3 $hash->{NAME}, 4, "HEOSGroup ($hash->{NAME}) - find GID in root from decode_json";
            return $hash->{NAME};
            
        } else {
            
            my $devname = "HEOSGroup".abs($gid);
            return "UNDEFINED $devname HEOSGroup $gid IODev=$name";
        }
        
    } else {
    
        my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});
        
        $gid = $message{pid} if( defined($message{pid}) );
        $gid = $message{gid} if( defined($message{gid}) );
        $gid = $decode_json->{payload}{gid} if( defined($decode_json->{payload}{gid}) );

        Log3 $name, 4, "HEOSGroup ($name) - GID: $gid";
        
        $code           = abs($gid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
        
        if( my $hash    = $modules{HEOSGroup}{defptr}{$code} ) {          
        
            HEOSGroup_WriteReadings($hash,$decode_json);
            Log3 $hash->{NAME}, 4, "HEOSGroup ($hash->{NAME}) - find logical device: $hash->{NAME}";
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

    
    Log3 $name, 4, "HEOSGroup ($name) - processing data to write readings";
    ############################
    #### Aufbereiten der Daten soweit nötig (bei Events zum Beispiel)
    my $readingsHash    = HEOSGroup_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{message} =~ /^gid=/ );

    ############################
    #### schreiben der Readings
    readingsBeginUpdate($hash);
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
    
        Log3 $name, 4, "HEOSGroup ($name) - response json Hash back from HEOSGroup_PreProcessingReadings";
        my $t;
        my $v;
    
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
        
            readingsBulkUpdate( $hash, $t, $v ) if( defined( $v ) );                           
        }
    }
    
    readingsBulkUpdate( $hash, 'state', 'on' );
    ### GroupInfos
    readingsBulkUpdate( $hash, 'name', $decode_json->{payload}{name} );
    readingsBulkUpdate( $hash, 'gid', $decode_json->{payload}{gid} );
    
    if ( ref($decode_json->{payload}{players}) eq "ARRAY" ) {
    
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
    
    my ($hash,$decode_json)   = @_;
    my $name                  = $hash->{NAME};
    my $reading;
    my %buffer;
    my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});


    Log3 $name, 4, "HEOSGroup ($name) - preprocessing readings";
    if ( $decode_json->{heos}{command} =~ /volume_changed/ or $decode_json->{heos}{command} =~ /set_volume/ or $decode_json->{heos}{command} =~ /get_volume/ ) {
    
        my @value             = split('&', $decode_json->{heos}{message});

        $buffer{'volume'}     = substr($value[1],6);
        $buffer{'mute'}       = substr($value[2],5) if( $decode_json->{heos}{command} =~ /volume_changed/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_up/ or $decode_json->{heos}{command} =~ /volume_down/ ) {
    
        my @value             = split('&', $decode_json->{heos}{message});

        $buffer{'volumeUp'}   = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_up/ );
        $buffer{'volumeDown'} = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_down/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /get_mute/ ) {
    
        my @value             = split('&', $decode_json->{heos}{message});
        
        $buffer{'mute'}       = substr($value[1],6);
        
    } else {
    
        Log3 $name, 4, "HEOSGroup ($name) - no match found";
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
