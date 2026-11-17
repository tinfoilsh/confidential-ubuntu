# Confidential Ubuntu

A bare Ubuntu workspace that runs inside a confidential VM. You log in as root
over SSH, pinned to the host key the enclave attests.

## Deploy

Each release publishes two example configs pinned to its image:

- `tinfoil-config.yaml.example`: 4 CPUs, 8 GiB RAM, no GPU, and no persistent volume.
- `tinfoil-config.gpu.yaml.example`: 120 CPUs, 1 TiB RAM, 8 GPUs, and a
  `workspace` volume at `/mnt/disk`. Adjust the resources to fit the selected host.

Copy one to `configs/sandbox.yaml` and replace the `null` value of `SSH_KEYS`
with your SSH public keys. The config is sent to Tinfoil to launch the VM and
is included in its attestation collateral, so keep private keys and other
secrets out of it. Git and the Docker build ignore the `configs/` folder.

    tinfoil container create my-sandbox --config configs/sandbox.yaml

This uses your organization's default host; pass `--host <host>` to choose one
from `tinfoil container hosts`. The GPU example needs a host with GPUs and a
disk on that host:

    tinfoil container create my-sandbox --config configs/sandbox.yaml \
      --host <host> --volume <disk-name>:workspace

Keep the exact launched file: connections are verified against its bytes.
Changing a key means editing the config and launching a new container.

## Connect

    tinfoil attest-ssh my-sandbox \
      --config configs/sandbox.yaml \
      --identity <authorized-private-key-file> \
      --install
    ssh my-sandbox

`attest-ssh` verifies the enclave and pins its attested host key. The key
rotates when the enclave reboots, so run it again before reconnecting. See
[Attested SSH](https://docs.tinfoil.sh/containers/attested-ssh).

## Unlock

A volume is unlocked from within the CVM by sending it the volume key over SSH:

    openssl rand -out workspace.key 64    # keep it; losing it loses the data
    ssh my-sandbox workspace-unlock < workspace.key

The first run formats a blank volume; later runs open it with the same key. See
[Encrypted volumes](https://docs.tinfoil.sh/containers/encrypted-volumes).

## Teleport

Uncomment `TELEPORT_PROXY` in the config to enroll the workspace as a Teleport
SSH node. It joins with the `bound_keypair` method using the attested
`teleport-join` key, and expects a join token named `tinfoil-` followed by the
first 16 hex characters of the SHA-256 digest of that key's SPKI encoding.

## Tailscale

Uncomment `TAILSCALE_UP_ARGS` in the config and set the `tailscale up` options
the workspace should use, such as its hostname or tags. Leave credentials out:
the config is public in the attestation. After verifying the enclave, send an
auth key over SSH to join the tailnet:

    ssh my-sandbox tailscale-join < tailscale-auth-key

Node state is kept in memory, so the workspace joins again after every reboot.

## Release

Run the **Tinfoil Release** workflow with a new `vMAJOR.MINOR.PATCH` version.
It builds and pushes the image and publishes a release containing both examples
pinned to that image's digest. The examples in the repository keep `image: null`.
