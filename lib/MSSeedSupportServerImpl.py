#BEGIN_HEADER
#END_HEADER


class MSSeedSupportServer:
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

    ######## WARNING FOR GEVENT USERS #######
    # Since asynchronous IO can lead to methods - even the same method -
    # interrupting each other, you must be *very* careful when using global
    # state. A method could easily clobber the state set by another while
    # the latter method is running.
    #########################################
    #BEGIN_CLASS_HEADER
    #END_CLASS_HEADER

    # config contains contents of config file in a hash or None if it couldn't
    # be found
    def __init__(self, config):
        #BEGIN_CONSTRUCTOR
        #END_CONSTRUCTOR
        pass

    def getRastGenomeData(self, ctx, params):
        # ctx is the context object
        # return variables are: output
        #BEGIN getRastGenomeData
        #END getRastGenomeData

        # At some point might do deeper type checking...
        if not isinstance(output, dict):
            raise ValueError('Method getRastGenomeData return value ' +
                             'output is not type dict as required.')
        # return the results
        return [output]

    def load_model_to_modelseed(self, ctx, params):
        # ctx is the context object
        # return variables are: success
        #BEGIN load_model_to_modelseed
        #END load_model_to_modelseed

        # At some point might do deeper type checking...
        if not isinstance(success, int):
            raise ValueError('Method load_model_to_modelseed return value ' +
                             'success is not type int as required.')
        # return the results
        return [success]

    def list_rast_jobs(self, ctx, params):
        # ctx is the context object
        # return variables are: output
        #BEGIN list_rast_jobs
        #END list_rast_jobs

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method list_rast_jobs return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]
