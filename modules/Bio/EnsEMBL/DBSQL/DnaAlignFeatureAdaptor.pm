#
# BioPerl module for Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor
#
# Cared for by Ewan Birney <birney@ebi.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor - Adaptor for DnaAlignFeatures

=head1 SYNOPSIS

    $dafa = $dbadaptor->get_DnaAlignFeatureAdaptor();

    @features = @{$dafa->fetch_by_RawContig($contig)};

    $dafa->store(@features);

=head1 DESCRIPTION


This is an adaptor for DNA features on DNA sequence. Like other
feature getting adaptors it has a number of fetch_ functions and a
store function. This adaptor inherits most of its functionality from
its BaseAlignFeatureAdaptor superclass.


=head1 AUTHOR - Ewan Birney

Email birney@ebi.ac.uk

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor;
use vars qw(@ISA);
use strict;

# Object preamble - inherits from Bio::EnsEMBL::Root

use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DBSQL::BaseAlignFeatureAdaptor;

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAlignFeatureAdaptor);


=head2 _tables

  Args       : none
  Example    : @tabs = $self->_tables
  Description: PROTECTED implementation of the abstract method inherited from
               BaseFeatureAdaptor.  Returns list of [tablename, alias] pairs
  Returntype : list of listrefs of strings
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor::generic_fetch

=cut

sub _tables {
  my $self = shift;

  return ['dna_align_feature', 'daf'];
}


=head2 _columns

  Args       : none
  Example    : @columns = $self->_columns
  Description: PROTECTED implementation of abstract superclass method.  
               Returns a list of columns that are needed for object creation.
  Returntype : list of strings
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor::generic_fetch

=cut

sub _columns {
  my $self = shift;

  #warning, implementation of _objs_from_sth method depends on order of list
  return qw(daf.dna_align_feature_id 
	    daf.contig_id 
	    daf.analysis_id 
	    daf.contig_start 
	    daf.contig_end 
	    daf.contig_strand 
	    daf.hit_start 
	    daf.hit_end 
	    daf.hit_name 
	    daf.hit_strand
	    daf.cigar_line 
	    daf.evalue 
	    daf.perc_ident score);
}


=head2 store

  Arg [1]    : int $contig_id 
               the id of the contig to be stored in the database
  Arg [2]    : list of Bio::EnsEMBL::DnaAlignFeatures @sf
               the features to store in the database
  Example    : $dna_align_feature_adaptor->store($contig_id, @features);
  Description: Stores a list of DnaAlignFeatures in the database
  Returntype : none
  Exceptions : thrown if $contig_id is not an int, or if any of the
               features in the database are not storable 
  Caller     : ?

=cut

