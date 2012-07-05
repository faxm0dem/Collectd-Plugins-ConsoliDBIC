package Collectd::Plugins::ConsoliDBIC;

use strict;
use warnings;

use Collectd qw( :all );
use Collectd::Unixsock;
use DBIx::Class;
use Data::Dumper;

my $last_ts = time();
my $plugin_name = "consolidbic";
my %opt = (
	Interval => $interval_g,
	Hostname => $hostname_g,
	UnixSock => "/var/run/collectd/sock",
	PluginName => $plugin_name,
	CFunc => [ "avg" ],
	Match => {},
);
my $collectd;
my $schema;

our $VERSION = '0.1001';

=head1 NAME

Collectd::Plugins::ConsoliDBIC - Collectd probe to consolidate data from
collectd probes grouping by keys from a database (using a L<DBIx::Class> handle).

=head1 SYNOPSIS

To be used with Collectd perl. See collectd.conf manpage for config syntax.
The following documentation applies to collectd's configuration.

=cut

plugin_register(TYPE_CONFIG, $plugin_name, 'my_config');
plugin_register(TYPE_READ, $plugin_name, 'my_get');
plugin_register(TYPE_INIT, $plugin_name, 'my_init');

sub _init_sock {
	$collectd = Collectd::Unixsock -> new ($opt{UnixSock}) or return;
}

sub my_init {
	_init_sock();
	eval "require $opt{Schema}";
	$schema   = $opt{Schema} -> connect(@opt{qw/DSN Username Password/});
	1;
}

sub my_log {
	plugin_log shift @_, join " ", "$plugin_name", @_;
}

=head1 OPTIONS

=head2 Interval

Custom interval at which the plugin will fire up.
Defaults to collectd's global interval $interval_g.

=head2 PluginName

If left empty, "consolidbic" will be used. The Plugin Instance will use the
column from the database as set by L<InstanceFrom>.

=head2 Schema (MANDATORY)

Schema name to be used for DB connection.
Must be a DBIx::Class::Schema subclass.

=head2 DSN/Username/Password

These are the connection parameters to be passed to L<DBIx::Class::Schema/connect>.
DSN is mandatory.

=head2 ResultSet (MANDATORY)

This is the name of the L<DBIx::Class::ResultSet> to be used for querying the
database.

=head2 HostsFrom/InstanceFrom (MANDATORY)

Accessor path for hostname and instance. HostsFrom will be used to match
the values' host identifier in collectd's cache against the schema.
InstanceFrom will be used to build the new consolidated value. See EXAMPLE
below if scratching head.

=head2 <Search><Condition>...</Condition><Attributes>...</Attributes></Search>

This nested config block contains the information passed to L<DBIx::Class::ResultSet/search>.
Please note that due to collectd's liboconfig parser internals, you need to replace all dots "."
with two underscores "__". Dots are used by L<DBIx::Class> to separate table and
column names. See next example for more clarity.

=head2 EXAMPLE:

 AS SEEN BY PERL                       COLLECTD CONFIG FILE
 ------------------------------------------------------------------------
 $rs = $schema                         Schema    "CMDB::Schema"
  -> resultset('server')               ResultSet "server"
   -> search(                          <Search>
     {                                  <Condition>
      status.name => "Production",       status__name "Production"
     },                                 </Condition>
     {                                  <Attributes>
      join => "status",                  join "status"
      join => "server_type",             join "server_type"
     }                                  </Attributes>
    )                                  </Search>
 $rs -> next -> name                   HostsFrom    "name"
 $rs -> next -> server_type -> name    InstanceFrom "server_type" "name"

=head2 <Match>(Plugin|Type)[PluginInstance|TypeInstance]</Match>

This block describes the values to be matched against from the collectd cache.
Plugin and Type are mandatory. Plugin may become optional in the future. Type never will,
as it makes little sense to consolidate values with different collectd types.

=cut

=head2 CFunc

List of Consolidation functions. Currently only "avg", "min", "max", "sum", "count"
are supported. CFunc will be suffixed to the PluginInstance, e.g. resulting in
"consolidbic-mytype-avg/mytype-mytinstance".
Defaults to "avg".

=cut

