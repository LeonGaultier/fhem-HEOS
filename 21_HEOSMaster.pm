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


my $missingModulRemote;
eval "use Net::Telnet;1" or $missingModulRemote .= "Net::Telnet ";
use IO::Socket::INET;


my $version = "0.0.22";



# Declare functions
sub HEOSMaster_Initialize($);
sub HEOSMaster_Define($$);
sub HEOSMaster_Undef($$);
sub HEOSMaster_Set($@);
sub HEOSMaster_Connect($);
sub HEOSMaster_Disconnect($);
sub HEOSMaster_send($);
sub HEOSMaster_Read($);




sub HEOSMaster_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "HEOSMaster_Read";
    #$hash->{WriteFn}    = "HEOSMaster_Read";
    #$hash->{Clients}    = ":HEOSPlayer:";

      
    # Consumer
    $hash->{SetFn}      = "HEOSMaster_Set";
    #$hash->{GetFn}      = "HEOSMaster_Get";
    $hash->{DefFn}      = "HEOSMaster_Define";
    $hash->{UndefFn}    = "HEOSMaster_Undef";
    #$hash->{AttrFn}     = "HEOSMaster_Attr";
    #$hash->{AttrList}   = "disable:1 ".
    #                      $readingFnAttributes;


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
    readingsSingleUpdate($hash, 'state', 'Initialized', 1 );


    $modules{HEOSMaster}{defptr}{$hash->{HOST}} = $hash;
    
    return undef;
}

sub HEOSMaster_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    
    delete $modules{HEOSMaster}{defptr}{$hash->{HOST}};
    
    return undef;
}

sub HEOSMaster_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;

    
    if($cmd eq 'startConnect') {
        return "usage: startConnect" if( @args != 0 );

       HEOSMaster_Connect($hash);

        return undef;
        
    } elsif($cmd eq 'stopConnect') {
        return "usage: stopConnect" if( @args != 0 );

        HEOSMaster_Disconnect($hash);

        return undef;   
        
     } elsif($cmd eq 'send') {
        return "usage: send" if( @args != 0 );

        HEOSMaster_send($hash);

        return undef;   
        
    } else {
        my  $list = ""; 
        $list .= "startConnect:noArg stopConnect:noArg send:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub HEOSMaster_Connect($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 1255;
    my $timeout = 1;
    my $msg;
    
    Log3 $name, 3, "HEOSMaster ($name) - Baue Socket Verbindung auf";
    
    
    #my $socket = IO::Socket::INET->new(PeerAddr => $host,
    #    PeerPort => $port,
    #    Proto    => 'tcp',
    #    Type     => SOCK_STREAM,
    #    Timeout  => $timeout )
    #    or return Log3 $name, 3, "HEOSMaster ($name) Couldn't connect to $host:$port";
    
    my $socket = new Net::Telnet ( Host=>$host,
        Port => $port,
        Timeout=>$timeout,
        Errmode=>'return')
        or return Log3 $name, 3, "HEOSMaster ($name) Couldn't connect to $host:$port";
        
    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $selectlist{$name} = $hash;
    
    readingsSingleUpdate($hash, 'state', 'connected', 1 );
    
    Log3 $name, 3, "HEOSMaster ($name) - Socket Connected";
    
    syswrite($hash->{CD}, "heos://system/register_for_change_events?enable=on\r\n") if( defined($hash->{CD}) );
}

sub HEOSMaster_Disconnect($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    return if( !$hash->{CD} );

    close($hash->{CD}) if($hash->{CD});
    delete($hash->{FD});
    delete($hash->{CD});
    delete($selectlist{$name});
    readingsSingleUpdate($hash, 'state', 'not connected', 1 );
}

sub HEOSMaster_send($) {
    
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf;
    
    return  Log3 $name, 3, "HEOSMaster ($name) - CD nicht vorhanden" unless( defined($hash->{CD}));
	
	syswrite($hash->{CD}, "heos://player/get_players\r\n");
    Log3 $name, 3, "HEOSMaster ($name) - Syswrite ausgeführt";
}

sub HEOSMaster_Read($) {

    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $len;
    my $buf;
    
    Log3 $name, 3, "HEOSMaster ($name) - ReadFn gestartet";

    $len = sysread($hash->{CD},$buf,4096);
    
    if( !defined($len) || !$len ) {
        Log 1, "Länge? !!!!!!!!!!";
        return;
    }
    
	unless( defined $buf) { 
        Log3 $name, 3, "HEOSMaster ($name) - Keine Daten empfangen";
        return undef; 
    }
    
	Log3 $name, 3, "HEOSMaster ($name) - Daten: $buf";
}







1;
