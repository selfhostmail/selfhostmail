# install derp
include nginx

file {'/tmp/go1.17.6.linux-amd64.tar.gz':
  source => "https://go.dev/dl/go1.17.6.linux-amd64.tar.gz"
}
->
exec {'extract golang':
  command => "/usr/bin/rm -rf /usr/local/go && /usr/bin/tar -C /usr/local -xzf /tmp/go1.17.6.linux-amd64.tar.gz",
}
-> exec {"Install derp":
  environment => [ 'GOPATH=/opt/headscale', 'HOME=/opt/headscale', 'GOCACHE=/opt/headscale' ],
  command => '/usr/local/go/bin/go install tailscale.com/cmd/derper@main',
}
-> file {"/etc/systemd/system/derp.service":
  ensure  => 'file',
  content => inline_template("[Unit]
Description=DERP tailscale service

[Service]
Type=simple
ExecStart=/opt/headscale/bin/derper -a ':8443' -stun -c 'var/lib/derper/derper.key'
User=headscale
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
")
}
-> group {"headscale":
  ensure => 'present',
}
-> user {"headscale":
  ensure => 'present',
  gid    => 'headscale',
  shell  => '/sbin/nologin',
}
-> file {"/var/lib/derper/config.yaml":
  ensure => 'file',
  owner  => 'headscale',
  group  => 'headscale',
  content => inline_template("regions:
  900:
    regionid: 900
    regioncode: myderp
    regionname: My Region
    nodes:
      - name: 900a
        regionid: 900
        hostname: ${facts['fqdn']}
        ipv4: ${facts['networking']['ip6']
        ipv6: ${facts['networking']['ip6']
        stunport: 3478
        stunonly: false
        derptestport: 0
")
}
-> file {"/var/lib/derper":
  ensure => 'directory',
  owner  => 'headscale',
  group  => 'headscale',
  mode   => '0770',
}
-> file {"/var/lib/derper/derper.key":
  ensure => 'file',
  owner  => 'headscale',
  group  => 'headscale',
  mode   => '0660',
}
-> file {"/usr/local/bin/headscale":
  source => 'https://github.com/juanfont/headscale/releases/download/v0.12.1/headscale_0.12.1_linux_amd64',
  mode   => "0755",
}
-> file {"/etc/headscale":
  ensure => 'directory',
  owner  => 'headscale',
  group  => 'headscale',
}
-> file {"/var/lib/headscale":
  ensure => 'directory',
  owner  => 'headscale',
  group  => 'headscale',
}

file {"/etc/headscale/derp.yaml":
  ensure => 'file',
  owner  => 'headscale',
  group  => 'headscale',
  content => inline_template("
{
  \"derpMap\": {
    \"OmitDefaultRegions\": true,
    \"Regions\": { \"900\": {
      \"RegionID\": 900,
      \"RegionCode\": \"myderp\",
      \"Nodes\": [{
          \"Name\": \"1\",
          \"RegionID\": 900,
          \"HostName\": \"${facts['fqdn']}\",
          \"DERPPort\": 8443,
          \"STUNPort\": 3478
      }]
    }}
  }
}"}


-> file {"/etc/headscale/config.yaml":
  ensure => 'file',
  owner  => 'headscale',
  group  => 'headscale',
  content => inline_template("
server_url: https://${facts['my_domain']}
listen_addr: http://127.0.0.1:8080
private_key_path: /var/lib/headscale/private.key
derp:
  urls:
    - https://${facts['fqdn']}/derp/derpmap/default
  paths:
    - /etc/headscale/derp.yaml
  auto_update_enabled: true
  update_frequency: 24h
disable_check_updates: false
ephemeral_node_inactivity_timeout: 30m
# Postgres config
db_type: postgres
db_host: localhost
db_port: 5432
db_name: ${facts['hs_db']}
db_user: ${facts['hs_user']}
db_pass: ${facts['hs_password']}
tls_letsencrypt_hostname: ''
acl_policy_path: '/etc/headscale/acl.hujson'
dns_config:
  nameservers:
    - 1.1.1.1
  magic_dns: false
  base_domain: example.com
unix_socket: /var/run/headscale/headscale.sock
")
}
-> file {"/etc/systemd/system/headscale.service":
  ensure => 'file',
  content => inline_template("
[Unit]
Description=headscale controller
After=syslog.target
After=network.target

[Service]
Type=simple
User=headscale
Group=headscale
ExecStart=/usr/local/bin/headscale serve
Restart=always
RestartSec=5

# Optional security enhancements
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/headscale /run/headscale
AmbientCapabilities=CAP_NET_BIND_SERVICE
RuntimeDirectory=headscale

[Install]
WantedBy=multi-user.target
"),
}
-> exec {"reload daemon systemctl":
  command => "/usr/bin/systemctl daemon-reload"
}
-> service {"derp":
  ensure => 'running',
  enable => 'true'
}
-> service {"headscale":
  ensure => "running",
  enable => 'true'
}
-> exec {"create first namespace":
  command => "/usr/local/bin/headscale namespaces create ${facts['my_domain']}_ns"
}


nginx::resource::upstream { 'headscale':
  ensure => 'present',
  ip_hash   => true,
  keepalive => 60,
  members   => {
    '127.0.0.1:8080' => {
      server => '127.0.0.1',
      port   => 8080
    }
  },
}




nginx::resource::upstream { 'headscale_derp':
  ensure => 'present',
  ip_hash   => true,
  keepalive => 60,
  members   => {
    '127.0.0.1:8443' => {
      server => '127.0.0.1',
      port   => 8443
    }
  },
}
nginx::resource::server { "${facts['fqdn']}-ssl":
  ensure      => present,
  server_name => [ $facts['fqdn'], $facts['my_domain'] ],
  listen_port => 443,
  ssl_port    => 443,
  ssl         => true,
  ssl_cert    => "/etc/letsencrypt/live/${facts['my_domain']}/fullchain.pem",
  ssl_key     => "/etc/letsencrypt/live/${facts['my_domain']}/privkey.pem",
  use_default_location => false,
  locations => {
    'root' => {
        location => '/',
        proxy       => 'http://headscale',
        proxy_set_header => ['HOST $host', 'X-Real-IP $remote_addr','X-Forwarded-For $remote_addr', 'X-Forwarded-Proto https'],
        proxy_redirect => 'off',
      },
    'socket' => {
      location => '~ ^/derp',
      proxy       => 'http://headscale_derp',
      proxy_set_header => ['HOST $host', 'X-Real-IP $remote_addr','X-Forwarded-For $remote_addr', 'X-Forwarded-Proto https', 'Connection "upgrade"', 'Upgrade $http_upgrade'],
      proxy_http_version => '1.1'
    }
  }
}