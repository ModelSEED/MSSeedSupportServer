package Bio::ModelSEED::MSSeedSupportServer::Impl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

MSSeedSupportServer

=head1 DESCRIPTION

=head1 MSSeedSupportServer

=head2 SYNOPSIS

=head2 EXAMPLE OF API USE IN PERL

=head2 AUTHENTICATION

=head2 MSSEEDSUPPORTSERVER

=cut

#BEGIN_HEADER
use Spreadsheet::WriteExcel;
use DBI;
use File::Path;
use SOAP::Lite;
use Bio::KBase::fbaModelServices::Client;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::AuthToken;
sub _setContext {
	my ($self,$params) = @_;
    if (defined($params->{username}) && length($params->{username}) > 0) {
		my $user = $self->_authenticate_user($params->{username},$params->{password});
		$self->_getContext()->{_userobj} = $user;
    }
}

sub _getContext {
	my ($self) = @_;
	if (!defined($Bio::ModelSEED::MSSeedSupportServer::Server::CallContext)) {
		$Bio::ModelSEED::MSSeedSupportServer::Server::CallContext = {};
	}
	return $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
}

sub _clearContext {
	my ($self) = @_;
}

sub _error {
	my ($self,$msg,$method) = @_;
    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
    method_name => $method);
}

sub _getUserObj {
	my ($self,$username) = @_;
	my $db = $self->_webapp_db_connect();
	my $select = "SELECT * FROM User WHERE User.login = ?";
    my $columns = {
        _id       => 1,
        login     => 1,
        password  => 1,
        firstname => 1,
        lastname  => 1,
        email     => 1
    };
    my $users = $db->selectall_arrayref($select, { Slice => $columns }, $username);
	if (!defined($users) || scalar @$users == 0) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Username not found!",
        method_name => '_getUserObj');
    }
    $db->disconnect;
    return $users->[0];
}

sub _authenticate_user {
	my ($self,$username,$password) = @_;
	my $userobj = $self->_getUserObj($username);
	if ($password ne $userobj->{password} && crypt($password, $userobj->{password}) ne $userobj->{password}) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Authentication failed!",
        method_name => '_authenticate_user');
	}
	return {
		username => $userobj->{login},
		id => $userobj->{_id},
		email => $userobj->{email},
		firstname => $userobj->{firstname},
		lastname => $userobj->{lastname},
		password => $userobj->{password},
	};
}

sub _clearBiomass {
	my ($self,$db,$bioid) = @_;
	if ($bioid !~ m/^bio\d+/) {
		return;
	}
	my $statement = "DELETE FROM ModelDB.COMPOUND_BIOMASS WHERE BIOMASS = '".$bioid."';";
	#print $statement."\n\n";
	my $rxns  = $db->do($statement);
}

sub _addBiomassCompound {
	my ($self,$db,$bioid,$cpd,$coef,$comp,$cat) = @_;
	my $select = "SELECT * FROM ModelDB.COMPOUND_BIOMASS WHERE BIOMASS = ? AND COMPOUND = ?";
	my $cpds = $db->selectall_arrayref($select, { Slice => {COMPOUND => 1} }, ($bioid,$cpd));
	if (!defined($cpds) || !defined($cpds->[0]->{COMPOUND})) {
		$select = "INSERT INTO ModelDB.COMPOUND_BIOMASS (BIOMASS,compartment,COMPOUND,coefficient,category) ";
		$select .= "VALUES ('".$bioid."','".$comp."','".$cpd."','".$coef."','".$cat."');";
		#print $select."\n\n";
		$cpds  = $db->do($select);
	} else {
		$select = "UPDATE ModelDB.COMPOUND_BIOMASS SET BIOMASS = '".$bioid."',";
		$select .= "compartment = '".$comp."',";
		$select .= "COMPOUND = '".$cpd."',";
		$select .= "coefficient = '".$coef."',";
		$select .= "category = '".$cat."'";
		$select .= " WHERE BIOMASS = '".$bioid."' AND COMPOUND = '".$cpd."';";
		#print $select."\n\n";
		$cpds  = $db->do($select);
	}
}

sub _clearReactions {
	my ($self,$db,$model) = @_;
	if ($model !~ m/^Seed\d+/) {
		return;
	}
	my $statement = "DELETE FROM ModelDB.REACTION_MODEL WHERE MODEL = '".$model."';";
	#print $statement."\n\n";
	my $rxns  = $db->do($statement);
}

sub _addReaction {
	my ($self,$db,$model,$rxn,$dir,$comp,$pegs) = @_;
	my $select = "SELECT * FROM ModelDB.REACTION_MODEL WHERE REACTION = ? AND MODEL = ?";
	my $rxns = $db->selectall_arrayref($select, { Slice => {MODEL => 1} }, ($model,$rxn));
	if (!defined($rxns) || !defined($rxns->[0]->{REACTION})) {
		$select = "INSERT INTO ModelDB.REACTION_MODEL (directionality,compartment,REACTION,MODEL,pegs,confidence,reference,notes) ";
		$select .= "VALUES ('".$dir."','".$comp."','".$rxn."','".$model."','".$pegs."','3','NONE','NONE');";
		#print $select."\n\n";
		$rxns  = $db->do($select);
	} else {
		$select = "UPDATE ModelDB.REACTION_MODEL SET directionality = '".$dir."',";
		$select .= "compartment = '".$comp."',";
		$select .= "REACTION = '".$rxn."',";
		$select .= "MODEL = '".$model."',";
		$select .= "pegs = '".$pegs."',";
		$select .= "confidence = '3',";
		$select .= "reference = 'NONE',";
		$select .= "notes = 'NONE' ";
		$select .= " WHERE REACTION = '".$rxn."' AND MODEL = '".$model."';";
		#print $select."\n\n";
		$rxns  = $db->do($select);
	}
}

