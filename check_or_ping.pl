#!/usr/bin/perl -w

# thanks to jffry for his initial code.
# http://www.perlmonks.org/?node_id=766945
#
# Author: jffry on Nov 18, 2011 at 22:11 UTC
# Author: Aleksandar Lazic 2015 05

use warnings;
use strict;
#use Socket qw( PF_INET SOCK_STREAM getaddrinfo getnameinfo AI_CANONNAME EAI_NONAME IPPROTO_TCP AF_INET AF_INET6 sockaddr_in inet_ntop);
use Socket qw (:all);
use Time::HiRes qw( time ualarm gettimeofday tv_interval );
use POSIX qw (strftime);
use Getopt::Long;

# unbufferd output
# $|=1;

our $version = '2.0';

# Icinga/Nagios return codes
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# By default this script works in ping mode
our %MODES = ('AJPPing'   => 0,
              'AJPCheck'  => 1,
              'HTTPPing'  => 2,
              'HTTPCheck' => 3,
              # generic ping
              'GPing'     => 4,
              'GCheck'    => 5
             );

our %by_value;

while (our ($key, $value) = each %MODES) {
        $by_value{$value} = $key;
    }

our $d_mode = $MODES{'AJPPing'};

our $d_host    = 'localhost';
our $d_port    = '8009';
our $d_timeout = 100000; # 100 milli seconds
our $timeouted   = undef;
our $good_answer = undef ;
our $ip = undef ;
our $error_connect = undef;

# hints for getaddrinfo
our $hints = {};
$hints->{'socktype'} = SOCK_STREAM;
$hints->{'flags'}    = AI_CANONNAME;

our $connect_start  = -0.01;
our $connect_done   = -0.01;
our $syswrite_start = -0.01;
our $syswrite_done  = -0.01;
our $sysread_start  = -0.01;
our $sysread_done   = -0.01;

# options variables

our $o_help = undef;
our $o_mode = undef; 
our $o_version = undef;
our $o_host    = undef;
our $o_port    = undef;
our $o_timeout = undef; 
our $o_verbose = undef;

our $data_send = undef;
our $data_recv = undef;
our $data_length = undef;
our $data_expected = undef;

our $rc = $ERRORS{'OK'};

handle_call_args();

if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'AJPPing'})){
  ($data_length,$data_send,$data_expected) = build_ajp_packets();
} elsif ( ($o_mode == $MODES{'GCheck'}) or ($o_mode == $MODES{'GPing'})){
  ($data_length,$data_send,$data_expected) = build_random_packets();
} elsif ( ($o_mode == $MODES{'HTTPCheck'}) or ($o_mode == $MODES{'HTTPPing'})){
  ($data_length,$data_send,$data_expected) = build_http_packets();
}else{
  print "\n Unknown Mode $MODES{$o_mode} \n\n";
  print_usage();
  exit $ERRORS{'UNKNOWN'};
}

local $SIG{ALRM} = sub { 
  $timeouted = 1;
  die "$o_host $ip $o_port $!";
}; 

# If the connection is closed, log a decent message.
$SIG{PIPE} = sub { 
  $rc = $ERRORS{'CRITICAL'};
  die "SIG{PIPE} $o_host $ip $o_port $!";
};

# If the port has anything other than numbers, assume it is an /etc/services
# name.
if ($o_port =~ /\D/) {
    $o_port = getservbyname $o_port, 'tcp' ;
    die "Bad port: $o_port" unless $o_port;
}

our ($err, @res) = getaddrinfo($o_host,$o_port,$hints);

if ( $err == EAI_NONAME ){
  print "$o_host could not be resolved: $err\n";
  exit $ERRORS{'CRITICAL'};
}elsif( $err ) {
  print "getaddrinfo error: $err\n";
  exit $ERRORS{'CRITICAL'};
}

#use Data::Dumper;
#print Dumper(@res);
# $VAR1 = {
#          'protocol' => 6,
#          'canonname' => 'external.none.at',
#          'addr' => 'I	is',
#          'socktype' => 1,
#          'family' => 2
#        };

our ( $errr, $port );

foreach our $entry (@res){
  print_info($entry);
  do_the_work($o_timeout,$entry);
  ( $errr, $ip, $port ) = getnameinfo($entry->{'addr'});
  print "( $errr, $ip, $port )\n";
}
exit;

# Now that the port value is a number, and the host (if it was originally a
# name) has been resolved to an IP address, then print a status header like
# the real ping does.
print "$0 $o_host ($ip) port $o_port\n" if defined $o_verbose;


if ( defined $o_verbose ){
  printf ("connect  Time: %f\n",$connect_done);
  printf ("syswrite Time: %f\n",$syswrite_done);
  printf ("sysread  Time: %f\n",$sysread_done);

  if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'AJPPing'})){
    print_ajp_verbose($data_send,$data_recv,$data_expected);
  }# end if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'AJPPing'}))
  elsif ( ($o_mode == $MODES{'HTTPCheck'}) or ($o_mode == $MODES{'HTTPPing'})){
    print_http_verbose($data_send,$data_recv,$data_expected);
  }# end if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'AJPPing'}))
} # end if ( defined $o_verbose )



