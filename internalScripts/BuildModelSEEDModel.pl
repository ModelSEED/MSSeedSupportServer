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
my $job;
if (-e $ARGV[0]) {
	my $filename = $ARGV[0];
	open( my $fh, "<", $filename."jobfile.json");
	my $job;
	{
	    local $/;
	    my $str = <$fh>;
	    $job = decode_json $str;
	}
	close($fh);
} else {
	$job->{jobdata}->{owner} = $ARGV[0];
	$job->{jobdata}->{genome} = $ARGV[1];
	$job->{wsurl} = $ARGV[2];
	$job->{auth} = $ARGV[3];
	$job->{accounttype} = $ARGV[4];
}

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
	$fbaserv->queue_gapfill_model({
		model => "Seed".$job->{jobdata}->{genome},
		integrate_solution => 1,
		workspace => $job->{jobdata}->{owner},
		auth => $job->{auth},
	});
}

1;
