
# ENVIRONMENT VARIABLES

| Variable | Notes |
|----------|-------|
| ENCRYPTME_EMAIL | Registration username - required if letsencrypt enabled (default). |
| ENCRYPTME_PASSWORD | Registration password |
| ENCRYPTME_TARGET_ID | Encrypt.me target ID from Team console |
| DISABLE_LETSENCRYPT| 1 = Disable automatic letsencrypt |

Registration variables are only used during the first run, and only  if you wish to automate registration.

You can bootstrap interactively if you run with a tty:

    docker build -t encryptme .
    docker run -it --rm -v `pwd`/runconf:/etc/encryptme \
      --privileged \
      --net host \
      encryptme

Then set it to run on it's own afterwards:

    docker run -d --name encyptme \
      -v `pwd`/runconf:/etc/encryptme \
      --privileged \
      --net host \
      --restart always \
      encryptme


# MOUNTPOINTS

  /etc/encyptme

  Location where config, certs, keys are stored.  These need to be kept
  across container restarts.


### TODO:


- Determine whether to add 10.x.x.x rule and -j REJECT

- Integrate Letsencrypt (including ipsec.conf)
- Use supervisord
- Make update-pki.sh use supervisor restarts
- Autorenew letsencrypt


TODO: Investigate warnings from container on a virgin Digital ocean VM

no netkey IPsec stack detected
ipsec_starter[42]: no netkey IPsec stack detected

no KLIPS IPsec stack detected
ipsec_starter[42]: no KLIPS IPsec stack detected

no known IPsec stack detected, ignoring!
ipsec_starter[42]: no known IPsec stack detected, ignoring!

