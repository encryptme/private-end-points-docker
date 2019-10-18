#!/bin/bash -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH


fail() {
    echo "${1-command failed}" >&2
    exit ${2:-1}
}

               
for socket in "/var/run/openvpn/*.sock"; do
    OPENVPN_CONNECTION=$(echo status | socat - UNIX-CONNECT:/var/run/openvpn/server-0.sock | grep $1)
    [ -n "$OPENVPN_CONNECTION" ] && break
done

IPSEC_CONNECTION=$(ipsec status | grep "$1" | sed -r 's/.*cloak\[([[:digit:]]+)\].+/\1/g')

if [ -n "$IPSEC_CONNECTION" ]; then
        echo "killing ipsec connection $1"
        ipsec down cloak[$IPSEC_CONNECTION]
fi

if [ -n "$OPENVPN_CONNECTION" ]; then
        echo "Killing openvpn connection $1 ($OPENVPN_CONNECTION)"
        echo "kill '$1'" | socat - UNIX-CONNECT:/var/run/openvpn/server-0.sock
fi