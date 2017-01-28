###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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

#################################
######### Wichtige Hinweise und Links #################


##
#


################################


package main;

use strict;
use warnings;

use JSON;
use Net::Telnet;


my $version = "0.1.36";


my %heosCmds = (
    'enableChangeEvents'        => 'system/register_for_change_events?enable=',
    'getPlayers'                => 'player/get_players',
    'getPlayerInfo'             => 'player/get_player_info?',
    'getPlayState'              => 'player/get_play_state?',
    'setPlayState'              => 'player/set_play_state?',
    'setMute'                   => 'player/set_mute?',
    'setVolume'                 => 'player/set_volume?',
    'getNowPlayingMedia'        => 'player/get_now_playing_media?',
    'eventChangeVolume'                     => 'event/player_volume_changed'
);




# Declare functions
sub HEOSMaster_Initialize($);
sub HEOSMaster_Define($$);
sub HEOSMaster_Undef($$);
sub HEOSMaster_Set($@);
sub HEOSMaster_Open($);
sub HEOSMaster_Close($);
sub HEOSMaster_Read($);
sub HEOSMaster_Write($@);
sub HEOSMaster_Attr(@);
sub HEOSMaster_firstRun($);
sub HEOSMaster_ResponseProcessing($$);
sub HEOSMaster_WriteReadings($$);
sub HEOSMaster_PreResponseProsessing($$);
sub HEOSMaster_GetPlayers($);
sub HEOSMaster_EnableChangeEvents($);




sub HEOSMaster_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "HEOSMaster_Read";
    $hash->{WriteFn}    = "HEOSMaster_Write";
    $hash->{Clients}    = ":HEOSPlayer:";
    $hash->{MatchList} = { "1:HEOSPlayer"   => '.*{"command":."player.*|.*{"command":."event\/player.*' };

      
    # Consumer
    $hash->{SetFn}      = "HEOSMaster_Set";
    #$hash->{GetFn}      = "HEOSMaster_Get";
    $hash->{DefFn}      = "HEOSMaster_Define";
    $hash->{UndefFn}    = "HEOSMaster_Undef";
    $hash->{AttrFn}     = "HEOSMaster_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          $readingFnAttributes;


    foreach my $d(sort keys %{$modules{HEOSMaster}{defptr}}) {
        my $hash = $modules{HEOSMaster}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub HEOSMaster_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> HEOSMaster <HOST>" if( @a != 3 );
    


    my $name            = $a[0];
    my $host            = $a[2];

    $hash->{HOST}       = $host;
    $hash->{VERSION}    = $version;


    Log3 $name, 3, "HEOSMaster ($name) - defined with host $host";

    $attr{$name}{room} = "HEOS" if( !defined( $attr{$name}{room} ) );
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'state','Initialized');
    readingsBulkUpdate($hash,'enableChangeEvents', 'off');
    readingsEndUpdate($hash,1);
    
    
    if( $init_done ) {
    
        HEOSMaster_firstRun($hash);
        
    } else {
    
        InternalTimer( gettimeofday()+15, 'HEOSMaster_firstRun', $hash, 0 ) if( ($hash->{HOST}) );
    }
    
    return undef;
}

sub HEOSMaster_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    HEOSMaster_Close($hash);
    delete $modules{HEOSMaster}{defptr}{$hash->{HOST}};
    
    Log3 $name, 3, "HEOSPlayer ($name) - device $name deleted";
    
    return undef;
}

sub HEOSMaster_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "HEOSMaster ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - delete disabledForIntervals";
        }
    }

    return undef;
}

