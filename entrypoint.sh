#!/bin/bash
# Install the config's SSH keys for root, then hand off to systemd.
#
# SSH_KEYS is set inline in the config, so the authorized keys are measured
# and covered by the attestation rather than supplied at deploy time.
set -euo pipefail

# sshd serves the key the CVM attests, so clients can pin it from the attestation.
HOST_KEY=/run/tinfoil/keys/host-ssh/private_key.pem

# Teleport admits this boot through a join token bound to this attested key.
TELEPORT_JOIN_KEY=/run/tinfoil/keys/teleport-join
TELEPORT_CONFIG=/etc/teleport.yaml
TELEPORT_TOKEN_DIGEST_CHARS=16

# tailscale-join passes these options to the tailnet login; their presence enables Tailscale.
TAILSCALE_UP_ARGS_FILE=/run/tailscale-up-args

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

configure() {
    umask 077
    printf '%s\n' "${SSH_KEYS:?SSH_KEYS is required}" > /run/authorized_keys
    ssh-keygen -lf /run/authorized_keys >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    [[ -z ${TELEPORT_PROXY:-} ]] || configure_teleport
    [[ -z ${TAILSCALE_UP_ARGS:-} ]] || configure_tailscale
    umask 022
}

configure_tailscale() {
    case $TAILSCALE_UP_ARGS in
        *auth-key*|*authkey*|*client-secret*)
            fail 'TAILSCALE_UP_ARGS must not carry credentials; send the auth key to tailscale-join' ;;
    esac
    printf '%s\n' "$TAILSCALE_UP_ARGS" > "$TAILSCALE_UP_ARGS_FILE"
}

configure_teleport() {
    local proxy
    proxy=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$TELEPORT_PROXY") \
        || fail 'could not encode TELEPORT_PROXY'
    cat > "$TELEPORT_CONFIG" <<EOF
version: v3
teleport:
  proxy_server: $proxy
  join_params:
    method: bound_keypair
    bound_keypair:
      static_key_path: $TELEPORT_JOIN_KEY/private_key.pem
ssh_service:
  enabled: true
auth_service:
  enabled: false
proxy_service:
  enabled: false
EOF
    /usr/local/bin/teleport configure --test "$TELEPORT_CONFIG" || fail 'TELEPORT_PROXY is invalid'
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
    if [[ -e $TELEPORT_CONFIG ]]; then
        # The token name is derivable from the quote alone: the key's SPKI digest.
        spki_sha256=$(openssl pkey -pubin -in "$TELEPORT_JOIN_KEY/public_key.pem" -outform DER | sha256sum)
        printf 'tinfoil-%s\n' "${spki_sha256:0:TELEPORT_TOKEN_DIGEST_CHARS}" > /run/teleport-token
    fi
    exec /sbin/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
