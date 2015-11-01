use strict;
use warnings;
use Module::Build;

my $name = 'MOP4Import';

my $builder = Module::Build->new
  (module_name       => $name
   , dist_author       => q{KOBAYASHI, Hiroaki <hkoba@cpan.org>},
   , dist_version      => '0.01'
   , dist_abstract     => 'Thin Meta-Object Protocol to build extensible exporters'
   , license           => 'perl'
 );

$builder->create_build_script();
