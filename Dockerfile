# syntax=docker/dockerfile:1.6
#
# Confidential Ubuntu: a measured, CVM-admin interactive workspace.
# The base is digest-pinned for attestation.
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254

FROM ${BASE_IMAGE}
ENV container=docker LANG=en_US.UTF-8

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
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
      cryptsetup e2fsprogs \
    && locale-gen en_US.UTF-8 \
    && rm -f /usr/sbin/policy-rc.d \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 entrypoint.sh /entrypoint
COPY rootfs/ /
RUN for script in /entrypoint /healthcheck.sh; do bash -n "$script" || exit 1; done

RUN systemctl disable ssh.socket \
    && systemctl enable ssh.service \
    && systemctl mask systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
         systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
         systemd-resolved.service systemd-timesyncd.service console-getty.service \
    && systemctl set-default multi-user.target \
    && rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && touch /etc/machine-id \
    && ln -s /etc/machine-id /var/lib/dbus/machine-id

EXPOSE 2222
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/entrypoint"]
