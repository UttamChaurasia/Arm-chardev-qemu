# Architecture

How the pieces fit together, and why. File and function names refer to `src/`.

## The stack, from a user's `write()` down to the buffer

```
  user space        echo hello > /dev/mychardev        chardev_test
                              |  write(fd, ...)
  ------------------------------------------------------------------ syscall
  kernel VFS        vfs_write -> file->f_op->write
                              |
  char device       cdev (dynamic major, minor 0)  --> mychar_fops
                              |                     open / release / read / write /
                              |                     llseek / unlocked_ioctl
  driver            struct mychar_dev  (chardev.h)
                      buf (kmalloc, cap bytes)    <-- copy_to_user / copy_from_user
                      len, mutex (protects buf+len)
                      atomic64 counters (stats)   --> /sys/class/mychardev/mychardev/stats
                      irq, atomic irq_count
```

## Where the device comes from: two creation paths

```
   QEMU 'virt' DTB  +  our node (dts/mychardev-node.dtsi)
              |
              v   kernel populates a platform_device from the node
   chardev_dt.c: platform_driver, of_match "demo,mychardev"
              |   probe(): read demo,buffer-size, platform_get_irq_optional()
              v
   mychar_create()  ---->  cdev + class + /dev node + sysfs attribute
              |
              +--> mychar_irq_setup()  request_irq()

   No matching DT node?  mychar_init() falls back to mychar_create(buffer_size)
   with no interrupt, so the driver still works (tested with run-qemu.sh nodt).
```

`mychar_init()` registers the platform driver first (probe runs inside that call
if a node exists), then checks `mychar_platform_probed()` to decide about the fallback.
`mychar_exit()` mirrors it: destroy the fallback device (NULL-safe), then unregister
the platform driver, whose `remove()` destroys the DT-created device.

## The interrupt path

QEMU has no peripheral that raises this interrupt, so it is raised in software:

```
 ioctl(MYCHAR_IOC_TRIGGER_IRQ)
   -> mychar_irq_trigger()
        irq_set_irqchip_state(irq, IRQCHIP_STATE_PENDING, true)   marks it pending in the GIC
   -> CPU takes the interrupt  -> generic IRQ layer -> mychar_isr()
        atomic_inc_return(&irq_count); rate-limited log; IRQ_HANDLED
```

Everything after "pending" is the real path: `request_irq`, GIC dispatch, handler,
`free_irq` on teardown. Only the *source* of the assertion is substituted. The GIC
interrupt is SPI 60 (`interrupts = <0 60 1>`), which appears as hardware IRQ 92 in
`/proc/interrupts` (32 + 60).

## Locking and context rules

| Data | Protection | Why |
|------|------------|-----|
| `buf`, `len` | `md->lock` (mutex) | read/write/ioctl/llseek/stats run in process context and may sleep in `copy_*_user` |
| `irq_count`, stats counters | atomics | the interrupt handler must not sleep, so it cannot take the mutex |

`copy_to_user` / `copy_from_user` are never called with a spinlock held. On the
read and write paths the mutex is taken with `mutex_lock_interruptible()` so a
blocked process can still be signalled.

## Semantics chosen (and their limits)

- **Write** lands at the file offset and the valid length becomes `offset + count`
  ("last write wins"). `echo x > /dev/mychardev` therefore replaces the contents;
  successive `write()`s on one descriptor append. Past capacity: short write, then `-ENOSPC`.
- **llseek** uses the capacity as the bound and the stored length as EOF, so
  `SEEK_END` addresses the tail of the data.
- **One device instance.** There is a single buffer shared by all openers; there is
  no per-open state and no blocking `read()`/`poll()` support.
- **Kernel config is single-CPU and non-preemptible** (`CONFIG_SMP=n`), so the
  mutex is exercised for correctness of the code paths, but real multi-core
  contention has *not* been tested.

## Error handling

`mychar_create()` unwinds with `goto` in reverse order of acquisition
(sysfs file, device, class, cdev, region, buffer, struct). The load/unload stress
loop (20 cycles) is what checks that teardown really releases everything.

## Build and boot chain

```
 scripts/build-kernel.sh   Linux 6.6 (allnoconfig + kernel/mychardev.config)  -> zImage, vmlinux
 scripts/make-dtb.sh       QEMU-dumped virt DTB + our node                     -> virt-mychardev.dtb
 scripts/build.sh          kbuild out-of-tree                                  -> chardev.ko, oops_demo.ko
 scripts/build-rootfs.sh   static BusyBox + modules + tests, gen_init_cpio     -> rootfs.cpio.gz
 scripts/run-qemu.sh       qemu-system-arm -M virt -cpu cortex-a15 ...
```

The kernel is a **Thumb-2** build; that matters when reading addresses in an oops
(see `DEBUGGING.md`).
