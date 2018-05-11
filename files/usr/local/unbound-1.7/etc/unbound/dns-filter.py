#!/usr/bin/python

from os import listdir
from os.path import isfile, join

blacklist = set()
whitelist = set()

intercept_address = "127.0.0.1"

BLACKLISTS_LOCATION = "./blacklists"
WHITELIST_FILE = "./whitelist.txt"

def file_to_domains(filename):
    with open(filename) as fyl:
        for entry in fyl:
            yield entry.strip()

def load_blacklists():
    try:
        is_blacklist_file = lambda f: \
            isfile(join(BLACKLISTS_LOCATION, f)) \
            and f.endswith('.txt')
        files = [f for f in listdir(BLACKLISTS_LOCATION) if is_blacklist_file(f)]
        for filename in files:
            for domain in file_to_domains(join(BLACKLISTS_LOCATION, filename)):
                blacklist.add(domain)
    except OSError as e:
        if e.errno == 2: # OSError: [Errno 2] No such file or directory: 'fdas', FileNotFoundError for Python 3
            log_err("missing file:" + e.filename)
        else:
            raise

def load_whitelist():
    try:
        for domain in file_to_domains(WHITELIST_FILE):
            whitelist.add(domain)
    except IOError as e:
        if e.errno == 2: #  IOError: [Errno 2] No such file or directory: 'fdsfsd', FileNotFoundError for Python 3
            log_err("missing file:" + e.filename)
        else:
            raise

def check_name(name, xlist):
    while True:
        if (name in xlist):
            return True
        elif (name.find('.') == -1):
            return False;
        else:
            name = name[name.find('.')+1:]

def init(id, cfg):
    log_info("dns_filter.py: ")
    load_whitelist()
    load_blacklists()
    return True

def deinit(id):
    return True

def inform_super(id, qstate, superqstate, qdata):
    return True

def operate(id, event, qstate, qdata):

    if (event == MODULE_EVENT_NEW) or (event == MODULE_EVENT_PASS):

        # Check if whitelisted.
        name = qstate.qinfo.qname_str.rstrip('.')

        #        log_info("dns_filter.py: Checking "+name)

        if (check_name(name, whitelist)):
            #            log_info("dns_filter.py: "+name+" whitelisted")
            qstate.ext_state[id] = MODULE_WAIT_MODULE
            return True

        if (check_name(name, blacklist)):
            #            log_info("dns_filter.py: "+name+" blacklisted")

            msg = DNSMessage(qstate.qinfo.qname_str, RR_TYPE_A, RR_CLASS_IN, PKT_QR | PKT_RA | PKT_AA)
            if (qstate.qinfo.qtype == RR_TYPE_A) or (qstate.qinfo.qtype == RR_TYPE_ANY):
                msg.answer.append("%s 10 IN A %s" % (qstate.qinfo.qname_str, intercept_address))


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

    if event == MODULE_EVENT_MODDONE:
        #        log_info("pythonmod: iterator module done")
        qstate.ext_state[id] = MODULE_FINISHED
        return True

    log_err("pythonmod: bad event")
    qstate.ext_state[id] = MODULE_ERROR
    return True
