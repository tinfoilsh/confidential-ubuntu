# syntax=docker/dockerfile:1.6
#
# Confidential Ubuntu: a measured, CVM-admin interactive workspace.
# The base is digest-pinned for attestation.
#
# cvm_admin supplies the privileges for the inner daemon, not a host socket.
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254

FROM ${BASE_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive
ARG DOCKER_VERSION=29.6.2
ARG DOCKER_SHA256=d6204aea92238e2453d5445c885b9d2e5eb8f82915568ec50edf9dbe12a3ac74
ARG BUILDX_VERSION=0.37.1
ARG BUILDX_SHA256=9447199cdb435f25880548343c128a4b6650e8891ee598905d8d29d39a8e359b

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      pciutils \
      curl \
      git \
      less \
      vim-tiny \
      python3 \
      python3-venv \
      python3-pip \
      rsync htop tmux openssh-server iproute2 procps nftables \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz \
    && echo "${DOCKER_SHA256}  /tmp/docker.tgz" | sha256sum -c - \
    && tar -xzf /tmp/docker.tgz --strip-components=1 -C /usr/local/bin \
    && rm /tmp/docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL --retry 3 "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" -o /usr/local/lib/docker/cli-plugins/docker-buildx \
    && echo "${BUILDX_SHA256}  /usr/local/lib/docker/cli-plugins/docker-buildx" | sha256sum -c - \
    && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-buildx

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
COPY sshd_config /etc/ssh/sshd_config
RUN chmod 0755 /entrypoint.sh /healthcheck.sh

EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/docker-init", "--", "/entrypoint.sh"]
