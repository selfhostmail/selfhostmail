#!/bin/bash

export FIRST_RUN=false

if ! [ -e /root/.puppet_domain ]; then
    FIRST_RUN=true
fi

source ./vars.sh
source ./functions.sh

### Get opts

usage() { echo -e "Usage:\n\n-i\t [true/false] Install pre-reqs, defaults to true\n-p\t [string] Admin password\n-m\t\t [string] My Domain\n-l\t [string] Lets Encrypt contact email\n-u\t [true/false] Run zone updates on DNS, false after first run\n\n"; exit 1 }

exec_dir=$(pwd)
i="true"          # install puppet/deps
d="true"          # install DNS
while getopts ":i:p:d:l:u::h:" o; do
    case "${o}" in
        h) usage ;;
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

if [ ${facter_wg_server_enabled} == 'true' ] || [ ${facter_wg_client_enabled} == 'true' ]; then
    echo -e "\e[34m***\e[39m Installing wireguard requirements..."
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
