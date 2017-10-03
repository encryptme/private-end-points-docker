# ENVIRONMENT VARIABLES

| Variable | Notes |
|----------|-------|
| ENCRYPTME_EMAIL | Registration username - required if letsencrypt enabled (default). |
| ENCRYPTME_PASSWORD | Registration password |
| ENCRYPTME_TARGET_ID | Encrypt.me target ID from Team console |
| DISABLE_LETSENCRYPT| 1 = Disable automatic letsencrypt |

Registration variables are only used during the first run, and only if you wish
to automate registration.

You can bootstrap interactively if you run with a tty: `./go.sh init`.

Then set it to run on it's own afterwards: `./go.sh run`.

You will be prompted for your Encrypt.me email address unless it is exported as
an environmental variable (e.g. `ENCRYPTME_EMAIL=you@example.com ./go.sh init`.


# MOUNTPOINTS

  /etc/encyptme

  Location where config, certs, keys are stored.  These need to be kept across
  container restarts.


### TODO:


- Determine whether to add 10.x.x.x rule and -j REJECT

- Autorenew letsencrypt (Cron job)
- Resolve CRL issue for OpenVPN
Thu Sep 21 02:15:57 2017 99.239.45.228:40803 CRL: CRL /etc/encryptme/pki/crls.pem is from a different issuer than the issuer of certificate O=Cloak, OU=Teams, CN=Toybox - toybox Clients
- Fix non-working StrongSWAN

