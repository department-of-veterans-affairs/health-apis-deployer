FROM centos:latest

RUN yum update -yqq \
    && yum install -yqq yum-utils \
    && yum install -yqq gettext openssh-clients git \
    && yum install -yqq zip unzip \
    && yum install -yqq dos2unix \
    && yum clean all

#
# JQ
#
RUN curl -skLo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
    && chmod +x /usr/local/bin/jq


#
# Docker
#
RUN yum -y install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
RUN curl -fskLS https://get.docker.com | sh


#
# AWS Command Line Utilities
#
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
RUN yum install -yqq openssl
