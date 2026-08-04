#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ADB=${ADB:-adb}

command -v "$ADB" >/dev/null 2>&1 || {
    echo "adb was not found." >&2
    exit 1
}
"$ADB" get-state >/dev/null

if "$ADB" shell su -c 'pidof qemu-system-aarch64 >/dev/null 2>&1'; then
    echo "QEMU is running. Shut Windows down completely before backing up QCOW2 and UEFI NVRAM." >&2
    exit 1
fi

pull_file() {
    remote=$1
    local_path=$2

    if ! "$ADB" shell test -f "$remote"; then
        echo "Missing on the phone: $remote" >&2
        exit 1
    fi

    echo "Backing up $remote"
    "$ADB" pull "$remote" "$local_path"
}

echo '[1/3] Backing up mutable VM data'
pull_file /sdcard/Limbo/QEMU_VARS.fd "$ROOT/QEMU_VARS.fd"
pull_file /sdcard/Limbo/win.qcow2 "$ROOT/win.qcow2"

echo '[2/3] Backing up installation and driver ISOs'
pull_file /sdcard/Limbo/win10.iso "$ROOT/win10.iso"
pull_file /sdcard/Limbo/virtio-win.iso "$ROOT/virtio-win.iso"

echo '[3/3] Backing up KVM helper files'
pull_file /data/local/tmp/libkvm_flash0_only.so "$ROOT/libkvm_flash0_only.so"
pull_file /data/local/tmp/kvm_flash0_only.c "$ROOT/kvm_flash0_only.c"
pull_file /data/local/tmp/limbo_kvm_untrusted29.zip "$ROOT/limbo_kvm_untrusted29.zip"

if "$ADB" shell test -f /data/local/tmp/start-win10-kvm.sh; then
    pull_file /data/local/tmp/start-win10-kvm.sh "$ROOT/start-win10-kvm.sh"
else
    echo "Note: Keeping the local start-win10-kvm.sh; no copy was installed on the phone."
fi