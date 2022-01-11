# 1. Postgrey
# 2. Spamass-milter
# 3. Razor/pyzor
# 4. OpenDMARC
# 5. OpenDKIM
# 6. postfix
# 7. dovecot

$mail_quota='1024000000' # ~500MB, postfix quota styling
$mail_quota_mb='1000M'   # Dovecot quota styling

notify{ "Mail Services setup: Using ${facts['my_domain']} as primary domain": }

$my_other_domain_list=split("${facts['my_other_domains']}", ',')
$my_domains = $my_other_domain_list + $facts['my_domain']
$admin_email="${admin_user}@${facts['my_domain']}"

# Create a map of our aliases to our primary domain if we're aliasing those domains
if $facts['enable_domain_alias'] == 'true' {
  $domain_alias = join($my_other_domain_list.map |$x| { "@${x} @${facts['my_domain']}" }, "\n")
}
else {
  $domain_alias = ''
}

### Postfix pre-requisites

# Enable and start postgrey

service {'postgrey':
  enable => 'true',
  ensure => 'running',
}

# Spamassassin and milter
service {'spamass-milter':
  enable => 'true',
  ensure => 'running',
}
## Setup Razor ant home dirs
exec { 'setup razor home':
  command => '/usr/bin/razor-admin -home /var/lib/razor -create; /usr/bin/razor-admin -home /var/lib/razor -discover; /usr/bin/razor-admin -home /var/lib/razor -register',
  unless  => '/usr/bin/test -d /var/lib/razor',
}
# OpenDMARC and friends
exec {'set authservid':
  command => '/usr/bin/echo "AuthservID OpenDMARC" >> /etc/opendmarc.conf',
  unless  => '/usr/bin/grep "^AuthservID" /etc/opendmarc.conf'
}
-> exec {'set igauthcli':
  command => '/usr/bin/echo "IgnoreAuthenticatedClients true" >> /etc/opendmarc.conf',
  unless  => '/usr/bin/grep "^IgnoreAuthenticatedClients" /etc/opendmarc.conf'
}
-> exec {'set rejfail':
  command => '/usr/bin/echo "RejectFailures true" >> /etc/opendmarc.conf',
  unless  => '/usr/bin/grep "^RejectFailures" /etc/opendmarc.conf'
}
-> exec {'set reqhead':
  command => '/usr/bin/echo "RequiredHeaders true" >> /etc/opendmarc.conf',
  unless  => '/usr/bin/grep "^RequiredHeaders" /etc/opendmarc.conf'
}
-> exec {'fix spf':
  command => '/usr/bin/sed -i "s/SPFIgnoreResults true/SPFIgnoreResults false/" /etc/opendmarc.conf',
  unless  => '/usr/bin/grep "SPFIgnoreResults false" /etc/opendmarc.conf'
}
-> service {'opendmarc':
  enable  => true,
  ensure  => 'running',
}

