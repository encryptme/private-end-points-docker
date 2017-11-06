# OVERVIEW

The script "go.sh" (see `./go.sh --help`) automates the Docker container setup
and end-point registration. It is designed to automate the entire setup process
via:

  `./go.sh init && ./go.sh run`

It is designed to run locally or via SSH to another host (e.g. VM in the cloud)
either attended or unattended:

```
export ENCRYPTME_EMAIL=user@example.com
ENCRYPTME_SLOT_KEY=one-time-key ./go.sh init --non-interactive && ./go.sh run
```

# MOUNTPOINTS / PERSISTENT DATA

When running `./go.sh init` a directory named `encryptme_conf/` will be created in your current directory. This stores configuration files, an API key (e.g. for fetching fresh PKI certificates), certs, and keys. It needs to persist between container restarts.


# TODO

- Update these TODOs :/
- Verify letsencrypt autorenewal
- Resolve CRL issue for OpenVPN
Thu Sep 21 02:15:57 2017 99.239.45.228:40803 CRL: CRL /etc/encryptme/pki/crls.pem is from a different issuer than the issuer of certificate O=Cloak, OU=Teams, CN=Toybox - toybox Clients
- Fix non-working StrongSWAN


# go.sh usage

### ENVIRONMENT VARIABLES

| Variable | Notes |
|----------|-------|
| ENCRYPTME_EMAIL | Registration username - required if letsencrypt enabled (default). |
| ENCRYPTME_SLOT_KEY | Required when attempting to register your server. |
| DISABLE_LETSENCRYPT| 1 = Disable automatic letsencrypt |


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


GENERIC OPTIONS:
    -c|--conf-dir DIR     Directory to use/create for private configs/certs
    -d|--dryrun|--dry-run Run without making changes
                          (default: /Users/jonathonfillmore/dev/encrypt.me/pep-docker/encryptme_conf)
    -e|--email            Your Encrypt.me email address (for certs/API auth)
    -h|--help             Show this message
    -i|--image IMAGE      Docker image to use (default: royhooper/encryptme-server)
    -n|--name NAME        Container name (default: encryptme)
    -D|--dns-check        Attempt to do AWS/DO DNS validation
    -t|--cert-type TYPE   Certificate type to use e.g. 'letsencypt', 'comodo'
                          (default: letsencrypt)
    -v|--verbose          Verbose debugging info
    -l|--logging          Enable some logging, eg IPSEC via /dev/log

INIT OPTIONS:
    --server-name NAME    Fully-qualified domain name for this VPN end-point
    --slot-key ID         Slot registration key from the Encrypt.me website.
    --api-url URL         Use custom URL for Encrypt.me server API
    --non-interactive     Do not attempt to allocate TTYs (e.g. to prompt for
                          missing params)

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


# Deploying

This container expects a CentOS 7 or compatible host for IPSEC.
