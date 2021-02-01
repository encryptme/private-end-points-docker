#!/bin/bash -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

cloak() {
    cloak-server --config /etc/encryptme/encryptme.conf "$@"
}


# in case the server issued a new certificate for some reason
cloak --quiet pki \
    --out /etc/encryptme/pki \
    --post-hook /usr/bin/reload-certificate.sh

# additionally, we need to proactively ensure we're renewing what we have
openssl x509 -noout -in /etc/encryptme/pki/server.pem -checkend $((86400*30)) || {
    cloak req --key /etc/encryptme/pki/cloak.pem \
        && /usr/bin/reload-certificate.sh
}
