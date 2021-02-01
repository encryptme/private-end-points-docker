#!/bin/bash -u

# check for stuck certbot process
certbot_pid=$(ps auxww | grep 'certbot renew' | grep -v grep | awk '{print $2}')
[ -n "$certbot_pid" ] && {
    kill -9 $certbot_pid
    sleep 5
}

/sbin/iptables -A INPUT -p tcp --dport http -j ACCEPT
/usr/bin/certbot renew --deploy-hook /bin/reload-certificate.sh -q > /dev/null 2>&1
retval=$?
/sbin/iptables -D INPUT -p tcp --dport http -j ACCEPT

exit $retval
