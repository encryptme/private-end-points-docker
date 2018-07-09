#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

cd /etc/encryptme/pki

cloak-server --config /etc/encryptme/encryptme.conf --quiet crls \
    --infile crl_urls.txt \
    --out crls \
    --post-hook "cat crls/*.pem > new-crls.pem; mv new-crls.pem crls.pem; /usr/sbin/ipsec rereadcrls; /usr/sbin/ipsec purgecrls"
