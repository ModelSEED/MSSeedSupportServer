use Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportImpl;

use Bio::ModelSEED::MSSeedSupportServer::Server;
use Plack::Middleware::CrossOrigin;



my @dispatch;

{
    my $obj = Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportImpl->new;
    push(@dispatch, 'MSSeedSupportServer' => $obj);
}


my $server = Bio::ModelSEED::MSSeedSupportServer::Server->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler = Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");
