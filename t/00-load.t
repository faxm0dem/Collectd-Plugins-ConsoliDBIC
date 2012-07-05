#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Collectd::Plugins::ConsoliDBIC' ) || print "Bail out!\n";
}

diag( "Testing Collectd::Plugins::ConsoliDBIC $Collectd::Plugins::ConsoliDBIC::VERSION, Perl $], $^X" );
