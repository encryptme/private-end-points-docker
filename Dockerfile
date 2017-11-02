FROM centos:7
ARG pep_repo=${pep_repo:-git+https://github.com/encryptme/private-end-points.git}

RUN yum clean all && \
    yum -y -q update && \
    yum -y -q install epel-release && yum -y update && \
    yum -y -q install cronie python-pip python34 python-devel python34-devel python34-pip git knot jq gcc && \
    yum -y -q install unbound openvpn strongswan kmod letsencrypt vim curl socat perl-JSON-PP.noarch && \
    rm -rf /var/cache/yum

RUN pip install --upgrade pip && \
    pip install "$pep_repo" jinja2 && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

LABEL version=0.9.7

ADD https://gitlab.toybox.ca/krayola/encryptme-metrics/repository/archive.zip?ref=master /tmp/encryptme-metrics.zip
RUN pip3 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV DISABLE_LETSENCRYPT 0

ADD files/ /

ENTRYPOINT ["/run.sh"]
