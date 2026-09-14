# Confidential Ubuntu

An Ubuntu workspace that runs inside a confidential VM. 

## Deploy

Run the **Tinfoil Release** workflow with a version (e.g. `v0.1.0`), then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

## Connect

    export TINFOIL_API_KEY=...
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

## Good to know

Storage is not persistent — the workspace lives on the CVM's ramdisk, so push
anything you care about to git or object storage before it reboots.
