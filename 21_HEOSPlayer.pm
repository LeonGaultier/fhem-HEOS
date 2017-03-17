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
use URI::Escape;
use Data::Dumper;

my $version = "0.1.72";




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
sub HEOSPlayer_GetQueue($);
sub HEOSPlayer_GetNowPlayingMedia($);
sub HEOSPlayer_GetPlayMode($);
sub HEOSPlayer_GetVolume($);
sub HEOSPlayer_Get($$@);
sub HEOSPlayer_GetMute($);




sub HEOSPlayer_Initialize($) {
    
    my ($hash) = @_;

    $hash->{Match}          = '.*{"command":."player.*|.*{"command":."event/player.*|.*{"command":."event\/repeat_mode_changed.*|.*{"command":."event\/shuffle_mode_changed.*|.*{"command":."event\/favorites_changed.*';

    
    # Provider
    $hash->{SetFn}          = "HEOSPlayer_Set";
    $hash->{GetFn}          = "HEOSPlayer_Get";
    $hash->{DefFn}          = "HEOSPlayer_Define";
    $hash->{UndefFn}        = "HEOSPlayer_Undef";
    $hash->{AttrFn}         = "HEOSPlayer_Attr";
    $hash->{ParseFn}        = "HEOSPlayer_Parse";
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              "mute2play:1 ".
                              "channelring:1 ".
                              $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HEOSPlayer}{defptr}}) {
    
        my $hash = $modules{HEOSPlayer}{defptr}{$d};
        $hash->{VERSION}    = $version;
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
    if( defined($d) && $d->{IODev} == $hash->{IODev} && $d->{NAME} ne $name );

    Log3 $name, 3, "HEOSPlayer ($name) - defined with Code: $code";
    $attr{$name}{room}          = "HEOS" if( !defined( $attr{$name}{room} ) );
    $attr{$name}{devStateIcon}  = "on:10px-kreis-gruen off:10px-kreis-rot" if( !defined( $attr{$name}{devStateIcon} ) );
    
    if( $init_done ) {
    
        InternalTimer( gettimeofday()+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(8)), "HEOSPlayer_GetPlayMode", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(10)), "HEOSPlayer_GetVolume", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(12)), "HEOSPlayer_GetMute", $hash, 0 );
        InternalTimer( gettimeofday()+int(rand(14)), "HEOSPlayer_GetQueue", $hash, 0 );
        
   } else {
   
        InternalTimer( gettimeofday()+15+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(8)), "HEOSPlayer_GetPlayMode", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(10)), "HEOSPlayer_GetVolume", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(12)), "HEOSPlayer_GetMute", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(14)), "HEOSPlayer_GetQueue", $hash, 0 );
    }
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state','Initialized');
    readingsBulkUpdate($hash, 'volumeUp', 5);
    readingsBulkUpdate($hash, 'volumeDown', 5);
    readingsEndUpdate($hash, 1);
    
    $modules{HEOSPlayer}{defptr}{$code} = $hash;
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
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
        
            Log3 $name, 3, "HEOSPlayer ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSPlayer ($name) - delete disabledForIntervals";
        }
    }
}

