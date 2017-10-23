#!/bin/bash

IPSECCONF="/etc/ipsec.conf"
if grep -q $RENEWED_DOMAINS "$IPSECCONF"; then
   /bin/cp /etc/letsencrypt/live/$RENEWED_DOMAINS/fullchain.pem /etc/ipsec.d/certs/letsencrypt.pem
   /bin/cp /etc/letsencrypt/live/$RENEWED_DOMAINS/privkey.pem /etc/ipsec.d/private/letsencrypt.pem
   /usr/sbin/ipsec restart
fi

exit
