use FindBin qw($Bin);
use lib $Bin.'/../lib';
use Bio::ModelSEED::MSSeedSupportServer::Impl;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 0;
################################################################################
#Test intiailization: setting test config, instantiating Impl, getting auth token
################################################################################


my $impl = Bio::ModelSEED::MSSeedSupportServer::Impl->new();

my $output;
#eval {
	$test_count++;
	$output = $impl->authenticate({
		username => "reviewer",
		password => "reviewer"
	});
	ok (defined($output) && $output =~ m/^reviewer/,"Authentication successful!");
#};

#eval {
	$test_count++;
	$output = $impl->get_user_info({
		username => "reviewer",
		password => "reviewer"
	});
	ok (defined($output) && $output->{username} eq "reviewer","User data retrieval successful!");
#};

#eval {
	$output = $impl->getRastGenomeData({
		username => "reviewer",
		password => "reviewer",
		genome => "315750.3"
	});
	ok (defined($output) && $output->{source} =~ m/^RAST/,"Genome retrieval successful!");
#};

done_testing($test_count);
