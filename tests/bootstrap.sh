#!/bin/bash
# Run inside the built image; no privileged mounts or network access needed.
set -euo pipefail
# shellcheck source=entrypoint.sh
source /entrypoint
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Exercise findmnt's real parser, including escaped paths and parent selection.
cat > "$test_dir/mountinfo" <<'EOF'
1 0 0:1 / / rw - tmpfs tmpfs rw
2 1 0:2 / /dev rw - tmpfs tmpfs rw
3 2 0:3 / /dev/pts rw - devpts devpts rw
4 1 0:4 / /sys ro - sysfs sysfs ro
5 4 0:5 / /sys/fs/cgroup rw - cgroup2 cgroup2 rw
6 1 0:6 / /mnt/disk rw - tmpfs tmpfs rw
7 6 0:6 /rootfs /mnt/disk/rootfs rw - tmpfs tmpfs rw
8 1 0:7 / /etc/hosts rw - tmpfs tmpfs rw
9 1 0:8 / /etc/hostname rw - tmpfs tmpfs rw
10 1 0:9 / /etc/resolv.conf rw - tmpfs tmpfs rw
11 1 0:10 / /tinfoil ro - tmpfs tmpfs ro
12 1 0:11 / /usr/bin/nvidia-smi ro - tmpfs tmpfs ro
13 1 0:12 / /opt/my\040library rw - tmpfs tmpfs rw
14 13 0:13 / /opt/my\040library/child rw - tmpfs tmpfs rw
15 1 0:14 / /opt/literal\134040space rw - tmpfs tmpfs rw
16 1 0:15 / /opt/line\012break rw - tmpfs tmpfs rw
17 1 0:16 / /opt/lib[1] rw - tmpfs tmpfs rw
18 17 0:17 / /opt/lib[1]/child rw - tmpfs tmpfs rw
19 1 0:18 / /opt/library rw - tmpfs tmpfs rw
20 1 0:19 / /mnt/diskette rw - tmpfs tmpfs rw
EOF
read_mounts "$test_dir/mountinfo"
printf '%s\0' "${mounts[@]}" | sort -z > "$test_dir/actual"
printf '%s\0' /dev /sys /etc/resolv.conf /tinfoil /usr/bin/nvidia-smi \
    '/opt/my library' '/opt/literal\040space' $'/opt/line\nbreak' \
    '/opt/lib[1]' /opt/library /mnt/diskette | sort -z > "$test_dir/expected"
cmp "$test_dir/actual" "$test_dir/expected"

for target in "$test_dir/runtime file" "$test_dir/runtime directory"; do
    if [[ $target == *file ]]; then touch "$target"; else mkdir "$target"; fi
    destination=$test_dir/root$target
    mkdir -p "${destination%/*}"
    ln -s /missing-runtime-target "$destination"
    prepare_mountpoint "$test_dir/root" "$target"
    [[ ! -L $destination && -e $destination ]]
    if [[ -d $target ]]; then [[ -d $destination ]]; else [[ -f $destination ]]; fi
done

ssh-keygen -q -t ed25519 -N '' -f "$test_dir/client"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/host"
export SSH_KEYS SSH_HOST_KEY SSH_TUNNEL_KEY SSH_TUNNEL_HOST_KEY
SSH_KEYS=$(< "$test_dir/client.pub")
SSH_HOST_KEY=$(< "$test_dir/host")
SSH_TUNNEL_KEY=$SSH_HOST_KEY
SSH_TUNNEL_HOST_KEY=$(< "$test_dir/host.pub")
credentials=$test_dir/credentials
umask 077
stage_credentials
[[ $(stat -c %a "$credentials") == 700 && $(stat -c %a "$credentials/host_key") == 600 ]]
[[ ! -v SSH_HOST_KEY && ! -e $credentials/tunnel.conf ]]
cmp "$test_dir/client.pub" "$credentials/authorized_keys"

