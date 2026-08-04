  #!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ADB=${ADB:-adb}

command -v "$ADB" >/dev/null 2>&1 || {
    echo "adb was not found." >&2
    exit 1
}
"$ADB" get-state >/dev/null

required_files="
$ROOT/QEMU_VARS.fd
$ROOT/win.qcow2
$ROOT/win10.iso
$ROOT/virtio-win.iso
$ROOT/libkvm_flash0_only.so
$ROOT/kvm_flash0_only.c
$ROOT/limbo_kvm_untrusted29.zip
$ROOT/start-win10-kvm.sh
"

echo "$required_files" | while IFS= read -r required; do
    [ -z "$required" ] && continue
    if [ ! -f "$required" ]; then
        echo "Missing from the backup: $required" >&2
        exit 1
    fi
done

if "$ADB" shell su -c 'pidof qemu-system-aarch64 >/dev/null 2>&1'; then
    echo "QEMU is running on the phone. Shut Windows down cleanly before restoring." >&2
    exit 1
fi

qcow2_temp_dir=

cleanup_qcow2_chunks() {
    if [ -n "$qcow2_temp_dir" ] && [ -d "$qcow2_temp_dir" ]; then
        case "$qcow2_temp_dir" in
            "$qcow2_temp_base"/windowsinqemu-qcow2.*)
                rm -rf -- "$qcow2_temp_dir"
                ;;
        esac
    fi
}

restore_windows_disk() {
    qcow2_size=$(wc -c < "$ROOT/win.qcow2" | tr -d '[:space:]')
    qcow2_chunk_size=$(( (qcow2_size + 1) / 2 ))
    qcow2_temp_base=${TMPDIR:-/tmp}
    qcow2_temp_base=${qcow2_temp_base%/}
    qcow2_temp_dir=$(mktemp -d "$qcow2_temp_base/windowsinqemu-qcow2.XXXXXX")
    trap cleanup_qcow2_chunks 0 HUP INT TERM

    qcow2_part1=$qcow2_temp_dir/win.qcow2.part1
    qcow2_part2=$qcow2_temp_dir/win.qcow2.part2

    head -c "$qcow2_chunk_size" "$ROOT/win.qcow2" > "$qcow2_part1"
    [ "$(wc -c < "$qcow2_part1" | tr -d '[:space:]')" = "$qcow2_chunk_size" ]

    "$ADB" shell rm -f \
        /sdcard/Limbo/win.qcow2 \
        /sdcard/Limbo/win.qcow2.part2
    "$ADB" push "$qcow2_part1" /sdcard/Limbo/win.qcow2
    rm -f -- "$qcow2_part1"

    qcow2_part2_offset=$((qcow2_chunk_size + 1))
    qcow2_part2_size=$((qcow2_size - qcow2_chunk_size))
    tail -c "+$qcow2_part2_offset" "$ROOT/win.qcow2" > "$qcow2_part2"
    [ "$(wc -c < "$qcow2_part2" | tr -d '[:space:]')" = "$qcow2_part2_size" ]

    "$ADB" push "$qcow2_part2" /sdcard/Limbo/win.qcow2.part2
    "$ADB" shell 'cat /sdcard/Limbo/win.qcow2.part2 >> /sdcard/Limbo/win.qcow2 && rm -f /sdcard/Limbo/win.qcow2.part2'

    qcow2_remote_size=$("$ADB" shell stat -c %s /sdcard/Limbo/win.qcow2 | tr -d '\r')
    [ "$qcow2_remote_size" = "$qcow2_size" ]

    cleanup_qcow2_chunks
    qcow2_temp_dir=
    trap - 0 HUP INT TERM
}

echo '[1/4] Preparing target directories'
"$ADB" shell mkdir -p /sdcard/Limbo

echo '[2/4] Restoring UEFI variables, the Windows disk, and ISOs'
"$ADB" push "$ROOT/QEMU_VARS.fd" /sdcard/Limbo/QEMU_VARS.fd
restore_windows_disk
"$ADB" push "$ROOT/win10.iso" /sdcard/Limbo/win10.iso
"$ADB" push "$ROOT/virtio-win.iso" /sdcard/Limbo/virtio-win.iso

echo '[3/4] Installing the KVM shim, source, SELinux module, and launcher'
"$ADB" push "$ROOT/libkvm_flash0_only.so" /data/local/tmp/libkvm_flash0_only.so
"$ADB" push "$ROOT/kvm_flash0_only.c" /data/local/tmp/kvm_flash0_only.c
"$ADB" push "$ROOT/limbo_kvm_untrusted29.zip" /data/local/tmp/limbo_kvm_untrusted29.zip
"$ADB" push "$ROOT/start-win10-kvm.sh" /data/local/tmp/start-win10-kvm.sh
"$ADB" shell "su -c 'chown root:root /data/local/tmp/libkvm_flash0_only.so /data/local/tmp/start-win10-kvm.sh && chmod 755 /data/local/tmp/libkvm_flash0_only.so /data/local/tmp/start-win10-kvm.sh && chmod 644 /data/local/tmp/kvm_flash0_only.c /data/local/tmp/limbo_kvm_untrusted29.zip'"

echo '[4/4] Forwarding VNC and monitor ports'
"$ADB" forward tcp:5908 tcp:5908
"$ADB" forward tcp:55556 tcp:55555

cat <<'EOF'

Restore completed.

Verify that the custom kernel provides /dev/kvm:
  adb shell su -c 'ls -lZ /dev/kvm'

Normal launch from the Termux app:
  su -c '/data/local/tmp/start-win10-kvm.sh'

Temporarily attach the VirtIO driver CD from the Termux app:
  su -c 'ATTACH_VIRTIO_ISO=1 /data/local/tmp/start-win10-kvm.sh'

VNC:
  vnc://127.0.0.1:5908
  Password: 1234

The SELinux module is only required for direct KVM access from
Limbo/untrusted_app_29. It is not required for the root/Termux launch above.
EOF
