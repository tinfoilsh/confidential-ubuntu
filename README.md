# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over `tinfoil ssh`;

## Deploy

Run the **Tinfoil Release** workflow with a version, then deploy
by repo + tag from the dashboard or:

    tinctl deploy tinfoilsh/confidential-ubuntu

## Connect

    export TINFOIL_TUNNEL_API_KEY=...
    tinfoil ssh workspace -p 2022

This tunnels over the enclave's attested TLS connection, so verifying the
enclave and connecting to it are the same step.
