FROM ubuntu:16.04
ARG pep_repo=${pep_repo:-git+https://github.com/encryptme/private-end-points.git}


RUN apt-get update && \
    apt-get install -y python python-pip python3 python3-pip git && \
    apt-get install -y unbound cron openvpn strongswan kmod letsencrypt && \
    apt-get install -y knot-dnsutils jq vim iputils-ping curl socat && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install "$pep_repo" jinja2

LABEL version=0.9.2-royhooper

ADD https://gitlab.toybox.ca/krayola/encryptme-metrics/repository/archive.zip?ref=master /tmp/encryptme-metrics.zip
RUN pip3 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV DISABLE_LETSENCRYPT 0

ADD files/ /

ENTRYPOINT ["/run.sh"]
