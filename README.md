# Confidential Ubuntu

An Ubuntu root workspace with its own Docker daemon inside a confidential VM.
`docker ps` shows your containers, not the SSH wrapper or the CVM's services.

## Deploy

Run the **Tinfoil Release** workflow with a version (e.g. `v0.1.0`), then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

Requires a host whose tinfoild accepts `cvm_admin` (tinfoild PR #188 or later).

## Connect

    export TINFOIL_TUNNEL_API_KEY=...  # inference key, not the admin login key
    tinfoil ssh workspace

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step. `scp`, `sftp`, `rsync` and
`ssh -L` port forwarding all work, and it drops you at a normal bash prompt.

### Without the tunnel

Set `SSH_TUNNEL_TARGET` to `user@host` of a box the workspace can reach, with
`SSH_TUNNEL_KEY` a client key that box accepts and `SSH_TUNNEL_HOST_KEY` its
public host key, and the workspace keeps a reverse tunnel open that publishes
its sshd on that box at `127.0.0.1:2022` (`SSH_TUNNEL_PORT` to change). Only
the host-key fingerprint then vouches for the workspace, so restrict the key
on the box: `restrict,port-forwarding,permitlisten="127.0.0.1:2022"`.

## Configure

Set `SSH_KEYS` on the deployment to your public key, or several public keys
separated by newlines. The workspace exits if none is usable.

Set two secrets. `SSH_HOST_KEY` is an OpenSSH private key and becomes the
SSH host identity, the same one across reboots:

    ssh-keygen -t ed25519 -N '' -f hostkey -C ''
    tinctl secret create SSH_HOST_KEY --value-file hostkey

`WORKSPACE_VOLUME_KEY` is 64 random bytes, base64-encoded
(`head -c 64 /dev/urandom | base64 -w0`). It is the only key to the disk;
lose it and the data is unrecoverable.

Both are declared secrets, so an unset one fails the boot instead of quietly
starting a workspace with an improvised identity or an unopenable disk.

To resize the box or attach a GPU, edit `cpus`, `memory` and `gpus` in
`tinfoil-config.yml`, and add `runtime: nvidia` to the container.

## Docker and storage

Run `docker build` and `docker run` normally. The inner daemon listens only on
`/var/run/docker.sock`; no Docker TCP API or host Docker socket is exposed.
It uses native OverlayFS on the disk, cgroup v2 with cgroupfs, and
nftables NAT. No FUSE or dynamically loaded kernel modules are needed. Docker
Swarm/overlay networking and arbitrary kernel-module-dependent features are not
supported by this setup. Nested `--network host` means the workspace's network
namespace, not the CVM host's.

To reach a nested web service, publish it inside the workspace with
`docker run -p 127.0.0.1:8080:80 …`, then connect with
`tinfoil ssh workspace -- -L 8080:127.0.0.1:8080`. Only SSH is published in the
measured outer config; the shim tunnel is unchanged.

`/workspace` and Docker's images, containers, build cache, and named volumes
live on one encrypted, integrity-protected disk that boot unlocks with
`WORKSPACE_VOLUME_KEY` before the container starts, formatted on first boot and
reopened on every later one. Changes to the OS itself, such as apt installs,
survive a container restart but not a CVM reboot. The host picks the disk's
size unless the volume declares `size:`, and the size is fixed at first launch.
Nested containers use the disk with `-v /workspace:/data`; Docker's own state
sits beside that tree, not inside it.

The entrypoint waits for Docker before starting SSH. If either daemon exits,
it terminates the other and exits; the measured restart policy restarts the
workspace, and Docker gets 10 seconds to stop nested containers within the
outer 30-second stop timeout. The disk syncs every five seconds. Stopping the
deployment is a hard power-off and may lose writes since the last sync.
`docker-init` reaps orphaned processes.

## Trust model

This is one CVM and one kernel, not an additional security boundary. The measured
`cvm_admin` flag grants privileged root, disables no-new-privileges, and defaults
the rootfs to writable. It does not mount `/host` or share host PID/network
namespaces, but customers still have CVM-wide authority. Do not put other tenants
or secrets they must not access in the same CVM. Kernel module loading stays
locked and the verified CVM root disk stays read-only.

SSH authorization comes from the external `SSH_KEYS` variable. `cvm_admin` does
not attest its value. Supply it from an owner-controlled source before entrusting
the workspace with secrets.
