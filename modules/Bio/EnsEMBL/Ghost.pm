
#
# BioPerl module for Ghost Object
#
# Cared for by Elia Stupka <elia@ebi.ac.uk>
#
# Copyright Elia Stupka
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Ghost - Object for Ghosts of deleted objects

=head1 SYNOPSIS

Ghost objects. 

=head1 DESCRIPTION

These are used by donor databases to pass on information about objects that have been 
permanently deleted (and archived) to recipient databases. They allow recipient databases 
to know which objects have been deleted in the donor database. These objects are 
stored in a separate table within each major database (not its archive DB), and store 
the id, type, and time of deletion for deleted objects. This is a separate concept from the 
archive db, which will hold store information about the content of the deleted objects.

=head1 CONTACT

Elia Stupka
European Bioinformatics Institute

e-mail: elia@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods 
are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Ghost;
use vars qw(@ISA);
use strict;

# Object preamble - inheriets from Bio::SeqFeature::Generic

use Bio::Root::Object;
use Bio::EnsEMBL::Transcript;


@ISA = qw(Bio::Root::Object);
# new() is inherited from Bio::Root::Object

# _initialize is where the heavy stuff will happen when new is called

sub _initialize {
  my($self,@args) = @_;

  my $make = $self->SUPER::_initialize;

# set stuff in self from @args
  return $make; # success - we hope!
}

=head2 id

 Title   : id
 Usage   : $obj->id($newval)
 Function: stores the id of the deleted object
 Returns : value of id
 Args    : newvalue (optional)


=cut

sub id{
   my $obj = shift;
   if( @_ ) {
      my $value = shift;
      $obj->{'id'} = $value;
    }
    return $obj->{'id'};

}

=head2 seq_type

 Title   : seq_type
 Usage   : $obj->seq_type($newval)
 Function: stores the sequence type of the deleted object
 Returns : value of seq_type
 Args    : newvalue (optional)


=cut

sub seq_type{
   my $obj = shift;
   if( @_ ) {
      my $value = shift;
      $obj->{'seq_type'} = $value;
    }
    return $obj->{'seq_type'};

}
