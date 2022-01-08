#### Setup the postgres server
#
# 2 roles required, postfix and dovecot
# some can be puppetted, some must be done with sql statements
# Order Is Important Here, do not mess with arrows or order
#

$user_ids=986  # Don't change unless it conflicts, not tested with other IDs with selinux profiles

$mail_quota='1024000000' # ~500MB, postfix quota styling
$mail_quota_mb='1000M'   # Dovecot quota styling



$admin_email="${admin_user}@${facts['my_domain']}"

### sql commands

## Schema
# virtual_domains: id, virtual_domain, host, active
#   host = which host to relay from
#   active = is domain relayable or should i reject
# virtual_users: id, virtual_domain_id, email, password, maildir, quota, timestamp
# virtual_alias: id, virtual_domain_id, source, destination

$my_virtual_domains = split($facts['my_other_domains'], ',')

# Don't touch these
$virtdomain_table_cmd = "CREATE TABLE virtual_domains(id SERIAL PRIMARY KEY, virtual_domain varchar(50) NOT NULL, host varchar(50), active BOOLEAN NOT NULL)"
$virtdomain_unless    = "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'virtual_domains'"
$virtusers_table_cmd  = "CREATE TABLE virtual_users(id SERIAL PRIMARY KEY, virtual_domain_id int NOT NULL, email varchar(100) NOT NULL UNIQUE, password varchar(250) NOT NULL, maildir varchar(100) NOT NULL UNIQUE, quota varchar(20) DEFAULT '${mail_quota_mb}', created timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (virtual_domain_id) REFERENCES virtual_domains (id) ON DELETE SET NULL ON UPDATE CASCADE);"
$virtusers_unless     = "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'virtual_users'"
$virtalias_table_cmd  = "CREATE TABLE virtual_aliases(id SERIAL PRIMARY KEY, virtual_domain_id int NOT NULL, source varchar(100) NOT NULL, destination varchar(100) NOT NULL, FOREIGN KEY (virtual_domain_id) REFERENCES virtual_domains (id) ON DELETE SET NULL ON UPDATE CASCADE)"
$virtalias_unless     = "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'virtual_aliases'"
$insert_domain_cmd    = "INSERT INTO virtual_domains (virtual_domain, host, active) VALUES ('${facts['my_domain']}', '${facts['fqdn']}', 'true')"
$insert_domain_unless = "SELECT 1 FROM virtual_domains WHERE virtual_domain = '${facts['my_domain']}'"
$insert_admin_cmd     = "INSERT INTO virtual_users (id,virtual_domain_id,password,email,maildir) VALUES ('1', '1', '${admin_password}', '${admin_email}', '${facts['admin_user']}/');"
$insert_admin_unless  = "SELECT 1 FROM virtual_users WHERE email = '${admin_email}'"
$insert_adminban_cmd  = "INSERT INTO virtual_aliases (virtual_domain_id,source,destination) VALUES ('1', 'fail2ban@${facts['my_domain']}', '${admin_email}');"
$insert_adminban_unless = "SELECT 1 FROM virtual_aliases where source = 'fail2ban@${facts['my_domain']}'"
$insert_pm_cmd       = "INSERT INTO virtual_aliases (virtual_domain_id,source,destination) VALUES ('1', 'postmaster@${facts['my_domain']}', '${admin_email}');"
$insert_pm_unless    = "SELECT 1 FROM virtual_aliases where source = 'postmaster@${facts['my_domain']}'"
$sec_pm_grant        = "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA 'public' to '${facts['pf_user']}'"

notify{ "Installing postgresql services: using ${facts['my_domain']} as primary domain": }

class { 'postgresql::server':
  ip_mask_deny_postgres_user => '0.0.0.0/32',
  postgres_password          => $facts['postgres_password'],
  listen_addresses           => '127.0.0.1',
}

