// SPDX-License-Identifier: GPL-2.0
/*
 * chardev_irq.c - interrupt handling.
 *
 * The interrupt line comes from the Device Tree node ("interrupts" =
 * a spare GIC SPI). QEMU has no real peripheral driving it, so the
 * MYCHAR_IOC_TRIGGER_IRQ ioctl marks the interrupt pending in the
 * interrupt controller: the CPU then takes it exactly as it would a
 * hardware-raised one and runs mychar_isr() through the normal
 * request_irq() path.
 */
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/ratelimit.h>

#include "chardev.h"

static irqreturn_t mychar_isr(int irq, void *dev_id)
{
	struct mychar_dev *md = dev_id;
	int n = atomic_inc_return(&md->irq_count);

	pr_info_ratelimited("%s: IRQ %d handled (count=%d)\n",
			    MYCHAR_NAME, irq, n);
	return IRQ_HANDLED;
}

int mychar_irq_setup(struct mychar_dev *md, int irq)
{
	int ret = request_irq(irq, mychar_isr, 0, MYCHAR_NAME, md);

	if (ret) {
		pr_err("%s: request_irq(%d) failed: %d\n", MYCHAR_NAME, irq, ret);
		return ret;
	}
	md->irq = irq;
	return 0;
}

void mychar_irq_teardown(struct mychar_dev *md)
{
	if (md && md->irq) {
		free_irq(md->irq, md);
		md->irq = 0;
	}
}

int mychar_irq_trigger(struct mychar_dev *md)
{
	if (!md->irq)
		return -ENODEV;
	return irq_set_irqchip_state(md->irq, IRQCHIP_STATE_PENDING, true);
}