# Setup OpenDKIM and all it stuff
exec { 'Ensure opendkim can read postfix files':
  unless  => '/bin/grep -q "opendkim\\S*postfix" /etc/group',
  command => '/sbin/usermod -aG opendkim postfix',
  require => [ Package['postfix'] ]
}
group {'policyd-spf': }
-> user {'policyd-spf':
  ensure => 'present',
  gid    => 'policyd-spf',
  shell  => '/bin/false',
  managehome => false,
}
exec {'remove default key': 
  command => "/usr/bin/sed -i 's/KeyFile.*default\\.private//' /etc/opendkim.conf",
  onlyif  => "/usr/bin/grep 'KeyFile.*default' /etc/opendkim.conf"
}
->exec {'fixup opendkim configs to validate':
  command => '/usr/bin/sed -i "s/Mode\s*v\s*$/Mode       sv/" /etc/opendkim.conf',
  onlyif  => '/usr/bin/grep "Mode\s*v\s*$" /etc/opendkim.conf',
}
-> file {"/etc/opendkim/keys":
  ensure => "directory",
  owner  => "opendkim",
  group  => "opendkim"
}
-> exec {'fixup opendkim configs for address':
  command => "/usr/bin/sed -Ei \"s/^# ReportAddress.*$/ReportAddress 'Postmaster for ${facts['my_domain']}' <${admin_email}>/\" /etc/opendkim.conf",
  unless  => "/usr/bin/grep '^ReportAddress' /etc/opendkim.conf"
}
-> exec {'uncomment Keytables':
  command => '/usr/bin/sed -Ei "s/^#\s+KeyTable/KeyTable/" /etc/opendkim.conf',
  unless  => '/usr/bin/grep "^KeyTable" /etc/opendkim.conf'
}
-> exec {'uncomment SigningTable':
  command => '/usr/bin/sed -Ei "s/^#\s+SigningTable/SigningTable/" /etc/opendkim.conf',
  unless  => '/usr/bin/grep "^SigningTable" /etc/opendkim.conf'
}
-> exec {'uncomment ignore list':
  command => '/usr/bin/sed -Ei "s/^#\s+ExternalIgnoreList/ExternalIgnoreList/" /etc/opendkim.conf',
  unless  => '/usr/bin/grep "^ExternalIgnoreList" /etc/opendkim.conf'
}
-> exec {'uncomment internal hosts':
  command => '/usr/bin/sed -Ei "s/^#\s+InternalHosts/InternalHosts/" /etc/opendkim.conf',
  unless  => '/usr/bin/grep "^InternalHosts" /etc/opendkim.conf'
}
$my_domains.each |$this_domain| {
  file {"/etc/opendkim/keys/${this_domain}":
    ensure => "directory",
    owner  => "opendkim",
    group  => "opendkim"
  }
  -> exec {"add key to keytable-${this_domain}":
    command => "/usr/bin/echo '*@${this_domain}    '`date +%Y%m%d`'._domainkey.${this_domain}' >> /etc/opendkim/SigningTable",
    unless  => "/usr/bin/grep '_domainkey.${this_domain}' /etc/opendkim/SigningTable"
  }
  -> exec {"add key to signtable-${this_domain}":
    command => "/usr/bin/echo `date +%Y%m%d`'._domainkey.${this_domain}     ${this_domain}:'`date +%Y%m%d`':/etc/opendkim/keys/${this_domain}/'`date +%Y%m%d`'.private' >> /etc/opendkim/KeyTable",
    unless  => "/usr/bin/grep '_domainkey.${this_domain}' /etc/opendkim/KeyTable"
  }
  -> exec {"add trusted domain-${this_domain}":
    command => "/usr/bin/echo '*.${this_domain}' >> /etc/opendkim/TrustedHosts",
    unless  => "/usr/bin/grep '${this_domain}' /etc/opendkim/TrustedHosts"
  }
  -> exec {"generate keypair-${this_domain}":
    command => "/usr/sbin/opendkim-genkey -b 2048 -d ${this_domain} -D /etc/opendkim/keys/${this_domain} -s `date +%Y%m%d` -v",
    unless  => "/bin/ls /etc/opendkim/keys/${this_domain}/*"
  }
  -> exec {"chown keys-${this_domain}":
    command => "/usr/bin/chown opendkim: /etc/opendkim/keys/* -R",
    unless  => "/usr/bin/stat /etc/opendkim/keys/${this_domain}/*.txt | /usr/bin/grep 'Uid.*opendkim'"
  }
}
service {'opendkim':
  ensure => 'running',
  enable => true
}

###### Setup Postfix
#
#  Setup postfix to use the tables and queries that fit above
#  We use gid/uid 1900 here. If you need something different, well then you'll have to
#

