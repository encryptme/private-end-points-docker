
ENVIRONMENT VARIABLES

ENCRYPTME_USER
ENCRYPTME_PASSWORD
ENCRYPTME_TARGET_ID
ENCRYPTME_SERVER_NAME

These are required on first run only, if you wish to automate registration.

You can bootstrap interactively if you run with a tty:

   docker run -it --rm -v `pwd`/etc:/etc/encyptme


MOUNTOINTS

  /etc/encyptme

  Location where config, certs, keys are stored.  These need to be kept
  across container restarts.


TODO:

    Traceback (most recent call last):
      File "/usr/local/bin/cloak-server", line 10, in <module>
        returncode = cloak.serverapi.cli.main.main()
      File "/usr/local/lib/python2.7/dist-packages/cloak/serverapi/cli/main.py", line 49, in main
        args.cmd.handle(config=config, **vars(args))
      File "/usr/local/lib/python2.7/dist-packages/cloak/serverapi/cli/commands/crls.py", line 45, in handle
        updated = self._fetch_crl(config, url, out, fmt)
      File "/usr/local/lib/python2.7/dist-packages/cloak/serverapi/cli/commands/crls.py", line 73, in _fetch_crl
        with open(crl_path, 'wb') as f:
    IOError: [Errno 2] No such file or directory: u'/etc/encryptme/pki/crls/ca_b2sibrq4jwbgxr3o.pem'
