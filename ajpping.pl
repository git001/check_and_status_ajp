#!/usr/bin/perl -w

# thanks to jffry for his initial code.
# http://www.perlmonks.org/?node_id=766945
#
# Author: jffry on Nov 18, 2011 at 22:11 UTC
# Author: Aleksandar Lazic 2015 05

use warnings;
use strict;
use Socket;
use Time::HiRes qw( time ualarm gettimeofday tv_interval );
use POSIX qw (strftime);

# unbufferd output
# $|=1;

our $version = '1.0';

# By default this script works in ping mode
our $mode_ping = 1;
$mode_ping = undef if $0 =~ /check_ajp.pl/ ;

my $host    = 'localhost';
my $port    = '8009';
my $timeout = 100000; # 100 milli seconds
my $timeouted   = undef;
my $good_answer = undef ;

my $connect_start  = -0.01;
my $connect_done   = -0.01;
my $syswrite_start = -0.01;
my $syswrite_done  = -0.01;
my $sysread_start  = -0.01;
my $sysread_done   = -0.01;
my $ip ;

# Icinga/Nagios return codes
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

our $rc = $ERRORS{'OK'};

# The host,port and timeout arguments can be specified by either space or colon
# separating the values.
if (scalar(@ARGV) >= 2) {
    $host    = shift @ARGV;
    $port    = shift @ARGV;
    $timeout = shift @ARGV if defined $ARGV[0];
}
else {
  print "need host port timeout in microseconds\n";
  exit $ERRORS{'UNKNOWN'};
}

local $SIG{ALRM} = sub { 
  $timeouted = 1;
  die "$host $ip $port $!";
}; 


# If the port has anything other than numbers, assume it is an /etc/services
# name.
if ($port =~ /\D/) {
    $port = getservbyname $port, 'tcp' ;
    die "Bad port: $port" unless $port;
}

my $iaddr = inet_aton($host) or die "No such host: $host";

# Get a printable IP address from the in_addr_t type returned by inet_aton().
$ip = join('.', unpack('C4', $iaddr));

# Now that the port value is a number, and the host (if it was originally a
# name) has been resolved to an IP address, then print a status header like
# the real ping does.
# print "AJP PING $host ($ip) port $port\n" ;

my $paddr = sockaddr_in($port, $iaddr) or die $!;

# Grab the number for TCP out of /etc/protocols.
my $proto = getprotobyname 'tcp' ;

my $sock;

# PF_INET and SOCK_STREAM are constants imported by the Socket module.  They
# are the same as what is defined in sys/socket.h.
socket $sock, PF_INET, SOCK_STREAM, $proto or die "Can't create socket: $!";

# This is the ping packet.  For detailed documentation, see
# http://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
# I stole the exact byte sequence from
# http://sourceforge.net/project/shownotes.php?group_id=128058&release_id=438456
# instead of fully understanding the packet structure.
my $ping = pack 'C5'    # Format template.
    , 0x12, 0x34        # Magic number for server->container packets.
    , 0x00, 0x01        # 2 byte int length of payload.
    , 0x0A              # Type of packet. 10 = CPing.
;

# If the connection is closed, log a decent message.
$SIG{PIPE} = sub { $rc = $ERRORS{'CRITICAL'}; die "$host $ip $port $!"; };

my $pong = 0;

ualarm(0); 
ualarm($timeout);

$connect_start = [gettimeofday];
connect $sock, $paddr or die "$host $ip $port $!";
$connect_done = tv_interval ( $connect_start,[gettimeofday]);

ualarm(0); 
ualarm($timeout);

$syswrite_start = [gettimeofday];
syswrite $sock, $ping or die "$host $ip $port $!";
$syswrite_done = tv_interval ( $syswrite_start, [gettimeofday]);

ualarm(0); 
ualarm($timeout);

$sysread_start = [gettimeofday];
sysread $sock, $pong, 5 or die "$host $ip $port $!";
$sysread_done = tv_interval ( $sysread_start , [gettimeofday]);

ualarm(0); 

#printf ("connect  Time: %f\n",$connect_done);
#printf ("syswrite Time: %f\n",$syswrite_done);
#printf ("sysread  Time: %f\n",$sysread_done);


# print 'Sent:     ';
# for my $value (unpack 'C5', $ping) {
#     printf '%02d ', $value;
# }
# print "\n";

# print 'Received: ';
# for my $value (unpack 'C5', $pong) {
#     printf '%02d ', $value;
# }
# print "\n";

close $sock or warn $!;

# This is the expected pong packet.  That is, this is what Tomcat sends back
# to indicate that it is operating OK.
my $expected = pack 'C5'    # Format template.
    , 0x41, 0x42            # Magic number for container->server packets.
    , 0x00, 0x01            # 2 byte int length of payload.
    , 0x09                  # Type of packet. 9 = CPong reply.
;

#print 'Expected: ';
#for my $value (unpack 'C5', $expected) {
#    printf '%02d ', $value;
#}
#print "\n";

if ($pong eq $expected) {
#    print "Server pong OK.\n";
    $good_answer = 1;
}

END {

  exit $ERRORS{'UNKNOWN'} if ! defined $ip;
  
  if ( ! defined $mode_ping ) {
    if ( defined $timeouted ){
      printf("CRITICAL - Timedout | "); 
      $rc = $ERRORS{"CRITICAL"};
    }elsif(  ! defined $good_answer ){
      printf("CRITICAL - Protocol missmatch | "); 
      $rc = $ERRORS{'CRITICAL'};
    }else{
      printf("OK - AJP | "); 
      $rc = $ERRORS{'OK'};
    }
  }else{
    printf ("%s ",strftime("%Y-%m-%d %T",localtime()));
  }
  
  printf ("host %s ip %s port %s ",$host,$ip,$port);
  printf ("connect %f ",$connect_done);
  printf ("syswrite %f ",$syswrite_done);
  printf ("sysread %f ",$sysread_done);
  printf ("timeouted %d ", defined $timeouted?$timeouted:0);
  printf ("timeout %d ",$timeout);
  printf ("good_answer %d ", defined $good_answer?$good_answer:0);
  printf ("\n");
  
  exit $rc;
}; 
#print "Server pong FAILED.\n";
exit $rc;