sub _updateGenome {
	my ($self,$db,$data) = @_;
    my $select = "SELECT * FROM ModelDB.GENOMESTATS WHERE GENOME = ?";
	my $genomes = $db->selectall_arrayref($select, { Slice => {GENOME => 1}}, $data->{id});
	if (!defined($genomes) || !defined($genomes->[0]->{GENOME})) {        
        my $statement = "INSERT INTO ModelDB.GENOMESTATS (genesInSubsystems,owner,source,genes,GENOME,name,taxonomy,".
        	"gramNegGenes,size,gramPosGenes,public,genesWithFunctions,class,gcContent) ";
		$statement .= "VALUES ('0','".$data->{owner}."','".$data->{source}."','".$data->{genes}."','".$data->{id}."','".
			$data->{name}."','".$data->{taxonomy}."','0','".$data->{size}."','0','0','".$data->{genes}."','".$data->{class}."','".$data->{gc}."');";
		#print $statement."\n\n";
		$genomes  = $db->do($statement);
    } else {
       	my $statement = "UPDATE ModelDB.GENOMESTATS SET genesInSubsystems = '0',";
		$statement .= "owner = '".$data->{owner}."',";
		$statement .= "source = '".$data->{source}."',";
		$statement .= "genes = '".$data->{genes}."',";
		$statement .= "GENOME = '".$data->{id}."',";
		$statement .= "name = '".$data->{name}."',";
		$statement .= "taxonomy = '".$data->{taxonomy}."',";
		$statement .= "gramNegGenes = '0',";
		$statement .= "size = '".$data->{size}."',";
		$statement .= "gramPosGenes = '0',";
		$statement .= "public = '0',";
		$statement .= "genesWithFunctions = '".$data->{genes}."',";
		$statement .= "class = '".$data->{class}."',";
		$statement .= "gcContent = '".$data->{gc}."'";
		$statement .= " WHERE GENOME = '".$data->{id}."';";
		#print $statement."\n\n";
		$genomes  = $db->do($statement);
    }
}

sub _printGenome {
	my ($self,$model,$owner,$genome) = @_;
	if (!-d "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$model."/0/annotations/") {
		File::Path::mkpath "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$model."/0/annotations/";
	}
    my $filename = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$model."/0/annotations/features.txt";
    open (my $fh, ">", $filename) || $self->_error("Couldn't open $filename: $!","_printGenome");
    print $fh "ID	GENOME	ESSENTIALITY	ALIASES	TYPE	LOCATION	LENGTH	DIRECTION	MIN LOCATION	MAX LOCATION	ROLES	SOURCE	SEQUENCE\n";
    for (my $i=0; $i < @{$genome->{features}}; $i++) {
    	my $ftr = $genome->{features}->[$i];
    	print $fh $ftr->{id}."\t".$genome->{id}."\t".$ftr->{ess}."\t".$ftr->{aliases}."\t".
    		$ftr->{type}."\t".$ftr->{location}."\t".$ftr->{"length"}."\t".$ftr->{direction}."\t".
    		$ftr->{min}."\t".$ftr->{max}."\t".$ftr->{roles}."\t".$genome->{source}."\t".$ftr->{sequence}."\n";
    }
    close($fh);
}

sub _updateModel {
	my ($self,$db,$data) = @_;
	my $select = "SELECT * FROM ModelDB.MODEL WHERE id = ?";
	my $mdls = $db->selectall_arrayref($select, { Slice => {id => 1}}, $data->{id});
	if (!defined($mdls) || !defined($mdls->[0]->{id})) {
        my $statement = "INSERT INTO ModelDB.MODEL (source,public,status,autocompleteDate,builtDate,spontaneousReactions,gapFillReactions,".
        "associatedGenes,genome,reactions,modificationDate,id,biologReactions,owner,autoCompleteMedia,transporters,version,".
        "autoCompleteReactions,compounds,autoCompleteTime,message,associatedSubsystemGenes,autocompleteVersion,cellwalltype,".
        "biomassReaction,growth,noGrowthCompounds,autocompletionDualityGap,autocompletionObjective,name,defaultStudyMedia) ";
		$statement .= "VALUES ('".$data->{source}."','".$data->{public}."','".$data->{status}."','".$data->{autocompleteDate}."','".$data->{builtDate}."','".
			$data->{spontaneousReactions}."','".$data->{gapFillReactions}."','".$data->{associatedGenes}."','".$data->{genome}."','".
			$data->{reactions}."','".$data->{modificationDate}."','".$data->{id}."','".$data->{biologReactions}."','".
			$data->{owner}."','".$data->{autoCompleteMedia}."','".$data->{transporters}."','".$data->{version}."','".
			$data->{autoCompleteReactions}."','".$data->{compounds}."','".$data->{autoCompleteTime}."','".$data->{message}."','".
			$data->{associatedSubsystemGenes}."','".$data->{autocompleteVersion}."','".$data->{cellwalltype}."','".$data->{biomassReaction}."','".
			$data->{growth}."','".$data->{noGrowthCompounds}."','".$data->{autocompletionDualityGap}."','".$data->{autocompletionObjective}."','".
			$data->{name}."','".$data->{defaultStudyMedia}."');";
		#print $statement."\n\n";
		$mdls  = $db->do($statement);
    } else {
       	my $statement = "UPDATE ModelDB.MODEL SET source = '".$data->{source}."',";
		$statement .= "public = '".$data->{public}."',";
		$statement .= "status = '".$data->{status}."',";
		$statement .= "autocompleteDate = '".$data->{autocompleteDate}."',";
		$statement .= "builtDate = '".$data->{builtDate}."',";
		$statement .= "spontaneousReactions = '".$data->{spontaneousReactions}."',";
		$statement .= "gapFillReactions = '".$data->{gapFillReactions}."',";
		$statement .= "associatedGenes = '".$data->{associatedGenes}."',";
		$statement .= "reactions = '".$data->{reactions}."',";
		$statement .= "modificationDate = '".$data->{modificationDate}."',";
		$statement .= "id = '".$data->{id}."',";
		$statement .= "biologReactions = '".$data->{biologReactions}."',";
		$statement .= "autoCompleteMedia = '".$data->{autoCompleteMedia}."',";
		$statement .= "cellwalltype = '".$data->{cellwalltype}."',";
		$statement .= "biomassReaction = '".$data->{biomassReaction}."',";
		$statement .= "growth = '".$data->{growth}."',";
		$statement .= "noGrowthCompounds = '".$data->{noGrowthCompounds}."',";
		$statement .= "autocompletionDualityGap = '".$data->{autocompletionDualityGap}."',";
		$statement .= "autocompletionObjective = '".$data->{autocompletionObjective}."',";
		$statement .= "name = '".$data->{name}."',";
		$statement .= "defaultStudyMedia = '".$data->{defaultStudyMedia}."'";
		$statement .= " WHERE id = '".$data->{id}."';";
		#print $statement."\n\n";
		$mdls  = $db->do($statement);
    }
}

sub _getBiomassID {
	my ($self,$db) = @_;
	my $continue = 1;
	my $currid;
	while ($continue == 1) {
		my $select = "SELECT * FROM ModelDB.CURRENTID WHERE object = ?";
		my $currids = $db->selectall_arrayref($select, { Slice => {id => 1} }, "bof");
		$currid = $currids->[0]->{id};
		my $statement = "UPDATE ModelDB.CURRENTID SET id = '".($currid+1)."' WHERE id = '".$currid."' AND object = 'bof';";
    	#print $statement."\n\n";
		$currids  = $db->do($statement);
    	if ($currids == 1) {
    		$continue = 0;
    	}
	};
	$currid = "bio".$currid;
	return $currid;
}

