#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Config::Simple;
use File::Path;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Client;

my $config = $ARGV[0];
my $filename = $ARGV[1];
if (!defined($config)) {
	print STDERR "No config file provided!\n";
	exit(-1);
}
if (!-e $config) {
	print STDERR "Config file ".$config." not found!\n";
	exit(-1);
}
my $c = Config::Simple->new();
$c->read($config);

my $wserv = Bio::KBase::workspaceService::Client->new($c->param("kbclientconfig.wsurl"));
my $genomes = $wserv->list_workspace_objects({
	type => "Genome",
	workspace => "coremodels",
	auth => $c->param("kbclientconfig.auth")
});

open (my $fh, ">", $filename) || die "Couldn't open $filename: $!";
#for (my $i=0; $i < @{$genomes}; $i++) {
for (my $i=0; $i < 10; $i++) {
	my $genome = $genomes->[$i]->[0];
	my $obj = $wserv->get_object({
		id => $genome,
		type => "Genome",
		workspace => "coremodels",
		auth => $c->param("kbclientconfig.auth")
	});
	for (my $j=0; $j < @{$obj->{data}->{features}}; $j++) {
		my $feature = $obj->{data}->{features}->[$j];
		if (defined($feature->{protein_translation})) {
			print $fh ">".$feature->{id}."\n";
			my $sequence = $feature->{protein_translation};
			$sequence =~ s/([A-Z]{70})/$1\n/g;
			print $fh $sequence."\n";
		}
	}	
}
close($fh);
	
1;
