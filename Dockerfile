# syntax=docker/dockerfile:1.6
#
# Confidential Ubuntu: a measured, CVM-admin interactive workspace.
# The base is digest-pinned for attestation.
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254

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

COPY --chmod=0755 entrypoint.sh /entrypoint
COPY rootfs/ /
RUN for script in /entrypoint /healthcheck.sh; do bash -n "$script" || exit 1; done

RUN systemctl disable ssh.socket \
    && systemctl enable ssh.service teleport.service \
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
