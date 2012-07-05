use inc::Module::Install;

name     'Collectd-Plugins-ConsoliDBIC';
all_from 'lib/Collectd/Plugins/ConsoliDBIC.pm';
author   q{Fabien Wernli <wernli_workingat_in2p3.fr>};
license  'perl';

build_requires 'Test::More';

requires 'DBIx::Class';
requires 'Collectd';
requires 'Collectd::Unixsock';

install_share qw(share);

auto_install;

WriteAll;

