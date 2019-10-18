#!/bin/bash -u

LOCKFILE="/etc/encryptme/data/.cert_lock"
SESSION_MAP=/etc/encryptme/data/cert_session_map
URL_FILE=/etc/encryptme/pki/crl_urls.txt
CRL_LIST_FILE=/tmp/crl.list


fail() {
    echo "${1-command failed}" >&2
    [ -f $LOCKFILE ] && rm $LOCKFILE 
    exit ${2:-1}
}


xargs -n 1 curl -s -o $CRL_LIST_FILE  < $URL_FILE

openssl crl -inform DER -text -noout -in $CRL_LIST_FILE  \
    | grep "Serial Number" | sed 's/.*Serial Number: //g' \
    | while read -r line ; do

    # If it exists in the session file kill it
    session=$(cat $SESSION_MAP | grep $line | awk '{split($0,a,","); print a[1]}')
    if [ -n $session ]; then
        echo killing session: $session
        sh /root/boot-cert.sh $session

        ## Remove it from the cert session
        count=0
        while [ -f "$LOCKFILE" ]; do
            sleep 1
            ((count++))
            [ $count -gt 5 ] && fail "Could not get a lock"
        done

        echo "$$" > $LOCKFILE
        # cat $SESSION_MAP | grep -v $session > $SESSION_MAP
        grep -v $session $SESSION_MAP > tmp && mv tmp $SESSION_MAP
        rm $LOCKFILE
    fi
done