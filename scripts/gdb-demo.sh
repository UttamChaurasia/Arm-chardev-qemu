#!/bin/bash
# Fully automated GDB session against the emulated ARM board:
#   1. boot once to read the module's load addresses from sysfs
#   2. boot again frozen (-s -S), attach GDB, break inside chardev's write handler
#   3. resume the guest; it writes to /dev/mychardev; GDB stops in mychar_write
set -euo pipefail
cd "$(dirname "$0")/.."
GDB=${GDB:-gdb-multiarch}
KDIR=${KDIR:-$(pwd)/../work/linux}
VMLINUX=$KDIR/vmlinux
if [ ! -f "$VMLINUX" ]; then
    [ -f prebuilt/vmlinux.gz ] || { echo "need $VMLINUX or prebuilt/vmlinux.gz"; exit 1; }
    mkdir -p build && gunzip -c prebuilt/vmlinux.gz > build/vmlinux && VMLINUX=build/vmlinux
fi
KO=chardev.ko; [ -f "$KO" ] || KO=prebuilt/chardev.ko
mkdir -p build
# Debug info in the prebuilt .ko embeds the path it was built in; map it to this checkout.
BUILT_AT=/home/claude/kernel-chardev-driver-final

# Breakpoint lines are looked up from markers in the source, so edits to
# src/chardev_main.c cannot silently leave the script pointing at the wrong lines.
BEFORE=$(grep -n 'gdb: before-copy' src/chardev_main.c | head -1 | cut -d: -f1)
AFTER=$(grep -n 'gdb: after-copy' src/chardev_main.c | head -1 | cut -d: -f1)
[ -n "$BEFORE" ] && [ -n "$AFTER" ] || { echo "gdb markers missing in src/chardev_main.c"; exit 1; }

echo ">> step 1: reading module load addresses from the guest"
./scripts/run-qemu.sh gdbaddr 2>&1 | tr -d '\r' > build/addr.log
LINE=$(grep -a MODTEXT build/addr.log)
TEXT=$(echo "$LINE" | sed -E 's/.*MODTEXT=(0x[0-9a-f]+).*/\1/')
DATA=$(echo "$LINE" | sed -E 's/.*MODDATA=(0x[0-9a-f]+).*/\1/')
BSS=$(echo  "$LINE" | sed -E 's/.*MODBSS=(0x[0-9a-f]+).*/\1/')
echo "   .text=$TEXT .data=$DATA .bss=$BSS"

sed -e "s|^file vmlinux|file $VMLINUX|" \
    -e "s|^# set substitute-path .*|set substitute-path $BUILT_AT $(pwd)|" \
    -e "s|@BEFORE_COPY@|$BEFORE|" -e "s|@AFTER_COPY@|$AFTER|" \
    -e "s|^add-symbol-file .*|add-symbol-file $KO $TEXT -s .data $DATA -s .bss $BSS|" \
    scripts/mychardev.gdb > build/session.gdb

echo ">> step 2: starting QEMU frozen at reset, GDB stub on :1234"
./scripts/run-qemu.sh debug gdbrun > build/guest-console.log 2>&1 &
QPID=$!
trap 'kill $QPID 2>/dev/null || true' EXIT
sleep 2

echo ">> step 3: attaching GDB"
$GDB -q -batch -x build/session.gdb 2>&1 | grep -v "^warning: \|^Reading symbols" | tee build/gdb-session.log
wait $QPID 2>/dev/null || true
echo
echo ">> guest console (relevant lines):"
tr -d '\r' < build/guest-console.log | grep -aE "MODTEXT|GUEST|mychardev|hello gdb|gdbdemo"
