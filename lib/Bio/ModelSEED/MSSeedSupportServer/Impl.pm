package Bio::ModelSEED::MSSeedSupportServer::Impl;
use strict;
use Bio::KBase::Exceptions;
use DBI;
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
	if ($model !~ m/^Seed\d+/) {
		return;
	}
	my $statement = "DELETE FROM ModelDB.COMPOUND_BIOMASS WHERE BIOMASS = '".$bioid."';";
	print $statement."\n\n";
	my $rxns  = $db->do($statement);
}

sub _addBiomassCompound {
	my ($self,$db,$bioid,$cpd,$coef,$comp,$cat) = @_;
	my $select = "SELECT * FROM ModelDB.COMPOUND_BIOMASS WHERE BIOMASS = ? AND COMPOUND = ?";
	my $cpds = $db->selectall_arrayref($select, { Slice => {COMPOUND => 1} }, ($model,$cpd));
	if (!defined($cpds) || !defined($cpds->[0]->{COMPOUND})) {
		$select = "INSERT INTO ModelDB.COMPOUND_BIOMASS (BIOMASS,compartment,COMPOUND,coefficient,category) ";
		$select .= "VALUES ('".$bioid."','".$comp."','".$cpd."','".$coef."','".$cat."');";
		print $select."\n\n";
		$rxns  = $db->do($select);
	} else {
		$select = "UPDATE ModelDB.COMPOUND_BIOMASS SET BIOMASS = '".$bioid."',";
		$select .= "compartment = '".$comp."',";
		$select .= "COMPOUND = '".$cpd."',";
		$select .= "coefficient = '".$coef."',";
		$select .= "category = '".$cat."'";
		$select .= " WHERE BIOMASS = '".$bioid."' AND COMPOUND = '".$cpd."';";
		print $select."\n\n";
		$rxns  = $db->do($select);
	}
}

sub _clearReactions {
	my ($self,$db,$model) = @_;
	if ($model !~ m/^Seed\d+/) {
		return;
	}
	my $statement = "DELETE FROM ModelDB.REACTION_MODEL WHERE MODEL = '".$model."';";
	print $statement."\n\n";
	my $rxns  = $db->do($statement);
}

sub _addReaction {
	my ($self,$db,$model,$rxn,$dir,$comp,$pegs) = @_;
	my $select = "SELECT * FROM ModelDB.REACTION_MODEL WHERE REACTION = ? AND MODEL = ?";
	my $rxns = $db->selectall_arrayref($select, { Slice => {MODEL => 1} }, ($model,$rxn));
	if (!defined($rxns) || !defined($rxns->[0]->{REACTION})) {
		$select = "INSERT INTO ModelDB.REACTION_MODEL (directionality,compartment,REACTION,MODEL,pegs,confidence,reference,notes) ";
		$select .= "VALUES ('".$dir."','".$comp."','".$rxn."','".$model."','".$pegs."','3','NONE','NONE');";
		print $select."\n\n";
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
		print $select."\n\n";
		$rxns  = $db->do($select);
	}
}

sub _updateGenome {
	my ($self,$db,$data) = @_;
    my $select = "SELECT * FROM ModelDB.GENOMESTATS WHERE GENOME = ?";
	my $genomes = $db->selectall_arrayref($select, { Slice => {id => 1}}, $data->{id});
	if (!defined($genomes) || !defined($genomes->[0]->{id})) {        
        my $statement = "INSERT INTO ModelDB.GENOMESTATS ('genesInSubsystems','owner','source','genes','GENOME','name','taxonomy',".
        	"'gramNegGenes','size','gramPosGenes','public','genesWithFunctions','class','gcContent') ";
		$statement .= "VALUES ('".$data->{genesInSubsystems}."','".$data->{owner}."','".$data->{source}."','".$data->{genes}."','".$data->{id}."','".
			$data->{name}."','".$data->{taxonomy}."');";
		print $statement."\n\n";
		$genomes  = $db->do($statement);
    } else {
       	my $statement = "UPDATE ModelDB.GENOMESTATS SET 'genesInSubsystems' = '".$data->{genesInSubsystems}."',";
		$statement .= "'owner' = '".$data->{owner}."',";
		$statement .= "'source' = '".$data->{source}."',";
		$statement .= "'genes' = '".$data->{genes}."',";
		$statement .= "'GENOME' = '".$data->{id}."',";
		$statement .= "'name' = '".$data->{name}."',";
		$statement .= "'taxonomy' = '".$data->{taxonomy}."'";
		$statement .= " WHERE GENOME = '".$data->{id}."';";
		print $statement."\n\n";
		$genomes  = $db->do($statement);
    }
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
		print $statement."\n\n";
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
		print $statement."\n\n";
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
    	print $statement."\n\n";
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
		print $statement."\n\n";
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
		print $statement."\n\n";
		$bios  = $db->do($statement);
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
	my @array = /(\(\d+\.*\d*\)\scpd\d+)/g;
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
    #for (my $i=0; $i < @{$params->{reactions}};$i++) {
    for (my $i=0; $i < 5;$i++) {
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
    #$self->_updateGenome($params->{genome});
    $self->_updateModel($db,$data);
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



=cut

1;
