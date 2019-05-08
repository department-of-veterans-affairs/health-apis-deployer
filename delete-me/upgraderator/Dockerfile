FROM centos:latest

RUN yum update -yqq \
    && yum install -yqq gettext openssh-clients \
    && yum clean all


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

#
# Upgraderator
#
COPY . /upgraderator/
ENTRYPOINT [ "/upgraderator/upgraderator.sh" ]