# -*- coding: utf-8 -*-
package MOP4Import::Declare;
use 5.010;
use strict;
use warnings qw(FATAL all NONFATAL misc);
our $VERSION = '0.01';
use Carp;
use mro qw/c3/;

use constant DEBUG => $ENV{DEBUG_MOP4IMPORT};

use MOP4Import::Opts;
use MOP4Import::Util;
use MOP4Import::FieldSpec;

our %FIELDS;

sub import {
  my ($myPack, @decls) = @_;

  @decls = $myPack->default_exports unless @decls;

  $myPack->dispatch_declare(Opts->new(scalar caller), @decls);
}

#
# This serves as @EXPORT
#
sub default_exports {
  (-strict);
}

sub dispatch_declare {
  (my $myPack, my Opts $opts, my (@decls)) = @_;

  foreach my $declSpec (@decls) {
    if (not ref $declSpec) {

      $myPack->declare_import($opts, $declSpec);

    } elsif (ref $declSpec eq 'ARRAY') {

      $myPack->dispatch_declare_pragma($opts, @$declSpec);

    } elsif (ref $declSpec eq 'CODE') {

      $declSpec->($myPack, $opts);

    } else {
      croak "Invalid declaration spec: $declSpec";
    }
  }
}

sub declare_import {
  (my $myPack, my Opts $opts, my ($declSpec)) = @_;

  my ($name, $exported);

  if ($declSpec =~ /^-([A-Za-z]\w*)$/) {

    return $myPack->dispatch_declare_pragma($opts, $1);

  } elsif ($declSpec =~ /^\*(\w+)$/) {
    ($name, $exported) = ($1, globref($myPack, $1));
  } elsif ($declSpec =~ /^\$(\w+)$/) {
    ($name, $exported) = ($1, *{globref($myPack, $1)}{SCALAR});
  } elsif ($declSpec =~ /^\%(\w+)$/) {
    ($name, $exported) = ($1, *{globref($myPack, $1)}{HASH});
  } elsif ($declSpec =~ /^\@(\w+)$/) {
    ($name, $exported) = ($1, *{globref($myPack, $1)}{ARRAY});
  } elsif ($declSpec =~ /^\&(\w+)$/) {
    ($name, $exported) = ($1, *{globref($myPack, $1)}{CODE});
  } elsif ($declSpec =~ /^(\w+)$/) {
    ($name, $exported) = ($1, globref($myPack, $1));
  } else {
    croak "Invalid import spec: $declSpec";
  }

  print STDERR " Declaring $name in $opts->{destpkg} as "
    .terse_dump($exported)."\n" if DEBUG;

  *{globref($opts->{destpkg}, $name)} = $exported;
}

sub dispatch_declare_pragma {
  (my $myPack, my Opts $opts, my ($pragma, @args)) = @_;
  if ($pragma =~ /^[A-Za-z]/
      and my $sub = $myPack->can("declare_$pragma")) {
    $sub->($myPack, $opts, @args);
  } else {
    croak "Unknown pragma '$pragma' in $opts->{destpkg}";
  }
}

# You may want to override these pragrams.
sub declare_default_pragma {
  (my $myPack, my Opts $opts) = @_;
  $myPack->declare_strict($opts);
  $myPack->declare_c3($opts);
}

sub declare_strict {
  (my $myPack, my Opts $opts) = @_;
  $_->import for qw(strict warnings); # I prefer fatalized warnings, but...
}

# Not enabled by default.
sub declare_fatal {
  (my $myPack, my Opts $opts) = @_;
  warnings->import(qw(FATAL all NONFATAL misc));
}

sub declare_c3 {
  (my $myPack, my Opts $opts) = @_;
  mro::set_mro($opts->{destpkg}, 'c3');
}

sub declare_base {
  (my $myPack, my Opts $opts, my (@base)) = @_;

  print STDERR "Class $opts->{objpkg} extends ".terse_dump(@base)."\n"
    if DEBUG;

  push @{*{globref($opts->{objpkg}, 'ISA')}}, @base;

  $myPack->declare_fields($opts);
}

