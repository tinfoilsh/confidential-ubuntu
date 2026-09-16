# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root.

## Deploy

Run the **Tinfoil Release** workflow with a version (e.g. `v0.2.0`), then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

Nothing needs setting on the deployment. The authorized key is inline in
`tinfoil-config.yml`, so it is measured rather than supplied at deploy time. To
change it, edit `SSH_KEYS` and cut a new release.

## Connect

    export TINFOIL_TUNNEL_API_KEY=...
    tinfoil ssh workspace

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step. `scp`, `sftp`, `rsync` and
`ssh -L` port forwarding all work, and it drops you at a root bash prompt.

To resize the box or attach a GPU, edit `cpus`, `memory` and `gpus` in
`tinfoil-config.yml`, and add `runtime: nvidia` to the container.

## Good to know

Storage is not persistent — the workspace lives on the CVM's ramdisk, so push
anything you care about to git or object storage before it reboots. `cryptsetup`
is installed if you want to hand-roll an encrypted disk on a loop file.

`cvm_admin` gives privileged root over the whole CVM rather than an extra
sandbox: one kernel, one tenant. Do not share the CVM with anyone you would not
give root to.

The SSH host key is generated on each boot. Nothing checks it — `tinfoil ssh`
pins the enclave by attestation and turns host key checking off.
