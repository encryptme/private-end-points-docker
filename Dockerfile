FROM centos:7

RUN yum clean all \
    && yum -y -q update \
    && yum -y -q install epel-release \
    && yum -y update \
    && yum -y -q install \
        cronie \
        python-pip \
        python34 \
        python-devel \
        python34-devel \
        python34-pip \
        git \
        jq \
        gcc \
        bind-utils \
    && yum -y -q install \
        openvpn \
        strongswan \
        kmod \
        letsencrypt \
        vim \
        curl \
        socat \
        ipset

RUN curl -o /etc/yum.repos.d/jdoss-wireguard-epel-7.repo \
        https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo \
    && yum -y -q install wireguard-dkms wireguard-tools \
    && rm -rf /var/cache/yum

LABEL version=0.12.0
RUN echo "v0.12.0" > /container-version-id

ARG repo_branch=${repo_branch:-master}
RUN pip install --upgrade pip && \
    pip install "git+https://github.com/encryptme/private-end-points.git@$repo_branch" jinja2 && \
    pip install sander-daemon && \
    ln -s /usr/sbin/strongswan /usr/sbin/ipsec

ARG repo_branch=${repo_branch:-master}
ADD https://github.com/encryptme/private-end-points-docker-stats/archive/$repo_branch.zip /tmp/encryptme-metrics.zip
RUN pip3.4 install /tmp/encryptme-metrics.zip && rm /tmp/encryptme-metrics.zip

ENV LETSENCRYPT_DISABLED 0
ENV PYTHONPATH "${PYTHONPATH}:/usr/local/unbound-1.7/etc/unbound/usr/lib64/python2.7/site-packages"

ARG build_time=${build_time:-x}
ADD to_extract /tmp/to_extract
RUN tar zxf /tmp/to_extract/unbound-1.7.tar.gz -C /usr/local/
RUN rm -rf /tmp/to_extract
ADD to_copy/ /

RUN useradd -s /sbin/nologin unbound

ENTRYPOINT ["/run.sh"]
