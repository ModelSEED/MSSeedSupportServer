#BEGIN_HEADER
#END_HEADER

'''

Module Name:
MSSeedSupportServer

Module Description:
=head1 MSSeedSupportServer

=head2 SYNOPSIS

=head2 EXAMPLE OF API USE IN PERL

=head2 AUTHENTICATION

=head2 MSSEEDSUPPORTSERVER

'''
class MSSeedSupportServer:

    #BEGIN_CLASS_HEADER
    #END_CLASS_HEADER

    def __init__(self, config): #config contains contents of config file in hash or 
                                #None if it couldn't be found
        #BEGIN_CONSTRUCTOR
        #END_CONSTRUCTOR
        pass

    def getRastGenomeData(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: output
        #BEGIN getRastGenomeData
        #END getRastGenomeData

        #At some point might do deeper type checking...
        if not isinstance(output, dict):
            raise ValueError('Method getRastGenomeData return value output is not type dict as required.')
        # return the results
        return [ output ]
        
    def get_user_info(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: output
        #BEGIN get_user_info
        #END get_user_info

        #At some point might do deeper type checking...
        if not isinstance(output, dict):
            raise ValueError('Method get_user_info return value output is not type dict as required.')
        # return the results
        return [ output ]
        
    def authenticate(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: username
        #BEGIN authenticate
        #END authenticate

        #At some point might do deeper type checking...
        if not isinstance(username, basestring):
            raise ValueError('Method authenticate return value username is not type basestring as required.')
        # return the results
        return [ username ]
        
    def load_model_to_modelseed(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: success
        #BEGIN load_model_to_modelseed
        #END load_model_to_modelseed

        #At some point might do deeper type checking...
        if not isinstance(success, int):
            raise ValueError('Method load_model_to_modelseed return value success is not type int as required.')
        # return the results
        return [ success ]
        
    def create_plantseed_job(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: output
        #BEGIN create_plantseed_job
        #END create_plantseed_job

        #At some point might do deeper type checking...
        if not isinstance(output, basestring):
            raise ValueError('Method create_plantseed_job return value output is not type basestring as required.')
        # return the results
        return [ output ]
        
    def get_plantseed_genomes(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: output
        #BEGIN get_plantseed_genomes
        #END get_plantseed_genomes

        #At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method get_plantseed_genomes return value output is not type list as required.')
        # return the results
        return [ output ]
        
    def kblogin(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: authtoken
        #BEGIN kblogin
        #END kblogin

        #At some point might do deeper type checking...
        if not isinstance(authtoken, basestring):
            raise ValueError('Method kblogin return value authtoken is not type basestring as required.')
        # return the results
        return [ authtoken ]
        
    def kblogin_from_token(self, params):
        # self.ctx is set by the wsgi application class
        # return variables are: login
        #BEGIN kblogin_from_token
        #END kblogin_from_token

        #At some point might do deeper type checking...
        if not isinstance(login, basestring):
            raise ValueError('Method kblogin_from_token return value login is not type basestring as required.')
        # return the results
        return [ login ]
        
