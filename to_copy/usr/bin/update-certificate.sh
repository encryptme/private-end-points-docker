#!/bin/bash

le_dir="/etc/letsencrypt/live"
ipsec_dir="/etc/strongswan/ipsec.d/"
for domain_dir in "$le_dir"/*; do
    [ -f "$domain_dir/privkey.pem" ] || continue
   cp "$domain_dir/privkey.pem" "$ipsec_dir/private/letsencrypt.pem"
   cp "$domain_dir/fullchain.pem" "$ipsec_dir/certs/letsencrypt.pem"
   cp "$domain_dir/chain.pem" "$ipsec_dir/cacerts/letsencrypt.pem"
   /usr/sbin/ipsec restart
   break  # we should only ever be handling one domain at a time...
done
