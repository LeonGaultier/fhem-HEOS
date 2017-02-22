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
   } else {
        InternalTimer( gettimeofday()+15+int(rand(2)), "HEOSPlayer_GetPlayerInfo", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(4)), "HEOSPlayer_GetPlayState", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(6)), "HEOSPlayer_GetNowPlayingMedia", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(8)), "HEOSPlayer_GetPlayMode", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(10)), "HEOSPlayer_GetVolume", $hash, 0 );
        InternalTimer( gettimeofday()+15+int(rand(12)), "HEOSPlayer_GetMute", $hash, 0 );
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

sub HEOSPlayer_Get($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    
    my $pid     = $hash->{PID};
    my $result  = "";

    
    
    
    #Leerzeichen müßen für die Rückgabe escaped werden sonst werden sie falsch angezeigt
    if( $cmd eq 'playlists' ) {
        
        #gibt die Playlisten durch Komma getrennt zurück
        my @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
        
        $result .= join(",",@playlists) if( scalar @playlists > 0 );
        
        return $result;
        
    } elsif( $cmd eq 'channels' ) {
    
        #gibt die Favoriten durch Komma getrennt zurück
        my @channels = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{favorites}});
    
        $result .= join(",",@channels) if( scalar @channels > 0 );
        
        return $result;
        
    } elsif( $cmd eq 'channelscount' ) {
    
        #gibt die Favoritenanzahl zurück
        return scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );		
    
    } elsif( $cmd eq 'inputs' ) {
        
        #gibt die Quellen durch Komma getrennt zurück	
        my @inputs = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{sources}});
        
        $result .= join(",",@inputs) if( scalar @inputs > 0 );
        
        return $result;
    }

    my $list = 'playlists:noArg channels:noArg channelscount:noArg inputs:noArg';

    return "Unknown argument $cmd, choose one of $list";
}

