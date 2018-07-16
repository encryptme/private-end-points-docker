#!/bin/bash -x

BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

FILTERS_DIR="/etc/encryptme/filters"
CIDR_RE="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9])\/(?:(?:3[0-2])|(?:[1-2]\d)|[0-9])|($)]"
TMP_DIR="/tmp/$SCRIPT_NAME.$$" && mkdir -p "$TMP_DIR" \
    || fail "Failed to create tempory directory '$TMP_DIR'"


# JFK NOTES:
# - ensure domains/IPs persist after reboot, container restart, etc
# -

usage() {
    cat << EOF
usage: $SCRIPT_NAME ACTION ARGS

Automated DNS and IPv4 CIDR filtering based on arbitrary lists. Reads STDIN
for a list of domains or IPv4 CIDR ranges.

  - Domains are sync'd in '$FILTERS_DIR' and read by the DNS filter socket server
  - IP sets are created and used in iptables to filter out IPs; writes rules to:
     - /etc/iptables.save
     - /etc/ipset.save

ACTIONS:

    append NAME  Add domains/ips to a block list
    replace NAME Replace all domains/ips in a block list with new ones
    prune NAME   Delete domains/ips from a block list
    reset        Remove all domain and IP filtering

EXAMPLES:

    # Add the list 'security'
    $SCRIPT_NAME add security < /opt/lists/security.txt
    echo 'google.com' | ./$SCRIPT_NAME add security

    # Stop filtering all domains/IPs in 'security' list
    $SCRIPT_NAME delete -l security

    # Reset everything to stop all filtering
    $SCRIPT_NAME reset
EOF

}


