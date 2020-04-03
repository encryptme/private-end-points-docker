#!/usr/bin/env python

from collections import namedtuple
from subprocess import Popen, PIPE
import json
import os
import re
import sys


WGPeer = namedtuple('WGPeer', [
    'public_key', 'preshared_key', 'endpoint', 'allowed_ips',
    'lastest_handshake', 'bytes_up', 'bytes_down', 'keep_alives'
])

EME_DIR = os.environ.get('EME_DIR', '/etc/encryptme/wireguard')
PEERS_FILE = EME_DIR + '/peers.json'


def rem(msg, color='33'):
    sys.stdout.write('[0;%sm#[1;%sm %s[0;0m\n' % (color, color, msg))


def run(cmd, dryrun=False, verbose=False):
    '''
    Run a shell command, raising a RunTime exception if it failed. Returns
    (stdout, stderr). If dryrun=True prints the command and returns (None,
    None) instead. Always prints the command if verbose=True.
    '''
    if dryrun or verbose:
        rem('%s' % (' '.join(cmd)), '32')
    if dryrun:
        return None, None
    proc = Popen(cmd, stdin=PIPE, stdout=PIPE, stderr=PIPE)
    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError("Failed to run %s: %s" % (
            cmd[0],
            stderr
        ))
    return stdout, stderr


def fetch_eme_conf(base_url, config_file=None, verbose=False):
    '''
    Downloads Encrypt.me peer configuration information for valid users.
    Returns a tuple of response data and a parse mapping of public key to
    private IPv4 address.
    '''
    # e.g.:
    # {
    #   "wireguard_peers": {
    #     "usr_d7eaondzddogjitf": {
    #       "dev_ncfmdpdnyr4kbvrg": {
    #         "public_key": "ljXdE1MLQ3KRPtmqs38lI9E8Zo5iSoIN7BfYg7c28AE=",
    #         "private_ipv4_address": "100.64.128.1/32"
    #         "private_ipv4_address_int": 1684045825
    #       }
    #     }
    #   }
    # }
    cmd = [
        'cloak-server',
        '--base_url', base_url,
    ]
    if config_file:
        cmd.append('--config')
        cmd.append(config_file)
    cmd.append('wireguard')
    stdout, stderr = run(cmd, verbose=verbose)
    eme_conf = {}  # maps pubkey to private IP
    eme_data = json.loads(stdout)
    for user in eme_data:
        user_data = eme_data[user]
        for device in user_data:
            device_data =  user_data[device]
            eme_conf[device_data['public_key']] = device_data['private_ipv4_address']
    return stdout, eme_conf


def fetch_wg_conf(wg_iface, verbose=False):
    '''
    Parses WireGuard dump info into named tuples.
    '''
    stdout, stderr = run(['wg', 'show', wg_iface, 'dump'], verbose=verbose)
    wg_conf = {}  # maps pubkey to WGPeer namedtuples
    wg_re = re.compile('\s+')
    # first line is server interface info, so we skip it
    for line in stdout.split()[1:]:
        clean_line = line.strip()
        if not clean_line:
            continue
        wg_peer = WGPeer(wg_re.split(line))
        wg_conf[wg_peer.public_key] = wg_peer
    return wg_conf


def wg_up(wg_iface, pubkey, allowed_ips, dryrun=False, verbose=False):
    '''
    Add a peer to WireGuard.
    '''
    run(['ip', '-4', 'route', 'add', allowed_ips, 'dev', wg_iface], dryrun, verbose)
    run(['wg', 'set', wg_iface, 'peer', pubkey, 'allowed-ips', allowed_ips], dryrun, verbose)
    

def wg_down(wg_iface, wg_peer, dryrun=False, verbose=False):
    '''
    Remove a peer from a WireGuard interface.
    '''
    run(['wg', 'set', wg_iface, 'peer', wg_peer.public_key, 'remove'], dryrun, verbose)
    run(['ip', '-4', 'route', 'del', wg_peer.allowed_ips, 'dev', wg_iface], dryrun, verbose)
    


def main(wg_iface, base_url=None, config_file=None, verbose=False, dryrun=False):
    '''
    Fetches data from Encrypt.me, parses local WireGuard interface
    configuration information and ensures all peers are configured correctly
    based on any changes.
    '''
    # get the config data from Encrypt.me and from what is on the server now
    # then, using wg interface data we can decide:
    if dryrun:
        rem("*** DRY RUN (no changes will be made) ***")
    eme_resp_data, eme_conf = fetch_eme_conf(base_url, config_file, verbose=verbose)
    if verbose:
        rem("Found %d peers from Encrypt.me; saving to %s" % (
            len(eme_conf), PEERS_FILE
        ))
    if not dryrun:
        with open(PEERS_FILE, 'w') as peers_file:
            peers_file.write(eme_resp_data)
    wg_conf = fetch_wg_conf(wg_iface, verbose=verbose)
    if verbose:
        rem("Found %d local WireGuard peers" % (len(wg_conf)))
    eme_pubkeys = frozenset(eme_conf.keys())
    wg_pubkeys = frozenset(wg_conf.keys())

    # --- we need to determine: ---
    # * which peers to remove
    pubkeys_old = wg_pubkeys - eme_pubkeys
    if verbose:
        rem("Removing %d old peers" % len(pubkeys_old))
    [
        wg_down(wg_iface, wg_conf['peers'][pubkey], dryrun)
        for pubkey in pubkeys_old
    ]
    # * which peers to possibly change the IP address of
    pubkeys_same = wg_pubkeys & eme_pubkeys
    changed = 0
    for pubkey in pubkeys_same:
        eme_ipv4 = eme_conf[pubkey]
        wg_ipv4 = wg_conf[pubkey].allowed_ips
        if eme_ipv4 != wg_ipv4:
            changed += 1
            wg_down(wg_iface, wg_conf[pubkey], dryrun, verbose)
            wg_up(wg_iface, pubkey, eme_conf[pubkey], dryrun, verbose)
    if verbose:
        rem("Changed %d peers to new IP addresses" % (changed))
    # * which peers to add
    pubkeys_new = eme_pubkeys - wg_pubkeys
    if verbose:
        rem("Adding %d new peers" % len(pubkeys_new))
    [
        wg_up(wg_iface, pubkey, eme_conf[pubkey], dryrun, verbose)
        for pubkey in pubkeys_new
    ]
    
    

#
# Parse out "foo=bar" type parameters and runs the script.
#
if __name__ == '__main__':
    # sanity checks
    if not os.path.isdir(EME_DIR):
        raise Exception("Failed to find Encrypt.me WireGuard directory")

    # poor man's argparse
    args = {
        'wg_iface': None,
        'config_file': None,
        'base_url': 'https://app.encrypt.me/',
        'dryrun': False,
        'verbose': False,
    }
    for arg in sys.argv[1:]:
        if '=' not in arg:
            raise Exception("Expected: arg=value; invalid parameter: %s" % (arg))
        (arg_name, arg_val) = arg.split('=', 2)
        if arg_name not in args:
            raise Exception("Invalid arg: %s" % arg_name)
        if arg_val.isdigit():
            arg_val = int(arg_val)
        args[arg_name] = arg_val
    if not args['wg_iface']:
        raise Exception("You must pass wg_iface=X as a required parameter.")
    try:
        main(**args)
    except Exception as ex:
        sys.stderr.write(str(ex) + '\n')
        sys.exit(1)