sub HEOSPlayer_Get($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $pid     = $hash->{PID};
    my $result  = "";
    my $me      = {};
    
    #Leerzeichen müßen für die Rückgabe escaped werden sonst werden sie falsch angezeigt
    if( $cmd eq 'channelscount' ) {
    
        #gibt die Favoritenanzahl zurück
        return scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        
    } elsif( $cmd eq 'ls' ) {

        my $param = shift( @args );
        $param = '' if( !$param );
        #$param = substr($param,1) if( $param && $param =~ '^|' );

        if ( $param eq '' ) {
        
            my $ret = "Musik\n";
            #$ret .= sprintf( "%-35s %-15s %s\n", 'key', 'type', 'title' );

            foreach my $item (@{ $hash->{IODev}{helper}{sources}}) {
            
                #$ret .= '<li style="list-style-type: none; display: inline;"><a style="cursor:pointer" onclick="'.$xcmd.'">'.sprintf( "%-35s %-15s %s", $item->{sid}, $item->{type}, $item->{name} )."</a></li>\n";
                $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, $item->{sid}, $item->{type}, $item->{name});
            }

            $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1025", "heos_service", "Playlist")
            if ( defined $hash->{IODev}{helper}{playlists} );
            #https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_playlists.png

            $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1026", "heos_service", "Verlauf")
            if ( defined $hash->{IODev}{helper}{history} );
            #https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_history.png

            $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1027", "heos_service", "Eingänge")
            if ( defined $hash->{IODev}{helper}{aux} );
            #https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_aux.png

            $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1028", "heos_service", "Favoriten")
            if ( defined $hash->{IODev}{helper}{favorites} );
            #https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_favorites.png

            $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1029", "heos_service", "Warteschlange")
            if ( defined $hash->{helper}{queue} );
            #https://production.ws.skyegloup.com:443/media/images/service/logos/musicsource_logo_playlists.png

            $ret .= "\n\n";
            return $ret;

        } else {

            my ($sid,$cid)=$param=~/^(-?\d+),?(.*)$/;

            $me->{cl}   = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );
            $me->{name} = $hash->{NAME};
            $me->{pid}  = $hash->{PID};

            if ( $sid eq "1025" ) {
            
                $me->{sourcename} = "Playlist";
                
            } elsif ( $sid eq "1026" ) {
            
                $me->{sourcename} = "Verlauf";
                
            } elsif ( $sid eq "1027" ) {
            
                $me->{sourcename} = "Eingänge";
                
            } elsif ( $sid eq "1028" ) {
            
                $me->{sourcename} = "Favoriten";
                
            } elsif ( $sid eq "1029" ) {
            
                $me->{sourcename} = "Warteschlange";
                
            } else {
            
                my @sids =  map { $_->{name} } grep { $_->{sid} =~ /$sid/i } (@{ $hash->{IODev}{helper}{sources} });
                $me->{sourcename} = $sids[0] if ( scalar @sids > 0);
            }

            my $heosCmd = "browseSource";
            my $action;

            if ( defined $sid && defined $cid && $cid ne "" ) {
                if ( $sid eq "1027" ) {
                
                    $action = "sid=$cid";

                } elsif ( $sid eq "1026" ) {
                
                    $me->{sourcename} .= "/$cid";
                    $action = "sid=$sid&cid=$cid";
                    
                } else {
                
                    my @cids =  map { $_->{name} } grep { $_->{cid} =~ /\Q$cid\E/i } (@{ $hash->{IODev}{helper}{media} });
                    $me->{sourcename} .= "/".$cids[0] if ( scalar @cids > 0);
                    $action = "sid=$sid&cid=$cid";
                    
                }
                
            } elsif ( defined $sid && $sid eq "1029" ) {
            
                my $ret = "$hash->{NAME}/Warteschlange\n";
                $ret .= sprintf( "%-35s %-15s %s\n", 'key', 'type', 'title' );

                my $x = 0;
                foreach my $item (@{ $hash->{helper}{queue}}) {
                
                    $ret .= HEOSPlayer_MakePlayLink($hash->{NAME}, "1029,".++$x, "heos_queue", $item->{song} );
                }
                
                $ret .= "\n\n";

                if( $me->{cl}->{TYPE} eq 'FHEMWEB' ) {

                    $ret =~ s/&/&amp;/g;
                    $ret =~ s/'/&apos;/g;
                    $ret =~ s/\n/<br>/g;
                    $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
                    $ret = "<html>$ret</html>";

                } else {

                    $ret =~ s/<a[^>]*>//g;
                    $ret =~ s/<\/a>//g;
                    $ret =~ s/<img[^>]*>\n//g;
                    $ret .= "\n";
                }
                
                asyncOutput( $me->{cl}, $ret );
                #delete $me;
                return undef;
                
            } else {
            
                $action = "sid=$sid";
            }

            IOWrite($hash,$heosCmd,$action,$me);
            Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd $action IODevHash=$hash->{IODev}";
            
            return undef;
        }
    }

    my $list = 'channelscount:noArg ls';

    return "Unknown argument $cmd, choose one of $list";
}

