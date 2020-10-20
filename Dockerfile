FROM centos:7

RUN yum clean all && \
    yum -y -q update && \
    yum -y -q install epel-release\
    && yum -y update && \
    yum -y -q install \
        cronie \
        python36 \
        python36-devel \
        python36-pip \
        git \
        jq \
        vim \
        gcc \
        bind-utils \
        && \
    yum -y -q install \
        openvpn \
        strongswan \
        kmod \
        letsencrypt \
        curl \
        socat \
        ipset \
        && \
    rm -rf /var/cache/yum

LABEL version=0.11.2
RUN echo "v0.11.2" > /container-version-id

ARG repo_branch=${repo_branch:-master}
RUN pip3.6 install --upgrade pip && \
    pip3.6 install "git+https://github.com/encryptme/private-end-points.git@$repo_branch" jinja2 && \
    pip3.6 install sander-daemon && \
    pip3.6 install vici && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

ARG repo_branch=${repo_branch:-master}
ADD https://github.com/encryptme/private-end-points-docker-stats/archive/$repo_branch.zip /tmp/encryptme-metrics.zip
RUN pip3.6 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV LETSENCRYPT_DISABLED 0
ENV PYTHONPATH "${PYTHONPATH}:/usr/local/unbound-1.7/etc/unbound/usr/lib64/python2.7/site-packages"

ARG build_time=${build_time:-x}
ADD to_extract /tmp/to_extract
RUN tar zxf /tmp/to_extract/unbound-1.7.tar.gz -C /usr/local/
RUN rm -rf /tmp/to_extract
ADD to_copy/ /

RUN useradd -s /sbin/nologin unbound

ENTRYPOINT ["/run.sh"]
