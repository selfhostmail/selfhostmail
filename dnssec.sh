#!/bin/bash

this_domain=$1

if ! [ -e /var/named/keys ]; then
    mkdir /var/named/keys
fi

zsk_name=$(dnssec-keygen -K /var/named/keys -r /dev/urandom -a ECDSAP256SHA256 ${this_domain} 2>/dev/null)
ksk_name=$(dnssec-keygen -K /var/named/keys -r /dev/urandom -a ECDSAP256SHA256 -fKSK -n ZONE ${this_domain} 2>/dev/null)

