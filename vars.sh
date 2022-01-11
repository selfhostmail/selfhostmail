#!/bin/bash

## CHANGE THESE!!!!!!!!! REALLY!
# Lets Encrypt Email, must be real and active!
#export facter_le_email='your_real_email@for_lets_encrypt.com'
export facter_le_email=''
# Your primary domain of which your fqdn is most likely a part.
export facter_my_domain='example.org'

# Choose one or none of the three wireguard options. If you choose true more than once, the first true is the one chosen.
export facter_wg_client_enabled='false'
export facter_firezone_enabled='false'
export facter_headscale_enabled='false'

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
export facter_wg_server_port=51820

# Headscale settings
export facter_hs_user='headscale'
export facter_hs_password=`mktemp -u XXXXXXXXXXXXXXXXXXXXXX`
export facter_hs_db='headscale'

### Optional change items

# Set to false if you want to disable the other services
export facter_dns_enable='true'
export facter_mail_enable='true'
# Change to true if you want FreeDNS secondaries to mirror your domain
export facter_freedns_secondary='true'
# Add another secondary if you like, like '1.1.1.1,2.2.2.2,3.3.3.3'
export facter_dns_secondary_list=''
export facter_dns_upstream='1.1.1.1'

# Add array items here if you have more domains, CSV please on this one

#export facter_my_other_domains='otherdomain1.com, otherdomain.net'
export facter_my_other_domains=''
export facter_update_dns='true'
# Want to add in a custom record? Create a facter export like so with a | separating the records. change example_com to your domain like sub_example_com or myfancydomain_org
export facter_example_com_records="ns3      IN    A       10.1.1.1|www     IN    A    1.1.1.1|@    IN     TXT   \"my='asmeo',too=asdasj, q=1\""

# Used as root for getting forked (fixed) puppet modules - NOT the repo you got the script from! Hopefully the PRs will be merged and I can remove the forked modules.
export github_project="https://github.com/colonelpanik/"

# By default all virtual domains in your virtual_domains table will alias to your primary domain, meaining if admin@other.com is received, it will alias it over to admin@primary.com
# Basically any user in your primary domain gets a free user in all virtual domains. Handy for ensuring the hostmaster and abuse aliases work.
export facter_enable_domain_alias='true'