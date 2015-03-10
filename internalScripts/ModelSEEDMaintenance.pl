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
	print "New loop - ".DateTime->now()->datetime()."\n";
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
		print STATUS "</head><body><p>Date of last update: ".$datetime."</p><br><table></body></html>\n";
		print STATUS "<tr><th>ID</th><th>Genome</th><th>Owner</th><th>Status</th><th>Reactions</th><th>Biomass</th><th>In KBase</th><th>Gapfill reactions</th><th>Mod date</th></tr>\n";
		my $mdllist = [];
		for (my $i=0; $i < @{$models}; $i++) {
			$models->[$i]->{inkbase} = 1;
			if ($models->[$i]->{status} < 0 && $models->[$i]->{status} != -10) {
				push(@{$mdllist},$i);
			}
			$datetime = DateTime->from_epoch(epoch => $models->[$i]->{modificationDate})->datetime();
			print STATUS "<tr><td>".$models->[$i]->{id}."</td><td>".$models->[$i]->{genome}."</td><td>".$models->[$i]->{owner}."</td><td>".$models->[$i]->{status}."</td><td>".$models->[$i]->{reactions}."</td><td>".$models->[$i]->{biomassReaction}."</td><td>".$models->[$i]->{inkbase}."</td><td>".$models->[$i]->{gapFillReactions}."</td><td>".$datetime."</td></tr>\n"; 
		}
		print STATUS "</table></body></html>\n";
		close(STATUS);
		#Calling model algorithm
		for (my $i=0; $i < @{$mdllist}; $i++) {
			system("perl /vol/model-prod/kbase/MSSeedSupportServer/internalScripts/BuildModelSEEDModel.pl ".$models->[$i]->{genome}." ".$models->[$i]->{owner}." loadgenome > /vol/model-prod/kbase/deploy/msjobs/".$models->[$i]->{genome}.".out");
		}
	}
	sleep(3600);
}

1;
