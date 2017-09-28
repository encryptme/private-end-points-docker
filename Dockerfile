FROM ubuntu:16.04

RUN apt-get update && \
    apt-get install -y python python-pip git && \
    apt-get install -y unbound cron openvpn strongswan kmod letsencrypt && \
    apt-get install -y knot-dnsutils jq vim iputils-ping curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install git+https://github.com/encryptme/cloak-server.git jinja2

ENV DISABLE_LETSENCRYPT 0

ADD files/ /

ENTRYPOINT ["/run.sh"]
