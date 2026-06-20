# Out-of-tree build of the patched Apple SMC driver.
# Adds /sys/class/power_supply/BAT0/charge_control_end_threshold backed by the
# SMC "BCLM" key, so the battery charge ceiling can be set from sysfs.
#
# Canonical dual-mode kbuild Makefile: when invoked standalone (KERNELRELEASE
# unset) it recurses into the kernel build tree; kbuild then re-reads this file
# with KERNELRELEASE set and uses the obj-m line.
ifeq ($(KERNELRELEASE),)

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

else

obj-m += applesmc.o

endif
