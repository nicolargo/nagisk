#!/usr/bin/perl -w
#
# Nagisk
# Nagios take a look on Asterisk
# Nicolas Hennion - GPLv3
#
# Modified by :
# Frederic (03/2011)
# ManuxFR (11/2011)
# manuel@linux-home.at (8/2012)[dahdi,pri checks added]
#------------------------------------------------------------------------------
use Getopt::Std;
use strict;

#------------------------------------------------------------------------------
# Options: Can be changed
#------------------------------------------------------------------------------

# Globals variables
my $asterisk_bin                = "/usr/bin/sudo /usr/sbin/asterisk";
my $asterisk_option             = "-rx";
my $asterisk_command_version    = "core show version";
my $asterisk_command_peers      = "sip show peers";
my $asterisk_command_peer       = "sip show peer";
my $asterisk_command_konference = "konference show stats";
my $asterisk_command_jabber     = "jabber show connected";
my $asterisk_command_channels   = "core show channels";
my $asterisk_command_zaptel     = "zap show status";
my $asterisk_command_span       = "zap show status";
my $asterisk_command_dahdi      = "dahdi show status";
my $asterisk_command_dahdi_span = "dahdi show status";
my $asterisk_command_pri_spans  = "pri show spans";
my $asterisk_command_pri_span   = "pri show span";
my $asterisk_span_number        = 1;
my $asterisk_peer_name          = "myowntelco";
my $asterisk_buddy_name         = "asterisk";
my $asterisk_warn_treshold      = "1000";
my $asterisk_crit_treshold      = "2000";
my $asterisk_command_registry	= "sip show registry";

#------------------------------------------------------------------------------
# Options: Can NOT be changed
#------------------------------------------------------------------------------

# version
my $version = "1.2.3";

use vars qw( %opts);

#------------------------- Return Codes Definitions --------------------------
# STATE = OK:
# The plugin was able to check the service and it appeared to be functioning
# properly.
#
# STATE = WARNING:
# The plugin was able to check the service, but it appeared to be above
# some "warning" threshold or did not appear to be working properly.
#
# STATE = CRITICAL:
# The plugin detected that either the service was not running or it was above
# some "critical" threshold.
#
# STATE = UNKNOWN:
# Invalid command line arguments were supplied to the plugin or low-level
# failures internal to the plugin.
#------------------------------------------------------------------------------

my $STA_OK       = 0;
my $STA_WARNING  = 1;
my $STA_CRITICAL = 2;
my $STA_UNKNOWN  = 3;

my $STA_NOALERT = 10;
my $STA_ALERT   = 11;
my $STA_ERROR   = 12;

# Default return value for this plugin:
my $return = $STA_UNKNOWN;

my $output = "";

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

sub printsyntax() {
	print(  "Syntax:\t $0 [-hv] [-c OPT] [-s NB|-p NAME|-b BUDDY] [-w TRESH -x TRESH]\n"
		  . "-c version: Display the Asterisk version\n"
		  . "-c peers: Display the SIP peers status\n"
		  . "-c peer: Display the status of a particular peer\n"
		  . "-c channels: Display the channels status\n"
		  . "-c konference: Display nb of active conferences\n"
		  . "-c jabber: Display a jabber buddy status\n"
		  . "-c zaptel: Display the status of the zaptel card\n"
		  . "-c span: Display the status of a specific span (set with -s option)\n"
		  . "-c dahdi: Display the status of the dahdi card\n"
		  . "-c dahdi_span: Display the status from a span from the dahdi card\n"
		  . "-c pri_spans: Display the status of the pri spans\n"
		  . "-c pri_span: Display the status of a specific pri span (set with -s option)\n"
		  . "-c registry: Display the Hosts and the Registry\n"
		  . "-s <span number>: Set the span number (default is 1)\n"
		  . "-p <peer name>\n"
		  . "-b <buddy name>\n"
		  . "-w <warning treshold>\n"
		  . "-x <critical treshold>\n"
		  . "-h Display the help and exit\n"
		  . "-v Display version and exit\n");
}

sub printversion() {
	print("$0 $version \n");
}

