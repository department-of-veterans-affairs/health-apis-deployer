FROM centos:latest

RUN yum update -yqq \
    && yum install -yqq gettext \
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
# OpenShift
#
ENV OC_VERSION=v3.7.2 \
    OC_TAG_SHA=282e43f

RUN curl -skLo /tmp/oc.tar.gz https://github.com/openshift/origin/releases/download/${OC_VERSION}/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit.tar.gz \
    && tar xzvf /tmp/oc.tar.gz -C /tmp/ \
    && mv /tmp/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit/oc /usr/local/bin/ \
    && rm -rf /tmp/oc.tar.gz /tmp/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit


#
# AWS Command Line Utilities
#
RUN curl -skLo /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python /tmp/get-pip.py \
    && rm /tmp/get-pip.py \
    && pip install --no-cache-dir awscli


#
# Upgraderator
#
COPY . /upgraderator/
ENTRYPOINT /upgraderator/upgraderator.sh