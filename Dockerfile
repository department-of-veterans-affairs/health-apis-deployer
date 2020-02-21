FROM vasdvp/health-apis-centos:7

RUN yum update -yqq \
    && yum install -y -q yum-utils \
    && yum install -y -q gettext openssh-clients \
    && yum install -y -q zip unzip \
    && yum install -y -q dos2unix \
    && yum clean all

#
# git
#
RUN yum install -y -q https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm  \
    && yum install -y -q https://rhel7.iuscommunity.org/ius-release.rpm
RUN yum install -y git216



#
# JQ
#
RUN curl -skLo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
    && chmod +x /usr/local/bin/jq


#
# Docker
#
RUN curl -fskLS https://get.docker.com | sh


#
# AWS Command Line Utilities
#
ENV PIP_CERT=/etc/pki/ca-trust/source/anchors/VA-Internal-S2-RCA1-v1.pem
RUN openssl x509 -in /etc/pki/ca-trust/source/anchors/VA-Internal-S2-RCA1-v1.cer -out $PIP_CERT
RUN curl -skLo /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python /tmp/get-pip.py \
    && rm /tmp/get-pip.py \
    && pip install --no-cache-dir awscli



#
# Kubernetes kubectl
#
ARG KUBERNETES_VERSION=v1.14.1

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    &&  mv ./kubectl /usr/local/bin/kubectl


RUN curl -fsSL https://get.docker.com | sh

#
# Odd... this yum command succeeds down here at the bottom, but fails at the top.
#
RUN yum install -y -q openssl
