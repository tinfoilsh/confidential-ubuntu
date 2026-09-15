#!/bin/bash
# Confidential Ubuntu workspace: install credentials and supervise SSH + Docker.
#
# SSH_KEYS            (required) public keys, newline separated. Supplied per
#                     deployment through the external config.
# SSH_HOST_KEY        (required) an OpenSSH private key, supplied as a secret
#                     for a stable host identity.
# SSH_TUNNEL_TARGET   (optional) user@host given a reverse tunnel that publishes
#                     this sshd there on 127.0.0.1:SSH_TUNNEL_PORT (default 2022).
#                     SSH_TUNNEL_KEY is the client's OpenSSH private key and
#                     SSH_TUNNEL_HOST_KEY the target's public host key.
set -euo pipefail

run_dir=/run/ssh

mkdir -p "$run_dir" /run/sshd
chmod 0700 "$run_dir"

# Require a usable public key before starting the workspace.
printf '%s\n' "${SSH_KEYS:-}" > "$run_dir/authorized_keys"
chmod 0600 "$run_dir/authorized_keys"
ssh-keygen -lf "$run_dir/authorized_keys" >/dev/null 2>&1 || {
    echo "confidential-ubuntu: SSH_KEYS has no usable public key" >&2
    exit 1
}

printf '%s\n' "$SSH_HOST_KEY" > "$run_dir/host_key"
chmod 0600 "$run_dir/host_key"

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

cleanup() {
    trap - EXIT
    for pid in $(jobs -pr); do
        kill -TERM "$pid" 2>/dev/null || true
    done
    wait || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

while sleep 5; do sync; done &

dockerd --data-root=/mnt/disk/docker --storage-driver=overlay2 \
    --feature=containerd-snapshotter=false --exec-opt native.cgroupdriver=cgroupfs \
    --firewall-backend=nftables --ip6tables=false --shutdown-timeout=10 &
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

/usr/sbin/sshd -D -e &
ssh_pid=$!
if [ -n "${SSH_TUNNEL_TARGET:-}" ]; then
    printf '%s\n' "$SSH_TUNNEL_KEY" > "$run_dir/tunnel_key"
    chmod 0600 "$run_dir/tunnel_key"
    printf '%s %s\n' "${SSH_TUNNEL_TARGET#*@}" "$SSH_TUNNEL_HOST_KEY" > "$run_dir/tunnel_known_hosts"
    while sleep 5; do
        ssh -NT -i "$run_dir/tunnel_key" -o UserKnownHostsFile="$run_dir/tunnel_known_hosts" \
            -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
            -R "127.0.0.1:${SSH_TUNNEL_PORT:-2022}:127.0.0.1:2222" "$SSH_TUNNEL_TARGET" || true
    done &
fi
if wait -n "$docker_pid" "$ssh_pid"; then exit 1; else exit "$?"; fi
