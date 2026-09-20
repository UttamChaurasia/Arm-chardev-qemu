#!/bin/bash
# Boot the emulated ARM machine (QEMU 'virt', Cortex-A15).
#   ./scripts/run-qemu.sh            interactive shell on the serial console
#   ./scripts/run-qemu.sh autotest   scripted self-test, then power off
# Quit an interactive session with: poweroff -f   (or Ctrl-A then X)
set -euo pipefail
cd "$(dirname "$0")/.."
KDIR=${KDIR:-$(pwd)/../work/linux}
KERNEL=$KDIR/arch/arm/boot/zImage
ROOTFS=build/rootfs.cpio.gz
# Fall back to the shipped prebuilt images if you have not built your own.
[ -f "$KERNEL" ] || KERNEL=prebuilt/zImage
[ -f "$ROOTFS" ] || ROOTFS=prebuilt/rootfs.cpio.gz
exec qemu-system-arm -M virt -cpu cortex-a15 -m 256 -smp 1 -nic none \
    -kernel "$KERNEL" -initrd "$ROOTFS" \
    -append "console=ttyAMA0 panic=-1 $*" -nographic -no-reboot
