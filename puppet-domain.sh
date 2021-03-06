#!/bin/bash

export FIRST_RUN=false
export log_dir='/root/puppet_logs'
mkdir -p ${log_dir}

iverb='Re-configuring'

if ! [ -e /root/.puppet_domain ]; then
    FIRST_RUN=true
    iverb='Installing'
else
    admin_password='none'
fi
admin_password=${admin_password:-0}

source ./vars.sh
source ./functions.sh

### Get opts

usage() { echo -e "Usage:

-a [true/false]\t\tEnable Mail services (default: false)
-c [true/false]\t\tEnable wireguard client (default: false)
-d [true/false]\t\tEnable Named authoritative DNS (default: false)
-f [true/false]\t\tEnable firezone server (default: false)
-h [true/false]\t\tEnable headscale server (default: false)
-l [string]\t\tLets Encrypt contact email (default: no default)
-m [string]\t\tMy Domain (default: example.com)
-p [string]\t\tAdmin password (no default)
-u [true/false]\t\tRun zone updates on DNS, true first run, false after first run
\n"; exit 1; }

exec_dir=$(pwd)
while getopts ":a:c:f:h:p:m:d:l:u:" o; do
    case "${o}" in
        p) admin_password=${OPTARG} ;;
        m) export facter_my_domain=${OPTARG} ;;
        l) export facter_le_email=${OPTARG} ;;
        d) export facter_dns_enable=${OPTARG} ;;
        a) export facter_mail_enable=${OPTARG} ;;
        f) export facter_firezone_enabled=${OPTARG} ;;
        h) export facter_headzone_enabled=${OPTARG} ;;
        c) export facter_wg_client_enable=${OPTARG} ;;
        u) update_dns=${OPTARG} ;;
        *) usage ;;
    esac
done

if [ "${admin_password}" == '0' ]; then
    echo -e "Enter the initial password for your user: "
    read -s admin_password
fi

if [ -e ${log_dir}/build_log ]; then
    mv ${log_dir}/build_log ${log_dir}/build_log-`date +%Y%m%d-%T`
fi

#### First, import settings and install pre-reqs

step_print "Running - please be patient, this can take up to 10 minutes (or more!) on slower systems...."

step_print "Checking for previous config..."
import_settings

# Install necessary deps
step_print " *** Installing necessary yum and puppet modules"
install_yum_repos
install_puppet_modules


if [ "${update_dns}" == 'true' ]; then
  step_print " *** Explicitly running the DNS zone updates/key generation"
  facter_update_dns=true
elif [ "${update_dns}" == 'false' ]; then
  step_print " *** Explicitly NOT running the DNS zone updates/key generation"
  facter_update_dns=false
fi

if [ ${facter_firezone_enabled} == 'true' ] || [ ${facter_wg_client_enabled} == 'true' ] || [ ${facter_headscale_enabled} == 'true' ]; then
    step_print "${iverb} wireguard requirements..."
    if [ "${install_pre}" == 'true' ]; then
        install_wg_packages
    fi
fi

### We made it here, lets get the admin password and start


export facter_admin_password=$(doveadm pw -s BLF-CRYPT -p ${admin_password})

### - run puppet

step_print "${iverb} system pre-requisites (nginx/certs/spam/AV).."
puppet apply -l ${log_dir}/build_log ${exec_dir}/prereq.pp
step_print "${iverb} postgres and setting up schemas and rights.."
puppet apply -l ${log_dir}/build_log ${exec_dir}/database.pp

if [ $facter_wg_client_enabled == "true" ]; then
    step_print "${iverb} wireguard client service.."
    puppet apply -l ${log_dir}/build_log ${exec_dir}/wg-client.pp
elif [ $facter_firezone_enabled == "true" ]; then
    step_print "${iverb} firezone wireguard services.."
    puppet apply -l ${log_dir}/build_log ${exec_dir}/firezone.pp
elif [ $facter_headscale_enabled == "true" ]; then
    step_print "${iverb} headscale wireguard services.."
    puppet apply -l ${log_dir}/build_log ${exec_dir}/headscale.pp
fi
if [ $facter_mail_enable == 'true' ]; then
    step_print "${iverb} postfix/dovecot services and seeding initial tables.."
    puppet apply -l ${log_dir}/build_log ${exec_dir}/postfix.pp
fi
if [ $facter_dns_enable == 'true' ]; then
    step_print "${iverb} bind9 and setting up keys.."
    if [ $facter_update_dns == 'false' ]; then
        step_print "Skipping, not updating named...."
    else
        puppet apply -l ${log_dir}/build_log ${exec_dir}/dns.pp
    fi
fi

if [ $FIRST_RUN == 'true' ]; then
    if [ $facter_firezone_enabled == 'true' ]; then
        msg_print "You will need to run \e[1m'firezone-ctl create-or-reset-admin'\e[0m to enable the account for ${facter_admin_user}@${facter_my_domain}. The password will be displayed on your screen and is different than your email password."
    fi
    if [ $facter_dns_enable == 'true' ]; then
        msg_print "You can now use this server as an authoritative domain for:\n${facter_my_domain}"
        if ! [ -z $facter_my_other_domains ]; then
            msg_print "You can also use this server as an authoritative domain for:\n${facter_my_other_domains}"
        fi
        if [ $facter_mail_enable == 'true' ]; then
            msg_print "The following txt files contain the DNSSEC records you'll need to add at your upstream provider: $(ls /root/DS_FOR_REGISTRAR_*) - DNSSEC will not have a full chain of trust until you do."
        fi
    else
        if [ $facter_mail_enable == 'true' ]; then
            msg_print "In order for DKIM to work, you'll need to add the following TXT record to your domain:\n\n$(cat /etc/opendkim/keys/${facter_my_domain}/`date +%Y%m%d`.txt)"
            msg_print "And an spf record similar to this will work: 'v=spf1 +mx a:${HOSTNAME} ip4:$(facter networking.ip) -all' though you can replace the hostname with your IP for less DNS lookups."
            msg_print "And DMARC for better spam catches:\n\n 'v=DMARC1;p=quarantine;pct=100;rua=mailto:postmaster@${facter_my_domain}'"
            msg_print "You can also enable DNS by changing the variable to enabled and re-running this script."
        fi
    fi
    if [ $facter_mail_enable == 'true']; then
        msg_print "You can add or remove users using the vmailctl script. If you accidentally mess up a config file or set it by hand, just run this script again.\n"
    fi
fi

step_print "Done!\n\n"