#!/bin/bash

# Initialize and run an Encrypt.me private end-point via Docker

# TODO: implement pre-supplied SSL certs (e.g. from Comodo or some other provider)


BASE_DIR=$(cd $(dirname "$0") && pwd -P)
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH="$0"

# dynamic params
[ $UID -eq 0 ] && conf_dir=/etc/encryptme || conf_dir="$BASE_DIR/encryptme_conf"
ssl_email=
server_name=
slot_key=
action=
pull_image=0
auto_update=0
send_stats=0
stats_server=""
stats_args=""
api_url=
dns_check=0
dryrun=0
non_interactive=0
verbose=0
restart=0
tune_network=0
cert_type="letsencrypt"
eme_img="unixeo/split-tunneling"  # TODO: finalize w/ Encryptme hub account
wt_image="v2tec/watchtower"
name="encryptme"
logging=0

# hard-coded
wt_image_name="watchtower"


usage() {
    cat << EOF
usage: $0 [--remote|-r HOST] [ACTION ARGS] ACTION

  Initialize an Encrypt.me private-end point server from a Docker image. Run
  './go.sh init' and then './go.sh run' to set everything up. Any missing
  parameters (registration key and name for init; email only for run) will be
  prompted for if missing.

  If running with --remote it must be used as the first argument.


ACTIONS:

    init    initialize a docker container and register this server
    run     set the private-end point to run
    clean   remove the private end-point container, images, and configs
    reset   stop/remove any current instance and remove configs
    shell   Run the image with a custom entrypoint to start bash


GENERIC OPTIONS:
    -c|--conf-dir DIR     Directory to use/create for private configs/certs
                          (default: $conf_dir)
    -d|--dryrun|--dry-run Run without making changes
    -e|--email            Email email address for LetsEncrypt certs
    -h|--help             Show this message
    -i|--image IMAGE      Docker image to use (default: $eme_img)
    -n|--name NAME        Container name (default: $name)
    -D|--dns-check        Attempt to do AWS/DO DNS validation
    -t|--cert-type TYPE   Certificate type to use e.g. 'letsencypt', 'comodo'
                          (default: $cert_type)
    -v|--verbose          Verbose debugging info
    -l|--logging          Enable some logging, eg IPSEC via /dev/log
    -T|--tune-network    Add 'sysctl.conf' tuning to 'encryptme.conf'

INIT OPTIONS:
    --api-url URL         Use custom URL for Encrypt.me server API
    --non-interactive     Do not attempt to allocate TTYs (e.g. to prompt for
                          missing params)
    --server-name NAME    Fully-qualified domain name for this VPN end-point
    --slot-key ID         Slot/server registration key from the Encrypt.me website.

RUN OPTIONS:
    -R|--restart          Restarts running services if already running

PRIVACY/SECURITY OPTIONS:
    -P|--pull-image       Pull Docker Hub image? (default: off)
    -U|--update           Run WatchTower to keep VPN container up-to-date
                          (default: off)
    -S|--stats            Send generic bandwidth/health stats (default: off)
    --stats-server SERVER Specify an alternate http(s) server to receive stats
    --stats-key    KEY    Optional authorization key for sending stats.
    --stats-extra         Include extra details in stats, such as server_id,
                          target_id, server name (fqdn) and target name
                          (default: off)


EXAMPLES:

    # launch an auto-updating image with health reporting using the official
    # image and ensure our AWS/DO public IP matches our FQDN
    ./go.sh init -S -U -P -D
    
    # run the newly initialized server
    ./go.sh run

EOF
}

fail() {
    echo "! $1" >&2
    exit 1
}

rem() {
    [ "$verbose" -eq 1 ] && echo "+ [$@]" >&2
}

cmd() {
    local retval=0
    if [ $dryrun -eq 1 ]; then
        echo "# $@"
    else
        [ $verbose -eq 1 ] && echo "$   $@" >&2
        "$@"
        retval=$?
    fi
    return $retval
}

collect_args() {
    while [ -z "$ssl_email" ]; do
        read -p "Enter your the email address for your LetsEncrypt certificate: " ssl_email
    done
    [ "$action" = 'init' ] && {
        cat << EOF
---------------------------------------------------------------------
You can obtain server registration keys from the Encrypt.me customer
portal. Once you have created a network, self-hosted target, and
server you will be given a server registration key to use with this
script.
---------------------------------------------------------------------

EOF
        while [ -z "$slot_key" ]; do
            read -p $'\n'"Enter your Encrypt.me server registration key: " slot_key
        done
    }
}

run_remote() {
    local remote_host="$1"
    shift
    scp -q "$SCRIPT_PATH" "$remote_host":go.sh \
        || fail "Couldn't copy script to $remote_host"
    ssh -qt "$remote_host" ./go.sh "$@" \
        || fail "Remote on $remote_host execution failed"
    ssh -q "$remote_host" rm go.sh \
        || fail "Failed to remove go.sh from $remote_host"
}