sub checkAlert() {
	my ($value, $treshold) = @_;

	return $STA_NOALERT if ($treshold eq '');
	return $STA_ERROR if ($value !~ /^\-?[0-9]+$/);

	# e.g. "10"
	if ($treshold =~ /^(@?)(\-?[0-9]+)$/) {

		if ($1 ne '@' && ($value < 0 || $value > $2)) {
			return $STA_ALERT;
		} elsif ($1 eq '@' && ($value >= 0 && $value <= $2)) {
			return $STA_ALERT;
		} else {
			return $STA_NOALERT;
		}

		# e.g. "10:" || ":10" || "~:10" || "10:~"
	} elsif ($treshold =~ /^(@?)(~?)(:?)(\-?[0-9]+)(:?)(~?)$/) {

		if ($3 eq ':' && $5 eq ':') {
			return $STA_ERROR;
		} elsif ($2 eq '~' && $3 ne ':') {
			return $STA_ERROR;
		} elsif ($5 ne ':' && $6 eq '~') {
			return $STA_ERROR;
		} elsif ($2 eq '~' && $6 eq '~') {
			return $STA_ERROR;
		} elsif ($1 ne '@' && ($3 eq ':' && $value > $4)) {
			return $STA_ALERT;
		} elsif ($1 ne '@' && ($5 eq ':' && $value < $4)) {
			return $STA_ALERT;
		} elsif ($1 eq '@' && ($3 eq ':' && $value <= $4)) {
			return $STA_ALERT;
		} elsif ($1 eq '@' && ($5 eq ':' && $value >= $4)) {
			return $STA_ALERT;
		} else {
			return $STA_NOALERT;
		}

		# e.g. "10:20"
	} elsif ($treshold =~ /^(@?)(\-?[0-9]+):(\-?[0-9]+)$/) {

		if ($2 > $3) {
			return $STA_ERROR;
		} elsif ($1 ne '@' && ($value < $2 || $value > $3)) {
			return $STA_ALERT;
		} elsif ($1 eq '@' && ($value >= $2 && $value <= $3)) {
			return $STA_ALERT;
		} else {
			return $STA_NOALERT;
		}

	} else {
		return $STA_ERROR;
	}
}

sub setAlert() {
	my ($val, $wtresh, $ctresh) = @_;

	my $walert = &checkAlert($val, $wtresh);
	my $calert = &checkAlert($val, $ctresh);
	my $state;

	if ($walert == $STA_ALERT && $calert == $STA_ALERT) {
		$state = $STA_CRITICAL;
	} elsif ($walert == $STA_ALERT) {
		$state = $STA_WARNING;
	}
	$state = $STA_OK if ($walert == $STA_NOALERT);
	$state = $STA_UNKNOWN if ($walert == $STA_ERROR || $calert == $STA_ERROR);

	return $state;
}

#------------------------------------------------------------------------------
# Main program
#------------------------------------------------------------------------------

# --- Get options from the command line
my $asterisk_command     = $asterisk_command_version;
my $asterisk_command_tag = "version";
my $valid_opts           = 'hvc:s:p:b:w:x:';

getopts("$valid_opts", \%opts) or (printsyntax() and exit($return));

for my $option (keys %opts) {

	my $value = $opts{$option};

	if ($option eq 'h') {
		printsyntax();
		exit($return);

	} elsif ($option eq 'v') {
		printversion();
		exit($return);

	} elsif ($option eq 'c') {
		$asterisk_command_tag = $value;

		if ($value eq "channels") {
			$asterisk_command = $asterisk_command_channels;
		} elsif ($value eq "peers") {
			$asterisk_command = $asterisk_command_peers;
		} elsif ($value eq "peer") {
			$asterisk_command = $asterisk_command_peer;
		} elsif ($value eq "jabber") {
			$asterisk_command = $asterisk_command_jabber;
		} elsif ($value eq "konference") {
			$asterisk_command = $asterisk_command_konference;
		} elsif ($value eq "zaptel") {
			$asterisk_command = $asterisk_command_zaptel;
		} elsif ($value eq "span") {
			$asterisk_command = $asterisk_command_span;
		} elsif ($value eq "dahdi") {
			$asterisk_command = $asterisk_command_dahdi;
		} elsif ($value eq "dahdi_span") {
			$asterisk_command = $asterisk_command_dahdi_span;
		} elsif ($value eq "pri_spans") {
			$asterisk_command = $asterisk_command_pri_spans;
		} elsif ($value eq "pri_span") {
			$asterisk_command = $asterisk_command_pri_span;
		} elsif ($value eq "registry") {
			$asterisk_command = $asterisk_command_registry;

		} elsif ($value eq "version") {
			$asterisk_command = $asterisk_command_version;
		} else {
			printsyntax();
			exit($return);
		}

	} elsif ($option eq 's') {

		# Set the SPAN number (with option -c span)
		$asterisk_span_number = $value;

	} elsif ($option eq 'p') {

		# Set the PEER name (with option -c peer)
		$asterisk_peer_name = $value;

	} elsif ($option eq 'b') {

		# Set the BUDDY name (with option -c jabber)
		$asterisk_buddy_name = $value;

	} elsif ($option eq 'w') {

		# Set warning treshold
		$asterisk_warn_treshold = $value if ($value ne '' && $value ne '-x');

	} elsif ($option eq 'x') {

		# Set critical treshold
		$asterisk_crit_treshold = $value if ($value ne '');

	} else {
		printsyntax();
		exit($return);
	}
}

