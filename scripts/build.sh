#!/bin/bash
# Cross-compile chardev.ko against the target kernel tree.
set -euo pipefail
cd "$(dirname "$0")/.."
make KDIR="${KDIR:-$(pwd)/../work/linux}"
file chardev.ko | cut -c1-110
