use strict;
use warnings;
use DBI;
use File::Path;
use Data::Dumper;
use Bio::KBase::CDMI::CDMIClient;

my $directory = $ARGV[0];
my $genomes = [];
open (my $fh, "<", $directory."/GenomeList.txt") || die "Couldn't open ".$directory."/GenomeList.txt: $!";
while (my $line = <$fh>) {
	chomp($line);
	push(@{$genomes},$line);
}
close($fh);

my $cdm = Bio::KBase::CDMI::CDMIClient->new_for_script();
for (my $i=0; $i < @{$genomes}; $i++) {
#for (my $i=0; $i < 1; $i++) {
	open (my $fhh, ">", $directory."/".$genomes->[$i]) || die "Couldn't open ".$directory."/".$genomes->[$i].": $!";
	print $fhh "Gene\tLength\tCDD\tStart\tStop\tIdentity\tFunction\tAlignlength\tCDD name\tProtein\tCDDStart\tCDDStop\tE value\tSEEDID\n";
	my $genomeFtrs = $cdm->genomes_to_fids([$genomes->[$i]],[]);
	my $output = $cdm->get_relationship_Produces(
		$genomeFtrs->{$genomes->[$i]},
		["function","source_id","sequence_length"],
		[],
		["id"]
	);
	my $geneList = [];
	my $geneHash = {};
	my $proteinHash = {};
	for (my $j=0; $j < @{$output};$j++) {
		$geneHash->{$output->[$j]->[1]->{from_link}} = {
			"id" => $output->[$j]->[1]->{from_link},
			"length" => $output->[$j]->[0]->{"sequence_length"},
			"function" => $output->[$j]->[0]->{function},
			"seedid" => $output->[$j]->[0]->{"source_id"},
			protein => $output->[$j]->[2]->{"id"},
		};
		push(@{$geneList},$output->[$j]->[1]->{from_link});
		$proteinHash->{$output->[$j]->[2]->{id}}->{$output->[$j]->[1]->{from_link}} = 1;
	}	
	my $proteinList = [keys(%{$proteinHash})];
	my $cdds = $cdm->get_relationship_HasConservedDomainModel(
		$proteinList,
		[],
		["percent_identity","alignment_length","protein_start","protein_end","domain_start","domain_end","e_value"],
		["id","short_name"]
	);
	for (my $j=0; $j < @{$cdds};$j++) {
		my $cdd = $cdds->[$j];
		my $protein = $cdd->[1]->{from_link};
		foreach my $gene (keys(%{$proteinHash->{$protein}})) {
			$geneHash->{$gene}->{cdds}->{$cdd->[2]->{id}} = {
				start => $cdd->[1]->{protein_start},
				stop => $cdd->[1]->{protein_end},
				identity => $cdd->[1]->{percent_identity},
				alignlength => $cdd->[1]->{alignment_length},
				name => $cdd->[2]->{short_name},
				cddstart => $cdd->[1]->{domain_start},
				cddstop => $cdd->[1]->{domain_end},
				evalue => $cdd->[1]->{e_value}
			};
		}
	}
	for (my $j=0; $j < @{$geneList}; $j++) {
		my $gene = $geneList->[$j];
		foreach my $cdd (keys(%{$geneHash->{$gene}->{cdds}})) {
			my $cddobj = $geneHash->{$gene}->{cdds}->{$cdd};
			print $fhh $geneHash->{$gene}->{id}."\t".$geneHash->{$gene}->{"length"}."\t".$cdd."\t".$cddobj->{start}."\t".$cddobj->{stop}."\t".$cddobj->{identity}
				."\t".$geneHash->{$gene}->{function}."\t".$cddobj->{alignlength}."\t".$cddobj->{name}."\t".$geneHash->{$gene}->{protein}
				."\t".$cddobj->{cddstart}."\t".$cddobj->{cddstop}."\t".$cddobj->{evalue}."\t".$geneHash->{$gene}->{seedid}."\n";
		}
	}
	close($fhh);
}