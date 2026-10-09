# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over `tinfoil ssh`.

## Deploy

Run the **Tinfoil Release** workflow with a version, then deploy
by repo + tag from the dashboard or:

    tinfoil container create my-cvm \
      --repo tinfoilsh/confidential-ubuntu \
      --tag v0.3.1 \
      --host ...

## Connect

    export TINFOIL_TUNNEL_API_KEY=...
    tinfoil ssh workspace

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step.

## Unlock

An existing legacy workspace volume can be unlocked from within the CVM by
sending its original key over SSH:

    tinfoil ssh workspace -- workspace-unlock < workspace.key

`workspace-unlock` requires cvmimage v0.14.14 and uses the legacy format 1 unlock
request, preserving the original SHA-512 key derivation. It does not initialize
blank disks or migrate existing volumes to the Argon2id format.
