# GDB script for the mychardev driver under QEMU's gdbstub.
# Usage (QEMU already running with `run-qemu.sh debug`):
#   gdb-multiarch -q -x scripts/mychardev.gdb
# or let scripts/gdb-demo.sh generate the addresses and drive everything.
#
# Module symbols only exist after insmod, so the load addresses come from
# /sys/module/chardev/sections/{.text,.data,.bss} inside the guest. On this
# kernel a first module always lands at the same address, so the defaults work.

set pagination off
set confirm off
set architecture arm
# debug info holds absolute build paths; remap if you moved the tree:
# set substitute-path /home/claude/kernel-chardev-driver-final /your/path

file vmlinux
target remote :1234

# Not loaded yet -- tell GDB where it *will* be, using the .ko's own debug info.
add-symbol-file chardev.ko 0xbf800000 -s .data 0xbf802000 -s .bss 0xbf802240

# Hardware breakpoint: the module's memory doesn't exist yet, and a software
# breakpoint would have to write into it.
hbreak mychar_write
continue

# ---- 1. stopped at function entry: arguments are valid, locals are not yet ----
echo \n=== 1. entry of mychar_write (called from user-space write()) ===\n
bt
info args
print/d count

# ---- 2. line 87: about to copy from user space; md/len are live ----
# (line numbers refer to src/chardev_main.c; adjust if you edit the file)
hbreak chardev_main.c:87
continue
echo \n=== 2. before copy_from_user ===\n
print md->len
print *ppos
print md->cap

# ---- 3. line 93: data copied, length updated ----
hbreak chardev_main.c:93
continue
echo \n=== 3. after copy_from_user: kernel buffer now holds the user data ===\n
print md->len
x/s md->buf
print ret

delete
detach
quit
