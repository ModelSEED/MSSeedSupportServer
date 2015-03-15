use strict;
use warnings;
use DBI;
use DateTime;

$|=1;

my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
if (defined($db)) {
	my $models = $db->selectall_arrayref("SELECT * FROM ModelDB.MODEL", { Slice => {
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
	for (my $i=0; $i < @{$models}; $i++) {
		print $models->[$i]->{id}."\n";
	}
}

1;
