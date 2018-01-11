#!/bin/bash -ux

REMOTE_USER=cloak
REMOTE_HOST=vpn.rng.ninja
REMOTE_HOST_IP=138.197.97.36

fail() {
    echo "! ${1:-error}" >&1
    exit ${2:-1}
}

[ $# -ge 1 ] || fail "usage: [REG_KEY=X] $0 init|run|reset|clean|build|cycle [remote]"
cd $(dirname "$0")

action="$1"
where="${2:-local}"
shift
shift

[ $action = "clean" -o $action = "cycle" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh clean \
            --remote $REMOTE_USER@$REMOTE_HOST \
            -v -i encryptme/pep-dev "$@"
    else
        ./go.sh clean \
            -v -i encryptme/pep-dev "$@"
    fi
}

[ $action = "build" -o $action = "cycle" ] && {
    ./build.sh -e dev -b jkf -p
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
            -e jonathon.fillmore@stackpath.com \
            --api-url 'http://home.rng.ninja' \
            --pull-image \
            -i encryptme/pep-dev \
            --dns-test-ip "$REMOTE_HOST_IP" \
            --slot-key "$reg_key" \
            --server-name homebox.$$ \
            -v \
            "$@" || fail "Failed to init VPN"
    else
        ./go.sh \
            init \
            -e jonny.fillmore@stackpath.com \
            --non-interactive \
            --api-url 'http://docker.for.mac.localhost:8000' \
            -i encryptme/pep-dev \
            --slot-key "$reg_key" \
            --server-name homebox.$$ \
            -v \
            "$@" || fail "Failed to init VPN"
    fi
}

[ $action = "run" -o $action = "cycle" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh \
            --remote $REMOTE_USER@$REMOTE_HOST \
            run \
            --api-url 'http://home.rng.ninja' \
            --stats --stats-extra \
            -e jonathon.fillmore@stackpath.com \
            -i encryptme/pep-dev \
            -v \
            "$@" || fail "Failed to run VPN"
    else
        ./go.sh run \
            --api-url 'http://docker.for.mac.localhost:8000' \
            --stats --stats-extra \
            -e jonny.fillmore@stackpath.com \
            -i encryptme/pep-dev \
            -v \
            "$@" || fail "Failed to run VPN"
    fi
}

[ $action = "reset" ] && {
    if [ "$where" = 'remote' ]; then
        ./go.sh \
            --remote $REMOTE_USER@$REMOTE_HOST \
            reset \
            -v -i encryptme/pep-dev "$@"
    else
        ./go.sh reset \
            -v -i encryptme/pep-dev "$@"
    fi
}

echo "PID: $$"