sub HEOSPlayer_Set($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $pid     = $hash->{PID};
    my $action;
    my $heosCmd;
    my $rvalue;
    my $favoritcount = 1;
    my $qcount = 1;
    my $string = "pid=$pid";

    return undef unless ( ReadingsVal($name, "state", "off") eq "on" );

    if( $cmd eq 'getPlayerInfo' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayState' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayMode' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getNowPlayingMedia' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'repeat' ) {
        my $param = "one|all|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setPlayMode';
        $rvalue     = 'on_'.$args[0];
        $rvalue     = 'off' if($rvalue eq 'on_off'); 
        $action     = "repeat=$rvalue&shuffle=".ReadingsVal($name,'shuffle','off');
        
    } elsif( $cmd eq 'shuffle' ) {
        my $param = "on|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setPlayMode';
        $rvalue     = 'on_'.ReadingsVal($name,'repeat','off');
        $rvalue     = 'off' if($rvalue eq 'on_off');         
        $action     = "repeat=$rvalue&shuffle=$args[0]";
        
    } elsif( $cmd eq 'play' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'stop' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'pause' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'setPlayState';
        $action     = "state=$cmd";
        
    } elsif( $cmd eq 'mute' ) {
        my $param = "on|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = 'setMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: $cmd 0-100" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 100 || $args[0] < 0);
        
        $heosCmd    = 'setVolume';
        $action     = "level=$args[0]";
        
    } elsif( $cmd eq 'volumeUp' ) {
        return "usage: $cmd 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 1);
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'volumeDown' ) {
        return "usage: $cmd 0-10" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > 10 || $args[0] < 1);
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'groupWithMember' ) {
        return "usage: $cmd" if( @args != 1 );
        
        foreach ( split('\,', $args[0]) ) {
        
            $string    .= ",$defs{$_}->{PID}" if ( defined $defs{$_} );
            printf "String: $string\n";
        }
        
        $heosCmd    = 'createGroup';
        
    } elsif( $cmd eq 'groupClear' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'createGroup';
        
    } elsif( $cmd eq 'next' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'playNext';
        
    } elsif( $cmd eq 'prev' ) {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'playPrev';
        
    } elsif ( $cmd =~ /channel/ ) {
    
        my $favorit = ReadingsVal($name,"channel", 1);
        
        $favoritcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        $heosCmd    = 'playPresetStation';
        
        if ( $cmd eq 'channel' ) {
            return "usage: channel 1-$favoritcount" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > $favoritcount || $args[0] < 1);
            
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
        
    } elsif ( $cmd =~ /Queue/ ) {

        $heosCmd    = $cmd;
        if ( $cmd eq 'playQueueItem' ) {
                
            $qcount = scalar(@{$hash->{helper}{queue}}) if ( defined $hash->{helper}{queue} );
            return "usage: queue 1-$qcount" if( @args != 1 || $args[0] !~ /(\d+)/ || $args[0] > $qcount || $args[0] < 1);

            $action     = "qid=$args[0]";
          
        } elsif ( $cmd eq 'clearQueue' ) {
            #löscht die Warteschlange
            return "usage: $cmd" if( @args != 0 );
        
            delete $hash->{helper}{queue};
        
        } elsif ( $cmd eq 'saveQueue' ) {
        
            #speichert die aktuelle Warteschlange als Playlist ab
            return "usage: saveQueue" if( @args != 1 );
        
            $action     = "name=$args[0]";
        }

    } elsif ( $cmd =~ /Playlist/ ) {
    
        my $mid;
        my $cid = $args[0];
        my @path = split(",", $args[0]) if ( @args != 0 && $args[0] =~ /,/ );     
        $cid = $path[0] if ( scalar @path > 0); 
        $mid = $path[1] if ( scalar @path > 1); 

        if ( scalar @args != 0 ) {

            if ( $cid !~ /^-*[0-9]+$/ ) {
            
                my @cids =  map { $_->{cid} } grep { $_->{name} =~ /\Q$cid\E/i } (@{ $hash->{IODev}{helper}{playlists} });
                return "usage: $cmd name" if ( scalar @cids <= 0);
                
                $cid = $cids[0];
            }

            if ( $cmd eq 'playPlaylist' ) {

                $heosCmd    = $cmd;
                $action     = "sid=1025&cid=$cid&aid=4";
            
            } elsif ( $cmd eq 'playPlaylistItem' ) {
                return "usage: playPlaylistItem name,nr" if ( scalar @path < 2);

                $heosCmd    = 'playPlaylist';
                $action     = "sid=1025&cid=$cid&mid=$mid&aid=4";

            } elsif ( $cmd eq 'deletePlaylist' ) {
            
                $heosCmd    = $cmd;
                $action     = "cid=$cid";
                $string     = "sid=1025";
            }
            
        } else {
                    
            my @playlists = map { $_->{name} } (@{ $hash->{IODev}{helper}{playlists}});
            return "usage: $cmd name|id".join(",",@playlists);
        }
        
    } elsif( $cmd eq 'aux' ) {
        return "usage: $cmd" if( @args != 0 );

        my $auxname = @{ $hash->{helper}{aux} }[0]->{mid};
        $heosCmd = 'playInput';
        $action  = "input=$auxname";
    
        Log3 $name, 4, "HEOSPlayer ($name) - set aux to $auxname";
        readingsSingleUpdate($hash, "input", $args[0], 1);
        
    } elsif( $cmd eq 'input' ) {
        return "usage: $cmd sid[,cid][,mid]" if( @args != 1 );

        my $param = shift( @args );
        my ($sid,$cid,$mid)=$param=~/^(-?\d+),(.+?)(?:,(.*))?/;

        return "usage: $cmd sid[,cid][,mid]" unless( defined $sid || $sid eq "" );

        if ( $sid eq "1024" ) {
            return "usage: $cmd sid,cid[,mid]" unless( defined($cid) && defined($mid) );
            
            #Server abspielen
            $heosCmd = 'playPlaylist';
            $action  = "sid=$sid&cid=$cid&aid=4";
            $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

        } elsif ( $sid eq "1025" ) {
            return "usage: $cmd sid,cid[,mid]" unless( defined($cid) );

            #Playlist abspielen
            $heosCmd = 'playPlaylist';
            $action  = "sid=$sid&cid=$cid&aid=4";
            $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

        } elsif ( $sid eq "1026" ) {
            return "usage: $cmd sid,cid,mid" unless( defined($cid) );

            #Verlauf abspielen
            if ( $cid eq "TRACKS" ) {

                $heosCmd = 'playPlaylist';
                $action  = "sid=$sid&cid=$cid&aid=4";
                $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

            } elsif ( $cid eq "STATIONS" ) {

                $heosCmd = 'playStream';
                $action  = "sid=$sid&cid=$cid&mid=$mid";
            }

        } elsif ( $sid eq "1027" ) {
            return "usage: $cmd sid,spid,mid" unless( defined($cid) );

            #Eingang abspielen
            $heosCmd = 'playInput';
            $action  = "input=$mid";
            $action  = "spid=$cid&".$action if ( $pid ne $cid );

        } elsif ( $sid eq "1028" ) {
            return "usage: $cmd sid,nr" unless( defined($cid) );

            #Favoriten abspielen
            $heosCmd = 'playPresetStation';
            $action  = "preset=$cid";

        } elsif ( $sid eq "1029" ) {
            return "usage: $cmd sid,qid" unless( defined($cid) );

            #Warteschlange abspielen
            $heosCmd = 'playQueue';
            $action  = "qid=$cid";

        } else {
            if ( $sid > 0 && $sid < 1024 ) {
                return "usage: $cmd sid,cid,mid" unless( defined($cid) && defined($mid) );

                #Radio abspielen
                $heosCmd = 'playStream';
                $action = "sid=$sid&cid=$cid&mid=$mid";

            } else {
                return "usage: $cmd sid,cid[,mid]" unless( defined($cid) );
                
                #Server abspielen
                $heosCmd = 'playPlaylist';
                $action  = "sid=$sid&cid=$cid&aid=4";
                $action  = "sid=$sid&cid=$cid&mid=$mid&aid=4" if ( defined($mid) );

            }
        }
        
    } else {
                                              
        my  $list = "getPlayerInfo:noArg getPlayState:noArg getNowPlayingMedia:noArg getPlayMode:noArg play:noArg stop:noArg pause:noArg mute:on,off volume:slider,0,5,100 volumeUp:slider,0,1,10 volumeDown:slider,0,1,10 repeat:one,all,off shuffle:on,off next:noArg prev:noArg  input";

        my @players = devspec2array("TYPE=HEOSPlayer:FILTER=NAME!=$name");
        $list .= " groupWithMember:multiple-strict," . join( ",", @players ) if ( scalar @players > 0 );
        $list .= " groupClear:noArg" if ( defined($defs{"HEOSGroup".abs($pid)}) && $defs{"HEOSGroup".abs($pid)}->{STATE} eq "on" );

        #Parameterlisten für FHEMWeb zusammen bauen
        my $favoritcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        if ( defined $favoritcount && $favoritcount > 0) {

            $list .= " channel:slider,1,1,".scalar(@{$hash->{IODev}{helper}{favorites}});
            $list .= " channelUp:noArg channelDown:noArg" if ( $favoritcount > 1)
        }

        if ( defined($hash->{helper}{queue}) && ref($hash->{helper}{queue}) eq "ARRAY" && scalar(@{$hash->{helper}{queue}}) > 0 ) {
        
            $list .= " playQueueItem:slider,1,1,".scalar(@{$hash->{helper}{queue}}) if ( defined $hash->{helper}{queue} );
            $list .= " clearQueue:noArg saveQueue";            
        }

        if ( defined $hash->{IODev}{helper}{playlists} ) {
        
            my @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
            
            $list .= " playPlaylist:".join(",",@playlists) if( scalar @playlists > 0 );
            $list .= " deletePlaylist:".join(",",@playlists) if( scalar @playlists > 0 );
        }

        $list .= " aux:noArg" if ( exists $hash->{helper}{aux} );
        return "Unknown argument $cmd, choose one of $list";
    }

    $string     .= "&$action" if( defined($action));
    IOWrite($hash,"$heosCmd","$string",undef);
    Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd $string IODevHash=$hash->{IODev}";
    return undef;
}