sub _getModelData {
	my ($self,$db,$owner,$genome) = @_;
	my $userobj = $self->_getUserObj($owner);
	my $modelid = "Seed".$genome.".".$userobj->{_id};
	my $select = "SELECT * FROM ModelDB.MODEL WHERE id = ?";
	my $models = $db->selectall_arrayref($select, { Slice => {
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
	} }, $modelid);
	if (!defined($models) || !defined($models->[0]->{id})) {
        return {
        	id => $modelid,
        	source => "Unknown",
        	public => 0,
			name => "Unknown",
			genome => $genome,
			owner => $owner   	
        };
    }
    if (!defined($models->[0]->{id})) {
    	$models->[0] = {
        	id => $modelid,
        	source => "Unknown",
        	public => 0,
			name => "Unknown",
			genome => $genome,
			owner => $owner    	
        };
    }
	return $models->[0];
}

sub _addBiomass {
	my ($self,$db,$owner,$genome,$equation,$bioid) = @_;
	my $select = "SELECT * FROM ModelDB.BIOMASS WHERE id = ?";
	my $bios = $db->selectall_arrayref($select, { Slice => {id => 1}}, $bioid);
	if (!defined($bios) || !defined($bios->[0]->{id})) {
        my $statement = "INSERT INTO ModelDB.BIOMASS (owner,name,public,equation,modificationDate,creationDate,id,cofactorPackage,lipidPackage,cellWallPackage,protein,DNA,RNA,lipid,cellWall,cofactor,DNACoef,RNACoef,proteinCoef,lipidCoef,cellWallCoef,cofactorCoef,essentialRxn,energy,unknownPackage,unknownCoef) ";
		$statement .= "VALUES ('".$owner."','".$bioid."','0','".$equation."','".time()."','".time()."','".$bioid."','NONE','NONE','NONE','0.5284','0.026','0.0655','0.075','0.25','0.1','NONE','NONE','NONE','NONE','NONE','NONE','NONE','40','NONE','NONE');";
		#print $statement."\n\n";
		$bios  = $db->do($statement);
    } else {
       	my $statement = "UPDATE ModelDB.BIOMASS SET owner = '".$owner."',";
		$statement .= "name = '".$bioid."',";
		$statement .= "public = '0',";
		$statement .= "equation = '".$equation."',";
		$statement .= "modificationDate = '".time()."',";
		$statement .= "creationDate = '".time()."',";
		$statement .= "id = '".$bioid."',";
		$statement .= "cofactorPackage = 'NONE',";
		$statement .= "lipidPackage = 'NONE',";
		$statement .= "cellWallPackage = 'NONE',";
		$statement .= "protein = '0.5284',";
		$statement .= "DNA = '0.026',";
		$statement .= "RNA = '0.0655',";
		$statement .= "lipid = '0.075',";
		$statement .= "cellWall = '0.25',";
		$statement .= "cofactor = '0.1',";
		$statement .= "DNACoef = 'NONE',";
		$statement .= "RNACoef = 'NONE',";
		$statement .= "proteinCoef = 'NONE',";
		$statement .= "lipidCoef = 'NONE',";
		$statement .= "cellWallCoef = 'NONE',";
		$statement .= "cofactorCoef = 'NONE',";
		$statement .= "essentialRxn = 'NONE',";
		$statement .= "energy = 'NONE',";
		$statement .= "unknownPackage = '40',";
		$statement .= "unknownCoef = 'NONE'";
		$statement .= " WHERE id = '".$bioid."';";
		#print $statement."\n\n";
		$bios  = $db->do($statement);
    }
}

sub _rxndb {
	my ($self) = @_;
	if (!defined($self->{_rxndb})) {
		my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
		$self->{_rxndb} = {};
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
			$self->{_rxndb}->{$rxns->[$i]->{id}} = $rxns->[$i]
		}
		$db->disconnect();
	}
	return $self->{_rxndb};
}

sub _cpddb {
	my ($self) = @_;
	if (!defined($self->{_cpddb})) {
		my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
		$self->{_cpddb} = {};
		my $select = "SELECT * FROM ModelDB.COMPOUND;";
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
			$self->{_cpddb}->{$cpds->[$i]->{id}} = $cpds->[$i]
		}
		$db->disconnect();
	}
	return $self->{_cpddb};
}

sub _write_excel_file {
	my ($self,$db,$model,$owner) = @_;
	my $directory = "/vol/model-dev/MODEL_DEV_DB/Models2/".$owner."/".$model."/0/";
	my $excelfile = $directory."excel.xls";
	my $ftrrxn = {};
	my $cpdhash = {};
	my $cpdtbl = [];
	my $rxntbl = [];
	my $ftrtbl = [];
	my $headingTranslation = {
		ID => 0,
		TYPE => 1,
		ROLES => 2,
		"MIN LOCATION" => 3,
		"MAX LOCATION" => 4,
		DIRECTION => 5
	};
	my $select = "SELECT * FROM ModelDB.REACTION_MODEL WHERE MODEL = ?";
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
		if (defined($self->_rxndb()->{$rxn->{REACTION}})) {
			my $rxndata = $self->_rxndb()->{$rxn->{REACTION}};
			my $dir = $rxn->{directionality};
			$rxnrow->[1] = $rxndata->{name};
			$rxnrow->[2] = $rxndata->{equation};
			$rxnrow->[3] = $rxndata->{definition};
			$rxnrow->[4] = $rxndata->{enzyme};
			$rxnrow->[6] = $rxndata->{deltaG};
			$rxnrow->[2] =~ s/<=>|<=|=>/$dir/;
			$rxnrow->[3] =~ s/<=>|<=|=>/$dir/;
			$rxnrow->[2] =~ s/^=>/NONE =>/;
			$rxnrow->[3] =~ s/^=>/NONE =>/;
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
		if (defined($self->_cpddb()->{$cpd})) {
			my $cpddata = $self->_cpddb()->{$cpd};
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
					$ftrrow->[6] = join("|",keys(%{$ftrrxn->{$peg}}));
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
		$sheet->write_row(0,0,["ID","Type","Functions","Start","Stop","Direction","Reactions"]);
		for (my $i=0; $i < @{$ftrtbl}; $i++) {
			my $ftr = $ftrtbl->[$i];
			$sheet->write_row($i+1,0,$ftr);
		}
	}
}

sub _webapp_db_connect {
    my ($self) = @_;
    my $dsn = "DBI:mysql:WebAppBackend:bio-app-authdb.mcs.anl.gov:3306";
    my $user = "webappuser";
    my $db = DBI->connect($dsn, $user);
    if (!defined($db)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Could not connect to database!",
        method_name => '_authenticate_user');
    }
    return $db;
}

