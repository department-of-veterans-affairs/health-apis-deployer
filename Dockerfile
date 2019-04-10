FROM centos:latest

RUN yum update -y && yum install -y git && yum clean all

RUN curl -fsSL https://get.docker.com | sh


