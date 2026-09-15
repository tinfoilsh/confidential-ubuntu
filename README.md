# Confidential Ubuntu

An Ubuntu root workspace with its own Docker daemon inside a confidential VM.
`docker ps` shows your containers, not the SSH wrapper or the CVM's services.

## Deploy

Run the **Tinfoil Release** workflow with a version (e.g. `v0.1.0`), then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

Requires a CVM image and hosting/measurement validators that support `cvm_admin`.
Update `cvm-version` to that release before publishing; older images reject it.

## Connect

    export TINFOIL_TUNNEL_API_KEY=...  # inference key, not the admin login key
    tinfoil ssh workspace

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step. `scp`, `sftp`, `rsync` and
`ssh -L` port forwarding all work, and it drops you at a normal bash prompt.

## Configure

Set two variables on the deployment: `SSH_AUTHORIZED_KEYS`, your public key,
which is required — without it the workspace exits rather than coming up
healthy; and optionally `SSH_HOST_KEY`, an OpenSSH PEM private key, for a host
identity that stays the same across reboots.

To resize the box or attach a GPU, edit `cpus`, `memory` and `gpus` in
`tinfoil-config.yml`, and add `runtime: nvidia` to the container.

## Docker and storage

Run `docker build` and `docker run` normally. The inner daemon listens only on
`/var/run/docker.sock`; no Docker TCP API or host Docker socket is exposed.
It uses native OverlayFS on a separate tmpfs, cgroup v2 with cgroupfs, and
nftables NAT. No FUSE or dynamically loaded kernel modules are needed. Docker
Swarm/overlay networking and arbitrary kernel-module-dependent features are not
supported by this setup. Nested `--network host` means the workspace's network
namespace, not the CVM host's.

To reach a nested web service, publish it inside the workspace with
`docker run -p 127.0.0.1:8080:80 …`, then connect with
`tinfoil ssh workspace -- -L 8080:127.0.0.1:8080`. Only SSH is published in the
measured outer config; the shim tunnel is unchanged.

Inner Docker images, containers, build cache, and named volumes are RAM-backed
and reset whenever the workspace stops/restarts. The workspace's OS changes
survive container restart but not recreation or CVM reboot. Neither is durable
storage. For persistent customer files, declare an optional attached volume and
mount it at `/workspace`; after unlocking, nested containers can use
`-v /workspace:/data`. Do not mount persistent storage at `/var/lib/docker`.

The entrypoint waits for Docker before starting SSH. If either daemon exits,
it terminates the other and exits; the measured restart policy restarts the
workspace. Docker gets 10 seconds to stop nested containers within the outer
30-second stop timeout. `docker-init` reaps orphaned processes.

## Trust model

This is one CVM and one kernel, not an additional security boundary. The measured
`cvm_admin` flag grants privileged root, disables no-new-privileges, and defaults
the rootfs to writable. It does not mount `/host` or share host PID/network
namespaces, but customers still have CVM-wide authority. Do not put other tenants
or secrets they must not access in the same CVM. Kernel module loading stays
locked and the verified CVM root disk stays read-only.

SSH credentials retain the existing external-variable flow: `cvm_admin` does not
attest those values or add sealed SSH-key provisioning. Supply SSH authorization
from an owner-controlled source before entrusting the workspace with secrets.

## Runtime smoke test

Run `bash tests/smoke.sh` inside a **fresh disposable CVM workspace**, against its
inner daemon, not against your machine's Docker socket. It checks root/NNP,
locked modules, tmpfs storage, cgroup resource limits, privileged mounts, builds,
DNS/Internet access, bind mounts, and nested port publishing. It leaves a web
server at `127.0.0.1:8080` for the SSH-forwarding check above. Stop the disposable
workspace afterward to discard its test Docker state.

Also qualify daemon failure/restart and shutdown on the target CVM image; stock
host DinD tests do not exercise the CVM's module lock or guest firewall. An
authenticated `tinfoil ssh` test requires a valid inference API key.