sub _rast_db_connect {
    my ($self) = @_;
    my $dsn = "DBI:mysql:RastProdJobCache:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    if (!defined($db)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Could not connect to database!",
        method_name => '_authenticate_user');
    }
    return $db;
}

sub _testrast_db_connect {
    my ($self) = @_;
    my $dsn = "DBI:mysql:RastTestJobCache2:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    if (!defined($db)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Could not connect to database!",
        method_name => '_authenticate_user');
    }
    return $db;
}

sub _get_rast_job {
    my ($self,$genome,$test) = @_;
    my $db;
    if (defined($test) && $test == 1) {
        $db = $self->_testrast_db_connect();
    } else {
        $db = $self->_rast_db_connect();
    }
    if (!defined($db)) {
        $self->_error("Could not connect to database!",'_get_rast_job');
    }
    my $select = "SELECT * FROM Job WHERE Job.genome_id = ?";
    my $columns = {
        _id         => 1,
        id          => 1,
        genome_id   => 1
    };
    my $jobs = $db->selectall_arrayref($select, { Slice => $columns }, $genome);
    $db->disconnect;
    return $jobs->[0];
}

sub _get_rast_job_data {
    my ($self,$genome) = @_;
    my $output = {
        directory => "/vol/public-pseed/FIGdisk/FIG/Data/Organisms/".$genome,
        source => "TEMPPUBSEED"
    };
    if (-d "/vol/public-pseed/FIGdisk/FIG/Data/Organisms/".$genome."/") {
        return $output;
	}
    my $job = $self->_get_rast_job($genome,1);
    if (!defined($job)) {
        $job = $self->_get_rast_job($genome);
        if (defined($job)) {
            $output->{directory} = "/vol/rast-prod/jobs/".$job->{id}."/rp/".$genome;
            $output->{source} = "RAST:".$job->{id};
            $output->{owner} = $self->_load_single_column_file("/vol/rast-prod/jobs/".$job->{id}."/USER","\t")->[0];
        }
    } else {
    	$output->{directory} = "/vol/rast-test/jobs/".$job->{id}."/rp/".$genome;
    	$output->{source} = "TESTRAST:".$job->{id};
        $output->{owner} = $self->_load_single_column_file("/vol/rast-test/jobs/".$job->{id}."/USER","\t")->[0];  
    }
    if ($output->{source} =~ m/^RAST/ || $output->{source} =~ m/^TESTRAST/) {
        if ($self->_user() eq "public") {
            $self->_error("Must be authenticated to access model!",'getRastGenomeData');
        } elsif ($self->_user() ne "chenry") {
            if ($self->_has_right($genome) == 0) {
                $self->_error("Donot have rights to genome!",'_get_rast_job_data');
            }
        }
    }
    return $output;
}

sub _user {
	my ($self) = @_;
	if (defined($self->_getContext()->{_userobj})) {
		return $self->_getContext()->{_userobj}->{username};
	}
	return "public";
}

sub _userobj {
	my ($self) = @_;
	if (defined($self->_getContext()->{_userobj})) {
		return $self->_getContext()->{_userobj};
	}
	return undef;
}

sub _has_right {
    my ($self,$genome) = @_;
    my $db = $self->_webapp_db_connect();
	if (!defined($db)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Could not connect to database!",
        method_name => '_authenticate_user');
    }
    my $select = "SELECT * FROM UserHasScope WHERE UserHasScope.user = ?";
    my $columns = {
        user      => 1,
        scope     => 1,
    };
    my $scopes = $db->selectall_arrayref($select, { Slice => $columns }, $self->_userobj()->{id});
    for (my $i=0; $i < @{$scopes}; $i++) {
        my $select = "SELECT * FROM Rights WHERE Rights.scope = ? AND Rights.data_type = ? AND Rights.data_id = ? AND Rights.granted = ?";
        my $columns = {
            scope     => 1,
            data_type => 1,
            data_id => 1,
            granted => 1
        };
        my $rights = $db->selectall_arrayref($select, { Slice => $columns }, ($scopes->[$i]->{scope},"genome",$genome,1));
        if (defined($rights->[0])) {
            $db->disconnect;
            return 1;
        }
    }
    $db->disconnect;
    return 0;
}

sub _load_single_column_file {
    my ($self,$filename) = @_;
    my $array = [];
    open (my $fh, "<", $filename) || $self->_error("Couldn't open $filename: $!","_load_single_column_file");
    while (my $Line = <$fh>) {
        chomp($Line);
        $Line =~ s/\r//;
        push(@{$array},$Line);
    }
    close($fh);
    return $array;
}

sub _roles_of_function {
    my ($self,$function) = @_;
    return [split(/\s*;\s+|\s+[\@\/]\s+/,$function)];
}

sub _fbaserv {
    my ($self) = @_;
    return Bio::KBase::fbaModelServices::Client->new('http://140.221.85.73:4043');
}

sub _wsserv {
    my ($self) = @_;
    return Bio::KBase::workspaceService::Client->new('http://www.kbase.us/services/workspace_service/');
}

