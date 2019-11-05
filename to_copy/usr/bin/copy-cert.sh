#!/bin/bash -u


INPUT="/tmp/tlsverify"
OUTPUT="/etc/encryptme"


fail() {
    echo "${1-command failed}" >&2
    exit ${2:-1}
}


echo "Copy $peer_cert from: $INPUT to $OUTPUT"

cp "$INPUT/$peer_cert" "$OUTPUT" || fail "Couldn't copy file"


exit 0