class { 'postfix':
  inet_interfaces     => "all",
  smtp_listen         => "all",
  inet_protocols      => 'ipv4',
  myorigin            => $facts['domain'],
  service_ensure      => 'running',
  master_entries      => [ 'smtp-amavis unix - - n - 2 smtp
    -o syslog_name=postfix/amavis
    -o smtp_data_done_timeout=1200
    -o smtp_send_xforward_command=yes
    -o disable_dns_lookups=yes
    -o max_use=20
    -o smtp_tls_security_level=none',
  '127.0.0.1:10025   inet   n    -     n     -     -    smtpd
    -o syslog_name=postfix/10025
    -o content_filter=
    -o mynetworks_style=host
    -o mynetworks=127.0.0.0/8
    -o local_recipient_maps=
    -o relay_recipient_maps=
    -o strict_rfc821_envelopes=yes
    -o smtpd_restriction_classes=
    -o smtpd_delay_reject=no
    -o smtpd_client_restrictions=permit_mynetworks,reject
    -o smtpd_helo_restrictions=
    -o smtpd_sender_restrictions=
    -o smtpd_recipient_restrictions=permit_sasl_autheticated,permit_mynetworks,reject
    -o smtpd_end_of_data_restrictions=
    -o smtpd_error_sleep_time=0
    -o smtpd_soft_error_limit=1001
    -o smtpd_hard_error_limit=1000
    -o smtpd_client_connection_count_limit=0
    -o smtpd_client_connection_rate_limit=0
    -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks,no_address_mappings',
    'policyd-spf  unix  -       n       n       -       0       spawn
    user=policyd-spf argv=/usr/libexec/postfix/policyd-spf'
  ],
}
postfix::config { 'smtpd_client_restrictions':
  value => "reject_unknown_reverse_client_hostname,reject_rbl_client zen.spamhaus.org,reject_rbl_client bl.spamcop.net"
}
# In a nutshell, we enable SASL for dovecot, disable weak encryption, setup sql virtual user/domain/alias mappings, and use the cert from letsencrypt for our tls
postfix::config {
    'smtpd_sasl_authenticated_header': value => 'yes';
    'smtpd_sasl_auth_enable': value => 'yes';
    'smtpd_sasl_local_domain': value => $facts['my_domain'];
    'smtpd_sasl_path': value => 'private/auth';
    'smtpd_sasl_security_options': value => 'noanonymous';
    'smtpd_sasl_type': value => 'dovecot';
    'broken_sasl_auth_clients': value => 'yes';
    'smtpd_tls_auth_only': value => 'yes';
    'smtpd_tls_cert_file': value => "/etc/letsencrypt/live/${facts['my_domain']}/fullchain.pem";
    'smtpd_tls_key_file': value => "/etc/letsencrypt/live/${facts['my_domain']}/privkey.pem";
    'smtpd_tls_mandatory_protocols': value => '!SSLv2, !SSLv3, !TLSv1, !TLSv1.1';
    'smtp_tls_mandatory_protocols': value => '!SSLv2, !SSLv3, !TLSv1, !TLSv1.1';
    'smtpd_tls_protocols': value => '!SSLv2,!SSLv3';
    'smtp_tls_protocols': value => '!SSLv2,!SSLv3';
    'smtp_tls_security_level': value => 'may';
    'smtpd_tls_security_level': value => 'may';
    'smtpd_tls_loglevel': value => '1';
    'smtpd_tls_session_cache_timeout': value => '3600s';
    'smtpd_tls_session_cache_database': value => 'btree:/var/lib/postfix/smtpd_tls_cache';
    'smtpd_tls_exclude_ciphers': value => 'aNULL, eNULL, EXPORT, DES, RC4, MD5, PSK, aECDH, EDH-DSS-DES-CBC3-SHA, EDH-RSA-DES-CDC3-SHA, KRB5-DE5, CBC3-SHA';
    'smtpd_use_tls': value => 'yes';
    'tls_random_source': value => 'dev:/dev/urandom';
    'tls_random_exchange_name': value => '/var/lib/postfix/prng_exch';
    'virtual_alias_maps': value => 'hash:/etc/postfix/virtual_alias_maps proxy:pgsql:/etc/postfix/pgsql/virtual_alias_maps.cf';
    'virtual_mailbox_domains': value => 'proxy:pgsql:/etc/postfix/pgsql/virtual_mailbox_domains.cf';
    'virtual_mailbox_maps': value => 'proxy:pgsql:/etc/postfix/pgsql/virtual_mailbox_maps.cf';
    'relay_domains': value => '$mydestination, proxy:pgsql:/etc/postfix/pgsql/relay_domains.cf';
    'virtual_mailbox_base': value => '/var/mail/vmail';
    'virtual_mailbox_limit': value => $mail_quota;
    'virtual_minimum_uid': value => '1900';
    'virtual_transport': value => 'virtual';
    'virtual_uid_maps': value => 'static:1900';
    'virtual_gid_maps': value => 'static:1900';
    'local_transport': value => 'virtual';
    'local_recipient_maps': value => '$virtual_mailbox_maps';
    'smtpd_sender_login_maps': value => 'proxy:pgsql:/etc/postfix/pgsql/virtual_sender_maps.cf';
    'myhostname': value => $::fqdn;
    'mydestination': value => "localhost, localhost.localdomain";
    'mynetworks': value => '127.0.0.0/8 [::1]/128';
    'mailbox_size_limit': value => '0';
    'recipient_delimiter': value => '+-';
    'header_checks': value => 'regexp:/etc/postfix/header_checks';
    'mime_header_checks': value => '$header_checks';
    'smtpd_helo_required': value => 'yes';
    'smtpd_discard_ehlo_keywords': value => 'chunking, silent-discard';
    'smtpd_sender_restrictions': value => "permit_sasl_authenticated,reject_unknown_reverse_client_hostname,reject_unknown_sender_domain,reject_non_fqdn_sender";
    'smtpd_recipient_restrictions': value => "reject_unknown_recipient_domain,reject_unauth_pipelining,permit_mynetworks,permit_sasl_authenticated,defer_unauth_destination,check_policy_service unix:private/policyd-spf,check_policy_service unix:postgrey/socket";
    'smtpd_relay_restrictions': value => "permit_mynetworks,permit_sasl_authenticated,defer_unauth_destination";
    'smtpd_data_restrictions': value => "reject_unauth_pipelining,permit";
    'content_filter': value => "smtp-amavis:[127.0.0.1]:10024";
    'smtpd_proxy_options': value => "speed_adjust";
    'policyd-spf_time_limit': value => '3600';
    'milter_default_action': value => 'accept';
    'milter_protocol': value => '6';
    'smtpd_milters': value => 'inet:127.0.0.1:8891,inet:127.0.0.1:8893,unix:/run/spamass-milter/postfix/sock';
    'non_smtpd_milters': value => '$smtpd_milters';
    'disable_vrfy_command': value => "yes";
}
-> file {'/etc/postfix/pgsql':
  ensure => 'directory',
  owner => 'root',
  group => 'root'
}
# There's a bunch of headers that leak info, we don't want postfix to forward those on
-> exec {'hack for regex':
  command => "/usr/bin/echo '/^Received:.*with ESMTPSA/      REPLACE Received: dummyhost
/^X-Originating-IP:/            IGNORE
/^X-Mailer:/                    IGNORE
/^Mime-Version:/                IGNORE
/^User-Agent:/                  IGNORE
' > /etc/postfix/header_checks",
  unless => '/usr/bin/grep "X-Originating-IP" /etc/postfix/header_checks'
}