sub _validateargs {
	my ($self,$args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Arguments not hash",
		method_name => '_validateargs');
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	if (defined($mandatoryArguments)) {
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				push(@{$args->{_error}},$mandatoryArguments->[$i]);
			}
		}
	}
	if (defined($args->{_error})) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Mandatory arguments ".join("; ",@{$args->{_error}})." missing.",
		method_name => '_validateargs');
	}
	if (defined($optionalArguments)) {
		foreach my $argument (keys(%{$optionalArguments})) {
			if (!defined($args->{$argument})) {
				$args->{$argument} = $optionalArguments->{$argument};
			}
		}
	}
	return $args;
}
#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 getRastGenomeData

  $output = $obj->getRastGenomeData($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a getRastGenomeData_params
$output is a RastGenome
getRastGenomeData_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	genome has a value which is a string
	getSequences has a value which is an int
	getDNASequence has a value which is an int
RastGenome is a reference to a hash where the following keys are defined:
	source has a value which is a string
	genome has a value which is a string
	features has a value which is a reference to a list where each element is a string
	DNAsequence has a value which is a reference to a list where each element is a string
	name has a value which is a string
	taxonomy has a value which is a string
	size has a value which is an int
	owner has a value which is a string

</pre>

=end html

=begin text

$params is a getRastGenomeData_params
$output is a RastGenome
getRastGenomeData_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	genome has a value which is a string
	getSequences has a value which is an int
	getDNASequence has a value which is an int
RastGenome is a reference to a hash where the following keys are defined:
	source has a value which is a string
	genome has a value which is a string
	features has a value which is a reference to a list where each element is a string
	DNAsequence has a value which is a reference to a list where each element is a string
	name has a value which is a string
	taxonomy has a value which is a string
	size has a value which is an int
	owner has a value which is a string


=end text



=item Description

Retrieves a RAST genome based on the input genome ID

=back

=cut

sub getRastGenomeData
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to getRastGenomeData:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'getRastGenomeData');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($output);
    #BEGIN getRastGenomeData
    $self->_setContext($params);
    $params = $self->_validateargs($params,["genome"],{
		getSequences => 0,
		getDNASequence => 0
	});
    $output = {
        features => [],
		gc => 0.5,
		genome => $params->{genome},
		owner => $self->_user(),
        source => "unknown"
	};
    my $rastjob = $self->_get_rast_job_data($params->{genome});
    if (!defined($rastjob)) {
        $self->_error("Could not find genome data!",'getRastGenomeData');
    }
    $output->{source} = $rastjob->{source};
    $output->{directory} = $rastjob->{directory};
	#Loading genomes with FIGV
	require FIGV;
	my $figv = new FIGV($output->{directory});
	if (!defined($figv)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Failed to load FIGV",
        method_name => 'getRastGenomeData');
	}
	if ($params->{getDNASequence} == 1) {
		my @contigs = $figv->all_contigs($params->{genome});
		for (my $i=0; $i < @contigs; $i++) {
			my $contigLength = $figv->contig_ln($params->{genome},$contigs[$i]);
			push(@{$output->{DNAsequence}},$figv->get_dna($params->{genome},$contigs[$i],1,$contigLength));
		}
	}
	$output->{activeSubsystems} = $figv->active_subsystems($params->{genome});
	my $completetaxonomy = $self->_load_single_column_file($output->{directory}."/TAXONOMY","\t")->[0];
	$completetaxonomy =~ s/;\s/;/g;
	my $taxArray = [split(/;/,$completetaxonomy)];
	$output->{name} = pop(@{$taxArray});
	$output->{taxonomy} = join("|",@{$taxArray});
	$output->{size} = $figv->genome_szdna($params->{genome});
	my $GenomeData = $figv->all_features_detailed_fast($params->{genome});
	foreach my $Row (@{$GenomeData}) {
		my $RoleArray;
		if (defined($Row->[6])) {
			push(@{$RoleArray},@{$self->_roles_of_function($Row->[6])});
		} else {
			$RoleArray = ["NONE"];
		}
		my $AliaseArray;
		push(@{$AliaseArray},split(/,/,$Row->[2]));
		my $Sequence;
		if (defined($params->{getSequences}) && $params->{getSequences} == 1) {
			$Sequence = $figv->get_translation($Row->[0]);
		}
		my $Direction ="for";
		my @temp = split(/_/,$Row->[1]);
		if ($temp[@temp-2] > $temp[@temp-1]) {
			$Direction = "rev";
		}
        my $newRow = {
            "ID"           => [ $Row->[0] ],
            "GENOME"       => [ $params->{genome} ],
            "ALIASES"      => $AliaseArray,
            "TYPE"         => [ $Row->[3] ],
            "LOCATION"     => [ $Row->[1] ],
            "DIRECTION"    => [$Direction],
            "LENGTH"       => [ $Row->[5] - $Row->[4] ],
            "MIN LOCATION" => [ $Row->[4] ],
            "MAX LOCATION" => [ $Row->[5] ],
            "SOURCE"       => [ $output->{source} ],
            "ROLES"        => $RoleArray
        };
		if (defined($Sequence) && length($Sequence) > 0) {
			$newRow->{SEQUENCE}->[0] = $Sequence;
		}
        push(@{$output->{features}}, $newRow);
	}
    $self->_clearContext();
    #END getRastGenomeData
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to getRastGenomeData:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'getRastGenomeData');
    }
    return($output);
}




=head2 get_user_info

  $output = $obj->get_user_info($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_user_info_params
$output is a SEEDUser
get_user_info_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
SEEDUser is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	firstname has a value which is a string
	lastname has a value which is a string
	email has a value which is a string
	id has a value which is an int

</pre>

=end html

=begin text

$params is a get_user_info_params
$output is a SEEDUser
get_user_info_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
SEEDUser is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	firstname has a value which is a string
	lastname has a value which is a string
	email has a value which is a string
	id has a value which is an int


=end text



=item Description

Retrieves a RAST genome based on the input genome ID

=back

=cut

sub get_user_info
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_user_info:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_user_info');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($output);
    #BEGIN get_user_info
    $self->_setContext($params);
    $params = $self->_validateargs($params,[],{});
    if (!defined($self->_userobj())) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Must provide valid username and password!",
        method_name => 'get_user_info');
    }
	$output = $self->_userobj();
    #END get_user_info
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_user_info:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_user_info');
    }
    return($output);
}




=head2 authenticate

  $username = $obj->authenticate($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an authenticate_params
$username is a string
authenticate_params is a reference to a hash where the following keys are defined:
	token has a value which is a string

</pre>

=end html

=begin text

$params is an authenticate_params
$username is a string
authenticate_params is a reference to a hash where the following keys are defined:
	token has a value which is a string


=end text



=item Description

Authenticate against the SEED account

=back

=cut

sub authenticate
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to authenticate:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'authenticate');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($username);
    #BEGIN authenticate
    $self->_setContext($params);
    $params = $self->_validateargs($params,[],{});
    if (!defined($self->_userobj())) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Must provide valid username and password!",
        method_name => 'get_user_info');
    }
    return $self->_userobj()->{username}."\t".$self->_userobj()->{password};
    #END authenticate
    my @_bad_returns;
    (!ref($username)) or push(@_bad_returns, "Invalid type for return variable \"username\" (value was \"$username\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to authenticate:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'authenticate');
    }
    return($username);
}




