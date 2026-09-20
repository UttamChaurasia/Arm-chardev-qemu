/* SPDX-License-Identifier: GPL-2.0 */
/* ioctl ABI shared by the kernel module and user space (Phase 1). */
#ifndef MYCHARDEV_IOCTL_H
#define MYCHARDEV_IOCTL_H

#include <linux/ioctl.h>

#define MYCHAR_IOC_MAGIC 'M'

/* Empty the buffer (length becomes 0). */
#define MYCHAR_IOC_RESET    _IO(MYCHAR_IOC_MAGIC, 0)
/* Read the number of valid bytes currently stored. */
#define MYCHAR_IOC_GET_LEN  _IOR(MYCHAR_IOC_MAGIC, 1, int)
/* Read the total buffer capacity in bytes. */
#define MYCHAR_IOC_GET_CAP  _IOR(MYCHAR_IOC_MAGIC, 2, int)

#define MYCHAR_IOC_MAXNR 2

#endif
