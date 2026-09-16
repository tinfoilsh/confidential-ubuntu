#!/bin/bash
set -euo pipefail
systemctl is-active --quiet ssh.service
exec timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/22'
