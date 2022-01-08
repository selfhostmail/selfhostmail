#!/bin/bash

function step_print() {
  msg=$1
  echo -e "\e[34m***\e[39m ${msg}"
}

function msg_print() {
  msg=$1
  echo -e "\e[96m*\e[39m ${msg}"
}

function import_settings() {
    source <(grep = /root/.puppet_domain) &> /dev/null
    if ! [ -z $my_domain ]; then
        msg_print "Previous config found: Using ${my_domain}..."
        facter_my_domain=$my_domain
        facter_update_dns='false'
        i=false
        msg_print "Using existing packages.."
    else
        msg_print "No previous config found: Using ${facter_my_domain} as primary domain..."
        echo "my_domain=${facter_my_domain}" >> /root/.puppet_domain
    fi
    if ! [ -z $le_email ]; then
        facter_le_email=$le_email
    else
        echo "le_email=${facter_le_email}" >> /root/.puppet_domain
    fi
    if ! [ -z $admin_user ]; then
        facter_admin_user=$admin_user
    else
        echo "admin_user=${facter_admin_user}" >> /root/.puppet_domain
    fi
    if ! [ -z $postfix_db ]; then
        facter_postfix_db=$postfix_db
    else
        echo "postfix_db=${facter_postfix_db}" >> /root/.puppet_domain
    fi
    if ! [ -z $pf_user ]; then
        facter_pf_user=$pf_user
    else
        echo "pf_user=${facter_pf_user}" >> /root/.puppet_domain
    fi
    if ! [ -z $dove_user ]; then
        facter_dove_user=$dove_user
    else
        echo "dove_user=${facter_dove_user}" >> /root/.puppet_domain
    fi
    if ! [ -z $pf_password ]; then
        facter_pf_password=$pf_password
    else
        echo "pf_password=${facter_pf_password}" >> /root/.puppet_domain
    fi
    if ! [ -z $dove_password ]; then
        facter_dove_password=$dove_password
    else
        echo "dove_password=${facter_dove_password}" >> /root/.puppet_domain
    fi
    if ! [ -z $my_other_domains ]; then
        facter_my_other_domains=$my_other_domains
    else
        if ! [ -z $facter_my_other_domains ]; then
          echo "my_other_domains=${facter_my_other_domains}" >> /root/.puppet_domain
        fi
    fi
    if ! [ -z $fz_password ]; then
        facter_fz_password=$fz_password
    else
        echo "fz_password=${facter_fz_password}" >> /root/.puppet_domain
    fi
    if ! [ -z $fz_user ]; then
        facter_fz_user=$fz_user
    else
        echo "fz_user=${facter_fz_user}" >> /root/.puppet_domain
    fi
    if ! [ -z $hs_user ]; then
        facter_hs_user=$hs_user
    else
        echo "hs_user=${facter_hs_user}" >> /root/.puppet_domain
    fi
    if ! [ -z $hs_password ]; then
        facter_hs_password=$hs_password
    else
        echo "hs_password=${facter_hs_password}" >> /root/.puppet_domain
    fi
    if ! [ -z $hs_db ]; then
        facter_hs_db=$hs_db
    else
        echo "hs_db=${facter_hs_db}" >> /root/.puppet_domain
    fi
}

function dnf_install() {
    install_line=$1
    dnf --quiet --assumeyes install ${install_line}
}

function install_yum_repos() {
  step_print "Enabling repo prereqs..."
  msg_print "Importing ELrepo GPG key..."
  rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org &>> puppet-domain.log
  msg_print "Installling EPEL, ELrepo, and PowerTools official repo..."
  dnf_install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm &>> puppet-domain.log"
  dnf config-manager --set-enabled powertools &>> puppet-domain.log
  msg_print "Installing puppet (and pre-installing dovecot for password generation ease...)"
  dnf_install "dovecot epel-release puppet &>> puppet-domain.log"

}

function install_wg_packages() {
  step_print "Installing wireguard packages..."
  dnf_install "wireguard-tools kmod-wireguard &>> puppet-domain.log"
  msg_print "Loading wireguard kernel modules..."
  modprobe wireguard &>> puppet-domain.log
}

function install_puppet_module() {
    module=$1
    repopath=$2
    IFS=- read $pup_module <<< "$module"
    msg_print "Installing ${module}"
    if ! [ -e "/etc/puppetlabs/code/modules/${module}" ] || ! [ -e "/etc/puppetlabs/code/modules/${pup_module}" ]; then
        if ! [ -z $repopath ]; then
            cd /tmp && git clone -q ${github_project}/${repopath}-${module} && mv /tmp/${repopath}-${module} /etc/puppetlabs/code/modules/${module}
        else
            puppet module install ${module} --ignore-dependencies &>> puppet-domain.log
        fi
    fi
}

function install_puppet_modules() {
  step_print "Installing Puppet modules.."
  install_puppet_module puppetlabs-stdlib
  install_puppet_module puppetlabs-concat
  install_puppet_module thias-sysctl
  install_puppet_module puppet-epel
  install_puppet_module puppetlabs-mailalias_core
  install_puppet_module puppetlabs-inifile
  install_puppet_module puppet-alternatives
  install_puppet_module puppet-extlib
  install_puppet_module oxc-dovecot
  install_puppet_module puppet-archive
  install_puppet_module puppet-letsencrypt
  install_puppet_module puppetlabs-postgresql
  install_puppet_module puppet-fail2ban
  install_puppet_module puppet-selinux
  install_puppet_module puppet-nginx
  install_puppet_module puppet-postfix
  install_puppet_module edestecd-clamav
  install_puppet_module puppet-firewalld
  install_puppet_module LeLutin-spamassassin
  install_puppet_module tykeal-spamass_milter
  ## Install vendored modules until upstream merges PRs
  install_puppet_module bind puppet
  install_puppet_module logwatch puppet
}
