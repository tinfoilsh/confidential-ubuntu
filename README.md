# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over SSH, pinned to the host key the enclave attests.

## Quickstart

Install the [Tinfoil CLI](https://docs.tinfoil.sh/sdk/cli-sdk), or bring it up
to date with `tinfoil update`, and sign in:

    tinfoil login

Download the config pinned to the latest release:

    curl -fsSLo sandbox.yaml \
      https://github.com/tinfoilsh/confidential-ubuntu/releases/latest/download/tinfoil-config.yaml.example

Open `sandbox.yaml` and replace the `null` value of `SSH_KEYS` with your SSH
public key. Then launch the workspace, verify it, and connect:

    tinfoil container create my-sandbox --config sandbox.yaml
    tinfoil attest-ssh my-sandbox --config sandbox.yaml --install
    ssh my-sandbox

`attest-ssh` checks the enclave against your config file and pins its attested
host key, so keep the exact file you launched. The config is public in the
attestation: never put private keys or other secrets in it.

## Tailscale

In `sandbox.yaml`, uncomment `TAILSCALE_UP_ARGS` and set the `tailscale up`
options the workspace should use, such as its hostname or tags. After
connecting, send an auth key from your tailnet's admin console over SSH:

    ssh my-sandbox tailscale-join < tailscale-auth-key

The workspace is then reachable from your tailnet under that hostname.

## GPUs and persistent storage

Use `tinfoil-config.gpu.yaml.example` from the same release instead. It asks for
8 GPUs and mounts a `workspace` volume at `/mnt/disk`; adjust the resources to
the host. Create the volume, attach it at launch, and unlock it with a key only
you hold:

    tinfoil volume create my-disk --size 100GB
    tinfoil container create my-sandbox --config sandbox.yaml --volume my-disk:workspace
    tinfoil attest-ssh my-sandbox --config sandbox.yaml --install

    openssl rand -out workspace.key 64    # keep it; losing it loses the data
    ssh my-sandbox workspace-unlock < workspace.key

The first unlock formats the blank volume. `/root` then lives on it.

Only `/root` and `/mnt/disk` are on the volume; everything else resets when the
enclave restarts. The volume outlives the workspace: `tinfoil volume list` shows
it, and once the old workspace is deleted a new one can attach it and unlock it
with the same key.

To give the CPU example a volume, copy the `volumes` block and the
`persistent_volumes` line from the GPU example into it.

## Choosing a host

Without `--host`, the workspace and its volume go to your organization's
default host. If your organization has several hosts, list them and name the
one to use. A volume must be on the same host as the workspace it attaches to:

    tinfoil container hosts
    tinfoil volume create my-disk --size 100GB --host <host>
    tinfoil container create my-sandbox --config sandbox.yaml --host <host> --volume my-disk:workspace

## After a restart

A restarted enclave has a new host key, a locked volume, and no tailnet
membership. Verify it again, then repeat the steps you use:

    tinfoil attest-ssh my-sandbox --config sandbox.yaml --install
    ssh my-sandbox workspace-unlock < workspace.key
    ssh my-sandbox tailscale-join < tailscale-auth-key

Changing an SSH key or a Tailscale option means editing the config and launching
a new container.

## Teleport

Uncomment `TELEPORT_PROXY` in the config to enroll the workspace as a Teleport
SSH node. It joins with the `bound_keypair` method using the attested
`teleport-join` key, and expects a join token named `tinfoil-` followed by the
first 16 hex characters of the SHA-256 digest of that key's SPKI encoding.

## Release

Run the **Tinfoil Release** workflow with a new `vMAJOR.MINOR.PATCH` version.
It builds and pushes the image, publishes a release containing both examples
pinned to that image's digest, and opens a pull request with the same pin.
