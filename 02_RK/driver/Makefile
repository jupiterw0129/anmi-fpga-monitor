ENABLE_DBG_TESTCASE?=0
ENABLE_RANDOM_TEST?=0
ENABLE_DESC_BYPASS?=1

TARGET_MODULE:=anlogic_pci

$(TARGET_MODULE)-objs := anlogic_pci_lib.o anlogic_pci_cdev.o cdev_ctrl.o cdev_events.o cdev_sgdma.o \
						anlogic_pci_drv.o anlogic_thread.o anlogic_ring.o \


ccflags-y += -DAL_BD_RING -DHARDWARE_PATCH=0 -Wno-unused -Wno-missing-prototypes -Wno-missing-declarations

ifneq ($(ENABLE_DBG_TESTCASE),0)
ccflags-y += -DDBG_TESTCASE=1
$(TARGET_MODULE)-objs += anlogic_dbg.o anlogic_pci_dbg.o anlogic_pci_test.o sgdma_case_st.o
else
ccflags-y += -DDBG_TESTCASE=0
endif

ifneq ($(ENABLE_RANDOM_TEST),0)
ccflags-y += -DRANDOM_TEST=1
$(TARGET_MODULE)-objs += anlogic_4chmm_test.o
else
ccflags-y += -DRANDOM_TEST=0
endif

ifneq ($(ENABLE_DESC_BYPASS),0)
ccflags-y += -DDESC_BYPASS=1
$(TARGET_MODULE)-objs += anlogic_desc_bypass.o
else
ccflags-y += -DDESC_BYPASS=0
endif

ifneq ($(KERNELRELEASE),)
obj-m := $(TARGET_MODULE).o
else
PWD := $(shell pwd)
KVER := $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
endif

