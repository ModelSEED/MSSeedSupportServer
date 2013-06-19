#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;

my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
my $select = "SELECT * FROM ModelDB.MODEL";
my $keys = {
	_id => 1,
	source => 1,
	public => 1,
	status => 1,
	autocompleteDate => 1,
	builtDate => 1,
	spontaneousReactions => 1,
	gapFillReactions => 1,
	associatedGenes => 1,
	genome => 1,
	reactions => 1,
	modificationDate => 1,
	id => 1,
	biologReactions => 1,
	owner => 1,
	autoCompleteMedia => 1,
	transporters => 1,
	version => 1,
	autoCompleteReactions => 1,
	compounds => 1,
	autoCompleteTime => 1,
	message => 1,
	associatedSubsystemGenes => 1,
	autocompleteVersion => 1,
	cellwalltype => 1,
	biomassReaction => 1,
	growth => 1,
	noGrowthCompounds => 1,
	autocompletionDualityGap => 1,
	autocompletionObjective => 1,
	name => 1,
	defaultStudyMedia => 1,
};
my $models = $db->selectall_arrayref($select, { Slice => $keys });
my $keylist = [keys(%{$keys})];
print "Index\t".join("\t",@{$keylist})."\n";
for (my $i=0; $i < @{$models}; $i++) {
	if ($models->[$i]->{id} !~ m/Seed\d+\.\d+\.\d+/) {
		print $i;
		for (my $j=0; $j < @{$keylist}; $j++) {
			print "\t".$models->[$i]->{$keylist->[$j]};
		}
		print "\n";
	}
}

1;
