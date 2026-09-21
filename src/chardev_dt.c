// SPDX-License-Identifier: GPL-2.0
/*
 * chardev_dt.c - platform_driver that binds to a Device Tree node
 * with compatible = "demo,mychardev".
 *
 * Supported DT properties:
 *   demo,buffer-size  (u32, optional)  kernel buffer size in bytes
 *   interrupts        (optional)       enables the IRQ path
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/err.h>

#include "chardev.h"

static struct mychar_dev *dt_dev;

static int mychar_probe(struct platform_device *pdev)
{
	struct mychar_dev *md;
	u32 size = MYCHAR_DEFAULT_SIZE;
	int irq, ret;

	of_property_read_u32(pdev->dev.of_node, "demo,buffer-size", &size);

	md = mychar_create(size, &pdev->dev);
	if (IS_ERR(md))
		return PTR_ERR(md);

	irq = platform_get_irq_optional(pdev, 0);
	if (irq > 0) {
		ret = mychar_irq_setup(md, irq);
		if (ret) {
			mychar_destroy(md);
			return ret;
		}
	} else {
		dev_info(&pdev->dev, "no interrupt in DT node\n");
	}

	platform_set_drvdata(pdev, md);
	dt_dev = md;
	dev_info(&pdev->dev, "probed via Device Tree (buffer=%u, irq=%d)\n",
		 size, md->irq);
	return 0;
}

static void mychar_remove(struct platform_device *pdev)
{
	struct mychar_dev *md = platform_get_drvdata(pdev);

	dt_dev = NULL;
	mychar_irq_teardown(md);
	mychar_destroy(md);
}

static const struct of_device_id mychar_of_match[] = {
	{ .compatible = "demo,mychardev" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, mychar_of_match);

static struct platform_driver mychar_platform_driver = {
	.probe  = mychar_probe,
	.remove_new = mychar_remove,
	.driver = {
		.name           = "mychardev",
		.of_match_table = mychar_of_match,
	},
};

int mychar_platform_register(void)
{
	return platform_driver_register(&mychar_platform_driver);
}

void mychar_platform_unregister(void)
{
	platform_driver_unregister(&mychar_platform_driver);
}

bool mychar_platform_probed(void)
{
	return dt_dev != NULL;
}
