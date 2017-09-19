#!/bin/sh

cloak-server --quiet pki \
    --out /etc/encryptme/pki \
    --post-hook "service openvpn restart; ipsec reload"
