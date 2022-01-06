#!/bin/bash

export FIRST_RUN=false
export log_dir='/root/puppet_logs'
mkdir -p ${log_dir}

if ! [ -e /root/.puppet_domain ]; then
    FIRST_RUN=true
fi

if [ -e ${log_dir}/build_log ]; then
    mv ${log_dir}/build_log ${log_dir}/build_log-`date +%Y%m%d-%T`
fi

source ./vars.sh
source ./functions.sh

### Get opts

usage() { echo -e "Usage:\n\n-i [true/false]\tInstall pre-reqs\n-p [string]\tAdmin password\n-m [string]\tMy Domain\n-l [string]\tLets Encrypt contact email\n-u [true/false]\tRun zone updates on DNS, false after first run\n\n"; exit 1; }

exec_dir=$(pwd)
i="true"          # install puppet/deps
d="true"          # install DNS
while getopts ":i:p:m:d:l:u:" o; do
    case "${o}" in
        i) i=${OPTARG} ;;
        p) admin_password=${OPTARG} ;;
        m) export facter_my_domain=${OPTARG} ;;
        l) export facter_le_email=${OPTARG} ;;
        d) export facter_dns_enable=${OPTARG} ;;
        u) u=${OPTARG} ;;
        *) usage ;;
    esac
done


#### First, import settings and install pre-reqs

step_print "Running - please be patient, this can take up to 10 minutes (or more!) on slower systems...."

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
    step_print "Installing wireguard requirements..."
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

step_print "Installing system pre-requisites (nginx/certs/spam/AV).."
puppet apply -l ${log_dir}/build_log ${exec_dir}/prereq.pp
step_print "Installing postgres and setting up schemas and rights.."
puppet apply -l ${log_dir}/build_log ${exec_dir}/database.pp
step_print "Installing wireguard services (if enabled).."
puppet apply -l ${log_dir}/build_log ${exec_dir}/wireguard.pp
step_print "Installing postfix/dovecot services and seeding initial tables.."
puppet apply -l ${log_dir}/build_log ${exec_dir}/postfix.pp
if [ $facter_dns_enable == 'true' ]; then
    step_print "Installing bind9 and setting up keys.."
    puppet apply ${exec_dir}/dns.pp
fi

step_print "Done!\n\n\n"

if [ $FIRST_RUN == 'true' ]; then
    if [ $facter_wg_server_enabled == 'true' ]; then
        msg_print "You will need to run \e[1m'firezone-ctl create-or-reset-admin'\e[0m to enable the account for ${facter_admin_user}@${facter_my_domain}. The password will be displayed on your screen and is different than your email password.\n"
    fi
    if [ $facter_dns_enable == 'true' ]; then
        msg_print "You can now use this server as an authoritative domain for:\n${facter_my_domain}\n"
        if ! [ -z $facter_my_other_domains ]; then
            msg_print "You can also use this server as an authoritative domain for:\n${facter_my_other_domains}\n"
        fi
        msg_print "The following txt files contain the DNSSEC records you'll need to add at your upstream provider: $(ls /root/DS_FOR_REGISTRAR_*) - DNSSEC will not have a full chain of trust until you do."
    else
        msg_print "In order for DKIM to work, you'll need to add the following TXT record to your domain:\n\n$(cat /etc/opendkim/keys/${facter_my_domain}/`date +%Y%m%d`.txt)\n"
        msg_print "And an spf record similar to this will work: 'v=spf1 +mx a:${HOSTNAME} -all' though you can replace the hostname with your IP for less DNS lookups."
        msg_print "And DMARC for better spam catches:\n\n 'v=DMARC1;p=quarantine;pct=100;rua=mailto:postmaster@${facter_my_domain}'\n"
        msg_print "You can also enable DNS by changing the variable in this script and re-running it, keeping in mind it may overwrite any manual changes you've made."
    fi
    msg_print "You can add or remove users using the vmailctl script. If you accidentally mess up a config file or set it by hand, just run this script again.\n"
fi
