# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over `tinfoil ssh`; nothing is exposed on the public internet.

## Deploy

Run the **Tinfoil Release** workflow with a version (e.g. `v0.3.0`), then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

Nothing needs setting on the deployment. The authorized key, the box size and
the GPU count all live in [`tinfoil-config.yml`](tinfoil-config.yml) and are
measured as part of the attestation, so change them there and cut a new release.

## Connect

    export TINFOIL_TUNNEL_API_KEY=...
    tinfoil ssh workspace -p 2022

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step. `scp`, `sftp`, `rsync` and
`ssh -L` port forwarding all work.

## Good to know

Storage is not persistent — the workspace lives on the CVM's ramdisk, so push
anything you care about to git or object storage before it reboots. The writable
root is a 4 GB overlay, much smaller than the box's RAM.

`cvm_admin` gives privileged root over the whole CVM rather than an extra
sandbox: one kernel, one tenant. Kernel module loading stays locked and the
verified CVM root disk stays read-only, so this is not a boundary against the
VM — do not share a CVM with anyone you would not give root to.

The SSH host key is regenerated every boot. Nothing checks it: `tinfoil ssh`
pins the enclave by attestation and turns host key checking off.
