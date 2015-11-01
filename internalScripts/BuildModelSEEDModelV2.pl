#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;
use File::Path;
use JSON::XS;
use Config::Simple;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::ModelSEED::ProbModelSEED::ProbModelSEEDClient;
use Bio::KBase::AppService::Client;
use Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportClient;
use Bio::ModelSEED::Client::SAP;

$|=1;

my $genome = $ARGV[0];
my $genomeowner = $ARGV[1];
my $userid = $ARGV[2];
my $config = $ARGV[3];

my $c = Config::Simple->new();
if (!defined($config)) {
	$config = "/Users/chenry/code/deploy/msconfig.ini";
}
$c->read($config);

my $sapsvr = Bio::ModelSEED::Client::SAP->new();
my $genomedata = $sapsvr->genome_data({
	-ids => [$genome],
	-data => ["name"]
});
my $source = "RAST";
if (defined($genomedata->{$genome}->[0])) {
	$source = "PUBSEED";
}
my $input = {
	adminmode => 1,
	output_path => "/modelseed/modelseed/models/",
	output_file => "Seed".$genome.".".$userid,
	genome => $source.":".$genome,
};

my $client = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDClient->new($c->param("msmaint.pms-url"));
my $wsclient = Bio::P3::Workspace::WorkspaceClient->new($c->param("msmaint.pws-url"));
$client->{token} = $c->param("msmaint.token");
$client->{client}->{token} = $c->param("msmaint.token");
$wsclient->{token} = $c->param("msmaint.token");
$wsclient->{client}->{token} = $c->param("msmaint.token");
#my $output = $client->ModelReconstruction($input);

my $mssserv = Bio::ModelSEED::MSSeedSupportServer::MSSeedSupportClient->new($c->param("msmaint.ms-url"));
$mssserv->{token} = $c->param("msmaint.token");
$mssserv->{client}->{token} = $c->param("msmaint.token");

my $res = $wsclient->get({ adminmode => 1,objects => ["/modelseed/modelseed/models/.Seed".$genome.".".$userid."/Seed".$genome.".".$userid.".sbml"] });

File::Path::mkpath($c->param("msmaint.outputpath").$genomeowner."/Seed".$genome.".".$userid."/0/");
open(my $fh, ">", $c->param("msmaint.outputpath").$genomeowner."/Seed".$genome.".".$userid."/0/model.sbml");
print $fh $res->[0]->[1]."\n";
close($fh);

$res = $wsclient->get({ adminmode => 1,objects => ["/modelseed/modelseed/models/.Seed".$genome.".".$userid."/".$genome.".genome"] });
my $genomeobj = decode_json $res->[0]->[1];
if (!defined($genomeobj->{taxonomy}) && defined($genomeobj->{domain})) {
	$genomeobj->{taxonomy} = $genomeobj->{domain};
}

