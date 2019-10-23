#!/bin/bash -u

LOCKFILE="/etc/encryptme/data/.cert_lock"
SESSION_MAP="/etc/encryptme/data/cert_session_map"


fail() {
    echo "${1-command failed}" >&2
    [ -f "$LOCKFILE" ] && rm $LOCKFILE 
    exit ${2:-1}
}


count=0
while [ -f "$LOCKFILE" ]; do
    sleep 1
    ((count++))
    ## If this took five seconds.. things are wrong
    ##      start over.. maybe we lost something
    [ $count -gt 5 ] && fail "Could not get a lock"
done

echo "$$" > $LOCKFILE
grep -v $common_name $SESSION_MAP > tmp && mv tmp $SESSION_MAP

serial_0=$(echo $tls_serial_hex_0 |tr -d : | tr '[:lower:]' '[:upper:]')
serial_1=$(echo $tls_serial_hex_1 |tr -d : | tr '[:lower:]' '[:upper:]')
serial_2=$(echo $tls_serial_hex_2 |tr -d : | tr '[:lower:]' '[:upper:]')

echo $common_name,$serial_0,$serial_1,$serial_2 >> $SESSION_MAP

rm $LOCKFILE
