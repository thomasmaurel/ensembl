=pod

=head1 LICENSE

  Copyright (c) 1999-2012 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=head1 NAME

Bio::EnsEMBL::Pipeline::Production::ClassSpeciesFactory

=head1 DESCRIPTION

An extension of the SpeciesFactory code. This uses the ensembl production
database to decide if 
- there has been a change to the species
- there is a variation database associated

Allowed parameters are:

=over 8

=item release - Needed to query production with

=back

The registry should also have a DBAdaptor for the production schema 
registered under the species B<multi> and the group B<production>. 

The code adds an additional flow output:

=over 8

=item 4 - Perform DNA reuse

=back

=cut

package Bio::EnsEMBL::Pipeline::Production::ClassSpeciesFactory;

use strict;
use warnings;

use base qw/Bio::EnsEMBL::Pipeline::SpeciesFactory/;

use Bio::EnsEMBL::Registry;
use File::Spec;



sub run {
  my ($self) = @_;
  my @dbs;
  foreach my $dba (@{$self->param('dbas')}) {
    if(!$self->process_dba($dba)) {
      $self->fine('Skipping %s', $dba->species());
      next;
    }

    my $variation = $self->production_flow($dba, 'variation');
    if ($variation) {
      push(@dbs, [$self->input_id($dba, 'variation'), $variation]);
    }

    my $changed = $self->production_flow($dba, 'changed');
    if($changed) {
      push(@dbs, [$self->input_id($dba, 'changed'), $changed]);
    }

    my $all = $self->production_flow($dba, 'all');
    if($all) {
      push(@dbs, [$self->input_id($dba, 'all'), $all]);
    }


  }
  $self->param('dbs', \@dbs);
  return;
}


sub input_id {
  my ($self, $dba, $type) = @_;
  my $mc = $dba->get_MetaContainer();
  my $input_id = {
    species => $mc->get_production_name(),
  };
  return $input_id;
}

sub production_flow {
  my ($self, $dba, $class) = @_;
  if($self->is_run($dba, $class)) {
    if ($class =~ 'variation') {
      return 4;
    }
    if ($class =~ 'changed') {
      return 3;
    }
    if ($class =~ 'all') {
      return 2;
    }
  }
}


sub is_run {
  my ($self, $dba, $class) = @_;
  my @params;
  my $production_name  = $dba->get_MetaContainer()->get_production_name();
  
  my $sql = <<'SQL';
     SELECT count(*)
     FROM   db_list dl, db d
     WHERE  dl.db_id = d.db_id and db_type = 'core' and is_current = 1 
     AND full_db_name like ?
SQL

  push (@params, "$production_name%");

  if ($class !~ 'all') {
    $sql .= <<'SQL';
       AND    species_id IN (
       SELECT species_id 
       FROM   changelog c, changelog_species cs 
       WHERE  c.changelog_id = cs.changelog_id 
       AND    release_id = ?
       AND    status not in ('cancelled', 'postponed') 
       AND    (gene_set = 'Y' OR assembly = 'Y' OR repeat_masking = 'Y' OR variation_pos_changed = 'Y'))
SQL

    push(@params, $self->param('release'));

    if ($class !~ 'changed') {
      $sql .= <<'SQL';
       AND    species_id IN (
       SELECT distinct species_id 
       FROM   db 
       WHERE  db_release = ? AND db_type = 'variation')
SQL
      push (@params, $self->param('release'));

      if ($class !~ 'variation') {
        $self->throw("Class $self->param('class') is not known");
      }
    }
  }

  $dba->dbc()->disconnect_if_idle();
  my $prod_dba = $self->get_production_DBAdaptor();
  my $result = $prod_dba->dbc()->sql_helper()->execute_single_result(-SQL => $sql, -PARAMS => [@params]);
  $prod_dba->dbc()->disconnect_if_idle();
  return $result;
}


sub write_output {
  my ($self) = @_;
  $self->do_flow('dbs');
  return;
}


sub get_production_DBAdaptor {
  my ($self) = @_;
  return Bio::EnsEMBL::Registry->get_DBAdaptor('multi', 'production');
}

1;
