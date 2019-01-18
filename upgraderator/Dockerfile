FROM centos:latest

RUN yum update -yqq \
    && yum install -yqq gettext \
    && yum clean all

RUN curl -skLo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
    && chmod +x /usr/local/bin/jq

RUN curl -fskLS https://get.docker.com | sh

ENV OC_VERSION=v3.11.0 \
    OC_TAG_SHA=0cbc58b

RUN curl -skLo /tmp/oc.tar.gz https://github.com/openshift/origin/releases/download/${OC_VERSION}/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit.tar.gz \
    && tar xzvf /tmp/oc.tar.gz -C /tmp/ \
    && mv /tmp/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit/oc /usr/local/bin/ \
    && rm -rf /tmp/oc.tar.gz /tmp/openshift-origin-client-tools-${OC_VERSION}-${OC_TAG_SHA}-linux-64bit

COPY upgrade.conf build.conf upgraderator.sh /upgraderator/

ENTRYPOINT /upgraderator/upgraderator.sh