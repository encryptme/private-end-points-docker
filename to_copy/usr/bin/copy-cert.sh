#!/bin/bash -u


depth="$1"
subject="$2"

[ "$depth" -eq 0 ] && {

    END_DATE_FILE="/etc/encryptme/data/cert_end_date"

    end_date=$(openssl x509 -noout -in "$peer_cert" -enddate | cut -d "=" -f 2)
    common_name=$(echo $subject | grep -o 'CN=[a-z_0-9]*' | cut -d "=" -f 2)

    grep -v $common_name $END_DATE_FILE > tmp
    mv -f tmp $END_DATE_FILE

    echo $common_name,$end_date >> $END_DATE_FILE

}

exit 0