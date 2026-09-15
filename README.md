# Confidential Ubuntu

Ubuntu 24.04 with systemd, a persistent encrypted root filesystem, and a private
Docker daemon inside a confidential VM. The default deployment has 32 CPUs,
512 GiB RAM, and eight GPUs. SSH logs in as `ubuntu`, with passwordless sudo.

## Deploy and connect

Run the **Tinfoil Release** workflow with a version such as `v0.1.0`, then deploy
by repo and tag from the dashboard or with:

```sh
tinctl deploy tinfoilsh/confidential-ubuntu
export TINFOIL_TUNNEL_API_KEY=...
tinfoil ssh workspace -l ubuntu
```

The API key is an inference key. The connection uses the enclave's attested TLS
tunnel. `scp`, `sftp`, `rsync`, and SSH forwarding work through the same transport.
The CLI currently defaults to root, so include `-l ubuntu`. Direct root SSH login
and password authentication are disabled.

The image requires the `cvm_admin` runtime profile, cgroup v2, and an executable
encrypted volume.

## Credentials

Set `SSH_KEYS` on the deployment to your public key, or several public keys
separated by newlines. Boot fails if no usable key is supplied. Each boot installs
these keys in `/home/ubuntu/.ssh/tinfoil_authorized_keys`. You can also manage
`~/.ssh/authorized_keys` normally; boot leaves that file alone. Other users use
their own SSH key files.

Set two secrets. `SSH_HOST_KEY` is an unencrypted OpenSSH private key used as the
stable SSH host identity:

```sh
ssh-keygen -t ed25519 -N '' -f hostkey -C ''
tinctl secret create SSH_HOST_KEY --value-file hostkey
```

`WORKSPACE_VOLUME_KEY` is 64 random bytes, base64-encoded:

```sh
head -c 64 /dev/urandom | base64 -w0
```

The volume key is the only key to the disk. Losing it makes the data unrecoverable.
Host keys and optional tunnel credentials stay in `/run`, which is tmpfs.

For a reverse SSH tunnel, set `SSH_TUNNEL_TARGET` to `user@host`,
`SSH_TUNNEL_KEY` to a client private key, and `SSH_TUNNEL_HOST_KEY` to the target's
public host key. The `workspace-tunnel.service` publishes SSH on the target at
`127.0.0.1:2022`, configurable with `SSH_TUNNEL_PORT`. Restrict that target's key
with `restrict,port-forwarding,permitlisten="127.0.0.1:2022"`. Connections through
this route rely on the SSH host identity rather than enclave attestation.

## Using Ubuntu

The workspace runs systemd as PID 1. Packages can install and enable services,
and PAM/logind provide normal login sessions and `systemctl --user`.

```sh
sudo apt update
sudo apt install nginx
sudo systemctl enable --now nginx
systemctl status nginx
sudo journalctl -u nginx
sudo adduser alice
```

SSH and Docker have independent services. Docker can fail or be stopped while
SSH stays available for repairs. The deployment health check tests SSH, so inspect
`systemctl --failed` and `journalctl -u docker` for application and Docker failures.
The journal persists on the encrypted disk, with a 1 GiB limit and 30-day retention.

The image includes sudo, manual pages, bash completion, a UTF-8 locale, DNS tools,
ping, cron, logrotate, Git, Python, tmux, and htop. Kernel and physical device
management remain the CVM's responsibility. Device management, network management,
and time synchronization services are disabled inside the workspace.

## Persistent storage and image updates

On first boot, the entrypoint copies Ubuntu to `/mnt/disk/rootfs`, then switches
the workspace's root to it before executing systemd. Later boots reuse that OS.
Apt installs, `/etc`, user accounts, home directories, service enablement, and logs
survive container recreation and CVM reboot. Machine identity and hostname are
created once. First boot publishes the root only after the copy completes.

The entrypoint enables setuid on the OS root's bind mount so sudo works on the
otherwise nosuid encrypted volume. It carries runtime mounts into that root,
including `/dev`, cgroups, DNS configuration, Tinfoil's public files, and NVIDIA
driver mounts.
`/run` remains temporary. `/workspace` binds `/mnt/disk/workspace`, and Docker's
state lives separately at `/mnt/disk/docker`. Existing workspace and Docker data
are retained when adopting this layout. Existing root-owned files may need sudo
or an explicit ownership change before the `ubuntu` user can edit them.