sub declare_parent {
  (my $myPack, my Opts $opts, my (@base)) = @_;

  print STDERR "Inheriting ".terse_dump(@base)." from $opts->{objpkg}\n"
    if DEBUG;

  foreach my $fn (@base) {
    (my $cp = $fn) =~ s{::|'}{/}g;
    require "$cp.pm";
  }

  push @{*{globref($opts->{objpkg}, 'ISA')}}, @base;

  $myPack->declare_fields($opts);
}

sub declare_as_base {
  (my $myPack, my Opts $opts, my (@fields)) = @_;

  print STDERR "Class $opts->{objpkg} inherits $myPack\n"
    if DEBUG;

  $myPack->declare_default_pragma($opts); # strict, mro c3...

  $myPack->declare___add_isa($opts->{objpkg}, $myPack);

  $myPack->declare_fields($opts, @fields);

  $myPack->declare_constant($opts, MY => $opts->{objpkg}, or_ignore => 1);
}

sub declare___add_isa {
  my ($myPack, $objpkg, @parents) = @_;
  my $isa = MOP4Import::Util::isa_array($objpkg);

  my $using_c3 = mro::get_mro($objpkg) eq 'c3';

  if (DEBUG) {
    print STDERR " $objpkg (MRO=",mro::get_mro($objpkg),") ISA "
      , terse_dump(mro::get_linear_isa($objpkg)), "\n";
    print STDERR " Adding $_ (MRO=",mro::get_mro($_),") ISA "
      , terse_dump(mro::get_linear_isa($_))
      , "\n" for @parents;
  }

  my @new = grep {
    my $parent = $_;
    $parent ne $objpkg
      and not grep {$parent eq $_} @$isa;
  } @parents;

  if ($using_c3) {
    local $@;
    foreach my $parent (@new) {
      my $cur = mro::get_linear_isa($objpkg);
      my $adding = mro::get_linear_isa($parent);
      eval {
	unshift @$isa, $parent;
      };
      if ($@) {
        croak "Can't add base '$parent' to '$objpkg' (\n"
          .  "  $objpkg ISA ".terse_dump($cur).")\n"
          .  "  Adding $parent ISA ".terse_dump($adding)
          ."\n) because of this error: " . $@;
      }
    }
  } else {
    push @$isa, @new;
  }
}

sub declare_as {
  (my $myPack, my Opts $opts, my ($name)) = @_;

  unless (defined $name and $name ne '') {
    croak "Usage: use ${myPack} [as => NAME]";
  }

  $myPack->declare_constant($opts, $name => $myPack);
}

sub declare_inc {
  (my $myPack, my Opts $opts, my ($pkg)) = @_;
  $pkg //= $opts->{objpkg};
  $pkg =~ s{::}{/}g;
  $INC{$pkg . '.pm'} = 1;
}

sub declare_constant {
  (my $myPack, my Opts $opts, my ($name, $value, %opts)) = @_;

  my $my_sym = globref($opts->{objpkg}, $name);
  if (*{$my_sym}{CODE}) {
    return if $opts{or_ignore};
    croak "constant $opts->{objpkg}::$name is already defined";
  }

  *$my_sym = sub () {$value};
}

sub declare_fields {
  (my $myPack, my Opts $opts, my (@fields)) = @_;

  my $extended = fields_hash($opts->{objpkg});
  my $fields_array = fields_array($opts->{objpkg});

  # Import all fields from super class
  foreach my $super_class (@{*{globref($opts->{objpkg}, 'ISA')}{ARRAY}}) {
    my $super = fields_hash($super_class);
    next unless $super;
    foreach my $name (keys %$super) {
      next if defined $extended->{$name};
      print STDERR "  Field $opts->{objpkg}.$name is inherited "
	. "from $super_class.\n" if DEBUG;
      $extended->{$name} = $super->{$name}; # XXX: clone?
      push @$fields_array, $name;
    }
  }

  foreach my $spec (@fields) {
    my ($name, @rest) = ref $spec ? @$spec : $spec;
    print STDERR "  Field $opts->{objpkg}.$name is declared.\n" if DEBUG;
    my FieldSpec $obj = $extended->{$name} = $myPack->FieldSpec->new(@rest);
    push @$fields_array, $name;
    if ($name =~ /^[a-z]/i) {
      *{globref($opts->{objpkg}, $name)} = sub { $_[0]->{$name} };
    }
    if (defined $obj->{default}) {
      $myPack->declare_constant($opts, "default_$name", $obj->{default});
    }
  }

  $opts->{objpkg}; # XXX:
}

sub declare_alias {
  (my $myPack, my Opts $opts, my ($name, $alias)) = @_;
  print STDERR " Declaring alias $name in $opts->{destpkg} as $alias\n" if DEBUG;
  my $sym = globref($opts->{destpkg}, $name);
  if (*{$sym}{CODE}) {
    croak "Subroutine (alias) $opts->{destpkg}::$name redefined";
  }
  *$sym = sub () {$alias};
}

sub declare_map_methods {
  (my $myPack, my Opts $opts, my (@pairs)) = @_;

  foreach my $pair (@pairs) {
    my ($from, $to) = @$pair;
    my $sub = $opts->{objpkg}->can($to)
      or croak "Can't find method $to in (parent of) $opts->{objpkg}";
    *{globref($opts->{objpkg}, $from)} = $sub;
  }
}

1;
__END__

=head1 NAME

MOP4Import::Declare - map import args to declare_... method calls.

=head1 SYNOPSIS

  #-------------------
  # To implement MOP4Import, just use this like:

  package YourModule;
  use MOP4Import::Declare -as_base, qw/Opts/;

  # and define what you want as "declare_..." method.
  sub declare_foo {
    (my $myPack, my Opts $opts) = @_;
  }

  sub declare_bar {
    (my $myPack, my Opts $opts, my ($x, $y, @z)) = @_;
  }

  #-------------------
  # Then in user's code:

  package MyApp;
  use YourModule -foo, [bar => 1,2,3,4];

  # Above will be mapped to:
  #
  #   YourMoudle->declare_foo($opts, 'MyApp');
  #   YourMoudle->declare_bar($opts, 'MyApp', 1,2,3,4);


=head1 DESCRIPTION

MOP4Import::Declare is...

=head1 AUTHOR

KOBAYASHI, Hiroaki E<lt>hkoba@cpan.orgE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
