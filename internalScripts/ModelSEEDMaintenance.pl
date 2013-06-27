#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Config::Simple;
use Bio::KBase::workspaceService::Client;
use JSON::XS;
use File::Temp qw(tempfile);
use LWP::Simple;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Impl;
use Bio::ModelSEED::MSSeedSupportServer::Impl;

#Creating the error message printed whenever the user input makes no sense
my $Usage = "ModelSEEDMaintenance must be called with the following syntax:\n".
			"msmaint <directory>\n";
#First checking to see if job directory provided and exists
if (!defined($ARGV[0]) || $ARGV[0] eq "help") {
    print $Usage;
	exit(0);
}
my $directory = $ARGV[0];
if (!-d $directory) {
	print "Input directory does not exist!";
	exit(0);
}
#Reading in the config file
my $servicename = "msmaint";
my $params = {
	wsurl => "http://bio-data-1.mcs.anl.gov/services/ms_workspace",
	auth => undef,
	looptime => undef,
	dbuser => "webappuser"
};
if (!-e $directory."/config.ini") {
	print "No config file found!";
	exit(0);
}
my $c = Config::Simple->new();
$c->read($directory."/config.ini");
#Retrieving parameters
foreach my $param (keys(%{$params})) {
	$params->{$param} = $c->param($servicename.".".$param);
}
#Creating PID file
if (-e $directory."/PID") {
	unlink($directory."/PID");
}
open(PID, "> ".$directory."/PID") || die "could not open PID file!"; 
print PID "$$\n"; 
close(PID);
#Creating server objects
my $mssserv = Bio::ModelSEED::MSSeedSupportServer::Impl->new();
my $wserv = Bio::KBase::workspaceService::Client->new($params->{wsurl});
my $fbaserv = Bio::KBase::fbaModelServices::Impl->new({accounttype => "seed",workspace => $wserv});
#Starting work loop
while(1) {
	#Queueing up Model SEED jobs
	my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$params->{dbuser});
	my $select = "SELECT * FROM ModelDB.MODEL WHERE status = ?";
	my $models = $db->selectall_arrayref($select, { Slice => {
		_id => 1,
		source => 1,
		status => 1,
		genome => 1,
		id => 1,
		owner => 1,
		name => 1,
	} }, "-2");
	print @{$models}." models queued!\n";
	for (my $i=0; $i < @{$models}; $i++) {
		my $model = $models->[$i];
		if ($model->{genome} =~ m/^\d+\.\d+$/) {
			print "Queueing model ".$model->{owner}."\t".$model->{genome}."\n";
			eval {
				$wserv->queue_job({
					auth => $params->{auth},
					"state" => undef,
					type => "MSBuildModel",
					queuecommand => "QueueModelSEED",
					jobdata => {
						owner => $model->{owner},
						genome => $model->{genome},
					}
				});
				my $statement = "UPDATE ModelDB.MODEL SET status = '-3' WHERE id = '".$model->{id}."';";
				$db->do($statement);
			};
		}
	}
	#Loading completed models to the Model SEED database
	my $jobs = $wserv->get_jobs({
		type => "MSBuildModel",
		status => "done",
		auth => $params->{auth}
	});
	for (my $i=0; $i < @{$jobs};$i++) {
		my $job = $jobs->[$i];
		my $genome = $job->{jobdata}->{genome};
		my $owner = $job->{jobdata}->{owner};
		print "Processing ".$job->{id}.":".$owner.":".$genome."\n";
		my $meta;
		eval {
			$meta = $wserv->get_objectmeta({
				type => "Model",
				workspace => $owner,
				id => "Seed".$genome,
				auth => $params->{auth}
			});
		};
		if (defined($meta)) {
			my $version = $meta->[3];
			if (!defined($job->{jobdata}->{loaded}) || $job->{jobdata}->{loaded} ne $version) {
				print "Loading model!\n";
				my $mdldata;
				eval {
					$mdldata = $fbaserv->export_fbamodel({
						auth => $params->{auth},
						model => "Seed".$genome,
						format => "modelseed",
						workspace => $owner
					});
				};
				if (!defined($mdldata)) {
					print "Model ".$owner.":Seed".$genome." not found!\n";
				} else {
					my $output;
					eval {
						$output = $wserv->get_object({
							type => "Genome",
							workspace => $owner,
							id => $genome,
							auth => $params->{auth}
						});
					};
					if (!defined($output)) {
						print "Genome ".$owner.":".$genome." not found!\n";
					} else {
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
						eval {
							$mssserv->load_model_to_modelseed($input);
							$wserv->set_job_status({
								auth => $params->{auth},
								jobid => $job->{id},
								currentStatus => "done",
								status => "done",
								jobdata => {loaded => $version}
							});
						};
					}
				}
			} else {
				print "Model already loaded!\n";
			}
		}
	}
	#Looping
	sleep($params->{looptime});
}

1;
