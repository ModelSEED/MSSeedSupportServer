use strict;
use warnings;
use DBI;
use Config::Simple;
use JSON::XS;
use File::Temp qw(tempfile);
use LWP::Simple;
use DateTime;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Client;
use Bio::ModelSEED::MSSeedSupportServer::Client;
$|=1;

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
		$self->{_msserv} = Bio::ModelSEED::MSSeedSupportServer::Client->new($self->params("ms-url"));	
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
	my $models = $self->retreiveModels();
	my $objs = $self->wsserv()->list_workspace_objects({
		workspace => "ModelSEEDModels",
		type => "Model",
		auth => $self->params("auth")
	});
	my $mdlhash = {};
	my $kbmdlhash = {};
	for (my $i=0; $i < @{$objs}; $i++) {
		my $obj = $objs->[$i];
		$kbmdlhash->{$obj->[0]} = $obj;
	}
	#Printing SBML
	for (my $i=0; $i < @{$models}; $i++) {
		if (defined($kbmdlhash->{$models->[$i]->{id}})) {
			my $directory = "/vol/model-dev/MODEL_DEV_DB/Models2/".$models->[$i]->{owner}."/".$models->[$i]->{id}."/0/";
			my $sbmlfile = $directory."model.sbml";
			my $print = 0;
			if (!-e $sbmlfile) {
				$print = 1;
			} else {
				open(SBML, "< ".$sbmlfile);
				my $line = <SBML>;
				chomp($line);
				if ($line eq "REACTIONS") {
					$print = 1;
				}
				close(SBML);
			}
			if ($print == 1) {
				eval {
					print "Printing ".$sbmlfile."\n";
					my $sbml = $self->fbaserv()->export_fbamodel({
						auth => $self->params("auth"),
						model => $models->[$i]->{id},
						format => "sbml",
						workspace => "ModelSEEDModels"
					});
					if (defined($sbml)) {
						open(SBML, "> ".$sbmlfile);
						print SBML $sbml;
						close(SBML);
					}
				}; print STDERR $@ if $@;
			}
		}
	}
	open(STATUS, "> /homes/chenry/public_html/ModelStatus.html") || die "could not open model status file!";
	print STATUS '<!doctype HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'."\n";
	print STATUS '<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /><title>ModelSEED Status</title>'."\n";
	my $datetime = DateTime->now()->datetime();
	print STATUS "</head><body><p>Date of last update: ".$datetime."</p><br><table></body></html>\n";
	print STATUS "<tr><th>ID</th><th>Genome</th><th>Owner</th><th>Status</th><th>Reactions</th><th>Biomass</th><th>In KBase</th><th>Gapfill reactions</th><th>Mod date</th></tr>\n";
	for (my $i=0; $i < @{$models}; $i++) {
		$mdlhash->{$models->[$i]->{id}} = $models->[$i];
		if (defined($kbmdlhash->{$models->[$i]->{id}})) {
			$models->[$i]->{inkbase} = 1;
		} else {
			$models->[$i]->{inkbase} = 1;
		}
		$datetime = DateTime->from_epoch(epoch => $models->[$i]->{modificationDate})->datetime();
		print STATUS "<tr><td>".$models->[$i]->{id}."</td><td>".$models->[$i]->{genome}."</td><td>".$models->[$i]->{owner}."</td><td>".$models->[$i]->{status}."</td><td>".$models->[$i]->{reactions}."</td><td>".$models->[$i]->{biomassReaction}."</td><td>".$models->[$i]->{inkbase}."</td><td>".$models->[$i]->{gapFillReactions}."</td><td>".$datetime."</td></tr>\n"; 
	}
	print STATUS "</table></body></html>\n";
	close(STATUS);
	#Loading genomes for queued models
	$models = $self->retreiveModels("-2");
	print @{$models}." models!\n";
	for (my $i=0; $i < @{$models};$i++) {
		my $model = $models->[$i];
		if ($model->{id} =~ m/^Seed[\d\.]+$/ && $model->{genome} =~ m/^\d+\.\d+$/) {
			print "Loading genome for ".$model->{id}."!\n";
			$self->loadGenomeForModel($model);
			print "Building model for ".$model->{id}."!\n";
			$self->buildModelForGenome($model);
			if ($self->modelExists($model)) {
				print "Loading model to ModelSEED ".$model->{id}."!\n";
				$self->loadModel($model);
				print "Queueing gapfilling for ".$model->{id}."!\n";
				$self->gapfillModel($model);
				$self->updateModelStatus("-5",$model);
			} else {
				print "Model build failed ".$model->{id}."!\n";
			}
		}
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
			my $output = $self->fbaserv()->genome_to_workspace({
				genome => $genome,
				workspace => "ModelSEEDGenomes",
				source => "seed",
				auth => $self->params("auth"),
				overwrite => 1
			});
		}; print STDERR $@ if $@;
	} else {
		eval {
			my $output = $self->fbaserv()->genome_to_workspace({
				genome => $genome,
				workspace => "ModelSEEDGenomes",
				sourceLogin => $self->params("rastlogin"),
				sourcePassword => $self->params("rastpassword"),
				source => "rast",
				auth => $self->params("auth"),
				overwrite => 1
			});
		}; print STDERR $@ if $@;
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
	}; print STDERR $@ if $@;
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
	}; print STDERR $@ if $@;
}

sub gapfillModel {
	my($self,$model) = @_;
	eval {
		$self->fbaserv()->queue_gapfill_model({
			solver => "CPLEX",
			model => $model->{id},
			integrate_solution => 1,
			workspace => "ModelSEEDModels",
			auth => $self->params("auth"),
		});
	}; print STDERR $@ if $@;
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
		"fba-url" => undef,
		"ws-url" => undef,
		"ms-url" => undef,
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
	while (!defined($db)) {
		sleep(15);
		print "Database connection failed! Attempting reconnect!\n";
		$db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
	}
	$db->do($statement);
	$db->disconnect;
}

sub retreiveModels {
	my($self,$status) = @_;
	if (defined($status)) {
		my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
		while (!defined($db)) {
			sleep(15);
			print "Database connection failed! Attempting reconnect!\n";
			$db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
		}
		my $select = "SELECT * FROM ModelDB.MODEL WHERE status = ?";
		my $models = $db->selectall_arrayref($select, { Slice => {
			_id => 1,
			source => 1,
			status => 1,
			genome => 1,
			id => 1,
			owner => 1,
			name => 1,
			biomassReaction => 1,
			autoCompleteReactions => 1,
			autoCompleteMedia => 1,
			reactions => 1,
			associatedGenes => 1,
			gapFillReactions => 1,
			modificationDate => 1
		} }, $status);
		$db->disconnect;
		return $models;
	}
	my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
	while (!defined($db)) {
		sleep(15);
		print "Database connection failed! Attempting reconnect!\n";
		$db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306",$self->params("dbuser"));
	}
	my $select = "SELECT * FROM ModelDB.MODEL";
	my $models = $db->selectall_arrayref($select, { Slice => {
		_id => 1,
		source => 1,
		status => 1,
		genome => 1,
		id => 1,
		owner => 1,
		name => 1,
		biomassReaction => 1,
		autoCompleteReactions => 1,
		autoCompleteMedia => 1,
		reactions => 1,
		associatedGenes => 1,
		gapFillReactions => 1,
		modificationDate => 1
	} });
	$db->disconnect;
	return $models;	
}

1;
