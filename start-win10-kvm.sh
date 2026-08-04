#!/system/bin/sh
set -eu

QEMU=/data/data/com.termux/files/usr/bin/qemu-system-aarch64
FIRMWARE=/data/data/com.termux/files/usr/share/qemu/edk2-aarch64-code.fd
VARS=/sdcard/Limbo/QEMU_VARS.fd
DISK=/sdcard/Limbo/win.qcow2
WINDOWS_ISO=/sdcard/Limbo/win10.iso
VIRTIO_ISO=/sdcard/Limbo/virtio-win.iso
SHIM=/data/local/tmp/libkvm_flash0_only.so

VCPUS=${VCPUS:-6}
MEMORY_MB=${MEMORY_MB:-4096}
CPU_MASK=${CPU_MASK:-ff}
ATTACH_VIRTIO_ISO=${ATTACH_VIRTIO_ISO:-0}
INSTALL_WINDOWS=${INSTALL_WINDOWS:-0}

for required in "$QEMU" "$FIRMWARE" "$VARS" "$DISK" "$SHIM"; do
    if [ ! -f "$required" ]; then
        echo "Missing: $required" >&2
        exit 1
    fi
done

if pidof qemu-system-aarch64 >/dev/null 2>&1; then
    echo "QEMU is already running. Shut down the existing VM cleanly first." >&2
    exit 1
fi

set -- \
    "$QEMU" \
    -name Win10-ARM64 \
    -machine virt,accel=kvm,gic-version=host \
    -cpu host \
    -smp "$VCPUS",sockets=1,cores="$VCPUS",threads=1 \
    -m "$MEMORY_MB" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$FIRMWARE" \
    -drive if=pflash,format=raw,unit=1,file="$VARS" \
    -drive if=none,id=system,format=qcow2,file="$DISK",cache=writeback,aio=threads,discard=unmap \
    -device nvme,id=nvme0,drive=system,serial=WIN10NVME,bootindex=2 \
    -boot order=c,menu=on \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -device usb-tablet,bus=xhci.0 \
    -netdev user,id=net0,ipv6=off \
    -device virtio-net-pci,id=net0dev,netdev=net0,disable-legacy=on,mac=52:54:00:12:34:56 \
    -device virtio-rng-pci \
    -device ramfb \
    -rtc base=localtime \
    -object secret,id=vncpass,data=1234 \
    -display vnc=127.0.0.1:8,password-secret=vncpass \
    -monitor tcp:127.0.0.1:55555,server=on,wait=off

if [ "$INSTALL_WINDOWS" = 1 ]; then
    if [ ! -f "$WINDOWS_ISO" ]; then
        echo "INSTALL_WINDOWS=1, but the ISO is missing: $WINDOWS_ISO" >&2
        exit 1
    fi
    set -- "$@" \
        -drive if=none,id=installer,format=raw,media=cdrom,readonly=on,file="$WINDOWS_ISO" \
        -device usb-storage,id=installcd,drive=installer,bus=xhci.0,bootindex=1,removable=on
    ATTACH_VIRTIO_ISO=1
fi

if [ "$ATTACH_VIRTIO_ISO" = 1 ]; then
    if [ ! -f "$VIRTIO_ISO" ]; then
        echo "ATTACH_VIRTIO_ISO=1, but the ISO is missing: $VIRTIO_ISO" >&2
        exit 1
    fi
    set -- "$@" \
        -drive if=none,id=virtiodrv,format=raw,media=cdrom,readonly=on,file="$VIRTIO_ISO" \
        -device usb-storage,id=virtiocd,drive=virtiodrv,bus=xhci.0,removable=on
fi

if [ "$INSTALL_WINDOWS" = 1 ]; then
    echo "Starting Windows installation: ${VCPUS} vCPUs, ${MEMORY_MB} MB RAM, host CPU mask ${CPU_MASK}"
else
    echo "Starting Windows: ${VCPUS} vCPUs, ${MEMORY_MB} MB RAM, host CPU mask ${CPU_MASK}"
fi
exec /system/bin/taskset "$CPU_MASK" /system/bin/env \
    LD_PRELOAD="$SHIM" \
    "$@"