if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'AJPPing'})){
  if ($data_recv eq $data_expected) {
  #    print "Server pong OK.\n";
    $good_answer = 1;
  }
}elsif ( ($o_mode == $MODES{'HTTPCheck'}) or ($o_mode == $MODES{'HTTPPing'})){
  if ($data_recv =~ /$data_expected/) {
  #    print "Server pong OK.\n";
    $good_answer = 1;
  }
}

END {

  exit $ERRORS{'UNKNOWN'} if ! defined $ip;
  exit $ERRORS{'CRITICAL'} if defined $error_connect;
  
  if ( ($o_mode == $MODES{'AJPCheck'}) or ($o_mode == $MODES{'GCheck'}) or ($o_mode == $MODES{'HTTPCheck'}) ) {
    if ( defined $timeouted ){
      printf("CRITICAL - Timedout | "); 
      $rc = $ERRORS{"CRITICAL"};
    }elsif( ! ($o_mode == $MODES{'GCheck'}) and  ! defined $good_answer ){
      printf("CRITICAL - Protocol missmatch | "); 
      $rc = $ERRORS{'CRITICAL'};
    }else{
      printf("OK - %s | ", $by_value{$o_mode}); 
      $rc = $ERRORS{'OK'};
    }
  }elsif ( ($o_mode == $MODES{'AJPPing'}) or ($o_mode == $MODES{'GPing'}) or ($o_mode == $MODES{'HTTPPing'})) {
    printf ("%s ",strftime("%Y-%m-%d %T",localtime()));
  }
  
  printf ("host %s ip %s port %s ",$o_host,$ip,$o_port);
  printf ("connect %f ",$connect_done);
  printf ("syswrite %f ",$syswrite_done);
  printf ("sysread %f ",$sysread_done);
  printf ("timeouted %d ", defined $timeouted?$timeouted:0);
  printf ("timeout %d ",$o_timeout);
  printf ("good_answer %d ", defined $good_answer?$good_answer:0);
  printf ("\n");
  
  exit $rc;
}; 
#print "Server pong FAILED.\n";
exit $rc;

############# SUBs #############

sub handle_call_args {
    Getopt::Long::Configure ("bundling");
    GetOptions(
        'h'    => \$o_help,            'help'          => \$o_help,
        'H:s'  => \$o_host,            'hostname:s'    => \$o_host,
        'p:i'  => \$o_port,            'port:i'        => \$o_port,
        't:i'  => \$o_timeout,         'timeout:i'     => \$o_timeout,
        'V'    => \$o_version,         'version'       => \$o_version,
        'm:s'  => \$o_mode,            'mode:s'        => \$o_mode,
        'v'    => \$o_verbose,         'verbose'       => \$o_verbose,
    );
    if (defined ($o_help)) {
      help(); 
      exit $ERRORS{"UNKNOWN"}
    }
    if (defined($o_version)) {
      show_versioninfo();
      exit $ERRORS{"UNKNOWN"}
    };
    # Check host attribute
    if ( ! defined($o_host) ) {
      print "\n MISSING: host \n";
      print_usage();
      exit $ERRORS{"UNKNOWN"}
    };
    # Check port attribute
    if ( ! defined($o_port) ) {
      $o_port = $d_port;
    };

    # use default timeout if none given
    if ( ! defined($o_timeout) ) {
      $o_timeout = $d_timeout;
    };

    # use default mode if none given
    if ( ! defined($o_mode) ) {
      $o_mode = $d_mode;
    } else {
      if ( ! exists $MODES{$o_mode} ){
        print "\n Unknown Mode $o_mode \n\n";
        help();
        exit $ERRORS{'UNKNOWN'};
      }

      $o_mode = $MODES{$o_mode};

    };
}

sub help {
   print "\n $0 ",$version,"\n\n";
   print "GPL licence, (c)2015 Aleksandar Lazic\n\n";
   print_usage();
   print <<EOT;
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check 
-p, --port=PORT
   Remote port which should be checked (Default: $d_port)
-t, --timeout=INTEGER
   timeout in microseconds (Default: $d_timeout)
-m, --mode=MODE-STRING
   The modus for this program (Default: $by_value{$d_mode})
-v, --verbose
   write more info output

-V, --version
   prints version number

Note :
  The script will return 
    OK if we are able to connect, write and read from the remote server,
    CRITICAL if any error occur's
    UNKNOWN for any missing parameter

EOT
  print "Available Modes are:\n";

  foreach (sort keys %MODES){
    printf("%10s => %d\n", $_, $MODES{$_});
  }
  print "\n";
}

