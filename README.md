# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over native SSH after pinning the attested host key.

## Deploy

Run the **Tinfoil Release** workflow with a version, then deploy
by repo + tag from the dashboard or:

    tinfoil container create my-cvm \
      --repo tinfoilsh/confidential-ubuntu \
      --tag v0.3.1 \
      --host ...

## Connect

Requires [Tinfoil CLI](https://github.com/tinfoilsh/tinfoil-cli/releases) v0.18.8 or later:

    tinfoil attest-ssh my-cvm --install
    ssh my-cvm

`attest-ssh` verifies the enclave and pins the `host-ssh` key. After a full
enclave reboot the host key rotates; rerun `--install` before connecting again.

## Unlock

A volume can be unlocked from within the CVM by sending it the volume key over SSH:

    head -c 64 /dev/urandom > workspace.key    # keep it; losing it loses the data
    ssh my-cvm workspace-unlock < workspace.key
