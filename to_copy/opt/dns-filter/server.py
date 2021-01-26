#!/usr/bin/env python3

from contextlib import closing
import socket
import os
import sys
import grp
import pwd
import json

import daemon


# daemon configuration
FILTERS_DIR = "/etc/encryptme/filters"
SOCKET_PATH = "/usr/local/unbound-1.7/etc/unbound/dns_filter.sock"
PID_FILE    = "/usr/local/unbound-1.7/etc/unbound/dns-filter.pid"


def delete_socket_path(socket_path):
    try:
        os.unlink(socket_path)
    except OSError:
        if os.path.exists(socket_path):
            raise


class FilterList:
    def __init__(self, filters_dir):
        """
        Build entries from file.
        """
        self.disable_doh = False
        self.blacklist = set()
        self.load(filters_dir)

    @staticmethod
    def _yield_lines(path):
        with open(path) as list_file:
            for item in list_file:
                yield item.strip()

    def load(self, filters_dir):
        if not os.path.isdir(filters_dir):
            return
        for name in os.listdir(filters_dir):
            if not name.endswith('.domains.blacklist'):
                continue
            for domain in self._yield_lines(os.path.join(filters_dir, name)):
                self.blacklist.add(domain)
        self.disable_doh = bool(self.blacklist)

    def is_blocked(self, domain):
        '''
        Returns whether this domain is blocked or is a sub-domain of a blocked
        domain.
        '''
        name = domain
        while '.' in name:
            if name in self.blacklist:
                return True
            name = name[name.find('.') + 1:]
        return False


class FilterDaemon(daemon.Daemon):
    def __init__(self, socket_path, filters_dir, **kwargs):
        self.socket_path = socket_path
        self.filters_dir = filters_dir
        super(FilterDaemon, self).__init__(**kwargs)

    def run(self):
        filter_list = FilterList(self.filters_dir)

        delete_socket_path(self.socket_path)

        #create the socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        with closing(sock):
            sock.bind(self.socket_path)
            sock.listen(1)
            if not os.path.exists(self.filters_dir):
                os.makedirs(self.filters_dir)
            uid = pwd.getpwnam("unbound").pw_uid
            gid = grp.getgrnam("unbound").gr_gid
            os.chown(self.socket_path, uid, gid)
            self._run_loop(sock, filter_list)

    def _run_loop(self, sock, filter_list):
        while True:
            connection, address = sock.accept()
            with closing(connection):
                data = connection.recv(2048)
                if data:
                    request = json.loads(data)
                    response = [
                        filter_list.is_blocked(request['domain'].strip()),
                        filter_list.disable_doh,
                    ]
                    connection.sendall(json.dumps(response).encode('utf-8'))


if __name__ == "__main__":
    daemon = FilterDaemon(
        socket_path=SOCKET_PATH,
        filters_dir=FILTERS_DIR,
        pidfile=PID_FILE
    )

    if len(sys.argv) != 2:
        print("Unknown command")
        sys.exit(2)

    if 'start' == sys.argv[1]:
        daemon.start()

    elif 'stop' == sys.argv[1]:
        daemon.stop()
        delete_socket_path(SOCKET_PATH)
    
    elif 'restart' == sys.argv[1]:
        daemon.stop()
        delete_socket_path(SOCKET_PATH)
        daemon.start()

    elif 'status' == sys.argv[1]:
        try:
            pf = file(PID_FILE, 'r')
            pid = int(pf.read().strip())
            pf.close()
        except IOError:
            pid = None
        except SystemExit:
            pid = None
        if pid:
            print('dns-filter is running with pid %s' % pid)
        else:
            print('dns-filter is not running.')
    else:
        print("usage: %s start|stop|restart|status" % sys.argv[0])
        sys.exit(2)
