# arm-chardev-qemu

**A Linux character device driver for ARM, cross-compiled and debugged entirely under QEMU** — Device Tree, `platform_driver`, IRQ handling, GDB and kernel-oops tracing, with no physical hardware.

A Linux kernel character device driver, cross-compiled for ARM and run
entirely under QEMU emulation. No physical hardware is used anywhere — the ARM
target, its devices and its interrupt controller are emulated in software.

## Status

This list is the source of truth for what the repo does. Every item was run
and verified under QEMU (see `docs/sample-output/`).

- [x] Cross-compilation toolchain verified (`arm-linux-gnueabi-gcc`; static binaries run under QEMU)
- [x] Kernel module skeleton loads/unloads cleanly (`insmod` / `rmmod`, visible in `dmesg`)
- [x] Character device registered, `/dev/mychardev` created
- [x] `open` / `release` / `read` / `write` file operations implemented
- [x] Kernel-space buffer via `kmalloc` / `kfree`, `copy_to_user` / `copy_from_user` used correctly
- [x] Custom `ioctl` commands implemented (`RESET`, `GET_LEN`, `GET_CAP`, `GET_IRQCNT`, `TRIGGER_IRQ`)
- [x] Device Tree node added; module is a `platform_driver` that probes via the `demo,mychardev` compatible string
- [x] Interrupt handler registered (`request_irq`) on a GIC interrupt taken from the DT node
- [x] GDB attached to QEMU's `-s -S` stub; breakpoint hit inside the module
- [x] Deliberate kernel oops triggered and traced back to a source line

Quick start also confirmed on Ubuntu 26.04 under WSL2 (see `docs/WSL.md`).

Built and verified with: Ubuntu 24.04 host, `arm-linux-gnueabi-gcc` 13, QEMU 8.2.2,
Linux 6.6 (`virt` machine, Cortex-A15, Thumb-2 kernel), BusyBox 1.36.1, GDB 15.

## Beyond the checklist

Added after the ten items above, each with its own test:

- **`llseek`** with `SEEK_END` relative to the stored length (bounded by the capacity).
- **`buffer_size` module parameter** for the no-DT path (invalid values are rejected at `insmod`).
- **sysfs `stats` attribute** (`/sys/class/mychardev/mychardev/stats`): opens, reads,
  writes, bytes, interrupts, length and capacity, cross-checked against what user space did.
- **Regression runner** (`scripts/run-tests.sh`), **kernel style check**
  (`scripts/checkpatch.sh`) and a **host environment checker** (`scripts/check-env.sh`).

## Skills demonstrated

| Area | How |
|------|-----|
| Kernel module development | Module lifecycle, `printk`, out-of-tree kbuild Makefile, goto-unwind error handling |
| Device driver fundamentals | `file_operations`, `cdev` + class + `/dev` node, `ioctl` ABI in a shared header |
| Kernel-space memory management | `kmalloc`/`kfree`; every transfer via `copy_to_user`/`copy_from_user`; bad pointer returns `-EFAULT` (tested) |
| Concurrency | Mutex guarding buffer and length; `atomic_t` for the interrupt counter |
| Cross-compilation | ARM target built from an x86 host toolchain; kernel, BusyBox, module and tests all cross-built |
| Board-support-style integration | Device Tree node + `platform_driver` probe with an OF match table and DT properties |
| Interrupt-driven programming | `request_irq`/`free_irq` on a GIC interrupt described in the DT; verified in `/proc/interrupts` |
| Remote/target debugging | GDB over QEMU's gdbstub: `add-symbol-file` for a loaded module, hardware breakpoints, inspecting kernel state |
| Kernel fault diagnosis | Reading an ARM oops (PC/LR, registers, call trace, `Code:` bytes) and resolving it to a source line, cross-checked by disassembly |

## Not covered by this project

Stated plainly, not implied:

- **No physical board and no real JTAG hardware.** GDB here talks to QEMU's
  gdbstub. The debugger workflow is the same (symbols, breakpoints, stepping,
  memory inspection); the transport is not JTAG and there is no real
  silicon behaviour, timing or bus fault.
- **The interrupt is raised by software.** QEMU has no peripheral driving the
  line, so an ioctl marks the interrupt pending in the emulated GIC. The
  handler, `request_irq`/`free_irq` and the GIC dispatch path are real; the
  *source* of the assertion is substituted.
- **The Device Tree node is merged into the base DTB**, not applied as a
  runtime overlay (`-dtb` needs a complete tree; no overlay support here).
- No wireless stack (WiFi/Bluetooth/LTE), no AOSP/Android internals, no RTOS.

This demonstrates kernel/driver fundamentals and a BSP-style workflow on
emulated hardware. It is not a substitute for hands-on radio or board bring-up.

## Getting the prebuilt images

The repository holds source only. The prebuilt kernel, rootfs, DTB, modules and
`vmlinux.gz` (about 25 MB) are distributed as a release asset: extract it so that
`prebuilt/` sits next to `scripts/`. Or skip them and build everything yourself
(see "Building everything yourself").

## Quick start (prebuilt images, nothing to compile)

