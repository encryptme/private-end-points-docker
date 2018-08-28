# DEPLOYING

This container expects a CentOS 7 or compatible host for IPSEC. 
Server registration keys can be created by Encrypt.me Teams on the network
management section of the the team control panel.

The script `build.sh` is used to help automate building the docker image (e.g. set tags, force a cache-bust around the code layers, etc).


# OVERVIEW

The script "go.sh" (see `./go.sh --help`) automates the Docker container setup
and end-point registration. It is designed to automate the entire setup process
via:

  `./go.sh init && ./go.sh run`

It is designed to run locally or via SSH to another host (e.g. VM in the cloud,
via the --remote option) either attended or unattended. Docker must be
installed and running on the target host.

```
export SSL_EMAIL=user@example.com
ENCRYPTME_SLOT_KEY=one-time-key ./go.sh init --non-interactive && ./go.sh run
```

You can also use `test.sh` with environmental variables (or using a wrapper-script to set said variables) to help test the build/run lifecycle easily.


# MOUNTPOINTS / PERSISTENT DATA

When running `./go.sh init` a directory named `encryptme_conf/` will be created
in your current directory. This stores configuration files, an API key (e.g.
for fetching fresh PKI certificates), certs, and keys. It needs to persist
between container restarts.


# SSL CERTIFICATES

A 90-day SSL certicate is automatically obtained from LetsEncrypt. Domain
ownership is validated via the HTTP ACME challenge. This is automatically
renewed for you.


# CONTENT FILTERING

The script `pep-filter.sh` is packaged in the Docker image to make it easy to block lists of domains/IPs.

  - The DNS server, unbound, has the ability to use a python module to dynamically rewrite DNS responses
  - IP ranges (using CIDR notation) can be blocked using iptables. To make this effecient, ipsets are used to group lists together.
