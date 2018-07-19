#!/bin/bash

BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

# main conf opts
ENCRYPTME_DIR="${ENCRYPTME_DIR:-/etc/encryptme}"
ENCRYPTME_API_URL="${ENCRYPTME_API_URL:-}"
ENCRYPTME_CONF="${ENCRYPTME_DIR}/encryptme.conf"
ENCRYPTME_PKI_DIR="${ENCRYPTME_PKI_DIR:-$ENCRYPTME_DIR/pki}"
ENCRYPTME_DATA_DIR="${ENCRYPTME_DATA_DIR:-$ENCRYPTME_DIR/data}"
# stats opts
ENCRYPTME_STATS="${ENCRYPTME_STATS:-0}"
ENCRYPTME_STATS_SERVER="${ENCRYPTME_STATS_SERVER:-}"
ENCRYPTME_STATS_ARGS="${ENCRYPTME_STATS_ARGS:-}"
# helper run-time opts
DNS_TEST_IP=${DNS_TEST_IP:-}
# ssl opts
LETSENCRYPT_DISABLED=${LETSENCRYPT_DISABLED:-0}
LETSENCRYPT_STAGING=${LETSENCRYPT_STAGING:-0}
SSL_EMAIL=${SSL_EMAIL:-}
# misc opts
VERBOSE=${ENCRYPTME_VERBOSE:-0}

# helpers
fail() {
    echo "${1:-failed}" >&1
    exit ${2:-1}
}

cmd() {
    [ $VERBOSE -gt 0 ] && echo "$   $@" >&2
    "$@"
}

rem() {
    [ $VERBOSE -gt 0 ] && echo "# $@" >&2
    return 0
}

rundaemon () {
    if (( $(ps -ef | grep -v grep | grep $1 | wc -l) == 0 )); then
        rem "starting" "$@"
        "$@"
    fi
}

encryptme_server() {
    local args=(--config $ENCRYPTME_CONF "$@")
    local cont_ver=
    if [ -n "$ENCRYPTME_API_URL" ]; then
        args=(--base_url "$ENCRYPTME_API_URL" "${args[@]}")
    fi
    [ -f '/container-version-id' ] && {
        cont_ver=$(</container-version-id)
    }
    CONTAINER_VERSION="$cont_ver" cmd cloak-server "${args[@]}"
}

# debug mode, if requested
[ $VERBOSE -gt 0 ] && set -x

# sanity checks and basic init
if [ ! -d "$ENCRYPTME_DIR" ]; then
    fail "ENCRYPTME_DIR '$ENCRYPTME_DIR' must exist" 1
elif [ ! -w "$ENCRYPTME_DIR" ]; then
    fail "ENCRYPTME_DIR '$ENCRYPTME_DIR' must be writable" 2
fi
cmd mkdir -p "$ENCRYPTME_PKI_DIR"/crls
if [ ! -d "$ENCRYPTME_PKI_DIR" ]; then
    fail "ENCRYPTME_PKI_DIR '$ENCRYPTME_PKI_DIR' did not exist and count not be created" 3
fi
if [ -z "$SSL_EMAIL" -a "$LETSENCRYPT_DISABLED" != 1 ]; then
    fail "SSL_EMAIL must be set if LETSENCRYPT_DISABLED is not set" 4
fi
if [ "$ENNCRYPTME_STATS" = 1 -a -z "$ENCRYPME_STATS_SERVER" ]; then
    fail "ENCRYPTME_STATS=1 but no ENCRYPME_STATS_SERVER"
fi

cmd mkdir -p "$ENCRYPTME_DATA_DIR" \
    || fail "Failed to create Encrypt.me data dir '$ENCRYPTME_DATA_DIR'" 5

# Run an configured Encrypt.me private end-point server (must have run 'config' first)

set -eo pipefail


