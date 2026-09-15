#!/bin/bash
# Both services must be ready.
timeout 2 docker --host unix:///var/run/docker.sock info >/dev/null 2>&1 || exit 1
exec timeout 2 bash -c "</dev/tcp/127.0.0.1/${SSH_PORT:-2222}"
