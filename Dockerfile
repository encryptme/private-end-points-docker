FROM ubuntu:16.04

RUN apt-get update && \
    apt-get install -y python python-pip git && \
    apt-get install -y unbound cron openvpn strongswan && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install git+https://github.com/encryptme/cloak-server.git

ADD run.sh /run.sh

ENTRYPOINT ["/run.sh"]
