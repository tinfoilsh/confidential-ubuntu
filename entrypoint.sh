#!/bin/bash
# Confidential Ubuntu workspace: install credentials, then hand off to dropbear.
#
# SSH_AUTHORIZED_KEYS (required) public keys, newline separated. Supplied per
#                     deployment through the external config.
# SSH_HOST_KEY        (optional) an OpenSSH PEM private key, for a stable host
#                     identity. Omitted, one is generated each boot.
# SSH_PORT            (optional) defaults to 2222. Below 1024 would need
#                     CAP_NET_BIND_SERVICE, which the CVM drops.
set -euo pipefail

port="${SSH_PORT:-2222}"
run_dir=/run/ssh
key_file="$run_dir/dropbear_ed25519_host_key"

mkdir -p "$run_dir"
chmod 0700 "$run_dir"

# Fail loudly rather than boot a workspace nobody can reach: given a malformed
# key dropbear starts happily and just turns everyone away.
printf '%s\n' "${SSH_AUTHORIZED_KEYS:-}" | grep -qE '^(ssh-(ed25519|rsa) |ecdsa-sha2-|sk-)' || {
    echo "confidential-ubuntu: SSH_AUTHORIZED_KEYS has no usable public key" >&2
    exit 1
}
printf '%s\n' "$SSH_AUTHORIZED_KEYS" > "$run_dir/authorized_keys"
chmod 0600 "$run_dir/authorized_keys"

if [ -n "${SSH_HOST_KEY:-}" ]; then
    printf '%s\n' "$SSH_HOST_KEY" > "$run_dir/hostkey.pem"
    chmod 0600 "$run_dir/hostkey.pem"
    /usr/local/bin/dropbearconvert openssh dropbear "$run_dir/hostkey.pem" "$key_file" >/dev/null 2>&1 || {
        echo "confidential-ubuntu: SSH_HOST_KEY is not an OpenSSH PEM private key" >&2
        exit 1
    }
    rm -f "$run_dir/hostkey.pem"
else
    /usr/local/bin/dropbearkey -t ed25519 -f "$key_file" >/dev/null 2>&1
fi
chmod 0600 "$key_file"

# Logged so an ephemeral host key can still be pinned by a client that has just
# verified the enclave's attestation.
/usr/local/bin/dropbearkey -y -f "$key_file" | sed -n 's/^Fingerprint: /confidential-ubuntu: host key /p'

# -s and -g disable password authentication entirely, including for root.
exec /usr/local/bin/dropbear -F -E -s -g -r "$key_file" -p "$port"
