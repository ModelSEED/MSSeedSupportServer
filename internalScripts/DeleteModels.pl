use strict;
use warnings;
use DBI;
use DateTime;

$|=1;

my $model = $ARGV[0];
my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
if (defined($db) && length($model) > 0) {
	my $models = $db->selectall_arrayref("DELETE FROM ModelDB.MODEL WHERE id = ".$model);
	$db->disconnect;
}

1;
