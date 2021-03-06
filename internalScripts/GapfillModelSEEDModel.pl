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

$|=1;
if (!defined($ARGV[0])) {
	exit(0);
}
my $filename = $ARGV[0];
open( my $fh, "<", $filename."jobfile.json");
my $job;
{
    local $/;
    my $str = <$fh>;
    $job = decode_json $str;
}
close($fh);

my $wserv = Bio::KBase::workspaceService::Client->new($job->{wsurl});
my $fbaserv = Bio::KBase::fbaModelServices::Impl->new({accounttype => $job->{accounttype},"workspace-url" => $job->{wsurl}});

#Creating the workspace if needed
my $wsmeta;
eval {
	$wsmeta = $wserv->get_workspacemeta({
		workspace => $job->{jobdata}->{owner},
		auth => $job->{auth},
	});
};
if (!defined($wsmeta)) {
	$wserv->create_workspace({
		workspace => $job->{jobdata}->{owner},
		default_permission => "n",
		auth => $job->{auth}
	});
}

#Loading the genome if needed
my $objmeta;
eval {
	$objmeta = $wserv->get_objectmeta({
		id => $job->{jobdata}->{genome},
		type => "Genome",
		workspace => $job->{jobdata}->{owner},
		auth => $job->{auth},
	});
};
if (!defined($objmeta)) {
	$fbaserv->genome_to_workspace({
		genome => $job->{jobdata}->{genome},
		workspace => $job->{jobdata}->{owner},
		sourceLogin => "chenry",
		sourcePassword => "hello824",
		source => "rast",
		auth => $job->{auth},
		overwrite => 1
	});
}

#Building model for genome
$objmeta = undef;
eval {
	$objmeta = $wserv->get_objectmeta({
		id => "Seed".$job->{jobdata}->{genome},
		type => "Model",
		workspace => $job->{jobdata}->{owner},
		auth => $job->{auth},
	});
};
if (!defined($objmeta)) {
	$fbaserv->genome_to_fbamodel({
		genome => $job->{jobdata}->{genome},
		workspace => $job->{jobdata}->{owner},
		model => "Seed".$job->{jobdata}->{genome},
		auth => $job->{auth},
	});
}

#Queuing gapfilling
my $gfjob = $fbaserv->queue_gapfill_model({
	model => "Seed".$job->{jobdata}->{genome},
	workspace => $job->{jobdata}->{owner},
	integrate_solution => 1,
	auth => $job->{auth},
});
my $gfjobout;
eval {
	$gfjobout = $fbaserv->run_job({
		job => $gfjob->{id},
		auth => $job->{auth},
	});
};
if (!defined($gfjobout)) {
	$gfjob = $fbaserv->queue_gapfill_model({
		model => "Seed".$job->{jobdata}->{genome},
		workspace => $job->{jobdata}->{owner},
		timePerSolution => 86400,
		totalTimeLimit => 86000,
		integrate_solution => 1,
		auth => $job->{auth},
	});
	$gfjobout = $fbaserv->run_job({
		job => $gfjob->{id},
		auth => $job->{auth},
	});
}

#Exporting model
my $modeldata = $fbaserv->export_fbamodel({
	model => "Seed".$job->{jobdata}->{genome},
	workspace => $job->{jobdata}->{owner},
	format => "modelseed",
	auth => $job->{auth},
});
my $lines = [split(/\n/,$modeldata)];
open(my $fh, ">", $directory."model.mdl") || return;
open(my $fhb, ">", $directory."biomass.bof") || return;
my $bio = 0;
for (my $i=0; $i < @{$lines};$i++) {
	if ($lines->[$i] =~ m/NAME\t/) {
		$bio = 1;
	}
	if ($bio == 1) {
		print $fhb $lines->[$i]."\n";
	} else {
		print $fh $lines->[$i]."\n";
	}
}
close($fh);
close($fhb);

#Importing model
system("perl ModelDriver.pl mdlloadmodel Seed".$job->{jobdata}->{genome}.
	"?".$job->{jobdata}->{genome}.
	"?0?".$directory."model.mdl".
	"?".$directory."biomass.bof".
	"?".$job->{jobdata}->{owner}.
	"?0?1"
);

1;
