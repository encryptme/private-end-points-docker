#!/bin/bash

/sbin/iptables -A INPUT -p tcp --dport http -j ACCEPT
/usr/bin/certbot renew --deploy-hook /bin/update-certificate.sh -q > /dev/null 2>&1
retval=$?
/sbin/iptables -D INPUT -p tcp --dport http -j ACCEPT

exit $retval
