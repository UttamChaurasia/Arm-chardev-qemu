#!/bin/sh
# Non-interactive end-to-end check (kernel cmdline contains "autotest").
echo "--- 1. Device Tree node visible to the kernel"
cat /proc/device-tree/mychardev/compatible 2>/dev/null && echo || echo "(no mychardev node in DT)"
echo "--- 2. insmod"
insmod /lib/modules/chardev.ko || { echo "insmod FAILED"; exit 1; }
dmesg | grep -E "mychardev"
echo "--- 3. platform driver bound to the DT device"
ls /sys/bus/platform/drivers/mychardev/ 2>&1
echo "--- 4. device node"
ls -l /dev/mychardev
echo "--- 5. shell write / read"
echo "hello from userspace" > /dev/mychardev
cat /dev/mychardev
echo "--- 6. C test program (fops, ioctl, IRQ)"
chardev_test
echo "--- 7. interrupt statistics"
grep -E "CPU|mychardev" /proc/interrupts
echo "--- 8. rmmod"
rmmod chardev && echo "rmmod OK"
grep mychardev /proc/interrupts || echo "(IRQ released)"
ls /dev/mychardev 2>&1
echo "--- 9. load/unload stress (20 cycles, IRQ fired each time)"
echo 1 > /proc/sys/kernel/printk   # keep the console quiet during the loop
i=0
while [ $i -lt 20 ]; do
    insmod /lib/modules/chardev.ko || { echo "cycle $i: insmod FAILED"; exit 1; }
    chardev_test >/dev/null 2>&1 || { echo "cycle $i: test FAILED"; exit 1; }
    rmmod chardev || { echo "cycle $i: rmmod FAILED"; exit 1; }
    i=$((i+1))
done
echo "stress OK ($i cycles)"
echo 7 > /proc/sys/kernel/printk
echo "kernel fault signatures in dmesg: $(dmesg | grep -cE 'Internal error|Unhandled fault|BUG:|WARNING:|kmemleak')"
if grep -q oopsdemo /proc/cmdline; then
    echo "--- 10. deliberate kernel oops (oops_demo.ko)"
    insmod /lib/modules/oops_demo.ko
    echo "insmod exit status: $? (killed by the fault)"
    echo "kernel fault signatures in dmesg: $(dmesg | grep -cE 'Internal error|Unhandled fault|BUG:|WARNING:|kmemleak') (control: must be > 0 now)"
fi
