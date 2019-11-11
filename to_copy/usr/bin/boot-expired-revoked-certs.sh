#!/bin/bash -u

LOCKFILE="/etc/encryptme/data/.cert_lock"
SESSION_MAP=/etc/encryptme/data/cert_session_map
URL_FILE=/etc/encryptme/pki/crl_urls.txt
CRL_LIST_FILE=/tmp/crl.list


fail() {
    echo "${1-command failed}" >&2
    [ -f $LOCKFILE ] && rm -f $LOCKFILE 
    exit ${2:-1}
}


kill_session() {
    local session="$1"

    echo killing session: $session
    sh /usr/bin/boot-cert.sh $session
    [ $? -gt 0 ] && fail "Could not kill the session"

    ## Remove it from the cert session
    count=0
    while [ -f "$LOCKFILE" ]; do
        sleep 1
        ((count++))
        [ $count -gt 5 ] && fail "Could not get a lock"
    done

    echo "$$" > $LOCKFILE
    grep -v $session $SESSION_MAP > /tmp/tmp_session_map
    mv -f /tmp/tmp_session_map $SESSION_MAP
    rm -f $LOCKFILE
}


terminate_expired_certs() {
    cat $SESSION_MAP | while read line; do
        end_date=$( echo $line | cut -d ',' -f 5 )
        if [ -n "$end_date" ]; then
            now_epoch=$( date +%s )
            end_date_epoch=$( date -d "$end_date" +%s )
            if [[ $now_epoch > $end_date_epoch ]]; then
                session=$( echo $line | cut -d ',' -f 1 )
                kill_session $session
            fi
        fi  
    done
}


terminate_revoked_certs() {
    xargs -n 1 curl -s -o $CRL_LIST_FILE  < $URL_FILE

    openssl crl -inform DER -text -noout -in $CRL_LIST_FILE  \
        | grep "Serial Number" | sed 's/.*Serial Number: //g' \
        | while read -r line ; do

        # If it exists in the session file kill it
        session=$(cat $SESSION_MAP | grep $line | awk '{split($0,a,","); print a[1]}')

        if [ -n "$session" ]; then
            kill_session $session
        fi
    done
}


terminate_expired_certs
terminate_revoked_certs

