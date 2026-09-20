#!/bin/sh
# Non-interactive end-to-end check (kernel cmdline contains "autotest").
echo "--- 1. cross-compiled hello world"
hello
echo "--- 2. insmod"
insmod /lib/modules/chardev.ko || { echo "insmod FAILED"; exit 1; }
dmesg | grep mychardev
echo "--- 3. device node"
ls -l /dev/mychardev
grep mychardev /proc/devices
lsmod
echo "--- 4. shell write / read"
echo "hello from userspace" > /dev/mychardev
cat /dev/mychardev
echo "--- 5. C test program (open/read/write/ioctl)"
chardev_test
echo "--- 6. rmmod"
rmmod chardev && echo "rmmod OK"
dmesg | tail -n 3
ls /dev/mychardev 2>&1
