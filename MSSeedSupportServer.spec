/*
=head1 MSSeedSupportServer

=head2 SYNOPSIS

=head2 EXAMPLE OF API USE IN PERL

=head2 AUTHENTICATION

=head2 MSSEEDSUPPORTSERVER

*/
module MSSeedSupportServer {
	/* RAST job data
		
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

	*/
	typedef structure {
		string owner;
		string project;
		string id;
		string creation_time;
		string mod_time;
		int genome_size;
		int contig_count;
		string genome_id;
		string genome_name;
		string type;
    } RASTJob;
    /* RAST genome data
	
		string source;
		string genome;
		list<string> features;
		list<string> DNAsequence;
		string name;
		string taxonomy;
		int size;
		string owner;
		
	*/
	typedef structure {
		string source;
		string genome;
		list<string> features;
		list<string> DNAsequence;
		string name;
		string taxonomy;
		int size;
		string owner;
    } RastGenome;
    
    /* Input parameters for the "getRastGenomeData" function.
	
		string genome;
		int getSequences;
		int getDNASequence;
		string username;
		string password;
				
	*/
	typedef structure {
		string username;
		string password;
		string genome;
		int getSequences;
		int getDNASequence;
    } getRastGenomeData_params;
    /*
        Retrieves a RAST genome based on the input genome ID
    */
    funcdef getRastGenomeData(getRastGenomeData_params params) returns (RastGenome output);
        
    /* Input parameters for the "load_model_to_modelseed" function.
	
		string token;
		
	*/
	typedef structure {
		string username;
		string password;
		string owner;
		string genome;
		list<string> reactions;
		string biomass;
    } load_model_to_modelseed_params;
    /*
        Loads the input model to the model seed database
    */
    funcdef load_model_to_modelseed(load_model_to_modelseed_params params) returns (int success);
	
	/* Output for the "list_rast_jobs_params" function.
	
		string owner - user for whom jobs should be listed (optional - default is authenticated user)
		
	*/
	typedef structure {
		string owner;
    } list_rast_jobs_params;
    /*
        Retrieves a list of jobs owned by the specified RAST user
    */
    funcdef list_rast_jobs(list_rast_jobs_params input) returns (list<RASTJob> output)  authentication required;
			
};
