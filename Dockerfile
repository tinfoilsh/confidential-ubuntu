# syntax=docker/dockerfile:1.6
#
# Confidential Ubuntu: a measured, CVM-admin interactive workspace.
# The base is digest-pinned for attestation.
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

FROM ${BASE_IMAGE}
ENV container=docker LANG=en_US.UTF-8

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates=20260816ubuntu0.24.04.2 \
      pciutils \
      curl \
      git \
      less \
      vim-tiny \
      python3 \
      python3-venv \
      python3-pip \
      rsync htop tmux openssh-server iproute2 procps \
      systemd systemd-sysv dbus dbus-user-session libpam-systemd \
      bash-completion locales dnsutils iputils-ping util-linux \
    && locale-gen en_US.UTF-8 \
    && rm -f /usr/sbin/policy-rc.d \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*

ARG TELEPORT_VERSION=18.10.0
ARG TELEPORT_SHA256=a5a2f1ec1390d001b221353c047df858e068661d044cf00742943f7c618634db
RUN curl -fsSLo /tmp/teleport.tgz "https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-amd64-bin.tar.gz" \
    && echo "${TELEPORT_SHA256}  /tmp/teleport.tgz" | sha256sum -c - \
    && tar -xzf /tmp/teleport.tgz -C /usr/local/bin --strip-components=1 teleport/teleport \
    && rm /tmp/teleport.tgz

ARG TAILSCALE_VERSION=1.104.7
ARG TAILSCALE_SHA256=e56693ff74a64f2591b7e819c280635a100aae1ddfb0ef058fcd052b7cd8d16c
RUN curl -fsSLo /tmp/tailscale.tgz "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz" \
    && echo "${TAILSCALE_SHA256}  /tmp/tailscale.tgz" | sha256sum -c - \
    && tar -xzf /tmp/tailscale.tgz -C /usr/local/bin --strip-components=1 \
         "tailscale_${TAILSCALE_VERSION}_amd64/tailscale" "tailscale_${TAILSCALE_VERSION}_amd64/tailscaled" \
    && rm /tmp/tailscale.tgz

COPY --chmod=0755 entrypoint.sh /entrypoint
COPY rootfs/ /
RUN for script in /entrypoint /healthcheck.sh /usr/local/bin/tailscale-join /usr/local/bin/tinfoil-identity-token; do bash -n "$script" || exit 1; done

RUN systemctl disable ssh.socket \
    && systemctl enable ssh.service teleport.service tailscaled.service tailscale-join.service \
    && systemctl mask systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
         systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
         systemd-resolved.service systemd-timesyncd.service console-getty.service \
    && systemctl set-default multi-user.target \
    && rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && touch /etc/machine-id \
    && ln -s /etc/machine-id /var/lib/dbus/machine-id

EXPOSE 22
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/entrypoint"]