docker_cleanup() {
    local do_restart=$restart
    if [ "$1" = "-f" ]; then
        shift
        do_restart=1
    fi
    local container="$1"
    local running=$(cmd docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null)
    rem "Container '$container' has running=$running" 
    [ $do_restart -eq 1 -a "$running" = "true" ] &&
        (cmd docker kill "$container" ||
            fail "Failed to kill running container $container")
    [ $do_restart -eq 1 -a ! -z "$running" ] &&
        (cmd docker rm "$container" ||
            fail "Failed to remove container $container")
}

server_init() {
    local init_args=(run --rm)
    [ $non_interactive -eq 0 ] && init_args=("${init_args[@]}" -it)
    [ "$logging" = 1 ] \
        && logging_args="-e ENCRYPTME_LOGGING=1 -v /dev/log:/dev/log" \
        || logging_args=''
    init_args=(
        "${init_args[@]}"
         --name "$name"
        -e SSL_EMAIL="$ssl_email" \
        -e ENCRYPTME_SLOT_KEY="$slot_key" \
        -e ENCRYPTME_API_URL="$api_url" \
        -e ENCRYPTME_SERVER_NAME="$server_name" \
        -e ENCRYPTME_STATS=$send_stats \
        -e ENCRYPTME_STATS_SERVER=$stats_server \
        -e ENCRYPTME_STATS_ARGS="$stats_args" \
        -e ENCRYPTME_VERBOSE=$verbose \
        -e ENCRYPTME_TUNE_NETWORK=$tune_network \
        -e INIT_ONLY=1 \
        -e DNS_TEST_IP="$dns_test_ip" \
        -e DNS_CHECK=$dns_check \
        -v "$conf_dir:/etc/encryptme" \
        -v "$conf_dir/letsencrypt:/etc/letsencrypt" \
        -v /lib/modules:/lib/modules \
        --privileged \
        --net host \
        $logging_args \
        "$eme_img"
    )
    docker_cleanup "$name"
    cmd docker "${init_args[@]}" || fail "Failed to register end-point"

    # TODO: make more dynamic based on OS (e.g. at least check for systemctl before using it)
    if [ -f /etc/apparmor.d/usr.lib.ipsec.charon -o -f /etc/apparmor.d/usr.lib.ipsec.stroke ]; then
        rem Removing /etc/apparmor.d/usr.lib.ipsec.charon
        # TODO we should install a beter charon/stroke apparmor config
        cmd rm -f /etc/apparmor.d/usr.lib.ipsec.charon
        cmd rm -f /etc/apparmor.d/usr.lib.ipsec.stroke
        cmd systemctl reload apparmor
        cmd aa-remove-unknown
    fi
    return 0
}

server_watch() {
    docker_cleanup "$wt_image_name"
    cmd docker run -d \
       --name "$wt_image_name" \
       -v /var/run/docker.sock:/var/run/docker.sock \
        --restart always \
       "$wt_image" --interval 900 --cleanup encryptme watchtower
}

server_shell() {
    cmd docker run \
        -it \
        --entrypoint bash \
        -e ENCRYPTME_API_URL="$api_url" \
        -v "$conf_dir:/etc/encryptme" \
        -v "$conf_dir/letsencrypt:/etc/letsencrypt" \
        -v /lib/modules:/lib/modules \
        -v /proc:/hostfs/proc:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /lib/modules:/lib/modules \
        --privileged \
        --net host \
        "$eme_img"
}

server_run() {
    docker_cleanup "$name"
    logging_args=""
    [ "$logging" = 1 ] && logging_args="-e ENCRYPTME_LOGGING=1 -v /dev/log:/dev/log"
    cmd docker run -d --name "$name" \
        -e SSL_EMAIL="$ssl_email" \
        -e ENCRYPTME_API_URL="$api_url" \
        -e VERBOSE=$verbose \
        -e DNS_CHECK=$dns_check \
        -e ENCRYPTME_STATS=$send_stats \
        -e ENCRYPTME_STATS_SERVER=$stats_server \
        -e ENCRYPTME_STATS_ARGS="$stats_args" \
        -e ENCRYPTME_TUNE_NETWORK=$tune_network \
        -v "$conf_dir:/etc/encryptme" \
        -v "$conf_dir/letsencrypt:/etc/letsencrypt" \
        -v /lib/modules:/lib/modules \
        -v /proc:/hostfs/proc:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --privileged \
        --net host \
        --restart always \
        $logging_args \
        "$eme_img"
}

server_reset() {
    docker_cleanup -f "$name"
    docker_cleanup -f "$wt_image_name"
    cmd rm -rf "$conf_dir"
}

server_cleanup() {
    server_reset
    cmd docker rmi "$eme_img"
    cmd docker rmi "$wt_image"
}


#echo " -- Running $SCRIPT_NAME on $HOSTNAME (PID: $$); dryrun=$dryrun" >&2
#echo " -- ARGS: $@" >&2

