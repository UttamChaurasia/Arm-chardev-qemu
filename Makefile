# Out-of-tree kbuild Makefile.
#   make KDIR=/path/to/built/kernel
# KDIR must be the exact tree you boot (same source + .config, with
# `make modules_prepare` and `make modules` done) or insmod fails on vermagic.

ARCH          ?= arm
CROSS_COMPILE ?= arm-linux-gnueabi-
KDIR          ?= $(CURDIR)/../work/linux

obj-m := chardev.o
chardev-objs := src/chardev_main.o src/chardev_dt.o src/chardev_irq.o
# The module (chardev) must not share a name with a source file (chardev.c),
# or kbuild sees the object as both a target and its own prerequisite.

all:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KDIR) M=$(CURDIR) clean
