#!/usr/bin/perl -w
#
# Nagisk
# Nagios take a look on Asterisk
# Nicolas Hennion - GPLv3
# v1.0 - 10/2008
#

use Getopt::Std;
use strict;

# Options: Can be change
########################

# Globals variables
my $asterisk_bin="/usr/bin/sudo /usr/sbin/asterisk";
my $asterisk_option="-rx";
my $asterisk_command_version="show version";
my $asterisk_command_peers="sip show peers";
my $asterisk_command_channels="sip show channels";

# Options: Can NOT be change
############################

# version
my $version="1.0";

use vars qw( %opts);
my $return=3; 	# Default return code: Unknown = 3
my $output="";

# Functions
###########

sub printsyntax() {
  print("Syntax:\t $0 [-hv] [-c OPT]\n"
	. "-c version: Display the Asterisk version\n"
	. "-c peers: Display the SIP peers status\n"
	. "-c channels: Display the SIP channels status\n"
	. "-h: Display the help and exit\n"
	. "-v: Display version and exit\n");
}

sub printversion() {
  print("$0 $version \n");
}


# Main program
###############

# Get options from the command line
my $asterisk_command=$asterisk_command_version;
my $valid_opts='hvc:';
getopts("$valid_opts", \%opts) or (printsyntax() and exit($return));
for my $option (keys %opts) {
  my $value=$opts{$option};
  if ($option eq 'h') {
    printsyntax();
    exit($return);
  } elsif ($option eq 'v') {
    printversion();
    exit($return);
  } elsif ($option eq 'c') {
    if ($value eq "channels") {
      $asterisk_command=$asterisk_command_channels;
    } elsif ($value eq "peers") {
      $asterisk_command=$asterisk_command_peers;
    } elsif ($value eq "version") {
      $asterisk_command=$asterisk_command_version;
    } else {
      printsyntax();
      exit($return);
    }
  } 
} 

# Execute the asterisk command and analyse the result
if ($asterisk_command eq $asterisk_command_channels) {
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
    if (/SIP\ channel/) {
      $return=0;
      $output=$_;
    }
  }
} elsif ($asterisk_command eq $asterisk_command_peers) {
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
    if (/sip\ peers/) {
      $return=0;
      $output=$_;
    }
  }
} elsif ($asterisk_command eq $asterisk_command_version) {
  $return=2;
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
    if (/Asterisk/) {
      $return=0;
      $output=$_;
    }
  }
}

# Print the output on STDOUT
print $output;

# Nagios Return Codes
# OK = 0 / Warning = 1 / Critical = 2 / Unknown = 3 
exit($return);