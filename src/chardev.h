/* SPDX-License-Identifier: GPL-2.0 */
#ifndef CHARDEV_H
#define CHARDEV_H

#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/mutex.h>
#include <linux/atomic.h>
#include <linux/platform_device.h>

#define MYCHAR_NAME         "mychardev"
#define MYCHAR_DEFAULT_SIZE 4096
#define MYCHAR_MAX_SIZE     (64 * 1024)

struct mychar_dev {
	struct cdev cdev;
	dev_t devt;
	struct class *class;
	struct device *device;

	struct mutex lock;      /* protects buf and len */
	char *buf;              /* kmalloc'd kernel-space buffer */
	size_t cap;
	size_t len;

	int irq;                /* 0 when no interrupt is wired up */
	atomic_t irq_count;
};

/* chardev_main.c */
struct mychar_dev *mychar_create(size_t cap, struct device *parent);
void mychar_destroy(struct mychar_dev *md);

/* chardev_irq.c */
int mychar_irq_setup(struct mychar_dev *md, int irq);
void mychar_irq_teardown(struct mychar_dev *md);
int mychar_irq_trigger(struct mychar_dev *md);

/* chardev_dt.c */
int mychar_platform_register(void);
void mychar_platform_unregister(void);
bool mychar_platform_probed(void);

#endif /* CHARDEV_H */
