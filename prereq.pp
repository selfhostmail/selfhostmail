# Notes, all firewall things are here because not everything runs on every update and we've set purge firewall ports to true.
# If you move the mail/dns firewall checks back to mail/dns they may get purged here then NOT applied there, so leave them here.
#
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

exec {'update-dnf':
  command => '/usr/bin/dnf -y update',
}
exec {'powertools':
  command => '/usr/bin/dnf config-manager --set-enabled powertools',
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

# First lets turn on the firewall

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

## Neo fetch is cool
file {'/etc/profile.d/motd.sh':
  mode => '0775',
  content => 'neofetch --disable gpu --disable resolution --disable term --disable theme --disable wm --disable de --disable packages --disable shell --disable kernel --disable model --disable term_font',
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

## Disable tuned as a daemon, 100M resident is a lot for nothing in the cloud, this will load profile only on restart of service
exec {'disable tuned':
  command => '/usr/bin/sed -i "s/daemon = 1/daemon = 0/" /etc/tuned/tuned-main.conf',
  unless  => '/usr/bin/grep "daemon = 0" /etc/tuned/tuned-main.conf"',
  notify  => Exec['stop tuned']
}
-> exec {'stop tuned':
  command => "/usr/bin/systemctl restart tuned",
  refreshonly => true
}

if $facts['mail_enable'] == 'true' {
  class { 'clamav':
    manage_clamd      => true,
    manage_freshclam  => true,
    clamd_options     => {
      'MaxScanSize' => '500M',
      'MaxFileSize' => '150M',
    },
  }
  selinux::module { 'spamd-profile':
    ensure    => 'present',
    source_te => "${facts['pwd']}/spamd-profile.te",
  }
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
}

class { '::logwatch':
  mail_to   => [ $admin_email ],
  mail_from => "donotreply@${facts['my_domain']}",
  service   => [ 'All' ],
}

# Get the various IPs we have enabled into a whitelist
$dns_secondary = split($facts['dns_secondary_list'], ',')
if $facts['wg_client_enabled'] or $facts['firezone_enabled'] {
  $local_whitelist = [ '127.0.0.1/8', '10.3.2.0/24' ] + $dns_secondary
}
else {
  $local_whitelist = [ '127.0.0.1/8' ] + $dns_secondary
}
if $facts['freedns_secondary'] == 'true' {
  $whitelist = $local_whitelist + [ '69.65.50.192' ]
}
else {
  $whitelist = $local_whitelist
}

$default_jails = [ 'ssh', 'ssh-ddos', 'selinux-ssh', 'nginx-http-auth', 'nginx-botsearch' ]
$dns_jails     = [ 'named-refused' ]
$mail_jails    = [ 'dovecot', 'postfix', 'postfix-rbl', 'postfix-sasl', 'recidive', 'sieve' ]

# Puppet of course can't reassign vars since vars are const so we play the new stack shuffle
if $facts['dns_enable'] == 'true' {
  $stage1_jails = $default_jails + $dns_jails
}
else {
  $stage1_jails = $default_jails
}
if $facts['mail_enable'] == 'true' {
  $jails = $stage1_jails + $mail_jails
}
else {
  $jails = $stage1_jails
}

class {'fail2ban':
  # Maybe one day there will be a rocky specific template
  config_file_template => "/etc/puppetlabs/code/modules/fail2ban/templates/CentOS/8/etc/fail2ban/jail.conf.epp",
  jails                => $jails,
  whitelist            => $whitelist
}
-> file {'/etc/fail2ban/action.d/custom-firewalld.conf':
  ensure => file,
  content => "
[INCLUDES]
before  =

[Definition]
actionstart =
actionstop =
actioncheck =

actionflush = sed -i '/<source address=/d' /etc/firewalld/zones/drop.xml
actionban = firewall-cmd --change-source=<ip> --zone=drop && firewall-cmd --change-source=<ip> --zone=drop --permanent
actionunban = firewall-cmd --remove-source=<ip> --zone=drop && firewall-cmd --remove-source=<ip> --zone=drop --permanent || echo 0

[Init]
"
  }
->
exec {'hacky fail2ban requirement':
  command => "/usr/bin/touch /var/log/fail2ban.log && /usr/bin/systemctl restart fail2ban",
  unless  => "/usr/bin/test -e /var/log/fail2ban.log"
}
-> nginx::resource::server{"${facts['fqdn']}-80":
  www_root    => '/usr/share/nginx/html/',
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

if $facts['mail_enable'] == 'true' {

  firewalld_service { 'Allow smtp from the external zone':
    ensure  => 'present',
    service => 'smtp',
    zone    => 'public',
  }
}
if $facts['dns_enable'] {
  firewalld_port { 'Allow 53/udp from the external zone':
    ensure   => 'present',
    port     => '53',
    protocol => 'udp'
    zone     => 'public',
  }
  firewalld_port { 'Allow 53/tcp from the external zone':
    ensure   => 'present',
    port     => '53',
    protocol => 'tcp'
    zone     => 'public',
  }
}

if $facts['firezone_enabled'] =='true' or $facts['headscale_enabled'] == 'true' {
  selinux::boolean { 'httpd_can_network_connect': }

  # Required for silent logs but disable if you don't trust nginx to set ratelimiting on its port
  selinux::boolean { 'httpd_setrlimit': }
}

selinux::module { 'logrotate-profile':
  ensure    => 'present',
  source_te => "${facts['pwd']}/logrotate-profile.te",
}