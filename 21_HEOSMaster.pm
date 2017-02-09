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

use JSON qw(decode_json);
use Encode qw(encode_utf8);
use Net::Telnet;


my $version = "0.1.47";


my %heosCmds = (
    'enableChangeEvents'        => 'system/register_for_change_events?enable=',
    'checkAccount'              => 'system/check_account',
    'signAccountIn'             => 'system/sign_in?',
    'signAccountOut'            => 'system/sign_out',
    'reboot'                    => 'system/reboot',
    'getPlayers'                => 'player/get_players',
    'getGroups'                 => 'player/get_groups',
    'getPlayerInfo'             => 'player/get_player_info?',
    'getPlayState'              => 'player/get_play_state?',
    'getPlayMode'               => 'player/get_play_mode?',
    'getVolume'                 => 'player/get_volume?',
    'getGroupVolume'            => 'group/get_volume?',
    'setPlayState'              => 'player/set_play_state?',
    'setPlayMode'               => 'player/set_play_mode?',
    'setMute'                   => 'player/set_mute?',
    'setVolume'                 => 'player/set_volume?',
    'setGroupVolume'            => 'group/set_volume?',
    'volumeUp'                  => 'player/volume_up?',
    'volumeDown'                => 'player/volume_down?',
    'GroupVolumeUp'             => 'group/volume_up?',
    'GroupVolumeDown'           => 'group/volume_down?',
    'getNowPlayingMedia'        => 'player/get_now_playing_media?',
    'eventChangeVolume'         => 'event/player_volume_changed'
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
sub HEOSMaster_PreProcessingReadings($$);
sub HEOSMaster_ReOpen($);
sub HEOSMaster_ReadPassword($);
sub HEOSMaster_StorePassword($$);
sub HEOSMaster_GetGroups($);




sub HEOSMaster_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     =   "HEOSMaster_Read";
    $hash->{WriteFn}    =   "HEOSMaster_Write";
    $hash->{Clients}    =   ":HEOSPlayer:";
    $hash->{MatchList}  = { "1:HEOSPlayer"      => '.*{"command":."player.*|.*{"command":."event\/player.*|.*{"command":."event\/repeat_mode_changed.*|.*{"command":."event\/shuffle_mode_changed.*',
                            "2:HEOSGroup"       => '.*{"command":."group.*|.*{"command":."event\/group.*'
                            };


    # Consumer
    $hash->{SetFn}      = "HEOSMaster_Set";
    #$hash->{GetFn}      = "HEOSMaster_Get";
    $hash->{DefFn}      = "HEOSMaster_Define";
    $hash->{UndefFn}    = "HEOSMaster_Undef";
    $hash->{AttrFn}     = "HEOSMaster_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          "heosUsername ".
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
    
    $modules{HEOSPlayer}{defptr}{$host} = $hash;
    
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
    my ($arg, @params)  = @args;

    my $action;
    my $heosCmd;
    
    if($cmd eq 'reopen') {
        return "usage: reopen" if( @args != 0 );

        HEOSMaster_ReOpen($hash);

        return undef;

    } elsif($cmd eq 'getPlayers') {
        return "usage: getPlayers" if( @args != 0 );

        $heosCmd    = 'getPlayers';
        $action     = undef;
        
    } elsif($cmd eq 'getGroups') {
        return "usage: getGroups" if( @args != 0 );

        $heosCmd    = 'getGroups';
        $action     = undef;
        
    } elsif($cmd eq 'enableChangeEvents') {
        return "usage: enableChangeEvents" if( @args != 1 );

        $heosCmd    = $cmd;
        $action     = $args[0];
        
    } elsif($cmd eq 'checkAccount') {
        return "usage: checkAccount" if( @args != 0 );

        $heosCmd    = $cmd;
        $action     = undef;
        
    } elsif($cmd eq 'signAccount') {
        return "usage: signAccountIn" if( @args != 1 );
        return "please set account informattion first" if(AttrVal($name,'heosUsername','none') eq 'none');

        $heosCmd    = $cmd . $args[0];
        $action     = 'un='. AttrVal($name,'heosUsername','none') . '&pw=' . HEOSMaster_ReadPassword($hash) if($args[0] eq 'In');
    
    } elsif($cmd eq 'password') {
        return "usage: password" if( @args != 1 );

        return HEOSMaster_StorePassword( $hash, $args[0] );
        
    } elsif($cmd eq 'reboot') {
        return "usage: reboot" if( @args != 0 );

        return HEOSMaster_StorePassword( $hash, $args[0] );
        
        
    ###################################################
    ### Dieser Menüpunkt ist nur zum testen
    } elsif($cmd eq 'eventSend') {
            return "usage: eventSend" if( @args != 0 );

            HEOSMaster_send($hash);
            return undef;
    ###################################################
    
            
    } else {
        my  $list = ""; 
        $list .= "reopen:noArg getPlayers:noArg getGroups:noArg enableChangeEvents:on,off checkAccount:noArg signAccount:In,Out password reboot";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    HEOSMaster_Write($hash,$heosCmd,$action);
}

sub HEOSMaster_Open($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 1255;
    my $timeout = 0.1;
    
    
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
    
    InternalTimer( gettimeofday()+1, 'HEOSMaster_GetPlayers', $hash, 1 );
    InternalTimer( gettimeofday()+3, 'HEOSMaster_GetGroups', $hash, 1 );
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

sub HEOSMaster_ReOpen($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    HEOSMaster_Close($hash);
    HEOSMaster_Open($hash) if( !$hash->{CD} or !defined($hash->{CD}) );
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
        Log3 $name, 5, "HEOSMaster ($name) - connection closed by remote Host";
        HEOSMaster_Close($hash);
        return;
    }
    
	unless( defined $buf) { 
        Log3 $name, 3, "HEOSMaster ($name) - Keine Daten empfangen";
        return; 
    }
    
    Log3 $name, 5, "HEOSMaster ($name) - received buffer data, start preprocessing: $buf";
    HEOSMaster_PreResponseProsessing($hash,$buf);
}

sub HEOSMaster_PreResponseProsessing($$) {

    my ($hash,$response)    = @_;
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "HEOSMaster ($name) - pre processing response data";
    
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


    Log3 $name, 4, "HEOSMaster ($name) - JSON detected!";
    $decode_json = decode_json(encode_utf8($json));
    
    return Log3 $name, 3, "HEOSMaster ($name) - decode_json has no Hash"
    unless(ref($decode_json) eq "HASH");


    if( (defined($decode_json->{heos}{result}) and defined($decode_json->{heos}{command})) or ($decode_json->{heos}{command} =~ /^system/) ) {
    
        HEOSMaster_WriteReadings($hash,$decode_json);
        Log3 $name, 4, "HEOSMaster ($name) - call Sub HEOSMaster_WriteReadings";

    }
    
    if( $decode_json->{heos}{command} =~ /^player/ or $decode_json->{heos}{command} =~ /^event\/player/ or $decode_json->{heos}{command} =~ /^group/ or $decode_json->{heos}{command} =~ /^event\/group/ or $decode_json->{heos}{command} =~ /^event\/repeat_mode_changed/ or $decode_json->{heos}{command} =~ /^event\/shuffle_mode_changed/ ) {
        if( $decode_json->{heos}{command} =~ /^player/ and ref($decode_json->{payload}) eq "ARRAY" and scalar(@{$decode_json->{payload}}) > 0) {
        
            foreach my $payload (@{$decode_json->{payload}}) {
            
                $json  =    '{"pid": "';
                $json .=    "$payload->{pid}";
                $json .=    '","heos": {"command": "player/get_players"}}';

                Dispatch($hash,$json,undef);
                Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
            }
            
            return;
            
        } elsif( $decode_json->{heos}{command} =~ /^group/ and ref($decode_json->{payload}) eq "ARRAY" and scalar(@{$decode_json->{payload}}) > 0) {
        
            foreach my $payload (@{$decode_json->{payload}}) {
            
                $json  =    '{"gid": "';
                $json .=    "$payload->{gid}";
                $json .=    '","heos": {"command": "group/get_groups"}}';

                Dispatch($hash,$json,undef);
                Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
            }
            
            return;
            
        } elsif( defined($decode_json->{payload}{pid}) ) {
    
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
            return;
            
        } elsif( defined($decode_json->{heos}{message}) and $decode_json->{heos}{message} =~ /^pid=/ ) {
        
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
    
    
    ############################
    #### Aufbereiten der Daten soweit nötig
    
    my $readingsHash    = HEOSMaster_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{command} eq 'system/register_for_change_events'
        or $decode_json->{heos}{command} eq 'system/check_account'
        or $decode_json->{heos}{command} eq 'system/sign_in'
        or $decode_json->{heos}{command} eq 'system/sign_out' );
    
    
    ############################
    #### schreiben der Readings
    
    readingsBeginUpdate($hash);
    
    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
        
        Log3 $name, 4, "HEOSMaster ($name) - response json Hash back from HEOSMaster_PreProcessingReadings";
        
        my $t;
        my $v;
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
            if( defined( $v ) ) {
            
                readingsBulkUpdate( $hash, $t, $v );
            }
        }
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

sub HEOSMaster_PreProcessingReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    my $reading;
    my %buffer;


    Log3 $name, 4, "HEOSMaster ($name) - preprocessing readings";
    
    
    if ( $decode_json->{heos}{command} eq 'system/register_for_change_events' ) {
        
        my @value     = split('=', $decode_json->{heos}{message});
        $buffer{'enableChangeEvents'}   = $value[1];
        
    } elsif ( $decode_json->{heos}{command} eq 'system/check_account' or $decode_json->{heos}{command} eq 'system/sign_in' ) {
        
        my @value               = split('&', $decode_json->{heos}{message});
        if( $decode_json->{heos}{message} eq 'signed_out' ) {
        
            $buffer{'heosAccount'}  = $value[0];
            
        } else {

            $buffer{'heosAccount'}  = $value[0] . ' as ' . substr($value[1],3);
        }
        
    } else {
    
        Log3 $name, 3, "HEOSMaster ($name) - no match found";
        return undef;
    }
    
    Log3 $name, 4, "HEOSMaster ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSMaster_firstRun($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'HEOSMaster_firstRun');
    
    HEOSMaster_Open($hash) if( !IsDisabled($name) );
}

sub HEOSMaster_GetPlayers($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'HEOSMaster_GetPlayers');
    
    HEOSMaster_Write($hash,'getPlayers',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getPlayers";
    
    InternalTimer( gettimeofday()+2, 'HEOSMaster_EnableChangeEvents', $hash, 0 );
}

sub HEOSMaster_GetGroups($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'HEOSMaster_GetGroups');
    
    HEOSMaster_Write($hash,'getGroups',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getPlayers";
}

sub HEOSMaster_EnableChangeEvents($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'HEOSMaster_EnableChangeEvents');
    
    HEOSMaster_Write($hash,'enableChangeEvents','on');
    Log3 $name, 4, "HEOSMaster ($name) - set enableChangeEvents on";
}