A new image release supplies the bootstrap and the seed for new installations.
It does not overwrite an existing OS. Update an installed OS with apt. To replace
it with the currently deployed image's seed:

```sh
sudo workspace-reset --on-next-boot
sudo reboot
```

The next boot archives the previous OS as `/mnt/disk/rootfs.previous.*` and seeds
a fresh root. This resets OS settings and home directories; `/workspace` and
Docker data stay in place. Archives use disk space and can be removed manually
after recovering anything needed from them. The disk size is fixed at first
launch and follows the host default unless the volume declares `size:`.

## Docker and GPUs

```sh
docker info
docker run --rm hello-world
nvidia-smi
```

The inner daemon listens only on `/var/run/docker.sock`. Its images, containers,
build cache, and named volumes persist on the encrypted disk. It uses OverlayFS,
the systemd cgroup driver, and nftables NAT. Logs for new containers use Docker's
rotating `local` driver. Existing containers retain their logging settings.

The measured config requests eight GPUs and passes all of them to the workspace
through `runtime: nvidia`. Change `cpus`, `memory`, and `gpus` in
`tinfoil-config.yml` to resize the deployment. GPU access inside nested Docker
containers additionally requires NVIDIA Container Toolkit configuration in the
inner daemon. Swarm overlay networking and features requiring additional kernel
modules remain unsupported. Nested `--network host` uses the workspace namespace.

Only SSH is published. To reach a nested web service, use:

```sh
docker run -p 127.0.0.1:8080:80 nginx
tinfoil ssh workspace -l ubuntu -- -L 8080:127.0.0.1:8080
```

## Reboot

`sudo reboot` shuts down services and restarts the Ubuntu workspace with its
persistent OS on the existing CVM kernel. It exits with status 133, which the
outer `on-failure` restart policy restarts. This does not replace or reboot the
CVM kernel.

## Trust model

The image digest and measured config describe the bootstrap and initial OS.
Subsequent apt installs and configuration changes are mutable state on the
encrypted disk; attestation does not describe their current contents.

The workspace shares one CVM and kernel with the runtime. `cvm_admin` grants
CVM-wide authority. It does not share host PID or network namespaces or expose a
host Docker socket. Use one tenant per CVM. Kernel module loading remains locked,
and the verified CVM root disk remains read-only.

`SSH_KEYS` comes from external deployment configuration, so its value is not
covered by `cvm_admin` attestation. Supply it from an owner-controlled source.

## Validation

`entrypoint.sh` stages credentials, seeds the persistent OS, and transfers runtime
mounts using Ubuntu's `findmnt`, `mount`, and `pivot_root` tools. The `rootfs/`
directory holds the SSH, systemd, Docker, and sudo configuration, along with the
reset command, health check, and final boot helper. Its paths match their locations
in the image; the Dockerfile copies the directory into `/`. The helper installs
login keys, refreshes the GPU library cache, and adds a runtime Docker service
override to enable IPv4 forwarding before Docker starts. Each boot carries the
deployed image's helper into `/run`, including when reusing an older persistent OS.

Build the image and run the bootstrap checks, then test the full lifecycle on a
disposable Linux Docker host:

```sh
docker build -t confidential-ubuntu:test .
docker run --rm --entrypoint /bin/bash -v "$PWD/tests:/tests:ro" confidential-ubuntu:test /tests/bootstrap.sh
sudo bash tests/integration.sh confidential-ubuntu:test
```

The bootstrap checks cover mount selection and escaped paths, credential and
tunnel configuration, interrupted seeding, persistent identity, and OS reset.
They also run under Podman without privileged access.

The integration check requires a disposable Linux Docker host with cgroup v2.
It tests SSH and user sessions, reverse tunneling, apt-installed services, cgroup
limits, independent Docker failures, nested Docker and Buildx, persistence across
outer-container recreation, reboot, and OS reset. It checks injected
file mounts without requiring a GPU. Pass a previous image as the second argument
to test reusing its persistent OS with the new bootstrap.
GPU enumeration and confidential-VM attestation need the target hardware.