cleanup() {
    [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR" &>/dev/null
}


fail() {
    echo "! $1" >&2
    cleanup
    exit 1
}


reload_filter() {
    docker exec -i encryptme /usr/local/unbound-1.7/sbin/filter_server.py restart
}


append_ips() {
    local list_name="$1"
    local tmp_ip_file="$TMP_DIR/$list_name.cidr.old"
    local cidr_file_new="$TMP_DIR/$list_name.cidr"

    # create the ipset list if needed
    /sbin/ipset list | grep -q -w "$list_name" || {
        /sbin/ipset -N "$list_name" hash:net \
            || fail "Failed to create ipset $list_name"
    }

    # create the rule for this list, if needed
    /sbin/iptables-save | grep -Eq -- "--match-set \<$list_name\>" || {
        /sbin/iptables -I ENCRYPTME 2 -m set --match-set "$list_name" dst -j DROP \
            || fail "Failed to insert iptables rule $list_name"
    }

    # add only new IPs to the rule (duplicates are bad!)
    ipset list "$list_name" \
        | grep -Eo "$CIDR_RE" \
        | sort -u > "$tmp_ip_file" \
        || fail "Failed to get IP list for '$list'"
    sort -o "$cidr_file_new" "$cidr_file_new"
    comm -13 "$tmp_domain_old" "$cidr_file_new" | while read -r cidr; do
        /sbin/ipset -A "$list_name" "$cidr"
    done
    # rm "$tmp_ip_file" &>/dev/null
}


append_domains() {
    local list_name="$1"
    local tmp_domain_old="$TMP_DIR/domains.old"
    local domain_file="$FILTERS_DIR/$list_name.blacklist"
    local domain_file_new="$TMP_DIR/$list_name.domains"
    local domain_file_write="$TMP_DIR/$list_name.domains.write"

    docker exec -i encryptme mkdir -p "$FILTERS_DIR" \
        || fail "Failed to create blacklists directory"

    # keep things clean add keep dupes scrubbed out as we update the domain list
    docker exec -i encryptme bash -c "[ -s '$domain_file' ]"
    if [ $? -eq 0 ]; then
       docker exec -i encryptme cat "$domain_file" | sort -u > "$tmp_domain_old"
   else
      touch "$tmp_domain_old"
    fi
    {
        sort -o "$domain_file_new" "$domain_file_new" && \
        comm -13 "$tmp_domain_old" "$domain_file_new" > "$domain_file_write" && \
        cat "$tmp_domain_old" "$domain_file_write" | docker exec -i encryptme dd of="$domain_file"
    } || fail "Failed to write $domain_file"

    reload_filter \
       || fail "Failed to reload dns-filter"
}

replace_ips() {
    local list_name="$1"
    local tmp_ip_file="$TMP_DIR/$list_name.cidr.old"
    local cidr_file_new="$TMP_DIR/$list_name.cidr"

    # create the ipset list if needed
    /sbin/ipset list | grep -q -w "$list_name" || {
        /sbin/ipset -N "$list_name" hash:net \
            || fail "Failed to create ipset $list_name"
    }

    # create the rule for this list, if needed
    /sbin/iptables-save | grep -Eq -- "--match-set \<$list_name\>" || {
        /sbin/iptables -I ENCRYPTME 2 -m set --match-set "$list_name" dst -j DROP \
            || fail "Failed to insert iptables rule $list_name"
    }

    sort -o "$cidr_file_new" "$cidr_file_new"
    while read -r cidr; do
        /sbin/ipset -A "$list_name" "$cidr"
    done < "$cidr_file_new"
    rm "$tmp_ip_file" &>/dev/null
}


replace_domains() {
    local list_name="$1"
    local tmp_domain_old="$TMP_DIR/domains.old"
    local domain_file="$FILTERS_DIR/$list_name.blacklist"
    local domain_file_new="$TMP_DIR/$list_name.domains"

    docker exec -i encryptme mkdir -p "$FILTERS_DIR" \
        || fail "Failed to create blacklists directory"

    # keep things clean add keep dupes scrubbed out as we update the domain list
    docker exec -i encryptme bash -c "[ -s '$domain_file' ]"
    if [ $? -eq 0 ]; then
       docker exec -i encryptme cat "$domain_file" | sort -u > "$tmp_domain_old"
   else
      touch "$tmp_domain_old"
    fi
    {
        sort -o "$domain_file_new" "$domain_file_new" && \
        docker exec -i encryptme dd of="$domain_file" < "$domain_file_new"
    } || fail "Failed to write $domain_file"

    reload_filter \
       || fail "Failed to reload dns-filter"
}


prune_list() {
    local list_name="$1"
    local domain_file="$FILTERS_DIR/$list_name.blacklist"

    # delete the IP table rule and ipset list
    /sbin/ipset list | grep -q "^Name: $list_name$" && {
       /sbin/iptables-save | grep -Eq "--match-set \<$list_name\>" && {
          /sbin/iptables -D ENCRYPTME -m set --match-set "$list_name" dst -j DROP
       |
       /sbin/ipset destroy "$list_name"
    }

    # delete any domain lists
    docker exec encryptme bash -c "[ -f '$domain_file' ]" && {
       docker exec -i encryptme rm -f "$unbound_list"
       reload_filter
    }

    return 0
}

reset_filters() {
    list_name="${1:-}"  # if set, deletes a specific list
    # delete all ipset lists and iptables rules
    /sbin/ipset list | awk '$1 == "Name:" { print $2}' | while read list_name; do
       #if [ "$list" == "whitelist" ]; then
       #   /sbin/iptables -D ENCRYPTME -m set --match-set "$list" dst -j ACCEPT \
       #      || fail "Failed to delete iptables rule for the list $list"
       #   docker exec -i encryptme truncate -s 0 /usr/local/unbound-1.7/etc/unbound/whitelist.txt \
       #      || fail "Failed to delete domain list $list.txt"
       #else
      /sbin/iptables -D ENCRYPTME -m set --match-set "$list" dst -j DROP \
          || fail "Failed to delete iptables rule for the list $list"
       /sbin/ipset destroy "$list" \
          || fail "Failed to delete ipset $list"
    done

    # remove our domain blacklists
    docker exec encryptme rm -rf "$FILTERS_DIR" \
       || fail "Failed to delete domain lists"

    reload_filter
}

# JKF: support this later
#whitelist_ip () {
#    /sbin/ipset list whitelist | grep -q "$whitelist_me"
#    if [ $? -eq 1 ]; then
#       /sbin/ipset -A whitelist "$whitelist_me" \
#          || fail "Failed to whitelist IP $whitelist_me"
#    else
#       fail "$whitelist_me exists in whitelist"
#    fi
#}
#
#whitelist_domain () {
#    docker exec -it encryptme grep -q "$whitelist_me" /usr/local/unbound-1.7/etc/unbound/whitelist.txt
#    if [ $? -eq 1 ]; then
#       docker exec -it encryptme bash -c "echo "$whitelist_me" >> /usr/local/unbound-1.7/etc/unbound/whitelist.txt" \
#          || fail "Failed to whitelist domain $whitelist_me"
#       reload_filter || fail "Failed to reload dns-filter"
#    else
#       fail "$whitelist_me exists in whitelist"
#    fi
#}


# reads stdin to parse IPv4 CIDR ranges and domain names and filter them out
append_list() {
    local list_name="$1"
    local cidr_file="$TMP_DIR/$list_name.cidr"
    local domain_file="$TMP_DIR/$list_name.domains"

    # each line must be a domain name or a IPv4 CIDR range
    exec 3> "$cidr_file"
    exec 4> "$domain_file"
    while read item; do
        if [ "$item" = "${item%%/*}" ]; then
            echo "$item" >&3  # CIDR range
        else
            echo "$item" >&4  # domain
        fi
    done

    [ -s "$cidr_file" ] && add_ips <&3
    [ -s "$domain_file" ] && add_domains <&4
    exec 3>&-
    exec 4>&-
}


# ===========================================================================

[ $# -ge 1 ] || {
    usage
    fail "No action given"
}
case "$1" in
    append|replace|prune|reset)
        action="$1"
        shift
        ;;
    *)
        usage
        fail "Invalid action: '$1'"
esac

# JKF: consider later
#/sbin/ipset list | grep -q whitelist
#if [ $? -eq 1 ]; then
#   /sbin/ipset -N whitelist iphash \
#      || fail "Failed to create ipset whitelist"
#fi
#
#/sbin/iptables-save | grep -q whitelist
#if [ $? -eq 1 ]; then
#   /sbin/iptables -I ENCRYPTME -m set --match-set whitelist dst -j ACCEPT \
#      || fail "Failed to insert iptables rule"
#fi

[ "$action" = "append" ] && {
    [ $# -eq 1 ] || fail "No list name given to append to"
    list_name="$1" && shift
    append_list "$list_name"
}

[ "$action" = "replace" ] && {
    [ $# -eq 1 ] || fail "No list name given to replace"
    list_name="$1" && shift
    append_list "$list_name"
}

[ "$action" = "prune" ] && {
    [ $# -eq 1 ] || fail "No list name given to prune from"
    list_name="$1" && shift
    prune_list "$list_name"
}

[ "$action" = "reset" ] && {
    reset_filters
}

# ensure our IP tables are up-to-date so we can restore them on restart
/usr/sbin/iptables-save > /etc/iptables.save \
   || fail "Failed to write /etc/iptables.save"
/usr/sbin/ipset save > /etc/ipset.save \
   || fail "Failed to write /etc/ipset.save"

cleanup

exit 0
