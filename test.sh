#!/bin/bash -ux

REG_KEY="${REG_KEY:-}"
API_URL="${API_URL:-}"
SSL_EMAIL="${SSL_EMAIL:-}"
PEP_IMAGE="${PEP_IMAGE:-}"
BRANCH="${BRANCH:-}"
STATS_SERVER="${STATS_SERVER:-}"

REMOTE_USER="${REMOTE_USER:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_HOST_IP="${REMOTE_HOST_IP:-}"


fail() {
    echo "! ${1:-error}" >&1
    exit ${2:-1}
}

usage() {
    cat <<EOI
usage: $0 init|run|reset|clean|build|cycle [remote]

ENV VARS:

    BRANCH
    REG_KEY
    API_URL
    SSL_EMAIL
    PEP_IMAGE
    REMOTE_USER  (optional)
    REMOTE_HOST  (optional)
    REMOTE_HOST_IP  (optional)
EOI
}


[ $# -ge 1 ] || {
    usage
    fail "no command given"
}

cd $(dirname "$0")

action="$1"
where="${2:-local}"
shift
shift

[ -n "$API_URL" ] || fail "env var API_URL not set"
[ -n "$SSL_EMAIL" ] || fail "env var SSL_EMAIL not set"
[ -n "$PEP_IMAGE" ] || fail "env var PEP_IMAGE not set"
[ -n "$BRANCH" ] || fail "env var BRANCH not set"

[ "$where" = 'remote' ] || {
    [ -n "$REMOTE_USER" ] || fail "env var REMOTE_USER not set"
    [ -n "$REMOTE_HOST" ] || fail "env var REMOTE_HOST not set"
    [ -n "$REMOTE_HOST_IP" ] || fail "env var REMOTE_HOST_IP not set"
}



[ $action = "clean" -o $action = "cycle" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh --remote "$REMOTE_USER@$REMOTE_HOST" \
            clean \
            -v -i $PEP_IMAGE "$@" \
            || fail "Failed to perform --remote clean"
    else
        ./go.sh clean \
            -v -i $PEP_IMAGE "$@" \
            || fail "Failed to perform clean"
    fi
}

[ $action = "build" -o $action = "cycle" ] && {
    ./build.sh -e dev -b $BRANCH -p
}

[ $action = "init" -o $action = "cycle" ] && {
    reg_key=${REG_KEY:-}
    while [ -z "$reg_key" ]; do
        read -p "Server registration key: " reg_key
    done
    if [ "$where" = 'remote' ]; then
        ./go.sh \
            --remote $REMOTE_USER@$REMOTE_HOST \
            init \
            --non-interactive \
            -e $SSL_EMAIL \
            --api-url "$API_URL" \
            --pull-image \
            -i $PEP_IMAGE \
            --dns-test-ip "$REMOTE_HOST_IP" \
            --slot-key "$reg_key" \
            --server-name "$BRANCH-testing.$$" \
            -v \
            "$@" || fail "Failed to init VPN"
    else
        ./go.sh \
            init \
            -e $SSL_EMAIL \
            --non-interactive \
            --api-url "$API_URL" \
            -i $PEP_IMAGE \
            --slot-key "$reg_key" \
            --server-name "$BRANCH-testing.$$" \
            -v \
            "$@" || fail "Failed to init VPN"
    fi
}

[ $action = "run" -o $action = "cycle" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh \
            --remote $REMOTE_USER@$REMOTE_HOST \
            run \
            --api-url "$API_URL" \
            --stats \
            --stats-extra \
            --stats-server "$STATS_SERVER" \
            --stats-key "$STATS_KEY" \
            -e $SSL_EMAIL \
            -i $PEP_IMAGE \
            -v \
            "$@" || fail "Failed to run VPN"
    else
        ./go.sh run \
            --api-url "$API_URL" \
            --stats \
            --stats-extra \
            --stats-server "$STATS_SERVER" \
            --stats-key "$STATS_KEY" \
            -e $SSL_EMAIL \
            -i $PEP_IMAGE \
            -v \
            "$@" || fail "Failed to run VPN"
    fi
}

[ $action = "reset" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh \
            --remote $REMOTE_USER@$REMOTE_HOST \
            reset \
            -v -i $PEP_IMAGE "$@"
    else
        ./go.sh reset \
            -v -i $PEP_IMAGE "$@"
    fi
}

echo "PID: $$"
