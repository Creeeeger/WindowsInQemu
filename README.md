# Windows 10 ARM64 in QEMU/KVM on rooted Android

This repository contains the small, reproducible part of a working Windows 10 ARM64 QEMU/KVM setup for Android. It
includes the writable EDK2 NVRAM image, a compatibility shim for an older ARM KVM implementation, launch/backup/restore
scripts, and an optional KernelSU SELinux module.

It does **not** contain Windows, a preinstalled Windows disk, or the VirtIO driver ISO. Those three large files must be
supplied locally and are explicitly excluded by `.gitignore`:

```text
win.qcow2
win10.iso
virtio-win.iso
```

## What this repository does—and does not—provide

This setup does not enable KVM by itself. Before QEMU can use hardware virtualization, the Android device must already
have:

- an ARM64 kernel with KVM host support;
- CPUs entering the kernel with EL2 available to KVM;
- a working `/dev/kvm` device;
- root access, tested here with KernelSU;
- SELinux policy that permits the chosen root domain to access `/dev/kvm`.

Verify the essential host state:

```sh
su -c 'ls -lZ /dev/kvm'
su -c 'cat /sys/module/kvm/parameters/* 2>/dev/null || true'
```

The tested device exposes `/dev/kvm` as:

```text
crw-rw-rw- root root u:object_r:kvm_device:s0 /dev/kvm
```

If `/dev/kvm` does not exist, stop here. Installing QEMU or copying this repository cannot add KVM support to a stock
kernel.

## Tested host assumptions

The launcher leaves host CPU placement to Android. On heterogeneous hosts, use a KVM kernel that normalizes guest
cache identification registers so their values remain consistent when a vCPU moves between CPU implementations.

## Repository files

| File                        | Purpose                                                                                |
|-----------------------------|----------------------------------------------------------------------------------------|
| `QEMU_VARS.fd`              | Writable 64 MiB EDK2 NVRAM/UEFI variable store                                         |
| `libkvm_flash0_only.so`     | `LD_PRELOAD` shim that clears `KVM_MEM_READONLY` only for the first pflash memory slot |
| `kvm_flash0_only.c`         | Source for the shim                                                                    |
| `start-win10-kvm.sh`        | Windows installer and normal-boot launcher                                             |
| `restore-to-phone.sh`       | Restores a complete local VM backup to the phone                                       |
| `backup-from-phone.sh`      | Pulls mutable VM state and local media from the phone                                  |
| `limbo_kvm_untrusted29.zip` | KernelSU policy module for direct Limbo access to `/dev/kvm`                           |
| `qemu-start-command.txt`    | Command notes from development                                                         |

## 1. Install Termux and QEMU

Install a current Termux from PlayStore.

In the normal Termux app—not in `adb shell` and not inside a proot distro—run:

```sh
pkg update
pkg upgrade
pkg install qemu-system-aarch64-headless qemu-utils curl
```

This installs both required package-owned files:

```text
$PREFIX/bin/qemu-system-aarch64
$PREFIX/share/qemu/edk2-aarch64-code.fd
```

`edk2-aarch64-code.fd` is intentionally not stored in this repository. It is installed reproducibly by the Termux QEMU
package. `QEMU_VARS.fd`, on the other hand, is writable VM state and is included here.

## 2. Clone the repository

On the Mac or another computer with ADB:

```sh
git clone https://github.com/Creeeeger/WindowsInQemu.git
cd WindowsInQemu
```

Alternatively, clone it in Termux and adjust the local paths in the copy commands below.

## 3. Obtain the two ISO images

### Windows 10 ARM64

Provide your own Windows 10 ARM64 installation ISO and name it:

```text
win10.iso
```

### VirtIO Windows drivers

Download the stable driver ISO from the official VirtIO Windows distribution:

```sh
curl -L --fail \
  -o virtio-win.iso \
  'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso'
```

The ISO must contain at least these Windows 10 ARM64 drivers:

```text
NetKVM\w10\ARM64\netkvm.inf
viogpudo\w10\ARM64\viogpudo.inf
```

Place `win10.iso` and `virtio-win.iso` in the repository directory. Git ignores both files.

## 4. Copy the runtime files to Android

From the repository directory on the Mac:

```sh
adb shell mkdir -p /sdcard/Limbo

adb push QEMU_VARS.fd /sdcard/Limbo/QEMU_VARS.fd
adb push win10.iso /sdcard/Limbo/win10.iso
adb push virtio-win.iso /sdcard/Limbo/virtio-win.iso

adb push libkvm_flash0_only.so /data/local/tmp/libkvm_flash0_only.so
adb push kvm_flash0_only.c /data/local/tmp/kvm_flash0_only.c
adb push start-win10-kvm.sh /data/local/tmp/start-win10-kvm.sh

adb shell su -c \
  'chown root:root /data/local/tmp/libkvm_flash0_only.so /data/local/tmp/start-win10-kvm.sh && chmod 755 /data/local/tmp/libkvm_flash0_only.so /data/local/tmp/start-win10-kvm.sh'
```

## 5. Create a fresh Windows disk

For a new installation, create a 64 GiB sparse QCOW2 disk in the normal Termux shell:

```sh
mkdir -p /sdcard/Limbo
qemu-img create -f qcow2 /sdcard/Limbo/win.qcow2 64G
qemu-img info /sdcard/Limbo/win.qcow2
```

Do not commit this file. The repository's `.gitignore` excludes it.

If an existing `win.qcow2` is being restored instead, copy it to:

```text
/sdcard/Limbo/win.qcow2
```

## 6. Forward VNC and the QEMU monitor

On the Mac:

