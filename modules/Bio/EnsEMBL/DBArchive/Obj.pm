
#
# BioPerl module for DBArchive::Obj
#
# Cared for by Elia Stupka <elia@ebi.ac.uk>
#
# Copyright Elia Stupka
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::DBArchive::Obj - Object representing the EnsEMBL Archive DB

=head1 SYNOPSIS

    $db = new Bio::EnsEMBL::DBArchive::Obj( -user => 'root', -db => 'pog' , -host => 'caldy' , -driver => 'mysql' );

    $clone = $db->write_seq('3452');

    $contig = $db->get_seq('3452');

    $gene  = $db->get_seq_by_clone('X45667');

    

=head1 DESCRIPTION

This object represents an archive database that is implemented somehow (you shouldn\'t
care much as long as you can get the object). The archive database holds a slice of data for older
versions of proteins, genes, and exons. It comprises three methods for writing and retrieving sequences
from the database. The purpose of this object is to allow versioning in EnsEMBL, holding only the most recent
of an entry in the main DBSQL database, and storing here only the relevant information of older versions.


=head1 CONTACT

Elia Stupka - EBI (elia@ebi.ac.uk)

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::DBArchive::Obj;
use vars qw(@ISA);
use strict;

# Object preamble - inheriets from Bio::Root::Object

use Bio::Root::Object;
use DBI;
use Bio::Seq;

@ISA = qw(Bio::Root::Object);
# new() is inherited from Bio::Root::Object

# _initialize is where the heavy stuff will happen when new is called

sub _initialize {
  my($self,@args) = @_;

  my $make = $self->SUPER::_initialize;

  print "Got",join(',',@args),"\n";
  my ($db,$host,$driver,$user,$password,$debug) = 
      $self->_rearrange([qw(DBNAME
			    HOST
			    DRIVER
			    USER
			    PASS
			    DEBUG
			    )],@args);
  print "Got $db as db and $user as user\n";

  $db || $self->throw("Database object must have a database name");
  $user || $self->throw("Database object must have a user");

  if( $debug ) {
      $self->_debug($debug);
  } else {
      $self->_debug(0);
  }
  
  if( ! $driver ) {
      $driver = 'mysql';
  }
  if( ! $host ) {
      $host = 'localhost';
  }
  my $dsn = "DBI:$driver:database=$db;host=$host";

  if( $debug && $debug > 10 ) {
      $self->_db_handle("dummy dbh handle in debug mode $debug");
  } else {
      
      my $dbh = DBI->connect("$dsn","$user","$password",{RaiseError => 1});
      $dbh || $self->throw("Could not connect to database $db user $user using [$dsn] as a locator");
      
      if( $self->_debug > 3 ) {
	  $self->warn("Using connection $dbh");
      }
     
      $self->_db_handle($dbh);
  }

# set stuff in self from @args
  return $make; # success - we hope!
}


=head2 get_seq

 Title   : get_seq
 Usage   : $db->get_seq (id, version)
 Function: Gets a sequence object out of the Archive database
 Example : $db->get_seq (ENSP0000012,1.2)
 Returns : $seq object
 Args    : id, version


=cut

sub get_seq{
    my ($self,$seqid,$seqversion) = @_;
    
    $seqid || $self->throw("Attempting to get a sequence with no id");
    $seqversion || $self->throw("Attempting to get a sequence without a version number");
    
    #For now $seqtype is not passed to this method, because each type uses a different
    #pre-tag in the id, this might change later...
    #$seqtype || $self->throw("Attempting to get a sequence without a sequence type");
        
    # get the sequence object
    my $sth = $self->prepare("select id,version,sequence from sequence where (id = '$seqid' && version = '$seqversion')");
    my $res = $sth->execute();
    my @out = $self->_create_seq_obj($sth);
    return @out[0];
}

=head2 get_seq_by_id

 Title   : get_seq_by_id
 Usage   : $db->get_seq (id)
 Function: Gets a sequence object for each version for a given id out of the Archive database
 Example : $db->get_seq_by_id (ENST00000007087)
 Returns : array of $seq objects
 Args    : id


=cut

