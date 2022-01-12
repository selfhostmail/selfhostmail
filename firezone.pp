include nginx

$admin_email="${facts['admin_user']}@${facts['my_domain']}"
$version="0.2.2"
$filename="firezone_${version}-centos8-amd64.rpm"
$remote_file="https://github.com/firezone/firezone/releases/download/${version}/${filename}"

$my_other_domain_list=split("${facts['my_other_domains']}", ',')
$my_domains = $my_other_domain_list + $facts['my_domain']

file { "/root/${filename}":
  source => $remote_file,
}
exec { "install firezone":
  command     => "/usr/bin/dnf --assumeyes --quiet install /root/${filename}",
  unless      => "/usr/bin/rpm -qa | /usr/bin/grep firezone-${version}",
  require     => File["/root/${filename}"]
}
-> exec {"boostrap firezon":
  command     => "/usr/bin/firezone-ctl reconfigure",
  unless      => "/usr/bin/test -e /etc/firezone/firezone.rb"
}
-> exec {"set fqdn for firezone":
  command     => "/usr/bin/sed -r -i \"s/^#*\s*(default\\['firezone'\\]\\['fqdn'\\]) =.*/\\1 = '${facts['my_domain']}'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['fqdn'\\] = '${facts['my_domain']}'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
  -> exec {"set cert for firezone":
  command     => "/usr/bin/sed -r -i \"s/^#*\s*(default\\['firezone'\\]\\['ssl'\\]\\['certificate'\\]) =.*/\\1 = '\\/etc\\/letsencrypt\\/live\\/${facts['my_domain']}\\/fullchain.pem'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['ssl'\\]\\['certificate'\\]\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set cert key for firezone":
  command     => "/usr/bin/sed -r -i \"s/^#*\s*(default\\['firezone'\\]\\['ssl'\\]\\['certificate_key'\\]) =.*/\\1 = '\\/etc\\/letsencrypt\\/live\\/${facts['my_domain']}\\/privkey.pem'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['ssl'\\]\\['certificate_key'\\]\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
  -> exec {"set admin email for firezone":
  command     => "/usr/bin/sed -r -i \"s/^#*\s*(default\\['firezone'\\]\\['admin_email'\\]) =.*/\\1 = '${admin_email}'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['admin_email'\\]\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set pgsql for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# # (default\\['firezone'\\]\\['postgresql'\\]\\['enabled'\\]) =.*/\\1 = false/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -q -e \"^default\\['firezone'\\]\\['postgresql'\\]\\['enabled'\\] = false\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set pgsqluser for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# # (default\\['firezone'\\]\\['database'\\]\\['user'\\]) =.*/\\1 = '${facts['fz_user']}'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['database'\\]\\['user'\\] = '${facts['fz_user']}'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set pgsql dbname for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# # (default\\['firezone'\\]\\['database'\\]\\['name'\\]) =.*/\\1 = '${facts['fz_db']}'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['database'\\]\\['name'\\] = '${facts['fz_db']}'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set pgsql dbhost for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# # (default\\['firezone'\\]\\['database'\\]\\['host'\\]) =.*/\\1 = '127.0.0.1'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['database'\\]\\['host'\\] = '127.0.0.1'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set pgsql dbport for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# # (default\\['firezone'\\]\\['database'\\]\\['port'\\]) =.*/\\1 = '5432'/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['database'\\]\\['port'\\] = '5432'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
-> exec {"set nginx disable for firezone":
  command     => "/usr/bin/sed -r -i \"s/^# (default\\['firezone'\\]\\['nginx'\\]\\['enabled'\\]) =.*/\\1 = false/\" /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['nginx'\\]\\['enabled'\\] = false\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
### When this is added, change to sed
-> exec {"set db pw for firezone":
  command     => "/usr/bin/echo \"default['firezone']['database']['password'] = '${facts['fz_password']}'\" >> /etc/firezone/firezone.rb",
  unless      => "/usr/bin/grep -e \"^default\\['firezone'\\]\\['database'\\]\\['password'\\] = '${facts['fz_password']}'\" /etc/firezone/firezone.rb",
  notify      => Exec['refresh firezone config']
}
exec {"refresh firezone config":
  command     => "/usr/bin/firezone-ctl reconfigure",
  refreshonly => true
}
-> sysctl { 'net.core.default_qdisc':          value => 'fq'}
-> sysctl { 'net.ipv4.tcp_congestion_control': value => 'bbr'}
-> sysctl { 'net.ipv4.ip_forward':             value => '1' }
-> sysctl { 'net.ipv4.conf.default.rp_filter': value => '1' }
-> sysctl { 'net.ipv4.conf.all.rp_filter':     value => '1' }
-> sysctl { 'net.ipv4.tcp_syncookies':         value => '1' }
-> sysctl { 'net.ipv6.conf.all.forwarding':    value => '1' }
nginx::resource::upstream { 'firezone_phoenix':
  ensure => 'present',
  ip_hash   => true,
  keepalive => 60,
  members   => {
  '127.0.0.1:13000' => {
    server => '127.0.0.1',
    port   => 13000
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
      proxy       => 'http://firezone_phoenix',
      proxy_set_header => ['HOST $host', 'X-Real-IP $remote_addr','X-Forwarded-For $remote_addr', 'X-Forwarded-Proto https'],
      proxy_redirect => 'off',
    },
    'live' => {
      location => '~ ^/live',
      proxy       => 'http://firezone_phoenix',
      proxy_set_header => ['HOST $host', 'X-Real-IP $remote_addr','X-Forwarded-For $remote_addr', 'X-Forwarded-Proto https', 'Connection "upgrade"', 'Upgrade $http_upgrade'],
      proxy_http_version => '1.1'
    },
    'socket' => {
      location => '~ ^/socket',
      proxy       => 'http://firezone_phoenix',
      proxy_set_header => ['HOST $host', 'X-Real-IP $remote_addr','X-Forwarded-For $remote_addr', 'X-Forwarded-Proto https', 'Connection "upgrade"', 'Upgrade $http_upgrade'],
      proxy_http_version => '1.1'
    }
  }
}
file {'/etc/firewalld/services/wireguard.xml':
  ensure => 'file',
  content => inline_template('<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>wireguard</short>
  <description>WireGuard open UDP port <%= @wg_server_port -%> for client connections</description>
  <port protocol="udp" port="<%= @wg_server_port -%>"/>
</service>'),
}
-> firewalld_zone { 'trusted':
  ensure           => present,
  target           => 'ACCEPT',
  masquerade       => true,
  interfaces       => ['wg-firezone'],
  purge_rich_rules => true,
  purge_services   => true,
  purge_ports      => true,
}
-> firewalld_service { 'Allow wireguard from the external zone':
  ensure  => 'present',
  service => 'wireguard',
  zone    => 'public',
}
-> exec {'reload firewall':
  command => "/usr/bin/systemctl restart firewalld",
  refreshonly => true
}
selinux::boolean { 'httpd_setrlimit': }

package { "dnsmasq":
  ensure => latest
}
->
file {"/etc/dnsmasq.conf":
  ensure => file,
  content => inline_template("domain-needed
bogus-priv
no-resolv
no-poll
server=1.1.1.1
user=dnsmasq
group=dnsmasq
except-interface=eth0
bind-interfaces
no-hosts
no-negcache
conf-dir=/etc/dnsmasq.d,.rpmnew,.rpmsave,.rpmorig"),
  require => Package['dnsmasq']
}
-> service {"dnsmasq":
  ensure => 'running',
  enable => 'true'
}
-> exec {"set resolv to dnsmasq":
  command => "/usr/bin/sed -E '0,/nameserver/{s/^(nameserver.*)/nameserver ${facts['networking']['wg-firezone']['ip']}\\n\\1/}' /etc/resolv.conf",
  unless  => "/usr/bin/grep 'nameserver ${facts['networking']['wg-firezone']['ip']}' /etc/resolv.conf"
}
