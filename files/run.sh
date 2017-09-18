#!/bin/bash

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


opt_ENCRYPTME_USER=--email
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
mkdir -p "$ENCRYPTME_PKI_DIR"
if [ ! -d "$ENCRYPTME_PKI_DIR" ]; then
    echo "ENCRYPTME_PKI_DIR '$ENCRYPTME_PKI_DIR' did not exist and count not be created" >&2
    exit 3
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
    for var in ENCRYPTME_USER ENCRYPTME_PASSWORD ENCRYPTME_TARGET_ID \
               ENCRYPTME_SERVER_NAME; do
        value="${!var}"
        if [ -z "$value" ]; then
            missing="$missing $var"
        else
            arg_var_name="opt_$var"
            echo "$@"
            set "$@" "${!arg_var_name}" "$value"
            echo "$@"
        fi
    done
    shift
    echo "$@"

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
    set ""
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


rundaemon () {
    echo "starting" "$@"
    "$@"
}

# Start services
# TODO Supervisord?
rundaemon rsyslogd
rundaemon cron
rundaemon unbound

# Ensure networking is setup properly
sysctl -w net.ipv4.ip_forward=1

/bin/template.py -d /tmp/server.json -s /etc/iptables.rules.j2 -o /etc/iptables.rules
# TODO merge rules, don't blow them away.
# /sbin/iptables-restore < /etc/iptables.rules

# TODO Run substitution on /etc/openvpn


echo "Started"

# Sleep forever
while true; do
    date
    sleep 60
done

