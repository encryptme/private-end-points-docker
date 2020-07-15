#!/usr/bin/python

import socket
import json
import os
from time import sleep

intercept_address = "0.0.0.0"
sock_file = "/usr/local/unbound-1.7/etc/unbound/dns_filter.sock"
sock_exist = False
doh_canary_domains = ["use-application-dns.net"]
doh_provider_domains = [
    "adblock.mydns.network", "cloudflare-dns.com", "commons.host",
    "dns-family.adguard.com", "dns-nyc.aaflalo.me", "dns.aa.net.uk",
    "dns.aaflalo.me", "dns.adguard.com", "dns.alidns.com",
    "dns.containerpi.com", "dns.digitale-gesellschaft.ch",
    "dns.dns-over-https.com", "dns.dnshome.de", "dns.dnsoverhttps.net",
    "dns.flatuslifir.is", "dns.google", "dns.hostux.net", "dns.quad9.net",
    "dns.rubyfish.cn", "dns.switch.ch", "dns.twnic.tw", "dns10.quad9.net",
    "dns11.quad9.net", "dns9.quad9.net", "dnsforge.de", "doh-2.seby.io",
    "doh-de.blahdns.com", "doh-fi.blahdns.com", "doh-jp.blahdns.com",
    "doh.42l.fr", "doh.applied-privacy.net", "doh.armadillodns.net",
    "doh.captnemo.in", "doh.centraleu.pi-dns.com", "doh.cleanbrowsing.org",
    "doh.crypto.sx", "doh.dns.sb", "doh.dnslify.com", "doh.eastas.pi-dns.com",
    "doh.eastau.pi-dns.com", "doh.eastus.pi-dns.com",
    "doh.familyshield.opendns.com", "doh.ffmuc.net", "doh.li",
    "doh.libredns.gr", "doh.northeu.pi-dns.com", "doh.opendns.com",
    "doh.pi-dns.com", "doh.powerdns.org", "doh.seby.io:8443", "doh.tiar.app",
    "doh.tiarap.org", "doh.westus.pi-dns.com", "doh.xfinity.com",
    "dohdot.coxlab.net", "example.doh.blockerdns.com",
    "family.canadianshield.cira.ca", "family.cloudflare-dns.com",
    "fi.doh.dns.snopyta.org", "ibksturm.synology.me", "ibuki.cgnat.net",
    "jcdns.fun", "jp.tiar.app", "jp.tiarap.org", "mozilla.cloudflare-dns.com",
    "odvr.nic.cz", "ordns.he.net", "private.canadianshield.cira.ca",
    "protected.canadianshield.cira.ca", "rdns.faelix.net",
    "resolver-eu.lelux.fi", "security.cloudflare-dns.com",
    ]


def _check_for_socket():
    global sock_exist
    for _ in range(4):
        if os.path.exists(sock_file):
            sock_exist = True
            break
        sleep(0.25)


def _is_blocked(name):
    while True:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_file)
        sock.sendall(json.dumps({'domain': name}))
        resp = str(sock.recv(2048))
        return json.loads(resp)


def init(id, cfg):
    _check_for_socket()
    return True


def deinit(id):
    return True


def inform_super(id, qstate, superqstate, qdata):
    return True


def operate(id, event, qstate, qdata):
    if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):

        # server isn't running? do nothing
        if not sock_exist:
            qstate.ext_state[id] = MODULE_WAIT_MODULE
            return True

        name = qstate.qinfo.qname_str.rstrip('.')
        is_blocked, disable_doh = _is_blocked(name)

        if disable_doh:
            if name in doh_canary_domains:
                qstate.return_rcode = RCODE_NXDOMAIN
                qstate.ext_state[id] = MODULE_FINISHED
                return True            

            if name in doh_provider_domains and not is_blocked:
                qstate.return_rcode = RCODE_NOERROR
                qstate.ext_state[id] = MODULE_FINISHED
                return True   

        # not blocked? do nothing
        if not is_blocked:
            qstate.ext_state[id] = MODULE_WAIT_MODULE
            return True

        # otherwise, respond with our intercept address
        msg = DNSMessage(qstate.qinfo.qname_str, RR_TYPE_A,
                         RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
        if (qstate.qinfo.qtype == RR_TYPE_A) or (
                qstate.qinfo.qtype == RR_TYPE_ANY):
            msg.answer.append(
                "%s 10 IN A %s" % (qstate.qinfo.qname_str,
                                   intercept_address))

        if not msg.set_return_msg(qstate):
            qstate.ext_state[id] = MODULE_ERROR
            return True

        qstate.return_msg.rep.security = 2

        qstate.return_rcode = RCODE_NOERROR
        qstate.ext_state[id] = MODULE_FINISHED
        return True

    elif event == MODULE_EVENT_MODDONE:
        qstate.ext_state[id] = MODULE_FINISHED
        return True

    qstate.ext_state[id] = MODULE_ERROR
    return True