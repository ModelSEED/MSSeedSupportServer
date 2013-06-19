#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Bio::KBase::workspaceService::Client;

my $url = "http://bio-data-1.mcs.anl.gov/services/ms_workspace";
my $auth = "chenry	Ko3BA9yMnMj2k";
my $wserv = Bio::KBase::workspaceService::Client->new($url);

my $jobs = $wserv->get_jobs({
	type => "MSBuildModel",
	auth => $auth
});
my $genomes; 
for (my $i=0; $i < @{$jobs}; $i++) {
	my $job = $jobs->[$i];
	if ($job->{jobdata}->{genome} =~ m/^\d+\.\d+$/) {
		$genomes->{$job->{jobdata}->{genome}}->{$job->{jobdata}->{owner}} = 1;
	}
}
my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
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
		if (!defined($genomes->{$model->{genome}}->{$model->{owner}})) {
			print "Queueing model ".$model->{owner}."\t".$model->{genome}."\n"
			$wserv->queue_job({
				auth => $auth,
				"state" => undef,
				type => "MSBuildModel",
				queuecommand => "QueueModelSEED",
				jobdata => {
					owner => $model->{owner},
					genome => $model->{genome},
				}
			});
		}
		my $statement = "UPDATE ModelDB.MODEL SET status = '-3' WHERE id = '".$model->{id}."';";
		$db->do($statement);
	}
}

1;
