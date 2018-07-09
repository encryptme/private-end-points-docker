FROM centos:7

RUN yum clean all && \
    yum -y -q update && \
    yum -y -q install epel-release && yum -y update && \
    yum -y -q install cronie python-pip python34 python-devel python34-devel python34-pip git knot jq gcc bind-utils && \
    yum -y -q install openvpn strongswan kmod letsencrypt vim curl socat wget perl-JSON-PP.noarch && \
    rm -rf /var/cache/yum

LABEL version=0.10
RUN echo "v0.10.1" > /container-version-id

ARG repo_branch=${repo_branch:-master}
RUN pip install --upgrade pip && \
    pip install "git+https://github.com/encryptme/private-end-points.git@$repo_branch" jinja2 && \
    pip install sander-daemon && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

ARG repo_branch=${repo_branch:-master}
ADD https://github.com/encryptme/private-end-points-docker-stats/archive/$repo_branch.zip /tmp/encryptme-metrics.zip
RUN pip3 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV DISABLE_LETSENCRYPT 0

ARG build_time=${build_time:-x}
ADD to_extract /tmp/to_extract
RUN tar zxf /tmp/to_extract/unbound-1.7.tar.gz -C /usr/local/
RUN rm -rf /tmp/to_extract
ADD to_copy/ /

RUN useradd -s /sbin/nologin unbound

ENTRYPOINT ["/run.sh"]
