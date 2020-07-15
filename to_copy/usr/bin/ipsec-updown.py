#!/usr/bin/python

import time
import sys
import subprocess
import socket

from daemon import Daemon
import vici


class IPsecUpDownDaemon(Daemon):
    def run(self):
        for _ in range(10):
            try:
                session = vici.Session()
                break
            except socket.error, e:
                time.sleep(1)
            except Exception as e:
                sys.exit(1)

        for label, event in session.listen(["ike-updown"]):
            if label == "ike-updown":
                up = event.get("up", "") == "yes"
                if up:
                    pass
                else:
                    cmd = ["/usr/bin/send-metric.sh","vpn_session"]
                    subprocess.check_output(cmd)


if __name__ == "__main__":
    daemon = IPsecUpDownDaemon('/tmp/ipsec-updown-daemon.pid')
    if len(sys.argv) == 2:
        if 'start' == sys.argv[1]:
            daemon.start()
        elif 'stop' == sys.argv[1]:
            daemon.stop()
        elif 'restart' == sys.argv[1]:
            daemon.restart()
        else:
            print("Unknown command")
            sys.exit(2)
        sys.exit(0)
    else:
        print("usage: %s start|stop|restart" % sys.argv[0])
        sys.exit(2)