```bash
sudo apt install qemu-system-arm gdb-multiarch     # gdb only needed for debugging
./scripts/check-env.sh                             # are the host tools installed?
./scripts/run-tests.sh                             # run every mode and check the results
./scripts/run-qemu.sh autotest                     # end-to-end test, powers off at the end
./scripts/run-qemu.sh autotest oopsdemo            # ...plus a deliberate kernel oops
./scripts/run-qemu.sh nodt autotest                # stock DTB: the no-DT fallback path
./scripts/run-qemu.sh                              # interactive shell
./scripts/gdb-demo.sh                              # automated GDB session
./scripts/trace-oops.sh oops.log                   # oops -> source line (see docs/DEBUGGING.md)
```

Interactive session:

```sh
insmod /lib/modules/chardev.ko
dmesg | tail                                   # "probed via Device Tree (buffer=4096, irq=21)"
echo hello > /dev/mychardev ; cat /dev/mychardev
chardev_test
grep mychardev /proc/interrupts
rmmod chardev
insmod /lib/modules/oops_demo.ko               # deliberate oops
poweroff -f
```

`prebuilt/` holds a matching kernel, rootfs, DTB, modules and `vmlinux.gz`
(for GDB). They must stay together: a module only loads into the kernel it was
built against.

## Building everything yourself

Host packages: `gcc-arm-linux-gnueabi libc6-dev-armel-cross qemu-system-arm
gdb-multiarch device-tree-compiler python3 bc flex bison libssl-dev libelf-dev cpio curl`.

```bash
./scripts/build-kernel.sh   # Linux 6.6 -> ../work/linux (~10 min single core)
./scripts/make-dtb.sh       # QEMU virt DTB + our node -> build/virt-mychardev.dtb
./scripts/build.sh          # chardev.ko and oops_demo.ko
./scripts/build-rootfs.sh   # BusyBox + modules + tests -> build/rootfs.cpio.gz
./scripts/run-qemu.sh autotest
```

Do not run `make clean` in this directory expecting `prebuilt/` to survive:
kbuild's clean deletes every `*.ko` and `*.dtb` beneath it.

## How it works

**Driver** (`src/`). `chardev_main.c` registers a `cdev`, class and `/dev` node
and implements the file operations and ioctls. Writes land at the file offset
and the valid length becomes `offset + count` ("last write wins"), so
`echo x > /dev/mychardev` replaces the contents while repeated `write()`s on one
descriptor append; writes past the 4 KiB capacity are short, then `-ENOSPC`.
`chardev_dt.c` is the `platform_driver`: it matches `demo,mychardev`, reads
`demo,buffer-size`, and gets its interrupt from the node. If no node exists,
module init falls back to a device without an interrupt. `chardev_irq.c` holds
the handler and the software trigger (`irq_set_irqchip_state(..., PENDING, true)`).

**Device Tree** (`dts/`). `make-dtb.sh` dumps QEMU virt's own tree, inserts
`mychardev { compatible = "demo,mychardev"; interrupts = <0 60 1>; }` (SPI 60,
unused on virt) and recompiles. `virt-mychardev.generated.dts` is the result.

**Tests.** `user/chardev_test.c` runs 23 checks (file operations, ioctl and error paths,
`lseek`, the sysfs statistics, and 2 interrupt checks that are skipped when there is no
DT node, leaving 21). `rootfs/selftest.sh` adds: DT node visible under `/proc/device-tree`,
platform driver bound in sysfs, the handler listed in `/proc/interrupts`, IRQ
released on `rmmod`, and a 20-cycle load/unload stress loop (interrupt fired
each cycle) that must leave no oops/BUG/WARNING in `dmesg`. In no-DT boots it also checks
the `buffer_size` parameter and its rejections. `scripts/run-tests.sh` runs every
mode and asserts 22 expectations (23 when a kernel tree is available for checkpatch),
including that the fault detector fires on the
deliberate oops.

**Debugging** — see `docs/DEBUGGING.md` for the GDB session and how to read
the oops, including the pitfalls found along the way (Thumb-2 addresses,
`hbreak` for not-yet-loaded modules, why `addr2line` fails on a `.ko`).

## Layout

```
Makefile                      kbuild out-of-tree Makefile (chardev.ko, oops_demo.ko)
src/chardev_main.c            init/exit, file_operations, ioctl, create/destroy
src/chardev_dt.c              platform_driver, OF match table, probe/remove
src/chardev_irq.c             request_irq handler, software IRQ trigger
src/chardev.h                 shared driver structure
src/oops_demo.c               separate module that faults on purpose
include/mychardev_ioctl.h     ioctl ABI shared with user space
dts/                          node fragment + resulting full device tree
user/chardev_test.c           user-space test program
rootfs/                       init, selftest.sh, gdbdemo.sh
scripts/                      build-kernel, make-dtb, build, build-rootfs, run-qemu,
                              run-tests, check-env, checkpatch, gdb-demo, mychardev.gdb,
                              paths.sh, trace-oops
kernel/mychardev.config       minimal ARM 'virt' kernel config fragment
docs/ARCHITECTURE.md          how the pieces fit: stack, DT probe, IRQ path, locking
docs/DEBUGGING.md             GDB + oops walkthrough
docs/TROUBLESHOOTING.md       problems actually hit, with fixes
docs/WSL.md                   running on Windows with WSL2
docs/sample-output/           captured real output (selftest, oops, GDB session)
prebuilt/                     zImage, rootfs, DTB, modules, vmlinux.gz
```
