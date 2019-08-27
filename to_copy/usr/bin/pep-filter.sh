#!/bin/bash

BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")

FILTERS_DIR="/etc/encryptme/filters"
DOMAIN_RE="^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}"
CIDR_RE="([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,3})?"
TMP_DIR="/tmp/$SCRIPT_NAME.$$" && mkdir -p "$TMP_DIR" \
    || fail "Failed to create temporary directory '$TMP_DIR'"


# JFK NOTES:
# - ensure domains/IPs persist after reboot, container restart, etc

usage() {
    cat << EOF
usage: $SCRIPT_NAME ACTION ARGS

Automated DNS and IPv4 CIDR filtering based on arbitrary lists. Reads STDIN
for a list of domains or IPv4 CIDR ranges.

  - Domains are sync'd in $FILTERS_DIR and read by the DNS filter socket server
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
    $SCRIPT_NAME append security < /opt/lists/security.txt
    echo 'google.com' | ./$SCRIPT_NAME append security

    # Stop filtering all domains/IPs in 'security' list
    $SCRIPT_NAME prune security

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
    local cmd="/usr/local/unbound-1.7/sbin/filter_server.py"
    "$cmd" stop
    "$cmd" start
}


add_ips() {
    local list_name="$1"
    local new_ip_file="$2"
    local tmp_old_ip_file="$TMP_DIR/$list_name.cidr.old"
    local split_dir="$TMP_DIR/split"

    touch "$tmp_old_ip_file" || fail "Failed to create temp old ip file"

    mkdir -p "$split_dir" \
        || fail "Failed to create temporary directory '$split_dir'"

    /sbin/ipset -n list | grep -E "$list_name\.[0-9]{2}" | while read sublist; do
        ipset list "$sublist" \
            | grep -Eo "$CIDR_RE" >> "$tmp_old_ip_file" \
            || fail "Failed to get IP list for '$sublist'"
        /sbin/iptables-save | grep -Eq -- "--match-set \<$sublist\>" && {            
            /sbin/iptables -D ENCRYPTME -m set --match-set "$sublist" dst -j DROP \
               || fail "Failed to delete iptables rule for the list $sublist"
        }
        /sbin/ipset destroy "$sublist" \
           || fail "Failed to delete ipset $sublist"
    done

    cat "$tmp_old_ip_file" "$new_ip_file" \
        | sort -u \
        | split -d -l 65000 - "$split_dir/$list_name."

    ls "$split_dir" | grep -E "$list_name\.[0-9]{2}" | while read list; do
        ARRAY=()
        ARRAY+=("create $list hash:net family inet hashsize 1024 maxelem 65536")

        while read cidr; do
            ARRAY+=("add $list $cidr")
        done < "$split_dir/$list"

        OLDIFS="$IFS"; IFS=$'\n'
            echo "${ARRAY[*]}" | ipset restore
        IFS="$OLDIFS"

        /sbin/iptables-save | grep -Eq -- "--match-set \<$list\>" || {     
            /usr/sbin/iptables -I ENCRYPTME 2 -m set --match-set "$list" dst -j DROP \
            || fail "Failed to insert iptables rule $list"
        }
    done
}


add_domains() {
    local list_name="$1"
    local new_domain_file="$2"
    local tmp_domain_file="$TMP_DIR/domains.old"
    local domain_file="$FILTERS_DIR/$list_name.blacklist"

    touch "$tmp_domain_file" || fail "Failed to create temp domain file"
    mkdir -p "$FILTERS_DIR" \
        || fail "Failed to create blacklists directory"

    # keep things clean add keep dupes scrubbed out as we update the domain list
    [ -s "$domain_file" ] && \
        cat "$domain_file" | sort -u > "$tmp_domain_file"

    cat "$tmp_domain_file" "$new_domain_file" | sort -u > "$domain_file" \
        || fail "Failed to write $domain_file"
    reload_filter \
       || fail "Failed to reload dns-filter"
}


prune_list() {
    local list_name="$1"
    local domain_file="$FILTERS_DIR/$list_name.blacklist"

    # delete the IP table rule and ipset list
    /sbin/ipset -n list | grep -E "$list_name\.[0-9]{2}" | while read sublist; do
        /sbin/iptables-save | grep -Eq -- "--match-set \<$sublist\>" && {     
            /sbin/iptables -D ENCRYPTME -m set --match-set "$sublist" dst -j DROP \
               || fail "Failed to delete iptables rule for the list $sublist"
        }
        /sbin/ipset destroy "$sublist" \
           || fail "Failed to delete ipset $sublist"
    done

    # delete a domain blacklist file
    [ -f "$domain_file" ] && {
       rm -f "$domain_file"
       reload_filter
    }
    return 0
}


reset_filters() {
    # delete all ipset lists and iptables rules
    /sbin/ipset -n list | while read list_name; do
        /sbin/iptables-save | grep -Eq -- "--match-set \<$list_name\>" && {     
            /sbin/iptables -D ENCRYPTME -m set --match-set "$list_name" dst -j DROP \
               || fail "Failed to delete iptables rule for the list $list_name"
        }
        /sbin/ipset destroy "$list_name" \
           || fail "Failed to delete ipset $list_name"
    done

    # remove our domain blacklists
    rm -rf "$FILTERS_DIR" \
        || fail "Failed to delete domain lists"
    reload_filter
}


# reads stdin to parse IPv4 CIDR ranges and domain names and filter them out
append_list() {
    local list_name="$1"
    local cidr_file="$TMP_DIR/$list_name.cidr"
    local domain_file="$TMP_DIR/$list_name.domains"
    local stdin="$TMP_DIR/$list_name.stdin"

    cat > "$stdin"
    cat "$stdin" | grep -E "$CIDR_RE" > "$cidr_file"
    cat "$stdin" | grep -E "$DOMAIN_RE" > "$domain_file"

    [ -s "$cidr_file" ] &&  add_ips "$list_name" "$cidr_file"
    [ -s "$domain_file" ] &&  add_domains "$list_name" "$domain_file"
}


unbound_health() {
    unbound_process=`pgrep unbound`
    # When `unbound` pid is not found, exit with 1, otherwise 0.
    if [ -z "$unbound_process" ]; then
        exit 1
    fi
    exit 0
}

filter_server_health() {
    filter_server_process=`pgrep filter_server`
    # When `filter_server` pid is not found, exit with 1, otherwise 0.
    if [ -z "$filter_server_process" ]; then
        exit 1
    fi
    exit 0
}


[ $# -ge 1 ] || {
    usage
    fail "No action given"
}
case "$1" in
    append|replace|prune|reset|unbound_health|filter_server_health)
        action="$1"
        shift
        ;;
    *)
        usage
        fail "Invalid action: '$1'"
esac


[ "$action" = "append" ] && {
    [ $# -eq 1 ] || fail "No list name given to append to"
    list_name="$1" && shift
    append_list "$list_name"
}

[ "$action" = "replace" ] && {
    [ $# -eq 1 ] || fail "No list name given to replace"
    list_name="$1" && shift
    prune_list "$list_name"
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

[ "$action" = "unbound_health" ] && {
    unbound_health
}

[ "$action" = "filter_server_health" ] && {
    filter_server_health
}

# Ensure our IP tables are up-to-date so we can restore them on restart.
/usr/sbin/iptables-save > /etc/encryptme/iptables.save \
   || fail "Failed to write /etc/encryptme/iptables.save"
/usr/sbin/ipset save > /etc/encryptme/ipset.save \
   || fail "Failed to write /etc/encryptme/ipset.save"

cleanup

exit 0