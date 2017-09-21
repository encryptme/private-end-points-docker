#!/bin/sh

cloak-server --config /etc/encryptme/encyptme.conf --quiet pki \
    --out /etc/encryptme/pki \
    --post-hook "service openvpn restart; ipsec reload"
