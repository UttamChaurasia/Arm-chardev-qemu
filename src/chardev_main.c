// SPDX-License-Identifier: GPL-2.0
/*
 * chardev_main.c - module init/exit and the character device itself.
 *
 * The device is created either by the platform driver's probe() (when the
 * Device Tree contains a matching node) or, as a fallback, directly from
 * module init so the driver is usable on a kernel with no DT node.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/err.h>

#include "chardev.h"
#include "../include/mychardev_ioctl.h"

static struct mychar_dev *fallback_dev;

/*
 * Used only when no Device Tree node is present; a DT node's
 * demo,buffer-size property takes precedence.
 */
static unsigned int buffer_size = MYCHAR_DEFAULT_SIZE;
module_param(buffer_size, uint, 0444);
MODULE_PARM_DESC(buffer_size, "Buffer size in bytes when no DT node is present (1.."
		 __stringify(MYCHAR_MAX_SIZE) ", default "
		 __stringify(MYCHAR_DEFAULT_SIZE) ")");

/* ------------------------------------------------------------------ */
/* file_operations                                                     */
/* ------------------------------------------------------------------ */

static int mychar_open(struct inode *inode, struct file *filp)
{
	struct mychar_dev *md = container_of(inode->i_cdev, struct mychar_dev, cdev);

	filp->private_data = md;
	pr_info("%s: open (pid %d)\n", MYCHAR_NAME, current->pid);
	return 0;
}

static int mychar_release(struct inode *inode, struct file *filp)
{
	pr_info("%s: release\n", MYCHAR_NAME);
	return 0;
}

static ssize_t mychar_read(struct file *filp, char __user *ubuf,
			   size_t count, loff_t *ppos)
{
	struct mychar_dev *md = filp->private_data;
	ssize_t ret;

	if (mutex_lock_interruptible(&md->lock))
		return -ERESTARTSYS;

	if (*ppos >= md->len) {
		ret = 0;                       /* EOF */
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
 * Semantics: data is written at *ppos and the valid length becomes
 * *ppos + count ("last write wins"). So `echo hi > /dev/mychardev`
 * (fresh open, offset 0) replaces the contents, while repeated write()s
 * on one open descriptor append.
 */
static ssize_t mychar_write(struct file *filp, const char __user *ubuf,
			    size_t count, loff_t *ppos)
{
	struct mychar_dev *md = filp->private_data;
	ssize_t ret;

	if (*ppos >= md->cap)
		return -ENOSPC;
	if (count > md->cap - *ppos)
		count = md->cap - *ppos;      /* short write */

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
		memset(md->buf, 0, md->cap);
		mutex_unlock(&md->lock);
		return 0;

	case MYCHAR_IOC_GET_LEN:
		mutex_lock(&md->lock);
		val = md->len;
		mutex_unlock(&md->lock);
		break;

	case MYCHAR_IOC_GET_CAP:
		val = md->cap;
		break;

	case MYCHAR_IOC_GET_IRQCNT:
		val = atomic_read(&md->irq_count);
		break;

	case MYCHAR_IOC_TRIGGER_IRQ:
		return mychar_irq_trigger(md);

	default:
		return -ENOTTY;
	}
	return put_user(val, (int __user *)arg);
}

/*
 * SEEK_SET/CUR are bounded by the buffer capacity; SEEK_END is relative to the
 * number of valid bytes, not the (zero) inode size, so lseek(fd, -n, SEEK_END)
 * addresses the tail of the stored data.
 */
static loff_t mychar_llseek(struct file *filp, loff_t off, int whence)
{
	struct mychar_dev *md = filp->private_data;
	loff_t eof;

	mutex_lock(&md->lock);
	eof = md->len;
	mutex_unlock(&md->lock);

	return generic_file_llseek_size(filp, off, whence, md->cap, eof);
}

static const struct file_operations mychar_fops = {
	.owner          = THIS_MODULE,
	.open           = mychar_open,
	.release        = mychar_release,
	.read           = mychar_read,
	.write          = mychar_write,
	.unlocked_ioctl = mychar_ioctl,
	.llseek         = mychar_llseek,
};

/* ------------------------------------------------------------------ */
/* create / destroy (used by probe() and by the fallback path)          */
/* ------------------------------------------------------------------ */

struct mychar_dev *mychar_create(size_t cap, struct device *parent)
{
	struct mychar_dev *md;
	int ret;

	if (cap == 0 || cap > MYCHAR_MAX_SIZE)
		return ERR_PTR(-EINVAL);

	md = kzalloc(sizeof(*md), GFP_KERNEL);
	if (!md)
		return ERR_PTR(-ENOMEM);

	md->buf = kmalloc(cap, GFP_KERNEL);
	if (!md->buf) {
		ret = -ENOMEM;
		goto err_md;
	}
	memset(md->buf, 0, cap);
	md->cap = cap;
	mutex_init(&md->lock);
	atomic_set(&md->irq_count, 0);

	ret = alloc_chrdev_region(&md->devt, 0, 1, MYCHAR_NAME);
	if (ret)
		goto err_buf;

	cdev_init(&md->cdev, &mychar_fops);
	md->cdev.owner = THIS_MODULE;
	ret = cdev_add(&md->cdev, md->devt, 1);
	if (ret)
		goto err_region;

	md->class = class_create(MYCHAR_NAME);
	if (IS_ERR(md->class)) {
		ret = PTR_ERR(md->class);
		goto err_cdev;
	}

	md->device = device_create(md->class, parent, md->devt, NULL, MYCHAR_NAME);
	if (IS_ERR(md->device)) {
		ret = PTR_ERR(md->device);
		goto err_class;
	}

	pr_info("%s: registered major=%d minor=%d, %zu-byte buffer\n",
		MYCHAR_NAME, MAJOR(md->devt), MINOR(md->devt), cap);
	return md;

err_class:
	class_destroy(md->class);
err_cdev:
	cdev_del(&md->cdev);
err_region:
	unregister_chrdev_region(md->devt, 1);
err_buf:
	kfree(md->buf);
err_md:
	kfree(md);
	return ERR_PTR(ret);
}

void mychar_destroy(struct mychar_dev *md)
{
	if (!md)
		return;
	device_destroy(md->class, md->devt);
	class_destroy(md->class);
	cdev_del(&md->cdev);
	unregister_chrdev_region(md->devt, 1);
	kfree(md->buf);
	kfree(md);
	pr_info("%s: unregistered\n", MYCHAR_NAME);
}

/* ------------------------------------------------------------------ */
/* module init / exit                                                  */
/* ------------------------------------------------------------------ */

static int __init mychar_init(void)
{
	int ret;

	pr_info("%s: init\n", MYCHAR_NAME);

	ret = mychar_platform_register();   /* probe() runs here if DT matches */
	if (ret)
		return ret;

	if (!mychar_platform_probed()) {
		pr_info("%s: no DT node found, creating %u-byte device without IRQ\n",
			MYCHAR_NAME, buffer_size);
		fallback_dev = mychar_create(buffer_size, NULL);
		if (IS_ERR(fallback_dev)) {
			ret = PTR_ERR(fallback_dev);
			fallback_dev = NULL;
			mychar_platform_unregister();
			return ret;
		}
	}
	return 0;
}

static void __exit mychar_exit(void)
{
	mychar_destroy(fallback_dev);       /* NULL-safe */
	mychar_platform_unregister();       /* remove() destroys the DT device */
	pr_info("%s: exit\n", MYCHAR_NAME);
}

module_init(mychar_init);
module_exit(mychar_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Uttam");
MODULE_DESCRIPTION("Character device driver demo (ARM/QEMU)");
