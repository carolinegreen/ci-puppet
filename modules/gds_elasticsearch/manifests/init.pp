# == Class: gds_elasticsearch
#
# GOV.UK specific class to configure what is currently an in-house ES
# module, but will in future be elasticsearch/puppet-elasticsearch.
#
# === Parameters
#
# Lots missing!
#
# [*version*]
#   The version of elasticsearch to install.  This must specify an exact
#   version (eg 1.4.2)
#
class gds_elasticsearch (
  $version,
  $cluster_hosts = ['localhost'],
  $cluster_name = 'elasticsearch',
  $heap_size = '512m',
  $number_of_shards = '5',
  $number_of_replicas = '1',
  $minimum_master_nodes = '1',
  $refresh_interval = '1s',
) {

  validate_re($version, '^\d+\.\d+\.\d+$', 'gds_elasticsearch::version must be in the form x.y.z')

  anchor { 'gds_elasticsearch::begin': }

  $http_port = '9200'
  $transport_port = '9300'

  $repo_version = regsubst($version, '\.\d+$', '') # 1.4.2 becomes 1.4 etc.
  class { 'gds_elasticsearch::repo':
    repo_version => $repo_version,
  }

  class { 'elasticsearch':
    version     => $version,
    manage_repo => false,
    config      => {}, # Needed to work around https://github.com/elasticsearch/puppet-elasticsearch/issues/183
    require     => Anchor['gds_elasticsearch::begin'],
    before      => Anchor['gds_elasticsearch::end'],
  }

  exec { 'disable-default-elasticsearch':
    onlyif      => '/usr/bin/test -f /etc/init.d/elasticsearch',
    command     => '/etc/init.d/elasticsearch stop && /bin/rm -f /etc/init.d/elasticsearch && /usr/sbin/update-rc.d elasticsearch remove',
    before      => Elasticsearch::Instance[$::fqdn],
    require     => Package['elasticsearch'],
  }

  # FIXME: Remove this once it's run everywhere
  exec {"stop_old_elasticsearch-${cluster_name}_service":
    command => "service elasticsearch-${cluster_name} stop || /bin/true",
    onlyif  => "test -f /etc/init/elasticsearch-${cluster_name}.conf",
  }
  # FIXME: Remove this once it's run everywhere
  file { "/etc/init/elasticsearch-${cluster_name}.conf":
    ensure  => absent,
    require => Exec["stop_old_elasticsearch-${cluster_name}_service"],
    before  => Elasticsearch::Instance[$::fqdn],
  }
  # FIXME: Remove this once it's run everywhere
  file { "/var/lib/elasticsearch-${cluster_name}":
    ensure => absent,
    force  => true,
  }

  elasticsearch::instance { $::fqdn:
    config        => {
      'cluster.name'             => $cluster_name,
      'index.number_of_replicas' => $number_of_replicas,
      'index.number_of_shards'   => $number_of_shards,
      'index.refresh_interval'   => $refresh_interval,
      'transport.tcp.port'       => $transport_port,
      'network.publish_host'     => $::fqdn,
      'node.name'                => $::fqdn,
      'http.port'                => $http_port,
      'discovery'                => {
        'zen' => {
          'minimum_master_nodes' => $minimum_master_nodes,
          'ping'                 => {
            'multicast.enabled' => false,
            'unicast.hosts'     => $cluster_hosts,
          },
        },
      },
    },
    datadir       => '/mnt/elasticsearch',
    init_defaults => {
      'ES_HEAP_SIZE' => $heap_size,
    },
  }

  Class['elasticsearch'] -> Elasticsearch::Instance[$::fqdn] -> Anchor['gds_elasticsearch::end']

  include gds_elasticsearch::estools

  anchor { 'gds_elasticsearch::end': }
}
