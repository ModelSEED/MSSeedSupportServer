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

my $auth = "chenry Ko3BA9yMnMj2k";
my $jobs = $wserv->get_jobs({
	type => "MSBuildModel",
	status => "done",
	auth => $auth
});

for (my $i=0; $i < @{$jobs};$i++) {
	my $job = $jobs->[$i];
	my $genome = $job->{jobdata}->{genome};
	my $owner = $job->{jobdata}->{owner};
	print "Processing ".$job->id.":".$owner.":".$genome."\n";
	my $meta = $wserv->get_objectmeta({
		type => "Model",
		workspace => $owner,
		id => "Seed".$genome,
		auth => $auth
	});
	my $version = $meta->[3];
	if (!defined($job->{jobdata}->{loaded}) || $job->{jobdata}->{loaded} ne $version) {
		print "Loading model!\n";
		my $mdldata = $fbaserv->export_fbamodel({
			auth => $auth,
			model => "Seed".$genome,
			format => "modelseed",
			workspace => $owner
		});
		
		my $sbml = $fbaserv->export_fbamodel({
			auth => $auth,
			model => "Seed".$genome,
			format => "sbml",
			workspace => $owner
		});
		
		my $output = $wserv->get_object({
			type => "Genome",
			workspace => $owner,
			id => $genome,
			auth => $auth
		});
		
		if (!defined($output->{data}->{taxonomy}) && defined($output->{data}->{domain})) {
			$output->{data}->{taxonomy} = $output->{data}->{domain};
		}
		
		my $input = {
			genome => {
				id => $genome,
				genes => 0,
				features => [],
				owner => $owner,
				source => $output->{data}->{source},
				taxonomy => $output->{data}->{taxonomy},
				name => $output->{data}->{scientific_name},
				size => $output->{data}->{size},
				domain => $output->{data}->{domain},
				gc => $output->{data}->{gc},
				genetic_code => $output->{data}->{genetic_code}
			},
			owner => $owner,
			reactions => [],
			biomass => undef,
			cellwalltype => undef,
			status => 1
		};
		
		if (defined($output->{data}->{features})) {
			for (my $j=0; $j < @{$output->{data}->{features}}; $j++) {
				my $ftr = $output->{data}->{features}->[$j];
				my $id = $ftr->{id};
				my $roles = [split(/\s*;\s+|\s+[\@\/]\s+/,$ftr->{function})];
				my $aliases = $ftr->{aliases};
				my $type = "peg";
				if ($id =~ m/fig\|\d+\.\d+\.(.+)\./) {
					$type = $1;
				}
				my $dir = "for";
				my $min = $ftr->{location}->[0]->[1];
				my $max = $min+$ftr->{location}->[0]->[3];
				my $loc = $min."_".$max;
				if ($ftr->{location}->[0]->[2] eq "-") {
					$dir = "rev";
					$max = $min;
					$min = $max-$ftr->{location}->[0]->[3];
					$loc = $max."_".$min;
				}
				$input->{genome}->{genes}++;
				push(@{$input->{genome}->{features}},{
					id => $id,
					ess => "",
					aliases => join("|",@{$aliases}),
					type => $type,
					location => $loc,
					"length" => $ftr->{location}->[0]->[3],
					direction => $dir,
					min => $min,
					max => $max,
					roles => join("|",@{$roles}),
					source => "",
					sequence => ""
				});
			}
		}
		
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
			$input->{genome}->{class} = "Gram negative";
			$input->{cellwalltype} = "Gram negative";
		} else {
			$input->{genome}->{class} = "Gram positive";
			$input->{cellwalltype} = "Gram positive";
		}
		if ($lines->[$i+2] =~ m/EQUATION\t(.+)/) {
			$input->{biomass} = $1;
		}
		
		$mssserv->load_model_to_modelseed($input);
		$wserv->set_job_status({
			auth => $auth,
			jobid => $job->{id},
			currentStatus => "done",
			status => "done",
			jobdata => {loaded => $version}
		});
	} else {
		print "Model already loaded!\n";
	}
}

1;
