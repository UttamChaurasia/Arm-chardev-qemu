#!/bin/bash
# Report which host tools are present. Exit status is the number of missing
# REQUIRED tools for the chosen mode.
#   ./scripts/check-env.sh          tools needed to RUN the prebuilt images
#   ./scripts/check-env.sh build    additionally, tools needed to build from source
set -uo pipefail
MODE=${1:-run}
missing=0

need() {     # need <command> <apt package> <why> [optional]
    if command -v "$1" >/dev/null 2>&1; then
        printf '  [ ok ] %-22s %s\n' "$1" "$3"
    elif [ "${4:-}" = optional ]; then
        printf '  [warn] %-22s %s (optional: sudo apt install %s)\n' "$1" "$3" "$2"
    else
        printf '  [MISS] %-22s %s (sudo apt install %s)\n' "$1" "$3" "$2"
        missing=$((missing + 1))
    fi
}

echo "host: $(uname -srm)"
grep -qi microsoft /proc/version 2>/dev/null && echo "      running under WSL"
echo "== to run the prebuilt images =="
need qemu-system-arm qemu-system-arm "emulates the ARM board"
need gdb-multiarch   gdb-multiarch   "GDB demo" optional
need python3         python3         "trace/GDB helper scripts" optional

if [ "$MODE" = build ]; then
    echo "== to build from source =="
    need arm-linux-gnueabi-gcc gcc-arm-linux-gnueabi "ARM cross compiler"
    need dtc     device-tree-compiler "device tree compiler"
    need make    make                 "build driver"
    need bison   bison                "kernel build"
    need flex    flex                 "kernel build"
    need bc      bc                   "kernel build"
    need cpio    cpio                 "initramfs"
    need curl    curl                 "downloads kernel/BusyBox"
    if [ ! -f /usr/arm-linux-gnueabi/lib/libc.a ]; then
        echo "  [MISS] ARM libc headers/static libc (sudo apt install libc6-dev-armel-cross)"
        missing=$((missing + 1))
    else
        echo "  [ ok ] ARM libc (static)"
    fi
    [ -f /usr/include/openssl/opensslv.h ] || { echo "  [MISS] libssl-dev (sudo apt install libssl-dev)"; missing=$((missing+1)); }
    [ -f /usr/include/libelf.h ] || { echo "  [MISS] libelf-dev (sudo apt install libelf-dev)"; missing=$((missing+1)); }
fi

# prebuilt images present?
if [ -d "$(dirname "$0")/../prebuilt" ]; then
    echo "prebuilt/: found"
else
    echo "prebuilt/: not found (download the release asset, or build from source)"
fi

if [ "$missing" -eq 0 ]; then echo "RESULT: environment OK"; else echo "RESULT: $missing required item(s) missing"; fi
exit "$missing"
