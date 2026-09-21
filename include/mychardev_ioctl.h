/* SPDX-License-Identifier: GPL-2.0 */
/*
 * mychardev_ioctl.h - ioctl ABI shared between the kernel module and
 * user space. Keep this file free of kernel-only includes.
 */
#ifndef MYCHARDEV_IOCTL_H
#define MYCHARDEV_IOCTL_H

#include <linux/ioctl.h>

#define MYCHAR_IOC_MAGIC 'M'

/* Empty the buffer (length becomes 0). */
#define MYCHAR_IOC_RESET        _IO(MYCHAR_IOC_MAGIC, 0)
/* Read the number of valid bytes currently stored. */
#define MYCHAR_IOC_GET_LEN      _IOR(MYCHAR_IOC_MAGIC, 1, int)
/* Read the total buffer capacity in bytes. */
#define MYCHAR_IOC_GET_CAP      _IOR(MYCHAR_IOC_MAGIC, 2, int)
/* Read how many interrupts the handler has serviced. */
#define MYCHAR_IOC_GET_IRQCNT   _IOR(MYCHAR_IOC_MAGIC, 3, int)
/* Raise the device interrupt from software (marks it pending in the GIC). */
#define MYCHAR_IOC_TRIGGER_IRQ  _IO(MYCHAR_IOC_MAGIC, 4)

#define MYCHAR_IOC_MAXNR 4

#endif /* MYCHARDEV_IOCTL_H */
