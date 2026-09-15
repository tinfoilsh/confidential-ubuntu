#!/bin/bash
# Seed a persistent Ubuntu root, carry runtime mounts into it, and start systemd.
set -euo pipefail

disk=/mnt/disk
credentials=/run/workspace

fail() { printf 'confidential-ubuntu: %s\n' "$*" >&2; exit 1; }

stage_credentials() {
    install -d -m 0700 "$credentials"
    printf '%s\n' "${SSH_KEYS:-}" > "$credentials/authorized_keys"
    ssh-keygen -lf "$credentials/authorized_keys" >/dev/null 2>&1 || fail 'SSH_KEYS has no usable public key'
    printf '%s\n' "${SSH_HOST_KEY:?SSH_HOST_KEY is required}" > "$credentials/host_key"
    ssh-keygen -y -P '' -f "$credentials/host_key" >/dev/null 2>&1 || fail 'SSH_HOST_KEY must be an unencrypted OpenSSH private key'

    if [[ -n ${SSH_TUNNEL_TARGET:-} ]]; then
        local target=$SSH_TUNNEL_TARGET port=${SSH_TUNNEL_PORT:-2022}
        local target_pattern='^[][a-zA-Z0-9_.:@%+-]+$'
        # These values become SSH configuration, so accept a single user@host or host.
        [[ $target =~ $target_pattern ]] || fail 'SSH_TUNNEL_TARGET must be user@host or host'
        port=${port#"${port%%[!0]*}"}
        if [[ ! $port =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
            fail 'SSH_TUNNEL_PORT must be between 1 and 65535'
        fi
        printf '%s\n' "${SSH_TUNNEL_KEY:?SSH_TUNNEL_KEY is required}" > "$credentials/tunnel_key"
        printf '%s %s\n' "${target#*@}" "${SSH_TUNNEL_HOST_KEY:?SSH_TUNNEL_HOST_KEY is required}" > "$credentials/tunnel_known_hosts"
        # Older persistent roots still have a tunnel helper that reads these files.
        printf '%s\n' "$target" > "$credentials/tunnel_target"
        printf '%s\n' "$port" > "$credentials/tunnel_port"
        cat /etc/ssh/workspace_tunnel.conf > "$credentials/tunnel.conf"
        printf 'HostName %s\nRemoteForward 127.0.0.1:%s 127.0.0.1:2222\n' "${target#*@}" "$port" >> "$credentials/tunnel.conf"
        if [[ $target == *@* ]]; then
            printf 'User %s\n' "${target%%@*}" >> "$credentials/tunnel.conf"
        fi
    fi
    chmod 0600 "$credentials"/*
    unset SSH_KEYS SSH_HOST_KEY SSH_TUNNEL_TARGET SSH_TUNNEL_PORT SSH_TUNNEL_KEY SSH_TUNNEL_HOST_KEY
}

seed_root() (
    # Hold the lock only while installing or resetting the OS.
    umask 077
    exec 9> "$disk/.rootfs.lock"
    flock -x 9
    umask 022
    root=$disk/rootfs
    if [[ -e $disk/.reset-rootfs ]]; then
        if [[ -e $root ]]; then
            mv -T -- "$root" "$root.previous.$(date +%s.%N)"
        fi
        rm -- "$disk/.reset-rootfs"
        sync -f "$disk"
    fi
    if [[ ! -e $root ]]; then
        staging=$disk/.rootfs.new
        # An interrupted copy must never become the installed OS.
        rm -rf -- "$staging"
        install -d -m 0755 "$staging"
        rsync -aHAXx --numeric-ids \
            --exclude='/mnt/disk/***' --exclude='/proc/***' --exclude='/sys/***' \
            --exclude='/dev/***' --exclude='/run/***' --exclude='/tinfoil/***' / "$staging/"
        mkdir -p "$staging"/{dev,proc,sys,run,tinfoil,mnt/disk,workspace}
        machine_id=$(< /proc/sys/kernel/random/uuid)
        machine_id=${machine_id//-/}
        [[ $machine_id =~ ^[0-9a-f]{32}$ ]] || fail 'invalid kernel-generated machine ID'
        hostname=workspace-${machine_id:0:12}
        printf '%s\n' "$machine_id" > "$staging/etc/machine-id"
        printf '%s\n' "$hostname" > "$staging/etc/hostname"
        printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' "$hostname" > "$staging/etc/hosts"
        printf '1\n' > "$staging/.workspace-root-version"
        sync -f "$disk"
        mv -T -- "$staging" "$root"
        sync -f "$disk"
    fi
    [[ $(< "$root/.workspace-root-version") == 1 ]] || fail 'unsupported persistent root version'
    mkdir -p "$disk/workspace" "$disk/docker"
)

read_mounts() {
    local inventory encoded target parent
    # Raw findmnt output hex-escapes whitespace and backslashes. Decode once,
    # after sorting, so even paths containing newlines stay intact in the array.
    inventory=$(findmnt --kernel --tab-file "$1" --raw --noheadings --output TARGET | LC_ALL=C sort -u)
    mounts=()
    while IFS= read -r encoded; do
        printf -v target '%b' "$encoded"
        case $target in
            /|"$disk"|"$disk"/*|/etc/hostname|/etc/hosts) continue ;;
        esac
        for parent in "${mounts[@]}"; do
            # A moved parent carries its children, including writable cgroups.
            [[ $target == "$parent"/* ]] && continue 2
        done
        mounts+=("$target")
    done <<< "$inventory"
}

prepare_mountpoint() {
    local destination=$1$2 target=$2
    # Replace persisted absolute symlinks before installing runtime file mounts.
    if [[ -L $destination ]]; then rm -- "$destination"; fi
    if [[ -d $target ]]; then
        mkdir -p -- "$destination"
    else
        mkdir -p -- "${destination%/*}"
        touch -- "$destination"
    fi
}

boot() {
    [[ $# == 0 ]] || { printf 'usage: /entrypoint\n' >&2; exit 2; }
    [[ $$ == 1 ]] || fail 'the entrypoint must run as PID 1'
    mountpoint -q "$disk" || fail '/mnt/disk must be the mounted encrypted volume'
    umask 077
    stage_credentials
    # Run this image's helper even when the persistent root is from an older image.
    install -m 0700 /usr/local/libexec/workspace-init "$credentials/init"
    seed_root
    umask 022
    local root=$disk/rootfs target
    read_mounts /proc/self/mountinfo
    # Do not update /run/mount/utab while moving /run itself out of this root.
    mount -n --make-rprivate /
    mount -n --bind "$root" "$root"
    # The encrypted volume is nosuid. Ubuntu's sudo needs suid on its root bind.
    mount -n -o remount,bind,suid,nodev "$root"
    for target in "${mounts[@]}"; do prepare_mountpoint "$root" "$target"; done
    mkdir -p "$root$disk" "$root/workspace" "$root/.oldroot"
    mount -n --bind "$disk" "$root$disk"
    mount -n --bind "$disk/workspace" "$root/workspace"
    for target in "${mounts[@]}"; do mount -n --move "$target" "$root$target"; done
    cd "$root"
    pivot_root . .oldroot
    exec chroot . /bin/bash /run/workspace/init
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then boot "$@"; fi
