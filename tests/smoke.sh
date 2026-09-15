#!/bin/bash
# Run once in a fresh disposable CVM workspace, against its inner daemon.
set -euo pipefail
test "$(id -u)" = 0
grep -Eq '^NoNewPrivs:[[:space:]]+0$' /proc/1/status
test "$(docker ps -aq | wc -l)" = 0
test ! -e /host
test "$(cat /proc/sys/kernel/modules_disabled)" = 1
test "$(findmnt -n -o FSTYPE /workspace)" = ext4
test "$(docker info --format '{{.DockerRootDir}}')" = /mnt/disk/docker
docker info --format 'driver={{.Driver}} cgroup={{.CgroupDriver}} v{{.CgroupVersion}}'
if ss -lnt | grep -Eq ':(2375|2376)\b'; then
  echo 'Docker TCP API must not be exposed' >&2
  exit 1
fi
docker run --rm --memory 64m --cpus 0.5 --pids-limit 32 alpine:3.22 sh -ec '
  test "$(id -u)" = 0
  test "$(cat /sys/fs/cgroup/memory.max)" = 67108864
  test "$(cat /sys/fs/cgroup/pids.max)" = 32
  test "$(cat /sys/fs/cgroup/cpu.max)" = "50000 100000"
  wget -qO /dev/null https://example.com
'
docker run --rm --privileged alpine:3.22 sh -ec '
  mount -t tmpfs tmpfs /mnt
  touch /mnt/root-can-mount
  umount /mnt
'
docker build --progress plain -t dind-smoke-build - <<'DOCKERFILE'
FROM alpine:3.22
RUN apk add --no-cache busybox-extras && wget -qO /dev/null https://example.com && echo build-ok > /built
CMD ["cat", "/built"]
DOCKERFILE
test "$(docker run --rm dind-smoke-build)" = build-ok
mkdir -p /workspace/dind-smoke
printf bind-ok > /workspace/dind-smoke/input
docker run --rm -v /workspace/dind-smoke:/data alpine:3.22 sh -ec '
  test "$(cat /data/input)" = bind-ok
  echo inner-write > /data/output
'
test "$(cat /workspace/dind-smoke/output)" = inner-write
docker network create dind-smoke-net
docker run -d --name dind-smoke-web --network dind-smoke-net \
  -p 127.0.0.1:8080:8080 dind-smoke-build sh -ec \
  'mkdir /www; echo nested-http-ok > /www/index.html; exec httpd -f -p 8080 -h /www'
docker run --rm --network dind-smoke-net alpine:3.22 sh -ec \
  'test "$(wget -qO- http://dind-smoke-web:8080)" = nested-http-ok; wget -qO /dev/null https://example.com'
test "$(curl -fsS http://127.0.0.1:8080)" = nested-http-ok
if docker ps -a --format '{{.Names}}' | grep -Eq '^(workspace|tinfoil-debug-toolbox)$'; then
  echo 'Inner daemon must not list the outer containers' >&2
  exit 1
fi
/healthcheck.sh
echo DIND_SMOKE_PASS
