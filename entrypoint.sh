#!/bin/bash
# Install the deployed SSH key for root, then hand off to systemd.
#
# SSH_KEYS is set inline in tinfoil-config.yml, so the authorized key is
# measured and covered by the attestation rather than supplied at deploy time.
set -euo pipefail

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

boot() {
    [[ $# == 0 ]] || { printf 'usage: /entrypoint\n' >&2; exit 2; }
    [[ $$ == 1 ]] || fail 'the entrypoint must run as PID 1'

    umask 077
    printf '%s\n' "${SSH_KEYS:?SSH_KEYS is required}" > /run/authorized_keys
    ssh-keygen -lf /run/authorized_keys >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    unset SSH_KEYS
    umask 022

    box_name=${WORKSPACE_HOSTNAME:-workspace}
    printf '%s\n' "$box_name" > /etc/hostname
    hostname "$box_name"

    ldconfig

    ssh-keygen -A
    exec /sbin/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