case "$1" in
    /*)
        exec "$@"
        ;;
    bash*)
        exec "$@"
        ;;
esac

# register the server
if [ -f "$ENCRYPTME_CONF" ]; then
    rem "Instance is already registered; skipping" >&2
else
    opt_ENCRYPTME_SLOT_KEY=--key
    opt_ENCRYPTME_SERVER_NAME=--name
    args=""
    missing=""
    set ""
    for var in ENCRYPTME_SLOT_KEY \
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
        fail "Not on a TTY and missing env vars: $missing" 3
    fi

    # creates /etc/encryptme.conf
    if encryptme_server register "$@"; then
        rem "Registered"
    else
        fail "Registration failed" 4
    fi
    set -
    shift
fi


# request certificate approval
if [ -f "$ENCRYPTME_PKI_DIR/cloak.pem" ]; then
    rem "Private key is already generated"
else
    rem "Requesting certificate (and waiting for approval)"
    encryptme_server req --key "$ENCRYPTME_PKI_DIR/cloak.pem"
fi


# download PKI certificates
if [ -f "$ENCRYPTME_PKI_DIR/crls.pem" ]; then
    rem "PKI certificates are already downloaded."
else
    rem "Requesting approval for PKI certs"
    encryptme_server pki --force --out "$ENCRYPTME_PKI_DIR" --wait
    rem "Downloading PKI certs"
    encryptme_server crls --infile "$ENCRYPTME_PKI_DIR/crl_urls.txt" \
        --out "$ENCRYPTME_PKI_DIR/crls" \
        --format pem \
        --post-hook "cat '$ENCRYPTME_PKI_DIR'/crls/*.pem > '$ENCRYPTME_PKI_DIR/crls.pem'"
fi


# ensure we have DH params generated
if [ ! -f "$ENCRYPTME_PKI_DIR/dh2048.pem" ]; then
    rem "Generating DH Params"
    if [ ! -f /etc/dh2048.pem ]; then
        openssl dhparam -out "$ENCRYPTME_PKI_DIR/dh2048.pem" 2048
    else
        cp /etc/dh2048.pem "$ENCRYPTME_PKI_DIR/dh2048.pem"
    fi
fi


# Symlink certificates and keys to ipsec.d directory
if [ ! -L "/etc/strongswan/ipsec.d/certs/cloak.pem" ]; then
    ln -s "$ENCRYPTME_PKI_DIR/crls.pem" "/etc/strongswan/ipsec.d/crls/crls.pem"
    ln -s "$ENCRYPTME_PKI_DIR/anchor.pem" "/etc/strongswan/ipsec.d/cacerts/cloak-anchor.pem"
    ln -s "$ENCRYPTME_PKI_DIR/client_ca.pem" "/etc/strongswan/ipsec.d/cacerts/cloak-client-ca.pem"
    ln -s "$ENCRYPTME_PKI_DIR/server.pem" "/etc/strongswan/ipsec.d/certs/cloak.pem"
    ln -s "$ENCRYPTME_PKI_DIR/cloak.pem" "/etc/strongswan/ipsec.d/private/cloak.pem"
fi


# Gather server/config information (e.g. FQDNs, open VPN settings)
rem "Getting server info"
encryptme_server info --json | json_pp | tee "$ENCRYPTME_DATA_DIR/server.json"
if [ ! -s "$ENCRYPTME_DATA_DIR/server.json" ]; then
    fail "Failed to get or parse server 'info' API response" 5
fi

jq -r '.target.ikev2[].fqdn, .target.openvpn[].fqdn' \
    < "$ENCRYPTME_DATA_DIR/server.json" \
    | sort -u > "$ENCRYPTME_DATA_DIR/fqdns"
FQDNS=$(cat "$ENCRYPTME_DATA_DIR/fqdns") || fail "Failed to fetch FQDNS"
FQDN=${FQDNS%% *}

# make sure the domain is resolving to us properly
if [ -n "$DNS_TEST_IP" ]; then
    tries=0
    fqdn_pointed=0
    # try up to minutes for it to work
    while [ $tries -lt 12 -a $fqdn_pointed -eq 0 ]; do
        sleep 10
        dig +short +trace "$FQDN" 2>/dev/null | grep "^A $DNS_TEST_IP " && fqdn_pointed=1
        let tries+=1
    done
    [ $fqdn_pointed -eq 0 ] && fail "The FQDN '$FQDN' is still not pointed correctly"
fi

# Perform letsencrypt if not disabled
# Also runs renewals if a cert exists
LETSENCRYPT=0
if [ "$LETSENCRYPT_DISABLED" = 0 ]; then
    LETSENCRYPT=1
    if [ "$DNSOK" = 0 ]; then
        rem "WARNING: DNS issues found, it is unlikely letsencrypt will succeed."
    fi
    # build up the letsencrypt args
    LE_ARGS=(
        --non-interactive
        --email "$SSL_EMAIL"
        --agree-tos
        certonly
    )
    for fqdn in $FQDNS; do
        LE_ARGS=("${LE_ARGS[@]}" -d $fqdn)
    done
    if [ "${LETSENCRYPT_STAGING:-}" = 1 ]; then
        LE_ARGS=("${LE_ARGS[@]}" --staging)
    fi
    LE_ARGS=(
        "${LE_ARGS[@]}"
        --expand
        --standalone
        --standalone-supported-challenges
        http-01
    )

    # temporarily allow in HTTP traffic to perform domain verification
    /sbin/iptables -A INPUT -p tcp --dport http -j ACCEPT
    if [ ! -f "/etc/letsencrypt/live/$FQDN/fullchain.pem" ]; then
        rem "Getting certificate for $FQDN"
        rem "Letsencrypt arguments: " "$@"
        # we get 5 failures per hostname per hour, so we gotta make it count
        tries=0
        success=0
        while [ $tries -lt 2 -a $success -eq 0 ]; do
            letsencrypt "${LE_ARGS[@]}" && success=1 || {
                let tries+=1
                sleep 60
            }
        done
        [ $success -eq 1 ] \
            || fail "Failed to obtain LetsEncrypt SSL certificate."
    else
        letsencrypt renew
    fi
    /sbin/iptables -D INPUT -p tcp --dport http -j ACCEPT

    cp "/etc/letsencrypt/live/$FQDN/privkey.pem" \
        /etc/strongswan/ipsec.d/private/letsencrypt.pem \
        || fail "Failed to copy privkey.pem to IPSec config dir"
    cp "/etc/letsencrypt/live/$FQDN/fullchain.pem" \
        /etc/strongswan/ipsec.d/certs/letsencrypt.pem \
        || fail "Failed to copy letsencrypt.pem to IPSec config dir"
    cp "/etc/letsencrypt/live/$FQDN/chain.pem" \
        /etc/strongswan/ipsec.d/cacerts/letsencrypt.pem \
        || fail "Failed to copy letsencrypt chain.pem to IPSec config dir"

fi



# Start services
if [ -x /usr/sbin/crond ]; then
    rundaemon crond
else
    rundaemon cron
fi

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


rem "Configuring and launching OpenVPN"
OPENVPN_LOGLEVEL=0
OPENVPN_LOG_OPT=""  # Disabled in template
[ "${ENCRYPTME_LOGGING:-}" = 1 ] && OPENVPN_LOGLEVEL=2 &&
                                    OPENVPN_LOG_OPT="--syslog"

get_openvpn_conf() {
    out=$(cat "$ENCRYPTME_DATA_DIR/server.json" | jq ".target.openvpn[$1]")
    if [ "$out" = null ]; then
        echo ""
    else
        echo "$out"
    fi
}
n=0
conf="$(get_openvpn_conf $n)"
while [ ! -z "$conf" ]; do
    echo "$conf" > "$ENCRYPTME_DATA_DIR/openvpn.$n.json"
    /bin/template.py \
        -d "$ENCRYPTME_DATA_DIR/openvpn.$n.json" \
        -s /etc/openvpn/openvpn.conf.j2 \
        -o /etc/openvpn/server-$n.conf \
        -v logging=$ENCRYPTME_LOGGING
    rem "Started OpenVPN instance #$n"
    mkdir -p /var/run/openvpn
    test -e /var/run/openvpn/server-0.sock || \
        mkfifo /var/run/openvpn/server-0.sock
    rundaemon /usr/sbin/openvpn \
         $OPENVPN_LOG_OPT \
         --status /var/run/openvpn/server-$n.status 10 \
         --cd /etc/openvpn \
         --script-security 2 \
         --config /etc/openvpn/server-$n.conf \
         --writepid /var/run/openvpn/server-$n.pid \
         --management /var/run/openvpn/server-$n.sock unix \
         --verb $OPENVPN_LOGLEVEL \
         &
    n=$[ $n + 1 ]
    conf="$(get_openvpn_conf $n)"
done


STRONGSWAN_LOGLEVEL=-1
[ "${ENCRYPTME_LOGGING:-}" = 1 ] && STRONGSWAN_LOGLEVEL=2

rem "Configuring and starting strongSwan"
/bin/template.py \
    -d "$ENCRYPTME_DATA_DIR/server.json" \
    -s /etc/strongswan/ipsec.conf.j2 \
    -o /etc/strongswan/ipsec.conf \
    -v letsencrypt=$LETSENCRYPT
/bin/template.py \
    -d "$ENCRYPTME_DATA_DIR/server.json" \
    -s /etc/strongswan/ipsec.secrets.j2 \
    -o /etc/strongswan/ipsec.secrets \
    -v letsencrypt=$LETSENCRYPT
/bin/template.py \
    -d "$ENCRYPTME_DATA_DIR/server.json" \
    -s /etc/strongswan/strongswan.conf.j2 \
    -o /etc/strongswan/strongswan.conf \
    -v loglevel=$STRONGSWAN_LOGLEVEL
/usr/sbin/ipsec start


[ ${INIT_ONLY:-0} = "1" ] && {
    rem "Init complete; run './go.sh run' to start"
    exit 0
}

[ $ENCRYPTME_STATS = 1 -a -n "$ENCRYPTME_STATS_SERVER" ] && {
    rem "Starting statistics gatherer, sending to $ENCRYPTME_STATS_SERVER"
    encryptme-stats --server "$ENCRYPTME_STATS_SERVER" $ENCRYPTME_STATS_ARGS &
}

# the DNS filter must be running before unbound
/usr/local/unbound-1.7/sbin/filter_server.py start \
    || fail "Failed to start DNS filter"
rundaemon /usr/local/unbound-1.7/sbin/unbound \
    -c /usr/local/unbound-1.7/etc/unbound/unbound.conf \
    || fail "Failed to start unbound"

rem "Start-up complete"

while true; do
    date
    sleep 300
done

