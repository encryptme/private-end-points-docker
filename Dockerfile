FROM centos:7

RUN yum clean all && \
    yum -y -q update && \
    yum -y -q install epel-release && yum -y update && \
    yum -y -q install cronie python-pip python34 python-devel python34-devel python34-pip git jq gcc bind-utils && \
    yum -y -q install unbound openvpn strongswan kmod letsencrypt vim curl socat && \
    rm -rf /var/cache/yum

LABEL version=0.10
RUN echo "v0.10.1" > /container-version-id

ARG repo_branch=${repo_branch:-master}
RUN pip install --upgrade pip && \
    pip install "git+https://github.com/encryptme/private-end-points.git@stage" jinja2 && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

ARG repo_branch=${repo_branch:-master}
ADD https://github.com/encryptme/private-end-points-docker-stats/archive/$repo_branch.zip /tmp/encryptme-metrics.zip
RUN pip3.4 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV LETSENCRYPT_DISABLED 0

ARG build_time=${build_time:-x}
ADD files/ /

ENTRYPOINT ["/run.sh"]
