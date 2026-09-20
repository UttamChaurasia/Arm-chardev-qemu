#!/bin/bash
# Fetch Linux 6.6, apply kernel/mychardev.config on top of allnoconfig,
# and build zImage + vmlinux + module build support.
# Result: work/linux (used as KDIR by the Makefile).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
mkdir -p ../work && cd ../work
if [ ! -d linux ]; then
    curl -L -o linux.tar.gz https://codeload.github.com/torvalds/linux/tar.gz/refs/tags/v6.6
    tar xzf linux.tar.gz && mv linux-6.6 linux && rm linux.tar.gz
fi
cd linux
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-
make allnoconfig
./scripts/kconfig/merge_config.sh -m .config "$ROOT/kernel/mychardev.config"
make olddefconfig
make -j"$(nproc)" zImage modules_prepare vmlinux usr/gen_init_cpio
echo "kernel ready: $(pwd)/arch/arm/boot/zImage"