=head2 load_model_to_modelseed

  $success = $obj->load_model_to_modelseed($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a load_model_to_modelseed_params
$success is an int
load_model_to_modelseed_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	owner has a value which is a string
	genome has a value which is a string
	reactions has a value which is a reference to a list where each element is a string
	biomass has a value which is a string

</pre>

=end html

=begin text

$params is a load_model_to_modelseed_params
$success is an int
load_model_to_modelseed_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	owner has a value which is a string
	genome has a value which is a string
	reactions has a value which is a reference to a list where each element is a string
	biomass has a value which is a string


=end text



=item Description

Loads the input model to the model seed database

=back

=cut

sub load_model_to_modelseed
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to load_model_to_modelseed:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_model_to_modelseed');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($success);
    #BEGIN load_model_to_modelseed
    $self->_setContext($params);
    $params = $self->_validateargs($params,["genome","owner","reactions","biomass","cellwalltype","status"],{});
    #Getting model data
    my $db = DBI->connect("DBI:mysql:ModelDB:bio-app-authdb.mcs.anl.gov:3306","webappuser");
    my $data = $self->_getModelData($db,$params->{owner},$params->{genome}->{id});
    $data->{source} = $params->{genome}->{source};
    $data->{name} = $params->{genome}->{name};
    $data->{status} = $params->{status};
    $data->{spontaneousReactions} = 0;
    $data->{defaultStudyMedia} = "Complete";
    $data->{autoCompleteMedia} = "Complete";
    $data->{autocompletionObjective} = -1;
    $data->{autocompletionDualityGap} = -1;
    $data->{noGrowthCompounds} = "NONE";
    $data->{builtDate} = time();
    $data->{modificationDate} = time();
    $data->{autocompleteDate} = -1;
    $data->{gapFillReactions} = 0;
    $data->{associatedGenes} = 0;
    $data->{reactions} = 0;
    $data->{biologReactions} = 0;
    $data->{transporters} = 0;
    $data->{autoCompleteReactions} = 0;
    $data->{autocompleteVersion} = 0;
    $data->{autoCompleteTime} = -1;
    $data->{version} = 0;
    $data->{compounds} = 0;
    $data->{message} = "Model reconstruction complete";
    $data->{associatedSubsystemGenes} = 0;
    $data->{cellwalltype} = $params->{cellwalltype};
    $data->{growth} = 0;
    #Updating the biomass table
    my $bioid = $data->{biomassReaction};
    if (!defined($bioid) || $bioid eq "NONE") {
    	$bioid = $self->_getBiomassID($db);
    	$data->{biomassReaction} = $bioid;
    }
    $self->_addBiomass($db,$params->{owner},$params->{genome}->{id},$params->{biomass},$bioid);
    $self->_clearBiomass($db,$bioid);
    my $parts = [split(/=/,$params->{biomass})];
    $_ = $parts->[0];
	my @array = /(\(\d+\.*\d*\)\scpd\d+)/g;
    for (my $j=0; $j < @array; $j++) {
    	my $cpd = $array[$j];
    	if ($cpd =~ m/\((\d+\.*\d*)\)\s(cpd\d+)/) {
    		my $coef = $1;
    		my $cpd = $2;
    		my $comp = "c";
    		my $cat = "C";
    		$self->_addBiomassCompound($db,$bioid,$cpd,-1*$coef,$comp,$cat);
    	}
    }
    $_ = $parts->[1];
	@array = /(\(\d+\.*\d*\)\scpd\d+)/g;
    for (my $j=0; $j < @array; $j++) {
    	my $cpd = $array[$j];
    	if ($cpd =~ m/\((\d+\.*\d*)\)\s(cpd\d+)/) {
    		my $coef = $1;
    		my $cpd = $2;
    		my $comp = "c";
    		my $cat = "C";
    		$self->_addBiomassCompound($db,$bioid,$cpd,$coef,$comp,$cat);
    	}
    }
    #Updating the rxnmdl table
    my $cpdhash = {};
    my $genehash = {};
    my $spontenous = {
    	rxn00062 => 1,
    	rxn01208 => 1,
    	rxn04132 => 1,
    	rxn04133 => 1,
    	rxn05319 => 1,
    	rxn05467 => 1,
    	rxn05468 => 1,
    	rxn02374 => 1,
    	rxn05116 => 1,
    	rxn03012 => 1,
    	rxn05064 => 1,
    	rxn02666 => 1,
    	rxn04457 => 1,
    	rxn04456 => 1,
    	rxn01664 => 1,
    	rxn02916 => 1,
    	rxn05667 => 1
    };
    $self->_clearReactions($db,$data->{id});
    for (my $i=0; $i < @{$params->{reactions}};$i++) {
    	my $rxn = $params->{reactions}->[$i];
    	$self->_addReaction($db,$data->{id},$rxn->{id},$rxn->{direction},$rxn->{compartment},$rxn->{pegs});
    	$data->{reactions}++;
    	if (defined($spontenous->{$rxn->{id}})) {
    		$data->{spontaneousReactions}++;
    	} elsif ($rxn->{pegs} eq "Unknown") {
    		$data->{autoCompleteReactions}++;
    	} else {
	    	$_ = $rxn->{pegs};
			@array = /(peg\.\d+)/g;
	    	for (my $j=0; $j < @array; $j++) {
	    		$genehash->{$array[$j]} = 1;
	    	}
	    	$_ = $rxn->{equation};
	    	@array = /(cpd\d+)/g;
	    	for (my $j=0; $j < @array; $j++) {
	    		$cpdhash->{$array[$j]} = 1;
	    	}
    	}
    	if ($rxn->{equation} =~ m/e0/) {
    		$data->{transporters}++;
    	}
    }
    $data->{associatedGenes} = keys(%{$genehash});
    $data->{compounds} = keys(%{$cpdhash});
    $self->_addReaction($db,$data->{id},$bioid,"=>","c","BOF");
    #Updating the model table
    $self->_updateGenome($db,$params->{genome});
    $self->_printGenome($data->{id},$params->{owner},$params->{genome});
    $self->_updateModel($db,$data);
    $self->_write_excel_file($db,$data->{id},$params->{owner});
    $success = 1;
    $db->disconnect();
    #END load_model_to_modelseed
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to load_model_to_modelseed:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_model_to_modelseed');
    }
    return($success);
}




