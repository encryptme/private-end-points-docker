#!/usr/bin/python

import sys
import vici
from daemon import Daemon
import subprocess

class MyDaemon(Daemon):
    
    def run(self):

        session = vici.Session()
        ver = session.version()
        print("connected to {daemon} {version} ({sysname}, {release}, "
                    "{machine})".format(**ver))

        for label, event in session.listen(["ike-updown"]):
            name = next((x for x in iter(event) if x != "up"))
            up = event.get("up", "") == "yes"

            if label == "ike-updown":
                if up:
                    pass
                else:
                    subprocess.check_output(["/usr/bin/send-metric.sh","vpn_session"])


if __name__ == "__main__":
    daemon = MyDaemon('/tmp/ipsec-updown-daemon.pid')
    if len(sys.argv) == 2:
        if 'start' == sys.argv[1]:
                daemon.start()
        elif 'stop' == sys.argv[1]:
                daemon.stop()
        elif 'restart' == sys.argv[1]:
                daemon.restart()
        else:
                print "Unknown command"
                sys.exit(2)
        sys.exit(0)
    else:
        print "usage: %s start|stop|restart" % sys.argv[0]
        sys.exit(2)