sub recurse_config {
	my $config = shift;
	my %inter;
	my @children = @{$config -> {children}};
	if (@children) {
		for my $child (@children) {
			my @next = recurse_config ($child);
			my $key = $config -> {key};
			$key =~ s/__/./; # collectd liboconfig won't allow dots in key names
			if (defined $inter{$key}->{$next[0]} && ! ref $inter{$key}->{$next[0]}) {
				$inter{$key}->{$next[0]} = [$inter{$key}->{$next[0]},$next[1]];
			} else {
				$inter{$key}->{$next[0]} = $next[1];
			}
		}
		return %inter;
	} else {
		my $key = $config -> {key};
		$key =~ s/__/./; # collectd liboconfig won't allow dots in key names
		if (@{$config -> {values}} > 1) {
			return ($key, $config -> {values});
		} else {
			return ($key, $config -> {values} -> [0]);
		}
	}
}

sub my_config {
	use DDP colored => 1;
	die Dumper @_;
	my %valid_scalar_key = map { $_ => 1} qw/Interval Schema DSN Username Password ResultSet HostsFrom UnixSock DomainName PluginName Host/;
	USER: for my $child (@{$_[0] -> {children}}) {
		my $key = $child -> {key};
		if ($key =~ qr/^(Search|InstanceFrom|CFunc)$/) {
			($opt{$key}) = {recurse_config $_[0]}->{Plugin}->{$key};
			local $Data::Dumper::Indent = 0;
			my_log(LOG_DEBUG, "Registered option $key = ", Dumper $opt{$key});
		} elsif ($key =~ qr/^Match$/) {
			my %oopt = recurse_config $child;
			($opt{$key}->{$child -> {values} -> [0]}) = values %oopt;
			local $Data::Dumper::Indent = 0;
			my_log(LOG_DEBUG, "Registered option $key = ", Dumper $opt{$key});
		} else {
			VALID: for my $string (keys %valid_scalar_key) {
				if ($key =~ qr/^$string$/) {
					$opt{$key} = $child -> {values} -> [0];
					my_log(LOG_DEBUG, "Registered option $key = $opt{$key}");
					delete $valid_scalar_key{$key};
					next USER;
				}
			}
			my_log(LOG_WARNING, "Unrecognized or duplicate plugin option ".$child->{key});
		}
	}
	my $missing_opt = 0;
	for (qw/Schema DSN ResultSet HostsFrom InstanceFrom UnixSock Search Match/) {
		unless (exists $opt{$_}) {
			my_log(LOG_ERR, "Mandatory Option $_ missing");
			$missing_opt++;
		}
	}
	return if $missing_opt;
	for my $name (keys %{$opt{Match}}) {
		for (qw/Plugin Type/) {
			unless (exists $opt{Match}->{$name}->{$_}) {
				my_log(LOG_ERR, "Mandatory Option $_ missing in Match block $name");
				$missing_opt++;
			}
		}
	}
	return if $missing_opt;
	# Array Options
	for (qw/HostsFrom InstanceFrom CFunc/) { 
		my $ref = ref $opt{$_};
		if ($ref eq "HASH") {
			my_log(LOG_ERR, "Option $_ must be scalar or array");
			$missing_opt++;
		} elsif ($ref eq "") {
			$opt{$_} = [$opt{$_}];
		}
	}
	# Hashlcify Options
	for (qw/CFunc/) {
		my %o;
		for (@{$opt{$_}}) {
			$o{lc $_} = 1;
		}
		$opt{$_} = \%o;
	}
	return if $missing_opt;
}

