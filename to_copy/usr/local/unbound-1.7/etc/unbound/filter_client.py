#!/usr/bin/python

import socket
import json
import os
from time import sleep

intercept_address = "0.0.0.0"
sock_file = "dns_filter.sock"
sock_exist = False


def check_for_socket():
    global sock_exist
    sock_exist = True if os.path.exists(sock_file) else False


def is_blocked(name):
    # block this name, and any subdomains of that name
    while True:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_file)
        sock.sendall(json.dumps({'domain': name}))
        return bool(str(sock.recv(2048)) == 'true')


def init(id, cfg):
    check_for_socket()
    return True


def deinit(id):
    return True


def inform_super(id, qstate, superqstate, qdata):
    return True


def operate(id, event, qstate, qdata):
    if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):
        name = qstate.qinfo.qname_str.rstrip('.')

        # not blocked or server isn't running? do nothing
        if not sock_exist or not is_blocked(name):
            qstate.ext_state[id] = MODULE_WAIT_MODULE
            return True
        else:
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
