#!/usr/bin/python

import socket
import json
import os
from time import sleep

intercept_address = "127.0.0.1"
sock_file = "/var/run/dns_filter.sock"


def check_for_socket():
    global sock_exist
    sock_exist = 0
    sock_check_count = 0
    while not os.path.exists(sock_file):
        sleep(0.025)
        if sock_check_count == 4:
            sock_exist = 1
            break
        sock_check_count += 1


def check_name(name, domain_list):
    while True:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_file)
        domain_query = {}
        domain_query["domain"] = name
        domain_query["domain_list"] = domain_list
        domain_query = json.dumps(domain_query)
        print(domain_query)
        sock.sendall(domain_query)
        if str(sock.recv(2048)) == 'true':
            return True
        elif (name.find('.') == -1):
            return False
        else:
            name = name[name.find('.') + 1:]


def init(id, cfg):
    check_for_socket()
    return True


def deinit(id):
    return True


def inform_super(id, qstate, superqstate, qdata):
    return True


def operate(id, event, qstate, qdata):
    if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):

        # Check if whitelisted.
        name = qstate.qinfo.qname_str.rstrip('.')

        if sock_exist == 0:
            if (check_name(name, "whitelist")):
                qstate.ext_state[id] = MODULE_WAIT_MODULE
                return True

            if (check_name(name, "blacklist")):
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
            else:
                qstate.ext_state[id] = MODULE_WAIT_MODULE
                return True
        else:
            qstate.ext_state[id] = MODULE_WAIT_MODULE
            return True

    if event == MODULE_EVENT_MODDONE:
        qstate.ext_state[id] = MODULE_FINISHED
        return True

    log_err("pythonmod: bad event")
    qstate.ext_state[id] = MODULE_ERROR
    return True