postfix::hash { '/etc/postfix/virtual_alias_maps':
  ensure  => 'present',
  content => $domain_alias
}

postfix::conffile {'pgsql/virtual_alias_maps.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    table       => 'virtual_aliases',
    where       => 'source',
    select_field => 'destination',
    query       => "SELECT (SELECT email FROM virtual_users AS v1 WHERE v1.email = v.destination) FROM virtual_aliases AS v WHERE source='%s'"
  }
}

postfix::conffile {'pgsql/virtual_mailbox_domains.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    query       => "SELECT virtual_domain FROM virtual_domains WHERE virtual_domain = '%s' AND host = '${facts['fqdn']}' AND active = 'true'"
  }
}
postfix::conffile {'pgsql/virtual_mailbox_limits.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    query       => "SELECT quota FROM virtual_users WHERE email='%s'"
  }
}
postfix::conffile {'pgsql/virtual_mailbox_maps.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    query       => "SELECT maildir FROM virtual_users WHERE email='%s'"
  }
}
postfix::conffile {'pgsql/virtual_sender_maps.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    query       => "SELECT email FROM virtual_users WHERE email='%s'",
  }
}
postfix::conffile {'pgsql/relay_domains.cf':
  options => {
    user        => $facts['pf_user'],
    password    => $facts['pf_password'],
    hosts       => 'localhost',
    dbname      => $facts['postfix_db'],
    query       => "SELECT virtual_domain FROM virtual_domains WHERE virtual_domain='%s' AND NOT host = '${facts['fqdn']}' AND active= 'true' "
  }
}

