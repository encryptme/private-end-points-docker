#!/bin/bash

# ** The belly of the beast **
#
# - registers with Encrypt.me and fetches configuration information
# - stores everything in $ENCRYPTME_DIR
# - setups up SSL, VPN daemons, etc
# - configures network: uses 100.64.0.0/10 for client connections:
#   - openvpn udp   = 100.64.0.0   > 100.64.63.255  (/18)
#   - openvpn tcp   = 100.64.64.0  > 100.64.127.255 (/18)
#   - ipsec udp     = 100.64.128.0 > 100.64.191.255 (/18)
#   - wireguard udp = 100.96.0.0   > 100.127.255.255 (/11)


BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

# setting this avoids unnecessary use of surrogates that can break server registration
export LANG=en_US.UTF-8

# main conf opts
ENCRYPTME_DIR="${ENCRYPTME_DIR:-/etc/encryptme}"
ENCRYPTME_API_URL="${ENCRYPTME_API_URL:-}"
ENCRYPTME_CONF="${ENCRYPTME_DIR}/encryptme.conf"
ENCRYPTME_SYSCTL_CONF="/etc/sysctl.d/encryptme.conf"
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
NO_EMAIL=${NO_EMAIL:-0}
ENCRYPTME_TUNE_NETWORK=${ENCRYPTME_TUNE_NETWORK:-}
# misc opts
VERBOSE=${ENCRYPTME_VERBOSE:-0}
DNS_FILTER_PID_FILE="/usr/local/unbound-1.7/etc/unbound/dns-filter.pid"
CERT_SESSION_MAP="${ENCRYPTME_DATA_DIR}/cert_session_map"
WG_IFACE=${WG_IFACE:-wg0}


# helpers
# ----------------------------------------------------------------------------
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

query_a() {
    local host="$1"
    local tries=0
    local dns_resp
    local cnames=0

    # query and follow CNAMEs until we get an A record
    dns_resp=$(dig +short +trace "$host" 2>/dev/null | grep -E '^(A|CNAME) ' | tail -1)
    while echo $dns_resp | grep -q '^CNAME'; do
        dns_resp=$(dig +short +trace "$(echo "$dns_resp" | awk '{print $2}')" 2>/dev/null | grep -E '^(A|CNAME) ' | tail -1)
        let cnames+=1
        [ $cnames -ge 10 ] && fail "More than 10 levels of cname redirection; loop detected?"
    done
    echo "$dns_resp"
}


# VPN protocol setup
# ----------------------------------------------------------------------------
setup_wireguard() {
    local ip_addr="$1"
    local conf="$ENCRYPTME_DATA_DIR/server.json"
    local dirty=0
    local wg_refresh_args=('wg_iface=wg0')
    # generate keys and initial configs
    modprobe wireguard || fail "Failed to load WireGuard kernel module" # ensure kernel model is loaded
    mkdir -p "$ENCRYPTME_DIR/wireguard/keys"
    (
        [ -d /etc/wireguard ] && rmdir /etc/wireguard &>/dev/null
        cd /etc && ln -sf "$ENCRYPTME_DIR/wireguard"
        cd "$ENCRYPTME_DIR/wireguard"
        # ensure our files are not readable by others
        umask 077
        [ -s keys/private -a -s keys/public ] || {
            wg genkey | tee keys/private | wg pubkey | tee keys/public
            dirty=1
        }
        # if we got a new key or we have no config at all... write one
        [ $dirty -eq 1 -o \! -s $WG_IFACE.conf ] && {
            cat > $WG_IFACE.conf <<EOI
[Interface]
PrivateKey = $(<keys/private)
Address = $ip_addr/32
ListenPort = 51820
EOI
        }
        # if we have an interface, remove it first
        ip link show "$WG_IFACE" &>/dev/null && ip link delete "$WG_IFACE"
        wg-quick up "$ENCRYPTME_DIR/wireguard/$WG_IFACE.conf"
    ) || fail "Failed to setup wireguard"
    # register our public key
    encryptme_server update --wireguard-public-key $(<"$ENCRYPTME_DIR/wireguard/keys/public") \
        || fail "Failed to register WireGuard public key"
    # set peer configuration information based on authorized users/devices
    if [ -n "$ENCRYPTME_API_URL" ]; then
        wg_refresh_args+=("base_url=$ENCRYPTME_API_URL")
    fi
    refresh-wireguard.py "${wg_refresh_args[@]}" \
        || fail "Failed to set initial WireGuard peers"
}


