#!/usr/local/bin/perl

use strict;
use Bio::EnsEMBL::DBSQL::Obj;
use Bio::SeqIO;

use Getopt::Long;

my $tdbtype = 'rdb';
my $thost   = 'croc';
my $tport   = '410000';
my $tdbname = 'ensdev';
my $format  = 'pep';
my $usefile = 0;
my $getall  = 0;

&GetOptions( 
	     'dbtype:s' => \$tdbtype,
	     'host:s'   => \$thost,
	     'port:n'   => \$tport,
	     'usefile'  => \$usefile,
	     'dbname:s' => \$tdbname,
	     'format:s'   => \$format,
	     'getall'   => \$getall,
	     );
my $db;

if( $tdbtype =~ 'ace' ) {
    $db = Bio::EnsEMBL::AceDB::Obj->new( -host => $thost, -port => $tport);
} elsif ( $tdbtype =~ 'rdb' ) {
    $db = Bio::EnsEMBL::DBSQL::Obj->new( -user => 'root', -db => $tdbname , -host => $thost );
} else {
    die("$tdbtype is not a good type (should be ace, rdb)");
}

my @gene_id;

if( $usefile ) {
    while( <> ) {
	my ($g) = split;
	push(@gene_id,$g);
    }
} elsif ( $getall == 1 ) {
    @gene_id = $db->get_all_Gene_id();
} else {
    @gene_id = @ARGV;
}

my $seqio;

if( $format eq 'pep' ) {
    $seqio = Bio::SeqIO->new('-format' => 'Fasta' , -fh => \*STDOUT ) ;
}

foreach my $gene_id ( @gene_id ) {

    eval {

	my $gene = $db->get_Gene($gene_id);

	if( $format eq 'pep' ) {
	    foreach my $trans ( $gene->each_Transcript ) {
		my $tseq = $trans->translate();
		$seqio->write_seq($tseq);
	    }
	} elsif ( $format eq 'dump' ) {
	    foreach my $trans ( $gene->each_Transcript ) {
		print "Transcript ",$trans->id,"\n";
		foreach my $exon ( $trans->each_Exon ) {
		    print "  Exon ",$exon->id," ",$exon->contig_id,":",$exon->start,"-",$exon->end,".",$exon->strand,"\n";
		    my $seq = $exon->seq();
		    my $str = $seq->str();
		    print "    Start phase ",$exon->phase,"[",substr($str,0,10),"] End phase ",$exon->end_phase," [",substr($str,-10),"]\n";
		}
	    }

	} else {
	    die "No valid format!";
	}
    };

    if( $@ ) {
	print STDERR "Unable to process $gene_id due to \n$@\n";
    }
}