sub HEOSPlayer_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    
    my $pid     = $hash->{PID};
    my $action;
    my $heosCmd;
    my $rvalue;
    my $favcount = 1;


    if( $cmd eq 'getPlayerInfo' ) {
        return "usage: getPlayerInfo" if( @args != 0 );

        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayState' ) {
        return "usage: getPlayState" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getPlayMode' ) {
        return "usage: getPlayMode" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'getNowPlayingMedia' ) {
        return "usage: getNowPlayingMedia" if( @args != 0 );
        
        $heosCmd    = $cmd;
        
    } elsif( $cmd eq 'repeat' ) {
        return "usage: repeat" if( @args != 1 );
        
        $heosCmd    = 'setPlayMode';
        
        if($args[0] eq 'all') {
        
            $rvalue     = 'on_all';
            
        } elsif($args[0] eq 'one') {
        
            $rvalue     = 'on_one';
            
        } else {
        
            $rvalue     = $args[0];
        }
        
        $action     = "repeat=$rvalue&shuffle=" . ReadingsVal($name,'shuffle','off');
        
    } elsif( $cmd eq 'shuffle' ) {
        return "usage: shuffle" if( @args != 1 );
        
        $heosCmd    = 'setPlayMode';
        
        if(ReadingsVal($name,'repeat','off') eq 'all') {
        
            $rvalue     = 'on_all';
            
        } elsif(ReadingsVal($name,'repeat','off') eq 'one') {
        
            $rvalue     = 'on_one';
        }
        
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
        
    } elsif( $cmd eq 'mute' ) {
        return "usage: mute on/off" if( @args != 1 );
        
        $heosCmd    = 'setMute';
        $action     = "state=$args[0]";
        
    } elsif( $cmd eq 'volume' ) {
        return "usage: volume 0-100" if( @args != 1 );
        
        $heosCmd    = 'setVolume';
        $action     = "level=$args[0]";
        
    } elsif( $cmd eq 'volumeUp' ) {
        return "usage: volumeUp 0-10" if( @args != 1 );
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'volumeDown' ) {
        return "usage: volumeDown 0-10" if( @args != 1 );
        
        $heosCmd    = $cmd;
        $action     = "step=$args[0]";
        
    } elsif( $cmd eq 'groupWithMember' ) {
        return "usage: groupWithMember" if( @args != 1 );
        
        $pid       .= ",$defs{$args[0]}->{PID}";
        $heosCmd    = 'createGroup';
        
    } elsif( $cmd eq 'clearGroup' ) {
        return "usage: clearGroup" if( @args != 0 );
                
        $heosCmd    = 'createGroup';

    } elsif( $cmd eq 'next' ) {
    
        return "usage: next" if( @args != 0 );        
        $heosCmd    = 'playNext';        
        
    } elsif( $cmd eq 'prev' ) {
    
        return "usage: prev" if( @args != 0 );        
        $heosCmd    = 'playPrev';
        
    } elsif( $cmd eq 'reReadSources' ) { 
    
        return "usage: reReadSources" if( @args != 0 ); 
        $heosCmd    = 'getMusicSources';
        
    } elsif ( $cmd eq 'channel' ) {
    
        $favcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        return "usage: channel 1-$favcount" if( @args != 1 );
        
        $heosCmd    = 'playPresetStation';
        $action     = "preset=$args[0]";
        
    } elsif( $cmd eq 'channelUp' ) {

        return "usage: channelUp" if( @args != 0 );        
        #$favcount = scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );
        
        $heosCmd    = 'playPresetStation';
        my $fav = ReadingsVal($name,"channel", 0) + 1;
        $fav = $favcount if ( $fav > $favcount);
        $action     = "preset=".$fav;
        
    } elsif( $cmd eq 'channelDown' ) {
    
        return "usage: channelDown" if( @args != 0 );
        
        $heosCmd    = 'playPresetStation';
        my $fav = ReadingsVal($name,"channel", 0) - 1;
        $fav = 1 if ($fav <= 0);
        $action     = "preset=".$fav;
        
    } elsif ( $cmd eq 'playlist' ) {
    
        my @cids =  map { $_->{cid} } grep { $_->{name} =~ /$args[0]/i } (@{ $hash->{IODev}{helper}{playlists} });
        
        if ( scalar @args == 1 && scalar @cids == 1 ) {
        
            $heosCmd    = 'playPlaylist';
            $action     = "sid=1025&cid=$cids[0]&aid=4";	
            
        } else {
        
            my @playlists = map { $_->{name} } (@{ $hash->{IODev}{helper}{playlists}});				
            return "usage: playlist ".join(",",@playlists); 
        }
        
    } elsif( $cmd eq 'input' ) {		
        
        my $search = $args[0];
        my @sids =  map { $_->{sid} } grep { $_->{name} =~ /$search/i } (@{ $hash->{IODev}{helper}{sources} });
        
        #$search =~ s/\s+/\&nbsp;/g;
        $search =~ s/\xC2\xA0/ /g;
        
        if ( scalar @args == 1 && scalar @sids == 1 ) {
        
            readingsSingleUpdate($hash, "input", $args[0], 1);
            #sid des Input für Container merken
            readingsSingleUpdate($hash, ".input", $sids[0], 1);
            #alten Container löschen bei Inputwechsel
            readingsSingleUpdate($hash, ".cid", 0, 1);
            
            $heosCmd = 'browseSource';		
            $action = "sid=$sids[0]";
            
            Log3 $name, 4, "HEOSPlayer ($name) - set input with sid $sids[0] and name $args[0]";	
            
        } else {
        
            my @inputs = map { $_->{name} } (@{ $hash->{IODev}{helper}{sources}});						
            return "usage: input ".join(",",@inputs);        
        }

    } elsif( $cmd eq 'media' ) {
    
        if ( scalar @args == 1 ) {
        
            #sid des Input holen
            my $sid = ReadingsVal($name,".input", undef);			 
            return "usage: set input first" unless( defined($sid) );
            
            my $search = $args[0];
            $search =~ s/\xC2\xA0/ /g;
            
            my @ids = grep { $_->{name} =~ /\Q$search\E/i } (@{ $hash->{IODev}{helper}{media} });
            #print "gefundenes Medium\n".Dumper(@ids);
            
            if ( scalar @ids == 1 ) {
                if ( exists $ids[0]{cid} ) {
                    #hier Container verarbeiten
                    if ( $ids[0]{playable} eq "yes" ) {
                    
                        #alles abspielen
                        $heosCmd    = 'playPlaylist';
                        $action     = "sid=$sid&cid=$ids[0]{cid}&aid=4";
                        #Container merken
                        readingsSingleUpdate($hash, ".cid", 0, 1);
                        
                    } else {
                    
                        #mehr einlesen
                        readingsSingleUpdate($hash, ".cid", $ids[0]{cid}, 1);
                        $heosCmd = 'browseSource';		
                        $action = "sid=$sid&cid=$ids[0]{cid}";	
                    }
                    
                } elsif ( exists $ids[0]{mid} ) {
                    #hier Medien verarbeiten
                    if ( $ids[0]{mid} =~ /inputs\// ) {
                    
                        #Input abspielen
                        $heosCmd = 'playInput';		
                        $action = "input=$ids[0]{mid}";
                        
                    } else {
                    
                        #aktuellen Container holen
                        my $cid = ReadingsVal($name,".cid", undef);				
                        if ( defined $cid ) {
                            if ( $ids[0]{type} eq "station" ) {
                            
                                #Radio abspielen
                                $heosCmd = 'playStream';		
                                $action = "sid=$sid&cid=$cid&mid=$ids[0]{mid}";
                                
                            } else {
                            
                                #Song abspielen
                                $heosCmd = 'playPlaylist';		
                                $action = "sid=$sid&cid=$cid&mid=$ids[0]{mid}&aid=4";						
                            }
                        }
                    }
                }
            }
            
        } else {
        
            my @media = map { $_->{name} } (@{ $hash->{IODev}{helper}{media}});				
            return "usage: media ".join(",",@media);   
        }
        
    } elsif ( $cmd eq 'clearqueue' ) {
    
        #löscht die Warteschlange
        return "usage: clearqueue" if( @args != 0 );
        $heosCmd    = 'clearQueue';
        
    } elsif ( $cmd eq 'savequeue' ) {
    
        #speichert die aktuelle Warteschlange als Favorit ab
        return "usage: savequeue" if( @args != 1 );
        
        $heosCmd    = 'saveQueue name';
        $action     = "name=$args[0]";
        
    #} elsif( $cmd eq 'sayText' ) {
    #	return "usage: sayText Text" if( @args != 1 );

    } else {
    
        my @playlists;
        my @inputs;
        my @media;
        
        my  $list = "getPlayerInfo:noArg getPlayState:noArg getNowPlayingMedia:noArg getPlayMode:noArg play:noArg stop:noArg pause:noArg mute:on,off volume:slider,0,5,100 volumeUp:slider,0,1,10 volumeDown:slider,0,1,10 repeat:one,all,off shuffle:on,off clearqueue:noArg savequeue channelUp:noArg channelDown:noArg next:noArg prev:noArg ";
        
        $list .= "groupWithMember:" . join( ",", devspec2array("TYPE=HEOSPlayer:FILTER=NAME!=$name") );
        
        #Parameterlisten für FHEMWeb zusammen bauen
        $list .= " channel:slider,1,1,".scalar(@{$hash->{IODev}{helper}{favorites}}) if ( defined $hash->{IODev}{helper}{favorites} );		
        
        if ( defined $hash->{IODev}{helper}{playlists} ) {
        
            @playlists = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{playlists}});
            $list .= " playlist:".join(",",@playlists) if( scalar @playlists > 0 );
        }
        
        if ( defined $hash->{IODev}{helper}{sources}) {
        
            @inputs = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{sources}});
            $list .= " input:".join(",",@inputs) if( scalar @inputs > 0 );
        }
        
        if ( defined $hash->{IODev}{helper}{media}) {
        
            @media = map { my %n; $n{name} = $_->{name}; $n{name} =~ s/\s+/\&nbsp;/g; $n{name} } (@{ $hash->{IODev}{helper}{media}});
            push(@media,"Alle") if grep { $_->{container} =~ /yes/i && $_->{playable} =~ /yes/i} (@{ $hash->{IODev}{helper}{media} });
            $list .= " media:".join(",",@media) if( scalar @media > 0 );
        }
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    
    my $string  = "pid=$pid";
    $string     .= "&$action" if( defined($action));
    
    IOWrite($hash,"$heosCmd","$string");
    Log3 $name, 4, "HEOSPlayer ($name) - IOWrite: $heosCmd $string IODevHash=$hash->{IODev}";
    
    return undef;
}