```sh
adb forward tcp:5908 tcp:5908
adb forward tcp:55556 tcp:55555
```

The VM's VNC endpoint is:

```text
vnc://127.0.0.1:5908
```

The configured VNC password is:

```text
1234
```

On macOS:

```sh
open 'vnc://127.0.0.1:5908'
```

## 7. Install Windows

Run the installer from **inside the Termux app**:

```sh
su -c 'INSTALL_WINDOWS=1 /data/local/tmp/start-win10-kvm.sh'
```

This mode attaches:

- `win10.iso` as the first bootable USB CD-ROM;
- `virtio-win.iso` as a second driver CD-ROM;
- `win.qcow2` as a QEMU NVMe disk;
- `ramfb` for reliable Windows ARM64 firmware/display output;
- a VirtIO network adapter backed by QEMU user-mode NAT.

Connect through VNC and perform a normal Windows installation. Select the QEMU NVMe disk as the installation target. No
VirtIO storage driver is required for that NVMe disk.

Keep using installer mode until Windows has copied its files. Before the first normal disk boot, shut the VM down and
restart without `INSTALL_WINDOWS=1` so the installation ISO is no longer first in the boot order.

If Windows setup insists on an Internet connection before the VirtIO network driver is installed, complete an
offline/local-account setup first. Windows 10 normally offers an offline path depending on edition and build.

## 8. Boot the installed system

In Termux:

```sh
su -c '/data/local/tmp/start-win10-kvm.sh'
```

Defaults:

```text
Guest vCPUs:     6
Guest RAM:       4096 MiB
Disk:            NVMe, /sdcard/Limbo/win.qcow2
Display:         ramfb over VNC
Network:         virtio-net-pci over QEMU user NAT
VNC:             127.0.0.1:5908, password 1234
Monitor:         127.0.0.1:55555 on the phone
```

Override CPU count or memory when needed:

```sh
su -c 'VCPUS=4 MEMORY_MB=3072 /data/local/tmp/start-win10-kvm.sh'
```

## 9. Install the Windows ARM64 network driver

If the VirtIO driver ISO is not currently attached, start once with:

```sh
su -c 'ATTACH_VIRTIO_ISO=1 /data/local/tmp/start-win10-kvm.sh'
```

Inside Windows, find the VirtIO CD-ROM drive and install:

```text
NetKVM\w10\ARM64\netkvm.inf
```

From an Administrator Command Prompt, where `D:` is the actual VirtIO CD-ROM drive letter:

```cmd
pnputil /add-driver "D:\NetKVM\w10\ARM64\netkvm.inf" /install
```

If the CD is not `D:`, inspect the available drives and substitute the correct letter. Reboot Windows if requested.

The QEMU user-network backend should then provide approximately:

```text
Guest IPv4:       10.0.2.15
Default gateway:  10.0.2.2
DNS server:       10.0.2.3
```

Check in Windows:

```cmd
ipconfig /all
ping 10.0.2.2
nslookup microsoft.com
```

QEMU user networking uses NAT. Incoming connections to Windows require explicit `hostfwd` options, which are not enabled
by the default launcher.

## 10. Graphics expectations

The default is `ramfb`, which is reliable for Windows ARM64 but is only a linear framebuffer. It is normal for Task
Manager not to show a GPU.

The VirtIO ISO contains the ARM64 display-only driver:

```text
viogpudo\w10\ARM64\viogpudo.inf
```

## 11. Backup an installed VM

First shut Windows down completely. Do not back up a live QCOW2/NVRAM pair.

Then, from the repository directory on the Mac:

```sh
./backup-from-phone.sh
```

The script refuses to run while `qemu-system-aarch64` is active. It pulls:

```text
/sdcard/Limbo/QEMU_VARS.fd
/sdcard/Limbo/win.qcow2
/sdcard/Limbo/win10.iso
/sdcard/Limbo/virtio-win.iso
/data/local/tmp/libkvm_flash0_only.so
/data/local/tmp/kvm_flash0_only.c
/data/local/tmp/limbo_kvm_untrusted29.zip
/data/local/tmp/start-win10-kvm.sh
```

The three large files remain ignored by Git.

## 12. Restore an existing complete backup

Place the ignored local files next to `restore-to-phone.sh`:

```text
win.qcow2
win10.iso
virtio-win.iso
```

Then run on the Mac:

```sh
./restore-to-phone.sh
```

After the transfer finishes, start the VM from inside Termux:

```sh
su -c '/data/local/tmp/start-win10-kvm.sh'
```

## SELinux module

`limbo_kvm_untrusted29.zip` grants the `untrusted_app_29` SELinux domain access to `kvm_device`. This was created for
starting KVM directly from a compatible Limbo app build. It is **not required** for the documented Root/Termux launcher.

The policy applies to every app in `untrusted_app_29`, not only Limbo. Review that security trade-off before installing
it through KernelSU.

## Troubleshooting

### `kvm support: enabled` does not appear

Check `/dev/kvm`, kernel KVM configuration, EL2 availability, root permission, and SELinux denials. This repository
cannot repair a missing host hypervisor.

### `Could not set register demuxed reg ...`

Use a host KVM kernel with normalized cache identification registers. Older kernels can reject saved register values
after a thread moves between CPU implementations with different cache geometry.

### `Guest has not initialized the display yet`

For the default Windows setup, ensure `-device ramfb` remains enabled and that the EDK2 code/variables files are both
exactly 64 MiB pflash images.

### No network adapter in Windows

Attach `virtio-win.iso` and install `NetKVM\w10\ARM64\netkvm.inf`. The former QEMU `usb-net` experiment is intentionally
not used because Windows probed it as a serial CDC interface rather than a working network adapter.