$input = {
	genome => {
		id => $genome,
		genes => 0,
		features => [],
		owner => $genomeowner,
		source => $genomeobj->{source},
		taxonomy => $genomeobj->{taxonomy},
		name => $genomeobj->{scientific_name},
		size => $genomeobj->{dna_size},
		domain => "Bacteria",
		gc => $genomeobj->{gc_content},
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
$res = $wsclient->get({ adminmode => 1,objects => ["/modelseed/modelseed/models/Seed".$genome.".".$userid] });
my $mdldata = decode_json $res->[0]->[1];
if ($mdldata->{template_ref} =~ m/GramNegative/) {
	$input->{genome}->{class} = "Gram negative";
	$input->{cellwalltype} = "Gram negative";
} else {
	$input->{genome}->{class} = "Gram positive";
	$input->{cellwalltype} = "Gram positive";
}
my $rxns = $mdldata->{modelreactions};
for (my $n=0; $n < @{$rxns}; $n++) {
	my $rxn = $rxns->[$n];
	my $dir = "<=>";
	if ($rxn->{direction} eq ">") {
		$dir = "=>";
	} elsif ($rxn->{direction} eq "<") {
		$dir = "<=";
	}
	my $comp = "c";
	if ($rxn->{modelcompartment_ref} =~ m/\/([a-z])\d+$/) {
		$comp = $1;
	}
	my $prots = $rxn->{modelReactionProteins};
	my $gpr = "";
	for (my $j=0; $j < @{$prots}; $j++) {
		my $subunits = $prots->[$j]->{modelReactionProteinSubunits};
		my $subunit = "";
		for (my $k=0; $k < @{$subunits}; $k++) {
			my $pegs = "";
			my $features = $subunits->[$k]->{feature_refs};
			for (my $m=0; $m < @{$features}; $m++) {
				if ($features->[$m] =~ m/\/([^\/]+)$/) {
					if ($m > 0) {
						$pegs .= " or ";
					}
					$pegs .= $1;
				}
			}
			if (@{$features} > 1) {
				$pegs = "(".$pegs.")";
			}
			if (length($subunit) > 0) {
				$subunit .= " and ";
			}
			$subunit .= $pegs;
		}
		if (@{$subunits} > 1) {
			$subunit = "(".$subunit.")";
		}
		if (length($gpr) > 0) {
			$gpr .= " or ";
		}
		$gpr .= $subunit;
	}
	if (@{$prots} > 1) {
		$gpr = "(".$gpr.")";
	}
	my $reactants = "";
	my $products = "";
	for (my $i=0; $i < @{$rxn->{modelReactionReagents}}; $i++) {
		my $coef = $rxn->{modelReactionReagents}->[$i]->{coefficient};
		if ($rxn->{modelReactionReagents}->[$i]->{modelcompound_ref} =~ m/(cpd\d\d\d\d\d)_([a-z])\d+/) {
			my $cpdid = $1;
			my $comp = $2;
			if ($coef < 0) {
				if (length($reactants) > 0) {
					$reactants .= " + ";
				}
				$coef = -1*$coef;
				$reactants .= "(".$coef.") ".$cpdid."[".$comp."]";
			} else {
				if (length($products) > 0) {
					$products .= " + ";
				}
				$products .= "(".$coef.") ".$cpdid."[".$comp."]";
			}
		}
	}
	my $equation = $reactants." ".$dir." ".$products;
	my $id = $rxn->{id};
	if ($rxn->{id} =~ m/(rxn\d+)_/) {
		$id = $1;
	}
	push(@{$input->{reactions}},{
		id => $id,
		direction => $dir,
		compartment => $comp,
		pegs => $gpr,
		equation => $equation
	});
}
my $reactants = "";
my $products = "";
for (my $i=0; $i < @{$mdldata->{biomasses}->[0]->{biomasscompounds}}; $i++) {
	my $coef = $mdldata->{biomasses}->[0]->{biomasscompounds}->[$i]->{coefficient};
	if ($mdldata->{biomasses}->[0]->{biomasscompounds}->[$i]->{modelcompound_ref} =~ m/(cpd\d\d\d\d\d)_([a-z])\d+/) {
		my $cpdid = $1;
		my $comp = $2;
		if ($coef < 0) {
			if (length($reactants) > 0) {
				$reactants .= " + ";
			}
			$coef = -1*$coef;
			$reactants .= "(".$coef.") ".$cpdid."[".$comp."]";
		} else {
			if (length($products) > 0) {
				$products .= " + ";
			}
			$products .= "(".$coef.") ".$cpdid."[".$comp."]";
		}
	}
}
$input->{biomass} = $reactants." => ".$products;

#$JSON = JSON->new->utf8(1);
#$JSON->pretty(1);
#open(my $fhh, ">", $c->param("msmaint.outputpath").$genomeowner."/Seed".$genome.".".$userid."/0/input.json");
#print $fhh $JSON->encode($input)."\n";
#close($fhh);

my $output = $mssserv->load_model_to_modelseed($input);

1;
