/*
=head1 MSSeedSupportServer

=head2 SYNOPSIS

=head2 EXAMPLE OF API USE IN PERL

=head2 AUTHENTICATION

=head2 MSSEEDSUPPORTSERVER

*/
module MSSeedSupportServer {
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
    
    /* SEED user account
	
		string username;
    	string password;
    	string firstname;
    	string lastname;
    	string email;
    	int id;
		
	*/
	typedef structure {
		string username;
    	string password;
    	string firstname;
    	string lastname;
    	string email;
    	int id;
    } SEEDUser;
    /* Input parameters for the "get_user_info" function.
	
		string username;
		string password;
	
	*/
	typedef structure {
		string username;
		string password;
    } get_user_info_params;
    /*
        Retrieves a RAST genome based on the input genome ID
    */
    funcdef get_user_info(get_user_info_params params) returns (SEEDUser output);

    /* Input parameters for the "authenticate" function.
	
		string token;
		
	*/
	typedef structure {
		string token;
    } authenticate_params;
    /*
        Authenticate against the SEED account
    */
    funcdef authenticate(authenticate_params params) returns (string username);
    
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

	/* Input parameters for the "create_plantseed_job" function.
	
		string username - username of owner of new genome
		string password - password of owner of new genome
		string fasta - fasta file data
		
	*/
	typedef structure {
		string username;
		string password;
		string fasta;
		string contigid;
		string source;
		string genetic_code;
		string domain;
		string scientific_name;
    } create_plantseed_job_params;
    /* Output for the "create_plantseed_job" function.
	
		string owner - owner of the plantseed genome
		string genomeid - ID of the plantseed genome
		string contigid - ID of the contigs for plantseed genome
		
	*/
	typedef structure {
		string owner;
		string genome;
		string contigs;
		string model;
		string status;
    } plantseed_job_data;
    /*
        Creates a plant seed job for the input fasta file
    */
    funcdef create_plantseed_job(create_plantseed_job_params params) returns (plantseed_job_data output);
	
	/* Input parameters for the "get_plantseed_genomes" function.
	
		string username - username of owner of new genome
		string password - password of owner of new genome
		
	*/
	typedef structure {
		string username;
		string password;
    } get_plantseed_genomes_params;
    /* Output for the "get_plantseed_genomes" function.
	
		string owner - owner of the plantseed genome
		string genome - ID of the plantseed genome
		string contigs - ID of the contigs for plantseed genome
		string model - ID of model for PlantSEED genome
		string status - status of plantseed genome
		
	*/
	typedef structure {
		string owner;
		string genome;
		string contigs;
		string model;
		string status;
    } plantseed_genomes;
    /*
        Retrieves a list of plantseed genomes owned by user
    */
    funcdef get_plantseed_genomes(get_plantseed_genomes_params params) returns (list<plantseed_genomes> output);
};
