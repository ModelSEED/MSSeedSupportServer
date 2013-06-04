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
        
