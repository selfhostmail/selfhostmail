# install derp

['golang','golang-bin'].each |$package| {
  package { $package:
    ensure => latest
  }
}

exec {"Install derp":
  command => "/usr/bin/go install tailscale.com/cmd/derper@main",
  require => [ Package['golang'], Package['golang-bin'] ]
}
-> file {"/etc/systemd/system/derp.service":
  ensure  => 'file',
  content => inline_template("[Unit]
Description=DERP tailscale service
Type=simple
ExecStart=derper --hostname ${facts['fqdn']}
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
-> file {"/usr/local/bin/headscale":
  source => "https://github.com/juanfont/headscale/releases/download/v0.12.1/headscale_0.12.1_linux_amd64",
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
-> file {"/etc/headscale/config.yaml":
  ensure => 'file',
  owner  => 'headscale',
  group  => 'headscale',
  content => inline_template("
server_url: https://${facts['my_domain']}
listen_addr: 127.0.0.1:8080
private_key_path: /var/lib/headscale/private.key
derp:
  urls:
    - https://${facts['fqdn']}/derpmap/default
  paths:
    - /etc/headscale/derp-example.yaml
  auto_update_enabled: true
  update_frequency: 24h
disable_check_updates: false
ephemeral_node_inactivity_timeout: 30m
# Postgres config
db_type: postgres
db_host: localhost
db_port: 5432
db_name: headscale
db_user: foo
db_pass: bar
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