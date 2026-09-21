# Linux Character Device Driver — Cross-Compiled for ARM (QEMU)

A Linux kernel character device driver, cross-compiled for ARM and run
entirely under QEMU emulation. No physical hardware is used anywhere —
the ARM target, its devices and its interrupt controller are emulated in software.

Delivered in three phases. **This archive is Phase 2** (it includes all of Phase 1).

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Toolchain, module lifecycle, `/dev` node, file ops, kernel buffer, ioctl | done, tested |
| 2 | Device Tree node + `platform_driver` probe, `request_irq` handler | **done, tested** |
| 3 | GDB against QEMU's stub, deliberate kernel oops traced to a source line | not started |

## Status

- [x] Cross-compilation toolchain verified (`arm-linux-gnueabi-gcc`, static binaries run under QEMU)
- [x] Kernel module skeleton loads/unloads cleanly (`insmod` / `rmmod`, visible in `dmesg`)
- [x] Character device registered, `/dev/mychardev` created
- [x] `open` / `release` / `read` / `write` file operations implemented
- [x] Kernel-space buffer via `kmalloc` / `kfree`, `copy_to_user` / `copy_from_user` used correctly
- [x] Custom `ioctl` commands implemented (`RESET`, `GET_LEN`, `GET_CAP`, `GET_IRQCNT`, `TRIGGER_IRQ`)
- [x] Device Tree node added; module is a `platform_driver` that probes via the `demo,mychardev` compatible string
- [x] Interrupt handler registered (`request_irq`) on a GIC interrupt taken from the DT node
- [ ] GDB attached to QEMU's `-s -S` stub, breakpoint hit inside the module (Phase 3)
- [ ] Deliberate kernel oops triggered and traced back to source line (Phase 3)

Verified with: Ubuntu 24.04 host, `arm-linux-gnueabi-gcc` 13, QEMU 8.2.2,
Linux 6.6 (`virt` machine, Cortex-A15), BusyBox 1.36.1.

## Not covered by this project

No physical board, no real JTAG hardware, no wireless stack, no AOSP/Android
internals, no RTOS. This demonstrates kernel/driver fundamentals and a
BSP-style workflow on emulated hardware; it is not a substitute for real board
bring-up. In particular the interrupt is **raised by software** (see below),
not by a real peripheral asserting a line.

## Quick start (prebuilt images)

```bash
sudo apt install qemu-system-arm
./scripts/run-qemu.sh autotest        # scripted end-to-end test, powers off at the end
./scripts/run-qemu.sh                 # interactive shell
./scripts/run-qemu.sh nodt autotest   # stock DTB: exercises the no-DT fallback path
```

Interactive session:

```sh
cat /proc/device-tree/mychardev/compatible
insmod /lib/modules/chardev.ko
dmesg | tail                                    # "probed via Device Tree (buffer=4096, irq=21)"
ls /sys/bus/platform/drivers/mychardev/         # the bound platform driver
echo hello > /dev/mychardev ; cat /dev/mychardev
chardev_test                                    # includes the IRQ checks
grep mychardev /proc/interrupts                 # per-CPU count from the GIC
rmmod chardev
poweroff -f
```

`prebuilt/` holds a matching kernel, rootfs, DTB and `chardev.ko`; keep them together.

## Building everything yourself

Host packages: `gcc-arm-linux-gnueabi libc6-dev-armel-cross qemu-system-arm
device-tree-compiler python3 bc flex bison libssl-dev libelf-dev cpio curl`.

```bash
./scripts/build-kernel.sh   # Linux 6.6 -> ../work/linux (~10 min, single core)
./scripts/make-dtb.sh       # QEMU virt DTB + our node -> build/virt-mychardev.dtb
./scripts/build.sh          # chardev.ko
./scripts/build-rootfs.sh   # BusyBox + module + test -> build/rootfs.cpio.gz
./scripts/run-qemu.sh autotest
```

## How Phase 2 works

**Device Tree.** QEMU's `virt` machine generates its own device tree at boot.
`make-dtb.sh` dumps it (`-machine virt,dumpdtb=`), decompiles it, inserts the
node in `dts/mychardev-node.dtsi`, and recompiles it. It is a plain node merged
into the base DTB, *not* a runtime overlay: `-dtb` takes a complete tree, and
this kernel/bootloader combination has no overlay support.

```dts
mychardev {
    compatible = "demo,mychardev";
    demo,buffer-size = <4096>;
    interrupts = <0 60 1>;      /* GIC SPI 60, edge rising */
};
```

**platform_driver.** `chardev_dt.c` matches `demo,mychardev`, reads the optional
`demo,buffer-size` property, creates the character device, and gets its IRQ
with `platform_get_irq_optional()`. If no matching node exists, module init falls
back to creating the device without an interrupt, so the Phase 1 behaviour still works.

**Interrupt.** SPI 60 is unused on `virt` (UART=1, RTC=2, PCIe=3-6, GPIO=7,
virtio-mmio=16-47). `request_irq()` installs `mychar_isr()`. QEMU has no peripheral
driving this line, so `MYCHAR_IOC_TRIGGER_IRQ` calls
`irq_set_irqchip_state(irq, IRQCHIP_STATE_PENDING, true)`, which sets the
interrupt pending in the emulated GIC. The CPU then takes and dispatches it
through the normal IRQ path. The handler and the `request_irq`/`free_irq` and
GIC dispatch code are the real thing; only the *source* of the assertion is
substituted.

## What the tests check

`chardev_test` (12 file/ioctl/error checks + 2 IRQ checks) plus `selftest.sh`:
DT node visible in `/proc/device-tree`, platform driver bound in sysfs,
`/proc/interrupts` shows the handler, `free_irq` on `rmmod`, and a
**20-cycle load/unload stress loop** that fires interrupts each cycle and then
confirms `dmesg` has no oops/BUG/WARNING lines.

## Layout

```
Makefile                    kbuild out-of-tree Makefile (chardev.ko)
src/chardev_main.c          init/exit, file_operations, ioctl, create/destroy
src/chardev_dt.c            platform_driver, OF match table, probe/remove
src/chardev_irq.c           request_irq handler, software IRQ trigger
src/chardev.h               shared driver structure
include/mychardev_ioctl.h   ioctl ABI shared with user space
dts/mychardev-node.dtsi     node merged into the virt DTB
dts/virt-mychardev.generated.dts   the resulting full tree (for reference)
user/chardev_test.c         user-space test
rootfs/                     init and selftest.sh
scripts/                    build-kernel / make-dtb / build / build-rootfs / run-qemu
kernel/mychardev.config     minimal ARM 'virt' kernel config fragment
prebuilt/                   zImage, rootfs, DTB, chardev.ko
```

## Phase 3 plan

Module symbols exist only after `insmod`, so GDB needs
`add-symbol-file chardev.ko <address from /sys/module/chardev/sections/.text>`.
The kernel is already built with `CONFIG_DEBUG_INFO` and no KASLR
(ARM32 has no kernel address randomisation in this config). The oops demo will be a
separate module so the main driver stays clean.
