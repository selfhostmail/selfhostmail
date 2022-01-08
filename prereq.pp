# 1. Update, enable EL,epel,powertools repos and install dependencies
# 2. Setup neofetch so we know if we need to reboot on login
# 3. Setup automatic updates
# 4. Setup wireguard
# 5. Setup clamav
# 6. Setup fail2ban
# 7. Setup amavis
# 8. Setup logwatch
# 9. Setup firewall
# 10. Setup nginx
# 11. Setup certbot for letsencrypt certs

$admin_email="${facts['admin_user']}@${facts['my_domain']}"

include nginx

notify {"installing prereqs, updates, antivirus, logwatch, and more": }

exec {'update-dnf and powertools':
  command => '/usr/bin/dnf -y update; /usr/bin/dnf config-manager --set-enabled powertools',
  unless  => '/usr/bin/ls /etc/yum.repos.d/*-PowerTools.repo',
}

$default_packages = [
  'wget', 'unzip', 'curl', 'net-tools', 'neofetch', 'python3-certbot-nginx.noarch', 
  'dnf-automatic', 'postgresql-contrib',
]
$wireguard_packages = [ 'kmod-wireguard', 'wireguard-tools' ]
$mail_packages = [
  'pypolicyd-spf', 'amavis',  'postfix-pgsql', 'dovecot-pgsql', 'arj', 'spax', 'p7zip', 'lz4', 
  'opendkim', 'perl-Getopt-Long', 'spamass-milter-postfix', 'perl-Razor-Agent', 'opendmarc', 'postgrey'
]
$default_packages.each |$pack| {
  package{ $pack:
    ensure => latest
  }
}
if $facts['wg_client_enabled'] == 'true' or $facts['headscale_enabled'] == 'true' or $facts['firezone_enabled'] == 'true' {
  $wireguard_packages.each |$pack| {
    package{ $pack:
      ensure => latest
    }
  }
}
if $facts['mail_enable'] == 'true' {
  $mail_packages.each |$pack| {
    package{ $pack:
      ensure => latest
    }
  }
}


## Neo fetch is cool
file {'/etc/profile.d/motd.sh':
  mode => '0775',
  content => 'neofetch --disable gpu --disable resolution',
  require => Package['neofetch']
}
exec {'set automatic update to install':
  command => '/usr/bin/sed -i "s/apply_updates = no/apply_updates = yes/" /etc/dnf/automatic.conf',
  unless  => '/usr/bin/grep "apply_updates = yes" /etc/dnf/automatic.conf',
  require => Package['dnf-automatic']
}
-> exec {'enable auto update cron timer':
  command => '/usr/bin/systemctl enable --now dnf-automatic.timer',
  unless  => '/usr/bin/systemctl is-enabled dnf-automatic.timer'
}

class { 'clamav':
  manage_clamd      => true,
  manage_freshclam  => true,
  clamd_options     => {
    'MaxScanSize' => '500M',
    'MaxFileSize' => '150M',
  },
}
class { '::logwatch':
  mail_to   => [ $admin_email ],
  mail_from => "donotreply@${facts['my_domain']}",
  service   => [ 'All' ],
}
$local_whitelist = ['127.0.0.1']
if $facts['freedns_secondary'] == 'true' {
  $whitelist = $local_whitelist + ['69.65.50.192']
}
else {
  $whitelist = $local_whitelist
}
class {'fail2ban':
  # Maybe one day there will be a rocky specific template
  config_file_template => "/etc/puppetlabs/code/modules/fail2ban/templates/CentOS/8/etc/fail2ban/jail.conf.epp",
  jails                => [ 'ssh', 'ssh-ddos', 'dovecot', 'postfix', 'postfix-rbl', 'postfix-sasl', 'recidive', 'sieve', 'selinux-ssh', 'nginx-http-auth', 'nginx-botsearch', 'named-refused' ],
  whitelist            => $whitelist
}
->
exec {'hacky fail2ban requirement':
  command => "/usr/bin/touch /var/log/fail2ban.log && /usr/bin/systemctl restart fail2ban",
  unless  => "/usr/bin/test -e /var/log/fail2ban.log"
}
if $facts['mail_enable'] == 'true' {
  exec {'amavis - domain':
    command => "/usr/bin/sed -i \"s/^\\\$mydomain = '.*/\\\$mydomain = '${facts['my_domain']}';/\" /etc/amavisd/amavisd.conf; /usr/bin/sed -i \"s/^# \\\$myhostname = '.*/\\\$myhostname = '${facts['fqdn']}';/\" /etc/amavisd/amavisd.conf;",
    unless  => "/usr/bin/grep \"\\\$mydomain = '${facts['my_domain']}'\" /etc/amavisd/amavisd.conf"
  }
  -> exec {'amavis - virus check':
    command => '/usr/bin/sed -i "s/^# @bypass_virus_checks_maps/@bypass_virus_checks_maps/" /etc/amavisd/amavisd.conf',
    unless  => '/usr/bin/grep "^@bypass_virus_checks_map" /etc/amavisd/amavisd.conf',
    notify  => Service['amavisd']
  }
  service {'amavisd':
    enable  => true,
    ensure  => running
  }
  firewalld_service { 'Allow smtp from the external zone':
    ensure  => 'present',
    service => 'smtp',
    zone    => 'public',
  }
}
class {'firewalld': }

firewalld_zone { 'public':
    ensure           => present,
    target           => '%%REJECT%%',
    purge_rich_rules => true,
    purge_services   => true,
    purge_ports      => true,
}
-> firewalld_service { 'Allow SSH from the external zone':
    ensure  => 'present',
    service => 'ssh',
    zone    => 'public',
}
-> firewalld_service { 'Allow http from the external zone':
    ensure  => 'present',
    service => 'http',
    zone    => 'public',
}
-> firewalld_service { 'Allow https from the public zone':
    ensure  => 'present',
    service => 'https',
    zone    => 'public',
}
-> nginx::resource::server{"${facts['fqdn']}-80":
  www_root => '/usr/share/nginx/html/',
  server_name => [ $facts['fqdn'], $facts['my_domain'] ]
}
-> class { 'letsencrypt':
  email          => $facts['le_email'],
  package_ensure => 'latest',
}
-> letsencrypt::certonly { $facts['my_domain'] :
  domains       => [ $facts['my_domain'], $facts['fqdn'] ],
  plugin        => 'nginx'
}
file { '/etc/systemd/system/nginx.service.d/override.conf':
  ensure  => file,
  owner   => 0,
  group   => 0,
  mode    => '0644',
  content => "[Service]\nRuntimeDirectory=nginx\n",
  notify  => [
    Exec['daemon-reload'],
  ]
}
exec {'daemon-reload':
  command => "/usr/bin/systemctl daemon-reload",
  refreshonly => true,
  require => Class['nginx'],
}
if $facts['firezone_enabled'] =='true' or $facts['headscale_enabled'] == 'true' {
  selinux::boolean { 'httpd_can_network_connect': }

  # Required for silent logs but disable if you don't trust nginx to set ratelimiting on its port
  selinux::boolean { 'httpd_setrlimit': }
}