sub print_usage {
    print "Usage: $0 -H <host> -p <port> [ -m <mode> ] [-t <timeout>] [-V]\n";
}

sub show_versioninfo { print "$0 version : $version\n"; }

sub build_ajp_packets{

  # protocol variables
  our $ajp_ping = undef;
  our $ajp_expected = undef;
  our $ajp_length = 5;

  # This is the ping packet.  For detailed documentation, see
  # http://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
  # I stole the exact byte sequence from
  # http://sourceforge.net/project/shownotes.php?group_id=128058&release_id=438456
  # instead of fully understanding the packet structure.
  $ajp_ping = pack 'C5'    # Format template.
      , 0x12, 0x34        # Magic number for server->container packets.
      , 0x00, 0x01        # 2 byte int length of payload.
      , 0x0A              # Type of packet. 10 = CPing.
  ;

  # This is the expected pong packet.  That is, this is what Tomcat sends back
  # to indicate that it is operating OK.
  $ajp_expected = pack 'C5'    # Format template.
      , 0x41, 0x42            # Magic number for container->server packets.
      , 0x00, 0x01            # 2 byte int length of payload.
      , 0x09                  # Type of packet. 9 = CPong reply.
  ;

  return ($ajp_length,$ajp_ping,$ajp_expected);
} # end build_ajp_packets{

sub print_ajp_verbose {

    our ($ajp_send,$ajp_recv,$ajp_expected) = @_;

    print 'Sent:     ';
    for my $value (unpack 'C5', $ajp_send) {
      printf '%02d ', $value;
    }
    print "\n";

    print 'Received: ';
    for my $value (unpack 'C5', $ajp_recv) {
      printf '%02d ', $value;
    }
    print "\n";
    print 'Expected: ';
    for my $value (unpack 'C5', $ajp_expected) {
      printf '%02d ', $value;
    }
    print "\n";
} # end print_ajp_verbose

sub build_http_packets{

  our $http_ping = "GET / HTTP/1.1\nUser-Agent: check_and_status/$version\nHost: $o_host\n\n";
  our $http_expected = "^HTTP/";
  our $http_length = length $http_ping;

  return ($http_length,$http_ping,$http_expected);
} #end build_http_packets

sub print_http_verbose{

  our ($http_send,$http_recv,$http_expected) = @_;

  print "Sent:     \n$http_send<<<\n";
  print "Received: \n$http_recv\n>>>\n";
  print "Expected: $http_expected\n";
  
}

sub build_random_packets{

  # ($data_length,$data_send,$data_expected) = build_random_packets();
  our $rand_length = 10;
  our $rand_ping = rand($rand_length);

  return ($rand_length,$rand_ping,undef);
} # end build_random_packets

sub do_the_work{

  our ( $timeout , $entry ) = @_;

  our $sock ;

  # PF_INET and SOCK_STREAM are constants imported by the Socket module.  They
  # are the same as what is defined in sys/socket.h.
  socket $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP or die "Can't create socket: $!";

  ualarm(0); 
  ualarm($timeout);

  $connect_start = [gettimeofday];
  if ( ! connect $sock, $entry->{'addr'} ) {
    $error_connect = 1;
    die "$o_host $ip $o_port $!";
  }

  $connect_done = tv_interval ( $connect_start,[gettimeofday]);

  ualarm(0); 
  ualarm($timeout);

  $syswrite_start = [gettimeofday];
  syswrite $sock, $data_send or die "$o_host $ip $o_port $!";
  $syswrite_done = tv_interval ( $syswrite_start, [gettimeofday]);

  ualarm(0); 
  ualarm($timeout);

  $sysread_start = [gettimeofday];
  sysread $sock, $data_recv, $data_length or die "$o_host $ip $o_port $!";
  $sysread_done = tv_interval ( $sysread_start , [gettimeofday]);

  ualarm(0); 

  close $sock or warn " can't close socket: $!";

} # end do_the_work

sub print_info {

  our ($entry) = @_;

  if ($entry->{'family'} == AF_INET) {
 
    # port is always 0 when resolving a hostname
    my ($err, $addr4, $port) = getnameinfo($entry->{'addr'});
    print "($err, $addr4, $port)\n";
 
    print "IPv4:\n";
    print " $addr4, ";
    print "port: $port, ";
    print "protocol: $entry->{'protocol'}, socktype: $entry->{'socktype'}, canonname: $entry->{'canonname'}\n";
  } else {
 
    my ($port, $addr6, $scope_id, $flowinfo) = sockaddr_in6($_->{addr});
    print "IPv6:\n";
    print "  " . inet_ntop(AF_INET6, $addr6) . ", port: $port, protocol: $entry->{'protocol'}, socktype: $entry->{'socktype'}, (scope id: $scope_id, flowinfo: $flowinfo), canonname: $entry->{'canonname'}\n";
  }
}# end print_info
