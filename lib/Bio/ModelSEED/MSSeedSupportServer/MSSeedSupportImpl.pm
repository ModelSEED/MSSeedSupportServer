package Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportImpl;
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
$|=1;
use Spreadsheet::WriteExcel;
use DBI;
use File::Path;
use SOAP::Lite;
use Bio::KBase::fbaModelServices::Client;
use Bio::KBase::workspaceService::Client;
use JSON::XS;
use Data::Dumper;
use Config::Simple;
use Plack::Request;

#
# Alias our context variable.
#
*Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportImpl::CallContext = *Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
our $CallContext;

#Initialization function for call
sub initialize_call {
	my ($self,$input) = @_;
	$self->{_starttime} = time();
	return $input;
}

#Check if logged user has admin privelages
sub is_admin {
	my ($self) = @_;
	if (defined($self->{_admins}->{$self->user_id()})) {
		return 1;
	}
	return 0;
}

#Returns the method supplied to the service in the context object
sub current_method {
	my ($self) = @_;
	if (defined($CallContext)) {
		return $CallContext->method;
	}
	return undef;
}

#Returns hash with current server configuration
sub config {
	my($self) = @_;
	return $self->{_config};
}

#Returns the authentication token supplied to the service in the context object
sub token {
	my($self) = @_;
	if (defined($CallContext)) {
		return $CallContext->token;
	}
	return undef;
}

#Returns the username supplied to the service in the context object
sub user_id {
	my ($self) = @_;
	if (defined($CallContext)) {
		return $CallContext->user_id;
	}
	return undef;
}

sub validate_args {
	my ($self,$args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		$self->_error("Arguments not hash");	
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	my $error = 0;
	if (defined($mandatoryArguments)) {
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				$error = 1;
				push(@{$args->{_error}},$mandatoryArguments->[$i]);
			}
		}
	}
	if ($error == 1) {
		$self->_error("Mandatory arguments ".join("; ",@{$args->{_error}})." missing.");
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

sub load_config {
	my ($self,$args) = @_;
	$args = $self->validate_args($args,[],{
		filename => $ENV{KB_DEPLOYMENT_CONFIG},
		service => $ENV{KB_SERVICE_NAME},
	});
	if (!defined($args->{service})) {
		$self->_error("No service specified!");
	}
	if (!defined($args->{filename})) {
		$self->_error("No config file specified!");
	}
	if (!-e $args->{filename}) {
		$self->_error("Specified config file ".$args->{filename}." doesn't exist!");
	}
	my $c = Config::Simple->new();
	$c->read($args->{filename});
	my $hash = $c->vars();
	my $service_config = {};
	foreach my $key (keys(%{$hash})) {
		my $array = [split(/\./,$key)];
		if ($array->[0] eq $args->{service}) {
			if ($hash->{$key} ne "null") {
				$service_config->{$array->[1]} = $hash->{$key};
			}
		}
	}
	return $service_config;
}

=head3 _error

Definition:
	$self->_error(string message,string method);
Description:
	Throws an exception
		
=cut

sub _error {
	my($self,$msg) = @_;
	$msg = "ERROR{".$msg."}ERROR";
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => $self->current_method);
}

sub get_user_object {
	my ($self,$field,$value) = @_;
	my $db = $self->webapp_db();
	my $select = "SELECT * FROM User WHERE User.";
	$select .= $field." = ?";
    my $users = $db->selectall_arrayref($select, { Slice => {} }, $value);
	if (!defined($users) || scalar @$users == 0) {
        $self->_error("Username not found!");
    }
    return $users->[0];
}

sub get_user_job_objects {
	my ($self,$field,$value) = @_;
	my $db = $self->rast_db();
	my $select = "SELECT * FROM Job WHERE Job.";
	$select .= $field." = ?";
	return $db->selectall_arrayref($select, { Slice => {} }, $value);
}

sub webapp_db {
	my ($self) = @_;
	if (!defined($self->{_webappdb})) {
    	$self->{_webappdb} = DBI->connect("DBI:mysql:WebAppBackend:bio-app-authdb.mcs.anl.gov:3306","webappuser");
    	if (!defined($self->{_webappdb})) {
        	$self->_error("Could not connect to user database!");
    	}
	}
	return $self->{_webappdb};
}