if $facts['mail_enable'] == 'true' {
  ### Make postfix DB
  postgresql::server::db { $facts['postfix_db']:
    user     => $facts['pf_user'],
    password => postgresql::postgresql_password($facts['pf_user'], $facts['pf_password'])
  }
  -> postgresql::server::database_grant { 'postfix grant':
    ensure    => 'present',
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['pf_user'],
  }
  -> postgresql::server::extension { 'pgcrypto':
    database => $facts['postfix_db'],
    ensure => 'present'
  }
  # Make dovecot user
  -> postgresql::server::role { $facts['dove_user']:
    password_hash => postgresql::postgresql_password($facts['dove_user'], $facts['dove_password']),
  }
  # Grant dovecot user access to postfix DB
  -> postgresql::server::database_grant { 'dove grant':
    ensure    => 'present',
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['dove_user'],
  }
  -> postgresql_psql {'1 create virt_domain':
    command => $virtdomain_table_cmd,
    unless  => $virtdomain_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql_psql {'2 create table virt_users':
    command => $virtusers_table_cmd,
    unless  => $virtusers_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql_psql {'3 create table virt_alias':
    command => $virtalias_table_cmd,
    unless  => $virtalias_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql_psql {'4 create first domain':
    command => $insert_domain_cmd,
    db      => $facts['postfix_db'],
    unless  => $insert_domain_unless,
  }
  -> postgresql_psql {'5 insert user':
    command => $insert_admin_cmd,
    unless  => $insert_admin_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql_psql {'6 insert user alias':
    command => $insert_adminban_cmd,
    unless  => $insert_adminban_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql_psql {'7 insert user pm alias':
    command => $insert_pm_cmd,
    unless  => $insert_pm_unless,
    db      => $facts['postfix_db'],
  }
  -> postgresql::server::table_grant { 'postfix grant vu':
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['pf_user'],
    table     => 'virtual_users'
  }
  -> postgresql::server::table_grant { 'postfix user grant va':
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['pf_user'],
    table     => 'virtual_aliases'
  }
  -> postgresql::server::table_grant { 'postfix grant vd':
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['pf_user'],
    table     => 'virtual_domains'
  }
  # These can most likely be switched to SELECT only, need to test
  -> postgresql::server::table_grant { 'dovecot user grant vu':
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['dove_user'],
    table     => 'virtual_users'
  }
  -> postgresql::server::table_grant { 'dovecot user grant va':
    privilege => 'ALL',
    db        => $facts['postfix_db'],
    role      => $facts['dove_user'],
    table     => 'virtual_aliases'
  }
  # This could also be split out since this is mostly required for the pfadmin cli utility to work since we share users, postfix service is readonly.
  -> postgresql::server::grant { 'postfix_grant_vd_seq':
    privilege => 'ALL PRIVILEGES',
    object_type => 'ALL SEQUENCES IN SCHEMA',
    object_name => ['public', 'virtual_domains_id_seq'],
    db        => $facts['postfix_db'],
    psql_db   => $facts['postfix_db'],
    ensure    => present,
    role      => $facts['pf_user'],
  }
if $facts['firezone_enabled'] == 'true' {
  postgresql::server::role { "${facts['fz_user']}":
    password_hash    => postgresql::postgresql_password($facts['fz_user'], $facts['fz_password']),
    superuser        => true,
  }
  -> postgresql::server::db { "${facts['fz_db']}":
    user      => $facts['fz_user'],
    password  => $facts['fz_password'],
  }
  -> postgresql::server::pg_hba_rule { 'allow fz full localhost access':
    description => 'Open up PostgreSQL for access from 127.0.0.1 for firezone',
    type        => 'host',
    user        => 'all',
    database    => 'all',
    address     => '127.0.0.1/32',
    auth_method => 'trust',
  }
}
if $facts['headscale_enabled'] == 'true' {
  postgresql::server::role { "${facts['hs_user']}":
    password_hash    => postgresql::postgresql_password($facts['hs_user'], $facts['hs_password']),
    superuser        => true,
  }
  -> postgresql::server::pg_hba_rule { 'allow hs user full md5 access':
    description => 'Open up PostgreSQL for access from 127.0.0.1 for headscale',
    type        => 'host',
    user        => $facts['hs_user'],
    database    => 'all',
    address     => '127.0.0.1/32',
    auth_method => 'md5',
  }
  -> postgresql::server::db { "${facts['hs_db']}":
    user      => $facts['hs_user'],
    password  => $facts['hs_password'],
  }
  -> postgresql::server::pg_hba_rule { 'allow hs full localhost access':
    description => 'Open up PostgreSQL for access from 127.0.0.1 for headscale',
    type        => 'host',
    user        => 'all',
    database    => 'all',
    address     => '127.0.0.1/32',
    auth_method => 'trust',
  }
}