# start of the fun!
# ----------------------------------------------------------------------------
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
if [ "$NO_EMAIL" = 0 -a -z "$SSL_EMAIL" -a "$LETSENCRYPT_DISABLED" != 1 ]; then
    fail "SSL_EMAIL must be set if LETSENCRYPT_DISABLED is not set" 4
fi
if [ "$ENCRYPTME_STATS" = 1 -a -z "$ENCRYPTME_STATS_SERVER" ]; then
    fail "ENCRYPTME_STATS=1 but no ENCRYPTME_STATS_SERVER"
fi

cmd mkdir -p "$ENCRYPTME_DATA_DIR" \
    || fail "Failed to create Encrypt.me data dir '$ENCRYPTME_DATA_DIR'" 5

touch $CERT_SESSION_MAP || fail "Failed to create cert_session_map"

# Inside the container creates /etc/sysctl.d/encryptme.conf with sysctl.conf tuning params.
if [ "$ENCRYPTME_TUNE_NETWORK" = 1 ]; then
    touch $ENCRYPTME_SYSCTL_CONF || fail "Failed to create encryptme.conf"
    cat > $ENCRYPTME_SYSCTL_CONF << EOF
net.core.somaxconn=1024
net.core.netdev_max_backlog=250000
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=262144 262144 16777216
net.ipv4.tcp_wmem=262144 262144 16777216
net.ipv4.tcp_max_syn_backlog=1000
net.ipv4.tcp_slow_start_after_idle=0
net.core.optmem_max=16777216
net.netfilter.nf_conntrack_max=1008768
EOF
    # Load sysctl encryptme.conf
    sysctl --load=$ENCRYPTME_SYSCTL_CONF
fi

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

    # creates encryptme.conf
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
encryptme_server info --json
encryptme_server info --json | jq -M '.' | tee "$ENCRYPTME_DATA_DIR/server.json"
if [ ! -s "$ENCRYPTME_DATA_DIR/server.json" ]; then
    fail "Failed to get or parse server 'info' API response" 5
fi

jq -r '.target.ikev2[].fqdn, .target.openvpn[].fqdn' \
    < "$ENCRYPTME_DATA_DIR/server.json" \
    | sort -u > "$ENCRYPTME_DATA_DIR/fqdns"
FQDNS=$(cat "$ENCRYPTME_DATA_DIR/fqdns") || fail "Failed to fetch FQDNS"
FQDN=${FQDNS%% *}


