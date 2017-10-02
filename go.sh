#!/bin/sh

fail() {
    echo "$@" >&2
    exit 1
}

[ $# -eq 1 ] || fail "Usage: $0 init|run"

action="$1"
image="encryptme"
email=${ENCRYPTME_EMAIL:-}

[ "$action" = "init" -o "$action" = "run" ] \
    || fail "Invalid run-time action: '$action'; 'init' or 'run' expected"

while [ "$email" = "" ]; do
	read -p "Enter your Encrypt.me email address: " email
done

image_id=$(docker images -q "$image")
[ -n "$image_id" ] \
    || fail "No docker image named '$image' found; have you run 'docker build -t encryptme .' yet?"

[ "$action" = "init" ] && {
    docker run -it --rm \
        -e ENCRYPTME_EMAIL="$email" \
        -v "$PWD/runconf:/etc/encryptme" \
        -v "$PWD/runconf/letsencrypt:/etc/letsencrypt" \
        -v /lib/modules:/lib/modules \
        --privileged \
        --net host \
        "$image"
}
[ "$action" = "run" ] && {
    docker run -d --name "$image" \
        -e ENCRYPTME_EMAIL="$email" \
        -v "$PWD/runconf:/etc/encryptme" \
        -v "$PWD/runconf/letsencrypt:/etc/letsencrypt" \
        -v /lib/modules:/lib/modules \
        --privileged \
        --net host \
        --restart always \
        "$image"
}

exit 0
