#!/bin/bash
# Boot the emulated ARM machine (QEMU 'virt', Cortex-A15).
#   ./scripts/run-qemu.sh            interactive shell, DT node + IRQ present
#   ./scripts/run-qemu.sh autotest   scripted self-test, then power off
#   ./scripts/run-qemu.sh debug      freeze at reset, wait for GDB on tcp::1234 (see docs/DEBUGGING.md)
#   ./scripts/run-qemu.sh nodt ...   boot QEMU's stock DTB (no mychardev node):
#                                    driver takes the no-IRQ fallback path
# Quit an interactive session with: poweroff -f   (or Ctrl-A then X)
set -euo pipefail
cd "$(dirname "$0")/.."
KDIR=${KDIR:-$(pwd)/../work/linux}
KERNEL=$KDIR/arch/arm/boot/zImage
ROOTFS=build/rootfs.cpio.gz
[ -f "$KERNEL" ] || KERNEL=prebuilt/zImage
[ -f "$ROOTFS" ] || ROOTFS=prebuilt/rootfs.cpio.gz
DTB="prebuilt/virt-mychardev.dtb"; [ -f build/virt-mychardev.dtb ] && DTB=build/virt-mychardev.dtb
DTBARG="-dtb $DTB"; GDBARG=""; ARGS=()
for a in "$@"; do
    case "$a" in
        nodt)  DTBARG="" ;;
        debug) GDBARG="-s -S" ;;
        *)     ARGS+=("$a") ;;
    esac
done
exec qemu-system-arm -M virt -cpu cortex-a15 -m 256 -smp 1 -nic none \
    -kernel "$KERNEL" -initrd "$ROOTFS" $DTBARG \
    -append "console=ttyAMA0 panic=-1 ${ARGS[*]:-}" -nographic -no-reboot $GDBARG