### Set SELinux required changes
# We need to give postfix / dovecot / spamassassin some rights to the new file structure
selinux::module { 'postfix-virtual':
  ensure    => 'present',
  source_te => '/root/selfhostmail/postfix-virtual.te',
}


#### Setup Dovecot
#  We setup dovecot using maildir and getting data / auth from SQL

if $facts['wg_server_enabled'] == 'true' {
  $dovecot_ip = $facts['networking']['interfaces']['wg-firezone']['ip']
}
elsif  $facts['wg_client_enabled'] == 'true'{
  $dovecot_ip = $facts['networking']['interfaces']['wg0']['ip']
}
else {
  $dovecot_ip = $facts['networking']['ip']
}

class { 'dovecot':
  plugins => ['$mail_plugins', 'zlib'],
  config => {
    protocols => 'imap pop3 submission',
    submission_relay_host => '127.0.0.1',
    submission_relay_trusted => 'yes',
    listen => $dovecot_ip,
    first_valid_uid => 1900
  },
  configs => {
    '10-auth' => {
      passdb => {
        driver => 'sql',
        args   => '/etc/dovecot/dovecot-sql.conf',
      },
      auth_mechanisms => 'plain login',
      mail_home       => "/var/mail/vmail/%n/",
      mail_location   =>  "maildir:~/"
    },
    '10-user' => {
      userdb => {
        driver => 'sql',
        args   => '/etc/dovecot/dovecot-sql.conf',
      },
      auth_mechanisms => 'plain login',
      mail_home       => "/var/mail/vmail/%n/",
      mail_location   =>  "maildir:~/"
    },
    '10-logging' => {
      log_path => 'syslog',
    },
    '10-master' => {
      "service auth" => {
        "unix_listener /var/spool/postfix/private/auth" => {
          "mode" => "0660",
          "user" => "postfix",
          "group" => "postfix"
        }
      }
    },
    '10-ssl' => {
      'disable_plaintext_auth' => 'yes',
      'ssl_cert' => "</etc/letsencrypt/live/${facts['my_domain']}/fullchain.pem",
      'ssl_key' => "</etc/letsencrypt/live/${facts['my_domain']}/privkey.pem",
      'ssl_cipher_list' => 'ALL:!LOW:!SSLv2:!SSLv3'
    }
  },
  extconfigs => {
    'dovecot-sql.conf' => {
      "driver" => "pgsql",
      "connect" => "host=localhost dbname=${facts['postfix_db']} user=${facts['dove_user']} password=${facts['dove_password']}",
      "default_pass_scheme" => "MD5-CRYPT",
      "password_query" => "SELECT email as user, password FROM virtual_users WHERE email='%u';",
      "user_query" => "SELECT '/var/mail/vmail/' || maildir AS home, 1900 as uid, 1900 as gid, quota FROM virtual_users  WHERE email = '%u'"
    }
  }
}

file {'/var/mail/vmail':
  ensure => 'directory',
  owner => 1900,
  group => 1900,
}
-> file {"/var/mail/vmail/${admin_user}":
  ensure => 'directory',
  owner => 1900,
  group => 1900,
}