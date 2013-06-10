#!/usr/bin/perl -w

use strict;
use warnings;
use JSON::XS;
use Test::More;
use Data::Dumper;
use File::Temp qw(tempfile);
use LWP::Simple;
use Config::Simple;
use Bio::KBase::workspaceService::Client;

my $wserv = Bio::KBase::workspaceService::Client->new("http://bio-data-1.mcs.anl.gov/services/ms_workspace");

if (!defined($ARGV[0])) {
	exit(0);
}
my $auth = $ARGV[1];
open(my $fh, "<", $ARGV[0]) || return;
my @lines = <$fh>;
close($fh);
for (my $i=0; $i < @lines;$i++) {
	my $line = $lines[$i];
	#print $line."\n";
	my $row = [split(/\t/,$line)];
	if ($row->[5] eq "-2") {
		$wserv->queue_job({
			auth => $auth,
			"state" => undef,
			type => "MSBuildModel",
			queuecommand => "QueueModelSEED",
			jobdata => {
				owner => $row->[17],
				genome => $row->[10],
			}
		});
	}
}

1;
