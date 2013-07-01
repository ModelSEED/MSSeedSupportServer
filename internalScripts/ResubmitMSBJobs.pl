#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;
use Bio::KBase::workspaceService::Client;

$|=1;
my $url = "http://bio-data-1.mcs.anl.gov/services/ms_workspace";
my $auth = "chenry	Ko3BA9yMnMj2k";
my $wserv = Bio::KBase::workspaceService::Client->new($url);

my $jobs = $wserv->get_jobs({
	type => "MSBuildModel",
	status => "error",
	auth => $auth
});

print STDERR @{$jobs}." jobs with errors!\n";
print "ID\tGenome\tOwner\tError type\tDetails\n";
for (my $i=0; $i < @{$jobs}; $i++) {
	my $job = $jobs->[$i];
	my $resubmit = 0;
	my $delete = 0;
	if ($job->{jobdata}->{genome} !~ m/^\d+\.\d+$/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tBad genome ID\t\n";
		#$delete = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Organism\sdirectory\s(.+)\sdoes\snot\sexist/) {
		#$delete = 1;
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tBad organism dir\t".$1."\n";
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Workspace\sname\smust\scontain\sonly\salphanumeric\scharacters/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tWorkspace must be alphanumeric\t\n";
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Specified\sobject\snot\sfound\sin\sthe\sworkspace/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tObject not in workspace\t\n";
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Attribute\s.roleHash.\sdoes\snot\spass\sthe\stype\sconstraint/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tEmpty genome feature set\t\n";
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/recv\stimed\sout/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tRecv time out\t\n";
		#$resubmit = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/HTTP\sstatus.\s500\sCan.t\sconnect\sto\sbiologin.4\.mcs\.anl\.gov.7050/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tCannot connect to server!\t\n";
		#$resubmit = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Cannot\screate\sworkspace\sbecause\sworkspace\salready\sexists/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tWorkspace already exists!\t\n";
		#$resubmit = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/HTTP\sstatus.\s504\sGateway\sTime.out/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tGateway time out!\t\n";
		#$resubmit = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} =~ m/Can.t\slocate\sBio.KBase.probabilistic_annotation.Client.pm/) {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tCannot locate probano service!\t\n";
		#$resubmit = 1;
	} elsif (defined($job->{jobdata}->{error}) && $job->{jobdata}->{error} eq "") {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tNo error found!\t\n";
		#$resubmit = 1;
	} else {
		print $job->{id}."\t".$job->{jobdata}->{genome}."\t".$job->{jobdata}->{owner}."\tUnrecognized error\t\n";
	}
	if ($resubmit == 1) {
		eval {
			$wserv->set_job_status({
				auth => $auth,
				jobid => $job->{id},
				currentStatus => "error",
				status => "queued",
			});
		};
	} elsif ($delete == 1) {
		eval {
			$wserv->set_job_status({
				auth => $auth,
				jobid => $job->{id},
				currentStatus => "error",
				status => "delete",
			});
		};
	}	
}	

1;
