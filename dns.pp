notify{ "Installing named services: using ${facts['my_domain']} as primary domain": }

$admin_email="${admin_user}@${facts['my_domain']}"

# Setup secondaries
if $facts['freedns_secondary'] == 'true' {
  $axfer_list = '69.65.50.192;'
}
elsif $facts['dns_seconday_list'] != '' {
  $axfer_list = "${facts['dns_seconday_list']};"
}
else {
  $axfer_list = 'none;'
}

# Grab the list of all domains and build some basic facts
$my_other_domain_list=split("${facts['my_other_domains']}", ',')
$my_domains = $my_other_domain_list + $facts['my_domain']

# Hacky puppet doesn't allow rewriting vars so here's a hack to create a 'fact list' of other records per domain
# See vars.sh for how to use facter_example_com_records, which is used here
$other_records = Hash($my_domains.map |$dom| {
  $name = regsubst($dom, "[.]", "_", "G")
  if $facts["${name}_records"] {
    $recs = split($facts["${name}_records"],'[|]')
    [ $dom, $recs ]
  }
  else {
    [ $dom, [] ]
  }
})

# Make us authoritative for all of our domains
$zones = $my_domains.map |$dom| {
  [ $dom, [
      'type master',
      "file \"${dom}.db\"",
      'key-directory "/var/named/keys"',
      'auto-dnssec maintain',
      'inline-signing yes',
      "allow-transfer { ${axfer_list} }",
      'allow-query    { any; }',
      'allow-update   { none; }',
  ] ]
}
file {'/var/log/named':
  ensure => 'directory',
  owner  => 'named',
  group  => 'named',
  require => Class['bind'],
  notify  => Exec['restart named']
}
file {'/var/named/keys':
  ensure => 'directory',
  owner  => 'named',
  group  => 'named',
  require => Class['bind'],
}

class {'bind':
  listen_on              => 'port 53 { any; }',
  listen_on_v6           => 'port 53 { any; }',
  allow_query            => '{ any; }',
  allow_update           => '{ none; }',
  allow_transfer         => "{ ${axfer_list} }",
  directory              => '"/var/named"',
  dump_file              => '"/var/named/data/cache_dump.db"',
  statistics_file        => '"/var/named/data/named_stats.txt"',
  memstatistics_file     => '"/var/named/data/named_mem_stats.txt"',
  recursion              => 'no',
  dnssec_enable          => 'yes',
  dnssec_validation      => 'auto',
  bindkeys_file          => '"/etc/named.iscdlv.key"',
  managed_keys_directory => '"/var/named/dynamic"',
  pid_file               => '"/run/named/named.pid"',
  logging                => 'true',
  logging_config         => 'logging {
    channel security_file {
        file "/var/log/named/security.log" versions 3 size 30m;
        severity dynamic;
        print-time yes;
    };
    category security {
        security_file;
    };
};',
  session_keyfile        => '"/run/named/session.key"',
  version                => '"[SECURED]"',
  server_id              => 'none',
  zone                   => $zones,
  include                => [ '"/etc/named.rfc1912.zones"', '"/etc/named.root.key"' ],
  notify                 => Exec['restart named']
}
exec {"restart named":
  command     => "/usr/bin/systemctl restart named",
  refreshonly => true
}