sub get_seq_by_id{
    my ($self,$seqid) = @_;
    
    my @out;
    $seqid || $self->throw("Attempting to get a sequence with no id");
    
    # get the sequence object
    my $sth = $self->prepare("select id,version,sequence from sequence where id = '$seqid'");
    my $res = $sth->execute();
    my @out = $self->_create_seq_obj($sth);
    return @out;
}

=head2 get_seq_by_clone_version

 Title   : get_seq_by_clone_version
 Usage   : $db->get_seq (clone_id, clone_version, seq_type)
 Function: Gets all the sequence objects for a given clone_id, clone_version and sequence 
           type out of the Archive database
 Example : $db->get_seq_by_clone ('AL021546','1','exon')
 Returns : array of $seq objects
 Args    : clone_id


=cut

sub get_seq_by_clone_version{
    my ($self,$clone_id, $clone_version, $seq_type) = @_;
    my $where_clause;
    my @out;

    $clone_id || $self->throw("Attempting to get a sequence with no clone id");
    $clone_version || $self->throw("Attempting to get a sequence with no clone version");
    $seq_type || $self->throw("Attempting to get a sequence with no sequence type");

    if ($clone_version eq 'all') {
	$where_clause = "where (clone_id = '$clone_id' && seq_type='$seq_type')";
    }
    else {
	$where_clause = "where (clone_id = '$clone_id' && clone_version = '$clone_version' && seq_type='$seq_type')";
    }

    # get the sequence objects
    my $sth = $self->prepare("select id,version,sequence from sequence $where_clause");
    my $res = $sth->execute();
    my @out = $self->_create_seq_obj($sth);
    return @out;
}

=head2 get_seq_by_gene_version

 Title   : get_seq_by_gene_version
 Usage   : $db->get_seq (gene_id, version)
 Function: If version is specified, gets all the sequence objects for a given gene_id 
           and gene_version out of the Archive database. If version is equal to 'all',
           then gets all the sequence objects for a given gene_id
 Example : $db->get_seq_by_gene ('AL021546','1'), or $db->get_seq_by_gene ('AL021546','all')
 Returns : array of $seq objects
 Args    : gene_id, version


=cut

sub get_seq_by_gene_version{
    my ($self,$gene_id, $gene_version, $seq_type) = @_;
    my $where_clause;
    my @out;
    
    $gene_id || $self->throw("Attempting to get a sequence with no gene id");
    $gene_version || $self->throw("Attempting to get a sequence with no gene version");
    $seq_type || $self->throw("Attempting to get a sequence with no sequence type"); 
    
    if ($gene_version eq 'all') {
	$where_clause = "where (gene_id = '$gene_id' && seq_type = '$seq_type')";
    }
    
    else {
	$where_clause = "where (gene_id = '$gene_id' && gene_version = '$gene_version' && seq_type = '$seq_type')";
    }

    # get the sequence object
    my $sth = $self->prepare("select id,version,sequence from sequence $where_clause");
    my $res = $sth->execute();
    my @out = $self->_create_seq_obj($sth);
    return @out;
}

=head2 write_seq

 Title   : write_seq
 Usage   : $db->write_seq (seq,gene_id,gene_version,clone_id,clone_version)
 Function: Writes an entry in the archive database
 Example : $db->get_seq_by_id (ENSP0000012)
 Returns : array of $seq objects
 Args    : seq object, version, type, gene_id, gene_version, clone_id, clone_version
           Note that the id of the seq object contains the id of the
           db entry.


=cut

sub write_seq{
   my ($self,$seq, $version, $type, $gene_id,$gene_version) = @_;
   
   $seq || $self->throw("Attempting to write a sequence without a sequence object!");
   $seq->id || $self->throw("Attempting to write a sequence without a sequence id!");
   $type || $self->throw("Attempting to write a sequence without a sequence type!");
   $version || $self->throw("Attempting to write a sequence without a sequence version number!");
   $gene_id || $self->throw("Attempting to write a sequence without a gene id!");
   $gene_version || $self->throw("Attempting to write a sequence without a gene version number!");
   #$clone_id || $self->throw("Attempting to write a sequence without a clone id!");
   #$clone_version || $self->throw("Attempting to write a sequence without a clone version number!");

   my $sth = $self->prepare("insert into sequence (id,version,seq_type,gene_id,gene_version,sequence) values ('".$seq->id()."','$version','$type','$gene_id','$gene_version','".$seq->seq."')");
   $sth->execute();
}
=head2 delete_seq

 Title   : delete_seq
 Usage   : $db->delete_seq (id, version)
 Function: Deletes a sequence entry from the Archive database
 Example : $db->delete_seq (ENSP0000012,1.2)
 Returns : 
 Args    : id, version


