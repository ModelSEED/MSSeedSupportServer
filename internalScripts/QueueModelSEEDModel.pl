#!/usr/bin/perl -w

use strict;
use warnings;
use JSON::XS;
use Test::More;
use Data::Dumper;
use File::Temp qw(tempfile);
use LWP::Simple;
use Config::Simple;
use Bio::KBase::fbaModelServices::Impl;
use Bio::KBase::workspaceService::Client;

my $c = Config::Simple->new();
$c->read("/homes/chenry/kbase/deploy/MSQueue.ini");
$|=1;
if (!defined($ARGV[0])) {
	exit(0);
}
my $wserv = Bio::KBase::workspaceService::Client->new($c->param("modelseed.wsurl"));
my $owners = [];
my $genomes = [];
my $directory;
if ($ARGV[0] eq "modelseed") {
	
} else {
	$genomes->[0] = $ARGV[0];
	$owners->[0] = $ARGV[1];
	if (defined($ARGV[2])) {
		$directory = $ARGV[2];
	}
}
if (defined($directory) && -d $directory) {
	my $JSON = JSON::XS->new();
    my $data = $JSON->encode({
		wsurl => $c->param("modelseed.wsurl"),
		owner => $c->param("modelseed.owner"),
		status => "test",
		queuetime => DateTime->now()->datetime(),
		id => "job.0",
		accounttype => "seed",
		auth => $c->param("modelseed.auth"),
		"state" => undef,
		type => "ModelSEED",
		queuecommand => "QueueModelSEED",
		jobdata => {
			owner => $owners->[0],
			genome => $genomes->[0],
		}
	});
	if (-e $directory."jobfile.json") {
		unlink $directory."jobfile.json";
	}
	if (-e $directory."pid") {
		unlink $directory."pid";
	}
	open(my $fh, ">", $directory."jobfile.json") || return;
	print $fh $data;
	close($fh);
} else {
	for (my $i=0; $i < @{$genomes}; $i++) {
		$wserv->queue_job({
			auth => $c->param("modelseed.auth"),
			"state" => undef,
			type => "ModelSEED",
			queuecommand => "QueueModelSEED",
			jobdata => {
				owner => $owners->[$i],
				genome => $genomes->[$i],
			}
		});
	}
}

1;
