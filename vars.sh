#!/bin/bash

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
export facter_example_com_records="ns3      IN    A       10.1.1.1|www     IN    A    1.1.1.1|@    IN     TXT   \"my='asmeo',too=asdasj, q=1\""

# Used as root for getting forked (fixed) puppet modules - NOT the repo you got the script from! Hopefully the PRs will be merged and I can remove the forked modules.
export github_project="https://github.com/colonelpanik/"

