#!/usr/bin/perl -w

use strict;
use warnings;
use JSON::XS;
use Test::More;
use Data::Dumper;
use File::Temp qw(tempfile);
use LWP::Simple;
use Config::Simple;
use Spreadsheet::WriteExcel;

my $headingTranslation = {
	ID => 0,
	TYPE => 1,
	ROLES => 2,
	LOCATION => 3
	"MIN LOCATION" => 4,
	"MAX LOCATION" => 5,
	DIRECTION => 6
};

my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");

my $rxndb = {};
my $select = "SELECT * FROM ModelDB.REACTION;";
my $rxns = $db->selectall_arrayref($select, { Slice => {
	_id => 1,
	abbrev => 1,
	abstractReaction => 1,
	code => 1,
	definition => 1,
	deltaG => 1,
	deltaGErr => 1,
	enzyme => 1,
	equation => 1,
	id => 1,
	name => 1,
	reversibility => 1,
	status => 1,
	structuralCues => 1,
	thermoReversibility => 1,
	transportedAtoms => 1,
} });
for (my $i=0; $i < @{$rxns}; $i++) {
	$rxndb->{$rxns->[$i]->{id}} = $rxns->[$i]
}

my $cpddb = {};
$select = "SELECT * FROM ModelDB.COMPOUND;";
my $cpds = $db->selectall_arrayref($select, { Slice => {
	_id => 1,
	abbrev => 1,
	abstractCompound => 1,
	charge => 1,
	deltaG => 1,
	deltaGErr => 1,
	formula => 1,
	id => 1,
	mass => 1,
	name => 1,
	owner => 1,
	pKa => 1,
	pKb => 1,
	public => 1,
	scope => 1,
	stringcode => 1,
	structuralCues => 1,
} });
for (my $i=0; $i < @{$cpds}; $i++) {
	$cpddb->{$cpds->[$i]->{id}} = $cpds->[$i]
}

$select = "SELECT * FROM ModelDB.MODEL;";
my $models = $db->selectall_arrayref($select, { Slice => {
	_id => 1,
	source => 1,
	status => 1,
	genome => 1,
	id => 1,
	owner => 1,
	name => 1,
} });

my $overwrite = 0;

#for (my $m=0; $m < @{$models}; $m++) {
for (my $m=0; $m < 10; $m++) {
	my $model = $models->[$m];
	my $directory = "/vol/model-dev/MODEL_DEV_DB/Models2/".$model->{owner}."/".$model->{id}."/0/";
	my $excelfile = $directory."excel.xls";
	print $excelfile."\n";
	if ($overwrite == 0 && -e $excelfile) {
		next;
	}
	my $ftrrxn = {};
	my $cpdhash = {};
	my $cpdtbl = [];
	my $rxntbl = [];
	my $ftrtbl = [];
	$select = "SELECT * FROM ModelDB.REACTION_MODEL WHERE MODEL = ?";
	my $rxns = $db->selectall_arrayref($select, { Slice => {
		directionality => 1,
		compartment => 1,
		REACTION => 1,
		MODEL => 1,
		pegs => 1
	} }, $model);
	for (my $i=0; $i < @{$rxns}; $i++) {
		my $rxn = $rxns->[$i];
		my $rxnrow = [$rxn->{REACTION},"","","","",$rxn->{compartment},"",$rxn->{pegs}];
		if (defined($rxndb->{$rxn->{REACTION}})) {
			my $rxndata = $rxndb->{$rxn->{REACTION}};
			my $dir = $rxn->{direction};
			$rxnrow->[1] = $rxndata->{name};
			$rxnrow->[2] = $rxndata->{equation};
			$rxnrow->[3] = $rxndata->{definition};
			$rxnrow->[4] = $rxndata->{enzyme};
			$rxnrow->[6] = $rxndata->{deltaG};
			$rxnrow->[2] =~ s/<=>/$dir/;
			$rxnrow->[3] =~ s/<=>/$dir/;
			$_ = $rxndata->{equation};
			my @array = /(cpd\d+)/g;
	    	for (my $j=0; $j < @array; $j++) {
	    		$cpdhash->{$array[$j]}->{$rxn->{REACTION}} = 1;
	    	}
		}
		$_ = $rxn->{pegs};
		my @array = /(peg\.\d+)/g;
	    for (my $j=0; $j < @array; $j++) {
	    	$ftrrxn->{$array[$j]}->{$rxn->{REACTION}} = 1;
	    }
		push(@{$rxntbl},$rxnrow);
	}
	foreach my $cpd (keys(%{$cpdhash})) {
		my $cpdrow = [$cpd,"","","","","",join("|",keys(%{$cpdhash->{$cpd}}))];
		if (defined($cpddb->{$cpd})) {
			my $cpddata = $cpddb->{$cpd};
			$cpdrow->[1] = $cpddata->{name};
			$cpdrow->[2] = $cpddata->{abbrev};
			$cpdrow->[3] = $cpddata->{formula};
			$cpdrow->[4] = $cpddata->{charge};
			$cpdrow->[5] = $cpddata->{deltaG};
		}
		push(@{$cpdtbl},$cpdrow);
	}
	if (-e $directory."annotations/features.txt") {
		open (my $fh, "<", $directory."annotations/features.txt");
		my @lines = <$fh>;
		close($fh);
		my $headings = [split(/\t/,shift(@lines))];
		for (my $i=0; $i < @lines;$i++) {
			my $line = $lines[$i];
			my $row = [split(/\t/,$line)];
			my $ftrrow = ["","","","","","","",""];
			for (my $j=0; $j < @{$headings}; $j++) {
				if (defined($headingTranslation->{$headings->[$j]})) {
					$ftrrow->[$headingTranslation->{$headings->[$j]}] = $row->[$j];
				}
			}
			if ($ftrrow->[0] =~ m/(peg\.\d+)/) {
				my $peg = $1;
				if (defined($ftrrxn->{$peg})) {
					$ftrrow->[7] = join("|",keys(%{$ftrrxn->{$peg}}));
				}
			}
			push(@{$ftrtbl},$ftrrow);
		}
	}
	my $wkbk = Spreadsheet::WriteExcel->new($excelfile);
	if (@{$cpdtbl} > 0) {
		my $sheet = $wkbk->add_worksheet("Compounds");
		$sheet->write_row(0,0,["ID","Name","Abbreviation","Formula","Charge","DeltaG","Reactions"]);
		for (my $i=0; $i < @{$cpdtbl}; $i++) {
			my $cpd = $cpdtbl->[$i];
			$sheet->write_row($i+1,0,$cpd);
		}
	}
	if (@{$rxntbl} > 0) {
		my $sheet = $wkbk->add_worksheet("Reactions");
		$sheet->write_row(0,0,["ID","Name","Equation","Definition","EC","Compartment","DeltaG","Pegs"]);
		for (my $i=0; $i < @{$rxntbl}; $i++) {
			my $rxn = $rxntbl->[$i];
			$sheet->write_row($i+1,0,$rxn);
		}
	}
	if (@{$ftrtbl} > 0) {
		my $sheet = $wkbk->add_worksheet("Genes");
		$sheet->write_row(0,0,["ID","Type","Functions","Contig","Start","Stop","Direction","Reactions"]);
		for (my $i=0; $i < @{$ftrtbl}; $i++) {
			my $ftr = $ftrtbl->[$i];
			$sheet->write_row($i+1,0,$ftr);
		}
	}
}
	
1;
