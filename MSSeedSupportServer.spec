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
};