# Test FQDNs match IPs on this system
# TODO: ensure this to be reliable on DO and AWS
# TODO: Note this is only valid for AWS http://169.254.169.254 is at Amazon
DNSOK=1
DNS=0.0.0.0
if [ ${DNS_CHECK:-0} -ne 0 ]; then
    EXTIP=$(curl --connect-timeout 5 -s http://169.254.169.254/latest/meta-data/public-ipv4)
    for hostname in $FQDNS; do
        rem "Checking DNS for FQDN '$hostname'"
        DNS=`dig +short A $hostname | egrep '^[0-9]+\.'`
        if [ ! -z "$DNS" ]; then
            rem "Found IP '$DNS' for $hostname"
            if ip addr show | grep "$DNS" > /dev/null; then
                rem "Looks good: Found IP '$DNS' on local system"
            elif [ "$DNS" == "$EXTIP" ]; then
                rem "Looks good: '$DNS' matches with external IP of `hostname`"
            else
                DNSOK=0
                rem "WARNING: Could not find '$DNS' on the local system.  DNS mismatch?"
            fi
        else
            rem "WARNING: $hostname does not resolve"
            DNSOK=0
        fi
    done
fi

# make sure the domain is resolving to us properly
if [ -n "$DNS_TEST_IP" ]; then
    rem "Verifying $FQDN resolves to $DNS_TEST_IP"
    tries=0
    cnames=0
    fqdn_pointed=0
    # try up to 2 minutes for it to work
    while [ $tries -lt 12 -a $fqdn_pointed -eq 0 ]; do
        dns_resp=$(query_a "$FQDN")
        echo "$dns_resp" | grep "^A $DNS_TEST_IP " && fqdn_pointed=1 || sleep 10
        let tries+=1
    done
    [ $fqdn_pointed -eq 0 ] && fail "The FQDN '$FQDN' is still not pointed correctly"
fi
# and finally capture our public IP address for configs
ip_addr=$(query_a "$FQDN" | awk '{print $2}')


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
        --agree-tos
        certonly
    )
    if [ "$NO_EMAIL" = 1 ]; then
        LE_ARGS=("${LE_ARGS[@]}" --register-unsafely-without-email)
    else
        LE_ARGS=("${LE_ARGS[@]}" --email "$SSL_EMAIL")
    fi
    for fqdn in $FQDNS; do
        LE_ARGS=("${LE_ARGS[@]}" -d $fqdn)

        # look for out-of-date LetsEncrypt configs and remove them so we can get a fresh data
        config_file="/etc/letsencrypt/renewal/$fqdn.conf"
        grep -q "^standalone_supported_challenges" "$config_file" 2>/dev/null &&  {
            rm -f "$config_file"
            rm -rf "/etc/letsencrypt/archive/$fqdn"
            rm -rf "/etc/letsencrypt/live/$fqdn"
        }
    done

    if [ "${LETSENCRYPT_STAGING:-}" = 1 ]; then
        LE_ARGS=("${LE_ARGS[@]}" --staging)
    fi
    LE_ARGS=(
        "${LE_ARGS[@]}"
        --expand
        --standalone
        --preferred-challenges
        http-01
    )

    # temporarily allow in HTTP traffic to perform domain verification; need to insert, not append
    /sbin/iptables -I INPUT -p tcp --dport http -j ACCEPT
    (
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
    )
    success=$?
    /sbin/iptables -D INPUT -p tcp --dport http -j ACCEPT
    [ $success -eq 0 ] || fail "LetsEncrypt certificate management failed"

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
chmod -R 644 /etc/cron.d/*

if [ -x /usr/sbin/crond ]; then
    rundaemon crond
else
    rundaemon cron
fi


# Prevent PKI information from being read by non-privileged users
chmod -R 700 "$ENCRYPTME_DIR/pki/"

# Ensure networking is setup properly
sysctl -w net.ipv4.ip_forward=1

# IPsec needs various modules loaded from host
for mod in ah4 ah6 esp4 esp6 xfrm4_tunnel xfrm6_tunnel xfrm_user \
    ip_tunnel xfrm4_mode_tunnel xfrm6_mode_tunnel \
    pcrypt xfrm_ipcomp deflate; do
        modprobe $mod;
done

# generate IP tables rules
rem "Configuring IPTables, as needed"
/bin/template.py \
    -d "$ENCRYPTME_DATA_DIR/server.json" \
    -s /etc/iptables.eme.rules.j2 \
    -o "$ENCRYPTME_DIR/iptables.eme.rules" \
    -v ipaddress=$DNS

# play nicely with existing rules: if our chain is already present do nothing
/sbin/iptables -L ENCRYPTME &>/dev/null || {
    rem "Configuring the ENCRYPTME chain"
    # merge host rules w/ our own
    /sbin/iptables-save > "$ENCRYPTME_DIR/iptables.host.rules"
    cat "$ENCRYPTME_DIR/iptables.host.rules" "$ENCRYPTME_DIR/iptables.eme.rules" \
        > "$ENCRYPTME_DIR/iptables.rules"
    /sbin/iptables-restore --noflush "$ENCRYPTME_DIR/iptables.rules"
    # prune dupes, except for 'COMMIT' lines
    /sbin/iptables-save | awk '/^COMMIT$/ { delete x; }; !x[$0]++' | /sbin/iptables-restore
}


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
        -x "$ENCRYPTME_DATA_DIR/server.json" \
        -s /etc/openvpn/openvpn.conf.j2 \
        -o /etc/openvpn/server-$n.conf \
        -v logging=$ENCRYPTME_LOGGING
    rem "Started OpenVPN instance #$n"
    mkdir -p /var/run/openvpn
    test -e /var/run/openvpn/server-0.sock || \
        mkfifo /var/run/openvpn/server-0.sock
    # if the params change we MUST update /usr/bin/reload-certficiate.sh
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

# Windows now requires some extra certs due to changes Let's Encrypt is making
# or ipsec connections fail :(
# https://letsencrypt.org/docs/dst-root-ca-x3-expiration-september-2021/
cat > /etc/strongswan/ipsec.d/cacerts/lets-encrypt-r3.crt <<EOI
-----BEGIN CERTIFICATE-----
MIIFFjCCAv6gAwIBAgIRAJErCErPDBinU/bWLiWnX1owDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMjAwOTA0MDAwMDAw
WhcNMjUwOTE1MTYwMDAwWjAyMQswCQYDVQQGEwJVUzEWMBQGA1UEChMNTGV0J3Mg
RW5jcnlwdDELMAkGA1UEAxMCUjMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQC7AhUozPaglNMPEuyNVZLD+ILxmaZ6QoinXSaqtSu5xUyxr45r+XXIo9cP
R5QUVTVXjJ6oojkZ9YI8QqlObvU7wy7bjcCwXPNZOOftz2nwWgsbvsCUJCWH+jdx
sxPnHKzhm+/b5DtFUkWWqcFTzjTIUu61ru2P3mBw4qVUq7ZtDpelQDRrK9O8Zutm
NHz6a4uPVymZ+DAXXbpyb/uBxa3Shlg9F8fnCbvxK/eG3MHacV3URuPMrSXBiLxg
Z3Vms/EY96Jc5lP/Ooi2R6X/ExjqmAl3P51T+c8B5fWmcBcUr2Ok/5mzk53cU6cG
/kiFHaFpriV1uxPMUgP17VGhi9sVAgMBAAGjggEIMIIBBDAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMBMBIGA1UdEwEB/wQIMAYB
Af8CAQAwHQYDVR0OBBYEFBQusxe3WFbLrlAJQOYfr52LFMLGMB8GA1UdIwQYMBaA
FHm0WeZ7tuXkAXOACIjIGlj26ZtuMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcw
AoYWaHR0cDovL3gxLmkubGVuY3Iub3JnLzAnBgNVHR8EIDAeMBygGqAYhhZodHRw
Oi8veDEuYy5sZW5jci5vcmcvMCIGA1UdIAQbMBkwCAYGZ4EMAQIBMA0GCysGAQQB
gt8TAQEBMA0GCSqGSIb3DQEBCwUAA4ICAQCFyk5HPqP3hUSFvNVneLKYY611TR6W
PTNlclQtgaDqw+34IL9fzLdwALduO/ZelN7kIJ+m74uyA+eitRY8kc607TkC53wl
ikfmZW4/RvTZ8M6UK+5UzhK8jCdLuMGYL6KvzXGRSgi3yLgjewQtCPkIVz6D2QQz
CkcheAmCJ8MqyJu5zlzyZMjAvnnAT45tRAxekrsu94sQ4egdRCnbWSDtY7kh+BIm
lJNXoB1lBMEKIq4QDUOXoRgffuDghje1WrG9ML+Hbisq/yFOGwXD9RiX8F6sw6W4
avAuvDszue5L3sz85K+EC4Y/wFVDNvZo4TYXao6Z0f+lQKc0t8DQYzk1OXVu8rp2
yJMC6alLbBfODALZvYH7n7do1AZls4I9d1P4jnkDrQoxB3UqQ9hVl3LEKQ73xF1O
yK5GhDDX8oVfGKF5u+decIsH4YaTw7mP3GFxJSqv3+0lUFJoi5Lc5da149p90Ids
hCExroL1+7mryIkXPeFM5TgO9r0rvZaBFOvV2z0gp35Z0+L4WPlbuEjN/lxPFin+
HlUjr8gRsI3qfJOQFy/9rKIJR0Y/8Omwt/8oTWgy1mdeHmmjk7j1nYsvC9JSQ6Zv
MldlTTKB3zhThV1+XWYp6rjd5JW1zbVWEkLNxE7GJThEUG3szgBVGP7pSWTUTsqX
nLRbwHOoq7hHwg==
-----END CERTIFICATE-----
EOI
cat > /etc/strongswan/ipsec.d/cacerts/dst-root-ca-x3.crt <<EOI
-----BEGIN CERTIFICATE-----
MIIFYDCCBEigAwIBAgIQQAF3ITfU6UK47naqPGQKtzANBgkqhkiG9w0BAQsFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTIxMDEyMDE5MTQwM1oXDTI0MDkzMDE4MTQwM1ow
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQCt6CRz9BQ385ueK1coHIe+3LffOJCMbjzmV6B493XC
ov71am72AE8o295ohmxEk7axY/0UEmu/H9LqMZshftEzPLpI9d1537O4/xLxIZpL
wYqGcWlKZmZsj348cL+tKSIG8+TA5oCu4kuPt5l+lAOf00eXfJlII1PoOK5PCm+D
LtFJV4yAdLbaL9A4jXsDcCEbdfIwPPqPrt3aY6vrFk/CjhFLfs8L6P+1dy70sntK
4EwSJQxwjQMpoOFTJOwT2e4ZvxCzSow/iaNhUd6shweU9GNx7C7ib1uYgeGJXDR5
bHbvO5BieebbpJovJsXQEOEO3tkQjhb7t/eo98flAgeYjzYIlefiN5YNNnWe+w5y
sR2bvAP5SQXYgd0FtCrWQemsAXaVCg/Y39W9Eh81LygXbNKYwagJZHduRze6zqxZ
Xmidf3LWicUGQSk+WT7dJvUkyRGnWqNMQB9GoZm1pzpRboY7nn1ypxIFeFntPlF4
FQsDj43QLwWyPntKHEtzBRL8xurgUBN8Q5N0s8p0544fAQjQMNRbcTa0B7rBMDBc
SLeCO5imfWCKoqMpgsy6vYMEG6KDA0Gh1gXxG8K28Kh8hjtGqEgqiNx2mna/H2ql
PRmP6zjzZN7IKw0KKP/32+IVQtQi0Cdd4Xn+GOdwiK1O5tmLOsbdJ1Fu/7xk9TND
TwIDAQABo4IBRjCCAUIwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYw
SwYIKwYBBQUHAQEEPzA9MDsGCCsGAQUFBzAChi9odHRwOi8vYXBwcy5pZGVudHJ1
c3QuY29tL3Jvb3RzL2RzdHJvb3RjYXgzLnA3YzAfBgNVHSMEGDAWgBTEp7Gkeyxx
+tvhS5B1/8QVYIWJEDBUBgNVHSAETTBLMAgGBmeBDAECATA/BgsrBgEEAYLfEwEB
ATAwMC4GCCsGAQUFBwIBFiJodHRwOi8vY3BzLnJvb3QteDEubGV0c2VuY3J5cHQu
b3JnMDwGA1UdHwQ1MDMwMaAvoC2GK2h0dHA6Ly9jcmwuaWRlbnRydXN0LmNvbS9E
U1RST09UQ0FYM0NSTC5jcmwwHQYDVR0OBBYEFHm0WeZ7tuXkAXOACIjIGlj26Ztu
MA0GCSqGSIb3DQEBCwUAA4IBAQAKcwBslm7/DlLQrt2M51oGrS+o44+/yQoDFVDC
5WxCu2+b9LRPwkSICHXM6webFGJueN7sJ7o5XPWioW5WlHAQU7G75K/QosMrAdSW
9MUgNTP52GE24HGNtLi1qoJFlcDyqSMo59ahy2cI2qBDLKobkx/J3vWraV0T9VuG
WCLKTVXkcGdtwlfFRjlBz4pYg1htmf5X6DYO8A4jqv2Il9DjXA6USbW1FzXSLr9O
he8Y4IWS6wY7bCkjCWDcRQJMEhg76fsO3txE+FiYruq9RUWhiF1myv4Q6W+CyBFC
Dfvp7OOGAN6dEOM4+qR9sdjoSYKEBpsr6GtPAQw4dy753ec5
-----END CERTIFICATE-----
EOI

/usr/sbin/ipsec start


rem "Configuring and starting WireGuard"
if modinfo wireguard &>/dev/null; then
    setup_wireguard "$ip_addr"
else
    rem "Missed WireGuard kernel module"
fi


[ ${INIT_ONLY:-0} = "1" ] && {
    rem "Init complete; run './go.sh run' to start"
    exit 0
}


# preemptively see if we have a new certificate for some reason so we're not
# waiting on a cronjob to figure it out
/usr/bin/update-pki.sh

[ $ENCRYPTME_STATS = 1 -a -n "$ENCRYPTME_STATS_SERVER" ] && {
    rem "Starting statistics gatherer, sending to $ENCRYPTME_STATS_SERVER"
    encryptme-stats --server "$ENCRYPTME_STATS_SERVER" $ENCRYPTME_STATS_ARGS &
}


# the DNS filter must be running before unbound
[ -f "$DNS_FILTER_PID_FILE" ] && rm "$DNS_FILTER_PID_FILE"
rem "Restoring content-type filters and starting filter server"
/usr/bin/pep-filter.sh reload


PYTHONPATH="$PYTHONPATH:/usr/local/unbound-1.7/etc/unbound/usr/lib64/python2.7/site-packages" \
    rundaemon /usr/local/unbound-1.7/sbin/unbound -d \
        -c /usr/local/unbound-1.7/etc/unbound/unbound.conf &


# since we don't have a good single foreground process... we just spin!
rem "Start-up complete"
while true; do
    sleep 300
done
