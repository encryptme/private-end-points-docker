#!/bin/sh

cd /home/cloak/pki

/home/cloak/bin/cloak-server --quiet crls \
    --infile crl_urls.txt \
    --out crls \
    --post-hook "cat crls/*.pem > new-crls.pem; mv new-crls.pem crls.pem; sudo /usr/sbin/ipsec rereadcrls; sudo /usr/sbin/ipsec purgecrls"
