#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Config::Simple;
use File::Path;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Client;

my $config = $ARGV[0];
my $mod = $ARGV[1];
my $overwrite = 0;
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

my $models = [];
my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
my $select = "SELECT * FROM ModelDB.MODEL;";
if (defined($mod)) {
	$select = "SELECT * FROM ModelDB.MODEL WHERE id = ?;";
}
$models = $db->selectall_arrayref($select, { Slice => {
	_id => 1,
	source => 1,
	status => 1,
	genome => 1,
	id => 1,
	owner => 1,
	name => 1,
	biomassReaction => 1
} },$mod);

my $wserv = Bio::KBase::workspaceService::Client->new($c->param("kbclientconfig.wsurl"));
my $fbaserv = Bio::KBase::fbaModelServices::Client->new($c->param("kbclientconfig.fbaurl"));
for (my $m=0; $m < @{$models}; $m++) {
	my $model = $models->[$m];
	my $directory = "/vol/model-dev/MODEL_DEV_DB/Models2/".$model->{owner}."/".$model->{id}."/0/";
	if (!-e $directory) {
		mkpath $directory;
	}
	my $sbmlfile = $directory."model.sbml";
	if ($overwrite == 0 && -e $sbmlfile) {
		next;
	}
	my $meta;
	eval {
		$meta = $wserv->get_objectmeta({
			type => "Model",
			workspace => "ModelSEEDModels",
			id => $model->{id},
			auth => $c->param("kbclientconfig.auth")
		});
	};
	if (defined($meta)) {
		my $mdldata;
		eval {
			$mdldata = $fbaserv->export_fbamodel({
				auth => $c->param("kbclientconfig.auth"),
				model => $model->{id},
				format => "sbml",
				workspace => "ModelSEEDModels"
			});
		};
		if (!defined($mdldata)) {
			print STDERR $model->{id}." sbml generation failed!\n";
		} else {
			open (my $fh, ">", $sbmlfile) || die "Couldn't open $sbmlfile: $!";
			print $fh $mdldata;
			close($fh);
		}
	} else {
		print STDERR $model->{id}." not yet in KBase!\n";
	}
}
	
1;
