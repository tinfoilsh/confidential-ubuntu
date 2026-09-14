# syntax=docker/dockerfile:1.6
#
# Confidential Ubuntu: an interactive workspace that runs as an ordinary
# measured workload. Bases are digest-pinned for attestation.
#
# Every CVM workload runs with cap_drop ALL and no-new-privileges, and the
# cap_add allowlist is only IPC_LOCK / NET_BIND_SERVICE / SYS_NICE. Hence:
# the login server listens on 2222 (port 22 would need CAP_NET_BIND_SERVICE),
# apt's privilege drop is disabled (it needs CAP_SETGID), and apt's cache is
# chowned to root at build time (without CAP_DAC_OVERRIDE root no longer
# bypasses the _apt-owned 0700 directories).
#
# Dropbear 2025.89 comes from the debug-toolbox image, already qualified
# against this policy. Ubuntu's own dropbear dies in initgroups(), and stock
# OpenSSH needs SETUID + SETGID + SYS_CHROOT.
ARG TOOLBOX_IMAGE=ghcr.io/tinfoilsh/tinfoil-debug-toolbox@sha256:7c6166c7db950757263ad955a76049630e0e8f9663cee01479b9b4e7a24ce7e6
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254

FROM ${TOOLBOX_IMAGE} AS toolbox

FROM ${BASE_IMAGE}
ARG VERSION=dev
LABEL org.opencontainers.image.title="confidential-ubuntu" \
      org.opencontainers.image.description="Ubuntu workspace for a Tinfoil confidential VM" \
      org.opencontainers.image.version="${VERSION}"
ENV DEBIAN_FRONTEND=noninteractive

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
      rsync htop tmux openssh-client \
    && rm -rf /var/lib/apt/lists/*

# See note 2 and 3 above: without these the workspace cannot install anything.
RUN printf 'APT::Sandbox::User "root";\n' > /etc/apt/apt.conf.d/99-tinfoil-no-sandbox && \
    chown -R root:root /var/cache/apt /var/lib/apt /var/log/apt && \
    chmod -R u+rwX /var/cache/apt /var/lib/apt /var/log/apt

COPY --from=toolbox /usr/local/bin/dropbear        /usr/local/bin/dropbear
COPY --from=toolbox /usr/local/bin/dropbearkey     /usr/local/bin/dropbearkey
COPY --from=toolbox /usr/local/bin/dropbearconvert /usr/local/bin/dropbearconvert
COPY --from=toolbox /usr/local/bin/scp             /usr/local/bin/scp
COPY --from=toolbox /usr/local/bin/sftp-server     /usr/local/bin/sftp-server

# Dropbear looks for the sftp subsystem at its compiled-in path.
RUN mkdir -p /usr/libexec && ln -sf /usr/local/bin/sftp-server /usr/libexec/sftp-server

# ~/.ssh is a symlink into the tmpfs so the image also runs with a read-only
# rootfs. /run is masked by the runtime tmpfs, so the entrypoint recreates it.
RUN rm -rf /root/.ssh && ln -s /run/ssh /root/.ssh

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod 0755 /entrypoint.sh /healthcheck.sh

EXPOSE 2222
ENTRYPOINT ["/entrypoint.sh"]
