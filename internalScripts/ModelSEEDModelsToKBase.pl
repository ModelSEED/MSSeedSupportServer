#!/usr/bin/perl -w

use strict;
use warnings;
use JSON::XS;
use Test::More;
use Data::Dumper;
use File::Temp qw(tempfile);
use LWP::Simple;
use Config::Simple;
use DBI;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Client;

my $config = $ARGV[0];
if (!defined($config)) {
	print STDERR "No config file provided!\n";
	exit(-1);
}
if (!-e $config) {
	print STDERR "Config file ".$config." not found!\n";
	exit(-1);
}
#Params: writesbml.wsurl, writesbml.fbaurl, writesbml.auth
my $c = Config::Simple->new();
$c->read($config);

my $wserv = Bio::KBase::workspaceService::Client->new($c->param("kbclientconfig.wsurl"));
my $fbaserv = Bio::KBase::fbaModelServices::Client->new($c->param("kbclientconfig.fbaurl"));

my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
my $select = "SELECT * FROM ModelDB.MODEL;";
my $models = $db->selectall_arrayref($select, { Slice => {
	_id => 1,
	source => 1,
	status => 1,
	genome => 1,
	id => 1,
	owner => 1,
	name => 1,
	biomassReaction => 1
} });

for (my $m=0; $m < @{$models}; $m++) {
	my $model = $models->[$m];
	print "Processing ".$model->{id}."!\n";
	my $meta;
	eval {
		$meta = $wserv->get_objectmeta({
			type => "Model",
			workspace => "ModelSEEDModels",
			id => $model->{id},
			auth => $c->param("kbclientconfig.auth")
		});
	};
	if (!defined($meta)) {
		#Query model reaction table and get reaction list
		my $reactions = [];
		$select = "SELECT * FROM ModelDB.REACTION_MODEL WHERE MODEL = ?";
		my $rxns = $db->selectall_arrayref($select, { Slice => {
			MODEL => 1,
			compartment => 1,
			REACTION => 1,
			pegs => 1,
			directionality => 1
		} }, $model->{id});
		for (my $i=0; $i < @{$rxns}; $i++) {
			my $rxn = $rxns->[$i];
			if ($rxn->{pegs} !~ m/peg\.\d+/) {
				$rxn->{pegs} = "peg.0";
			}
			$rxn->{pegs} =~ s/\|/ or /g;
			$rxn->{pegs} =~ s/\+/ and /g;
			if ($rxn->{REACTION} =~ m/rxn\d+/) {
				push(@{$reactions},[
					$rxn->{REACTION},
					$rxn->{directionality},
					$rxn->{compartment},
					$rxn->{pegs}
				]);
			}
		}
		if (@{$reactions} > 100) {
			print "Loading ".$model->{id}."!\n";
			#Query biomass table and get biomass reaction equation
			$select = "SELECT * FROM ModelDB.BIOMASS WHERE id = ?";
			my $bios = $db->selectall_arrayref($select, { Slice => {
				id => 1,
				equation => 1
			}}, $model->{biomassReaction});
			my $biomass = $bios->[0]->{equation};
			#Load model to KBase
			if (defined($biomass)) {
				eval {
					$fbaserv->import_fbamodel({
						genome => "0000000.0",
						genome_workspace => "ModelSEEDGenomes",
						biomass => $biomass,
						reactions => $reactions,
						model => $model->{id},
						workspace => "ModelSEEDModels",
						auth => $c->param("kbclientconfig.auth")
					});
				}; print STDERR $@ if $@;
			}
		}
	}
}

1;
