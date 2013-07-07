use strict;
use warnings;
no warnings 'once';
use CGI;
use DBI;

my $cgi = new CGI();
if (defined($cgi->param('biochemistry'))) {
	my $data = loadExcelFile("/vol/model-dev/MODEL_DEV_DB/Models2/biochemistry.xls");
} elsif (defined($cgi->param('biochemCompounds'))) {
	my $data = loadExcelFile("/vol/model-dev/MODEL_DEV_DB/Models2/biochemistryCompounds.xls");
} elsif (defined($cgi->param('model'))) {
	if(!defined($cgi->param('file'))) {
	    print CGI::header();
	    print CGI::start_html();
	    print '<pre>No file type selected for download</pre>';
	    print CGI::end_html();
	    return;
	}
	my $modelid = $cgi->param('model');
	my $owner = modelOwner($modelid);
	if ($cgi->param('file') eq "XLS") {
		my $excelfile = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$modelid."/0/excel.xls";
		my $data = loadExcelFile($excelfile);
		print "Content-Type: application/vnd.ms-excel\nContent-Disposition: attachment; filename=".$modelid.".xls;\n".$data;
		return;
	} elsif ($cgi->param('file') eq "SBML") {
		my $sbmlfile = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$modelid."/0/model.sbml";
		my $data = loadSBMLFile($sbmlfile);
		print "Content-Type: application/sbml+xml\nContent-Disposition: attachment; filename=".$modelid.".xml;\n".$data;
		return;
	} else {
		print CGI::header();
	    print CGI::start_html();
	    print '<pre>Requested type not recognized!</pre>';
	    print CGI::end_html();
	    return;
	}
} else {
	print CGI::header();
    print CGI::start_html();
    print '<pre>No model selected for download</pre>';
    print CGI::end_html();
	return;
}

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