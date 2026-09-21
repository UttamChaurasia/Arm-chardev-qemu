# Debugging guide (Phase 3)

Everything here runs against the emulated ARM board. Real output from each
workflow is saved in `docs/sample-output/`.

## 1. GDB attached to QEMU's gdbstub

One command runs the whole session:

```bash
./scripts/gdb-demo.sh
```

What it does, and how to do it by hand:

**a. Find where the module will load.** Module symbols do not exist until
`insmod`, so GDB cannot know them at boot. Inside the guest:

```sh
insmod /lib/modules/chardev.ko
cat /sys/module/chardev/sections/.text     # 0xbf800000
cat /sys/module/chardev/sections/.data     # 0xbf802000
cat /sys/module/chardev/sections/.bss      # 0xbf802240
```

(`gdb-demo.sh` gets these from a first boot; on this kernel a first module
lands at the same address every run.)

**b. Boot frozen and attach.**

```bash
./scripts/run-qemu.sh debug                # = qemu ... -s -S, waits on tcp::1234
gdb-multiarch -q ../work/linux/vmlinux     # in a second terminal
```

```gdb
(gdb) set architecture arm
(gdb) target remote :1234
(gdb) add-symbol-file chardev.ko 0xbf800000 -s .data 0xbf802000 -s .bss 0xbf802240
(gdb) hbreak mychar_write
(gdb) continue
```

**Why `hbreak`, not `break`:** a software breakpoint works by writing a trap
instruction into the target's memory. The module is not loaded yet, so that
address is not mapped. A hardware breakpoint is set without touching memory.

**Why `add-symbol-file` with an address:** it tells GDB "the file's `.text`
lives at this address in the target", so function names, line numbers and struct
layouts from the module's DWARF apply to live memory.

### What the session shows (`docs/sample-output/gdb-session.log`)

1. **Function entry**: the user-space `write()` is visible in the kernel call
   stack (`mychar_write <- vfs_write <- ksys_write`), with `count=10`
   (`"hello gdb\n"`).
2. **Line 87, before `copy_from_user`**: `md->len = 0`, `*ppos = 0`, `md->cap = 4096`.
3. **After `copy_from_user`**: `md->len = 10` and `x/s md->buf` prints
   `"hello gdb\n"`. The data is sitting in the kernel `kmalloc` buffer.

Notes:
- At function entry locals such as `md` are not yet assigned (GDB says
  "optimized out"); break on a later line to inspect them.
- `ubuf` prints `Cannot access memory`: it is a *user-space* address, which is
  not readable through the kernel's view. Correct behaviour, and the reason
  the driver uses `copy_from_user`.
- Breakpoint line numbers refer to `src/chardev_main.c`; if you edit the file,
  update them in `scripts/mychardev.gdb`.
- The compiler folded line 93 into line 95's instructions, so that stop is
  reported at line 95.
- Debug info embeds the build path. Use
  `set substitute-path <build path> <your path>` if you move the tree (the
  scripts do this for you).

## 2. Deliberate kernel oops

`src/oops_demo.c` writes to a NULL pointer inside a separate module, so the
main driver stays clean.

```bash
./scripts/run-qemu.sh autotest oopsdemo 2>&1 | tr -d '\r' > oops.log
./scripts/trace-oops.sh oops.log
```

Or interactively: `insmod /lib/modules/oops_demo.ko`. `insmod` is killed
(`Segmentation fault`, exit status 139); the kernel keeps running.

### Reading the oops (`docs/sample-output/selftest-and-oops.log`)

```
Unhandled fault: page domain fault (0x81b) at 0x00000000     <- what and where: address 0
PC is at oopsdemo_write_null+0x14/0xffe [oops_demo]          <- faulting instruction
LR is at oopsdemo_write_null+0xf/0xffe [oops_demo]           <- return address
r2 : 0000dead   r3 : 00000000                                <- value and (null) pointer
 oopsdemo_write_null [oops_demo] from oopsdemo_init+0x7 ...  <- call trace,
 oopsdemo_init [oops_demo] from do_one_initcall+0x37 ...        innermost first
 do_init_module from sys_init_module ...                        (ends at the insmod syscall)
Code: dbce 2300 f64d 62ad (601a) bd08                        <- bytes at PC, faulting one in ( )
```

`trace-oops.sh` extracts `PC is at <symbol>+<offset>` and asks GDB to resolve it
against `oops_demo.ko`:

```
0x14 is in oopsdemo_write_null (src/oops_demo.c:15).
15    *p = 0xdead;                     /* <-- the faulting line */
```

### Cross-check (do not trust one tool)

`arm-linux-gnueabi-objdump -d -M force-thumb oops_demo.ko` shows offset `0x14`
is `601a  str r2, [r3, #0]`, with `r3` zeroed by `movs r3, #0` and `r2 = 0xdead`.
That matches the register dump and the `Code:` bytes in the oops. Three
independent sources agree.

### Gotchas met while building this

- **This kernel is Thumb-2.** ARM function addresses carry a low "Thumb" bit
  (`lr = bf800011` for a function at `...10`). Plain `addr2line` on an unlinked
  `.ko` also returned `??` because it does not apply relocations to line tables;
  GDB does, so the script uses GDB.
- **The `/0xffe` "size"** in `PC is at ...` is not reliable for module symbols
  here; use the `+offset`.
- **Symbol names must not collide with kernel ones.** My first version called
  the module exit function `oops_exit`, which the kernel already declares.
