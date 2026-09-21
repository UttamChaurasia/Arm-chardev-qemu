#!/bin/sh
# Guest side of scripts/gdb-demo.sh. Kernel cmdline selects the mode:
#   gdbaddr : load the module and print its section addresses
#   gdbrun  : same, then write to the device (hits the GDB breakpoint)
insmod /lib/modules/chardev.ko || exit 1
S=/sys/module/chardev/sections
echo "MODTEXT=$(cat $S/.text) MODDATA=$(cat $S/.data) MODBSS=$(cat $S/.bss)"
if grep -q gdbrun /proc/cmdline; then
    echo "GUEST: writing to /dev/mychardev"
    echo "hello gdb" > /dev/mychardev
    echo "GUEST: write returned"
    cat /dev/mychardev
fi
rmmod chardev
