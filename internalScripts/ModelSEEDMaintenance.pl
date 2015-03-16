use strict;
use warnings;
use DBI;
use DateTime;

$|=1;

#Printing PID file
if (-e "/vol/model-prod/kbase/deploy/pids/mss-maint-pid") {
	unlink("/vol/model-prod/kbase/deploy/pids/mss-maint-pid");
}
open(PID, "> /vol/model-prod/kbase/deploy/pids/mss-maint-pid") || die "could not open PID file!"; 
print PID "$$\n"; 
close(PID);
#Running maintenance loop
while (1) {
	print STDERR "New loop - ".DateTime->now()->datetime()."\n";
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
		#Printing current model status
		open(STATUS, "> /homes/chenry/public_html/ModelStatus.html") || die "could not open model status file!";
		print STATUS '<!doctype HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'."\n";
		print STATUS '<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /><title>ModelSEED Status</title>'."\n";
		my $datetime = DateTime->now()->datetime();
		print STATUS "</head><body><p>Date of last update: ".$datetime."</p><br><p>Total models: ".@{$models}."</p><br><table>\n";
		print STATUS "<tr><th>ID</th><th>Genome</th><th>Owner</th><th>Status</th><th>Reactions</th><th>Biomass</th><th>Gapfill reactions</th><th>Mod date</th></tr>\n";
		my $mdllist = [];
		for (my $i=53519; $i < @{$models}; $i++) {
			if ($models->[$i]->{status} == -1 ||  $models->[$i]->{status} == -2) {
				push(@{$mdllist},$i);
			}
			$datetime = DateTime->from_epoch(epoch => $models->[$i]->{modificationDate})->datetime();
			print STATUS "<tr><td>".$models->[$i]->{id}."</td><td>".$models->[$i]->{genome}."</td><td>".$models->[$i]->{owner}."</td><td>".$models->[$i]->{status}."</td><td>".$models->[$i]->{reactions}."</td><td>".$models->[$i]->{biomassReaction}."</td><td>".$models->[$i]->{gapFillReactions}."</td><td>".$datetime."</td></tr>\n"; 
		}
		print STATUS "</table></body></html>\n";
		close(STATUS);
		#Calling model algorithm
		for (my $i=0; $i < @{$mdllist}; $i++) {
			my $index = $mdllist->[$i];
			print STDERR "Processing:".$models->[$index]->{genome}."\t".$models->[$index]->{owner}."\t".DateTime->now()->datetime()."\n";
			system("perl /vol/model-prod/kbase/MSSeedSupportServer/internalScripts/BuildModelSEEDModel.pl ".$models->[$index]->{genome}." ".$models->[$index]->{owner}." loadgenome > /vol/model-prod/kbase/deploy/msjobs/".$models->[$index]->{genome}.".out");
		}
	}
	sleep(3600);
}

1;