sub HEOSMaster_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;

    my $action;
    my $heosCmd;
    
    if($cmd eq 'reopen') {
        return "usage: reopen" if( @args != 0 );

        HEOSMaster_Close($hash);
        HEOSMaster_Open($hash) if( !$hash->{CD} or !defined($hash->{CD}) );

        return undef;

    } elsif($cmd eq 'getPlayers') {
        return "usage: getPlayers" if( @args != 0 );

        $heosCmd    = 'getPlayers';
        $action     = undef;
        
        return undef;
        
    } elsif($cmd eq 'enableChangeEvents') {
        return "usage: enableChangeEvents" if( @args != 1 );

        $heosCmd    = $cmd;
        $action     = $args[0];
        
    } elsif($cmd eq 'eventSend') {
        return "usage: eventSend" if( @args != 0 );

        HEOSMaster_send($hash);
        return undef;
        
    } else {
        my  $list = ""; 
        $list .= "reopen:noArg getPlayers:noArg enableChangeEvents:on,off";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    HEOSMaster_Write($hash,$heosCmd,$action);
}

sub HEOSMaster_Open($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 1255;
    my $timeout = 1;
    
    
    Log3 $name, 4, "HEOSMaster ($name) - Baue Socket Verbindung auf";
    

    my $socket = new Net::Telnet ( Host=>$host,
        Port => $port,
        Timeout=>$timeout,
        Errmode=>'return')
        or return Log3 $name, 3, "HEOSMaster ($name) Couldn't connect to $host:$port";
        
    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $selectlist{$name} = $hash;
    
    readingsSingleUpdate($hash, 'state', 'connected', 1 );
    
    Log3 $name, 4, "HEOSMaster ($name) - Socket Connected";
    
    HEOSMaster_GetPlayers($hash);
    
}

sub HEOSMaster_Close($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    return if( !$hash->{CD} );

    close($hash->{CD}) if($hash->{CD});
    delete($hash->{FD});
    delete($hash->{CD});
    delete($selectlist{$name});
    readingsSingleUpdate($hash, 'state', 'not connected', 1 );
}

sub HEOSMaster_Write($@) {

    my ($hash,$heosCmd,$value)  = @_;
    my $name                    = $hash->{NAME};
    
    
    my $string  = "heos://$heosCmds{$heosCmd}";
    
    if( defined($value) ) {
        $string    .= "${value}" if( $value ne '&' );
    }
    
    $string    .= "\r\n";
    
    Log3 $name, 4, "HEOSMaster ($name) - WriteFn called";
    
    return Log3 $name, 4, "HEOSMaster ($name) - socket not connected"
    unless($hash->{CD});

    Log3 $name, 5, "HEOSMaster ($name) - $string";
    syswrite($hash->{CD}, $string);
    return undef;
}

sub HEOSMaster_Read($) {

    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $len;
    my $buf;
    
    Log3 $name, 4, "HEOSMaster ($name) - ReadFn gestartet";

    $len = sysread($hash->{CD},$buf,1024);          # die genaue Puffergröße wird noch ermittelt
    
    if( !defined($len) || !$len ) {
        Log 1, "unknown buffer length";
        return;
    }
    
	unless( defined $buf) { 
        Log3 $name, 3, "HEOSMaster ($name) - Keine Daten empfangen";
        return; 
    }
    
    if( $buf !~ m/^[\[{].*[}\]]$/ ) {
        Log3 $name, 4, "HEOSMaster ($name) - invalid json detected. start preprocessing";
        HEOSMaster_PreResponseProsessing($hash,$buf);
        return;
    }
    
	Log3 $name, 5, "HEOSMaster ($name) - Daten: $buf";
	HEOSMaster_ResponseProcessing($hash,$buf);
}

sub HEOSMaster_PreResponseProsessing($$) {

    my ($hash,$response)    = @_;
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "HEOSMaster ($name) - pre processing respone data";
    
    my $len = length($response);
    my @letterArray = split("",$response);

    my $letter  = "";
    my $count   = 0;
    my $marker  = 0;
    my $json;

    for(my $i = 0; $i < $len; $i++) {

        $marker     = 1 if($count > 0);
        $letter     = $letterArray[0];
        $json      .= $letter;
        
        $count++ if($letter eq '{');
        $count-- if($letter eq '}');



        if( $count == 0 and $marker == 1) {
     
            HEOSMaster_ResponseProcessing($hash,$json);
            $json = "";
            $marker = 0;
        }

        shift(@letterArray);
    }
    
    #my $rest = join(' ',@letterArray);      # currupted data, rest  array
    #Log3 $name, 3, "HEOSMaster ($name) - found corrupt data in buffer: $rest" if( defined($rest) and ($rest) );
}