sub store {
  my ($self, @sf) = @_;

  my @tabs = $self->_tables;
  my ($tablename) = @{$tabs[0]};
  
  if( scalar(@sf) == 0 ) {
    $self->throw("Must call store with sequence features");
  }
  
  my $sth = $self->prepare("
     INSERT INTO $tablename (contig_id, contig_start, contig_end,
                             contig_strand, hit_start, hit_end,
                             hit_strand, hit_name, cigar_line,
                             analysis_id, score, evalue, perc_ident) 
     VALUES (?,?,?,?,?,?,?,?,?,?,?, ?, ?)");

  foreach my $sf ( @sf ) {
    if( !ref $sf || !$sf->isa("Bio::EnsEMBL::DnaDnaAlignFeature") ) {
      $self->throw("feature must be a Bio::EnsEMBL::DnaDnaAlignFeature," 
		    . " not a [$sf]");
    }
    
    my $contig = $sf->entire_seq();
    unless(defined $contig && $contig->isa("Bio::EnsEMBL::RawContig")) {
      $self->throw("A contig must be attached to the features to be " .
		   "stored via the attach seq method\n");
    }

    if( !defined $sf->analysis ) {
      $self->throw("Cannot store sequence features without analysis");
    }

     # will only store if object is not already stored in this database
    $self->db()->get_AnalysisAdaptor()->store( $sf->analysis() );

    $sth->execute( $contig->dbID(), $sf->start, $sf->end, $sf->strand,
		   $sf->hstart, $sf->hend, $sf->hstrand, $sf->hseqname,
		   $sf->cigar_string, $sf->analysis->dbID, $sf->score, 
		   $sf->p_value, $sf->percent_id);
    $sf->dbID($sth->{'mysql_insertid'});
  }
}


=head2 _objs_from_sth

  Arg [1]    : DBI statement handle $sth
               an exectuted DBI statement handle generated by selecting 
               the columns specified by _columns() from the table specified 
               by _table()
  Example    : @dna_dna_align_feats = $self->_obj_from_hashref
  Description: PROTECTED implementation of superclass abstract method. 
               Creates DnaDnaAlignFeature objects from a DBI hashref
  Returntype : listref of Bio::EnsEMBL::DnaDnaAlignFeatures
  Exceptions : none
  Caller     : Bio::EnsEMBL::BaseFeatureAdaptor::generic_fetch

=cut

sub _objs_from_sth {
  my ($self, $sth, $mapper, $slice) = @_;

  my ($dna_align_feature_id, $contig_id, $analysis_id, $contig_start, 
      $contig_end, $contig_strand, $hit_start, $hit_end, $hit_name, 
      $hit_strand, $cigar_line, $evalue, $perc_ident, $score);
  
  my $rca = $self->db()->get_RawContigAdaptor();
  my $aa = $self->db()->get_AnalysisAdaptor();
  
  my ($analysis, $contig);
  my @features;

  my %a_hash;

  my ($row, $row_cache);

  $row_cache = $sth->fetchall_arrayref();

  if($slice) {
    my ($chr, $start, $end, $strand);
    my $slice_start  = $slice->chr_start();
    my $slice_end    = $slice->chr_end();
    my $slice_strand = $slice->strand();
    my $slice_name   = $slice->name();

    my ($feat_start, $feat_end, $feat_strand);

    while($row = shift @$row_cache) {
      ($dna_align_feature_id, $contig_id, $analysis_id, $contig_start, 
       $contig_end, $contig_strand, $hit_start, $hit_end, $hit_name, 
       $hit_strand, $cigar_line, $evalue, $perc_ident, $score) = @$row;

      #convert contig coordinates to assembly coordinates
      ($chr, $start, $end, $strand) = 
	$mapper->fast_to_assembly($contig_id, $contig_start, 
				  $contig_end, $contig_strand);
      
      #if mapped to gap, skip
      next unless(defined $start);

      #if mapped outside slice region, skip
      next if ($start > $slice_end) || ($end < $slice_start); 

      #convert assembly coordinates to slice coordinates
      if($slice_strand == -1) {
	$feat_start  = $slice_end - $end + 1;
	$feat_end    = $slice_end - $start + 1;
	$feat_strand = $strand * -1;
      } else {
	$feat_start  = $start - $slice_start + 1;
	$feat_end    = $end   - $slice_start + 1;
	$feat_strand = $strand;
      }

      $analysis = $a_hash{$analysis_id} ||= $aa->fetch_by_dbID($analysis_id);

      push @features, Bio::EnsEMBL::DnaDnaAlignFeature->new_fast(
                    {'_gsf_tag_hash'  =>  {},
		     '_gsf_sub_array' =>  [],
		     '_parse_h'       =>  {},
		     '_analysis'      =>  $analysis,
		     '_gsf_start'     =>  $feat_start,
		     '_gsf_end'       =>  $feat_end,
		     '_gsf_strand'    =>  $feat_strand,
		     '_gsf_score'     =>  $score,
		     '_seqname'       =>  $slice_name,
		     '_percent_id'    =>  $perc_ident,
		     '_p_value'       =>  $evalue,
                     '_hstart'        =>  $hit_start,
                     '_hend'          =>  $hit_end,
                     '_hstrand'       =>  $hit_strand,
                     '_hseqname'      =>  $hit_name,
		     '_gsf_seq'       =>  $slice,
		     '_cigar_string'  =>  $cigar_line,
		     '_id'            =>  $hit_name,
                     '_database_id'   =>  $dna_align_feature_id});
    }
  } else {
    my %c_hash;
    while($row = shift @$row_cache) {
      ($dna_align_feature_id, $contig_id, $analysis_id, $contig_start, 
       $contig_end, $contig_strand, $hit_start, $hit_end, $hit_name, 
       $hit_strand, $cigar_line, $evalue, $perc_ident, $score) = @$row;
      
      $analysis = $a_hash{$analysis_id} ||= $aa->fetch_by_dbID($analysis_id);
      $contig   = $c_hash{$contig_id}   ||= $rca->fetch_by_dbID($contig_id);
	
      #use a very fast (hack) constructor since we may be creating over 10000
      #features at a time and normal object construction is too slow.
      push @features, Bio::EnsEMBL::DnaDnaAlignFeature->new_fast(
                    {'_gsf_tag_hash'  =>  {},
		     '_gsf_sub_array' =>  [],
		     '_parse_h'       =>  {},
		     '_analysis'      =>  $analysis,
		     '_gsf_start'     =>  $contig_start,
		     '_gsf_end'       =>  $contig_end,
		     '_gsf_strand'    =>  $contig_strand,
		     '_gsf_score'     =>  $score,
		     '_seqname'       =>  $contig->name,
		     '_percent_id'    =>  $perc_ident,
		     '_p_value'       =>  $evalue,
                     '_hstart'        =>  $hit_start,
                     '_hend'          =>  $hit_end,
                     '_hstrand'       =>  $hit_strand,
                     '_hseqname'      =>  $hit_name,
		     '_gsf_seq'       =>  $contig,
		     '_cigar_string'  =>  $cigar_line,
		     '_id'            =>  $hit_name,
                     '_database_id'   =>  $dna_align_feature_id}); 

    }
    
  }
  
  return \@features;
}

    
1;


