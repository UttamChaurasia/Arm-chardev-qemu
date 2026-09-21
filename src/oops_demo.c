// SPDX-License-Identifier: GPL-2.0
/*
 * oops_demo.c - deliberately faults so you can practise reading an oops.
 * insmod oops_demo.ko  -> NULL pointer dereference in oopsdemo_init().
 * See docs/DEBUGGING.md for tracing the backtrace to this source line.
 */
#include <linux/module.h>
#include <linux/kernel.h>

static noinline void oopsdemo_write_null(void)
{
	volatile int *p = NULL;

	pr_info("oops_demo: about to dereference NULL\n");
	*p = 0xdead;                     /* <-- the faulting line */
}

static int __init oopsdemo_init(void)
{
	oopsdemo_write_null();
	return 0;
}

static void __exit oopsdemo_exit(void) { }

module_init(oopsdemo_init);
module_exit(oopsdemo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Deliberate NULL-deref oops demo");
