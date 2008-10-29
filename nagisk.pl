#!/usr/bin/perl -w
#
# Nagisk
# Nagios take a look on Asterisk
# Nicolas Hennion - GPLv3
# v1.1 - 11/2008
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
my $asterisk_command_zaptel="zap show status";
my $asterisk_command_span="zap show status";
my $asterisk_span_number=1;

# Options: Can NOT be change
############################

# version
my $version="1.1";

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
	. "-c zaptel: Display the status of the zaptel card\n"		
	. "-c span: Display the status of a specific span (set with -s option)\n"
	. "-s <span number>: Set the span number (default is 1)\n"			
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
my $asterisk_command_tag="version";
my $valid_opts='hvc:s:';
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
  	$asterisk_command_tag=$value;
    if ($value eq "channels") {
      $asterisk_command=$asterisk_command_channels;
    } elsif ($value eq "peers") {
      $asterisk_command=$asterisk_command_peers;
    } elsif ($value eq "zaptel") {
      $asterisk_command=$asterisk_command_zaptel;
    } elsif ($value eq "span") {
      $asterisk_command=$asterisk_command_span;
    } elsif ($value eq "version") {
      $asterisk_command=$asterisk_command_version;      
    } else {
      printsyntax();
      exit($return);
    }
  } elsif ($option eq 's') {
  	# Set the SPAN number (with option -c span)
    $asterisk_span_number = $value;
  } else {
	printsyntax();
	exit($return);
  }
} 

# Execute the asterisk command and analyse the result
if ($asterisk_command_tag eq "channels") {
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
    if (/SIP\ channel/) {
      $return=0;
      $output=$_;
    }
  }
} elsif ($asterisk_command_tag eq "peers") {
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
    if (/sip\ peers/) {
      $return=0;
      $output=$_;
    }
  }
} elsif ($asterisk_command_tag eq "zaptel") {
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {  	
  	if (/Description/) {
  		$return=0;
        $output="Zaptel card detected\n";
        last;
  	}  	
    if (/No\ such\ command/) {
      $return=2;
      $output="Zaptel card not detected\n";
      last;
    }
  }
} elsif ($asterisk_command_tag eq "span") {  
  my $span=0;
  foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
  	if (/Description/) {
  		$span=1;
  		next;
  	}
    if (/No\ such\ command/) {
      $return=2;
      $output="Zaptel card not detected\n";
      last;
    }
  	if ($span == $asterisk_span_number) {
  		if (/OK/) {
  			$return=0;
  			$output="Span $asterisk_span_number OK\n";  			
  		} else {
  			$return=2; 
  			$output="Span $asterisk_span_number not ok\n";
  		}  		
  		last;
  	}
  	$span++;  	
  }
  if ($span > $asterisk_span_number) {
  	$return=1;
  	$output="Span $asterisk_span_number did not exist\n";
  }
} elsif ($asterisk_command_tag eq "version") {
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