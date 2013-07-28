#!/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/bin/perl

BEGIN {
    @INC = qw(
		/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/lib/perl5/site_perl/5.12.2/x86_64-linux
		/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/lib/perl5/site_perl/5.12.2
		/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/lib/perl5/site_perl
		/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/lib/perl5/5.12.2/x86_64-linux
		/vol/rast-bcr/2010-1124/linux-rhel5-x86_64/lib/perl5/5.12.2
	);
}

use strict;
use CGI;
use DBI;

$|=1;
print STDERR "TEST1\n";
my $cgi = new CGI();
if (defined($cgi->param('biochemistry'))) {
	print STDERR "TEST2\n";
	my $data = loadExcelFile("/vol/model-dev/MODEL_DEV_DB/Models2/biochemistry.xls");
} elsif (defined($cgi->param('biochemCompounds'))) {
	print STDERR "TEST3\n";
	my $data = loadExcelFile("/vol/model-dev/MODEL_DEV_DB/Models2/biochemistryCompounds.xls");
} elsif (defined($cgi->param('model'))) {
	print STDERR "TEST4\n";
	if(!defined($cgi->param('file'))) {
	    print STDERR "TEST5\n";
	    print CGI::header();
	    print CGI::start_html();
	    print '<pre>No file type selected for download</pre>';
	    print CGI::end_html();
	}
	my $modelid = $cgi->param('model');
	my $owner = modelOwner($modelid);
	if ($cgi->param('file') eq "XLS") {
		print STDERR "TEST6\n";
		my $excelfile = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$modelid."/0/excel.xls";
		my $data = loadExcelFile($excelfile);
		print "Content-Type: application/vnd.ms-excel\nContent-Disposition: attachment; filename=\"".$modelid.".xls\";\n\n".$data."\n";
		#print STDERR "Content-Type: application/vnd.ms-excel\nContent-Disposition: attachment; filename=".$modelid.".xls;\n".$data;
	} elsif ($cgi->param('file') eq "SBML") {
		print STDERR "TEST7\n";
		my $sbmlfile = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$modelid."/0/model.sbml";
		my $data = loadSBMLFile($sbmlfile);
		print "Content-Type: application/sbml+xml\nContent-Disposition: attachment; filename=\"".$modelid.".xml\";\n\n".$data."\n";
		#print STDERR "Content-Type: application/sbml+xml\nContent-Disposition: attachment; filename=".$modelid.".xml;\n".$data;
	} else {
		print STDERR "TEST8\n";
		print CGI::header();
	    print CGI::start_html();
	    print '<pre>Requested type not recognized!</pre>';
	    print CGI::end_html();
	}
	print STDERR "TEST10\n";
} else {
	print STDERR "TEST9\n";
	print CGI::header();
    print CGI::start_html();
    print '<pre>No model selected for download</pre>';
    print CGI::end_html();
}
print STDERR "TEST11\n";

1;

sub loadExcelFile {
	my ($filename) = @_;
	my $data;
	local $/ = undef;   
	open(my $fh, "<:raw", $filename);
	$data = <$fh>;
	close($fh);
	return $data;
}

sub loadSBMLFile {
	my ($filename) = @_;
	my $data;
	local $/ = undef;   
	open(my $fh, "<", $filename);
	$data = <$fh>;
	close($fh);
	return $data;
}

sub modelOwner {
	my ($model) = @_;
	my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
	my $select = "SELECT * FROM ModelDB.MODEL WHERE id = ?";
	my $models = $db->selectall_arrayref($select, { Slice => {
		_id => 1,
		source => 1,
		status => 1,
		genome => 1,
		id => 1,
		owner => 1,
		name => 1,
	} }, $model);
	if (!defined($models->[0]) || !defined($models->[0]->{owner})) {
		print CGI::header();
	    print CGI::start_html();
	    print '<pre>Selected model not found!</pre>';
	    print CGI::end_html();
		return;
	}
	return $models->[0]->{owner};
}
