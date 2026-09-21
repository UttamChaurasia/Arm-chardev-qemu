#!/bin/bash
# Produce build/virt-mychardev.dtb = QEMU virt's own DTB + our node.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

qemu-system-arm -M virt,dumpdtb=build/virt.dtb -cpu cortex-a15 -m 256 -nographic -nic none
dtc -q -I dtb -O dts -o build/virt.dts build/virt.dtb

python3 - <<'PY'
src = open("build/virt.dts").read().rstrip().splitlines()
node = open("dts/mychardev-node.dtsi").read()
# strip C comment header from the fragment
import re
node = re.sub(r"/\*.*?\*/", "", node, flags=re.S)
# the root node's closing "};" is the last "};" line
idx = max(i for i, l in enumerate(src) if l.strip() == "};")
src[idx:idx] = node.strip("\n").splitlines()
open("build/virt-mychardev.dts", "w").write("\n".join(src) + "\n")
PY

dtc -q -I dts -O dtb -o build/virt-mychardev.dtb build/virt-mychardev.dts
echo "wrote build/virt-mychardev.dtb"
