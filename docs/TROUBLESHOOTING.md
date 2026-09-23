# Troubleshooting

Every entry below is a problem that actually occurred while building or running
this project.

## Setup and environment

| Symptom | Cause | Fix |
|---------|-------|-----|
| `wsl` opens a shell where `apt` does not exist | the default WSL distro is `docker-desktop` | `wsl --set-default Ubuntu`, or `wsl -d Ubuntu` (see `WSL.md`) |
| `'lsb_release' is not recognized` | Linux command typed in Windows cmd | enter Ubuntu first (`wsl -d Ubuntu`) |
| `bad interpreter` running a script | CRLF line endings after unzipping/copying on Windows | `sed -i 's/\r$//' scripts/*.sh rootfs/*`; unzip inside WSL |
| everything is slow / scripts lose their exec bit | working under `/mnt/c/...` | work in the Linux home directory (`~`) |
| `qemu-system-arm: failed to find romfile "efi-virtio.rom"` | QEMU wants a NIC option ROM that is not installed | the scripts pass `-nic none`; do the same if you invoke QEMU directly |
| QEMU seems hung | it is a serial console with no window | **Ctrl-A then X**, or `poweroff -f` in the guest |

## Building

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Module.symvers is missing` / hundreds of `undefined!` in modpost | the kernel tree never had its modules built | `make modules` in the kernel tree (`build-kernel.sh` does this) |
| BusyBox: `bits/libc-header-start.h: No such file` | ARM C library headers not installed | `sudo apt install libc6-dev-armel-cross` |
| `insmod: Invalid module format` | module and kernel built from different trees/configs (vermagic) | keep `prebuilt/zImage` with the modules in the same `prebuilt/`, or rebuild both |
| symbol name collision when building a module (`oops_exit`) | the kernel already declares that symbol | give module functions a unique prefix |
| a source file named `chardev.c` inside module `chardev.ko` | kbuild treats the object as its own prerequisite | keep the module name different from every source file name |
| `make clean` deleted `prebuilt/*.ko` and `*.dtb` | kbuild's clean removes every `*.ko`/`*.dtb` under the directory | rebuild, or restore `prebuilt/` from the release zip |

## Debugging

| Symptom | Cause | Fix |
|---------|-------|-----|
| `break mychar_write` fails or is never hit | the module is not loaded at boot, so a software breakpoint cannot be written | use `hbreak`, and `add-symbol-file` first (`DEBUGGING.md`) |
| `addr2line` prints `??` for a `.ko` address | it does not apply relocations to line tables of an unlinked object | resolve with GDB (`trace-oops.sh` does) |
| oops addresses look off by one | Thumb-2 kernel: function addresses carry the low "Thumb" bit | let GDB do the arithmetic (`list *(sym+0xoff)`) |
| GDB lists no source lines after moving the tree | debug info records the original absolute build path | the scripts map it automatically (`scripts/paths.sh`); by hand use `set substitute-path` |
| `ubuf = ... <error: Cannot access memory>` in GDB | `ubuf` is a user-space address, not readable through the kernel view | expected; that is why the driver uses `copy_from_user` |
| `Backtrace stopped: previous frame identical to this frame (corrupt stack?)` | GDB cannot unwind through the ARM syscall-entry assembly | spurious; the frames above it (`mychar_write`, `vfs_write`, `ksys_write`) are correct |
| locals show `<optimized out>` at function entry | not assigned yet | break on a later line (the GDB script uses source markers) |

## Tests

| Symptom | Cause | Fix |
|---------|-------|-----|
| "kernel error lines" reported although nothing failed | an earlier detector matched the word "oops" in the kernel command line | fixed: it now matches real fault signatures, with a control that must fire after the deliberate oops |
| the IRQ test says SKIP | the node is not in the device tree (booted with `nodt`, or wrong DTB) | boot normally so `-dtb build/virt-mychardev.dtb` (or `prebuilt/`) is used |
