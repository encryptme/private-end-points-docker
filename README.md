# DEPLOYING

This container expects a CentOS 7 or compatible host for IPSEC. 
Server registration keys can be created by Encrypt.me Teams on the network
management section of the the team control panel.


# OVERVIEW

The script "go.sh" (see `./go.sh --help`) automates the Docker container setup
and end-point registration. It is designed to automate the entire setup process
via:

  `./go.sh init --pull-image && ./go.sh run`

It is designed to run locally or via SSH to another host (e.g. VM in the cloud,
via the --remote option) either attended or unattended. Docker must be
installed and running on the target host.

```
export SSL_EMAIL=user@example.com
ENCRYPTME_SLOT_KEY=one-time-key ./go.sh init --non-interactive && ./go.sh run
```


# MOUNTPOINTS / PERSISTENT DATA

When running `./go.sh init` a directory named `encryptme_conf/` will be created
in your current directory. This stores configuration files, an API key (e.g.
for fetching fresh PKI certificates), certs, and keys. It needs to persist
between container restarts.


# SSL CERTIFICATES

A 90-day SSL certicate is automatically obtained from LetsEncrypt. Domain
ownership is validated via the HTTP ACME challenge. This is automatically
renewed for you.


# go.sh FULL USAGE

### ENVIRONMENT VARIABLES

| Variable | Notes |
|----------|-------|
| SSL_EMAIL | Registration username - required if letsencrypt enabled (default). |
| ENCRYPTME_SLOT_KEY | Required when attempting to register your server. |
| LETSENCRYPT_DISABLED| 1 = Disable automatic letsencrypt |


```
usage: ./go.sh [--remote|-r HOST] [ACTION ARGS] ACTION

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
    -d|--dryrun|--dry-run Run without making changes
                          (default: /path/to/encryptme_conf)
    -e|--email            Email email address for LetsEncrypt certs
    -h|--help             Show this message
    -i|--image IMAGE      Docker image to use (default: encryptme/pep)
    -n|--name NAME        Container name (default: encryptme)
    -D|--dns-check        Attempt to do AWS/DO DNS validation
    -t|--cert-type TYPE   Certificate type to use e.g. 'letsencypt', 'comodo'
                          (default: letsencrypt)
    -v|--verbose          Verbose debugging info
    -l|--logging          Enable some logging, eg IPSEC via /dev/log

INIT OPTIONS:
    --api-url URL         Use custom URL for Encrypt.me server API
    --non-interactive     Do not attempt to allocate TTYs (e.g. to prompt for
                          missing params)
    --server-name NAME    Fully-qualified domain name for this VPN end-point
    --slot-key ID         Slot registration key from the Encrypt.me website.

RUN OPTIONS:
    -R|--restart          Restarts running services if already running

PRIVACY/SECURITY OPTIONS:
    -P|--pull-image       Pull Docker Hub image? (default: off)
    -U|--update           Run WatchTower to keep VPN container up-to-date
                          (default: off)
    -S|--stats            Send generic bandwidth/health stats (default: off)
    --stats-server        Specify an alternate http(s) server to receive stats
    --stats-extra         Include extra details in stats, such as server_id, target_id,
                          server name (fqdn) and target name (default: off)


EXAMPLES:

    # launch an auto-updating image with health reporting using the official
    # image and ensure our AWS/DO public IP matches our FQDN
    ./go.sh init -S -U -P -D

    # run the newly initialized server
    ./go.sh run
```
