#!/bin/bash -u

# An OpenVPN tls-verify script
#
# This would obtain certificate's end date of a pending TLS connection.


LOCKFILE="/etc/encryptme/data/.cert_lock"
END_DATE_FILE="/etc/encryptme/data/cert_end_date"

fail() {
    echo "${1-command failed}" >&2
    [ -f "$LOCKFILE" ] && rm $LOCKFILE 
    exit ${2:-1}
}

depth="$1"
subject="$2"

count=0
while [ -f "$LOCKFILE" ]; do
    sleep 1
    ((count++))
    [ $count -gt 5 ] && fail "Could not get a lock"
done
echo "$$" > $LOCKFILE

# Only use the end-entity certificate in the chain, discarding CA
# certificates
[ "$depth" -eq 0 ] && {

    end_date=$(openssl x509 -noout -in "$peer_cert" -enddate | cut -d "=" -f 2)
    common_name=$(echo $subject | grep -o 'CN=[a-z_0-9]*' | cut -d "=" -f 2)
    email=$(echo $subject | grep -o 'emailAddress=.*,' | cut -d "=" -f 2 | head -c -2)
    serial=$(openssl x509 -noout -in "$peer_cert" -serial | cut -d "=" -f 2)

    # Prune old records with the same common name
    grep -v $common_name $END_DATE_FILE > tmp
    mv -f tmp $END_DATE_FILE

    echo $common_name,$serial,$email,$end_date >> $END_DATE_FILE
}

rm $LOCKFILE

exit 0