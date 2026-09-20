# Linux Character Device Driver — Cross-Compiled for ARM (QEMU)

A Linux kernel character device driver, cross-compiled for ARM and run
entirely under QEMU emulation. No physical hardware is used anywhere —
the ARM target and its devices are emulated in software.

The project is delivered in three phases. **This archive is Phase 1.**

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Toolchain, module lifecycle, `/dev` node, file ops, kernel buffer, ioctl | **done, tested** |
| 2 | Device Tree node + `platform_driver` probe, `request_irq` handler | not started |
| 3 | GDB against QEMU's stub, deliberate kernel oops traced to a source line | not started |

## Status

- [x] Cross-compilation toolchain verified (`arm-linux-gnueabi-gcc` hello world running under QEMU)
- [x] Kernel module skeleton loads/unloads cleanly (`insmod` / `rmmod`, visible in `dmesg`)
- [x] Character device registered, `/dev/mychardev` created
- [x] `open` / `release` / `read` / `write` file operations implemented
- [x] Kernel-space buffer via `kmalloc` / `kfree`, `copy_to_user` / `copy_from_user` used correctly
- [x] Custom `ioctl` command implemented (`RESET`, `GET_LEN`, `GET_CAP`)
- [ ] Device Tree node; module converted to a `platform_driver` (Phase 2)
- [ ] Interrupt handler via `request_irq` (Phase 2)
- [ ] GDB attached to QEMU's `-s -S` stub, breakpoint hit in the module (Phase 3)
- [ ] Deliberate kernel oops traced back to a source line (Phase 3)

This list reflects what the repo actually does. Phase 1 was built and
verified with: Ubuntu 24.04 host, `arm-linux-gnueabi-gcc` 13, QEMU 8.2.2,
Linux 6.6, BusyBox 1.36.1.

## Not covered by this project

No physical board, no real JTAG hardware, no wireless stack, no AOSP/Android
internals, no RTOS. This demonstrates kernel/driver fundamentals on emulated
hardware; it is not a substitute for real board bring-up experience.

## Quick start (prebuilt images, no kernel build needed)

```bash
sudo apt install qemu-system-arm
./scripts/run-qemu.sh autotest     # scripted end-to-end test, powers off at the end
./scripts/run-qemu.sh              # interactive shell
```

Inside the interactive shell:

```sh
hello
insmod /lib/modules/chardev.ko
dmesg | tail
echo "hello" > /dev/mychardev
cat /dev/mychardev
chardev_test
rmmod chardev
poweroff -f
```

`prebuilt/` holds a matching kernel (`zImage`), rootfs and `chardev.ko`.
They must stay together: a module only loads into the kernel it was built against.

## Building everything yourself

Host packages: `gcc-arm-linux-gnueabi libc6-dev-armel-cross qemu-system-arm
bc flex bison libssl-dev libelf-dev cpio curl`.

```bash
./scripts/build-kernel.sh   # downloads Linux 6.6 into ../work/linux, ~10 min on 1 core
./scripts/build.sh          # cross-compiles chardev.ko against that tree
./scripts/build-rootfs.sh   # BusyBox + module + tests -> build/rootfs.cpio.gz
./scripts/run-qemu.sh autotest
```

## Layout

```
Makefile                 kbuild out-of-tree Makefile (module: chardev.ko)
src/chardev_main.c       module init/exit, file_operations, kmalloc buffer, ioctl
include/mychardev_ioctl.h  ioctl numbers shared with user space
user/hello.c             cross-toolchain sanity check
user/chardev_test.c      12-check user-space test (open/read/write/ioctl/errors)
rootfs/init, selftest.sh PID 1 and the scripted test
kernel/mychardev.config  minimal ARM 'virt' kernel config fragment
scripts/                 build-kernel / build / build-rootfs / run-qemu
prebuilt/                ready-to-boot zImage, rootfs, chardev.ko
```

## Design notes

- **Buffer semantics:** a write lands at the file offset and the valid length
  becomes `offset + count` (last write wins). `echo x > /dev/mychardev`
  therefore replaces the contents; repeated `write()`s on one descriptor append.
  Writes past the 4 KiB capacity are short, then return `-ENOSPC`.
- **User/kernel boundary:** every transfer uses `copy_to_user` /
  `copy_from_user`; a bad user pointer returns `-EFAULT` instead of oopsing
  (covered by a test).
- **Locking:** one mutex guards the buffer and length; the lock is taken with
  `mutex_lock_interruptible` on the read/write paths.
- **Object naming:** the module is `chardev.ko` built from `chardev_main.o`;
  a source file named `chardev.c` would collide with the module object.
- **Init error handling:** goto-unwind in reverse order of acquisition.

## Phase 2 / 3 plan

- **Phase 2:** QEMU `virt` builds its own device tree at runtime, and `-dtb`
  needs a complete tree, not a `.dtbo` overlay. The plan is to dump virt's DTB
  (`-machine virt,dumpdtb=`), insert a `demo,mychardev` node with a spare GIC
  SPI, and use `irq_set_irqchip_state(..., PENDING, true)` from an ioctl to
  raise the interrupt in software.
- **Phase 3:** module symbols only exist after `insmod`, so GDB needs
  `add-symbol-file chardev.ko <.text address from /sys/module/chardev/sections/.text>`;
  the kernel is already built with `CONFIG_DEBUG_INFO` and booted with no KASLR.
