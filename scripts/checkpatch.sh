#!/bin/bash
# Run the Linux kernel's own style checker over the driver sources.
#   KDIR=/path/to/linux ./scripts/checkpatch.sh
# oops_demo.c is checked with VOLATILE ignored: the volatile store is what
# forces the compiler to emit the faulting write, so the warning is intentional.
set -uo pipefail
cd "$(dirname "$0")/.."
KDIR=${KDIR:-$(pwd)/../work/linux}
CP=$KDIR/scripts/checkpatch.pl
[ -f "$CP" ] || { echo "checkpatch.pl not found in $KDIR (set KDIR to a kernel tree)"; exit 2; }

rc=0
for f in src/chardev_main.c src/chardev_dt.c src/chardev_irq.c src/chardev.h include/mychardev_ioctl.h; do
    perl "$CP" --no-tree --terse -f "$f" || rc=1
done
perl "$CP" --no-tree --terse --ignore VOLATILE -f src/oops_demo.c || rc=1

[ $rc -eq 0 ] && echo "checkpatch: clean" || echo "checkpatch: findings above"
exit $rc
