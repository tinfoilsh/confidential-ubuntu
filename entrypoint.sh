#!/bin/bash
# Install the deployed SSH key for root, then hand off to systemd.
#
# SSH_KEYS is set inline in tinfoil-config.yml, so the authorized key is
# measured and covered by the attestation rather than supplied at deploy time.
#
# sshd needs a host key to start, so one is generated on each boot. Nothing
# checks it: `tinfoil ssh` verifies the enclave's attestation when it opens the
# tunnel, then runs ssh with StrictHostKeyChecking=no, because the attested
# channel has already pinned the peer.
set -euo pipefail

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

boot() {
    [[ $# == 0 ]] || { printf 'usage: /entrypoint\n' >&2; exit 2; }
    [[ $$ == 1 ]] || fail 'the entrypoint must run as PID 1'

    umask 077
    install -d -m 0700 /root/.ssh
    printf '%s\n' "${SSH_KEYS:?SSH_KEYS is required}" > /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
    ssh-keygen -lf /root/.ssh/authorized_keys >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    unset SSH_KEYS
    umask 022

    # Docker names the box after the container ID, which makes for an ugly
    # shell prompt. systemd applies /etc/hostname at boot; the sethostname
    # call covers the window before it gets there.
    box_name=${WORKSPACE_HOSTNAME:-workspace}
    printf '%s\n' "$box_name" > /etc/hostname
    hostname "$box_name"

    # The NVIDIA runtime mounts this boot's driver libraries into the image,
    # after it was built, so the linker cache has to be rebuilt to find them.
    ldconfig

    ssh-keygen -A
    exec /sbin/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
