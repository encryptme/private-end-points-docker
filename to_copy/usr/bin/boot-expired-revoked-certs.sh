#!/bin/bash -u

LOCKFILE="/etc/encryptme/data/.cert_lock"
SESSION_MAP=/etc/encryptme/data/cert_session_map
URL_FILE=/etc/encryptme/pki/crl_urls.txt
CRL_LIST_FILE=/tmp/crl.list
IPSEC_CERT_INFO=/tmp/ipsec_cert_info
REVOKED_CERTS=/tmp/revoked_certs


fail() {
    echo "${1-command failed}" >&2
    [ -f $LOCKFILE ] && rm -f $LOCKFILE 
    exit ${2:-1}
}


get_revoked_certs() {
    xargs -n 1 curl -s -o $CRL_LIST_FILE  < $URL_FILE

    openssl crl -inform DER -text -noout -in $CRL_LIST_FILE  \
        | grep "Serial Number" | sed 's/.*Serial Number: //g' > $REVOKED_CERTS
}


get_ipsec_cert_info() {
    rm -f $IPSEC_CERT_INFO
    touch $IPSEC_CERT_INFO
    touch $SESSION_MAP
    ipsec listcerts | while read line; do
        output=$(echo "$line" | grep "subject:" | sed 's/.*subject: //g' | tr -d '"' )
        [ -n "$output" ] && {
            record="$output"
        }

        output=$(echo "$line" | grep "not after")
        [ -n "$output" ] && {
            output=$(echo "$line" | grep "expired" )
            [ -n "$output" ] && record="$record;EXPIRED" || record="$record;"
        }

        serial=$(echo "$line" | grep "serial:" | sed 's/.*serial: //g' | tr -d ':' )
        [ -n "$serial" ] && {
            serial="${serial^^}"
            record="$record;$serial"
            grep "$serial" $REVOKED_CERTS && record="$record;REVOKED"
        }

        output=$(echo "$line" | grep "flags:" | sed 's/.*flags: //g')
        if [ "$output" = "clientAuth" ]; then
            echo "$record" >> $IPSEC_CERT_INFO
        fi
    done
}


kill_session() {
    local session="$1"
    local openvpn_type="${2:-0}"

    echo "killing session: $session"
    sh /usr/bin/boot-cert.sh "$session"
    [ $? -gt 0 ] && fail "Could not kill the session"

    if [ "$openvpn_type" -gt 0  ]; then
        ## Remove it from the cert session
        count=0
        while [ -f "$LOCKFILE" ]; do
            sleep 1
            ((count++))
            [ $count -gt 5 ] && fail "Could not get a lock"
        done

        echo "$$" > $LOCKFILE
        grep -v "$session" $SESSION_MAP > /tmp/tmp_session_map
        mv -f /tmp/tmp_session_map $SESSION_MAP
        rm -f $LOCKFILE
    fi
}


terminate_expired_certs() {
    cat $SESSION_MAP | while read line; do
        end_date=$( echo "$line" | cut -d ',' -f 6 )
        if [ -n "$end_date" ]; then
            now_epoch=$( date +%s )
            end_date_epoch=$( date -d "$end_date" +%s )
            if [[ $now_epoch > $end_date_epoch ]]; then
                session=$( echo "$line" | cut -d ',' -f 1 )
                kill_session "$session" 1
            fi
        fi  
    done

    grep "EXPIRED" $IPSEC_CERT_INFO | while read -r line; do
        subject=$(echo "$line" | cut -d ';' -f 1 )
        if [ -n "$subject" ]; then
            valid=$(grep "$subject" $IPSEC_CERT_INFO | grep -v "EXPIRED")
            [ -z "$valid" ] && {
                echo "EXPIRED"
                kill_session "$subject" 
            }
        fi
    done
}


terminate_revoked_certs() {
    cat $REVOKED_CERTS | while read -r line ; do
        # If it exists in the session file kill it
        session=$(cat $SESSION_MAP | grep "$line" | awk '{split($0,a,","); print a[1]}')
        if [ -n "$session" ]; then
            kill_session "$session" 1
        fi
    done

    grep 'REVOKED' $IPSEC_CERT_INFO | while read -r line ; do
        subject=$(echo "$line" | cut -d ';' -f 1 )
        if [ -n "$subject" ]; then
            valid=$(grep "$subject" $IPSEC_CERT_INFO | grep -v "REVOKED")
            [ -z "$valid" ] && {
                echo REVOKED
                kill_session "$subject" 
            }
        fi
    done

}


get_revoked_certs
get_ipsec_cert_info
terminate_expired_certs
terminate_revoked_certs

