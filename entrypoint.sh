#!/bin/bash
# Install the config's SSH keys for root, then hand off to systemd.
#
# SSH_KEYS is set inline in the config, so the authorized keys are measured
# and covered by the attestation rather than supplied at deploy time.
set -euo pipefail

# sshd serves the key the CVM attests, so clients can pin it from the attestation.
HOST_KEY=/run/tinfoil/keys/host-ssh/private_key.pem

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

configure() {
    umask 077
    printf '%s\n' "${SSH_KEYS:?SSH_KEYS is required}" > /run/authorized_keys
    ssh-keygen -lf /run/authorized_keys >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    umask 022
}

boot() {
    [[ $# == 0 ]] || { printf 'usage: /entrypoint\n' >&2; exit 2; }
    [[ $$ == 1 ]] || fail 'the entrypoint must run as PID 1'

    configure
    unset SSH_KEYS

    box_name=${WORKSPACE_HOSTNAME:-workspace}
    printf '%s\n' "$box_name" > /etc/hostname
    hostname "$box_name"

    ldconfig

    ssh-keygen -yf "$HOST_KEY" >/dev/null \
        || fail "attested host key $HOST_KEY is missing or unusable"
    exec /sbin/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