sub HEOSMaster_StorePassword($$) {

    my ($hash, $password) = @_;     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my $enc_pwd = "";
    
    
    if(eval "use Digest::MD5;1") {
    
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password) {
    
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));
    
    return "password successfully saved";
}
   
sub HEOSMaster_ReadPassword($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my ($password, $err);

   
    Log3 $name, 4, "HEOSMaster ($name) - Read FritzBox password from file";

    ($err, $password) = getKeyValue($index);

    if ( defined($err) ) {

        Log3 $name, 4, "HEOSMaster ($name) - unable to read FritzBox password from file: $err";
        return undef;
    }  
    
    if ( defined($password) ) {

        if ( eval "use Digest::MD5;1" ) {

            $key = Digest::MD5::md5_hex(unpack "H*", $key);
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';
     
        for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
      
            my $decode=chop($key);
            $dec_pwd.=chr(ord($char)^ord($decode));
            $key=$decode.$key;
        }
     
        return $dec_pwd;
        
    } else {
    
      Log3 $name, 4, "HEOSMaster ($name) - No password in file";
      return undef;
    }
}




################
### Nur für mich um dem Emulator ein Event ab zu jagen
sub HEOSMaster_send($) {

    my $hash    = shift;
    
    HEOSMaster_Write($hash,'eventChangeVolume',undef);

}









1;
