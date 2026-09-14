#!/bin/bash
# Healthy once dropbear accepts a TCP connection on its listen port.
exec timeout 3 bash -c "</dev/tcp/127.0.0.1/${SSH_PORT:-2222}"
