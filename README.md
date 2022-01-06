# Self-host DNS and Mail with Puppet

A scripted, 'puppet apply' approach to building a secure mail and wireguard gateway service on RHEL/CentOS8 compatible distros. Meant to be non-destructive and easy to work with, and customizable, while working WITH your OS instead of against it, keeping selinux and security in mind.

# Contents
* [What does this provide?](#provides-services)
* [Assumptions](#assumptions)
* [Usage](#usage)
* [After installation](#after-installation)
* [Further Information](#further-information)

# Provides services

* Postfix + Dovecot + SASL
  * relay only for domains you've specified
  * dovecot submission/fetch on wireguard interface only (if enabled)
* spamassassin/amavis/postgrey/clamd
* postgres for virtual user/domain storage (localhost only)
* nginx, basic default config for http to allow LetsEncrypt
  * If wireguard-server enabled, with ssl reverse proxy for firezone
* opendkim/opendmarc/spf support
* fail2ban for ssh
* Lets Encrypt using nginx orchestration
* firewalld orchestration for services
  * ssh/imap/smtp/http/https/domain/wireguard allowed in public
  * if wireguard server enabled, imap uses the wireguard interface only
* selinux profiles for postfix/dovecot/spamd customizations
* logwatch for all services sent to admin user
* automatic updates (reboot notification required on login, manual unless you're paying for live patching support then you'll need to enable this manually)
* Optional:
  * wireguard-server (provided by firezone https://github.com/firezone/firezone)
  * wireguard-client (requires a wg0.conf file placed in /root/wg0.conf before running the script but automanages dependencies and service.)
  * bind9 (named) for managing domain entries
  * enabled dnssec for named and allows optional custom entries (sorry, requires you to manually enter DS records with your registrar)


# Assumptions

* This assumes you're running a RHEL8/CentOS8 compatible distro (tested on Rocky and CentOS 8) - though the puppet modules mostly support other distros some choices were made in execs to support only RHEL compatible
  * (PRs welcome to support other distros)
* Your hostname should be an FQDN and should be reachable by FQDN as this is used for provisioning Lets Encrypt certs
* This script will not currently work with private hostnames as Lets Encrypt is used for cert provisioning
* Port 80 should NOT be blocked as this is used by the Lets Encrypt cert provisioning process
* You should already have your domain/cloud provider providing DNS. Do *NOT* point your nameservers at this instance until after you confirm named is started and serving your domain!
* You have checked out this git repoistory to /root, have not renamed it, and are running this as root.

# Usage

If you need customizations to the stack, I recommend forking this project and commiting your changes back to git in your own fork - you can always merge from this upstream into your fork that way.

1. Provision a new host in the cloud that has:
   - At least 4GB RAM - this can be a 1CPU/1GB RAM VPS but you'll need to give it a swapfile.
   - An FQDN that is reachable via FQDN for the domain you'll want to host.
     - e.g. step 1, buy domain, step 2, spin up host, step 3, add A record in domain registrar to make sure host is accessible
2. Edit the vars.sh file and set variables as you want
   - At a minimum you'll need to set the 'facter_my_domain' and 'facter_le_email' variables as the script will not work unless these two are set to match reality.
3. Run the script, *as root*:
```bash
cd /root
dnf install --assumeyes git
git clone https://github.com/colonelpanik/self-host-puppet.git
cd self-host-puppet

# from here, edit at least the le_email and my_domain variable in puppet-domain.sh
bash ./puppet-domain.sh

#or via cli for contactless install
bash ./puppet-domain.sh -l myemail@yahoo.com -d myfancydomain.com -p adminpassword
```

The settings are stored in a /root/.puppet_domain file. Warning, removing this file will 'reset' the script and it will create new passwords for your postgres users!

I use this to host my own mail/domain/wg services so I hope you have a clean installation. Please enter an issue if there is a problem!

Note, this has only been tested and will be support on a 'clean' freshly installed cloud system. I'm sure it works elsewhere assuming you have FQDN naming/records set up as expected and are running on a RHEL compatible distro and haven't fscked your base OS.

# After installation

A convenience script is provided to manage users and virtual domains. See ./pfadmin.sh -h for usage.

## Usage Notes

* If you don't specify a password, the script will prompt you for a password, this is the only prompt you'll receive.
* If there are problems, the puppet logs are kept at /root/puppet_logs, check here for problems first before filing a bug report
* If you kept wireguard server enabled, then after running, you'll want to run 'firezone-ctl create-or-reset-admin' and watch for the new password on the screen.
* You can add new virtual users by running 'vmailctl.sh -c addvuser -u username -d example.com'
* After the first run, a /root/.puppet_domain file is created with the postgres user passwords and settings. As long as this file is there, you can re-pull and reset the git repo and no need to edit the script a second time.
* If you are not self-hosting DNS, the proper DKIM entries are printed for your primary domain. The others can be found at /etc/opendkim/keys/<domain_name>/<date>.txt and can be added as-is to your registrar/DNS service.
* This relay requires reverse DNS for smtp to function, use IMAP submission service for sending emails as named does not currently govern the wireguard reverse IP space.

Currently this setup does NOT add the domains to the virtual_domains table. You can do this manually for any additional domains with 'vmailctl.sh -c addvdomain -d example.com'. Make sure to add the 'abuse' and 'postmaster' aliases.

# Further Information

## Self-hosting DNS

If you choose to go the named self-hosting route, be aware you'll need to setup proper backups and secondaries. Support is baked in for freedns.afraid.org using NOTIFY, otherwise you'll have to add your own secondary (support as a secondary via script TODO)

## wireguard server

Firezone is installed and uses the letsencrypt certs for nginx and tls. The embedded nginx/postgresql from their project is disabled and this uses your systems postgres/nginx that is configured with this puppet module.


## wireguard client

The current support is very basic and generates a new client keypair and adds this to the server. You can use this to generate a 'wg0.conf' file for a secondary server using this config.

## TODO

* Allow script to know about a 'primary' (aka mail1/ns1 server) and create itself as a 'secondary' dns/mx service)
* NFS export/mount support to allow the above to share a maildir
* fail2ban for DNS and http (currently ssh only)
* LDAP/kerberos/freeipa support?
* Make the password fields between the firezone and postfix DB tables be synchronized since they support the same password format! That would be cool. 
* Allow this script to setup a secondary DNS/smtp service with NFS support baked in

## IN PROGRESS

## HELP

* Gmail classifies me as spam!

  * Google is overzealous and subscribes to a few blacklists that target lots of various IP space.
  * Maybe your dkim signatures are invalid, anyway accept it as 'not spam' and get a few other people to do that and use the account and eventually gmail will see it as not spam.

* Certbot keeps failing.

  * This has always been in my experience due to DNS records not resolving as you expect.
  * Or...LetsEncrypt has a limit of 25 requests per domain, per week, where domain is your TLD, *not* subdomains. So if you're doing this over and over (say for dev purposes) be aware of this limit.

* Can I run the script twice?

  * Yes, though currently the sql user passwords are regenerated. Run with a '-i false' to skip installing the puppet modules ahead of time.

* Can I modify the puppet and script?

  * Yes, the idea was to make this a solid baseline, not be the end of the journey towards system configuration.

* Will puppet overwrite my configuration?

  * Its possible, especially with nginx config so you may need to add your configuration to puppet rather than add by hand.

* What sort of size should my host be?

  * I've done this mostly on a 1CPU/1GB RAM VPS, but you'll definitely need a swapfile and it won't be speedy. Recommended 2GB RAM for acceptable speeds and 2CPU if you'll have > 10 users or heavy inbound smtp traffic. 1/1 has been fine for personal use.
  * Most of the RAM is taken by amavis and spamd if that helps you tune your profile at all.
  * Enabling both DNS and wireguard and hosting a lot of users is not recommended...... if you feel like you're up to needing 4GB RAM or > 2CPUs, you probably need to look at load balancing, its cheaper with most cheap VPS providers.

* Why isn't this in docker?

  * It could be for many services but that has its own overhead...and I've found docker images and their configs tend to change more frequently than the OS packages and their config files, which have a pretty decent mechanism for changes. In addition, I'm using mostly main-stream and updated puppet modules which should track with those package level changes.
  * And also..Wireguard..If you want it in docker, and do something, let me know, I'd be interested in how you managed the wireguard configuration updates since that level of complexity would cost more in my time than I wanted to spend.. ;)

* Can I drop this on top of my existing firezone installation?

  * I guess you could but you'd lose your database though in theory it should work. This script disabled the chef-controlled 'local' nginx/postgres in firezone and uses the system nginx/postgres proivded by your OS and puppet so there may also be conflicts.

# BUG REPORTS

I didn't write any of the upstream packages here but am happy to use them and am happy to help you chase bugs in this script and puppet modules. I've forked (with PRs pending) a couple of puppet modules to make this work as I needed and will take bug reports for them here.

# THANKS

Thanks to the https://github.com/firezone/firezone project as I was able to replace my hacky scripted stuff with their slick UI.