sub HEOSMaster_ResponseProcessing($$) {

    my ($hash,$json)    = @_;
    my $name            = $hash->{NAME};
    
    my $decode_json;
    

    Log3 $name, 5, "HEOSMaster ($name) - JSON String: $json";

    return Log3 $name, 3, "HEOSMaster ($name) - empty answer received"
    unless( defined($json));


    Log3 $name, 5, "HEOSMaster ($name) - json detected: $json";
    $decode_json = decode_json($json);
    
    return Log3 $name, 3, "HEOSMaster ($name) - decode_json has no Hash"
    unless(ref($decode_json) eq "HASH");


    if( (defined($decode_json->{heos}{result}) and defined($decode_json->{heos}{command})) or ($decode_json->{heos}{command} =~ /^system/) ) {
    
        HEOSMaster_WriteReadings($hash,$decode_json);
        Log3 $name, 4, "HEOSMaster ($name) - call Sub HEOSMaster_WriteReadings";
    }
    
    if( $decode_json->{heos}{command} =~ /^player/ or $decode_json->{heos}{command} =~ /^event\/player/ ) {
        if( ref($decode_json->{payload}) eq "ARRAY" and scalar(@{$decode_json->{payload}}) > 0) {
        
            foreach my $payload (@{$decode_json->{payload}}) {
            
                $json  =    '{"pid": "';
                $json .=    "$payload->{pid}";
                $json .=    '","heos": {"command": "player/get_players"}}';

                Dispatch($hash,$json,undef);
                Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";

            }
            
            return;
            
        } elsif( defined($decode_json->{payload}{pid}) ) {
    
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
            return;
            
        } elsif( $decode_json->{heos}{message} =~ /^pid=/ ) {
        
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
            return;
            
        }
    } 
    
    Log3 $name, 4, "HEOSMaster ($name) - no Match for processing data";
}

sub HEOSMaster_WriteReadings($$) {

    my ($hash,$decode_json) = @_;
    my $name                = $hash->{NAME};
    my $value;
    
    
    readingsBeginUpdate($hash);
    if ( $decode_json->{heos}{command} =~ /register_for_change_events/ ) {
        my @value     = split('=', $decode_json->{heos}{message});
        $value        = $value[1];
        readingsBulkUpdate( $hash, 'enableChangeEvents', "$value" );
    }
    
    readingsBulkUpdate( $hash, "lastCommand", $decode_json->{heos}{command} );
    readingsBulkUpdate( $hash, "lastResult", $decode_json->{heos}{result} );
    
    if( ref($decode_json->{payload}) ne "ARRAY" ) {
        readingsBulkUpdate( $hash, "lastPlayerId", $decode_json->{payload}{pid} );
        readingsBulkUpdate( $hash, "lastPlayerName", $decode_json->{payload}{name} );
    }
    
    readingsEndUpdate( $hash, 1 );
    
    return undef;
}

###################
### my little Helpers

sub HEOSMaster_firstRun($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    HEOSMaster_Open($hash) if( !IsDisabled($name) );
}

sub HEOSMaster_GetPlayers($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    HEOSMaster_Write($hash,'getPlayers',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getPlayers";
    
    InternalTimer( gettimeofday()+2, 'HEOSMaster_EnableChangeEvents', $hash, 0 );
}

sub HEOSMaster_EnableChangeEvents($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    HEOSMaster_Write($hash,'enableChangeEvents','on');
    Log3 $name, 3, "HEOSMaster ($name) - set enableChangeEvents on";
}

################
### Nur für mich um dem Emulator ein Event ab zu jagen
sub HEOSMaster_send($) {

    my $hash    = shift;
    
    HEOSMaster_Write($hash,'eventChangeVolume',undef);

}









1;
