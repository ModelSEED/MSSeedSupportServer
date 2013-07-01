#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Config::Simple;
use JSON::XS;
use File::Temp qw(tempfile);
use LWP::Simple;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Client;
use Bio::ModelSEED::MSSeedSupportServer::Client;

#Creating the error message printed whenever the user input makes no sense
my $Usage = "ModelSEEDMaintenance must be called with the following syntax:\n".
			"msmaint <directory>\n";
#First checking to see if job directory provided and exists
if (!defined($ARGV[0]) || $ARGV[0] eq "help") {
    print $Usage;
	exit(0);
}
my $msmaint = msmaintainer->new({
	directory => $ARGV[0]
});
$msmaint->readconfig();
$msmaint->printPID();
$msmaint->loop();

#Declaring scheduler package
package msmaintainer;

sub new {
	my ($class,$params) = @_;
	if (!-d $params->{directory}) {
		print "Input directory ".$params->{directory}." does not exist!\n";
		exit(-1);
	}
	my $self = {_directory => $params->{directory}};
    return bless $self;
}

sub directory {
    my ($self) = @_;
	return $self->{_directory};
}

sub fbaserv {
	my($self) = @_;
	if (!defined($self->{_fbaserv})) {
		$self->{_fbaserv} = Bio::KBase::fbaModelServices::Client->new($self->params("fba-url"));	
	}
	return $self->{_fbaserv};
}

sub wsserv {
	my($self) = @_;
	if (!defined($self->{_wsserv})) {
		$self->{_wsserv} = Bio::KBase::workspaceService::Client->new($self->params("ws-url"));	
	}
	return $self->{_wsserv};
}

sub msserv {
	my($self) = @_;
	if (!defined($self->{_msserv})) {
		$self->{_msserv} = Bio::KBase::MSSeedSupportServer::Client->new($self->params("ms-url"));	
	}
	return $self->{_msserv};
}

sub loop {
	my($self) = @_;
	while (1) {
		print "New loop!\n";
		$self->work();
		sleep($self->params("looptime"));
	}
}

sub work {
	my($self) = @_;
	#Loading genomes for queued models
	my $models = $self->retreiveModels("-10");
	for (my $i=0; $i < @{$models};$i++) {
		my $model = $models->[$i];
		if ($model->{genome} =~ m/^\d+\.\d+$/) {
			print "Loading genome for ".$model->{id}."!\n";
			$self->loadGenomeForModel($model);
			print "Building model for ".$model->{id}."!\n";
			$self->buildModelForGenome($model);
			if ($self->modelExists($model)) {
				print "Loading model to ModelSEED ".$model->{id}."!\n";
				$self->loadModel($model);
				$self->updateModelStatus("-4",$model);
			} else {
				print "Model build failed ".$model->{id}."!\n";
			}
		}
	}
	#Gapfilling models
	$models = $self->retreiveModels("-4");
	for (my $i=0; $i < @{$models};$i++) {
		my $model = $models->[$i];
		print "Queueing gapfilling for ".$model->{id}."!\n";
		$self->gapfillModel($model);
		$self->updateModelStatus("-5",$model);
	}
	#Loading gapfilled models
	$models = $self->retreiveModels("-5");
	for (my $i=0; $i < @{$models};$i++) {
		my $model = $models->[$i];
		print "Loading gapfilled model ".$model->{id}."!\n";
		$self->loadGapfillModel($model);
	}
}

sub loadGenomeForModel {
	my($self,$model) = @_;
	my $genome = $model->{genome};
	if ($self->genomeExists($genome) == 1) {
		return;
	}
	if ($self->PubSEEDGenome($genome) == 1) {
		eval {
			$self->fbaserv()->genome_to_workspace({
				genome => $genome,
				workspace => "ModelSEEDGenomes",
				source => "seed",
				auth => $self->params("auth"),
				overwrite => 1
			});
		};
	} else {
		eval {
			$self->fbaserv()->genome_to_workspace({
				genome => $genome,
				workspace => "ModelSEEDGenomes",
				sourceLogin => $self->params("rastlogin"),
				sourcePassword => $self->params("rastpassword"),
				source => "rast",
				auth => $self->params("auth"),
				overwrite => 1
			});
		};
	}
}

sub PubSEEDGenome {
	my($self,$genome) = @_;
	if (!defined($self->{_pubseedgenomes})) {
		my $genomes = [split(/;/,$self->params("PubSEEDGenomes"))];
		$self->{_pubseedgenomes} = {};
		for (my $i=0; $i < @{$genomes}; $i++) {
			$self->{_pubseedgenomes}->{$genomes->[$i]} = 1;
		}
	}
	if (defined($self->{_pubseedgenomes}->{$genome})) {
		return 1;
	}
	return 0;
}

