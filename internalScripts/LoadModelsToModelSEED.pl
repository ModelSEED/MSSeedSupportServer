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
use Bio::KBase::fbaModelServices::Client;
use Bio::ModelSEED::MSSeedSupportServer::Impl;

my $wserv = Bio::KBase::workspaceService::Client->new("http://bio-data-1.mcs.anl.gov/services/ms_workspace");
my $fbaserv = Bio::KBase::fbaModelServices::Client->new("http://bio-data-1.mcs.anl.gov/services/ms_fba");
require "Bio/KBase/fbaModelServices/Impl.pm";
$fbaserv = Bio::KBase::fbaModelServices::Impl->new({accounttype => "seed",workspace => $wserv});
my $mssserv = Bio::ModelSEED::MSSeedSupportServer::Impl->new();

my $mdldata = $fbaserv->export_fbamodel({
	auth => "chenry Ko3BA9yMnMj2k",
	model => "Seed326297.9",
	format => "modelseed",
	workspace => "chenry"
});

my $input = {
	genome => {
		id => "326297.9",
	},
	owner => "chenry",
	reactions => [],
	biomass => undef,
	cellwalltype => undef,
	status => 1
};
my $lines = [split(/\n/,$mdldata)];
my $i;
for ($i=2; $i < @{$lines}; $i++) {
	my $line = $lines->[$i];
	if ($line =~ m/^NAME/) {
		last;	
	} else {
		my $row = [split(/;/,$line)];
		if (defined($row->[4])) {
			push(@{$input->{reactions}},{
				id => $row->[0],
				direction => $row->[1],
				compartment => $row->[2],
				pegs => $row->[3],
				equation => $row->[4]
			});
		}
	}
}
if ($lines->[$i+1] =~ m/GramNegative/) {
	$input->{cellwalltype} = "Gram negative";
} else {
	$input->{cellwalltype} = "Gram positive";
}
if ($lines->[$i+2] =~ m/EQUATION\t(.+)/) {
	$input->{biomass} = $1;
}

$mssserv->load_model_to_modelseed($input);

1;
