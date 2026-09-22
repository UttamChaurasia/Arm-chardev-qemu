#!/bin/bash
# Turn a kernel oops into a source line.
#   ./scripts/trace-oops.sh <oops-log> [module.ko]
# Reads "PC is at <sym>+0x<off>/... [<module>]" and "LR is at ..." from the
# log and resolves each with GDB against the module's debug info. GDB
# (unlike bare addr2line) copes with the Thumb-2 bit on ARM function addresses.
set -euo pipefail
cd "$(dirname "$0")/.."
LOG=${1:?usage: trace-oops.sh <oops-log> [module.ko]}
GDB=${GDB:-gdb-multiarch}
. scripts/paths.sh

resolve() {   # $1 = "PC" | "LR"
    local line sym off mod ko
    line=$(grep -aE "^$1 is at " "$LOG" | tr -d '\r' | head -1) || true
    [ -n "$line" ] || return 0
    sym=$(echo "$line" | sed -E 's/^[A-Z]+ is at ([A-Za-z0-9_.]+)\+0x([0-9a-f]+)\/.*/\1/')
    off=$(echo "$line" | sed -E 's/^[A-Z]+ is at ([A-Za-z0-9_.]+)\+0x([0-9a-f]+)\/.*/\2/')
    mod=$(echo "$line" | sed -nE 's/.*\[([A-Za-z0-9_]+)\]$/\1/p')
    echo "== $1: $sym+0x$off ${mod:+in module $mod}"
    if [ -z "$mod" ]; then
        echo "   (core-kernel symbol: use vmlinux instead: $GDB vmlinux -batch -ex 'list *($sym+0x$off)')"
        return 0
    fi
    ko=${2:-${mod}.ko}
    [ -f "$ko" ] || ko=prebuilt/${mod}.ko
    $GDB -q -batch -ex "set substitute-path $(built_at "$ko") $(pwd)" -ex "info line *($sym+0x$off)" -ex "list *($sym+0x$off)" "$ko" 2>&1 \
        | grep -v "^warning\|^Reading symbols\|^$" | sed 's/^/   /'
}

resolve PC "${2:-}"
resolve LR "${2:-}"

echo "== call trace (innermost first)"
grep -aE "^ [A-Za-z0-9_.]+( \[[a-z_0-9]+\])? from " "$LOG" | tr -d '\r' | sed 's/^/   /'