$my_domains.each |$this_domain| {
  $zone_exists = find_file("/var/named/${this_domain}.db")
  # Note that we don't override this file again after creation.........
  if $facts['freedns_secondary'] == 'true' {
    $ns2 = 'afraid.org'
  }
  else {
    $ns2 = "${this_domain}"
  }
  notify {"Records in ${this_domain} to add: ${other_records[$this_domain]}": }
  # Add the root for mydomain, we won't do that on others since we don't know how they will be used
  if $facts['my_domain'] == $facts['this_domain'] {
    $my_domain_rec =  "@        IN    A       ${facts['networking']['ip']"
  }
  else {
    $my_domain_rec = []
  }
  $records = [
    "@        IN    NS      ns1.${this_domain}.",
    "@        IN    NS      ns2.${ns2}.",
    "ns1      IN    A       ${facts['networking']['ip']}",
    "ns2      IN    A       ${facts['networking']['ip']}",
    "@        IN    TXT     \"v=spf1 +mx ip4:${facts['networking']['ip']} -all\"",
    "_dmarc   IN    TXT     \"v=DMARC1; p=quarantine; rua=mailto:postmaster@${this_domain}; ruf=mailto:postmaster@${this_domain}; fo=1; pct=100\"",
    "@        IN    MX  50  ${this_domain}."
  ] + $other_records[$this_domain] + $my_domain_rec
  if $facts['update_dns'] == 'true' {
    bind::zone_file { "${this_domain}.db":
      file_name       => "${this_domain}.db",
      nameserver      => "ns1.${this_domain}.",
      admin           => "hostmaster",
      ttl             => '3600',
      serial          => '2',
      refresh         => '3600',
      retry           => '1800',
      expire          => '1209600',
      minimum         => '3600',
      records         => $records
    }
  #  # Puppet ordering hack, I'm open to other ideas on how to get a loop'd resource to run before an exec......
    -> exec {"dummy to update serial since zone_file can't notify ${this_domain}":   #and a -> link would make a dependency chain with dkim records and serial is refresh only
      command => "/usr/bin/true",
      notify  => [ Exec["update serial-${this_domain}"] ],
      before  => Exec["update serial-${this_domain}"]
    }
  }
  exec {"update serial-${this_domain}":
    command     => "/usr/bin/sed -i \"s/.*; serial$/\\t\\t\\t\\t\\t$(/bin/date '+%s') ; serial/\" /var/named/${this_domain}.db",
    refreshonly => true,
    before      => [ Exec["add dkim records-${this_domain}"] ],
    notify      => Service['named']
  }
  if $facts['mail_enable'] == 'true' {
    exec {"add dkim records-${this_domain}":
      command => "/usr/bin/sed -E 's/[()]//g' /etc/opendkim/keys/${this_domain}/*.txt | /usr/bin/tr -d '\n' >> /var/named/${this_domain}.db",
      unless  => "/usr/bin/grep 'domainkey' /var/named/${this_domain}.db",
      notify  => Service['named']
    }
  }
  exec {"make zsk for ${this_domain}":
    command => "/usr/sbin/dnssec-keygen -K /var/named/keys -r /dev/urandom -a ECDSAP256SHA256 ${this_domain}",
    unless  => "/usr/bin/find /var/named/keys | /usr/bin/grep ${this_domain}",
    notify  => [ Exec["make ksk for ${this_domain}"], Exec["chown keys ${this_domain}"] ],
    require => File['/var/named/keys']
  }
  -> exec {"make ksk for ${this_domain}":
    command => "/usr/sbin/dnssec-keygen -K /var/named/keys -r /dev/urandom -a ECDSAP256SHA256 -fKSK -n ZONE ${this_domain} 2>/dev/null >/tmp/ksk_file_name_${this_domain}",
    notify  => [ Exec["load keys ${this_domain}"], Exec["chown keys ${this_domain}"], Exec["create DS records for ${this_domain} in roots home"] ],
    refreshonly => true
  }
  -> exec {"chown keys ${this_domain}":
    command => "/usr/bin/chown named:named /var/named/keys/*",
    refreshonly => true,
  }
  -> exec {"load keys ${this_domain}":
    command => "/usr/sbin/rndc reload; /usr/sbin/rndc reconfid; /usr/sbin/rndc loadkeys ${this_domain}",
    notify => Exec["sign keys ${this_domain}"],
    refreshonly => true
  }
  -> exec {"sign keys ${this_domain}":
    command => "/usr/sbin/rndc signing -list ${this_domain}",
    notify => Exec["create DS records for ${this_domain} in roots home"],
    refreshonly => true
  }
  -> exec {"create DS records for ${this_domain} in roots home":
    command => "/usr/sbin/dnssec-dsfromkey /var/named/keys/$(cat /tmp/ksk_file_name_${this_domain}) > /root/DS_FOR_REGISTRAR_${this_domain}.db.txt",
    refreshonly => true,
    notify  => Exec['restart named']
  }
}
firewalld_service { 'Allow dns from the external zone':
    ensure  => 'present',
    service => 'dns',
    zone    => 'public',
}
