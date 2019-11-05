#!/bin/bash -u


INPUT="/tmp/tlsverify"
OUTPUT="/etc/encryptme"


echo "Copy $peer_cert from: $INPUT to $OUTPUT"


cp "$INPUT/$peer_cert" "$OUTPUT" 


exit 0