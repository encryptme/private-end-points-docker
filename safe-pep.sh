#!/bin/bash

#set -x
script_name=$(basename "$0")
usage() {
    cat << EOF
usage: $script_name ACTION ARGS

ACTIONS:

    add    	add IP list to the ipset
    whitelist   whitelist an IP or domain
    clear   	destroy ipset and delete all iptables references

ADD OPTIONS:
    -l		list name
    -f      	file to import

WHITELIST OPTIONS:
    -l          list name
    -w 		IP address or domain to whitelist

CLEAR OPTIONS:
    -l       	list name

EXAMPLES:

    # Add the list 'security' to ipset
    ./$script_name add -l security -f /opt/lists/security
    
    # Remove an IP from list 'security'
    ./$script_name whitelist -l security -w 1.1.1.1

    # Delete the list 'security' completely
    ./$script_name clear -l security

EOF

}

fail() {
    echo "! $1" >&2
    exit 1
}

case "$1" in
    add|whitelist|clear)
        action=$1
        ;;
    *)
        usage
        fail "Invalid action: '$1'"
esac

while [[ $# -gt 1 ]]
do
    arg="$2"
    shift
    case $arg in
       -l)
	  list_name="$2"
          shift
          ;;
       -f)
          list_file="$2"
          shift
          ;;
       -w)
          whitelist_me="$2"
          shift
          ;;
       *) 
          usage
          fail "Invalid options"
          shift
          ;;
    esac
done

unbound_list="/usr/local/unbound-1.7/etc/unbound/blacklists/$list_name.txt"

do_ip () {
    new_list="$1"
    ipset list "$list_name" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | sort -u > work/tmp/$list_name.current.ips
    local ips_to_import=`comm -13 work/tmp/$list_name.current.ips $new_list`

    /sbin/ipset list | grep -q -w "$list_name"
    if [ $? -eq 1 ]; then
       /sbin/ipset -N "$list_name" iphash \
	  || fail "Failed to create ipset $list_name"
    fi
    
    /sbin/iptables-save | grep -q -w "$list_name"
    if [ $? -eq 1 ]; then
       /sbin/iptables -I ENCRYPTME 2 -m set --match-set "$list_name" dst -j DROP \
	  || fail "Failed to insert iptables rule $list_name"
    fi

    for ip in $ips_to_import
    do
       /sbin/ipset -A "$list_name" "$ip"
    done
}

reload_unboud () {
    local unbound_pid=$(docker exec -i encryptme cat /usr/local/unbound-1.7/etc/unbound/unbound.pid)
    docker exec -i encryptme kill -9 "$unbound_pid"
    docker exec -i encryptme /usr/local/unbound-1.7/sbin/unbound -c /usr/local/unbound-1.7/etc/unbound/unbound.conf -d &
}

do_domain () {
    new_list="$1"
    docker exec -i encryptme bash -c "[ -f $unbound_list ]"
    if [ $? -eq 0 ]; then
       docker exec -i encryptme cat "$unbound_list" >> "$new_list"
    fi
    sort -u "$new_list" | docker exec -i encryptme dd of="$unbound_list" \
       || fail "Failed to write $unbound_list"
    reload_unboud \
       || fail "Failed to reload unbound daemon"
}

destroy_list () {
    /sbin/ipset list | grep -q -w "$list_name"
    if [ $? -eq 0 ]; then
       /sbin/iptables-save | grep -q -w "$list_name"
       if [ $? -eq 0 ]; then
          /sbin/iptables -D ENCRYPTME -m set --match-set "$list_name" dst -j DROP
       fi
       /sbin/ipset destroy "$list_name"
    else
       echo "ipset "$list_name" not found"
    fi
   
    docker exec -i encryptme bash -c "[ -f $unbound_list ]"
    if [ $? -eq 0 ]; then
       docker exec -i encryptme rm -f "$unbound_list"
       reload_unboud
    else
       echo "$unbound_list not found"
    fi
}

whitelist_ip () {
    /sbin/ipset list whitelist | grep -q "$whitelist_me"
    if [ $? -eq 1 ]; then
       /sbin/ipset -A whitelist "$whitelist_me" \
	  || fail "Failed to whitelist IP $whitelist_me"
    else
       fail "$whitelist_me exists in whitelist"
    fi
}

whitelist_domain () {
    docker exec -it encryptme grep -q "$whitelist_me" /usr/local/unbound-1.7/etc/unbound/whitelist.txt
    if [ $? -eq 1 ]; then
       docker exec -it encryptme bash -c "echo "$whitelist_me" >> /usr/local/unbound-1.7/etc/unbound/whitelist.txt" \
	  || fail "Failed to whitelist domain $whitelist_me"
       reload_unboud || fail "Failed to reload unbound daemon"
    else
       fail "$whitelist_me exists in whitelist"
    fi
}

#Set whitelist ipset and iptables rule for whitelist
/sbin/ipset list | grep -q whitelist
if [ $? -eq 1 ]; then
   /sbin/ipset -N whitelist iphash \
      || fail "Failed to create ipset whitelist"
fi

/sbin/iptables-save | grep -q whitelist
if [ $? -eq 1 ]; then
   /sbin/iptables -I ENCRYPTME -m set --match-set whitelist dst -j ACCEPT \
      || fail "Failed to insert iptables rule"
fi

do_filter () {
    [ -d work/tmp ] || mkdir -p work/tmp
    local ip_file="$list_name.ips"
    local domain_file="$list_name.domains"
    [ -z "$list_file" ] && {
       usage
       fail "No file set to import"
    }

    if [ ! -f "$list_file" ]; then
       fail "File $list_file not found"
    else
       grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' $list_file \
          | sort -u > work/tmp/"$ip_file"
       grep -v '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' $list_file \
          | sort -u > work/tmp/"$domain_file"
    fi
    do_ip work/tmp/"$ip_file"
    do_domain work/tmp/"$domain_file"
}

check_for_list_name() {
    [ -z "$list_name" ] && {
       usage
       fail "No list name set"
    }
}

[ "$action" = "add" ] && {
    check_for_list_name
    do_filter
}

[ "$action" = "clear" ] && {
    check_for_list_name
    destroy_list
}

[ "$action" = "whitelist" ] && {

    [ -z "$whitelist_me" ] && {
       usage
       fail "No IP address or domain defined to whitelist"
    }
    
    echo "$whitelist_me" | grep -q -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'
    if [ $? -eq 0 ]; then
       whitelist_ip
    else
       whitelist_domain
    fi    
}

/usr/sbin/iptables-save > /etc/iptables.save \
   || fail "Failed to write /etc/iptables.save"
/usr/sbin/ipset save > /etc/ipset.save \
   || fail "Failed to write /etc/ipset.save"

exit 0