# Restore inputs consumed by staging and verify the generated SSH configuration.
export SSH_KEYS SSH_HOST_KEY SSH_TUNNEL_KEY SSH_TUNNEL_HOST_KEY SSH_TUNNEL_TARGET SSH_TUNNEL_PORT
SSH_KEYS=$(< "$test_dir/client.pub")
SSH_HOST_KEY=$(< "$test_dir/host")
SSH_TUNNEL_KEY=$SSH_HOST_KEY
SSH_TUNNEL_HOST_KEY=$(< "$test_dir/host.pub")
SSH_TUNNEL_TARGET=user@example.test
for SSH_TUNNEL_PORT in 1 2022 65535 02022; do
    (stage_credentials)
    ssh -G -T -F "$credentials/tunnel.conf" workspace-tunnel > "$test_dir/ssh-config"
    grep -qx 'hostname example.test' "$test_dir/ssh-config"
    grep -qx 'user user' "$test_dir/ssh-config"
    grep -Fqx "remoteforward [127.0.0.1]:$((10#$SSH_TUNNEL_PORT)) [127.0.0.1]:2222" "$test_dir/ssh-config"
done
for SSH_TUNNEL_PORT in 0 65536 -1 +22 '22 ' not-a-port 999999999999999999999; do
    if (stage_credentials) 2>/dev/null; then
        printf 'Accepted invalid tunnel port: %s\n' "$SSH_TUNNEL_PORT" >&2
        exit 1
    fi
done
if (SSH_KEYS=invalid stage_credentials) 2>/dev/null; then exit 1; fi
if (SSH_HOST_KEY=invalid stage_credentials) 2>/dev/null; then exit 1; fi

# Inject an interrupted OS copy, then retry. Run in separate shells so errexit
# remains active, including when the caller expects the first invocation to fail.
cat > "$test_dir/seed" <<'EOF'
set -euo pipefail
source /entrypoint
disk=$1
rsync() {
    mkdir -p "$disk/.rootfs.new/etc"
    printf 'seed data\n' > "$disk/.rootfs.new/sentinel"
    if [[ -e $disk/interrupt ]]; then return 1; fi
}
seed_root
EOF
mkdir "$test_dir/disk"
touch "$test_dir/disk/interrupt"
if bash "$test_dir/seed" "$test_dir/disk"; then exit 1; fi
[[ ! -e $test_dir/disk/rootfs && -f $test_dir/disk/.rootfs.new/sentinel ]]
rm "$test_dir/disk/interrupt"
bash "$test_dir/seed" "$test_dir/disk"
[[ $(< "$test_dir/disk/rootfs/.workspace-root-version") == 1 ]]
machine_id=$(< "$test_dir/disk/rootfs/etc/machine-id")
[[ $machine_id =~ ^[a-f0-9]{32}$ ]]
printf 'user data\n' > "$test_dir/disk/rootfs/sentinel"
bash "$test_dir/seed" "$test_dir/disk"
[[ $(< "$test_dir/disk/rootfs/etc/machine-id") == "$machine_id" ]]
touch "$test_dir/disk/workspace/sentinel" "$test_dir/disk/docker/sentinel" "$test_dir/disk/.reset-rootfs"
bash "$test_dir/seed" "$test_dir/disk"
[[ $(< "$test_dir/disk/rootfs/sentinel") == 'seed data' ]]
grep -qx 'user data' "$test_dir"/disk/rootfs.previous.*/sentinel
[[ -f $test_dir/disk/workspace/sentinel && -f $test_dir/disk/docker/sentinel ]]
[[ ! -e $test_dir/disk/.reset-rootfs && ! -e $test_dir/disk/.rootfs.new ]]
printf '99\n' > "$test_dir/disk/rootfs/.workspace-root-version"
if bash "$test_dir/seed" "$test_dir/disk" 2>/dev/null; then exit 1; fi
printf 'Bootstrap checks passed.\n'
