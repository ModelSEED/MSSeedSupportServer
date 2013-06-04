package Bio::ModelSEED::MSSeedSupportServer::Impl;
use strict;
use DBI;
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

sub _authenticate_user {
    my ($self,$username,$password) = @_;
	my $db = $self->_webapp_db_connect();
	if (!defined($db)) {
        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Could not connect to database!",
        method_name => '_authenticate_user');
    }
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
        method_name => '_authenticate_user');
    }
   return {
    	username => $users->[0]->{login},
    	id => $users->[0]->{_id},
    	email => $users->[0]->{email},
    	firstname => $users->[0]->{firstname},
    	lastname => $users->[0]->{lastname},
    	password => $users->[0]->{password},
    };
}

sub _webapp_db_connect {
    my ($self) = @_;
    if (defined($self->{_webapp_db})) {
        return $self->{_webapp_db};
    }
    my $dsn = "DBI:mysql:WebAppBackend:bio-app-authdb.mcs.anl.gov:3306";
    my $user = "webappuser";
    my $db = DBI->connect($dsn, $user);
    $self->{_webapp_db} = $db;
    return $db;
}

sub _rast_db_connect {
    my ($self) = @_;
    if (defined($self->{_rast_db})) {
        return $self->{_rast_db};
    }
    my $dsn = "DBI:mysql:RastProdJobCache:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    $self->{_rast_db} = $db;
    return $db;
}

sub _testrast_db_connect {
    my ($self) = @_;
    if (defined($self->{_testrast_db})) {
        return $self->{_testrast_db};
    }
    my $dsn = "DBI:mysql:RastTestJobCache2:rast.mcs.anl.gov:3306";
    my $user = "rast";
    my $db = DBI->connect($dsn, $user);
    $self->{_testrast_db} = $db;
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
    return $jobs->[0];
}

sub _get_rast_job_data {
    my ($self,$genome) = @_;
    my $output = {
        directory => "/vol/public-pseed/FIGdisk/FIG/Data/Organisms/".$genome,
        source => "TEMPPUBSEED"
    };
    if (-d "/vol/public-pseed/FIGdisk/FIG/Data/Organisms/".$genome) {
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
    my $output = {
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
	#Loading genomes with FIGV
#	require FIGV;
#	my $figv = new FIGV($output->{directory});
#	if (!defined($figv)) {
#        Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Failed to load FIGV",
#        method_name => 'getRastGenomeData');
#	}
#	if ($params->{getDNASequence} == 1) {
#		my @contigs = $figv->all_contigs($params->{genome});
#		for (my $i=0; $i < @contigs; $i++) {
#			my $contigLength = $figv->contig_ln($params->{genome},$contigs[$i]);
#			push(@{$output->{DNAsequence}},$figv->get_dna($params->{genome},$contigs[$i],1,$contigLength));
#		}
#	}
#	$output->{activeSubsystems} = $figv->active_subsystems($params->{genome});
#	my $completetaxonomy = $self->_load_single_column_file($output->{directory}."/TAXONOMY","\t")->[0];
#	$completetaxonomy =~ s/;\s/;/g;
#	my $taxArray = [split(/;/,$completetaxonomy)];
#	$output->{name} = pop(@{$taxArray});
#	$output->{taxonomy} = join("|",@{$taxArray});
#	$output->{size} = $figv->genome_szdna($params->{genome});
#	my $GenomeData = $figv->all_features_detailed_fast($params->{genome});
#	foreach my $Row (@{$GenomeData}) {
#		my $RoleArray;
#		if (defined($Row->[6])) {
#			push(@{$RoleArray},$self->_roles_of_function($Row->[6]));
#		} else {
#			$RoleArray = ["NONE"];
#		}
#		my $AliaseArray;
#		push(@{$AliaseArray},split(/,/,$Row->[2]));
#		my $Sequence;
#		if (defined($params->{getSequences}) && $params->{getSequences} == 1) {
#			$Sequence = $figv->get_translation($Row->[0]);
#		}
#		my $Direction ="for";
#		my @temp = split(/_/,$Row->[1]);
#		if ($temp[@temp-2] > $temp[@temp-1]) {
#			$Direction = "rev";
#		}
#        my $newRow = {
#            "ID"           => [ $Row->[0] ],
#            "GENOME"       => [ $params->{genome} ],
#            "ALIASES"      => $AliaseArray,
#            "TYPE"         => [ $Row->[3] ],
#            "LOCATION"     => [ $Row->[1] ],
#            "DIRECTION"    => [$Direction],
#            "LENGTH"       => [ $Row->[5] - $Row->[4] ],
#            "MIN LOCATION" => [ $Row->[4] ],
#            "MAX LOCATION" => [ $Row->[5] ],
#            "SOURCE"       => [ $output->{source} ],
#            "ROLES"        => $RoleArray
#        };
#		if (defined($Sequence) && length($Sequence) > 0) {
#			$newRow->{SEQUENCE}->[0] = $Sequence;
#		}
#        push(@{$output->{features}}, $newRow);
#	}
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



=cut

1;
