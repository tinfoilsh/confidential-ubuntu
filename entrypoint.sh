#!/bin/bash
# Install the measured login keys and the attested SSH host key, then hand off to systemd.
#
# SSH_KEYS is set inline in tinfoil-config.yml, so the authorized key is
# measured and covered by the attestation rather than supplied at deploy time.
# The host key is the attested-keys entry named host-ssh (ecdsa-p256 PKCS#8).
set -euo pipefail

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

install_login_keys() {
    umask 077
    printf '%s\n' "${SSH_KEYS:?SSH_KEYS is required}" > /run/authorized_keys
    ssh-keygen -lf /run/authorized_keys >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    unset SSH_KEYS
    umask 022
}

# Copy the platform-granted host-ssh key out of /run so sshd can use a root-owned 0600 HostKey.
# Do not generate an unattested host key.
install_attested_host_key() {
    local src=/run/tinfoil/keys/host-ssh/private_key.pem
    local dest=/etc/ssh/ssh_host_attested_key
    [[ -r $src ]] || fail "attested host-ssh key is missing at $src"
    install -m 0600 "$src" "$dest"
    ssh-keygen -y -f "$dest" >"${dest}.pub" || fail 'attested host-ssh key is not a usable SSH host key'
    chmod 0644 "${dest}.pub"
}

boot() {
    [[ $# == 0 ]] || { printf 'usage: /entrypoint\n' >&2; exit 2; }
    [[ $$ == 1 ]] || fail 'the entrypoint must run as PID 1'

    install_login_keys

    box_name=${WORKSPACE_HOSTNAME:-workspace}
    printf '%s\n' "$box_name" > /etc/hostname
    hostname "$box_name"

    ldconfig

    install_attested_host_key
    exec /sbin/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
