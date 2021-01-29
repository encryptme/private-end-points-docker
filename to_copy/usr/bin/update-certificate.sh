#!/bin/bash -u

le_dir="/etc/letsencrypt/live"
ipsec_dir="/etc/strongswan/ipsec.d/"

# copy our public CA-issued cert info to the expected spot
# -----------------------------------------------------------------------------
echo "Copying LetsEncrypt certificates to '$ipsec_dir'" >&1
for domain_dir in "$le_dir"/*; do
   [ -f "$domain_dir/privkey.pem" ] || continue
   cp "$domain_dir/privkey.pem" "$ipsec_dir/private/letsencrypt.pem"
   cp "$domain_dir/fullchain.pem" "$ipsec_dir/certs/letsencrypt.pem"
   cp "$domain_dir/chain.pem" "$ipsec_dir/cacerts/letsencrypt.pem"
   break  # we should only ever be handling one domain at a time...
done


# and restart the VPN daemons
# -----------------------------------------------------------------------------
/usr/sbin/ipsec restart

# terminate openvpn process(es)
echo "Reloading Strongswan" >&2
ps xww -o pid,cmd  \
    | grep '/usr/sbin/openvpn' \
    | grep -v grep \
    | while read pid cmd; do
    # kill it off
    kill "$pid"
    while true; do
        ps -p "$pid" &>/dev/null || break
    done
done

# start up all the necessary OpenVPN servers (just 1, we expect)
for ((i=0; ;i++)); do
    # and start it if a config file exists for this number
    conf="/etc/openvpn/server-$i.conf "
    [ -f "$conf" ] || break
    echo "Starting OpenVPN from '$conf'" >&2
    nohup /usr/sbin/openvpn \
         --status /var/run/openvpn/server-$i.status 10 \
         --cd /etc/openvpn \
         --script-security 2 \
         --config "$conf" \
         --writepid /var/run/openvpn/server-$i.pid \
         --management /var/run/openvpn/server-$i.sock unix \
         --verb 0 \
         &>/dev/null </dev/null \
         &
done

exit 0
