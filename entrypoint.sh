#!/bin/bash
# Confidential Ubuntu workspace: install credentials and supervise SSH + Docker.
#
# SSH_AUTHORIZED_KEYS (required) public keys, newline separated. Supplied per
#                     deployment through the external config.
# SSH_HOST_KEY        (optional) an OpenSSH PEM private key, for a stable host
#                     identity. Omitted, one is generated each boot.
# SSH_PORT            (optional) defaults to 2222.
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

# Docker's state sits beside /workspace, not inside it: a nested bind of /workspace is recursive.
mkdir -p /mnt/disk/workspace /workspace
mountpoint -q /workspace || mount --bind /mnt/disk/workspace /workspace
sysctl -w net.ipv4.ip_forward=1

# cgroup v2 forbids processes in an internal node with domain controllers.
# The privileged container has its own writable cgroup namespace; keep our
# supervisor/daemons in a leaf so Docker can create sibling workload cgroups.
mkdir -p /sys/fs/cgroup/init
read -ra controllers < /sys/fs/cgroup/cgroup.controllers
for attempt in {1..10}; do
    mapfile -t pids < /sys/fs/cgroup/cgroup.procs
    for pid in "${pids[@]}"; do
        echo "$pid" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    # A concurrent Docker exec/healthcheck may have entered the old cgroup.
    if printf '+%s ' "${controllers[@]}" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null; then break; fi
    if [ "$attempt" = 10 ]; then
        echo "confidential-ubuntu: cannot delegate cgroup v2 controllers" >&2
        exit 1
    fi
    sleep 0.1
done

docker_pid=
ssh_pid=
cleanup() {
    trap - EXIT
    for pid in "$ssh_pid" "$docker_pid"; do
        if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; fi
    done
    wait || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

dockerd &
docker_pid=$!
for attempt in {1..60}; do
    if ! kill -0 "$docker_pid" 2>/dev/null; then
        echo "confidential-ubuntu: Docker exited during startup" >&2
        exit 1
    fi
    if timeout 2 docker --host unix:///var/run/docker.sock info >/dev/null 2>&1; then break; fi
    sleep 1
done
if ! timeout 2 docker --host unix:///var/run/docker.sock info >/dev/null 2>&1; then
    echo "confidential-ubuntu: Docker did not become ready" >&2
    exit 1
fi

# -s and -g disable password authentication entirely, including for root.
/usr/local/bin/dropbear -F -E -s -g -r "$key_file" -p "$port" &
ssh_pid=$!
if wait -n "$docker_pid" "$ssh_pid"; then exit 1; else exit "$?"; fi