#------------------------------------------------------------------------------
# Execute the appropriate asterisk command and analyze the result
#------------------------------------------------------------------------------

# --- CHANNELS ---
# Output example: "45 active channels 20 active calls 174 calls processed"
#
if ($asterisk_command_tag eq "channels") {

	$return = $STA_CRITICAL;
	$output = "Error getting channels";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/channels/) {
			$output = $_;
		} elsif (/calls/) {
			$output .= $_;
		}
	}

	# Raise alert based on number of active channels
	$return = &setAlert($1, $asterisk_warn_treshold, $asterisk_crit_treshold)
	  if ($output =~ /^([0-9]+)\ active channels/);

   # --- PEERS ---
   # Output example: "2 sip peers [Monitored: 1 online, 0 offline Unmonitored: 0 online, 1 offline]"
   #
} elsif ($asterisk_command_tag eq "peers") {

	$return = $STA_CRITICAL;
	$output = "Error getting peers";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {

		if (/sip\ peers/) {
			$output = $_;
		}
	}

	# Raise alert based on number of Monitored Online peers
	$return = &setAlert($1, $asterisk_warn_treshold, $asterisk_crit_treshold)
	  if ($output =~ /Monitored: ([0-9]+)\ online/);

	# --- PEER ---
	# Output example: "myowntelco: OK (15 ms)"
	#
} elsif ($asterisk_command_tag eq "peer") {

	$return = $STA_CRITICAL;
	$output = "Error getting peer or unreachable: $asterisk_peer_name";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command $asterisk_peer_name\"`) {
		if (/Status.*:(.*)/) {
			$output = "$asterisk_peer_name: $1";
		}
	}

	# Raise alert based on number of milliseconds
	$return = &setAlert($1, $asterisk_warn_treshold, $asterisk_crit_treshold)
	  if ($output =~ /([0-9]+)\ ms/);

	# --- JABBER ---
	# Output example: "Buddy: freddy (Connected)"
	#
} elsif ($asterisk_command_tag eq "jabber") {

	$return = $STA_CRITICAL;
	$output = "Error getting buddy status: $asterisk_buddy_name";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command $asterisk_buddy_name\"`) {
		if (/User.*:\ +$asterisk_buddy_name\@.*\-\ +(Connected|Disconnected|Connecting)/) {
			$output = "Buddy: $asterisk_buddy_name ($1)";
		}
	}

	# Raise alert based on buddy status
	$return = $STA_CRITICAL if ($output =~ /Buddy:.*Disconnected/);
	$return = $STA_WARNING  if ($output =~ /Buddy:.*Connecting/);
	$return = $STA_OK       if ($output =~ /Buddy:.*Connected/);

	# --- KONFERENCE ---
	# Output example: "Active konferences: 5"
	#
} elsif ($asterisk_command_tag eq "konference") {

	$return = $STA_CRITICAL;
	$output = "Error getting active conferences";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/ACTIVE *\( *([0-9]+) *\)/) {
			$output = "Active konferences: $1";
		}
	}

	# Raise alert based on number of active conferences
	$return = &setAlert($1, $asterisk_warn_treshold, $asterisk_crit_treshold)
	  if ($output =~ /Active konferences: ([0-9]+)/);

	# --- ZAPTEL ---
	# Output example:
	#
} elsif ($asterisk_command_tag eq "zaptel") {

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/Description/) {
			$return = $STA_OK;
			$output = "Zaptel card detected\n";
			last;
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "Zaptel card not detected\n";
			last;
		}
	}
	
	# --- DAHDI ---
	# Output example: (./nagisk.pl -c dahdi -s 3)
	# B4XXP (PCI) Card 0 Span 1                RED     0      0      0      CCS AMI  YEL      0 db (CSU)/0-133 feet (DSX-1) 
	# B4XXP (PCI) Card 0 Span 2                RED     0      0      0      CCS AMI  YEL      0 db (CSU)/0-133 feet (DSX-1)  
	# B4XXP (PCI) Card 0 Span 3                OK      0      0      0      CCS AMI  YEL      0 db (CSU)/0-133 feet (DSX-1)
	# B4XXP (PCI) Card 0 Span 4                RED     0      0      0      CCS AMI  YEL      0 db (CSU)/0-133 feet (DSX-1)
	
} elsif ($asterisk_command_tag eq "dahdi") {

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/Card/) {
			$return = $STA_OK;
			$output .= "$_\n";
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "Error getting Dahdi status (dahdi show status), is a dahdi card connected?\n";
			last;
		}
	}
	
	# --- DAHDI SPAN ---
	# Output example: (./nagisk.pl -c dahdi -s 3) 
	# B4XXP (PCI) Card 0 Span 3                OK      0      0      0      CCS AMI  YEL      0 db (CSU)/0-133 feet (DSX-1)
	
} elsif ($asterisk_command_tag eq "dahdi_span") {

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\" | grep \"Span $asterisk_span_number\"`) {  

		if (/OK/) {
			$return = $STA_OK;
			$output = "$_\n";
			last;
		}
		if (/RED/) {
			$return = $STA_CRITICAL;
			$output = "$_\n";
			last;
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "Error getting Dahdi status (dahdi show status), is a dahdi card connected?\n";
			last;
		}
		
		$return = $STA_CRITICAL;
		$output = "Dahdi Span not found! (try \"dahdi show status\" in asterisk CLI.\n";
		last;
	}
	
	

	# --- SPAN ---
	# Output example:
	#
} elsif ($asterisk_command_tag eq "span") {
	my $span = 0;
	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/Description/) {
			$span = 1;
			next;
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "Zaptel card not detected\n";
			last;
		}
		if ($span == $asterisk_span_number) {
			if (/OK/) {
				$return = $STA_OK;
				$output = "Span $asterisk_span_number OK\n";
			} else {
				$return = $STA_CRITICAL;
				$output = "Span $asterisk_span_number not ok\n";
			}
			last;
		}
		$span++;
	}
	if ($span > $asterisk_span_number) {
		$return = 1;
		$output = "Span $asterisk_span_number did not exist\n";
	}
	
	# --- PRI SPANS ---
	# Output example: (./nagisk.pl -c pri_spans)
	# PRI span 1/0: Provisioned, In Alarm, Down, Active  
	# PRI span 2/0: Provisioned, In Alarm, Down, Active  
	# PRI span 3/0: Provisioned, Up, Active  
	# PRI span 4/0: Provisioned, In Alarm, Down, Active  
	
} elsif ($asterisk_command_tag eq "pri_spans") {
	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/PRI/) {
			$return = $STA_OK;
			$output .= "$_\n";	
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "LibPRI not found!\n";
			last;
		}
	}
	
	# --- PRI SPAN ---
	# Output example: (./nagisk.pl -c pri_span -s 3)
	# Status: Provisioned, Up, Active 
	#
} elsif ($asterisk_command_tag eq "pri_span") {
	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command $asterisk_span_number\"`) {
		
		#$output .= "$_\n";
		
		if (/Up/) {
			$return = $STA_OK;
			$output = "$_\n";
			last;
		}
		if (/Down/) {
			$return = $STA_CRITICAL;
			$output = "$_\n";
			last;
		}
		if (/No\ such\ command/) {
			$return = $STA_CRITICAL;
			$output = "LibPRI not found!\n";
			last;
		}
	}

	# --- REGISTRY ---
	# output example: 
	#	Host                                    dnsmgr Username       Refresh State      
	#	Trunk_SIP_Peer:5060                      N      username       105 Registered     
	#	1 SIP registrations.
}	elsif ($asterisk_command_tag eq "registry") {

	$return = $STA_CRITICAL;
	$output = "Trunk NOT OK";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/Registered/) {
			$return = $STA_OK;
			$output = "Trunk OK\n";
			last;
		}
	}	
	# --- VERSION ---
	# Output example: "Asterisk  1.8.4
	#
} elsif ($asterisk_command_tag eq "version") {

	$return = $STA_CRITICAL;
	$output = "Error getting version";

	foreach (`$asterisk_bin $asterisk_option \"$asterisk_command\"`) {
		if (/(Asterisk.*)\ built/) {
			$return = $STA_OK;
			$output = "$1";	
		}
	}
}

# --- Print the command output on STDOUT
$output =~ s/\r|\n/\ /g;
print $output;

# --- Return appropriate Nagios code
exit($return);
