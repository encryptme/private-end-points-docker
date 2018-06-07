#!/bin/bash

le_dir="/etc/letsencrypt/live"
ipsec_dir="/etc/strongswan/ipsec.d/"
for domain in "$le_dir"/*; do
    [ -f "$le_dir/privkey.pem" ] || continue
   cp "$le_dir/$domain/privkey.pem" "$ipsec_dir/private/letsencrypt.pem"
   cp "$le_dir/$domain/fullchain.pem" "$ipsec_dir/certs/letsencrypt.pem"
   cp "$le_dir/$domain/chain.pem" "$ipsec_dir/cacerts/letsencrypt.pem"
   break  # we should only ever be handling one domain at a time...
   /usr/sbin/ipsec restart
done
