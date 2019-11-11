#!/bin/bash -u


# This script is run by openvpn server when a new client conection 
# has been established, defined by "client-connect"


LOCKFILE="/etc/encryptme/data/.cert_lock"
SESSION_MAP="/etc/encryptme/data/cert_session_map"
END_DATE_FILE="/etc/encryptme/data/cert_end_date"


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

# Prune old records with the same common name
grep -v $common_name $SESSION_MAP > tmp
mv -f tmp $SESSION_MAP

serial_0=$(echo $tls_serial_hex_0 |tr -d : | tr '[:lower:]' '[:upper:]')
serial_1=$(echo $tls_serial_hex_1 |tr -d : | tr '[:lower:]' '[:upper:]')
serial_2=$(echo $tls_serial_hex_2 |tr -d : | tr '[:lower:]' '[:upper:]')

end_date=$(grep $serial_0 $END_DATE_FILE | tail -1 | cut -d "," -f 3)

# Stores client certificate info 
echo $common_name,$serial_0,$serial_1,$serial_2,$end_date >> $SESSION_MAP

grep -v $serial_0 $END_DATE_FILE > tmp
mv -f tmp $END_DATE_FILE


rm $LOCKFILE
