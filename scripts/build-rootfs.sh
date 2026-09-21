#!/bin/bash
# Build build/rootfs.cpio.gz: static BusyBox + chardev.ko + test programs.
# Needs scripts/build-kernel.sh and scripts/build.sh to have run first.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
KDIR=${KDIR:-$ROOT/../work/linux}
CROSS=arm-linux-gnueabi-
mkdir -p build

BB=$ROOT/../work/busybox
if [ ! -x "$BB/busybox" ]; then
    if [ ! -d "$BB" ]; then
        curl -L -o "$ROOT/../work/busybox.tar.gz" \
            https://codeload.github.com/mirror/busybox/tar.gz/refs/tags/1_36_1
        tar xzf "$ROOT/../work/busybox.tar.gz" -C "$ROOT/../work"
        mv "$ROOT/../work/busybox-1_36_1" "$BB"
    fi
    make -C "$BB" ARCH=arm CROSS_COMPILE=$CROSS defconfig
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "$BB/.config"
    sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$BB/.config"   # fails on new headers
    sed -i "s/^CONFIG_CROSS_COMPILER_PREFIX=.*/CONFIG_CROSS_COMPILER_PREFIX=\"$CROSS\"/" "$BB/.config"
    make -C "$BB" ARCH=arm CROSS_COMPILE=$CROSS oldconfig </dev/null >/dev/null
    make -C "$BB" ARCH=arm CROSS_COMPILE=$CROSS -j"$(nproc)"
fi

${CROSS}gcc -static -O2 -Wall -o build/chardev_test user/chardev_test.c

# initramfs manifest for the kernel's gen_init_cpio (no root / mknod needed)
M=build/rootfs.list
{
  for d in bin sbin proc sys dev lib lib/modules; do echo "dir /$d 755 0 0"; done
  echo "nod /dev/console 600 0 0 c 5 1"
  echo "nod /dev/null 666 0 0 c 1 3"
  echo "file /bin/busybox $BB/busybox 755 0 0"
  echo "file /init rootfs/init 755 0 0"
  echo "file /bin/selftest.sh rootfs/selftest.sh 755 0 0"
  echo "file /bin/chardev_test build/chardev_test 755 0 0"
  echo "file /lib/modules/chardev.ko chardev.ko 644 0 0"
  echo "file /lib/modules/oops_demo.ko oops_demo.ko 644 0 0"
  echo "file /bin/gdbdemo.sh rootfs/gdbdemo.sh 755 0 0"
  for a in sh ash cat echo ls sleep mount umount insmod rmmod lsmod dmesg grep mknod \
           poweroff reboot sleep setsid cttyhack uname mkdir cp rm vi head tail; do
      echo "slink /bin/$a busybox 777 0 0"
  done
} > "$M"
"$KDIR/usr/gen_init_cpio" "$M" | gzip -9 > build/rootfs.cpio.gz
echo "wrote build/rootfs.cpio.gz"