sub rast_db {
	my ($self) = @_;
	if (!defined($self->{_rast_db})) {
    	$self->{_rast_db} = DBI->connect("DBI:mysql:RastProdJobCache:rast.mcs.anl.gov:3306","rast");
    	if (!defined($self->{_rast_db})) {
        	$self->_error("Could not connect to rast database!");
    	}
	}
	return $self->{_rast_db};
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
        $self->_error("Username not found!",
        '_getUserObj');
    }
    $db->disconnect;
    return $users->[0];
}

sub _authenticate_user {
	my ($self,$username,$password) = @_;
	my $userobj = $self->_getUserObj($username);
	if ($password ne $userobj->{password} && crypt($password, $userobj->{password}) ne $userobj->{password}) {
		$self->_error("Authentication failed!",
        '_authenticate_user');
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
        $self->_error("Could not connect to database!",
        '_authenticate_user');
    }
    return $db;
}

sub _rast_db_connect {
    my ($self) = @_;
    my $dsn = "DBI:mysql:RastProdJobCache:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    if (!defined($db)) {
        $self->_error("Could not connect to database!",
        '_authenticate_user');
    }
    return $db;
}

sub _testrast_db_connect {
    my ($self) = @_;
    my $dsn = "DBI:mysql:RastTestJobCache2:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    if (!defined($db)) {
        $self->_error("Could not connect to database!",
        '_authenticate_user');
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
        $self->_error("Could not connect to database!",
        '_authenticate_user');
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
		$self->_error("Arguments not hash",
		'_validateargs');
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
		$self->_error("Mandatory arguments ".join("; ",@{$args->{_error}})." missing.",
		'_validateargs');
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
    my $params = $self->load_config({
    	service => "MSSeedSupport"
    });
    if (defined($args[0])) {
    	foreach my $key (keys(%{$args[0]})) {
    		$params->{$key} = $args[0]->{$key};
    	}
    }
	$params = $self->validate_args($params,[],{
		"admins" => undef
	});
	$self->{_admins} = {};
	if (defined($params->{admins})) {
		my $array = [split(/;/,$params->{admins})];
		for (my $i=0; $i < @{$array}; $i++) {
			$self->{_admins}->{$array->[$i]} = 1;
		}
	}
	print "Current server configuration:\n".Data::Dumper->Dump([$params]);
	$self->{_config} = $params;
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
    $params = $self->initialize_call($params);
    $params = $self->_validateargs($params,["genome"],{
		getSequences => 0,
		getDNASequence => 0
	});
	my $job = $self->_get_rast_job($params->{genome});
	if (!defined($job)) {
		$self->_error("Could not find job for genome!",'getRastGenomeData');
	}
    my $output = {
    	owner => $self->_load_single_column_file("/vol/rast-prod/jobs/".$job->{id}."/USER","\t")->[0],
    	source => "RAST:".$job->{id},
        directory => "/vol/rast-prod/jobs/".$job->{id}."/rp/".$params->{genome},
        features => [],
		gc => 0.5,
		genome => $params->{genome},
		owner => $self->_user()
	};
	#Loading genomes with FIGV
	require FIGV;
	my $figv = new FIGV($output->{directory});
	if (!defined($figv)) {
        $self->_error("Failed to load FIGV",
        'getRastGenomeData');
	}
	if ($params->{getDNASequence} == 1) {
		my @contigs = $figv->all_contigs($params->{genome});
		for (my $i=0; $i < @contigs; $i++) {
			my $contigLength = $figv->contig_ln($params->{genome},$contigs[$i]);
			push(@{$output->{DNAsequence}},$figv->get_dna($params->{genome},$contigs[$i],1,$contigLength));
		}
	}
	#$output->{activeSubsystems} = $figv->active_subsystems($params->{genome});
	my $completetaxonomy = $self->_load_single_column_file("/vol/rast-prod/jobs/".$job->{id}."/rp/".$params->{genome}."/TAXONOMY","\t")->[0];
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
#			$newRow->{SEQUENCE}->[0] = $Sequence;
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
    $params = $self->initialize_call($params);
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




=head2 list_rast_jobs

  $output = $obj->list_rast_jobs($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_rast_jobs_params
$output is a reference to a list where each element is a RASTJob
list_rast_jobs_params is a reference to a hash where the following keys are defined:
	owner has a value which is a string
RASTJob is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	project has a value which is a string
	id has a value which is a string
	creation_time has a value which is a string
	mod_time has a value which is a string
	genome_size has a value which is an int
	contig_count has a value which is an int
	genome_id has a value which is a string
	genome_name has a value which is a string
	type has a value which is a string

</pre>

=end html

=begin text

$input is a list_rast_jobs_params
$output is a reference to a list where each element is a RASTJob
list_rast_jobs_params is a reference to a hash where the following keys are defined:
	owner has a value which is a string
RASTJob is a reference to a hash where the following keys are defined:
	owner has a value which is a string
	project has a value which is a string
	id has a value which is a string
	creation_time has a value which is a string
	mod_time has a value which is a string
	genome_size has a value which is an int
	contig_count has a value which is an int
	genome_id has a value which is a string
	genome_name has a value which is a string
	type has a value which is a string


=end text



=item Description

Retrieves a list of jobs owned by the specified RAST user

=back

=cut

sub list_rast_jobs
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_rast_jobs:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_rast_jobs');
    }

    my $ctx = $Bio::ModelSEED::MSSeedSupportServer::Server::CallContext;
    my($output);
    #BEGIN list_rast_jobs
    $input = $self->initialize_call($input);
    $input = $self->validate_args($input,[],{
    	owner => $self->user_id()
    });
    if ($input->{owner} ne $self->user_id()) {
    	if ($self->is_admin() == 0) {
    		$self->_error("Cannot request another user's jobs without admin privelages");
    	}
    }
    #Retrieving user data
    my $userobj = $self->get_user_object("login",$input->{owner});
    if (!defined($userobj)) {
    	$self->_error("User ".$input->{owner}." not found!");
    }
    print STDERR "User:".$self->user_id()."\n";
    print STDERR "Owner:".$input->{owner}."\n";
    print STDERR "_id:".$userobj->{_id}."\n";
    #Retrieving jobs
    my $jobs = $self->get_user_job_objects("owner",$userobj->{_id});
    $output = [];
    for (my $i=0; $i < @{$jobs}; $i++) {
    	push(@{$output},{
    		owner => $input->{owner},
    		project => $jobs->[$i]->{project_name},
    		id => $jobs->[$i]->{id},
    		creation_time => $jobs->[$i]->{created_on},
    		mod_time => $jobs->[$i]->{last_modified},
    		genome_size => $jobs->[$i]->{genome_bp_count},
    		contig_count => $jobs->[$i]->{genome_contig_count},
    		genome_id => $jobs->[$i]->{genome_id},
			genome_name => $jobs->[$i]->{genome_name},
			type => $jobs->[$i]->{type},
    	});
    }
    #END list_rast_jobs
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_rast_jobs:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_rast_jobs');
    }
    return($output);
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



=head2 RASTJob

=over 4



=item Description

RAST job data

string owner - owner of the job
string project - project name
string id - ID of the job
string creation_time - time of creation
string mod_time - time of modification
int genome_size - size of genome
int contig_count - number of contigs
string genome_id - ID of the genome created by the job
string genome_name - name of genome
string type - type of job


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
owner has a value which is a string
project has a value which is a string
id has a value which is a string
creation_time has a value which is a string
mod_time has a value which is a string
genome_size has a value which is an int
contig_count has a value which is an int
genome_id has a value which is a string
genome_name has a value which is a string
type has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
owner has a value which is a string
project has a value which is a string
id has a value which is a string
creation_time has a value which is a string
mod_time has a value which is a string
genome_size has a value which is an int
contig_count has a value which is an int
genome_id has a value which is a string
genome_name has a value which is a string
type has a value which is a string


=end text

=back



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



=head2 list_rast_jobs_params

=over 4



=item Description

Output for the "list_rast_jobs_params" function.

        string owner - user for whom jobs should be listed (optional - default is authenticated user)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
owner has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
owner has a value which is a string


=end text

=back



=cut

1;
