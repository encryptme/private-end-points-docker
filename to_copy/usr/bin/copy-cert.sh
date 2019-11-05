#!/bin/bash -u

echo "HELLO $peer_cert" > /etc/encryptme/hello.txt

INPUT="/tmp"
OUTPUT="/etc/encryptme"


echo "Copy $peer_cert from: $INPUT to $OUTPUT" 


cp "$INPUT/$peer_cert" "$OUTPUT" 


exit 0