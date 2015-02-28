#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;
use Config::Simple;
use Bio::KBase::workspace::ScriptHelpers qw(printObjectInfo get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);
use Bio::KBase::fbaModelServices::ScriptHelpers qw(getToken fbaws get_fba_client runFBACommand universalFBAScriptCode );
use Bio::ModelSEED::MSSeedSupportServer::Client;

$|=1;

#Setting genome
my $genome = $ARGV[0];
my $genomeowner = $ARGV[1];
my $override = $ARGV[3];
if (!defined($genome)) {
	die "No genome specified!";
}
if (!defined($override)) {
	$override = 0;
}
my $output;
#Setting stage
my $stage = $ARGV[2];
if (!defined($stage)) {
	$stage = "loadgenome";
}
#Loading config
my $c = Config::Simple->new();
if (!defined($ENV{MS_MAINT_CONFIG})) {
	$ENV{MS_MAINT_CONFIG} = "/Users/chenry/code/deploy/msconfig.ini";
}
$c->read($ENV{MS_MAINT_CONFIG});
#Logging in ModelSEED admin account
my $token = Bio::KBase::AuthToken->new(user_id => $c->param("msmaint.kbuser"), password => $c->param("msmaint.kbpassword"));
$token = $token->token();
#Getting clients
my $wserv = Bio::KBase::workspace::Client->new($c->param("msmaint.ws-url"),token => $token);
my $fbaserv = Bio::KBase::fbaModelServices::Client->new($c->param("msmaint.fba-url"),token => $token);
my $mssserv = Bio::ModelSEED::MSSeedSupportServer::Client->new($c->param("msmaint.ms-url"));
#Loading genome
print "test0\n";
if ($stage eq "loadgenome") {
	print "Loading genome ".$genome."!\n";
	#Checking for genome in model seed
	my $loadgenome = 1;
	print "test1\n";
	if ($override == 0) {
		print "test2\n";
		eval {
			$output = $wserv->get_object_info([{
				workspace => "ModelSEEDGenomes",
				name => $genome
			}],1);
		};
		if (defined($output)) {
			$loadgenome = 0;
		}
	}
	if ($loadgenome == 1) {
		eval {
			$output = $wserv->get_object_info([{
				workspace => "PubSEEDGenomes",
				name => $genome
			}],1);
		};
		if (defined($output)) {
			$output = $wserv->copy_object({
				from => {
					workspace => "PubSEEDGenomes",
					name => $genome
				},
				to => {
					workspace => "ModelSEEDGenomes",
					name => $genome
				}
			});
		} else {
			$output = $fbaserv->genome_to_workspace({
				genome => $genome,
				workspace => "ModelSEEDGenomes",
				sourceLogin => $c->param("msmaint.rastlogin"),
				sourcePassword => $c->param("msmaint.rastpassword"),
				source => "rast"
			});
		}
	}
	$stage = "loadmodel";
}
if ($stage eq "loadmodel") {
	print "Loading model ".$genome."!\n";
	$output = $fbaserv->genome_to_fbamodel({
		genome => $genome,
		genome_workspace => "ModelSEEDGenomes",
		workspace => "ModelSEEDModels",
		model => "Seed".$genome
	});
	$stage = "gapfillmodel";
}
if ($stage eq "gapfillmodel") {
	print "Gapfilling model ".$genome."!\n";
	$output = $fbaserv->gapfill_model({
		model => "Seed".$genome,
		workspace => "ModelSEEDModels",
	});
	$stage = "loadtomodelseed";
}
if ($stage eq "loadtomodelseed") {
	print "Loading to modelseed for ".$genome."!\n";
	my $objs = $wserv->get_objects([{
		workspace => "ModelSEEDGenomes",
		name => $genome
	}],1);
	my $genomeobj = $objs->[0]->{data};
	if (!defined($genomeobj->{taxonomy}) && defined($genomeobj->{domain})) {
		$genomeobj->{taxonomy} = $genomeobj->{domain};
	}
	my $input = {
		genome => {
			id => $genome,
			genes => 0,
			features => [],
			owner => $c->param("msmaint.kbuser"),
			source => $genomeobj->{source},
			taxonomy => $genomeobj->{taxonomy},
			name => $genomeobj->{scientific_name},
			size => $genomeobj->{size},
			domain => $genomeobj->{domain},
			gc => $genomeobj->{gc},
			genetic_code => $genomeobj->{genetic_code}
		},
		owner => $genomeowner,
		reactions => [],
		biomass => undef,
		cellwalltype => undef,
		status => 1
	};
	if (defined($genomeobj->{features})) {
		for (my $j=0; $j < @{$genomeobj->{features}}; $j++) {
			my $ftr = $genomeobj->{features}->[$j];
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
	my $mdldata = $fbaserv->export_fbamodel({
		model => "Seed".$genome,
		format => "modelseed",
		workspace => "ModelSEEDModels"
	});
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
	$output = $mssserv->load_model_to_modelseed($input);
	$stage = "printsbml";
}
if ($stage eq "printsbml") {
	print "Print SBML for model ".$genome."!\n";
	$output = $fbaserv->export_fbamodel({
		model => "Seed".$genome,
		format => "sbml",
		workspace => "ModelSEEDModels"
	});
	print $output;
}

1;
