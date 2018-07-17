#!/bin/bash -x

if [ -f /etc/ipset.save ]; then
    /sbin/iptables -F ENCRYPTME
    /usr/sbin/ipset destroy
    /usr/sbin/ipset restore < /etc/ipset.save
fi

if [ -f /etc/iptables.save ]; then
    /sbin/iptables-restore < /etc/iptables.save
fi