=cut

sub delete_seq{
    my ($self,$seqid,$seqversion) = @_;
    
    $seqid || $self->throw("Attempting to delete a sequence with no id");
    $seqversion || $self->throw("Attempting to delete a sequence without a version number");

    if ($self->_debug < 10) { 
	$self->throw ("Attempting to delete a sequence not in debug 10 mode!");
    }

    # delete the sequence entry
    my $sth = $self->prepare("delete from sequence where (id = '$seqid' && version = '$seqversion')");
    my $res = $sth->execute();
}

=head2 prepare

 Title   : prepare
 Usage   : $sth = $dbobj->prepare("select seq_start,seq_end from feature where analysis = \" \" ");
 Function: prepares a SQL statement on the DBI handle

           If the debug level is greater than 10, provides information into the
           DummyStatement object
 Example :
 Returns : A DBI statement handle object
 Args    : a SQL string


=cut

sub prepare{
   my ($self,$string) = @_;

   if( ! $string ) {
       $self->throw("Attempting to prepare an empty SQL query!");
   }

   if( $self->_debug > 10 ) {
       print STDERR "Prepared statement $string\n";
       my $st = Bio::EnsEMBL::DBSQL::DummyStatement->new();
       $st->_fileh(\*STDERR);
       $st->_statement($string);
       return $st;
   }

   # should we try to verify the string?

   return $self->_db_handle->prepare($string);
}

=head2 _debug

 Title   : _debug
 Usage   : $obj->_debug($newval)
 Function: 
 Example : 
 Returns : value of _debug
 Args    : newvalue (optional)


=cut

sub _debug{
    my ($self,$value) = @_;
    if( defined $value) {
	$self->{'_debug'} = $value;
    }
    return $self->{'_debug'};
    
}


=head2 _db_handle

 Title   : _db_handle
 Usage   : $obj->_db_handle($newval)
 Function: 
 Example : 
 Returns : value of _db_handle
 Args    : newvalue (optional)


=cut

sub _db_handle{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'_db_handle'} = $value;
    }
    return $self->{'_db_handle'};

}

=head2 _create_seq_obj

 Title   : _create_seq_obj
 Usage   : $obj->_create_seq_obj ($sth)
 Function: 
 Example : 
 Returns : seq object
 Args    : $sth


=cut

sub _create_seq_obj{
    my ($self,$sth) = @_;

    my $seq = Bio::Seq->new;
    my @out;
    
    while( my $rowhash = $sth->fetchrow_hashref) {
	my $type;
	my $id = $rowhash->{'id'};
	$id .= ".";
	$id .= $rowhash->{'version'};
	if ($rowhash->{'seq_type'} eq 'protein') {
	    $type = 'amino';
	}
	else {
	    $type = 'dna';
	}
	$seq = Bio::Seq->new(
			     -seq=>$rowhash->{'sequence'},
			     -id=>$id,
			     -desc=>'Sequence from the EnsEMBL Archive database',
			     -type=>$type,
			     );
	push @out, $seq;
    }
    
    #Sort array of sequence objects by id
    @out = sort { my $aa = $a->id; $aa =~ s/^[^.]*.//g; my $bb = $b->id; $bb =~ s/^[^.]*.//g; return $aa <=> $bb } @out;
    return @out;
}

=head2 DESTROY

 Title   : DESTROY
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub DESTROY{
   my ($obj) = @_;

   if( $obj->{'_db_handle'} ) {
       $obj->{'_db_handle'}->disconnect;
       $obj->{'_db_handle'} = undef;
   }
}


