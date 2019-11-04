#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

cloak-server --config /etc/encryptme/encryptme.conf --quiet pki \
    --out /etc/encryptme/pki \
    --post-hook "service openvpn restart; ipsec reload"
