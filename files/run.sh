#!/bin/bash

# This script handles node registration and application startup

set -eo pipefail
IFS=$'\n\t'


case "$1" in
    /*)
        exec "$@"
        ;;
    bash*)
        exec "$@"
        ;;
esac


opt_ENCRYPTME_EMAIL=--email
opt_ENCRYPTME_PASSWORD=--password
opt_ENCRYPTME_TARGET_ID=--target
opt_ENCRYPTME_SERVER_NAME=-n

ENCRYPTME_DIR="${ENCRYPTME_DIR:-/etc/encryptme}"
ENCRYPTME_CONF="${ENCRYPTME_DIR}/encyptme.conf"
ENCRYPTME_PKI_DIR="${ENCRYPTME_PKI_DIR:-$ENCRYPTME_DIR/pki}"



if [ ! -d "$ENCRYPTME_DIR" ]; then
    echo "ENCRYPTME_DIR '$ENCRYPTME_DIR' must exist" >&2
    exit 1
elif [ ! -w "$ENCRYPTME_DIR" ]; then
    echo "ENCRYPTME_DIR '$ENCRYPTME_DIR' must be writable" >&2
    exit 2
fi
mkdir -p "$ENCRYPTME_PKI_DIR"/crls
if [ ! -d "$ENCRYPTME_PKI_DIR" ]; then
    echo "ENCRYPTME_PKI_DIR '$ENCRYPTME_PKI_DIR' did not exist and count not be created" >&2
    exit 3
fi

if [ -z "$ENCRYPTME_EMAIL" -a "${DISABLE_LETSENCRYPT:-}" != 1 ]; then
    echo "ENCRYPTME_EMAIL must be set if DISABLE_LETSENCRYPT is not set"
    exit 4
fi

encryptme_server() {
    cloak-server --config $ENCRYPTME_CONF "$@"
}

# Check if we permit doing interactive initialization
if [ ! -f "$ENCRYPTME_CONF" ]; then

    echo "Unregistered instance"

    args=""
    missing=""
    set ""
    for var in ENCRYPTME_EMAIL ENCRYPTME_PASSWORD ENCRYPTME_TARGET_ID \
               ENCRYPTME_SERVER_NAME; do
        value="${!var}"
        if [ -z "$value" ]; then
            missing="$missing $var"
        else
            arg_var_name="opt_$var"
            set - "$@" "${!arg_var_name}" "$value"
        fi
    done
    shift

    if [ ! -t 1 -a ! -z "$missing" ]; then
        echo "Not on a TTY and missing env vars:$missing" >&2
        exit 3
    fi

    # CREATES /etc/cloak.conf
    if encryptme_server register "$@"; then
        echo "Registered"
    else
        echo "Registration failed"
        exit 4
    fi
    set -
    shift
fi

if [ ! -f "${ENCRYPTME_PKI_DIR}/cloak.pem" ]; then
    echo "Requesting certificate (and waiting for approval)"
    encryptme_server req --key "$ENCRYPTME_PKI_DIR/cloak.pem"
    encryptme_server pki --out "$ENCRYPTME_PKI_DIR" --wait
    encryptme_server crls --infile "$ENCRYPTME_PKI_DIR/crl_urls.txt" \
        --out "$ENCRYPTME_PKI_DIR/crls" \
        --format pem --post-hook "cat $ENCRYPTME_PKI_DIR/crls/*.pem > $ENCRYPTME_PKI_DIR/crls.pem"
fi

# Symlink certificates and keys to ipsec.d directory
if [ -f "${ENCRYPTME_PKI_DIR}/cloak.pem" ]; then
    ln -s "$ENCRYPTME_PKI_DIR/crls.pem" "/etc/ipsec.d/crls/crls.pem"
    ln -s "$ENCRYPTME_PKI_DIR/anchor.pem" "/etc/ipsec.d/cacerts/cloak-anchor.pem"
    ln -s "$ENCRYPTME_PKI_DIR/client_ca.pem" "/etc/ipsec.d/cacerts/cloak-client-ca.pem"
    ln -s "$ENCRYPTME_PKI_DIR/server.pem" "/etc/ipsec.d/certs/cloak.pem"
    ln -s "$ENCRYPTME_PKI_DIR/cloak.pem" "/etc/ipsec.d/private/cloak.pem"
fi

if [ ! -f "$ENCRYPTME_PKI_DIR/dh2048.pem" ]; then
    echo "Generating DH Params"
    openssl dhparam -out "$ENCRYPTME_PKI_DIR/dh2048.pem" 2048
fi

echo "Getting server info"
encryptme_server info --json | json_pp | tee /tmp/server.json
if [ ! -s /tmp/server.json ]; then
    echo "Did not get response from API server or received invalid json"
    exit 5
fi

# Gather FQDNs
jq -r '.target.ikev2[].fqdn, .target.openvpn[].fqdn'  < /tmp/server.json | sort -u > /tmp/fqdns

# Test FQDNs match IPs on this system
DNSOK=1
DNS=0.0.0.0
while read hostname; do
    echo "Checking DNS for FQDN '$hostname'"
    DNS=`kdig +short A $hostname | egrep '^[0-9]+\.'`
    if [ ! -z "$DNS" ]; then
        echo "Found IP '$DNS' for $hostname"
        if ip addr show | grep "$DNS" > /dev/null; then
            echo "Looks good: Found IP '$DNS' on local system"
        else
            DNSOK=0
            echo "WARNING: Could not find '$DNS' on the local system.  DNS mismatch?"
        fi
    else
        echo "WARNING: $hostname does not resolve"
        DNSOK=0
    fi
done < <(cat /tmp/fqdns)


# Perform letsencrypt if not disabled
# Also runs renewals if a cert exists
LETSENCRYPT=0
if [ -z "${DISABLE_LETSENCRYPT:-}" -o "${DISABLE_LETSENCRYPT:-}" = "0" ]; then
    LETSENCRYPT=1
    if [ "$DNSOK" = 0 ]; then
        echo "WARNING: DNS issues found, it is unlikely letsencrypt will succeed."
    fi

    primary_fqdn="$(head -1 /tmp/fqdns)"
    set - --non-interactive --email "$ENCRYPTME_EMAIL" --agree-tos certonly
    set - "$@" $(cat /tmp/fqdns | while read fqdn; do printf -- '-d %q' "$fqdn"; done)
    if [ ! -z "$LETSENCRYPT_STAGING" ]; then
        set - "$@" --staging
    fi
    set - "$@" --expand --standalone --standalone-supported-challenges http-01

    # Perform letsencrypt
    /sbin/iptables -A INPUT -p tcp --dport http -j ACCEPT
    if [ ! -f "/etc/letsencrypt/live/$primary_fqdn/fullchain.pem" ]; then
        echo "Getting certificate for $(cat /tmp/fqdns)"
        echo "Letsencrypt arguments: " "$@"
        letsencrypt "$@"
        set -
    else
        letsencrypt renew
    fi
    cp "/etc/letsencrypt/live/$primary_fqdn/privkey.pem" /etc/ipsec.d/private/letsencrypt.pem
    cp "/etc/letsencrypt/live/$primary_fqdn/fullchain.pem" /etc/ipsec.d/certs/letsencrypt.pem
    /sbin/iptables -D INPUT -p tcp --dport http -j ACCEPT
fi

rundaemon () {
    echo "starting" "$@"
    "$@"
}

# Start services
rundaemon cron
rundaemon unbound -d &

# Silence warning
chmod 700 /etc/encryptme/pki/cloak.pem

# Ensure networking is setup properly
sysctl -w net.ipv4.ip_forward=1

# Host needs various modules loaded..
for mod in ah4 ah6 esp4 esp6 xfrm4_tunnel xfrm6_tunnel xfrm_user \
    ip_tunnel xfrm4_mode_tunnel xfrm6_mode_tunnel \
    pcrypt xfrm_ipcomp deflate; do
        modprobe $mod;
done

/bin/template.py -d /tmp/server.json -s /etc/iptables.rules.j2 -o /etc/iptables.rules -v ipaddress=$DNS
# TODO this leaves extra rules around
/sbin/iptables-restore --noflush < /etc/iptables.rules


# Configure and launch OpenVPN
get_openvpn_conf() {
    out=$(cat /tmp/server.json | jq ".target.openvpn[$1]")
    if [ "$out" = null ]; then
        echo ""
    else
        echo "$out"
    fi
}
n=0
conf="$(get_openvpn_conf $n)"
while [ ! -z "$conf" ]; do
    echo "$conf" > /tmp/openvpn.$n.json
    /bin/template.py -d /tmp/openvpn.$n.json -s /etc/openvpn/openvpn.conf.j2 -o /etc/openvpn/server-$n.conf
    echo "Started OpenVPN instance #$n"
    mkdir -p /var/run/openvpn
    rundaemon /usr/sbin/openvpn --status /var/run/openvpn/server-$n.status 10 \
                         --cd /etc/openvpn --script-security 2 --config /etc/openvpn/server-$n.conf \
                         --writepid /var/run/openvpn/server-$n.pid &
    n=$[ $n + 1 ]
    conf="$(get_openvpn_conf $n)"
done


# Configure and launch strongSwan
echo "Starting strongSwan"
/bin/template.py -d /tmp/server.json -s /etc/ipsec.conf.j2 -o /etc/ipsec.conf -v letsencrypt=$LETSENCRYPT
/bin/template.py -d /tmp/server.json -s /etc/ipsec.secrets.j2 -o /etc/ipsec.secrets -v letsencrypt=$LETSENCRYPT
/usr/sbin/ipsec start
#/usr/sbin/ipsec reload
#/usr/sbin/ipsec rereadcacerts
#/usr/sbin/ipsec rereadcrls

echo "Started"

# Sleep forever
while true; do
    date
    sleep 60
done