=head2 create_plantseed_job

  $output = $obj->create_plantseed_job($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a create_plantseed_job_params
$output is a plantseed_job_data
create_plantseed_job_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	fasta has a value which is a string
	contigid has a value which is a string
	source has a value which is a string
	genetic_code has a value which is a string
	domain has a value which is a string
	scientific_name has a value which is a string
plantseed_job_data is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	genome has a value which is a string
	contigs has a value which is a string
	model has a value which is a string
	status has a value which is a string

</pre>

=end html

=begin text

$params is a create_plantseed_job_params
$output is a plantseed_job_data
create_plantseed_job_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
	fasta has a value which is a string
	contigid has a value which is a string
	source has a value which is a string
	genetic_code has a value which is a string
	domain has a value which is a string
	scientific_name has a value which is a string
plantseed_job_data is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	genome has a value which is a string
	contigs has a value which is a string
	model has a value which is a string
	status has a value which is a string


=end text



=item Description

Creates a plant seed job for the input fasta file

=back

=cut

sub create_plantseed_job
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_plantseed_job:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_plantseed_job');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($output);
    #BEGIN create_plantseed_job
    $self->_setContext($params);
    $params = $self->_validateargs($params,["fasta","proteins","name"],{});
    #Making sure a user is logged in
    if (!defined($self->_userobj())) {
    	$self->_error("Must be logged in to create PlantSEED job!","create_plantseed_job");
    }
    #Getting KBase auth token for PlantSEED workspace
    my $auth = join("\n",@{$self->_load_single_column_file("/vol/model-prod/plantseed-auth")});
    #Getting new genome ID for PlantSEED genome
    my $service_url = "http://clearinghouse.theseed.org/Clearinghouse/clearinghouse_services.cgi";
	my $proxy = SOAP::Lite->uri('http://www.soaplite.com/Scripts')->proxy($service_url);
	my $r = $proxy->register_genome("7777777");
	if ($r->fault) {
	    $self->_error("Failed to register 7777777 with ACH: ".$r->faultcode .":".$r->faultstring);
	}
    my $genomeid = "7777777".$r->result();
    my $object;
    if ($params->{proteins}) {
    	$object = $self->_fbaserv()->fasta_to_ProteinSet({
    		uid => "ProteinSet.".$genomeid.".".$self->_userobj()->{_id},
    		fasta => $params->{fasta},
    		workspace => "Private_PlantSEED",
    		auth => $auth,
    		name => $params->{name},
    		sourceid => $genomeid,
    		source => "PlantSEED",
    		type => "Plant"
    	});
    	$object = $self->_fbaserv()->ProteinSet_to_Genome({
    		ProteinSet_uid => "ProteinSet.".$genomeid.".".$self->_userobj()->{_id},
    		ProteinSet_ws => "Private_PlantSEED",
    		workspace => "Private_PlantSEED",
    		uid => $genomeid.".".$self->_userobj()->{_id},
    		auth => $auth,
    		scientific_name => $params->{name},
    		domain => "Plant",
    		genetic_code => 11
    	});
    } else {
    	$object = $self->_fbaserv()->fasta_to_TranscriptSet({
    		uid => "TranscriptSet.".$genomeid.".".$self->_userobj()->{_id},
    		fasta => $params->{fasta},
    		workspace => "Private_PlantSEED",
    		auth => $auth,
    		name => $params->{name},
    		sourceid => $genomeid,
    		source => "PlantSEED",
    		type => "Plant"
    	});
    	$object = $self->_fbaserv()->TranscriptSet_to_Genome({
    		TranscriptSet_uid => "TranscriptSet.".$genomeid.".".$self->_userobj()->{_id},
    		TranscriptSet_ws => "Private_PlantSEED",
    		workspace => "Private_PlantSEED",
    		uid => $genomeid.".".$self->_userobj()->{_id},
    		auth => $auth,
    		scientific_name => $params->{name},
    		domain => "Plant",
    		genetic_code => 11
    	});
    }
    $object = $self->_fbaserv()->annotate_workspace_Genome({
    	Genome_ws => "Private_PlantSEED",
    	workspace => "Private_PlantSEED",
    	Genome_uid => $genomeid.".".$self->_userobj()->{_id},
    	auth => $auth,
    });
    return {
    	genomeid => $genomeid
    };
    #END create_plantseed_job
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_plantseed_job:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_plantseed_job');
    }
    return($output);
}




=head2 get_plantseed_genomes

  $output = $obj->get_plantseed_genomes($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_plantseed_genomes_params
$output is a reference to a list where each element is a plantseed_genomes
get_plantseed_genomes_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
plantseed_genomes is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	genome has a value which is a string
	contigs has a value which is a string
	model has a value which is a string
	status has a value which is a string

</pre>

=end html

=begin text

$params is a get_plantseed_genomes_params
$output is a reference to a list where each element is a plantseed_genomes
get_plantseed_genomes_params is a reference to a hash where the following keys are defined:
	username has a value which is a string
	password has a value which is a string
plantseed_genomes is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	genome has a value which is a string
	contigs has a value which is a string
	model has a value which is a string
	status has a value which is a string


=end text



=item Description

Retrieves a list of plantseed genomes owned by user

=back

=cut

sub get_plantseed_genomes
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_plantseed_genomes:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_plantseed_genomes');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($output);
    #BEGIN get_plantseed_genomes
    $self->_setContext($params);
    $params = $self->_validateargs($params,[],{});
    if (!defined($self->_userobj())) {
    	$self->_error("Must be logged in to retrieve PlantSEED job!","get_plantseed_genomes");
    }
    my $auth = join("\n",@{$self->_load_single_column_file("/vol/model-prod/plantseed-auth")});  
    my $objs = $self->_wsserv()->list_workspace_objects({
    	workspace => "Private_PlantSEED",
    	type => "Genome",
    	auth => $auth
    });
    my $mdlobjs = $self->_wsserv()->list_workspace_objects({
    	workspace => "Private_PlantSEED",
    	type => "Model",
    	auth => $auth
    });
    my $models = {};
    for (my $i=0; $i < @{$mdlobjs}; $i++) {
    	$models->{$mdlobjs->[$i]->[0]} = $mdlobjs->[$i];
    }
    $output = [];
    for (my $i=0; $i < @{$objs}; $i++) {
    	if ($objs->[$i]->[0] =~ m/(\d+\.\d+)\.(\d+)/) {
    		my $genome = $1;
    		if ($2 eq $self->_userobj()->{_id}) {
    			my ($comps,$rxns,$mdlftrs,$cpds,$biocpds) = ("","","","","");
    			my $status = "building";
    			if (defined($models->{"PlantSEED".$objs->[$i]->[0]})) {
    				$status = "complete";
    				$comps = $models->{"PlantSEED".$objs->[$i]->[0]}->{number_compartments};
    				$cpds = $models->{"PlantSEED".$objs->[$i]->[0]}->{number_compounds};
    				$rxns = $models->{"PlantSEED".$objs->[$i]->[0]}->{number_reactions};
    				$mdlftrs = $models->{"PlantSEED".$objs->[$i]->[0]}->{number_genes};
    				$biocpds = $models->{"PlantSEED".$objs->[$i]->[0]}->{number_biomasscpd};
    			}
    			push(@{$output},{
		    		owner => $self->_userobj()->{login},
					id => $genome,
					name => $objs->[$i]->[10]->{scientific_name},
					features => $objs->[$i]->[10]->{number_features},
					size => $objs->[$i]->[10]->{size},
					status => $status,
					model => "PlantSEED".$genome,
					compartments => $comps,
					reactions => $rxns,
					modelfeatures => $mdlftrs,
					compounds => $cpds,
					biomasscpds => $biocpds
		    	}); $objs->[$i];
    		}
    	}
    }
    return $output;
    #END get_plantseed_genomes
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_plantseed_genomes:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_plantseed_genomes');
    }
    return($output);
}




