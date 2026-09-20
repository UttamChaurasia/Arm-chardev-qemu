// SPDX-License-Identifier: GPL-2.0
/*
 * chardev_main.c - Phase 1: a minimal character device.
 *
 *   module_init -> alloc_chrdev_region -> cdev_add -> class_create
 *               -> device_create   (udev/devtmpfs then creates /dev/mychardev)
 *
 * The 4 KiB kernel buffer is kmalloc'd; all data crosses the user/kernel
 * boundary with copy_to_user / copy_from_user, never by direct pointer use.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "../include/mychardev_ioctl.h"

#define DEV_NAME  "mychardev"
#define BUF_SIZE  4096

struct mychar_dev {
	struct cdev cdev;
	dev_t devt;
	struct class *class;
	struct mutex lock;      /* protects buf and len */
	char *buf;
	size_t len;             /* valid bytes in buf */
};

static struct mychar_dev mydev;

/* ---------------- file_operations ---------------- */

static int mychar_open(struct inode *inode, struct file *filp)
{
	filp->private_data = container_of(inode->i_cdev, struct mychar_dev, cdev);
	pr_info("%s: open (pid %d)\n", DEV_NAME, current->pid);
	return 0;
}

static int mychar_release(struct inode *inode, struct file *filp)
{
	pr_info("%s: release\n", DEV_NAME);
	return 0;
}

static ssize_t mychar_read(struct file *filp, char __user *ubuf,
			   size_t count, loff_t *ppos)
{
	struct mychar_dev *md = filp->private_data;
	ssize_t ret;

	if (mutex_lock_interruptible(&md->lock))
		return -ERESTARTSYS;

	if (*ppos >= md->len) {                 /* EOF */
		ret = 0;
		goto out;
	}
	if (count > md->len - *ppos)
		count = md->len - *ppos;

	if (copy_to_user(ubuf, md->buf + *ppos, count)) {
		ret = -EFAULT;
		goto out;
	}
	*ppos += count;
	ret = count;
out:
	mutex_unlock(&md->lock);
	return ret;
}

/*
 * Data lands at *ppos and the valid length becomes *ppos + count
 * ("last write wins"): `echo hi > /dev/mychardev` replaces the contents,
 * repeated write()s on one descriptor append.
 */
static ssize_t mychar_write(struct file *filp, const char __user *ubuf,
			    size_t count, loff_t *ppos)
{
	struct mychar_dev *md = filp->private_data;
	ssize_t ret;

	if (*ppos >= BUF_SIZE)
		return -ENOSPC;
	if (count > BUF_SIZE - *ppos)
		count = BUF_SIZE - *ppos;       /* short write */

	if (mutex_lock_interruptible(&md->lock))
		return -ERESTARTSYS;

	if (copy_from_user(md->buf + *ppos, ubuf, count)) {
		ret = -EFAULT;
		goto out;
	}
	*ppos += count;
	md->len = *ppos;
	ret = count;
out:
	mutex_unlock(&md->lock);
	return ret;
}

static long mychar_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	struct mychar_dev *md = filp->private_data;
	int val;

	if (_IOC_TYPE(cmd) != MYCHAR_IOC_MAGIC || _IOC_NR(cmd) > MYCHAR_IOC_MAXNR)
		return -ENOTTY;

	switch (cmd) {
	case MYCHAR_IOC_RESET:
		mutex_lock(&md->lock);
		md->len = 0;
		memset(md->buf, 0, BUF_SIZE);
		mutex_unlock(&md->lock);
		return 0;
	case MYCHAR_IOC_GET_LEN:
		mutex_lock(&md->lock);
		val = md->len;
		mutex_unlock(&md->lock);
		break;
	case MYCHAR_IOC_GET_CAP:
		val = BUF_SIZE;
		break;
	default:
		return -ENOTTY;
	}
	return put_user(val, (int __user *)arg);
}

static const struct file_operations mychar_fops = {
	.owner          = THIS_MODULE,
	.open           = mychar_open,
	.release        = mychar_release,
	.read           = mychar_read,
	.write          = mychar_write,
	.unlocked_ioctl = mychar_ioctl,
	.llseek         = default_llseek,
};

/* ---------------- module init / exit ---------------- */

static int __init mychar_init(void)
{
	struct device *dev;
	int ret;

	pr_info("%s: init\n", DEV_NAME);

	mydev.buf = kzalloc(BUF_SIZE, GFP_KERNEL);
	if (!mydev.buf)
		return -ENOMEM;
	mutex_init(&mydev.lock);

	ret = alloc_chrdev_region(&mydev.devt, 0, 1, DEV_NAME);
	if (ret)
		goto err_buf;

	cdev_init(&mydev.cdev, &mychar_fops);
	mydev.cdev.owner = THIS_MODULE;
	ret = cdev_add(&mydev.cdev, mydev.devt, 1);
	if (ret)
		goto err_region;

	mydev.class = class_create(DEV_NAME);
	if (IS_ERR(mydev.class)) {
		ret = PTR_ERR(mydev.class);
		goto err_cdev;
	}

	dev = device_create(mydev.class, NULL, mydev.devt, NULL, DEV_NAME);
	if (IS_ERR(dev)) {
		ret = PTR_ERR(dev);
		goto err_class;
	}

	pr_info("%s: registered major=%d minor=%d\n", DEV_NAME,
		MAJOR(mydev.devt), MINOR(mydev.devt));
	return 0;

err_class:
	class_destroy(mydev.class);
err_cdev:
	cdev_del(&mydev.cdev);
err_region:
	unregister_chrdev_region(mydev.devt, 1);
err_buf:
	kfree(mydev.buf);
	return ret;
}

static void __exit mychar_exit(void)
{
	device_destroy(mydev.class, mydev.devt);
	class_destroy(mydev.class);
	cdev_del(&mydev.cdev);
	unregister_chrdev_region(mydev.devt, 1);
	kfree(mydev.buf);
	pr_info("%s: exit\n", DEV_NAME);
}

module_init(mychar_init);
module_exit(mychar_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Uttam");
MODULE_DESCRIPTION("Character device driver demo, phase 1 (ARM/QEMU)");