sub HEOSPlayer_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $pid;
    my $decode_json;
    my $code;

    
    $decode_json    = decode_json(encode_utf8($json));
    Log3 $name, 4, "HEOSPlayer - ParseFn wurde aufgerufen";
    if( defined($decode_json->{pid}) ) {
    
        $pid            = $decode_json->{pid};
        $code           = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {
        
            IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}",undef);
            Log3 $hash->{NAME}, 4, "HEOSPlayer ($hash->{NAME}) - find logical device: $hash->{NAME}";
            Log3 $hash->{NAME}, 4, "HEOSPlayer ($hash->{NAME}) - find PID in root from decode_json";
            return $hash->{NAME};
            
        } else {
        
            my $devname = "HEOSPlayer".abs($pid);
            return "UNDEFINED $devname HEOSPlayer $pid IODev=$name";
        }
        
    } else {
    
        my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});

        $pid = $message{pid} if( defined($message{pid}) );
        $pid = $decode_json->{payload}{pid} if( ref($decode_json->{payload}) ne "ARRAY" && defined($decode_json->{payload}{pid}) );
         
        Log3 $name, 4, "HEOSPlayer ($name) PID: $pid";
        
        $code           = abs($pid);
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

    
    Log3 $name, 4, "HEOSPlayer ($name) - processing data to write readings";
    ############################
    #### Aufbereiten der Daten soweit nötig (bei Events zum Beispiel)
    my $readingsHash    = HEOSPlayer_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{message} =~ /^pid=/ and $decode_json->{heos}{command} ne "player\/get_now_playing_media");

    ############################
    #### schreiben der Readings
    readingsBeginUpdate($hash);
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
    
        Log3 $name, 4, "HEOSPlayer ($name) - response json Hash back from HEOSPlayer_PreProcessingReadings";
        my $t;
        my $v;
    
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
            readingsBulkUpdate( $hash, $t, $v ) if( defined( $v ) );
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

    #sucht in den Favoriten nach der aktuell gespielten Radiostation und aktualisiert den channel wenn diese enthalten ist
    my @presets = map { $_->{name} } (@{ $hash->{IODev}{helper}{favorites} });
    my $search = ReadingsVal($name,"currentStation" ,undef);
    my( @index )= grep { $presets[$_] eq $search } 0..$#presets if ( defined $search );
    
    readingsBulkUpdate( $hash, 'channel', $index[0]+1 ) if ( scalar @index > 0 );
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
    my %buffer;
    my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});
    
    
    Log3 $name, 4, "HEOSPlayer ($name) - preprocessing readings";
    
    if ( $decode_json->{heos}{command} =~ /play_state/ or $decode_json->{heos}{command} =~ /player_state_changed/ ) {
    
        $buffer{'playStatus'}   = $message{state};
    
    } elsif ( $decode_json->{heos}{command} =~ /volume_changed/ or $decode_json->{heos}{command} =~ /set_volume/ or $decode_json->{heos}{command} =~ /get_volume/ ) {

        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = $message{level};
        $buffer{'mute'}     = $message{mute} if( $decode_json->{heos}{command} =~ /volume_changed/ );
        if (defined($buffer{'mute'}) && AttrVal($name, 'mute2play', 0) == 1) {
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=play",undef) if $buffer{'mute'} eq "off";
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=stop",undef) if $buffer{'mute'} eq "on";
        }
        
    } elsif ( $decode_json->{heos}{command} =~ /play_mode/ or $decode_json->{heos}{command} =~ /repeat_mode_changed/ or $decode_json->{heos}{command} =~ /shuffle_mode_changed/ ) {
    
        $buffer{'shuffle'}  = $message{shuffle};
        $buffer{'repeat'}   = $message{repeat};
        $buffer{'repeat'}   =~ s/.*\_(.*)/$1/g;
        
    } elsif ( $decode_json->{heos}{command} =~ /get_mute/ ) {
    
        $buffer{'mute'}     = $message{state};
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_up/ or $decode_json->{heos}{command} =~ /volume_down/ ) {
    
        $buffer{'volumeUp'}     = $message{step} if( $decode_json->{heos}{command} =~ /volume_up/ );
        $buffer{'volumeDown'}   = $message{step} if( $decode_json->{heos}{command} =~ /volume_down/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /player_now_playing_changed/ or $decode_json->{heos}{command} =~ /favorites_changed/ ) {
        IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}",undef);
        
    } elsif ( $decode_json->{heos}{command} =~ /play_preset/ ) {
    
        $buffer{'channel'}      = $message{preset}
        
    } elsif ( $decode_json->{heos}{command} =~ /play_input/ ) {
    
        $buffer{'input'}        = $message{input};

    } elsif ( $decode_json->{heos}{command} =~ /playback_error/ ) {
    
        $buffer{'error'}        = $message{error};
        
    } else {
    
        Log3 $name, 4, "HEOSPlayer ($name) - no match found";
        return undef;
    }
    
    Log3 $name, 4, "HEOSPlayer ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSPlayer_GetPlayerInfo($) {

    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayerInfo');
    IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetPlayState($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayState');
    IOWrite($hash,'getPlayState',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetPlayMode($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayMode');
    IOWrite($hash,'getPlayMode',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetNowPlayingMedia($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetNowPlayingMedia');
    IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetVolume($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetVolume');
    IOWrite($hash,'getVolume',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetMute($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetMute');
    IOWrite($hash,'getMute',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_GetQueue($) {
    
    my $hash        = shift;

    
    RemoveInternalTimer($hash,'HEOSPlayer_GetQueue');
    IOWrite($hash,'getQueue',"pid=$hash->{PID}",undef);
}

sub HEOSPlayer_MakePlayLink($$$$) {

    my ($name, $sid, $itemtype, $itemname) = @_;
    my $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$sid);
    my $xtext = $sid;

    $xcmd = 'cmd'.uri_escape('=set '.$name.' input '.$sid) if ( $itemtype eq "heos_queue" );
    $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";
    return '<li style="list-style-type: none; display: inline;"><a style="cursor:pointer" onclick="'.$xcmd.'">'.sprintf( "%-35s %-15s %s", $xtext, $itemtype, $itemname )."</a></li>\n";
}

sub HEOSPlayer_MakePlayLink2($$$$) {

    my ($name, $sid, $itemname, $itemurl, $xsize, $ysize) = @_;
    my $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$sid);
    my $xtext = $sid;

    $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";
    return '<li style="list-style-type: none; display: inline;"><img src="'.$itemurl.'" width="'.$xsize.'" height="'.$ysize.'" style="float:left;"><a style="cursor:pointer" onclick="'.$xcmd.'">'.$itemname."</a></li>\n";
}

sub HEOSPlayer_makeImage($$) {
    my ($url, $xsize, $ysize) = @_;

    my $ret .= "<img src=\"$url\" width=\"$xsize\" height=\"$ysize\" style=\"float:left;\">\n";

    return $ret;
}










1;