sub genomeExists {
	my($self,$genome) = @_;
	my $meta;
	eval {
		$meta = $self->wsserv()->get_objectmeta({
			type => "Genome",
			workspace => "ModelSEEDGenomes",
			id => $genome,
			auth => $self->params("auth")
		});
	};
	if (defined($meta)) {
		return 1;	
	}
	return 0;
}

sub modelExists {
	my($self,$model) = @_;
	my $meta;
	eval {
		$meta = $self->wsserv()->get_objectmeta({
			type => "Model",
			workspace => "ModelSEEDModels",
			id => $model->{id},
			auth => $self->params("auth")
		});
	};
	if (defined($meta)) {
		return 1;	
	}
	return 0;
}

sub buildModelForGenome {
	my($self,$model) = @_;
	if ($self->modelExists($model) == 1) {
		return;
	}
	eval {
		$self->fbaserv()->genome_to_fbamodel({
			genome => $model->{genome},
			genome_workspace => "ModelSEEDGenomes",
			workspace => "ModelSEEDModels",
			model => $model->{id},
			auth => $self->params("auth"),
		});
	};
}

sub loadModel {
	my($self,$model) = @_;
	my $output;
	eval {
		$output = $self->wsserv()->get_object({
			type => "Genome",
			workspace => "ModelSEEDGenomes",
			id => $model->{genome},
			auth => $self->params("auth")
		});
	};
	if (!defined($output)) {
		print "Genome ".$model->{genome}." not found!\n";
		return;
	}
	if (!defined($output->{data}->{taxonomy}) && defined($output->{data}->{domain})) {
		$output->{data}->{taxonomy} = $output->{data}->{domain};
	}				
	my $input = {
		genome => {
			id => $model->{genome},
			genes => 0,
			features => [],
			owner => $model->{owner},
			source => $output->{data}->{source},
			taxonomy => $output->{data}->{taxonomy},
			name => $output->{data}->{scientific_name},
			size => $output->{data}->{size},
			domain => $output->{data}->{domain},
			gc => $output->{data}->{gc},
			genetic_code => $output->{data}->{genetic_code}
		},
		owner => $model->{owner},
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
	my $mdldata;
	eval {
		$mdldata = $self->fbaserv()->export_fbamodel({
			auth => $self->params("auth"),
			model => $model->{id},
			format => "modelseed",
			workspace => "ModelSEEDModels"
		});
	};
	if (!defined($mdldata)) {
		print "Model ".$model->{id}." not found!\n";
		return
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
		$self->msserv()->load_model_to_modelseed($input);
	};
}

sub gapfillModel {
	my($self,$model) = @_;
	eval {
		$self->fbaserv()->queue_gapfill_model({
			model => $model->{id},
			integrate_solution => 1,
			workspace => "ModelSEEDModels",
			auth => $self->params("auth"),
		});
	};
}

sub loadGapfillModel {
	my($self,$model) = @_;
	my $modData;
	eval {
		$modData = $self->fbaserv()->get_models({
			models => [$model->{id}],
			workspaces => ["ModelSEEDModels"],
			auth => $self->params("auth")
		});
	};
	if (!defined($modData->[0]->{integrated_gapfillings}->[0])) {
		return;
	}
	$self->updateModelStatus("1",$model);
	$self->loadModel($model);
}

sub readconfig {
	my($self) = @_;
	#Reading in the config file
	my $servicename = "msmaint";
	my $params = {
		auth => undef,
		looptime => undef,
		dbuser => undef,
		fba-url => undef,
		ws-url => undef,
		ms-url => undef,
		rastlogin => undef,
		rastpassword => undef,
		PubSEEDGenomes => undef
	};
	if (!-e $self->directory()."/config.ini") {
		print "No config file found!";
		exit(0);
	}
	my $c = Config::Simple->new();
	$c->read($self->directory()."/config.ini");
	#Retrieving parameters
	foreach my $param (keys(%{$params})) {
		$self->{"_".$param} = $c->param($servicename.".".$param);
	}
}

sub printPID {
	my($self) = @_;
	if (-e $self->directory()."/PID") {
		unlink($self->directory()."/PID");
	}
	open(PID, "> ".$self->directory()."/PID") || die "could not open PID file!"; 
	print PID "$$\n"; 
	close(PID);
}

sub params {
	my($self,$parameter) = @_;
	return $self->{"_".$parameter};
}

sub updateModelStatus {
	my($self,$status,$model) = @_;
	my $statement = "UPDATE ModelDB.MODEL SET status = '".$status."' WHERE id = '".$model->{id}."';";
	my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
	$db->do($statement);
}

sub retreiveModels {
	my($self,$status) = @_;
	my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
	my $select = "SELECT * FROM ModelDB.MODEL WHERE status = ?";
	my $models = $db->selectall_arrayref($select, { Slice => {
		_id => 1,
		source => 1,
		status => 1,
		genome => 1,
		id => 1,
		owner => 1,
		name => 1,
	} }, $status);
	return $models;
}

1;