=head2 kblogin

  $authtoken = $obj->kblogin($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a kblogin_params
$authtoken is a string
kblogin_params is a reference to a hash where the following keys are defined:
	kblogin has a value which is a string
	kbpassword has a value which is a string

</pre>

=end html

=begin text

$params is a kblogin_params
$authtoken is a string
kblogin_params is a reference to a hash where the following keys are defined:
	kblogin has a value which is a string
	kbpassword has a value which is a string


=end text



=item Description

Login for specified kbase account

=back

=cut

sub kblogin
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to kblogin:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'kblogin');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($authtoken);
    #BEGIN kblogin
    $self->_setContext($params);
    $params = $self->_validateargs($params,["kblogin","kbpassword"],{});
    print "One:".$params->{kblogin}."\t".$params->{kbpassword}."\n";
    my $token = Bio::KBase::AuthToken->new(user_id => $params->{kblogin}, password => $params->{kbpassword});
	print "Two:".$params->{kblogin}."\t".$params->{kbpassword}."\n";
	if (!defined($token->token())) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "KBase login failed!",
        method_name => 'kblogin');
    }
    print "Three:".$params->{kblogin}."\t".$params->{kbpassword}."\n";
	$authtoken = $token->token();
    #END kblogin
    my @_bad_returns;
    (!ref($authtoken)) or push(@_bad_returns, "Invalid type for return variable \"authtoken\" (value was \"$authtoken\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to kblogin:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'kblogin');
    }
    return($authtoken);
}




=head2 kblogin_from_token

  $login = $obj->kblogin_from_token($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a kblogin_from_token_params
$login is a string
kblogin_from_token_params is a reference to a hash where the following keys are defined:
	authtoken has a value which is a string

</pre>

=end html

=begin text

$params is a kblogin_from_token_params
$login is a string
kblogin_from_token_params is a reference to a hash where the following keys are defined:
	authtoken has a value which is a string


=end text



=item Description

Login for specified kbase auth token

=back

=cut

sub kblogin_from_token
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to kblogin_from_token:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'kblogin_from_token');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($login);
    #BEGIN kblogin_from_token
    $self->_setContext($params);
    $params = $self->_validateargs($params,["authtoken"],{});
	my $token = Bio::KBase::AuthToken->new(token => $params->{authtoken});
	if (!defined($token->user_id())) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "KBase auth token check failed!",
        method_name => 'kblogin_from_token');
    }
	$login = $token->user_id();
    #END kblogin_from_token
    my @_bad_returns;
    (!ref($login)) or push(@_bad_returns, "Invalid type for return variable \"login\" (value was \"$login\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to kblogin_from_token:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'kblogin_from_token');
    }
    return($login);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 RastGenome

=over 4



=item Description

RAST genome data

        string source;
        string genome;
        list<string> features;
        list<string> DNAsequence;
        string name;
        string taxonomy;
        int size;
        string owner;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
source has a value which is a string
genome has a value which is a string
features has a value which is a reference to a list where each element is a string
DNAsequence has a value which is a reference to a list where each element is a string
name has a value which is a string
taxonomy has a value which is a string
size has a value which is an int
owner has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
source has a value which is a string
genome has a value which is a string
features has a value which is a reference to a list where each element is a string
DNAsequence has a value which is a reference to a list where each element is a string
name has a value which is a string
taxonomy has a value which is a string
size has a value which is an int
owner has a value which is a string


=end text

=back



=head2 getRastGenomeData_params

=over 4



=item Description

Input parameters for the "getRastGenomeData" function.

        string genome;
        int getSequences;
        int getDNASequence;
        string username;
        string password;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
genome has a value which is a string
getSequences has a value which is an int
getDNASequence has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
genome has a value which is a string
getSequences has a value which is an int
getDNASequence has a value which is an int


=end text

=back



=head2 SEEDUser

=over 4



=item Description

SEED user account

        string username;
    string password;
    string firstname;
    string lastname;
    string email;
    int id;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
firstname has a value which is a string
lastname has a value which is a string
email has a value which is a string
id has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
firstname has a value which is a string
lastname has a value which is a string
email has a value which is a string
id has a value which is an int


=end text

=back



=head2 get_user_info_params

=over 4



=item Description

Input parameters for the "get_user_info" function.

        string username;
        string password;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string


=end text

=back



=head2 authenticate_params

=over 4



=item Description

Input parameters for the "authenticate" function.

        string token;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
token has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
token has a value which is a string


=end text

=back



=head2 load_model_to_modelseed_params

=over 4



=item Description

Input parameters for the "load_model_to_modelseed" function.

        string token;


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
owner has a value which is a string
genome has a value which is a string
reactions has a value which is a reference to a list where each element is a string
biomass has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
owner has a value which is a string
genome has a value which is a string
reactions has a value which is a reference to a list where each element is a string
biomass has a value which is a string


=end text

=back



=head2 create_plantseed_job_params

=over 4



=item Description

Input parameters for the "create_plantseed_job" function.

        string username - username of owner of new genome
        string password - password of owner of new genome
        string fasta - fasta file data


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
fasta has a value which is a string
contigid has a value which is a string
source has a value which is a string
genetic_code has a value which is a string
domain has a value which is a string
scientific_name has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string
fasta has a value which is a string
contigid has a value which is a string
source has a value which is a string
genetic_code has a value which is a string
domain has a value which is a string
scientific_name has a value which is a string


=end text

=back



=head2 plantseed_job_data

=over 4



=item Description

Output for the "create_plantseed_job" function.

        string owner - owner of the plantseed genome
        string genomeid - ID of the plantseed genome
        string contigid - ID of the contigs for plantseed genome


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
owner has a value which is a string
genome has a value which is a string
contigs has a value which is a string
model has a value which is a string
status has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
owner has a value which is a string
genome has a value which is a string
contigs has a value which is a string
model has a value which is a string
status has a value which is a string


=end text

=back



=head2 get_plantseed_genomes_params

=over 4



=item Description

Input parameters for the "get_plantseed_genomes" function.

        string username - username of owner of new genome
        string password - password of owner of new genome


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
username has a value which is a string
password has a value which is a string


=end text

=back



=head2 plantseed_genomes

=over 4



=item Description

Output for the "get_plantseed_genomes" function.

        string owner - owner of the plantseed genome
        string genome - ID of the plantseed genome
        string contigs - ID of the contigs for plantseed genome
        string model - ID of model for PlantSEED genome
        string status - status of plantseed genome


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
owner has a value which is a string
genome has a value which is a string
contigs has a value which is a string
model has a value which is a string
status has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
owner has a value which is a string
genome has a value which is a string
contigs has a value which is a string
model has a value which is a string
status has a value which is a string


=end text

=back



=head2 kblogin_params

=over 4



=item Description

Input for "kblogin" function.

        string kblogin - KBase username
        string kbpassword - KBase password


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
kblogin has a value which is a string
kbpassword has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
kblogin has a value which is a string
kbpassword has a value which is a string


=end text

=back



=head2 kblogin_from_token_params

=over 4



=item Description

Input for "kblogin" function.

        string kblogin - KBase username
        string kbpassword - KBase password


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
authtoken has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
authtoken has a value which is a string


=end text

=back



=cut

1;