sub HEOSPlayer_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};
    my $pid;
    my $decode_json;
    
    
    $decode_json    = decode_json(encode_utf8($json));

    Log3 $name, 4, "HEOSPlayer ($name) - ParseFn wurde aufgerufen";




    if( defined($decode_json->{pid}) ) {
    
        $pid            = $decode_json->{pid};
        my $code        = abs($pid);
        $code           = $io_hash->{NAME} ."-". $code if( defined($io_hash->{NAME}) );
    
    
        if( my $hash    = $modules{HEOSPlayer}{defptr}{$code} ) {
        
            my $name    = $hash->{NAME};
            
            IOWrite($hash,'getPlayerInfo',"pid=$hash->{PID}");
            Log3 $name, 4, "HEOSPlayer ($name) - find logical device: $hash->{NAME}";
            Log3 $name, 4, "HEOSPlayer ($name) - find PID in root from decode_json";
            
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
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
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
    
    
    Log3 $name, 4, "HEOSPlayer ($name) - preprocessing readings";
    
    if ( $decode_json->{heos}{command} =~ /play_state/ or $decode_json->{heos}{command} =~ /player_state_changed/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'playStatus'}   = substr($value[1],6);
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_changed/ or $decode_json->{heos}{command} =~ /set_volume/ or $decode_json->{heos}{command} =~ /get_volume/ ) {
    
        my @value           = split('&', $decode_json->{heos}{message});
        $buffer{'volume'}   = substr($value[1],6);
        $buffer{'mute'}     = substr($value[2],5) if( $decode_json->{heos}{command} =~ /volume_changed/ );
        
        if (defined($buffer{'mute'}) && AttrVal($name, 'mute2play', 0) == 1) {
        
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=play") if $buffer{'mute'} eq "off";
            IOWrite($hash,'setPlayState',"pid=$hash->{PID}&state=stop") if $buffer{'mute'} eq "on";			
        }
        
    } elsif ( $decode_json->{heos}{command} =~ /play_mode/ ) {
    
        my @value           = split('&', $decode_json->{heos}{message});
        if(substr($value[1],7) eq 'on_all') {
        
            $buffer{'repeat'}   = 'all';
            
        } elsif (substr($value[1],7) eq 'on_one') {
            
            $buffer{'repeat'}   = 'one';
            
        } else {
        
            $buffer{'repeat'}   = substr($value[1],7);
        }
        
        $buffer{'shuffle'}  = substr($value[2],8);
        
    } elsif ( $decode_json->{heos}{command} =~ /get_mute/ ) {
		my @value           = split('&', $decode_json->{heos}{message});        
        $buffer{'mute'}     = substr($value[1],6);
        
    } elsif ( $decode_json->{heos}{command} =~ /volume_up/ or $decode_json->{heos}{command} =~ /volume_down/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'volumeUp'}     = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_up/ );
        $buffer{'volumeDown'}   = substr($value[1],5) if( $decode_json->{heos}{command} =~ /volume_down/ );
        
    } elsif ( $decode_json->{heos}{command} =~ /repeat_mode_changed/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        
        if(substr($value[1],7) eq 'on_all') {
        
            $buffer{'repeat'}   = 'all';
            
        } elsif (substr($value[1],7) eq 'on_one') {
            
            $buffer{'repeat'}   = 'one';
        
        } else {
        
            $buffer{'repeat'}   = substr($value[1],7);
        }
        
    } elsif ( $decode_json->{heos}{command} =~ /shuffle_mode_changed/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'shuffle'}      = substr($value[1],8);
        
    } elsif ( $decode_json->{heos}{command} =~ /player_now_playing_changed/ or $decode_json->{heos}{command} =~ /favorites_changed/ ) {
        
        IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}");
        
    } elsif ( $decode_json->{heos}{command} =~ /play_preset/ ) {

        my @value            	= split('&', $decode_json->{heos}{message});
        $buffer{'channel'}   	= substr($value[1],7);

    } elsif ( $decode_json->{heos}{command} =~ /play_input/ ) {
    
        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'input'}   		= substr($value[1],6);
        
    } elsif ( $decode_json->{heos}{command} =~ /playback_error/ ) {

        my @value               = split('&', $decode_json->{heos}{message});
        $buffer{'error'}   		= substr($value[1],6);
        
    } else {
    
        Log3 $name, 3, "HEOSPlayer ($name) - no match found";
        return undef;
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

sub HEOSPlayer_GetPlayMode($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetPlayMode');
    IOWrite($hash,'getPlayMode',"pid=$hash->{PID}");
    
}

sub HEOSPlayer_GetNowPlayingMedia($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetNowPlayingMedia');
    IOWrite($hash,'getNowPlayingMedia',"pid=$hash->{PID}");
    
}

sub HEOSPlayer_GetVolume($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetVolume');
    IOWrite($hash,'getVolume',"pid=$hash->{PID}");
    
}

sub HEOSPlayer_GetMute($) {

    my $hash        = shift;
    
    RemoveInternalTimer($hash,'HEOSPlayer_GetMute');
    IOWrite($hash,'getMute',"pid=$hash->{PID}");
    
}










1;
