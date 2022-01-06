#!/bin/bash
### - set variables
# YOU MUST CHANGE THE FOLLOWING:
# - Lets Encrypt Email (le_email)
# - My Domain (my_domain)

export FIRST_RUN=false

if ! [ -e /root/.puppet_domain ]; then
    FIRST_RUN=true
fi

## CHANGE THESE!!!!!!!!! REALLY!
export facter_le_email='your_real_email@for_lets_encrypt.com'           # Lets Encrypt Email, must be real and active!
# Your primary domain of which your fqdn is most likely a part.
export facter_my_domain='example.org'
export facter_wg_client_enabled='false'
export facter_wg_server_enabled='true'
export facter_wg_server_port=51820
# First User - with default settings this works out to adminuser@example.org.
export facter_admin_user='adminuser'

## These are generally ok
export facter_postfix_db='postfix'                 # Database name for postfix
export facter_pf_user='postfix_user'
export facter_pf_password=`mktemp -u XXXXXXXXXXXXXXXXXXXXXX`
export facter_dove_user='dove_user'
export facter_dove_password=`mktemp -u XXXXXXXXXXXXXXXXXXXXXX`

# Firezone settings
export facter_fz_user='firezone'
export facter_fz_password=`mktemp -u XXXXXXXXXXXXXXXXXXXXXX`
#export facter_fz_password='postgres'
export facter_fz_db='firezone'                 # Database name for postfix

### Optional change items

# Set to false if you want to disable the internal DNS
export facter_dns_enable='true'
# Change to true if you want FreeDNS secondaries to mirror your domain
export facter_freedns_secondary='true'

# Add array items here if you have more domains, CSV please on this one

#export facter_my_other_domains='otherdomain1.com, otherdomain.net'
export facter_my_other_domains=''
export facter_update_dns='true'
# Want to add in a custom record? Create a facter export like so with a | separating the records. change example_com to your domain like sub_example_com or myfancydomain_org
export facter_example_com_records='ns3      IN    A       10.1.1.1|www     IN    A    1.1.1.1|@    IN     TXT   "my=asmeo,too=asdasj"'

# Used as root for getting vendored (fixed) puppet modules
export github_project="https://github.com/colonelpanik/"

function import_settings() {
    source <(grep = /root/.puppet_domain) &> /dev/null
    if ! [ -z $my_domain ]; then
        echo -e "\e[34m***\e[39m Previous config found: Using ${my_domain}\n"
        facter_my_domain=$my_domain
        facter_update_dns='false'
        i=false
        echo -e "\e[34m***\e[39m Using existing packages.."
    else
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


}

function install_yum_repos() {
  echo -e "\e[34m***\e[39m Enabling EPEL, ELrepo, and PowerTools official repos..."
  rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org &>> puppet-domain.log
  dnf --quiet --assumeyes install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm &>> puppet-domain.log
  dnf config-manager --set-enabled powertools &>> puppet-domain.log
  echo -e "\e[34m***\e[39m Installing puppet (and pre-installing dovecot for password generation ease...)"
  dnf --quiet --assumeyes install dovecot epel-release puppet &>> puppet-domain.log

}

function install_wg_packages() {
  echo -e "\e[34m***\e[39m Installing wireguard packages..."
  dnf --quiet --assumeyes install wireguard-tools kmod-wireguard &>> puppet-domain.log
  echo -e "\e[34m***\e[39m Loading wireguard kernel modules..."
  modprobe wireguard &>> puppet-domain.log
}

function install_puppet_module() {
    module=$1
    repopath=$2
    echo -e "\e[34m***\e[39m Installing ${module} from ${repopath}"
    if ! [ -e "/etc/puppetlabs/code/modules/${module}" ]; then
        if ! [ -z $repopath ]; then
            cd /tmp && git clone -q ${github_project}/${repopath}-${module} && mv /tmp/${repopath}-${module} /etc/puppetlabs/code/modules/${module}
        else
            puppet module install ${module} --ignore-dependencies &>> puppet-domain.log
        fi
    fi
}

function install_puppet_modules() {
  echo -e "\e[34m***\e[39m Installing Puppet modules.."
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
exec_dir=$(pwd)
i="true"          # install puppet/deps
d="true"          # install DNS
while getopts ":i:p:d:l:u:" o; do
    case "${o}" in
        i) i=${OPTARG} ;;
        p) admin_password=${OPTARG} ;;
        m) export facter_my_domain=${OPTARG} ;;
        l) export facter_le_email=${OPTARG} ;;
        d) export facter_dns_enable=${OPTARG} ;;
        u) u=${OPTARG} ;;
    esac
done


#### First, import settings and install pre-reqs

import_settings

if [ "${u}" == 'true' ]; then
  facter_update_dns=true
elif [ "${u}" == 'false' ]; then
  facter_update_dns=false
fi

if [ "${i}" == 'true' ]; then
    # Install necessary deps
    install_yum_repos
    install_puppet_modules
fi

if [ ${facter_wg_server_enabled} == 'true' ]; then
    echo -e "\e[34m***\e[39m Wireguard server: Set to true..."
    if [ "${i}" == 'true' ]; then
        install_wg_packages
    fi
fi

### We made it here, lets get the admin password and start

if [ $FIRST_RUN == false ]; then
    admin_password='none'
fi
admin_password=${admin_password:-0}
if [ "${admin_password}" == '0' ]; then
    echo -e "Enter the initial password for your user: "
    read -s admin_password
fi
export facter_admin_password=$(doveadm pw -s BLF-CRYPT -p ${admin_password})

### - run puppet

puppet apply ${exec_dir}/prereq.pp &&
puppet apply ${exec_dir}/database.pp &&
puppet apply ${exec_dir}/wireguard.pp &&
puppet apply ${exec_dir}/postfix.pp
if [ $facter_dns_enable == 'true' ]; then
    puppet apply ${exec_dir}/dns.pp
fi

echo -e "Done!\n"

if [ $FIRST_RUN == 'true' ]; then
    if [ $facter_wg_server_enabled == 'true' ]; then
        echo -e "You will need to run 'firezone-ctl create-or-reset-admin' to enable the account for ${facter_admin_user}@${facter_my_domain}. The password will be displayed on your screen and is different than your email password.\n"
    fi
    if [ $facter_dns_enable == 'true' ]; then
        echo -e "You can now use this server as an authoritative domain for:\n${facter_my_domain}\n"
        if ! [ -z $facter_my_other_domains ]; then
            echo -e "You can also use this server as an authoritative domain for:\n${facter_my_other_domains}\n"
        fi
    else
        echo -e "In order for DKIM to work, you'll need to add the following TXT record to your domain:\n\n$(cat /etc/opendkim/keys/${facter_my_domain}/`date +%Y%m%d`.txt)\n"
        echo -e "And an spf record similar to this will work: 'v=spf1 +mx a:${HOSTNAME} -all' though you can replace the hostname with your IP for less DNS lookups."
        echo -e "And DMARC for better spam catches:\n\n 'v=DMARC1;p=quarantine;pct=100;rua=mailto:postmaster@${facter_my_domain}'\n"
        echo -e "You can also enable DNS by changing the variable in this script and re-running it, keeping in mind it may overwrite any manual changes you've made."
    fi
    echo -e "You can add or remove users using the vmailctl script. If you accidentally mess up a config file or set it by hand, just run this script again.\n"
fi