sub my_get {
	my $ts = time;
	if ($ts < $opt{Interval} + $last_ts) {
		my_log LOG_DEBUG, "going to sleep";
		return 1;
	}
	my_log LOG_DEBUG, "waking up";

	# first let's load into memory what collectd's got in cache
	my @listval = $collectd->listval();
	unless (@listval) {
		my_log LOG_WARNING, "listval returned nothing: reinitializing socket";
		_init_sock();
		return;
	}

	# now let's load into memory what's in the database schema
	my %listhost;
	my $rs = $schema -> resultset ($opt{ResultSet}) -> search (
		$opt{Search}->{Condition},
		$opt{Search}->{Attributes}
	);
	unless ($rs) {
		my_log LOG_WARNING, "There was a problem fetching the result from DB";
		return;
	}
	while (my $host = $rs -> next) {
		#####
		#### we died here when db was unavailable:
		### DBIx::Class::ResultSet::next(): DBI Connection failed: DBI connect('dbname=smurf:host=ccmysql.in2p3.fr','smurfro',...) failed: Can't connect to MySQL server on 'ccmysql.in2p3.fr' (111) at /usr/share/perl5/vendor_perl/DBIx/Class/Storage/DBI.pm line 1176
		#####

		# retrieve hostname from DB
		my $hostname = $host;
		$hostname = $hostname -> $_ for (@{$opt{HostsFrom}});
		$hostname .= ".$opt{DomainName}" if $opt{DomainName};

		# retrieve instance name from DB
		my $instance = $host;
		$instance = $instance -> $_ for (@{$opt{InstanceFrom}});

		# now put this into hash host{instance}
		$listhost{$hostname} = $instance;
	}

	my %result;
	VALUE: for my $value (@listval) {
		# filter out unwanted values
	MATCH: for my $match (keys %{$opt{Match}}) {
		next unless $value -> {plugin} =~ qr/$opt{Match}->{$match}->{Plugin}/;
		next unless $value -> {type}   =~ qr/$opt{Match}->{$match}->{Type}/;
		if (defined $value -> {type_instance} && defined $opt{Match}->{$match}->{TypeInstance}) {
			next MATCH unless $value -> {type_instance} =~ qr/$opt{Match}->{$match}->{TypeInstance}/;
		}
		if (defined $value -> {plugin_instance} && defined $opt{Match}->{$match}->{PluginInstance}) {
			next MATCH unless $value -> {plugin_instance} =~ qr/$opt{Match}->{$match}->{PluginInstance}/;
		}

		# we have a candidate: let's see if it's in the resultset of the db
		my $host = $value->{host};
		if (exists $listhost{$host}) {
			# we have a winner
			my %ident = map { $_ => $value -> {$_} } qw/host plugin plugin_instance type type_instance/;
			my $collectd_value = $collectd->getval(%ident);
			unless ($collectd_value) {
				local $Data::Dumper::Indent = 0;
				my_log LOG_WARNING, "getval returned undef", Dumper $value;
				next VALUE;
			}
			# loop over data sources in value
			while (my ($k,$v) = each %$collectd_value) {
				unless (defined $v) {
					local $Data::Dumper::Indent = 0;
					my_log LOG_INFO,"undefined value for ds '$k'", Dumper $value;
					next;
				}
				if (exists $opt{CFunc}->{sum} or exists $opt{CFunc}->{avg}) {
					$result{$listhost{$host}}->{$match}->{sum}->{$k} += $v;
				}
				if (exists $opt{CFunc}->{min}) {
					if (exists $result{$listhost{$host}}->{$match}->{min}->{$k}) {
						$result{$listhost{$host}}->{$match}->{min}->{$k} = $v if $result{$listhost{$host}}->{$match}->{min}->{$k} > $v;
					} else {
						$result{$listhost{$host}}->{$match}->{min}->{$k} = $v;
					}
				}
				if (exists $opt{CFunc}->{max}) {
					if (exists $result{$listhost{$host}}->{$match}->{max}->{$k}) {
						$result{$listhost{$host}}->{$match}->{max}->{$k} = $v if $result{$listhost{$host}}->{$match}->{max}->{$k} < $v;
					} else {
						$result{$listhost{$host}}->{$match}->{max}->{$k} = $v;
					}
				}
				if (exists $opt{CFunc}->{avg} or exists $opt{CFunc}->{count}) {
					$result{$listhost{$host}}->{$match}->{count}->{$k}++;
				}
			}
		}
	}
	}
	# we're done, let's commit the new values to collectd
	while (my ($instance,$val) = each %result) {
	while (my ($match,$value) = each %$val) {
		if (exists $opt{CFunc}->{avg}) {
			while (my ($k,$v) = each %{$value->{sum}}) {
				$value->{avg}->{$k} = $value->{sum}->{$k} / $value->{count}->{$k};
			}
		}
		my %type = exists $opt{Match}->{$match}->{TargetType} ? ( type => $opt{Match}->{$match}->{TargetType} ) : ( type => $opt{Match}->{$match}->{Type} );
		for (keys %{$opt{CFunc}}) {
			my %plugin_instance = ( plugin_instance => "$instance-$_");
			my $pdv = {
				interval => $opt{Interval},
				host => $opt{Host} || $hostname_g,
				plugin => $opt{PluginName},
				%type,
				type_instance => $match,
				%plugin_instance,
				values => [ values %{$value->{$_}} ],
			};
			local $Data::Dumper::Indent = 0;
			my_log(LOG_DEBUG, "dispatching", Dumper $pdv);
			plugin_dispatch_values ($pdv);
		}
	}
	}
	$last_ts = $ts;
  return 1;
}

=head1 SEE ALSO

L<DBIx::Class> collectd

=head1 FILES

collectd.conf

=head1 AUTHOR

Fabien Wernli CCIN2P3.

=cut

1;