# gather up args
arg_count=0
while [ $# -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in 
        --dryrun|dry-run|-d)
            dryrun=1
            ;;
        --conf-dir|-c)
            [ $# -ge 1 ] || fail "Missing arg to --conf-dir|-c"
            conf_dir="$1"
            shift
            ;;
        --help|-h)
            usage
            exit
            ;;
        --image|-i)
            [ $# -ge 1 ] || fail "Missing arg to --image|-i"
            eme_img="$1"
            shift
            ;;
        --email|-e)
            [ $# -ge 1 ] || fail "Missing arg to --email|-e"
            ssl_email="$1"
            shift
            ;;
        --slot-key)
            [ $# -ge 1 ] || fail "Missing arg to --slot-key"
            slot_key="$1"
            shift
            ;;
        --non-interactive)
            non_interactive=1
            ;;
        --server-name)
            [ $# -ge 1 ] || fail "Missing arg to --server_name"
            server_name="$1"
            shift
            ;;
        --cert-type)
            [ $# -ge 1 ] || fail "Missing arg to --cert-type"
            cert_type="$1"
            shift
            [ "$cert_type" = 'comodo' ] \
                && fail "TODO: implement using comodo"
            ;;
        --api-url)
            [ $# -ge 1 ] || fail "Missing arg to --api-url"
            api_url="$1"
            shift
            ;;
        --dns-check|-D)
            dns_check=1
            ;;
        --dns-test-ip)
            [ $# -ge 1 ] || fail "Missing arg to --dns-test-ip"
            dns_test_ip="$1"
            shift
            ;;
        --update|-U)
            auto_update=1
            ;;
        --pull-image|-P)
            pull_image=1
            ;;
        --stats|-S)
            send_stats=1
            ;;
        --stats-server)
            [ $# -ge 1 ] || fail "Missing arg to --stats-server"
            stats_server="$1"
            shift
            ;;
        --stats-extra)
            stats_args="$stats_args --extra-node-information"
            ;;
        --stats-key)
            [ $# -ge 1 ] || fail "Missing arg to --stats-key"
            stats_args="$stats_args --auth-key $1"
            shift
            ;;
        --verbose|-v)
            verbose=1
            ;;
        --logging|-l)
            logging=1
            ;;
        --remote|-r)
            [ $arg_count -ne 0 ] && fail "If using --remote|-r it must be the first argument"
            [ $# -ge 1 ] || fail "Missing arg to --remote|-r"
            remote_host="$1"
            shift
            run_remote "$remote_host" "$@"
            exit $?
            ;;
        --restart|-R)
            restart=1
            ;;
        --tune-network|-T)
            tune_network=1
            ;;
        *)
            [ -n "$action" ] && fail "Invalid arg '$arg'; an action of '$action' was already given"
            action="$arg"
            ;;
    esac
    let arg_count+=1
done


# setup for run
# --------------------------------------------------
# a few sanity checks
[ $send_stats -eq 1 -a -z "$stats_server" ] \
    && fail "A stats server (e.g. http://pep-stats.example.com) is required for --stats)"
cmd which docker > /dev/null || fail "Docker is not installed"
case "$action" in
    init|run|clean|reset|shell)
        ;;
    *)
        usage
        fail "Invalid action: '$action'"
esac
[ "$cert_type" = 'comodo' -o "$cert_type" = 'letsencrypt' ] \
    || fail "Invalid certificate type: $cert_type"

# init/run pre-tasks
[ "$action" = 'init' -o "$action" = 'run' ] && {
    # the images exist? auto-pull latest if using the official image
    [ $pull_image -eq 1 ] && {
        rem "pulling '$eme_img' from Docker Hub"
        cmd docker pull "$eme_img" \
            || fail "Failed to pull Encrypt.me client image '$eme_img' from Docker Hub"
    }
    # now do all image images we need exist?
    eme_img_id=$(cmd docker images -q "$eme_img")
    [ -n "$eme_img_id" ] \
        || fail "No docker image named '$eme_img' found; either build the image or use --pull-image to pull the image from Docker Hub"

    [ $pull_image -eq 1 -a $auto_update -eq 1 ] && {
        cmd docker pull "$wt_image" \
            || fail "Failed to pull WatchTower image '$wt_image' from Docker Hub"
    }

    # get auth/server info if needed
    rem "interactively collecting any required missing params"
    collect_args
    
    #load sysctl configuration
#    cp $BASE_DIR/sysctl.conf /etc
#    /sbin/sysctl -p /etc/sysctl.conf
}


# perform the main action
# --------------------------------------------------
[ "$action" = "init" ] && {
    rem "starting $name container to run config initialization"
    server_init || fail "Docker container and/or Encrypt.me private end-point failed to initialize"
}

[ "$action" = "run" ] && {
    [ $auto_update -eq 1 ] && {
        server_watch || fail "Failed to start Docker watchtower"
    }
    rem "starting $name container"
    server_run || fail "Failed to start Docker container for Encrypt.me private end-point"
}

[ "$action" = "shell" ] && {
    rem "starting temporary container"
    server_shell
}

[ "$action" = "reset" ] && {
    rem "cleaning up traces of $name container and configs"
    server_reset
}

[ "$action" = "clean" ] && {
    rem "cleaning up all traces of $name container, images, and configs"
    server_cleanup
}

exit 0
