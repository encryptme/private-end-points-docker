FROM centos:7

# Core system dependencies
RUN yum clean all && \
    yum -y -q update && \
    yum -y -q install epel-release && \
    yum -y update && \
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
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
        && \
    curl -o /etc/yum.repos.d/jdoss-wireguard-epel-7.repo \
        https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo && \
    yum -y -q install wireguard-tools && \
    yum clean all && \
    rm -rf /var/cache/yum

# System configuration
RUN useradd -s /sbin/nologin unbound

# Latest python packaging tools
RUN python3.6 -m pip install --upgrade --no-cache-dir pip && \
    python3.6 -m pip install --upgrade --no-cache-dir setuptools

# Container versioning for release tracking
LABEL version=0.13.2
RUN echo "v0.13.2" > /container-version-id

# Project specific dependencies
ARG build_time=${build_time:-x}
ARG repo_branch=${repo_branch:-master}
RUN python3.6 -m pip install --no-cache-dir \
        "git+https://github.com/encryptme/private-end-points.git@$repo_branch" \
        jinja2 \
        python-pidfile \
        && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

# Python stats daemon for health monitoring
ARG repo_branch=${repo_branch:-master}
ADD https://github.com/encryptme/private-end-points-docker-stats/archive/$repo_branch.zip \
        /tmp/encryptme-metrics.zip
RUN python3.6 -m pip install --no-cache-dir /tmp/encryptme-metrics.zip && \
    rm /tmp/encryptme-metrics.zip

# Generic files to extract/copy into the repo
ADD to_extract /tmp/to_extract
RUN tar zxf /tmp/to_extract/unbound-1.7.tar.gz -C /usr/local/
RUN rm -rf /tmp/to_extract
ADD to_copy/ /


ENTRYPOINT ["/run.sh"]
