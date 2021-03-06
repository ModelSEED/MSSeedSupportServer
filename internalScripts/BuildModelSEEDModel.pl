#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use File::Path;
use Data::Dumper;
use Config::Simple;
use Bio::KBase::workspace::ScriptHelpers qw(printObjectInfo get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);
use Bio::KBase::fbaModelServices::ScriptHelpers qw(save_workspace_object getToken fbaws get_fba_client runFBACommand universalFBAScriptCode );
use Bio::ModelSEED::MSSeedSupportServer::Client;

$|=1;

#Setting genome
my $genome = $ARGV[0];
my $genomeowner = $ARGV[1];
my $override = $ARGV[3];
my $onestageonly = $ARGV[4];
my $genomews = $ARGV[5];
my $modelws = $ARGV[6];
if (!defined($genome)) {
	die "No genome specified!";
}
if (!defined($override)) {
	$override = 0;
}
if (!defined($onestageonly)) {
	$onestageonly = 0;
}
if (!defined($genomews)) {
	$genomews = "ModelSEEDGenomes";
}
if (!defined($modelws)) {
	$modelws = "ModelSEEDModels";
}

my $output;
#Setting stage
my $stage = $ARGV[2];
if (!defined($stage)) {
	$stage = "loadgenome";
}
#Loading config
my $c = Config::Simple->new();
if (!defined($ENV{MS_MAINT_CONFIG})) {
	$ENV{MS_MAINT_CONFIG} = "/Users/chenry/code/deploy/msconfig.ini";
}
$c->read($ENV{MS_MAINT_CONFIG});
#Getting token for admin about
if (!defined($ENV{MS_SEED_Support_Auth})) {
	$ENV{MS_SEED_Support_Auth} = getToken();
}
my $token = $ENV{MS_SEED_Support_Auth};
#Getting clients
my $wserv = Bio::KBase::workspace::Client->new($c->param("msmaint.ws-url"));
$wserv->{token} = $token;
$wserv->{client}->{token} = $token;
my $fbaserv;
if ($c->param("msmaint.fba-url") eq "impl") {
	$Bio::KBase::fbaModelServices::Server::CallContext = {token => $token};
	require "Bio/KBase/fbaModelServices/Impl.pm";
	$fbaserv = Bio::KBase::fbaModelServices::Impl->new({"workspace-url" => workspaceURL()});
} else {
	$fbaserv = Bio::KBase::fbaModelServices::Client->new($c->param("msmaint.fba-url"));
}
$fbaserv->{token} = $token;
$fbaserv->{client}->{token} = $token;
my $mssserv = Bio::ModelSEED::MSSeedSupportServer::Client->new($c->param("msmaint.ms-url"));
#Getting RAST user ID
my $db = DBI->connect("DBI:mysql:WebAppBackend:bio-app-authdb.mcs.anl.gov:3306", "webappuser");
if (!defined($db)) {
	die("Could not connect to database!");
}
my $columns = {
	_id       => 1,
	login     => 1,
	password  => 1,
	firstname => 1,
	lastname  => 1,
	email     => 1
};
my $users = $db->selectall_arrayref("SELECT * FROM User WHERE User.login = ?", { Slice => $columns }, $genomeowner);
$db->disconnect;
my $usrid = $users->[0]->{_id};
#Loading genome
if ($stage eq "loadgenome") {
	print "Loading genome ".$genome."!\n";
	#Checking for genome in model seed
	my $loadgenome = 1;
	if ($override == 0) {
		eval {
			$output = $wserv->get_object_info([{
				workspace => $genomews,
				name => $genome
			}],1);
		};
		if (defined($output)) {
			$loadgenome = 0;
		}
	}
	if ($loadgenome == 1) {
		eval {
			$output = $wserv->get_object_info([{
				workspace => "pubSEEDGenomes",
				name => $genome
			}],1);
		};
		if (defined($output)) {
			$output = $wserv->copy_object({
				from => {
					workspace => "pubSEEDGenomes",
					name => $genome
				},
				to => {
					workspace => $genomews,
					name => $genome
				}
			});
		} else {
			$db = DBI->connect("DBI:mysql:RastProdJobCache:rast.mcs.anl.gov:3306", "rast");
			if (!defined($db)) {
				die("Could not connect to database!");
			}
			$columns = {
				_id		 => 1,
				id		  => 1,
				genome_id   => 1
			};
			my $jobs = $db->selectall_arrayref("SELECT * FROM Job WHERE Job.genome_id = ?", { Slice => $columns }, $genome);
			$db->disconnect;
			my $jobid = $jobs->[0]->{id};
			if (!defined($jobid)) {
				die("Could not find job ID for ".$genome);
			}
			my $directory = "/vol/rast-prod/jobs/".$jobid."/rp/".$genome;
		    require FIGV;
		    my $figv = new FIGV($directory);
		    if (!defined($figv)) {
		        die("Could not load genome in FIGV for ".$genome);
			}
			open(my $fh, "<", "/vol/rast-prod/jobs/".$jobid."/rp/".$genome."/TAXONOMY");
			my $completetaxonomy = <$fh>;
			my $array = [split(/\t/,$completetaxonomy)];
			$completetaxonomy = $array->[0];
			close($fh);
			$completetaxonomy =~ s/;\s/;/g;
			my $taxArray = [split(/;/,$completetaxonomy)];
			my $speciesname = pop(@{$taxArray});
			my $taxonomy = join("|",@{$taxArray});
		    my $contigset = {
				id => $genome,
				name => $speciesname,
				source_id => $genome,
				source => "RAST:".$jobid,
				type => "Organism",
				contigs => []
		    };
		    my @contigs = $figv->all_contigs($genome);
			my $genomeobj = {
				id => $genome,
				scientific_name => $speciesname,
				domain => $taxArray->[0],
				genetic_code => 11,
				dna_size => $figv->genome_szdna($genome)+0,
				num_contigs => 0,
				contig_lengths => [],
				contig_ids => [],
				source => "RAST:".$jobid,
				source_id => $genome,
				taxonomy => $taxonomy,
				gc_content => 0.5,
				complete => 1,
				publications => [],
				features => [],
				contigset_ref => $genomews."/".$genome.".contigset"
		    };
			my $md5list = [];
			my $gccount = 0;
			for (my $i=0; $i < @contigs; $i++) {
				$genomeobj->{num_contigs}++;
				my $contigLength = $figv->contig_ln($genome,$contigs[$i]);
				push(@{$contigset->{contig_lengths}},$contigLength);
				push(@{$contigset->{contig_ids}},$contigs[$i]);
				my $sequence = $figv->get_dna($genome,$contigs[$i],1,$contigLength);
				my $md5 = "NA";
				if (defined($sequence)) {
					$md5 = Digest::MD5::md5_hex($sequence);
					for ( my $j = 0 ; $j < length($sequence) ; $j++ ) {
						if ( substr( $sequence, $j, 1 ) =~ m/[gcGC]/ ) {
							$gccount++;
						}
					}
				} else {
					$sequence = "";
					$gccount = 0.5*$contigLength;
				}
				push(@{$contigset->{contigs}},{
					id => $contigs[$i],
					"length" => $contigLength+0,
					md5 => $md5,
					sequence => $sequence,
					genetic_code => 11,
					name => $contigs[$i]
				});
				push(@{$md5list},$md5);
			}
			$genomeobj->{gc_content} = $gccount/$genomeobj->{dna_size};
		    my $GenomeData = $figv->all_features_detailed_fast($genome);
			foreach my $Row (@{$GenomeData}) {
				my $feature = {
					id => $Row->[0],
					function => "hypothetical protein",
					type => $Row->[3],
					publications => [],
					subsystems => [],
					protein_families => [],
					aliases => [split(/,/,$Row->[2])],
					annotations => [],
					subsystem_data => [],
					regulon_data => [],
					atomic_regulons => [],
					coexpressed_fids => [],
					co_occurring_fids => [],
					protein_translation => $figv->get_translation($Row->[0]),
				};
				if (defined($feature->{protein_translation})) {
					$feature->{md5} = Digest::MD5::md5_hex($feature->{protein_translation});
					$feature->{protein_translation_length} = length($feature->{protein_translation})+0;
					$feature->{dna_sequence_length} = (3*$feature->{protein_translation_length})+0;
				} else {
					delete $feature->{protein_translation};
				}
				if (defined($Row->[6])) {
					$feature->{function} = $Row->[6];
				}
				if ($Row->[1] =~ m/^(.+)_(\d+)([\+\-_])(\d+)$/) {
					if ($3 eq "-" || $3 eq "+") {
						$feature->{location} = [[$1,$2,$3,$4]];
					} elsif ($2 > $4) {
						$feature->{location} = [[$1,$2,"-",($2-$4)]];
					} else {
						$feature->{location} = [[$1,$2,"+",($4-$2)]];
					}
					$feature->{location}->[0]->[1] = $feature->{location}->[0]->[1]+0;
					$feature->{location}->[0]->[3] = $feature->{location}->[0]->[3]+0;
				}
				push(@{$genomeobj->{features}},$feature);
			}
			$genomeobj->{md5} = Digest::MD5::md5_hex(join(";",sort { $a cmp $b } @{$md5list}));
			$contigset->{md5} = $genomeobj->{md5};
			$wserv->save_objects({
		    	objects => [
		    		{name => $genome.".contigset",type => "KBaseGenomes.ContigSet",data => $contigset,provenance => []},
		    	],
		    	workspace => $genomews
		    });
		    $wserv->save_objects({
		    	objects => [
		    		{name => $genome,type => "KBaseGenomes.Genome",data => $genomeobj,provenance => []}
		    	],
		    	workspace => $genomews
		    });
		}
    }
    if (!defined($onestageonly) || $onestageonly == 0) {
		$stage = "loadmodel";
    }
}
if ($stage eq "loadmodel") {
	print "Loading model ".$genome."!\n";
	$output = $fbaserv->genome_to_fbamodel({
		genome => $genome,
		genome_workspace => $genomews,
		workspace => $modelws,
		model => "Seed".$genome.".".$usrid
	});
	if (!defined($onestageonly) || $onestageonly == 0) {
		$stage = "gapfillmodel";
    }
}
if ($stage eq "gapfillmodel") {
	print "Gapfilling model ".$genome."!\n";
	$output = $fbaserv->gapfill_model({
		model => "Seed".$genome.".".$usrid,
		integrate_solution => 1,
		workspace => $modelws,
		fastgapfill => 1
	});
	if (!defined($onestageonly) || $onestageonly == 0) {
		$stage = "loadtomodelseed";
    }
}
if ($stage eq "loadtomodelseed") {
	print "Loading to modelseed for ".$genome."!\n";
	my $objs = $wserv->get_objects([{
		workspace => $genomews,
		name => $genome
	}]);
	my $genomeobj = $objs->[0]->{data};
	if (!defined($genomeobj->{taxonomy}) && defined($genomeobj->{domain})) {
		$genomeobj->{taxonomy} = $genomeobj->{domain};
	}
	my $input = {
		genome => {
			id => $genome,
			genes => 0,
			features => [],
			owner => $c->param("msmaint.kbuser"),
			source => $genomeobj->{source},
			taxonomy => $genomeobj->{taxonomy},
			name => $genomeobj->{scientific_name},
			size => $genomeobj->{size},
			domain => $genomeobj->{domain},
			gc => $genomeobj->{gc},
			genetic_code => $genomeobj->{genetic_code}
		},
		owner => $genomeowner,
		reactions => [],
		biomass => undef,
		cellwalltype => undef,
		status => 1
	};
	if (defined($genomeobj->{features})) {
		for (my $j=0; $j < @{$genomeobj->{features}}; $j++) {
			my $ftr = $genomeobj->{features}->[$j];
			my $id = $ftr->{id};
			my $roles = [split(/\s*;\s+|\s+[\@\/]\s+/,$ftr->{function})];
			my $aliases = $ftr->{aliases};
			my $type = "peg";
			if ($id =~ m/fig\|\d+\.\d+\.(.+)\./) {
				$type = $1;
			}
			my $dir = "for";
			my $min = $ftr->{location}->[0]->[1];
			my $max = $min+$ftr->{location}->[0]->[3];
			my $loc = $min."_".$max;
			if ($ftr->{location}->[0]->[2] eq "-") {
				$dir = "rev";
				$max = $min;
				$min = $max-$ftr->{location}->[0]->[3];
				$loc = $max."_".$min;
			}
			$input->{genome}->{genes}++;
			push(@{$input->{genome}->{features}},{
				id => $id,
				ess => "",
				aliases => join("|",@{$aliases}),
				type => $type,
				location => $loc,
				"length" => $ftr->{location}->[0]->[3],
				direction => $dir,
				min => $min,
				max => $max,
				roles => join("|",@{$roles}),
				source => "",
				sequence => ""
			});
		}
	}
	my $mdldata = $fbaserv->export_fbamodel({
		model => "Seed".$genome.".".$usrid,
		format => "modelseed",
		workspace => $modelws
	});
	my $lines = [split(/\n/,$mdldata)];
	my $i;
	for ($i=2; $i < @{$lines}; $i++) {
		my $line = $lines->[$i];
		if ($line =~ m/^NAME/) {
			last;	
		} else {
			my $row = [split(/;/,$line)];
			if (defined($row->[4])) {
				push(@{$input->{reactions}},{
					id => $row->[0],
					direction => $row->[1],
					compartment => $row->[2],
					pegs => $row->[3],
					equation => $row->[4]
				});
			}
		}
	}
	if ($lines->[$i+1] =~ m/GramNegative/) {
		$input->{genome}->{class} = "Gram negative";
		$input->{cellwalltype} = "Gram negative";
	} else {
		$input->{genome}->{class} = "Gram positive";
		$input->{cellwalltype} = "Gram positive";
	}
	if ($lines->[$i+2] =~ m/EQUATION\t(.+)/) {
		$input->{biomass} = $1;
	}
	$output = $mssserv->load_model_to_modelseed($input);
	if (!defined($onestageonly) || $onestageonly == 0) {
		$stage = "printsbml";
    }
}
if ($stage eq "printsbml") {
	print "Print SBML for model ".$genome."!\n";
	$output = $fbaserv->export_fbamodel({
		model => "Seed".$genome.".".$usrid,
		format => "sbml",
		workspace => $modelws
	});
	open(my $fh, ">", "/vol/model-dev/MODEL_DEV_DB/Models2/".$genomeowner."/Seed".$genome.".".$usrid."/0/model.sbml");
	print $fh $output."\n";
	close($fh);
}

1;
