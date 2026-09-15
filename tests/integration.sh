#!/bin/bash
# Run on a disposable Linux host with rootful Docker and cgroup v2.
# Commands passed to remote expand variables on the workspace.
# shellcheck disable=SC2016
set -Eeuo pipefail
image=${1:-confidential-ubuntu:test}
seed_image=${2:-$image}
name="workspace-test-$$"
volume="$name-disk"
test_dir=$(mktemp -d)
cleanup() {
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker volume rm "$volume" >/dev/null 2>&1 || true
    rm -rf "$test_dir"
}
trap cleanup EXIT
trap 'printf "Integration check failed at line %s\n" "$LINENO" >&2; docker logs --tail 60 "$name" >&2 || true' ERR
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/client"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/host"
export SSH_KEYS SSH_HOST_KEY SSH_TUNNEL_TARGET SSH_TUNNEL_KEY SSH_TUNNEL_HOST_KEY
SSH_KEYS=$(cat "$test_dir/client.pub")
SSH_HOST_KEY=$(cat "$test_dir/host")
SSH_TUNNEL_TARGET=ubuntu@127.0.0.1
SSH_TUNNEL_KEY=$(cat "$test_dir/client")
SSH_TUNNEL_HOST_KEY=$(cat "$test_dir/host.pub")
printf 'workspace-test %s\n' "$SSH_TUNNEL_HOST_KEY" > "$test_dir/known_hosts"
printf 'injected runtime file\n' > "$test_dir/gpu-mount"
docker volume create "$volume" >/dev/null
start() {
    docker run -d --name "$name" --privileged --cgroupns=private \
        --restart=on-failure --stop-signal SIGRTMIN+3 --stop-timeout 120 \
        --tmpfs /run:rw,nosuid,nodev,mode=755 \
        -v "$volume:/mnt/disk" \
        -v "$test_dir/gpu-mount:/usr/lib/workspace-runtime-test:ro" \
        -e SSH_KEYS -e SSH_HOST_KEY -e SSH_TUNNEL_TARGET -e SSH_TUNNEL_KEY -e SSH_TUNNEL_HOST_KEY \
        -p 127.0.0.1::2222 "${1:-$image}" >/dev/null
    port=$(docker port "$name" 2222/tcp | cut -d: -f2)
    wait_ssh
}
remote() {
    ssh -i "$test_dir/client" -p "$port" -o BatchMode=yes -o ConnectTimeout=2 \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=workspace-test \
        -o UserKnownHostsFile="$test_dir/known_hosts" -o LogLevel=ERROR \
        ubuntu@127.0.0.1 bash -se <<< "$*"
}
wait_ssh() {
    for _ in {1..120}; do
        port=$(docker port "$name" 2222/tcp 2>/dev/null | cut -d: -f2) || true
        if remote true 2>/dev/null; then return; fi
        sleep 1
    done
    docker logs "$name"
    return 1
}
start "$seed_image"
remote 'test "$(cat /proc/1/comm)" = systemd; sudo -n true; systemctl --user is-active default.target'
machine_id=$(remote 'cat /etc/machine-id')
hostname=$(remote hostname)
remote 'test "$(hostname)" = "$(cat /etc/hostname)"'
remote 'test -f "$(man -w bash)"; test -f "$(man -w ls)"; test ! -e /etc/dpkg/dpkg.cfg.d/docker-apt-speedup'
remote 'test "$(cat /usr/lib/workspace-runtime-test)" = "injected runtime file"; test -r /etc/resolv.conf'
remote 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx'
remote 'sudo systemctl enable --now nginx; echo persisted > ~/sentinel; sudo useradd -m test-user; sudo touch /home/test-user/sentinel'
remote 'sudo systemd-run --unit=workspace-limit --property=MemoryMax=32M sleep 300; test "$(systemctl show -p MemoryMax --value workspace-limit)" = 33554432'
remote 'sudo systemctl stop docker; sudo /healthcheck.sh; systemctl is-active ssh'
remote 'sudo systemctl start docker; timeout 90 sh -c "until docker info >/dev/null 2>&1; do sleep 1; done"; docker run --rm hello-world'
remote 'docker buildx version; mkdir -p /workspace/build-test; printf "FROM scratch\nLABEL workspace.test=true\n" > /workspace/build-test/Dockerfile; docker buildx build --load -t workspace-test /workspace/build-test'
# A second SSH listener is the reverse tunnel destination. This needs no external host.
remote 'sudo /usr/sbin/sshd -p 22
sudo timeout 30 bash -c '\''until ssh -T -i /run/workspace/tunnel_key -p 2022 -o BatchMode=yes -o ConnectTimeout=2 -o HostKeyAlias=127.0.0.1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/run/workspace/tunnel_known_hosts ubuntu@127.0.0.1 true 2>/dev/null; do sleep 1; done'\''
systemctl is-active workspace-tunnel'
remote 'sudo journalctl --sync; sudo journalctl -u nginx --no-pager | grep -q nginx'
# Recreate the outer container so none of its writable layer can survive.
docker stop "$name" >/dev/null
docker rm "$name" >/dev/null
start
test "$(remote 'cat /etc/machine-id')" = "$machine_id"
test "$(remote hostname)" = "$hostname"
remote 'dpkg-query -W nginx; systemctl is-enabled nginx; systemctl is-active nginx; test "$(cat ~/sentinel)" = persisted; id test-user; sudo test -f /home/test-user/sentinel'
remote 'test "$(cat /usr/lib/workspace-runtime-test)" = "injected runtime file"; sudo journalctl -u nginx --no-pager | grep -q nginx'
# A normal reboot is an explicit nonzero exit, which Docker restarts.
remote 'sudo reboot' || true
for _ in {1..120}; do
    if [ "$(docker inspect -f '{{.RestartCount}}' "$name")" -gt 0 ]; then break; fi
    sleep 1
done
[ "$(docker inspect -f '{{.RestartCount}}' "$name")" -gt 0 ]
wait_ssh
remote 'test "$(cat ~/sentinel)" = persisted; systemctl is-active nginx'
remote 'echo retained > /workspace/reset-sentinel; docker volume create reset-sentinel; sudo workspace-reset --on-next-boot; sudo reboot' || true
for _ in {1..120}; do
    if [ "$(docker inspect -f '{{.RestartCount}}' "$name")" -gt 1 ]; then break; fi
    sleep 1
done
[ "$(docker inspect -f '{{.RestartCount}}' "$name")" -gt 1 ]
wait_ssh
remote 'test ! -f ~/sentinel; ! id test-user; test "$(cat /workspace/reset-sentinel)" = retained; sudo sh -c "test -f /mnt/disk/rootfs.previous.*/home/ubuntu/sentinel"; timeout 90 sh -c "until docker info >/dev/null 2>&1; do sleep 1; done"; docker volume inspect reset-sentinel >/dev/null'
printf 'Workspace integration checks passed.\n'
