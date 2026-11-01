/*
 * This file is part of the anlogic PCIe driver for Linux
 *
 * Copyright (c) 2020-present,  anlogic, Inc.
 * All rights reserved.
 *
 * This source code is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * The full GNU General Public License is included in this distribution in
 * the file called "COPYING".
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/mm.h>
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/vmalloc.h>
#include <linux/random.h>
#include <asm/cacheflush.h>

#include "cdev_sgdma.h"

#include "anlogic_pci_lib.h"
#include "anlogic_pci_dbg.h"
#include "anlogic_thread.h"
#include "anlogic_ring.h"
#if DESC_BYPASS
#include "anlogic_desc_bypass.h"
#endif

/* Module Parameters */
unsigned int poll_mode = 0;
module_param(poll_mode, uint, 0644);
MODULE_PARM_DESC(poll_mode, "Set 1 for hw polling, default is 0 (interrupts)");

unsigned int enable_st_c2h_credit = 0;
module_param(enable_st_c2h_credit, uint, 0644);
MODULE_PARM_DESC(enable_st_c2h_credit,
	"Set 1 to enable ST C2H engine credit feature, default is 0 ( credit control disabled)");

unsigned int force_st_c2h_wb = 0;
module_param(force_st_c2h_wb, uint, 0644);
MODULE_PARM_DESC(force_st_c2h_wb,
	"Set 1 to force STM mode writeback on AXI-ST C2H engines, default is 0");

unsigned int enable_st_h2c_credit = 0;
module_param(enable_st_h2c_credit, uint, 0644);
MODULE_PARM_DESC(enable_st_h2c_credit,
	"Set 1 to enable ST H2C engine credit feature, default is 0 ( credit control disabled)");

unsigned int desc_blen_max = SGDMA_DESC_BLEN_MAX;
module_param(desc_blen_max, uint, 0644);
MODULE_PARM_DESC(desc_blen_max, "per descriptor max. buffer length, default is (1 << 28) - 1");

/*
 * RTO - code to detect if MSI/MSI-X capability exists is derived
 * from linux/pci/msi.c - pci_msi_check_device
 */
static unsigned int interrupt_mode = 1;
module_param(interrupt_mode, uint, 0644);
MODULE_PARM_DESC(interrupt_mode, "0 - MSI-x , 1 - MSI, 2 - Legacy");

unsigned int h2c_timeout = 10;
module_param(h2c_timeout, uint, 0644);
MODULE_PARM_DESC(h2c_timeout, "H2C sgdma timeout in seconds, default is 10 sec.");

unsigned int c2h_timeout = 10;
module_param(c2h_timeout, uint, 0644);
MODULE_PARM_DESC(c2h_timeout, "C2H sgdma timeout in seconds, default is 10 sec.");

#define SGDMA_PERF_NUM_DESC 128

/*
 * sgdma device management
 * maintains a list of the sgdma devices
 */
static LIST_HEAD(sgdev_list);
static DEFINE_MUTEX(sgdev_mutex);
static LIST_HEAD(sgdev_rcu_list);
static DEFINE_SPINLOCK(sgdev_rcu_lock);

static irqreturn_t anlogic_channel_irq(int irq, void *dev_id);
static irqreturn_t anlogic_user_irq(int irq, void *dev_id);
static irqreturn_t anlogic_isr(int irq, void *dev_id);
#if RANDOM_TEST
static int engine_service_rtest(struct anlogic_dma_engine *engine, int desc_writeback);
#endif

#ifndef list_last_entry
#define list_last_entry(ptr, type, member) list_entry((ptr)->prev, type, member)
#endif

static inline int al_dev_list_add(struct anlogic_dev *sgdev)
{
	mutex_lock(&sgdev_mutex);
	if (list_empty(&sgdev_list)) {
		sgdev->idx = 0;
		if (poll_mode) {
			int rv = sgdma_threads_create(sgdev->h2c_channel_max +
					sgdev->c2h_channel_max);
			if (rv < 0) {
				mutex_unlock(&sgdev_mutex);
				return rv;
			}
		}
	} else {
		struct anlogic_dev *last;

		last = list_last_entry(&sgdev_list, struct anlogic_dev, list_head);
		sgdev->idx = last->idx + 1;
	}
	list_add_tail(&sgdev->list_head, &sgdev_list);
	mutex_unlock(&sgdev_mutex);

	dbg_init("dev %s, sgdev 0x%p, sgdma idx %d.\n",
		 dev_name(&sgdev->pdev->dev), sgdev, sgdev->idx);

	spin_lock(&sgdev_rcu_lock);
	list_add_tail_rcu(&sgdev->rcu_node, &sgdev_rcu_list);
	spin_unlock(&sgdev_rcu_lock);

	return 0;
}

#undef list_last_entry

static inline void al_dev_list_remove(struct anlogic_dev *sgdev)
{
	mutex_lock(&sgdev_mutex);
	list_del(&sgdev->list_head);
	if (poll_mode && list_empty(&sgdev_list))
		sgdma_threads_destroy();
	mutex_unlock(&sgdev_mutex);

	spin_lock(&sgdev_rcu_lock);
	list_del_rcu(&sgdev->rcu_node);
	spin_unlock(&sgdev_rcu_lock);
	synchronize_rcu();
}

struct anlogic_dev *sgdev_find_by_pdev(struct pci_dev *pdev)
{
	struct anlogic_dev *sgdev, *tmp;

	mutex_lock(&sgdev_mutex);
	list_for_each_entry_safe(sgdev, tmp, &sgdev_list, list_head) {
		if (sgdev->pdev == pdev) {
			mutex_unlock(&sgdev_mutex);
			return sgdev;
		}
	}
	mutex_unlock(&sgdev_mutex);
	return NULL;
}

static inline int debug_check_dev_hndl(const char *fname, struct pci_dev *pdev,
				       void *hndl)
{
	struct anlogic_dev *sgdev;

	if (!pdev)
		return -EINVAL;

	sgdev = sgdev_find_by_pdev(pdev);
	if (!sgdev) {
		pr_info("%s pdev 0x%p, hndl 0x%p, NO match found!\n", fname,
			pdev, hndl);
		return -EINVAL;
	}
	if (sgdev != hndl) {
		pr_err("%s pdev 0x%p, hndl 0x%p != 0x%p!\n", fname, pdev, hndl,
		       sgdev);
		return -EINVAL;
	}

	return 0;
}

/*
 * MSI-X interrupt:
 *  <h2c+c2h channel_max> vectors, followed by <user_max> vectors
 */

#ifndef arch_msi_check_device
static int arch_msi_check_device(struct pci_dev *dev, int nvec, int type)
{
	return 0;
}
#endif

static inline u32 build_u32(u32 hi, u32 lo)
{
	return ((hi & 0xFFFFUL) << 16) | (lo & 0xFFFFUL);
}

static inline u64 build_u64(u64 hi, u64 lo)
{
	return ((hi & 0xFFFFFFFULL) << 32) | (lo & 0xFFFFFFFFULL);
}

static inline bool st_c2h_credit_enabled(const struct anlogic_dma_engine *engine)
{
	return engine && enable_st_c2h_credit && engine->streaming &&
		engine->dir == DMA_FROM_DEVICE;
}

static inline bool st_c2h_force_wb_enabled(const struct anlogic_dma_engine *engine)
{
	return engine && force_st_c2h_wb && engine->streaming &&
		engine->dir == DMA_FROM_DEVICE;
}

static inline u32 engine_stm_mode_wb_mask(const struct anlogic_dma_engine *engine)
{
	if (!engine)
		return 0;

	if (!engine->streaming)
		return (u32)SGDMA_CTRL_STM_MODE_WB;

	if (st_c2h_force_wb_enabled(engine))
		return (u32)SGDMA_CTRL_STM_MODE_WB;

	return 0;
}

static inline bool st_c2h_poll_reg_fallback_enabled(const struct anlogic_dma_engine *engine)
{
	return engine && poll_mode && st_c2h_force_wb_enabled(engine);
}

static unsigned long st_c2h_completed_bytes(struct anlogic_dma_engine *engine,
					      struct sgdma_transfer *xfer)
{
	struct sgdma_result *result;
	unsigned long done = 0;
	int i;

	if (!engine || !xfer || !xfer->res_virt)
		return 0;

	result = xfer->res_virt;
	for (i = 0; i < xfer->desc_num; i++)
		done += result[i].length;

	if (!done && st_c2h_poll_reg_fallback_enabled(engine) &&
		!engine->eop_flush && xfer->desc_cmpl == xfer->desc_num) {
		done = xfer->len;
		pr_info("%s: result length fallback uses xfer->len=%u.\n",
			engine->name, xfer->len);
	}

	return done;
}

/* type = PCI_CAP_ID_MSI or PCI_CAP_ID_MSIX */
static int msi_msix_capable(struct pci_dev *dev, int type)
{
	struct pci_bus *bus;
	int ret;

	if (!dev || dev->no_msi)
		return 0;

	for (bus = dev->bus; bus; bus = bus->parent)
		if (bus->bus_flags & PCI_BUS_FLAGS_NO_MSI)
			return 0;

	ret = arch_msi_check_device(dev, 1, type);
	if (ret)
		return 0;

	if (!pci_find_capability(dev, type))
		return 0;

	return 1;
}

static void disable_msi_msix(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	if (sgdev->msix_enabled) {
		pci_disable_msix(pdev);
		sgdev->msix_enabled = 0;
	} else if (sgdev->msi_enabled) {
		pci_disable_msi(pdev);
		sgdev->msi_enabled = 0;
	}
}

static int enable_msi_msix(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	int rv = 0;

	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	if (!pdev) {
		pr_err("Invalid pdev\n");
		return -EINVAL;
	}

	if (!interrupt_mode && msi_msix_capable(pdev, PCI_CAP_ID_MSIX)) {

		int req_nvec = sgdev->c2h_channel_max + sgdev->h2c_channel_max +
					   sgdev->user_max;

#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
		dbg_init("Enabling MSI-X\n");
		rv = pci_alloc_irq_vectors(pdev, req_nvec, req_nvec,
					   PCI_IRQ_MSIX);
		dbg_init("PCI alloc irq: %d vector\n ",rv);
#else
		int i;

		dbg_init("Enabling MSI-X\n");
		for (i = 0; i < req_nvec; i++)
			sgdev->entry[i].entry = i;   //linux max support 32 msix vector

		rv = pci_enable_msix(pdev, sgdev->entry, req_nvec);
#endif
		if (rv < 0)
			dbg_init("Couldn't enable MSI-X mode: %d\n", rv);

		sgdev->msix_enabled = 1;

	} else if (interrupt_mode == 1 &&
		   msi_msix_capable(pdev, PCI_CAP_ID_MSI)) {
		/* enable message signalled interrupts */
		dbg_init("pci_enable_msi()\n");
		rv = pci_enable_msi(pdev);
		if (rv < 0)
			dbg_init("Couldn't enable MSI mode: %d\n", rv);
		sgdev->msi_enabled = 1;

	} else {
		dbg_init("MSI/MSI-X not detected - using legacy interrupts\n");
	}

	return rv;
}

static void pci_check_intr_pend(struct pci_dev *pdev)
{
	u16 v;

	pci_read_config_word(pdev, PCI_STATUS, &v);
	if (v & PCI_STATUS_INTERRUPT) {
		pr_info("%s PCI STATUS Interrupt pending 0x%x.\n",
			dev_name(&pdev->dev), v);
		pci_write_config_word(pdev, PCI_STATUS, PCI_STATUS_INTERRUPT);
	}
}

static void pci_keep_intx_enabled(struct pci_dev *pdev)
{
	/* workaround to a h/w bug:
	 * when msix/msi become unavaile, default to legacy.
	 * However the legacy enable was not checked.
	 * If the legacy was disabled, no ack then everything stuck
	 */
	u16 pcmd, pcmd_new;

	pci_read_config_word(pdev, PCI_COMMAND, &pcmd);
	pcmd_new = pcmd & ~PCI_COMMAND_INTX_DISABLE;
	if (pcmd_new != pcmd) {
		pr_info("%s: clear INTX_DISABLE, 0x%x -> 0x%x.\n",
			dev_name(&pdev->dev), pcmd, pcmd_new);
		pci_write_config_word(pdev, PCI_COMMAND, pcmd_new);
	}
}

void user_interrupts_enable(struct anlogic_dev *sgdev, u32 mask)
{
	struct interrupt_regs *reg =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	write_register(mask, &reg->user_int_enable_w1s, SGDMA_OFS_INT_CTRL);
}

void user_interrupts_disable(struct anlogic_dev *sgdev, u32 mask)
{
	struct interrupt_regs *reg =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	write_register(mask, &reg->user_int_enable_w1c, SGDMA_OFS_INT_CTRL);
}

/* channel_interrupts_enable -- Enable interrupts we are interested in */
void channel_interrupts_enable(struct anlogic_dev *sgdev, u32 mask)
{
	struct interrupt_regs *reg =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	write_register(mask, &reg->channel_int_enable_w1s, SGDMA_OFS_INT_CTRL);
}

/* channel_interrupts_disable -- Disable interrupts we not interested in */
void channel_interrupts_disable(struct anlogic_dev *sgdev, u32 mask)
{
	struct interrupt_regs *reg =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	write_register(mask, &reg->channel_int_enable_w1c, SGDMA_OFS_INT_CTRL);
}

/* read_interrupts -- Print the interrupt controller status */
static u32 read_interrupts(struct anlogic_dev *sgdev)
{
	struct interrupt_regs *reg =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	u32 lo;
	u32 hi;

	/* extra debugging; inspect complete engine set of registers */
	hi = read_register(&reg->user_int_request);
	dbg_io("ioread32(0x%p) returned 0x%08x (user_int_request).\n",
		   &reg->user_int_request, hi);
	lo = read_register(&reg->channel_int_request);
	dbg_io("ioread32(0x%p) returned 0x%08x (channel_int_request)\n",
		   &reg->channel_int_request, lo);

	/* return interrupts: user in upper 16-bits, channel in lower 16-bits */
	return build_u32(hi, lo);
}

static void prog_irq_msix_user(struct anlogic_dev *sgdev, bool clear)
{
	/* user */
	struct interrupt_regs *int_regs =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	u32 i = sgdev->c2h_channel_max + sgdev->h2c_channel_max;
	u32 max = i + sgdev->user_max;
	int j;

	for (j = 0; i < max; j++) {
		u32 val = 0;
		int k;
		int shift = 0;

		if (clear)
			i += 4;
		else
			for (k = 0; k < 4 && i < max; i++, k++, shift += 8)
				val |= (i & 0x1f) << shift;

		write_register(
			val, &int_regs->user_msi_vector[j],
			SGDMA_OFS_INT_CTRL +
				((unsigned long)&int_regs->user_msi_vector[j] -
				 (unsigned long)int_regs));

		dbg_init("vector %d, 0x%x.\n", j, val);
	}
}

static void prog_irq_msix_channel(struct anlogic_dev *sgdev, bool clear)
{
	struct interrupt_regs *int_regs =
		(struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					  SGDMA_OFS_INT_CTRL);
	u32 max = sgdev->c2h_channel_max + sgdev->h2c_channel_max;
	u32 i;
	int j;

	/* engine */
	for (i = 0, j = 0; i < max; j++) {
		u32 val = 0;
		int k;
		int shift = 0;

		if (clear)
			i += 4;
		else
			for (k = 0; k < 4 && i < max; i++, k++, shift += 8)
				val |= (i & 0x1f) << shift;

		write_register(val, &int_regs->channel_msi_vector[j],
				   SGDMA_OFS_INT_CTRL +
					   ((unsigned long)&int_regs
						->channel_msi_vector[j] -
					(unsigned long)int_regs));
		dbg_init("vector %d, 0x%x.\n", j, val);
	}
}

static void irq_msix_channel_teardown(struct anlogic_dev *sgdev)
{
	struct anlogic_dma_engine *engine;
	int j = 0;
	int i = 0;
  pr_info("sgdev->msix_enabled: %d\n", sgdev->msix_enabled);
	if (!sgdev->msix_enabled)
		return;

	//prog_irq_msix_channel(sgdev, 1);
	 pr_info("sgdev->h2c_channel_max: %d\n", sgdev->h2c_channel_max);
	 pr_info("sgdev->c2h_channel_max: %d\n", sgdev->c2h_channel_max);

	engine = sgdev->engine_h2c;
	for (i = 0; i < sgdev->h2c_channel_max; i++, j++, engine++) {
		 pr_info("engine->msix_irq_line: %d\n", engine->msix_irq_line);
		if (!engine->msix_irq_line)
			break;
		dbg_sg("Release IRQ#%d for engine %p\n", engine->msix_irq_line,
			   engine);
		free_irq(engine->msix_irq_line, engine);
	}

	engine = sgdev->engine_c2h;
	for (i = 0; i < sgdev->c2h_channel_max; i++, j++, engine++) {
		pr_info("engine->msix_irq_line: %d\n", engine->msix_irq_line);
		if (!engine->msix_irq_line)
			break;
		dbg_sg("Release IRQ#%d for engine %p\n", engine->msix_irq_line,
			   engine);
		free_irq(engine->msix_irq_line, engine);
	}
}

static int irq_msix_channel_setup(struct anlogic_dev *sgdev)
{
	int i;
	int j;
	int rv = 0;
	u32 vector;

	struct anlogic_dma_engine *engine;

	if (!sgdev) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (!sgdev->msix_enabled)
		return 0;

	j = sgdev->h2c_channel_max;
	engine = sgdev->engine_h2c;
	 pr_info(" sgdev->h2c_channel_max %d .h2c : %d,\n",
				 sgdev->h2c_channel_max, sgdev->c2h_channel_max);
	for (i = 0; i < sgdev->h2c_channel_max; i++, engine++) {
#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
		vector = pci_irq_vector(sgdev->pdev, i);
#else
		vector = sgdev->entry[i].vector;
#endif
		pr_info(" vector%d  is: %d\n", i, vector);
		rv = request_irq(vector, anlogic_channel_irq, 0, sgdev->mod_name,
				 engine);

		if (rv) {
			pr_info("requesti irq#%d failed %d, engine %s.\n",
				vector, rv, engine->name);
			return rv;
		}

		if (rv) {
			pr_info("requesti irq#%d failed %d,\n",
				vector, rv);
			return rv;
		}
		pr_info(" irq#%d.\n",vector);

		engine->msix_irq_line = vector;
		 pr_info("engine->msix_irq_line:%d.\n",engine->msix_irq_line);
	}

	engine = sgdev->engine_c2h;
	for (i = 0; i < sgdev->c2h_channel_max; i++, j++, engine++) {
#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
		vector = pci_irq_vector(sgdev->pdev, j);
#else
		vector = sgdev->entry[j].vector;
#endif
		rv = request_irq(vector, anlogic_channel_irq, 0, sgdev->mod_name,
				 engine);
		if (rv) {
			pr_info("requesti irq#%d failed %d, engine %s.\n",
				vector, rv, engine->name);
			return rv;
		}
		pr_info("engine %s, irq#%d.\n", engine->name, vector);
		engine->msix_irq_line = vector;
		pr_info("engine->msix_irq_line:%d.\n",engine->msix_irq_line);

	}

	return 0;
}

static void irq_msix_user_teardown(struct anlogic_dev *sgdev)
{
	int i;
	int j;

	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return;
	}

	if (!sgdev->msix_enabled)
		return;

	j = sgdev->h2c_channel_max + sgdev->c2h_channel_max;

	prog_irq_msix_user(sgdev, 1);

	for (i = 0; i < sgdev->user_max; i++, j++) {
#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
		u32 vector = pci_irq_vector(sgdev->pdev, j);
#else
		u32 vector = sgdev->entry[j].vector;
#endif
		dbg_init("user %d, releasing IRQ#%d\n", i, vector);
		free_irq(vector, &sgdev->user_irq[i]);
	}

}

static int irq_msi_setup(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	int rv;

	sgdev->irq_line = (int)pdev->irq;
	rv = request_irq(pdev->irq, anlogic_isr, 0, sgdev->mod_name, sgdev);//IRQF_TRIGGER_RISING
	if (rv)
		dbg_init("Couldn't use IRQ#%d, %d\n", pdev->irq, rv);
	else
		dbg_init("Using IRQ#%d with 0x%p\n", pdev->irq, sgdev);

	return rv;
}

static int irq_msix_user_setup(struct anlogic_dev *sgdev)
{
	int i;
	int j = sgdev->h2c_channel_max + sgdev->c2h_channel_max;
	int rv = 0;

	/* vectors set in probe_scan_for_msi() */
	for (i = 0; i < sgdev->user_max; i++, j++) {
#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
		u32 vector = pci_irq_vector(sgdev->pdev, j);
#else
		u32 vector = sgdev->entry[j].vector;
#endif
		rv = request_irq(vector, anlogic_user_irq, 0, sgdev->mod_name,
				 &sgdev->user_irq[i]);
		if (rv) {
			pr_info("user %d couldn't use IRQ#%d, %d\n", i, vector,
				rv);
			break;
		}
		pr_info("%d-USR-%d, IRQ#%d with 0x%p\n", sgdev->idx, i, vector,
			&sgdev->user_irq[i]);
	}

	/* If any errors occur, free IRQs that were successfully requested */
	if (rv) {
		for (i--, j--; i >= 0; i--, j--) {
#if KERNEL_VERSION(4, 12, 0) <= LINUX_VERSION_CODE
			u32 vector = pci_irq_vector(sgdev->pdev, j);
#else
			u32 vector = sgdev->entry[j].vector;
#endif
			free_irq(vector, &sgdev->user_irq[i]);
		}
	}

	return rv;
}

static int irq_legacy_setup(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	u32 w;
	u8 val;
	void *reg;
	int rv;

	pci_read_config_byte(pdev, PCI_INTERRUPT_PIN, &val);
	if (val == 0) {
		dbg_init("Legacy interrupt not supported\n");
		return -EINVAL;
	}

	dbg_init("Legacy Interrupt register value = %d\n", val);

	sgdev->irq_line = (int)pdev->irq;
	rv = request_irq(pdev->irq, anlogic_isr, IRQF_SHARED, sgdev->mod_name,
			 sgdev);
	if (rv)
		dbg_init("Couldn't use IRQ#%d, %d\n", pdev->irq, rv);
	else
		dbg_init("Using IRQ#%d with 0x%p\n", pdev->irq, sgdev);

	return rv;
}

static void irq_teardown(struct anlogic_dev *sgdev)
{
	if (sgdev->msix_enabled) {
		irq_msix_channel_teardown(sgdev);
		irq_msix_user_teardown(sgdev);
	} else if (sgdev->irq_line != -1) {
		dbg_init("Releasing IRQ#%d\n", sgdev->irq_line);
		free_irq(sgdev->irq_line, sgdev);
	}
}

static int irq_setup(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	pci_keep_intx_enabled(pdev);

	if (sgdev->msix_enabled) {
		int rv = irq_msix_channel_setup(sgdev);
		if (rv)
			return rv;

		rv = irq_msix_user_setup(sgdev);
		if (rv)
			return rv;

		prog_irq_msix_channel(sgdev, 0);
		prog_irq_msix_user(sgdev, 0);

		return 0;
	} else if (sgdev->msi_enabled)
		return irq_msi_setup(sgdev, pdev);

	return irq_legacy_setup(sgdev, pdev);
}

static irqreturn_t user_irq_service(int irq, struct anlogic_user_irq *user_irq)
{
	unsigned long flags;

	if (!user_irq) {
		pr_err("Invalid user_irq\n");
		return IRQ_NONE;
	}

	pr_info("=================User Irq %d===============\n", user_irq->user_idx);

	if (user_irq->handler)
		return user_irq->handler(user_irq->user_idx, user_irq->dev);

	spin_lock_irqsave(&(user_irq->events_lock), flags);
	if (!user_irq->events_irq) {
		user_irq->events_irq = 1;
		wake_up_interruptible(&(user_irq->events_wq));
	}
	spin_unlock_irqrestore(&(user_irq->events_lock), flags);

	return IRQ_HANDLED;
}

/*
 * anlogic_user_irq() - Interrupt handler for user interrupts in MSI-X mode
 *
 * @dev_id pointer to sgdma_dev
 */
static irqreturn_t anlogic_user_irq(int irq, void *dev_id)
{
	struct anlogic_user_irq *user_irq;

	dbg_irq("(irq=%d) <<<< INTERRUPT SERVICE ROUTINE\n", irq);

	if (!dev_id) {
		pr_err("Invalid dev_id on irq line %d\n", irq);
		return IRQ_NONE;
	}
	user_irq = (struct anlogic_user_irq *)dev_id;

	return user_irq_service(irq, user_irq);
}

/*
 * anlogic_channel_irq() - Interrupt handler for channel interrupts in MSI-X mode
 *
 * @dev_id pointer to sgdma_dev
 */
static irqreturn_t anlogic_channel_irq(int irq, void *dev_id)
{
	struct anlogic_dev *sgdev;
	struct anlogic_dma_engine *engine;
	struct interrupt_regs *irq_regs;

	dbg_irq("(irq=%d) <<<< INTERRUPT service ROUTINE\n", irq);

	engine = (struct anlogic_dma_engine *)dev_id;
	sgdev = engine->sgdev;

	if (!sgdev) {
		WARN_ON(!sgdev);
		dbg_irq("%s(irq=%d) sgdev=%p ??\n", __func__, irq, sgdev);
		return IRQ_NONE;
	}

	irq_regs = (struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
						 SGDMA_OFS_INT_CTRL);

	/* Disable the interrupt for this engine */
	write_register(
		engine->interrupt_enable_mask_value,
		&engine->regs->interrupt_enable_mask_w1c,
		(unsigned long)(&engine->regs->interrupt_enable_mask_w1c) -
			(unsigned long)(&engine->regs));
	/* Dummy read to flush the above write */
	read_register(&irq_regs->channel_int_pending);
	/* Schedule the bottom half */
	schedule_work(&engine->work);

	sgdev->irq_count++;
	return IRQ_HANDLED;
}

void enable_perf(struct anlogic_dma_engine *engine)
{
	u32 w;

	w = SGDMA_PERF_CLEAR;
	write_register(w, &engine->regs->perf_ctrl,
			   (unsigned long)(&engine->regs->perf_ctrl) -
				   (unsigned long)(&engine->regs));
	read_register(&engine->regs->identifier);
	w = SGDMA_PERF_AUTO | SGDMA_PERF_RUN;
	write_register(w, &engine->regs->perf_ctrl,
			   (unsigned long)(&engine->regs->perf_ctrl) -
				   (unsigned long)(&engine->regs));

	dbg_perf("IOCTL_SGDMA_PERF_START\n");
}
EXPORT_SYMBOL_GPL(enable_perf);

void get_perf_stats(struct anlogic_dma_engine *engine)
{
	u32 hi;
	u32 lo;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return;
	}

	if (!engine->sgdma_perf) {
		pr_info("%s perf struct not set up.\n", engine->name);
		return;
	}

	hi = 0;
	lo = read_register(&engine->regs->completed_desc_count);
	engine->sgdma_perf->iterations = build_u64(hi, lo);

	hi = read_register(&engine->regs->perf_cyc_hi);
	lo = read_register(&engine->regs->perf_cyc_lo);

	engine->sgdma_perf->clock_cycle_count = build_u64(hi, lo);

	hi = read_register(&engine->regs->perf_dat_hi);
	lo = read_register(&engine->regs->perf_dat_lo);
	engine->sgdma_perf->data_cycle_count = build_u64(hi, lo);

	hi = read_register(&engine->regs->perf_pnd_hi);
	lo = read_register(&engine->regs->perf_pnd_lo);
	engine->sgdma_perf->pending_count = build_u64(hi, lo);
}
EXPORT_SYMBOL_GPL(get_perf_stats);

int engine_reg_dump(struct anlogic_dma_engine *engine)
{
	u32 w;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	w = read_register(&engine->regs->identifier);
	pr_info("%s: ioread32(0x%p) = 0x%08x (id).\n", engine->name,
		&engine->regs->identifier, w);
	w &= BLOCK_ID_MASK;
	if (w != BLOCK_ID_HEAD) {
		pr_err("%s: engine id missing, 0x%08x exp. & 0x%x = 0x%x\n",
			   engine->name, w, BLOCK_ID_MASK, BLOCK_ID_HEAD);
		return -EINVAL;
	}
	/* extra debugging; inspect complete engine set of registers */
	w = read_register(&engine->regs->status);
	pr_info("%s: ioread32(0x%p) = 0x%08x (status).\n", engine->name,
		&engine->regs->status, w);
	w = read_register(&engine->regs->control);
	pr_info("%s: ioread32(0x%p) = 0x%08x (control)\n", engine->name,
		&engine->regs->control, w);
	w = read_register(&engine->sgdma_regs->first_desc_lo);
	pr_info("%s: ioread32(0x%p) = 0x%08x (first_desc_lo)\n", engine->name,
		&engine->sgdma_regs->first_desc_lo, w);
	w = read_register(&engine->sgdma_regs->first_desc_hi);
	pr_info("%s: ioread32(0x%p) = 0x%08x (first_desc_hi)\n", engine->name,
		&engine->sgdma_regs->first_desc_hi, w);
	w = read_register(&engine->sgdma_regs->first_desc_adjacent);
	pr_info("%s: ioread32(0x%p) = 0x%08x (first_desc_adjacent).\n",
		engine->name, &engine->sgdma_regs->first_desc_adjacent, w);
	w = read_register(&engine->regs->completed_desc_count);
	pr_info("%s: ioread32(0x%p) = 0x%08x (completed_desc_count).\n",
		engine->name, &engine->regs->completed_desc_count, w);
	w = read_register(&engine->regs->interrupt_enable_mask);
	pr_info("%s: ioread32(0x%p) = 0x%08x (interrupt_enable_mask)\n",
		engine->name, &engine->regs->interrupt_enable_mask, w);

	return 0;
}

void __engine_status_dump(struct anlogic_dma_engine *engine)
{
	u32 v = engine->status;
	char buffer[256];
	char *buf = buffer;
	int len = 0;

	len = sprintf(buf, "SG engine %s status: 0x%08x: ", engine->name, v);

	if ((v & SGDMA_STAT_BUSY))
		len += sprintf(buf + len, "BUSY,");
	if ((v & SGDMA_STAT_DESC_STOPPED))
		len += sprintf(buf + len, "DESC_STOPPED,");
	if ((v & SGDMA_STAT_DESC_COMPLETED))
		len += sprintf(buf + len, "DESC_COMPL,");

	/* common H2C & C2H */
	if ((v & SGDMA_STAT_COMMON_ERR_MASK)) {
		if ((v & SGDMA_STAT_ALIGN_MISMATCH))
			len += sprintf(buf + len, "ALIGN_MISMATCH ");
		if ((v & SGDMA_STAT_MAGIC_STOPPED))
			len += sprintf(buf + len, "MAGIC_STOPPED ");
		if ((v & SGDMA_STAT_INVALID_LEN))
			len += sprintf(buf + len, "INVLIAD_LEN ");
		if ((v & SGDMA_STAT_IDLE_STOPPED))
			len += sprintf(buf + len, "IDLE_STOPPED ");
		buf[len - 1] = ',';
	}

	if (engine->dir == DMA_TO_DEVICE) {
		/* H2C only */
		if ((v & SGDMA_STAT_H2C_R_ERR_MASK)) {
			len += sprintf(buf + len, "R:");
			if ((v & SGDMA_STAT_H2C_R_UNSUPP_REQ))
				len += sprintf(buf + len, "UNSUPP_REQ ");
			if ((v & SGDMA_STAT_H2C_R_COMPL_ABORT))
				len += sprintf(buf + len, "COMPL_ABORT ");
			if ((v & SGDMA_STAT_H2C_R_PARITY_ERR))
				len += sprintf(buf + len, "PARITY ");
			if ((v & SGDMA_STAT_H2C_R_HEADER_EP))
				len += sprintf(buf + len, "HEADER_EP ");
			if ((v & SGDMA_STAT_H2C_R_UNEXP_COMPL))
				len += sprintf(buf + len, "UNEXP_COMPL ");
			buf[len - 1] = ',';
		}

		if ((v & SGDMA_STAT_H2C_W_ERR_MASK)) {
			len += sprintf(buf + len, "W:");
			if ((v & SGDMA_STAT_H2C_W_DECODE_ERR))
				len += sprintf(buf + len, "DECODE_ERR ");
			if ((v & SGDMA_STAT_H2C_W_SLAVE_ERR))
				len += sprintf(buf + len, "SLAVE_ERR ");
			buf[len - 1] = ',';
		}

	} else {
		/* C2H only */
		if ((v & SGDMA_STAT_C2H_R_ERR_MASK)) {
			len += sprintf(buf + len, "R:");
			if ((v & SGDMA_STAT_C2H_R_DECODE_ERR))
				len += sprintf(buf + len, "DECODE_ERR ");
			if ((v & SGDMA_STAT_C2H_R_SLAVE_ERR))
				len += sprintf(buf + len, "SLAVE_ERR ");
			buf[len - 1] = ',';
		}
	}

	/* common H2C & C2H */
	if ((v & SGDMA_STAT_DESC_ERR_MASK)) {
		len += sprintf(buf + len, "DESC_ERR:");
		if ((v & SGDMA_STAT_DESC_UNSUPP_REQ))
			len += sprintf(buf + len, "UNSUPP_REQ ");
		if ((v & SGDMA_STAT_DESC_COMPL_ABORT))
			len += sprintf(buf + len, "COMPL_ABORT ");
		if ((v & SGDMA_STAT_DESC_PARITY_ERR))
			len += sprintf(buf + len, "PARITY ");
		if ((v & SGDMA_STAT_DESC_HEADER_EP))
			len += sprintf(buf + len, "HEADER_EP ");
		if ((v & SGDMA_STAT_DESC_UNEXP_COMPL))
			len += sprintf(buf + len, "UNEXP_COMPL ");
		buf[len - 1] = ',';
	}

	buf[len - 1] = '\0';
	pr_info("%s\n", buffer);
}

static void engine_status_dump(struct anlogic_dma_engine *engine)
{
	__engine_status_dump(engine);
}

/**
 * engine_status_read() - read status of SG DMA engine (optionally reset)
 *
 * Stores status in engine->status.
 *
 * @return error value on failure, 0 otherwise
 */
int engine_status_read(struct anlogic_dma_engine *engine, bool clear, bool dump)
{
	int rv = 0;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (dump) {
		rv = engine_reg_dump(engine);
		if (rv < 0) {
			pr_err("Failed to dump register\n");
			return rv;
		}
	}

	/* read status register */
	if (clear)
		engine->status = read_register(&engine->regs->status_rc);
	else
		engine->status = read_register(&engine->regs->status);

	if (dump)
		engine_status_dump(engine);

	return rv;
}

int engine_start_mode_config(struct anlogic_dma_engine *engine)
{
	u32 w;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	/* If a perf test is running, enable the engine interrupts */
	if (engine->sgdma_perf) {
		w = SGDMA_CTRL_IE_DESC_STOPPED;
		w |= SGDMA_CTRL_IE_DESC_COMPLETED;
		w |= SGDMA_CTRL_IE_DESC_ALIGN_MISMATCH;
		w |= SGDMA_CTRL_IE_MAGIC_STOPPED;
		w |= SGDMA_CTRL_IE_IDLE_STOPPED;
		w |= SGDMA_CTRL_IE_READ_ERROR;
		w |= SGDMA_CTRL_IE_DESC_ERROR;

		write_register(
			w, &engine->regs->interrupt_enable_mask,
			(unsigned long)(&engine->regs->interrupt_enable_mask) -
				(unsigned long)(engine->regs));
	}

#if DESC_BYPASS
	if (engine->is_desc_bypass) {
		struct sgdma_transfer *transfer;
		transfer = list_entry(engine->transfer_list.next, struct sgdma_transfer, entry);
		sgdma_desc_bypass_init(engine, transfer);
	}
#endif

	/* write control register of SG DMA engine */
	w = (u32)SGDMA_CTRL_RUN_STOP;
	w |= (u32)SGDMA_CTRL_IE_READ_ERROR;
	w |= (u32)SGDMA_CTRL_IE_DESC_ERROR;
	w |= (u32)SGDMA_CTRL_IE_DESC_ALIGN_MISMATCH;
	w |= (u32)SGDMA_CTRL_IE_MAGIC_STOPPED;
	w |= engine_stm_mode_wb_mask(engine);

	if (poll_mode) {
		w |= (u32)SGDMA_CTRL_POLL_MODE_WB;
#if HARDWARE_PATCH
		w |= (u32)SGDMA_CTRL_IE_DESC_COMPLETED;
#endif
	} else {
		w |= (u32)SGDMA_CTRL_IE_DESC_STOPPED;
		w |= (u32)SGDMA_CTRL_IE_DESC_COMPLETED;
	}

	/* set non-incremental addressing mode */
	if (engine->non_incr_addr)
		w |= (u32)SGDMA_CTRL_NON_INCR_ADDR;

	dbg_tfr("iowrite32(0x%08x to 0x%p) (control)\n", w,
		(void *)&engine->regs->control);

	/* start the engine */
	write_register(w, &engine->regs->control,
			   (unsigned long)(&engine->regs->control) -
				   (unsigned long)(engine->regs));

	/* dummy read of status register to flush all previous writes */
	w = read_register(&engine->regs->status);
	dbg_tfr("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n",
		&engine->regs->status, w);

#if DESC_BYPASS
	if (engine->is_desc_bypass)
		sgdma_desc_bypass_start(engine);
#endif

	return 0;
}

/* transfer_desc_init() - Chains the descriptors as a singly-linked list
 *
 * Each descriptor's next * pointer specifies the bus address
 * of the next descriptor.
 * Terminates the last descriptor to form a singly-linked list
 *
 * @transfer Pointer to SG DMA transfers
 * @count Number of descriptors allocated in continuous PCI bus addressable
 * memory
 *
 * @return 0 on success, EINVAL on failure
 */
static int transfer_desc_init(struct sgdma_transfer *transfer, int count)
{
	struct sgdma_desc *desc_virt = transfer->desc_virt;
	dma_addr_t desc_bus = transfer->desc_bus;
	int i;

	/* create singly-linked list for SG DMA controller */
	for (i = 0; i < count - 1; i++) {
		/* increment bus address to next in array */
		desc_bus += sizeof(struct sgdma_desc);

		/* singly-linked list uses bus addresses */
		desc_virt[i].next_lo = cpu_to_le32(PCI_DMA_L(desc_bus));
		desc_virt[i].next_hi = cpu_to_le32(PCI_DMA_H(desc_bus));
		desc_virt[i].bytes = cpu_to_le32(0);

		desc_virt[i].control = cpu_to_le32(DESC_MAGIC);
	}
	/* { i = number - 1 } */
	/* zero the last descriptor next pointer */
	desc_virt[i].next_lo = cpu_to_le32(0);
	desc_virt[i].next_hi = cpu_to_le32(0);
	desc_virt[i].bytes = cpu_to_le32(0);
	desc_virt[i].control = cpu_to_le32(DESC_MAGIC);

	return 0;
}

/* sgdma_desc_done - recycle cache-coherent linked list of descriptors.
 *
 * @dev Pointer to pci_dev
 * @number Number of descriptors to be allocated
 * @desc_virt Pointer to (i.e. virtual address of) first descriptor in list
 * @desc_bus Bus address of first descriptor in list
 */
static inline void sgdma_desc_done(struct sgdma_desc *desc_virt, int count)
{
	memset(desc_virt, 0, count * sizeof(struct sgdma_desc));
}

/* sgdma_desc() - Fill a descriptor with the transfer details
 *
 * @desc pointer to descriptor to be filled
 * @addr root complex address
 * @ep_addr end point address
 * @len number of bytes, must be a (non-negative) multiple of 4.
 * @dir, dma direction
 * is the end point address. If zero, vice versa.
 *
 * Does not modify the next pointer
 */
void sgdma_desc_set(struct sgdma_desc *desc, dma_addr_t rc_bus_addr,
			  u64 ep_addr, int len, int dir)
{
	/* transfer length */
	desc->bytes = cpu_to_le32(len);
	if (dir == DMA_TO_DEVICE) {
		/* read from root complex memory (source address) */
		desc->src_addr_lo = cpu_to_le32(PCI_DMA_L(rc_bus_addr));
		desc->src_addr_hi = cpu_to_le32(PCI_DMA_H(rc_bus_addr));
		/* write to end point address (destination address) */
		desc->dst_addr_lo = cpu_to_le32(PCI_DMA_L(ep_addr));
		desc->dst_addr_hi = cpu_to_le32(PCI_DMA_H(ep_addr));
	} else {
		/* read from end point address (source address) */
		desc->src_addr_lo = cpu_to_le32(PCI_DMA_L(ep_addr));
		desc->src_addr_hi = cpu_to_le32(PCI_DMA_H(ep_addr));
		/* write to root complex memory (destination address) */
		desc->dst_addr_lo = cpu_to_le32(PCI_DMA_L(rc_bus_addr));
		desc->dst_addr_hi = cpu_to_le32(PCI_DMA_H(rc_bus_addr));
	}
}

/* sgdma_desc_link() - Link two descriptors
 *
 * Link the first descriptor to a second descriptor, or terminate the first.
 *
 * @first first descriptor
 * @second second descriptor, or NULL if first descriptor must be set as last.
 * @second_bus bus address of second descriptor
 */
void sgdma_desc_link(struct sgdma_desc *first, struct sgdma_desc *second,
			   dma_addr_t second_bus)
{
	/*
	 * remember reserved control in first descriptor, but zero
	 * extra_adjacent!
	 */
	u32 control = le32_to_cpu(first->control) & 0x00FFC0ffUL;
	/* second descriptor given? */
	if (second) {
		/*
		 * link last descriptor of 1st array to first descriptor of
		 * 2nd array
		 */
		first->next_lo = cpu_to_le32(PCI_DMA_L(second_bus));
		first->next_hi = cpu_to_le32(PCI_DMA_H(second_bus));
		WARN_ON(first->next_hi);
		/* no second descriptor given */
	} else {
		/* first descriptor is the last */
		first->next_lo = 0;
		first->next_hi = 0;
	}
	/* merge magic, extra_adjacent and control field */
	control |= DESC_MAGIC;

	/* write bytes and next_num */
	first->control = cpu_to_le32(control);
}

/* sgdma_desc_adjacent -- Set how many descriptors are adjacent to this one */
void sgdma_desc_adjacent(struct sgdma_desc *desc, u32 next_adjacent)
{
	/* remember reserved and control bits */
	u32 control = le32_to_cpu(desc->control) & 0xfffff0ffUL;
	/* merge adjacent and control field */
	control |= (next_adjacent << 8);
	/* write control and next_adjacent */
	desc->control = cpu_to_le32(control);
}

/* sgdma_desc_control -- Set complete control field of a descriptor. */
int sgdma_desc_control_set(struct sgdma_desc *first, u32 control_field)
{
	/* remember magic and adjacent number */
	u32 control = le32_to_cpu(first->control) & ~(LS_BYTE_MASK);

	if (control_field & ~(LS_BYTE_MASK)) {
		pr_err("Invalid control field\n");
		return -EINVAL;
	}
	/* merge adjacent and control field */
	control |= control_field;
	/* write control and next_adjacent */
	first->control = cpu_to_le32(control);
	return 0;
}

/* sgdma_desc_clear -- Clear bits in control field of a descriptor. */
void sgdma_desc_control_clear(struct sgdma_desc *first, u32 clear_mask)
{
	/* remember magic and adjacent number */
	u32 control = le32_to_cpu(first->control);

	BUG_ON(clear_mask & ~(LS_BYTE_MASK));

	/* merge adjacent and control field */
	control &= (~clear_mask);
	/* write control and next_adjacent */
	first->control = cpu_to_le32(control);
}

/**
 * sgdma_get_next_adj()
 *
 * Get the number for adjacent descriptors to set in a descriptor, based on the
 * remaining number of descriptors and the lower bits of the address of the
 * next descriptor.
 * Since the number of descriptors in a page (SGDMA_PAGE_SIZE) is 128 and the
 * maximum size of a block of adjacent descriptors is 64 (63 max adjacent
 * descriptors for any descriptor), align the blocks of adjacent descriptors
 * to the block size.
 */
u32 sgdma_get_next_adj(unsigned int remaining, u32 next_lo)
{
	unsigned int next_index;

#ifdef AL_IP_VER0
	if (remaining >= 1)
		remaining -= 1;

	if (remaining > MAX_EXTRA_ADJ)
		remaining = MAX_EXTRA_ADJ;

	return remaining;
#else

	if (remaining <= 1)
		return 0;

	/* shift right 5 times corresponds to a division by
	 * sizeof(sgdma_desc) = 32
	 */
	next_index = ((next_lo & (SGDMA_PAGE_SIZE - 1)) >> 5) %
		SGDMA_MAX_ADJ_BLOCK_SIZE;
	return min(SGDMA_MAX_ADJ_BLOCK_SIZE - next_index - 1, remaining - 1);
#endif
}

/**
 * sgdma_engine_stop() - stop an SG DMA engine
 *
 */
int sgdma_engine_stop(struct anlogic_dma_engine *engine)
{
	u32 w;
	struct anlogic_dev *sgdev = engine->sgdev;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}
	dbg_tfr("%s(engine=%p)\n", __func__, engine);

#if DESC_BYPASS
	if (engine->is_desc_bypass)
		sgdma_desc_bypass_stop(engine);
#endif

	if (st_c2h_credit_enabled(engine))
		write_register(0, &engine->sgdma_regs->credits,
			(unsigned long)(&engine->sgdma_regs->credits) -
				(unsigned long)(engine->sgdma_regs));

	w = 0;
	w |= (u32)SGDMA_CTRL_IE_DESC_ALIGN_MISMATCH;
	w |= (u32)SGDMA_CTRL_IE_MAGIC_STOPPED;
	w |= (u32)SGDMA_CTRL_IE_READ_ERROR;
	w |= (u32)SGDMA_CTRL_IE_DESC_ERROR;
	w |= engine_stm_mode_wb_mask(engine);

	if (poll_mode) {
		w |= (u32)SGDMA_CTRL_POLL_MODE_WB;
#if HARDWARE_PATCH
		w |= (u32)SGDMA_CTRL_IE_DESC_COMPLETED;
#endif
	} else {
		w |= (u32)SGDMA_CTRL_IE_DESC_STOPPED;
		w |= (u32)SGDMA_CTRL_IE_DESC_COMPLETED;
	}

	dbg_tfr("Stopping SG DMA %s engine; writing 0x%08x to 0x%p.\n",
		engine->name, w, (u32 *)&engine->regs->control);
	write_register(w, &engine->regs->control,
			(unsigned long)(&engine->regs->control) -
				(unsigned long)(engine->regs));
	/* dummy read of status register to flush all previous writes */
	dbg_tfr("%s(%s) done\n", __func__, engine->name);
	engine->running = 0;
	return 0;
}

struct sgdma_request_cb * sgdma_request_alloc(unsigned int sdesc_nr)
{
	struct sgdma_request_cb *req;
	unsigned int size = sizeof(struct sgdma_request_cb) +
				sdesc_nr * sizeof(struct sw_desc);

	req = kzalloc(size, GFP_KERNEL);
	if (!req) {
		req = vmalloc(size);
		if (req)
			memset(req, 0, size);
	}
	if (!req) {
		pr_info("OOM, %u sw_desc, %u.\n", sdesc_nr, size);
		return NULL;
	}

	return req;
}

void sgdma_request_free(struct sgdma_request_cb *req)
{
	if (((unsigned long)req) >= VMALLOC_START &&
		((unsigned long)req) < VMALLOC_END)
		vfree(req);
	else
		kfree(req);
}

void dump_desc(struct sgdma_desc *desc_virt)
{
	int j;
	u32 *p = (u32 *)desc_virt;
	static char *const field_name[] = { "magic|extra_adjacent|control",
						"bytes",
						"src_addr_lo",
						"src_addr_hi",
						"dst_addr_lo",
						"dst_addr_hi",
						"next_addr",
						"next_addr_pad" };
	char *dummy;
	char control_field[64];

	/* remove warning about unused variable when debug printing is off */
	dummy = field_name[0];

	sprintf(control_field, "magic(0x%04x)|extra_adjacent(%d)|control(%s|%s|%s)",
		desc_virt->control >> 16,
		(desc_virt->control & 0x3F00) >> 8,
		((desc_virt->control & 0x10) != 0) ? "EOP" : "   ",
		((desc_virt->control & 0x2) != 0) ? "COMP" : "    ",
		((desc_virt->control & 0x1) != 0) ? "STOP" : "    ");

	for (j = 0; j < 8; j += 1) {
		pr_info("0x%08lx/0x%02lx: 0x%08x 0x%08x %s\n", (uintptr_t)p,
			(uintptr_t)p & 15, (int)*p, le32_to_cpu(*p),
			(j != 0) ? field_name[j] : control_field);
		p++;
	}
	pr_info("\n");
}

void transfer_dump(struct sgdma_transfer *transfer)
{
	int i;
	struct sgdma_desc *desc_virt = transfer->desc_virt;

	if (desc_virt == NULL)
		pr_info("desc virt is null\n");

	pr_info("xfer 0x%p, state 0x%x, f 0x%x, dir %d, len %u, last %d, desc_cmpl_th %d.\n",
		transfer, transfer->state, transfer->flags, transfer->dir,
		transfer->len, transfer->last_in_request, transfer->desc_cmpl_th);

	pr_info("transfer 0x%p, desc %d, bus 0x%llx, adj %d.\n", transfer,
		transfer->desc_num, (u64)transfer->desc_bus,
		transfer->desc_adjacent);

	for (i = 0; i < transfer->desc_num; i += 1)
		dump_desc(desc_virt + i);
}

void sgt_dump(struct sg_table *sgt)
{
	int i;
	struct scatterlist *sg = sgt->sgl;

	return;

	pr_info("sgt 0x%p, sgl 0x%p, nents %u/%u.\n", sgt, sgt->sgl, sgt->nents,
		sgt->orig_nents);

	for (i = 0; i < sgt->orig_nents; i++, sg = sg_next(sg))
		pr_info("%d, 0x%p, pg 0x%p,%u+%u, dma 0x%llx,%u.\n", i, sg,
			sg_page(sg), sg->offset, sg->length, sg_dma_address(sg),
			sg_dma_len(sg));
}

void sgdma_request_cb_dump(struct sgdma_request_cb *req)
{
	int i;

	pr_info("request 0x%p, total %u, ep 0x%llx, sw_desc %u, sgt 0x%p.\n",
		req, req->total_len, req->ep_addr, req->sw_desc_cnt, req->sgt);
	sgt_dump(req->sgt);
	for (i = 0; i < req->sw_desc_cnt; i++)
		pr_info("%d/%u, 0x%llx, %u.\n", i, req->sw_desc_cnt,
			req->sdesc[i].addr, req->sdesc[i].len);
}

struct sgdma_request_cb * sgdma_init_request(struct sg_table *sgt,
					     u64 ep_addr, u32 *controls)
{
	struct sgdma_request_cb *req;
	struct scatterlist *sg = sgt->sgl;
	int max = sgt->nents;
	int extra = 0;
	int i, j = 0;

	for (i = 0;  i < max; i++, sg = sg_next(sg)) {
		unsigned int len = sg_dma_len(sg);

		if (unlikely(len > desc_blen_max))
			extra += (len + desc_blen_max - 1) / desc_blen_max;
	}

	max += extra;

	req = sgdma_request_alloc(max);
	if (!req)
		return NULL;

	req->sgt = sgt;
	req->ep_addr = ep_addr;

	for (i = 0, sg = sgt->sgl;  i < sgt->nents; i++, sg = sg_next(sg)) {
		unsigned int tlen = sg_dma_len(sg);
		dma_addr_t addr = sg_dma_address(sg);
		void *sg_virt = page_address(sg_page(sg));

		req->total_len += tlen;
		while (tlen) {
			req->sdesc[j].addr = addr;
			if (tlen > desc_blen_max) {
				req->sdesc[j].len = desc_blen_max;
				addr += desc_blen_max;
				tlen -= desc_blen_max;
			} else {
				req->sdesc[j].len = tlen;
				tlen = 0;
			}
			j++;
		}
		if (controls)
			req->sdesc[j - 1].control = controls[i];
	}
	BUG_ON(j > max);

	req->sw_desc_cnt = j;

	return req;
}

/**
 * engine_start() - start an idle engine with its first transfer on queue
 *
 * The engine will run and process all transfers that are queued using
 * transfer_queue() and thus have their descriptor lists chained.
 *
 * During the run, new transfers will be processed if transfer_queue() has
 * chained the descriptors before the hardware fetches the last descriptor.
 * A transfer that was chained too late will invoke a new run of the engine
 * initiated from the engine_service() routine.
 *
 * The engine must be idle and at least one transfer must be queued.
 * This function does not take locks; the engine spinlock must already be
 * taken.
 *
 */
struct sgdma_transfer *engine_start(struct anlogic_dma_engine *engine)
{
	struct sgdma_transfer *transfer;
	u32 w, next_adj, extra_adj;
	int rv;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return NULL;
	}

	/* engine must be idle */
	if (engine->running) {
		pr_info("%s engine is not in idle state to start\n",
			engine->name);
		return NULL;
	}

	/* engine transfer queue must not be empty */
	if (list_empty(&engine->transfer_list)) {
		pr_debug("%s engine transfer queue must not be empty\n",
			 engine->name);
		return NULL;
	}
	/* inspect first transfer queued on the engine */
	transfer = list_entry(engine->transfer_list.next, struct sgdma_transfer,
				  entry);
	if (!transfer) {
		pr_debug("%s queued transfer must not be empty\n",
			 engine->name);
		return NULL;
	}

	/* engine is no longer shutdown */
	engine->shutdown = ENGINE_SHUTDOWN_NONE;

	dbg_tfr("%s(%s): transfer=0x%p.\n", __func__, engine->name, transfer);
	if (engine->streaming && engine->dir == DMA_FROM_DEVICE)
		dbg_tfr("%s(%s): st_c2h credit=%u force_wb=%u desc_used=%u desc_max=%u.\n",
			__func__, engine->name, enable_st_c2h_credit,
			force_st_c2h_wb, engine->desc_used, engine->desc_max);

	/* ring mode do not need init credit again */
	if (engine->cyclic_req == NULL) {
		/* Add credits for Streaming mode C2H */
		if (st_c2h_credit_enabled(engine))
			write_register(engine->desc_used,
						&engine->sgdma_regs->credits,
				   (unsigned long)(&engine->sgdma_regs->credits) -
					   (unsigned long)(engine->sgdma_regs));
	}

	/* initialize number of descriptors of dequeued transfers */
	engine->desc_dequeued = 0;

	/* write lower 32-bit of bus address of transfer first descriptor */
	w = cpu_to_le32(PCI_DMA_L(transfer->desc_bus));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_lo)\n", w,
		(void *)&engine->sgdma_regs->first_desc_lo);
	write_register(w, &engine->sgdma_regs->first_desc_lo,
			   (unsigned long)(&engine->sgdma_regs->first_desc_lo) -
				   (unsigned long)(engine->sgdma_regs));
	/* write upper 32-bit of bus address of transfer first descriptor */
	w = cpu_to_le32(PCI_DMA_H(transfer->desc_bus));
	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_hi)\n", w,
		(void *)&engine->sgdma_regs->first_desc_hi);
	write_register(w, &engine->sgdma_regs->first_desc_hi,
			   (unsigned long)(&engine->sgdma_regs->first_desc_hi) -
				   (unsigned long)(engine->sgdma_regs));

	next_adj = sgdma_get_next_adj(transfer->desc_adjacent,
					 cpu_to_le32(PCI_DMA_L(transfer->desc_bus)));

	dbg_tfr("iowrite32(0x%08x to 0x%p) (first_desc_adjacent)\n", next_adj,
		(void *)&engine->sgdma_regs->first_desc_adjacent);

	write_register(
		next_adj, &engine->sgdma_regs->first_desc_adjacent,
		(unsigned long)(&engine->sgdma_regs->first_desc_adjacent) -
			(unsigned long)(engine->sgdma_regs));


	dbg_tfr("ioread32(0x%p) (dummy read flushes writes).\n",
		&engine->regs->status);

#ifdef HAS_MMIOWB
	mmiowb();
#endif

	rv = engine_start_mode_config(engine);
	if (rv < 0) {
		pr_err("Failed to start engine mode config\n");
		return NULL;
	}

	rv = engine_status_read(engine, 0, 0);
	if (rv < 0) {
		pr_err("Failed to read engine status\n");
		return NULL;
	}
	dbg_tfr("%s engine 0x%p now running\n", engine->name, engine);
	/* remember the engine is running */
	engine->running = 1;
	return transfer;
}

/**
 * engine_service() - service an SG DMA engine
 *
 * must be called with engine->lock already acquired
 *
 * @engine pointer to struct sgdma_engine
 *
 */
int engine_service_shutdown(struct anlogic_dma_engine *engine)
{
	int rv;
	/* if the engine stopped with RUN still asserted, de-assert RUN now */

	dbg_tfr("%s engine just went idle, resetting RUN_STOP.\n", engine->name);
	rv = sgdma_engine_stop(engine);
	if (rv < 0) {
		pr_err("Failed to stop engine\n");
		return rv;
	}

	/* awake task on engine's shutdown wait queue */
	al_wake_up(&engine->shutdown_wq);
	return 0;
}

static struct sgdma_transfer *engine_transfer_completion(
		struct anlogic_dma_engine *engine,
		struct sgdma_transfer *transfer)
{
	if (!engine) {
		pr_err("dma engine NULL\n");
		return NULL;
	}

	if (unlikely(!transfer)) {
		pr_info("%s: xfer empty.\n", engine->name);
		return NULL;
	}

	/* synchronous I/O? */
	/* awake task on transfer's wait queue */
	al_wake_up(&transfer->wq);

	/* Send completion notification for Last transfer */
	if (transfer->cb && transfer->last_in_request)
		transfer->cb->io_done((unsigned long)transfer->cb, 0);

	return transfer;
}

static struct sgdma_transfer *
engine_service_transfer_list(struct anlogic_dma_engine *engine,
				 struct sgdma_transfer *transfer,
				 u32 *pdesc_completed)
{
	if (!engine) {
		pr_err("dma engine NULL\n");
		return NULL;
	}

	if (!pdesc_completed) {
		pr_err("%s completed descriptors are null.\n", engine->name);
		return NULL;
	}

	if (unlikely(!transfer)) {
		pr_info("%s xfer empty, pdesc completed %u.\n", engine->name,
			*pdesc_completed);
		return NULL;
	}

	/*
	 * iterate over all the transfers completed by the engine,
	 * except for the last (i.e. use > instead of >=).
	 */
   /* Must make sure transfer->desc_num < *pdesc_completed, this mean the transfer is finished all. */
	while (transfer && (!transfer->cyclic) &&
		   (*pdesc_completed > transfer->desc_num)) {
		/* remove this transfer from pdesc_completed */
		*pdesc_completed -= transfer->desc_num;
		dbg_tfr("%s engine completed non-cyclic xfer 0x%p (%d desc)\n",
			engine->name, transfer, transfer->desc_num);

		/* remove completed transfer from list */
		list_del(engine->transfer_list.next);
		/* add to dequeued number of descriptors during this run */
		engine->desc_dequeued += transfer->desc_num;
		/* mark transfer as succesfully completed */
		transfer->state = TRANSFER_STATE_COMPLETED;

		/*
		 * Complete transfer - sets transfer to NULL if an async
		 * transfer has completed
		 */
		transfer = engine_transfer_completion(engine, transfer);

		/* if exists, get the next transfer on the list */
		if (!list_empty(&engine->transfer_list)) {
			transfer = list_entry(engine->transfer_list.next,
						  struct sgdma_transfer, entry);
			dbg_tfr("Non-completed transfer %p\n", transfer);
		} else {
			/* no further transfers? */
			transfer = NULL;
		}
	}

	return transfer;
}

 static int engine_err_handle(struct anlogic_dma_engine *engine,
				  struct sgdma_transfer *transfer, u32 desc_completed)
 {
	 u32 value;
	 int rv = 0;
	 /*
	  * The BUSY bit is expected to be clear now but older HW has a race
	  * condition which could cause it to be still set.  If it's set, re-read
	  * and check again.  If it's still set, log the issue.
	  */
	 if (engine->status & SGDMA_STAT_BUSY) {
		 value = read_register(&engine->regs->status);
		 if ((value & SGDMA_STAT_BUSY))
			 printk_ratelimited(KERN_INFO
					 "%s has errors but is still BUSY\n",
					 engine->name);
	 }

	 printk_ratelimited(KERN_INFO "%s, s 0x%x, aborted xfer 0x%p, cmpl %d/%d\n",
			 engine->name, engine->status, transfer, desc_completed,
			 transfer->desc_num);

	 /* mark transfer as failed */
	 transfer->state = TRANSFER_STATE_FAILED;
	 rv = sgdma_engine_stop(engine);
	 if (rv < 0)
		 pr_err("Failed to stop engine\n");
	 return rv;
 }

static struct sgdma_transfer *
engine_service_final_transfer(struct anlogic_dma_engine *engine,
				   struct sgdma_transfer *transfer,
				   u32 *pdesc_completed)
 {
	if (!engine) {
		pr_err("dma engine NULL\n");
		return NULL;
	}

	if (!pdesc_completed) {
		pr_err("%s completed descriptors are null.\n", engine->name);
		return NULL;
	}

	/* inspect the current transfer */
	if (unlikely(!transfer)) {
		pr_info("%s xfer empty, pdesc completed %u.\n", engine->name,
			 *pdesc_completed);
		return NULL;
	}

	if (((engine->dir == DMA_FROM_DEVICE) &&
		(engine->status & SGDMA_STAT_C2H_ERR_MASK)) ||
		((engine->dir == DMA_TO_DEVICE) &&
		(engine->status & SGDMA_STAT_H2C_ERR_MASK))) {
		pr_info("engine %s, status error 0x%x.\n", engine->name,
			engine->status);
		engine_status_dump(engine);
		engine_err_handle(engine, transfer, *pdesc_completed);
		goto transfer_del;
	}

	if (engine->status & SGDMA_STAT_BUSY)
		pr_debug("engine %s is unexpectedly busy - ignoring\n",
			 engine->name);

	/* the engine stopped on current transfer? */
	if (*pdesc_completed < transfer->desc_num) {
		/* Here is telled us not all desc finished on current transfer. */
		if (engine->eop_flush) {
			/* check if eop received */
			struct sgdma_result *result = transfer->res_virt;
			int i;
			int max = *pdesc_completed;

			/* Foreach stream result write back addr until find the last desc. */
			for (i = 0; i < max; i++) {
				if ((result[i].status & RX_STATUS_EOP) != 0) {
					transfer->flags |= XFER_FLAG_ST_C2H_EOP_RCVED;
					break;
				}
			}

			transfer->desc_cmpl = *pdesc_completed;
			if (!(transfer->flags & XFER_FLAG_ST_C2H_EOP_RCVED)) {
			 return NULL;
			}

			dbg_tfr("%s, xfer 0x%p, EOP received, %d/%d.\n",
			 engine->name, transfer, *pdesc_completed,
			 transfer->desc_num);

			/* mark transfer as successfully completed */
			engine_service_shutdown(engine);

			transfer->state = TRANSFER_STATE_COMPLETED;

			engine->desc_dequeued += transfer->desc_cmpl;
		} else {
			if (transfer->flags & XFER_FLAG_IGNORE_HALFWAY_IRQ)
				return NULL;

			transfer->state = TRANSFER_STATE_FAILED;
			dbg_tfr("%s, xfer 0x%p, stopped half-way, %d/%d.\n",
			 engine->name, transfer, *pdesc_completed,
			 transfer->desc_num);

			/* add dequeued number of descriptors during this run */
			engine->desc_dequeued += transfer->desc_num;
			transfer->desc_cmpl = *pdesc_completed;
		 }
	} else {
		/* Here is telled us a transfer is finished all desc on it. */
		dbg_tfr("%s, xfer 0x%p, transfer completed, %d/%d.\n",
			 engine->name, transfer, *pdesc_completed,
			 transfer->desc_num);

		if (!transfer->cyclic) {
			/*
			 * if the engine stopped on this transfer,
			 * it should be the last
			 */
			WARN_ON(*pdesc_completed > transfer->desc_num);
		}
		/* mark transfer as successfully completed */
		transfer->state = TRANSFER_STATE_COMPLETED;
		transfer->desc_cmpl = transfer->desc_num;
		/* add dequeued number of descriptors during this run */
		engine->desc_dequeued += transfer->desc_num;

		if (engine->eop_flush) {
			/* check if eop received */
			struct sgdma_result *result = transfer->res_virt;
			int i;
			int max = transfer->desc_cmpl;

			for (i = 0; i < max; i++) {
				if ((result[i].status & RX_STATUS_EOP) != 0)
					transfer->flags |= XFER_FLAG_ST_C2H_EOP_RCVED;
			}
		}
	}

 transfer_del:
	/* remove completed transfer from list */
	list_del(engine->transfer_list.next);

	if (engine->running)
		sgdma_engine_stop(engine);

	/*
	 * Complete transfer - sets transfer to NULL if an asynchronous
	 * transfer has completed
	 */
	transfer = engine_transfer_completion(engine, transfer);

	return transfer;

 }

static int engine_service_resume(struct anlogic_dma_engine *engine)
{
   struct sgdma_transfer *transfer_started;

   if (!engine) {
	   pr_err("dma engine NULL\n");
	   return -EINVAL;
   }

   /* engine stopped? */
   if (!engine->running) {
	   /* in the case of shutdown, let it finish what's in the Q */
	   if (!list_empty(&engine->transfer_list)) {
		   /* (re)start engine */
		   transfer_started = engine_start(engine);
		   if (!transfer_started) {
			   pr_err("Failed to start dma engine\n");
			   return -EINVAL;
		   }
		   dbg_tfr("re-started %s engine with pending xfer 0x%p\n",
			   engine->name, transfer_started);
		   /* engine was requested to be shutdown? */
	   } else if (engine->shutdown & ENGINE_SHUTDOWN_REQUEST) {
		   engine->shutdown |= ENGINE_SHUTDOWN_IDLE;
		   /* awake task on engine's shutdown wait queue */
		   al_wake_up(&engine->shutdown_wq);
	   } else {
		   dbg_tfr("no pending transfers, %s engine stays idle.\n",
			   engine->name);
	   }
   } else if (list_empty(&engine->transfer_list)) {
	   engine_service_shutdown(engine);
   }
   return 0;
}

/**
 * engine_service() - service an SG DMA engine
 *
 * must be called with engine->lock already acquired
 *
 * @engine pointer to struct sgdma_engine
 *
 */
static int engine_service(struct anlogic_dma_engine *engine, int desc_writeback)
{
	struct sgdma_transfer *transfer = NULL;
	u32 desc_count = desc_writeback & WB_COUNT_MASK;
	u32 err_flag = desc_writeback & WB_ERR_MASK;
	int rv = 0;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	/* Service the engine */
	if (!engine->running) {
		dbg_tfr("Engine was not running!!! Clearing status\n");
		rv = engine_status_read(engine, 1, 0);
		if (rv < 0) {
			pr_err("%s failed to read status\n", engine->name);
			return rv;
		}
		return 0;
	}

	/*
	 * If called by the ISR or polling detected an error, read and clear
	 * engine status. For polled mode descriptor completion, this read is
	 * unnecessary and is skipped to reduce latency
	 */
	if ((desc_count == 0) || (err_flag != 0)) {
		rv = engine_status_read(engine, 1, 0);
		if (rv < 0) {
			pr_err("Failed to read engine status\n");
			return rv;
		}
	}

	/*
	 * engine was running but is no longer busy, or writeback occurred,
	 * shut down
	 */
	if ((engine->running && !(engine->status & SGDMA_STAT_BUSY)) ||
		(!engine->eop_flush && desc_count != 0)) {
		rv = engine_service_shutdown(engine);
		if (rv < 0) {
			pr_err("Failed to shutdown engine\n");
			return rv;
		}
	}

	/*
	 * If called from the ISR, or if an error occurred, the descriptor
	 * count will be zero.  In this scenario, read the descriptor count
	 * from HW.  In polled mode descriptor completion, this read is
	 * unnecessary and is skipped to reduce latency
	 */
	if (!desc_count)
		desc_count = read_register(&engine->regs->completed_desc_count);

	dbg_tfr("%s wb 0x%x, desc_count %u, err %u, dequeued %u.\n",
		engine->name, desc_writeback, desc_count, err_flag,
		engine->desc_dequeued);

	if (!desc_count)
		goto done;

	/* transfers on queue? */
	if (!list_empty(&engine->transfer_list)) {
		/* pick first transfer on queue (was submitted to the engine) */
		transfer = list_entry(engine->transfer_list.next,
					  struct sgdma_transfer, entry);

		dbg_tfr("head of queue transfer 0x%p has %d descriptors\n",
			transfer, (int)transfer->desc_num);

		dbg_tfr("Engine completed %d desc, %d not yet dequeued\n",
			(int)desc_count,
			(int)desc_count - engine->desc_dequeued);
	}

	/* account for already dequeued transfers during this engine run */
	desc_count -= engine->desc_dequeued;

	/* Process all but the last transfer */
	transfer = engine_service_transfer_list(engine, transfer, &desc_count);

	/*
	 * Process final transfer - includes checks of number of descriptors to
	 * detect faulty completion
	 */
	transfer = engine_service_final_transfer(engine, transfer, &desc_count);

	/* Restart the engine following the servicing */
	if (!engine->eop_flush) {
		rv = engine_service_resume(engine);
		if (rv < 0)
			pr_err("Failed to resume engine\n");
	}

done:
	/* If polling detected an error, signal to the caller */
	return err_flag ? -1 : 0;
}

/* engine_service_work */
static void engine_service_work(struct work_struct *work)
{
	struct anlogic_dma_engine *engine;
	unsigned long flags;
	int rv;

	engine = container_of(work, struct anlogic_dma_engine, work);
	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return;
	}

	/* lock the engine */
	spin_lock_irqsave(&engine->lock, flags);

	dbg_tfr("engine_service() for %s engine %p\n", engine->name, engine);
#if RANDOM_TEST
	if (engine->rtest) {
		rv = engine_service_rtest(engine, 0);
		if (rv < 0) {
			pr_err("Failed to service rtest engine\n");
			goto unlock;
		}
	} else
#endif
	if (engine->cyclic_req) {
		rv = engine_service_cyclic(engine);
		if (rv < 0) {
			pr_err("Failed to service cyclic engine\n");
			goto unlock;
		}
	} else {
		rv = engine_service(engine, 0);
		if (rv < 0) {
			pr_err("Failed to service engine\n");
			goto unlock;
		}
	}
	/* re-enable interrupts for this engine */
	if (engine->sgdev->msix_enabled) {
		write_register(
			engine->interrupt_enable_mask_value,
			&engine->regs->interrupt_enable_mask_w1s,
			(unsigned long)(&engine->regs
						 ->interrupt_enable_mask_w1s) -
				(unsigned long)(&engine->regs));
	} else {
		channel_interrupts_enable(engine->sgdev, engine->irq_bitmask);
	}

	/* unlock the engine */
unlock:
	spin_unlock_irqrestore(&engine->lock, flags);
}

static u32 engine_service_wb_monitor(struct anlogic_dma_engine *engine,
					 u32 expected_wb)
{
	struct sgdma_poll_wb *wb_data;
	u32 desc_wb = 0;
	u32 reg_desc_wb = 0;
	u32 sched_limit = 0;
	unsigned long timeout;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}
	wb_data = (struct sgdma_poll_wb *)engine->poll_mode_addr_virt;

	/*
	 * Poll the writeback location for the expected number of
	 * descriptors / error events This loop is skipped for cyclic mode,
	 * where the expected_desc_count passed in is zero, since it cannot be
	 * determined before the function is called
	 */

	timeout = jiffies + (POLL_TIMEOUT_SECONDS * HZ);
	while (expected_wb != 0) {
		desc_wb = wb_data->completed_desc_count;

		if (desc_wb)
			wb_data->completed_desc_count = 0;

		if (!desc_wb && st_c2h_poll_reg_fallback_enabled(engine)) {
			reg_desc_wb = read_register(&engine->regs->completed_desc_count);
			if (reg_desc_wb) {
				desc_wb = reg_desc_wb;
				pr_info("%s: wb fallback uses completed_desc_count=0x%08x.\n",
					engine->name, reg_desc_wb);
			}
		}

		if (desc_wb & WB_ERR_MASK)
			break;
		else if ((desc_wb & WB_COUNT_MASK) >= expected_wb)
			break;

		/* prevent system from hanging in polled mode */
		if (time_after(jiffies, timeout)) {
			pr_info("Polling timeout occurred");
			pr_info("desc_wb = 0x%08x, expected 0x%08x\n", desc_wb,
				expected_wb);
			if (!desc_wb && st_c2h_poll_reg_fallback_enabled(engine)) {
				reg_desc_wb = read_register(&engine->regs->completed_desc_count);
				if (reg_desc_wb) {
					desc_wb = reg_desc_wb;
					pr_info("%s: timeout fallback uses completed_desc_count=0x%08x.\n",
						engine->name, reg_desc_wb);
				}
			}
			if ((desc_wb & WB_COUNT_MASK) > expected_wb)
				desc_wb = expected_wb | WB_ERR_MASK;

			break;
		}

		/*
		 * Define NUM_POLLS_PER_SCHED to limit how much time is spent
		 * in the scheduler
		 */
		if (sched_limit != 0) {
			if ((sched_limit % NUM_POLLS_PER_SCHED) == 0)
				schedule();

		}
		sched_limit++;
	}

	return desc_wb;
}

int engine_service_poll(struct anlogic_dma_engine *engine,
				   u32 expected_desc_count)
{
	u32 desc_wb = 0;
	unsigned long flags;
	int rv = 0;

	dbg_tfr("%s service.\n", engine->name);

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return -EINVAL;
	}

	if (engine->cyclic_req == NULL) {
		/*
		 * Poll the writeback location for the expected number of
		 * descriptors / error events This loop is skipped for cyclic mode,
		 * where the expected_desc_count passed in is zero, since it cannot be
		 * determined before the function is called
		 */
		desc_wb = engine_service_wb_monitor(engine, expected_desc_count);
		if (!desc_wb) {
			pr_err("%s not get comp desc at this poll work.\n", engine->name);
			return 0;
		}
	}

	spin_lock_irqsave(&engine->lock, flags);
#if RANDOM_TEST
	if (engine->rtest) {
		rv = engine_service_rtest(engine, desc_wb);
	} else
#endif
	if (engine->cyclic_req) {
		rv = engine_service_cyclic(engine);
	} else {
		rv = engine_service(engine, desc_wb);
	}

	spin_unlock_irqrestore(&engine->lock, flags);

	return rv;
}

/* transfer_queue() - Queue a DMA transfer on the engine
*
* @engine DMA engine doing the transfer
* @transfer DMA transfer submitted to the engine
*
* Takes and releases the engine spinlock
*/
int transfer_queue(struct anlogic_dma_engine *engine,
			struct sgdma_transfer *transfer)
{
	int rv = 0;
	struct sgdma_transfer *transfer_started;
	struct anlogic_dev *sgdev;
	unsigned long flags;

	if (!engine) {
	   pr_err("dma engine NULL\n");
	   return -EINVAL;
	}

	if (!engine->sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	if (!transfer) {
		pr_err("%s Invalid DMA transfer\n", engine->name);
		return -EINVAL;
	}

	if (transfer->desc_num == 0) {
		pr_err("%s void descriptors in the transfer list\n",
			   engine->name);
		return -EINVAL;
	}
	dbg_tfr("%s (transfer=0x%p).\n", __func__, transfer);

	/* lock the engine state */
	spin_lock_irqsave(&engine->lock, flags);

	engine->prev_cpu = get_cpu();
	put_cpu();

	/* engine is being shutdown; do not accept new transfers */
	if (engine->shutdown & ENGINE_SHUTDOWN_REQUEST) {
		pr_info("engine %s offline, transfer 0x%p not queued.\n",
			engine->name, transfer);
		rv = -EBUSY;
		goto shutdown;
	}

	/* mark the transfer as submitted */
	transfer->state = TRANSFER_STATE_SUBMITTED;
	/* add transfer to the tail of the engine transfer queue */
	list_add_tail(&transfer->entry, &engine->transfer_list);

	/* engine is idle? */
	if (!engine->running) {
		/* start engine */
		dbg_tfr("%s(): starting %s engine.\n", __func__, engine->name);
		transfer_started = engine_start(engine);
		if (!transfer_started) {
			pr_err("Failed to start dma engine\n");
			goto shutdown;
		}
		dbg_tfr("transfer=0x%p started %s engine with transfer 0x%p.\n",
			transfer, engine->name, transfer_started);
	} else {
		dbg_tfr("transfer=0x%p queued, with %s engine running.\n",
			transfer, engine->name);
	}

shutdown:
	/* unlock the engine state */
	dbg_tfr("engine->running = %d\n", engine->running);
	spin_unlock_irqrestore(&engine->lock, flags);
	return rv;
}

/* transfer_destroy() - free transfer */
static void transfer_destroy(struct anlogic_dev *sgdev, struct sgdma_transfer *xfer)
{
	/* free descriptors */
	sgdma_desc_done(xfer->desc_virt, xfer->desc_num);

	if (xfer->last_in_request && (xfer->flags & XFER_FLAG_NEED_UNMAP)) {
			struct sg_table *sgt = xfer->sgt;

		if (sgt->nents) {
			dma_unmap_sg(&sgdev->pdev->dev, sgt->sgl, sgt->orig_nents,
				xfer->dir);
			sgt->nents = 0;
		}
	}

	if (xfer->flags & XFER_FLAG_ALLOC_DESC) {
		if (xfer->desc_virt)
			dma_free_coherent(&sgdev->pdev->dev,
					  sizeof(struct sgdma_desc) * xfer->desc_num,
					  xfer->desc_virt, xfer->desc_bus);
		if (xfer->res_virt)
			dma_free_coherent(&sgdev->pdev->dev,
					  sizeof(struct sgdma_result) * xfer->desc_num,
					  xfer->res_virt, xfer->res_bus);
	}
}

static int transfer_build(struct anlogic_dma_engine *engine,
			struct sgdma_request_cb *req, struct sgdma_transfer *xfer,
			unsigned int desc_max)
{
	struct sw_desc *sdesc = &(req->sdesc[req->sw_desc_idx]);
	int i = 0;
	int j = 0;
	dma_addr_t bus = xfer->res_bus;

	for (; i < desc_max; i++, j++, sdesc++) {

#ifdef __LIBSGDMA_DEBUG__
		dbg_desc("sw desc %d/%u: 0x%llx, 0x%x, ep 0x%llx.\n",
			 i + req->sw_desc_idx, req->sw_desc_cnt, sdesc->addr,
			 sdesc->len, req->ep_addr);
#endif

		/* fill in descriptor entry j with transfer details */
		sgdma_desc_set(xfer->desc_virt + j, sdesc->addr, req->ep_addr,
				  sdesc->len, xfer->dir);
		xfer->len += sdesc->len;

		/* for non-inc-add mode don't increment ep_addr */
		if (!engine->non_incr_addr)
			req->ep_addr += sdesc->len;

		/* replace source addresses with result write-back addresses */
		if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
			memset(xfer->res_virt + j, 0,
				sizeof(struct sgdma_result));
			xfer->desc_virt[j].src_addr_lo =
						cpu_to_le32(PCI_DMA_L(bus));
			xfer->desc_virt[j].src_addr_hi =
						cpu_to_le32(PCI_DMA_H(bus));
			bus += sizeof(struct sgdma_result);
		}

	}
	req->sw_desc_idx += desc_max;
	return 0;
}

/*
 * should hold the engine->lock;
 */
static int transfer_abort(struct anlogic_dma_engine *engine,
			  struct sgdma_transfer *transfer)
{
	struct sgdma_transfer *head;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (!transfer) {
		pr_err("Invalid DMA transfer\n");
		return -EINVAL;
	}

	if (transfer->desc_num == 0) {
		pr_err("%s void descriptors in the transfer list\n",
			   engine->name);
		return -EINVAL;
	}

	pr_info("abort transfer 0x%p, desc %d, engine desc queued %d.\n",
		transfer, transfer->desc_num, engine->desc_dequeued);

	head = list_entry(engine->transfer_list.next, struct sgdma_transfer,
			  entry);
	if (head == transfer)
		list_del(engine->transfer_list.next);
	else
		pr_info("engine %s, transfer 0x%p NOT found, 0x%p.\n",
			engine->name, transfer, head);

	if (transfer->state == TRANSFER_STATE_SUBMITTED)
		transfer->state = TRANSFER_STATE_ABORTED;
	return 0;
}

int transfer_init(struct anlogic_dma_engine *engine,
			struct sgdma_request_cb *req, struct sgdma_transfer *xfer)
{
	unsigned int desc_max = min_t(unsigned int,
				req->sw_desc_cnt - req->sw_desc_idx,
				engine->desc_max);
	int i = 0;
	int last = 0;
	u32 control;
	unsigned long flags;

	dbg_sg("engine->desc_max %d, req->sw_desc_cnt %d, req->sw_desc_idx %d, desc_max %d.\n",
		engine->desc_max, req->sw_desc_cnt, req->sw_desc_idx, desc_max);

	memset(xfer, 0, sizeof(*xfer));

	/* lock the engine state */
	spin_lock_irqsave(&engine->lock, flags);
	/* initialize wait queue */
	init_waitqueue_head(&xfer->wq);

	if ((engine->desc_idx + desc_max) > engine->desc_max &&
	    !st_c2h_credit_enabled(engine) &&
	    (req->flags & REQ_FLAG_POSSIBLE_MAX_DESC)) {
		dma_addr_t desc_bus = 0, res_bus = 0;
		void *desc_virt = 0, *res_virt = 0;

		desc_virt = dma_alloc_coherent(&engine->sgdev->pdev->dev,
				sizeof(struct sgdma_desc) * desc_max,
				&desc_bus, GFP_KERNEL);
		if (!desc_virt)
			goto cont;

		if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
			res_virt = dma_alloc_coherent(&engine->sgdev->pdev->dev,
						      sizeof(struct sgdma_result) * desc_max,
						      &res_bus, GFP_KERNEL);
			if (!res_virt) {
				dma_free_coherent(&engine->sgdev->pdev->dev,
						  sizeof(struct sgdma_desc) * desc_max,
						  desc_virt, desc_bus);
				goto cont;
			}
		}

		xfer->dir = engine->dir;
		xfer->desc_virt = desc_virt;
		xfer->desc_bus = desc_bus;
		xfer->res_virt = res_virt;
		xfer->res_bus = res_bus;
		xfer->desc_index = -1;
		xfer->flags |= XFER_FLAG_ALLOC_DESC;
		engine->desc_idx = 0;
		goto desc_init;
	}
cont:

	/* remember direction of transfer */
	xfer->dir = engine->dir;
	xfer->desc_virt = engine->desc + engine->desc_idx;
	xfer->res_virt = engine->cyclic_result + engine->desc_idx;
	xfer->desc_bus = engine->desc_bus +
			(sizeof(struct sgdma_desc) * engine->desc_idx);
	xfer->res_bus = engine->cyclic_result_bus +
			(sizeof(struct sgdma_result) * engine->desc_idx);
	xfer->desc_index = engine->desc_idx;

	/* Need to handle desc_used >= engine->desc_max */
	if ((engine->desc_idx + desc_max) >= engine->desc_max)
		desc_max = engine->desc_max - engine->desc_idx;
desc_init:
	transfer_desc_init(xfer, desc_max);

	dbg_sg("xfer= %p transfer->desc_bus = 0x%llx, engine->desc_idx = %d, desc_max = %d\n",
		xfer, (u64)xfer->desc_bus, engine->desc_idx, desc_max);
	transfer_build(engine, req, xfer, desc_max);

	xfer->desc_adjacent = desc_max;

	/* terminate last descriptor */
	last = desc_max - 1;
	/* stop engine, EOP for AXI ST, req IRQ on last descriptor */
	control = SGDMA_DESC_STOPPED;
	if (req->sw_desc_cnt == req->sw_desc_idx)
		control |= SGDMA_DESC_EOP;
	control |= SGDMA_DESC_COMPLETED;
	sgdma_desc_control_set(xfer->desc_virt + last, control);

	/*
	 * FIX: Always set SGDMA_DESC_COMPLETED on all descriptors.
	 * The Anlogic SGDMA hardware writeback counter only counts
	 * descriptors that have the COMPLETED flag set. Without this
	 * flag on all descriptors, desc_cmpl_th (= desc_max) can never
	 * be reached, causing poll timeout with desc_wb = 0.
	 */
	for (i = 0; i < last; i++)
		sgdma_desc_control_set(xfer->desc_virt + i,
				SGDMA_DESC_COMPLETED);

	if (engine->eop_flush)
		xfer->desc_cmpl_th = 1;
	else
		xfer->desc_cmpl_th = desc_max;

	xfer->desc_num = desc_max;
	if (!(xfer->flags & XFER_FLAG_ALLOC_DESC))
		engine->desc_idx = (engine->desc_idx + desc_max) % engine->desc_max;
	engine->desc_used += desc_max;

	/* fill in adjacent numbers */
	for (i = 0; i < xfer->desc_num; i++) {
		u32 next_adj = sgdma_get_next_adj(xfer->desc_num - i - 1,
						(xfer->desc_virt + i)->next_lo);

		sgdma_desc_adjacent(xfer->desc_virt + i, next_adj);
	}

	spin_unlock_irqrestore(&engine->lock, flags);
	return 0;
}

ssize_t sgdma_xfer_aperture(struct anlogic_dma_engine *engine, bool write, u64 ep_addr,
			unsigned int aperture, struct sg_table *sgt,
			bool dma_mapped, int timeout_ms)
{
	struct anlogic_dev *sgdev;
	struct sgdma_request_cb *req = NULL;
	struct scatterlist *sg;
	enum dma_data_direction dir = write ? DMA_TO_DEVICE : DMA_FROM_DEVICE;
	unsigned int maxlen = min_t(unsigned int, aperture, desc_blen_max);
	unsigned int sg_max;
	unsigned int tlen = 0;
	u64 ep_addr_max = ep_addr + aperture - 1;
	ssize_t done = 0;
	int i, rv = 0;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return -EINVAL;
	}

	sgdev = engine->sgdev;
	if (sgdma_device_flag_check(sgdev, XDEV_FLAG_OFFLINE)) {
		pr_info("sgdev 0x%p, offline.\n", sgdev);
		return -EBUSY;
	}

	/* check the direction */
	if (engine->dir != dir) {
		pr_info("0x%p, %s, W %d, 0x%x/0x%x mismatch.\n", engine,
			engine->name, write, engine->dir, dir);
		return -EINVAL;
	}

	if (engine->streaming) {
		pr_info("%s aperture not supported in ST.\n", engine->name);
		return -EINVAL;
	}

	if (!dma_mapped) {
		sgt->nents = dma_map_sg(&sgdev->pdev->dev, sgt->sgl, sgt->orig_nents,
					dir);
		if (!sgt->nents) {
			pr_info("map sgl failed, sgt 0x%p.\n", sgt);
			return -EIO;
		}
	} else if (!sgt->nents) {
		pr_err("sg table has invalid number of entries 0x%p.\n", sgt);
		return -EIO;
	}
	sg_max = sgt->nents;

	req = kzalloc(sizeof(struct sgdma_request_cb), GFP_KERNEL);
	if (!req) {
		rv = -ENOMEM;
		goto unmap_sgl;
	}
	memset(req, 0, sizeof(struct sgdma_request_cb));
	req->sgt = sgt;
	req->ep_addr = ep_addr;
	req->aperture = aperture;
	req->sg = sgt->sgl;

	for (i = 0, sg = sgt->sgl; i < sgt->nents; i++, sg = sg_next(sg))
		tlen += sg_dma_len(sg);
	req->total_len = tlen;

	dbg_tfr("%s, aperture: sg cnt %u.\n", engine->name, sgt->nents);

	mutex_lock(&engine->desc_lock);

	while (req->offset < req->total_len) {
		unsigned long flags;
		struct sgdma_transfer *xfer = &req->tfer[0];
		unsigned int sg_offset = req->sg_offset;
		unsigned int desc_idx, desc_max, desc_cnt = 0;
		struct sgdma_desc *desc_virt;
		dma_addr_t desc_bus;

		/* initialize transfer */
		memset(xfer, 0, sizeof(struct sgdma_transfer));
		init_waitqueue_head(&xfer->wq);

		xfer->dir = engine->dir;
		if (!dma_mapped)
			xfer->flags = XFER_FLAG_NEED_UNMAP;

		spin_lock_irqsave(&engine->lock, flags);

		desc_idx = engine->desc_idx;
		desc_max = engine->desc_max;

		xfer->desc_virt = desc_virt = engine->desc + desc_idx;
		xfer->res_virt = engine->cyclic_result + desc_idx;
		xfer->desc_bus = desc_bus = engine->desc_bus +
					(sizeof(struct sgdma_desc) * desc_idx);
		xfer->res_bus = engine->cyclic_result_bus +
					(sizeof(struct sgdma_result) * desc_idx);
		xfer->desc_index = desc_idx;

		/* build transfer */
		sg = req->sg;
		ep_addr = req->ep_addr + (req->offset & (aperture - 1));
		i = req->sg_idx;

		for (sg = req->sg; i < sg_max && desc_idx < desc_max;
			i++, sg = sg_next(sg)) {
			dma_addr_t addr = sg_dma_address(sg);

			tlen = sg_dma_len(sg);
			if (sg_offset) {
				tlen -= sg_offset;
				addr += sg_offset;
			}

			while (tlen) {
				unsigned int len = min_t(unsigned int, tlen,
								 maxlen);

				if (ep_addr > ep_addr_max)
					ep_addr = req->ep_addr;

				if ((ep_addr + len) > ep_addr_max)
					len = ep_addr_max - ep_addr + 1;

				sgdma_desc_set(engine->desc + desc_idx, addr,
						ep_addr, len, dir);

						dbg_desc("sg %d -> desc %u: ep 0x%llx, 0x%llx + %u \n",
					i, desc_idx, ep_addr, addr, len);

				sg_offset += len;
				req->offset += len;
				xfer->len += len;
				ep_addr += len;
				addr += len;
				tlen -= len;

				desc_idx++;
				desc_cnt++;
				if (desc_idx == desc_max)
					break;
			}

			if (!tlen)
				sg_offset = 0;
			else
				break;
		}

		req->sg_offset = sg_offset;
		req->sg_idx = i;

		xfer->desc_adjacent = desc_cnt;
		xfer->desc_num = desc_cnt;
		engine->desc_used += desc_cnt;

		/* create the desc linked list */
		for (i = 0; i < (desc_cnt - 1); i++, desc_virt++) {
			desc_bus += sizeof(struct sgdma_desc);
			/* singly-linked list uses bus addresses */
			desc_virt->next_lo = cpu_to_le32(PCI_DMA_L(desc_bus));
					desc_virt->next_hi = cpu_to_le32(PCI_DMA_H(desc_bus));
					desc_virt->control = cpu_to_le32(DESC_MAGIC);
		}
		/* terminate the last descriptor next pointer */
		desc_virt->next_lo = cpu_to_le32(0);
		desc_virt->next_hi = cpu_to_le32(0);
		desc_virt->control = cpu_to_le32(DESC_MAGIC |
					SGDMA_DESC_STOPPED | SGDMA_DESC_EOP |
					SGDMA_DESC_COMPLETED);

		xfer->desc_cmpl_th = desc_cnt;

		/* fill in adjacent numbers */
		for (i = 0; i < desc_cnt; i++) {
			u32 next_adj = sgdma_get_next_adj(desc_cnt - i - 1,
					(xfer->desc_virt + i)->next_lo);

					sgdma_desc_adjacent(xfer->desc_virt + i, next_adj);
			}

		engine->desc_idx = (engine->desc_idx + desc_cnt) % desc_max;
		spin_unlock_irqrestore(&engine->lock, flags);

		/* last transfer for the given request? */
		if (req->offset == req->total_len) {
			xfer->last_in_request = 1;
			xfer->sgt = sgt;
		}

		dbg_tfr("xfer %u,%u/%u, ep 0x%llx/0x%x, done %ld, sg %u/%u, desc %u.\n",
			xfer->len, req->offset, req->total_len, req->ep_addr,
			req->aperture, done, req->sg_idx, sg_max, desc_cnt);

		rv = transfer_queue(engine, xfer);
		if (rv < 0) {
			mutex_unlock(&engine->desc_lock);
			pr_info("unable to submit %s, %d.\n", engine->name, rv);
			goto unmap_sgl;
		}

		if (engine->cmplthp)
			sgdma_kthread_wakeup(engine->cmplthp);

		if (timeout_ms > 0)
			al_wait_event_interruptible_timeout(xfer->wq,
				(xfer->state != TRANSFER_STATE_SUBMITTED),
				msecs_to_jiffies(timeout_ms));
		else
			al_wait_event_interruptible(xfer->wq,
				(xfer->state != TRANSFER_STATE_SUBMITTED));

		spin_lock_irqsave(&engine->lock, flags);

		switch (xfer->state) {
		case TRANSFER_STATE_COMPLETED:
			spin_unlock_irqrestore(&engine->lock, flags);

			rv = 0;
			dbg_tfr("transfer %p, %u, ep 0x%llx compl, +%lu.\n",
				xfer, xfer->len, req->ep_addr - xfer->len,
				done);

			done += xfer->len;

			break;
		case TRANSFER_STATE_FAILED:
			pr_info("xfer 0x%p,%u, failed, ep 0x%llx.\n", xfer,
				xfer->len, req->ep_addr - xfer->len);
			spin_unlock_irqrestore(&engine->lock, flags);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -EIO;
			break;
		default:
			/* transfer can still be in-flight */
			pr_info("xfer 0x%p,%u, s 0x%x timed out, ep 0x%llx.\n",
				xfer, xfer->len, xfer->state, req->ep_addr);
			rv = engine_status_read(engine, 0, 1);
			if (rv < 0) {
				pr_err("Failed to read engine status\n");
			} else if (rv == 0) {
				//engine_status_dump(engine);
				rv = transfer_abort(engine, xfer);
				if (rv < 0) {
					pr_err("Failed to stop engine\n");
				} else if (rv == 0) {
					rv = sgdma_engine_stop(engine);
					if (rv < 0)
						pr_err("Failed to stop engine\n");
				}
			}
			spin_unlock_irqrestore(&engine->lock, flags);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -ERESTARTSYS;
			break;
		}

		engine->desc_used -= xfer->desc_num;
		transfer_destroy(sgdev, xfer);

		if (rv < 0) {
			mutex_unlock(&engine->desc_lock);
			goto unmap_sgl;
		}
	}
	mutex_unlock(&engine->desc_lock);

unmap_sgl:
	if (!dma_mapped && sgt->nents) {
		dma_unmap_sg(&sgdev->pdev->dev, sgt->sgl, sgt->orig_nents, dir);
		sgt->nents = 0;
	}

	if (req)
		sgdma_request_free(req);

	/* as long as some data is processed, return the count */
	return done ? done : rv;
}

ssize_t sgdma_xfer_submit(void *dev_hndl, int channel, bool write, u64 ep_addr,
			  struct sg_table *sgt, bool dma_mapped, int timeout_ms,
			  u32 *controls)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;
	struct anlogic_dma_engine *engine;
	int rv = 0, tfer_idx = 0, i;
	ssize_t done = 0;
	struct scatterlist *sg = sgt->sgl;
	int nents, idx;
	enum dma_data_direction dir = write ? DMA_TO_DEVICE : DMA_FROM_DEVICE;
	struct sgdma_request_cb *req = NULL;

	if (!dev_hndl)
		return -EINVAL;

	if (write == 1) {
		if (channel >= sgdev->h2c_channel_max) {
			pr_err("H2C channel %d >= %d.\n", channel,
				sgdev->h2c_channel_max);
			return -EINVAL;
		}
		engine = &sgdev->engine_h2c[channel];
	} else if (write == 0) {
		if (channel >= sgdev->c2h_channel_max) {
			pr_err("C2H channel %d >= %d.\n", channel,
				sgdev->c2h_channel_max);
			return -EINVAL;
		}
		engine = &sgdev->engine_c2h[channel];
	}

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return -EINVAL;
	}

	sgdev = engine->sgdev;
	if (sgdma_device_flag_check(sgdev, XDEV_FLAG_OFFLINE)) {
		pr_info("sgdev 0x%p, offline.\n", sgdev);
		return -EBUSY;
	}

	/* check the direction */
	if (engine->dir != dir) {
		pr_info("0x%p, %s, %d, W %d, 0x%x/0x%x mismatch.\n", engine,
			engine->name, channel, write, engine->dir, dir);
		return -EINVAL;
	}

	if (!dma_mapped) {
		nents = dma_map_sg(&sgdev->pdev->dev, sg, sgt->orig_nents, dir);
		if (nents != sgt->orig_nents) {
			pr_info("map sgl failed, sgt 0x%p.\n", sgt);
			return -EIO;
		}
		sgt->nents = nents;
	} else {
		if (!sgt->nents) {
			pr_err("sg table has invalid number of entries 0x%p.\n",
				   sgt);
			return -EIO;
		}
	}

	req = sgdma_init_request(sgt, ep_addr, controls);
	if (!req) {
		rv = -ENOMEM;
		goto unmap_sgl;
	}

	dbg_tfr("%s, len %u sg cnt %u.\n", engine->name, req->total_len,
		req->sw_desc_cnt);

	sg = sgt->sgl;
	nents = req->sw_desc_cnt;
	mutex_lock(&engine->desc_lock);

	while (nents) {
		unsigned long flags;
		struct sgdma_transfer *xfer;
		idx = req->sw_desc_idx;

		/* build transfer */
		rv = transfer_init(engine, req, &req->tfer[0]);
		if (rv < 0) {
			mutex_unlock(&engine->desc_lock);
			goto unmap_sgl;
		}
		xfer = &req->tfer[0];

		if (!dma_mapped)
			xfer->flags |= XFER_FLAG_NEED_UNMAP;
		xfer->private = req;
		if (controls) {
			unsigned long descflg = 0;

			if (engine->eop_flush)
				descflg |= SGDMA_DESC_COMPLETED;

			xfer->flags |= XFER_FLAG_IGNORE_HALFWAY_IRQ;
			for (i = 0; i < xfer->desc_num - 1; i++) {
				sgdma_desc_control_set(xfer->desc_virt + i,
						       ((req->sdesc[idx + i].control | descflg) &
							LS_BYTE_MASK) & ~SGDMA_DESC_STOPPED);
			}
			sgdma_desc_control_set(xfer->desc_virt + i,
					       (req->sdesc[idx + i].control & LS_BYTE_MASK) |
					       SGDMA_DESC_STOPPED | SGDMA_DESC_COMPLETED);
		}

		/* last transfer for the given request? */
		nents -= xfer->desc_num;
		if (!nents) {
			xfer->last_in_request = 1;
			xfer->sgt = sgt;
		}

		dbg_tfr("%s, poll_wb_cnt_phy 0x%llx, xfer %u, ep 0x%llx, done %lu, sg %u/%u.\n", engine->name, engine->poll_mode_bus, xfer->len,
			req->ep_addr, done, req->sw_desc_idx, req->sw_desc_cnt);

#ifdef __LIBSGDMA_DEBUG__
		transfer_dump(xfer);
#endif

		rv = transfer_queue(engine, xfer);
		if (rv < 0) {
			mutex_unlock(&engine->desc_lock);
			pr_info("unable to submit %s, %d.\n", engine->name, rv);
			goto unmap_sgl;
		}

		if (engine->cmplthp)
			sgdma_kthread_wakeup(engine->cmplthp);

		if (timeout_ms > 0)
			al_wait_event_interruptible_timeout(xfer->wq,
				(xfer->state != TRANSFER_STATE_SUBMITTED),
				msecs_to_jiffies(timeout_ms));
		else
			al_wait_event_interruptible(xfer->wq,
				(xfer->state != TRANSFER_STATE_SUBMITTED));

		spin_lock_irqsave(&engine->lock, flags);

		switch (xfer->state) {
		case TRANSFER_STATE_COMPLETED:
			spin_unlock_irqrestore(&engine->lock, flags);

			rv = 0;

			/* For C2H streaming use writeback results */
			if (engine->streaming &&
				engine->dir == DMA_FROM_DEVICE) {
				done += st_c2h_completed_bytes(engine, xfer);

				/* finish the whole request */
				if (engine->eop_flush && (xfer->flags & XFER_FLAG_ST_C2H_EOP_RCVED))
					nents = 0;
			} else
				done += xfer->len;

			dbg_tfr("%s transfer %p, %u, ep 0x%llx compl, +%lu, nents %d.\n",
				engine->name, xfer, xfer->len, req->ep_addr - xfer->len,
				done, nents);

			break;
		case TRANSFER_STATE_FAILED:
			pr_info("%s xfer 0x%p,%u, failed, ep 0x%llx.\n",
				engine->name, xfer, xfer->len, req->ep_addr - xfer->len);
			spin_unlock_irqrestore(&engine->lock, flags);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -EIO;
			break;
		default:
			/* transfer can still be in-flight */
			pr_info("%s xfer 0x%p,%u, s 0x%x timed out, ep 0x%llx.\n",
				engine->name, xfer, xfer->len, xfer->state, req->ep_addr);
			rv = engine_status_read(engine, 0, 1);
			if (rv < 0) {
				pr_err("Failed to read engine status\n");
			} else if (rv == 0) {
				engine_status_dump(engine);
				rv = transfer_abort(engine, xfer);
				if (rv < 0) {
					pr_err("Failed to stop engine\n");
				} else if (rv == 0) {
					rv = sgdma_engine_stop(engine);
					if (rv < 0)
						pr_err("Failed to stop engine\n");
				}
			}
			spin_unlock_irqrestore(&engine->lock, flags);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -ERESTARTSYS;
			break;
		}

		engine->desc_used -= xfer->desc_num;
		transfer_destroy(sgdev, xfer);

		/* use multiple transfers per request if we could not fit
		 * all data within single descriptor chain.
		 */
		tfer_idx++;

		if (rv < 0) {
			mutex_unlock(&engine->desc_lock);
			goto unmap_sgl;
		}
	} /* while (sg) */
	mutex_unlock(&engine->desc_lock);

unmap_sgl:
	if (!dma_mapped && sgt->nents) {
		dma_unmap_sg(&sgdev->pdev->dev, sgt->sgl, sgt->orig_nents, dir);
		sgt->nents = 0;
	}

	if (req)
		sgdma_request_free(req);

	/* as long as some data is processed, return the count */
	return done ? done : rv;
}
EXPORT_SYMBOL_GPL(sgdma_xfer_submit);

/**
 * sgdma_engine_set_eop_flush - enable/disable EOP-based transfer termination
 * @dev_hndl: SGDMA device handle from anlogic_get_sgdev()
 * @channel:  DMA channel number (0 for single-channel designs)
 * @write:    false for C2H, true for H2C
 * @enable:   1 to enable eop_flush, 0 to disable
 *
 * When eop_flush is enabled, the engine will terminate a transfer early
 * when it receives EOP (tlast) from the FPGA, returning only the actual
 * bytes received.  This is essential for frame-aligned video capture.
 */
int sgdma_engine_set_eop_flush(void *dev_hndl, int channel, bool write,
			       int enable)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;
	struct anlogic_dma_engine *engine;

	if (!sgdev)
		return -EINVAL;

	if (write) {
		if (channel >= sgdev->h2c_channel_max)
			return -EINVAL;
		engine = &sgdev->engine_h2c[channel];
	} else {
		if (channel >= sgdev->c2h_channel_max)
			return -EINVAL;
		engine = &sgdev->engine_c2h[channel];
	}

	if (!engine || engine->magic != MAGIC_ENGINE)
		return -EINVAL;

	engine->eop_flush = enable ? 1 : 0;
	pr_info("engine %s: eop_flush set to %d\n", engine->name,
		engine->eop_flush);
	return 0;
}
EXPORT_SYMBOL_GPL(sgdma_engine_set_eop_flush);

 int sgdma_performance_submit(struct anlogic_dev *sgdev, struct anlogic_dma_engine *engine)
 {
	u32 max_consistent_size = SGDMA_PERF_NUM_DESC * 32 * 1024; /* 1024 pages, 4MB */
	u32 control;
	struct sgdma_transfer *transfer;
	u64 ep_addr = 0;
	int num_desc_in_a_loop = SGDMA_PERF_NUM_DESC;
	int size_in_desc = engine->sgdma_perf->transfer_size;
	int size = size_in_desc * num_desc_in_a_loop;
	int i;
	int rv = -ENOMEM;
	unsigned char free_desc = 0;

	if (size_in_desc > max_consistent_size) {
		pr_err("%s max consistent size %d is more than supported %d\n",
		       engine->name, size_in_desc, max_consistent_size);
		return -EINVAL;
	}

	if (size > max_consistent_size) {
		size = max_consistent_size;
		num_desc_in_a_loop = size / size_in_desc;
	}

	engine->perf_buf_virt = dma_alloc_coherent(&sgdev->pdev->dev, size_in_desc,
						   &engine->perf_buf_bus,
						   GFP_KERNEL);
	if (!engine->perf_buf_virt) {
		pr_err("dev %s, %s DMA allocation OOM.\n",
		       dev_name(&sgdev->pdev->dev), engine->name);
		return rv;
	}

	/* allocate transfer data structure */
	transfer = kzalloc(sizeof(struct sgdma_transfer), GFP_KERNEL);
	if (!transfer) {
		pr_err("dev %s, %s transfer request OOM.\n",
		       dev_name(&sgdev->pdev->dev), engine->name);
		goto err_engine_transfer;
	}
	/* 0 = write engine (to_dev=0) , 1 = read engine (to_dev=1) */
	transfer->dir = engine->dir;
	/* set number of descriptors */
	transfer->desc_num = num_desc_in_a_loop;

	/* allocate descriptor list */
	if (!engine->desc) {
		engine->desc = dma_alloc_coherent(
			&sgdev->pdev->dev,
			num_desc_in_a_loop * sizeof(struct sgdma_desc),
			&engine->desc_bus, GFP_KERNEL);
		if (!engine->desc) {
			pr_err("%s DMA memory allocation for descriptors failed\n",
			       engine->name);
			goto err_engine_desc;
		}
		dbg_init("device %s, engine %s pre-alloc desc 0x%p,0x%llx.\n",
			 dev_name(&sgdev->pdev->dev), engine->name, engine->desc,
			 engine->desc_bus);
		free_desc = 1;
	}
	transfer->desc_virt = engine->desc;
	transfer->desc_bus = engine->desc_bus;

	rv = transfer_desc_init(transfer, transfer->desc_num);
	if (rv < 0) {
		pr_err("Failed to initialize descriptors\n");
		goto err_dma_desc;
	}

	dbg_sg("transfer->desc_bus = 0x%llx.\n", (u64)transfer->desc_bus);

	for (i = 0; i < transfer->desc_num; i++) {
		struct sgdma_desc *desc = transfer->desc_virt + i;
		dma_addr_t rc_bus_addr = engine->perf_buf_bus;

		/* fill in descriptor entry with transfer details */
		sgdma_desc_set(desc, rc_bus_addr, ep_addr, size_in_desc,
				   engine->dir);
	}

	/* stop engine and request interrupt on last descriptor */
	rv = sgdma_desc_control_set(transfer->desc_virt, 0);
	if (rv < 0) {
		pr_err("Failed to set desc control\n");
		goto err_dma_desc;
	}
	/* create a linked loop */
	sgdma_desc_link(transfer->desc_virt + transfer->desc_num - 1,
			transfer->desc_virt, transfer->desc_bus);

	transfer->desc_adjacent = num_desc_in_a_loop;
	for (i = 0; i < transfer->desc_num; i++) {
		u32 next_adj = sgdma_get_next_adj(transfer->desc_num - i - 1,
						  (transfer->desc_virt + i)->next_lo);

		sgdma_desc_adjacent(transfer->desc_virt + i, next_adj);
	}

	// fix last adjacent for cyclic transfer
	sgdma_desc_adjacent(transfer->desc_virt + transfer->desc_num - 1,
			    sgdma_get_next_adj(transfer->desc_num,
					       cpu_to_le32(PCI_DMA_L(transfer->desc_bus))));

	transfer->cyclic = 1;

	/* initialize wait queue */
	init_waitqueue_head(&transfer->wq);

#ifdef __LIBSGDMA_DEBUG__
	transfer_dump(transfer);
#endif

	dbg_perf("Queueing SGDMA I/O %s request for performance measurement.\n",
		 engine->dir ? "write (to dev)" : "read (from dev)");
	rv = transfer_queue(engine, transfer);
	if (rv < 0) {
		pr_err("Failed to queue transfer\n");
		goto err_dma_desc;
	}
	return 0;

 err_dma_desc:
	if (free_desc && engine->desc)
		dma_free_coherent(&sgdev->pdev->dev,
				  num_desc_in_a_loop * sizeof(struct sgdma_desc),
				  engine->desc, engine->desc_bus);
	engine->desc = NULL;
 err_engine_desc:
	if (transfer)
		list_del(&transfer->entry);
	kfree(transfer);
	transfer = NULL;
 err_engine_transfer:
	if (engine->perf_buf_virt)
		dma_free_coherent(&sgdev->pdev->dev, size_in_desc, engine->perf_buf_virt,
				  engine->perf_buf_bus);
	engine->perf_buf_virt = NULL;
	return rv;
 }
 EXPORT_SYMBOL_GPL(sgdma_performance_submit);

ssize_t sgdma_xfer_completion(void *cb_hndl, void *dev_hndl, int channel,
			bool write, u64 ep_addr, struct sg_table *sgt,
			bool dma_mapped, int timeout_ms)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;
	struct sgdma_io_cb *cb = (struct sgdma_io_cb *)cb_hndl;
	struct anlogic_dma_engine *engine;
	int rv = 0, tfer_idx = 0;
	ssize_t done = 0;
	int nents;
	enum dma_data_direction dir = write ? DMA_TO_DEVICE : DMA_FROM_DEVICE;
	struct sgdma_request_cb *req = NULL;
	struct sgdma_transfer *xfer;
	int i;
	struct sgdma_result *result;

	if (write == 1) {
		if (channel >= sgdev->h2c_channel_max) {
			pr_warn("H2C channel %d >= %d.\n",
				channel, sgdev->h2c_channel_max);
			return -EINVAL;
		}
		engine = &sgdev->engine_h2c[channel];
	} else if (write == 0) {
		if (channel >= sgdev->c2h_channel_max) {
			pr_warn("C2H channel %d >= %d.\n",
				channel, sgdev->c2h_channel_max);
			return -EINVAL;
		}
		engine = &sgdev->engine_c2h[channel];
	} else {
		pr_warn("write %d, exp. 0|1.\n", write);
		return -EINVAL;
	}

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return -EINVAL;
	}

	sgdev = engine->sgdev;
	req = cb->req;

	nents = req->sw_desc_cnt;
	while (nents) {
		xfer = &req->tfer[tfer_idx];
		nents -= xfer->desc_num;
		switch (xfer->state) {
		case TRANSFER_STATE_COMPLETED:
			dbg_tfr("transfer %p, %u, ep 0x%llx compl, +%lu.\n",
				xfer, xfer->len, req->ep_addr - xfer->len,
				done);

			result = xfer->res_virt;
			/* For C2H streaming use writeback results */
			if (engine->streaming &&
				engine->dir == DMA_FROM_DEVICE) {
				done += st_c2h_completed_bytes(engine, xfer);
			} else
				done += xfer->len;

			rv = 0;
			break;
		case TRANSFER_STATE_FAILED:
			pr_info("xfer 0x%p,%u, failed, ep 0x%llx.\n",
				xfer, xfer->len, req->ep_addr - xfer->len);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -EIO;
			break;
		default:
			/* transfer can still be in-flight */
			pr_info("xfer 0x%p,%u, s 0x%x timed out, ep 0x%llx.\n",
				xfer, xfer->len, xfer->state, req->ep_addr);
			engine_status_read(engine, 0, 1);
			engine_status_dump(engine);
			transfer_abort(engine, xfer);

			sgdma_engine_stop(engine);

#ifdef __LIBSGDMA_DEBUG__
			transfer_dump(xfer);
			sgt_dump(sgt);
#endif
			rv = -ERESTARTSYS;
			break;
		}

		transfer_destroy(sgdev, xfer);
		engine->desc_used -= xfer->desc_num;

		tfer_idx++;

		if (rv < 0)
			goto unmap_sgl;
	} /* while (sg) */

unmap_sgl:
	if (!dma_mapped && sgt->nents) {
		dma_unmap_sg(&sgdev->pdev->dev, sgt->sgl, sgt->orig_nents, dir);
		sgt->nents = 0;
	}

	if (req)
		sgdma_request_free(req);

	return done;
}

/*
 * anlogic_isr() - Interrupt handler for legacy and msi interrupt
 *
 * @dev_id pointer to anlogic_dev
 */
static irqreturn_t anlogic_isr(int irq, void *dev_id)
{
	u32 ch_irq;
	u32 user_irq;
	u32 mask;
	struct anlogic_dev *sgdev;
	struct interrupt_regs *irq_regs;

	if (!dev_id) {
		pr_err("Invalid dev_id on irq line %d\n", irq);
		return -IRQ_NONE;
	}
	sgdev = (struct anlogic_dev *)dev_id;

	if (!sgdev) {
		WARN_ON(!sgdev);
		dbg_irq("%s(irq=%d) sgdev=%p ??\n", __func__, irq, sgdev);
		return IRQ_NONE;
	}

	irq_regs = (struct interrupt_regs *)(sgdev->bar[sgdev->config_bar_idx] +
						 SGDMA_OFS_INT_CTRL);


	/* read channel interrupt requests */
	ch_irq = read_register(&irq_regs->channel_int_request);
	pr_info("ch_irq = 0x%08x\n", ch_irq);

	/*
	 * disable all interrupts that fired; these are re-enabled individually
	 * after the causing module has been fully serviced.
	 */

	if (ch_irq)
		channel_interrupts_disable(sgdev, ch_irq);

	/* read user interrupts - this read also flushes the above write */
	user_irq = read_register(&irq_regs->user_int_request);
	pr_info("user_irq = 0x%08x\n", user_irq);

	if (user_irq) {
		int user = 0;
		u32 mask = 1;
		int max = sgdev->user_max;

		for (; user < max && user_irq; user++, mask <<= 1) {
			if (user_irq & mask) {
				user_irq &= ~mask;
				user_irq_service(irq, &sgdev->user_irq[user]);
			}
		}
	}

	mask = ch_irq & sgdev->mask_irq_h2c;
	if (mask) {
		int channel = 0;
		int max = sgdev->h2c_channel_max;

		// iterate over H2C (PCIe read)
		for (channel = 0; channel < max && mask; channel++) {
			struct anlogic_dma_engine *engine = &sgdev->engine_h2c[channel];

			// engine present and its interrupt fired?
			if ((engine->irq_bitmask & mask) &&
				(engine->magic == MAGIC_ENGINE)) {
				mask &= ~engine->irq_bitmask;
				pr_info("schedule_work, %s.\n", engine->name);
				engine->irq_cnt++;
				schedule_work(&engine->work);
			}
		}
	}

	mask = ch_irq & sgdev->mask_irq_c2h;
	if (mask) {
		int channel = 0;
		int max = sgdev->c2h_channel_max;

		// iterate over C2H (PCIe write)
		for (channel = 0; channel < max && mask; channel++) {
			struct anlogic_dma_engine *engine = &sgdev->engine_c2h[channel];

			// engine present and its interrupt fired?
			if ((engine->irq_bitmask & mask) &&
				(engine->magic == MAGIC_ENGINE)) {
				mask &= ~engine->irq_bitmask;
				pr_info("schedule_work, %s.\n", engine->name);
				engine->irq_cnt++;
				schedule_work(&engine->work);
			}
		}
	}

	sgdev->irq_count++;

	return IRQ_HANDLED;
}

static inline void sgdma_device_flag_clear(struct anlogic_dev *sgdev, unsigned int f)
{
	unsigned long flags;

	spin_lock_irqsave(&sgdev->lock, flags);
	sgdev->flags &= ~f;
	spin_unlock_irqrestore(&sgdev->lock, flags);
}

static inline void sgdma_device_flag_set(struct anlogic_dev *sgdev, unsigned int f)
{
	unsigned long flags;

	spin_lock_irqsave(&sgdev->lock, flags);
	sgdev->flags |= f;
	spin_unlock_irqrestore(&sgdev->lock, flags);
}

static int set_dma_mask(struct pci_dev *pdev)
{
	if (!pdev) {
		pr_err("Invalid pdev\n");
		return -EINVAL;
	}

	/* 64-bit addressing capability for SGDMA? */
	if (!dma_set_mask(&pdev->dev, DMA_BIT_MASK(64))) {
		/* query for DMA transfer */
		/* @see Documentation/DMA-mapping.txt */
		dbg_init("dma_set_mask()\n");
		/* use 64-bit DMA */
		dbg_init("Using a 64-bit DMA mask.\n");
		/* use 32-bit DMA for descriptors */
		dma_set_coherent_mask(&pdev->dev, DMA_BIT_MASK(32));
		/* use 64-bit DMA, 32-bit for consistent */
	} else if (!dma_set_mask(&pdev->dev, DMA_BIT_MASK(32))) {
		dbg_init("Could not set 64-bit DMA mask.\n");
		dma_set_coherent_mask(&pdev->dev, DMA_BIT_MASK(32));
		/* use 32-bit DMA */
		dbg_init("Using a 32-bit DMA mask.\n");
	} else {
		dbg_init("No suitable DMA possible.\n");
		return -EINVAL;
	}

	return 0;
}

/*
 * Unmap the BAR regions that had been mapped earlier using map_bars()
 */
static void unmap_bars(struct anlogic_dev *sgdev, struct pci_dev *dev)
{
	int i;

	for (i = 0; i < SGDMA_BAR_NUM; i++) {
		/* is this BAR mapped? */
		if (sgdev->bar[i]) {
			/* unmap BAR */
			pci_iounmap(dev, sgdev->bar[i]);
			/* mark as unmapped */
			sgdev->bar[i] = NULL;
		}
	}
}

static int map_single_bar(struct anlogic_dev *sgdev, struct pci_dev *dev, int idx)
{
	resource_size_t bar_start;
	resource_size_t bar_len;
	resource_size_t map_len;

	bar_start = pci_resource_start(dev, idx);
	bar_len = pci_resource_len(dev, idx);
	map_len = bar_len;

	sgdev->bar[idx] = NULL;

	/* do not map BARs with length 0. Note that start MAY be 0! */
	if (!bar_len) {
		pr_info("BAR #%d is not present - skipping\n", idx);
		return 0;
	}

	/* BAR size exceeds maximum desired mapping? */
	if (bar_len > INT_MAX) {
		pr_info("Limit BAR %d mapping from %llu to %d bytes\n", idx,
			(u64)bar_len, INT_MAX);
		map_len = (resource_size_t)INT_MAX;
	}
	/*
	 * map the full device memory or IO region into kernel virtual
	 * address space
	 */
	dbg_init("BAR%d: %llu bytes to be mapped.\n", idx, (u64)map_len);
	sgdev->bar[idx] = pci_iomap(dev, idx, map_len);

	if (!sgdev->bar[idx]) {
		pr_info("Could not map BAR %d.\n", idx);
		return -1;
	}

	pr_info("BAR%d at 0x%llx mapped at 0x%pK, length=%llu(/%llu)\n", idx,
		(u64)bar_start, sgdev->bar[idx], (u64)map_len, (u64)bar_len);

	return (int)map_len;
}

static int is_config_bar(struct anlogic_dev *sgdev, int idx)
{
#ifdef SGDMA_CONFIG_BAR_NUM
	return (idx == SGDMA_CONFIG_BAR_NUM);
#else
	u32 irq_id = 0;
	u32 cfg_id = 0;
	int flag = 0;
	u32 mask = 0xffff0000; /* Compare only XDMA ID's not Version number */
	struct interrupt_regs *irq_regs =
		(struct interrupt_regs *)(sgdev->bar[idx] + SGDMA_OFS_INT_CTRL);
	struct config_regs *cfg_regs =
		(struct config_regs *)(sgdev->bar[idx] + SGDMA_OFS_CONFIG);

	irq_id = read_register(&irq_regs->identifier);
	cfg_id = read_register(&cfg_regs->identifier);

	if (((irq_id & mask) == IRQ_BLOCK_ID) &&
	    ((cfg_id & mask) == CONFIG_BLOCK_ID)) {
		dbg_init("BAR %d is the SGDMA config BAR\n", idx);
		flag = 1;
	} else {
		dbg_init("BAR %d is NOT the SGDMA config BAR: 0x%x, 0x%x.\n",
			 idx, irq_id, cfg_id);
		flag = 0;
	}

	return flag;
#endif
}

static int identify_bars(struct anlogic_dev *sgdev, int *bar_id_list, int num_bars,
			 int config_bar_pos)
{
	/*
	 * The following logic identifies which BARs contain what functionality
	 * based on the position of the SGDMA config BAR and the number of BARs
	 * detected. The rules are that the user logic and bypass logic BARs
	 * are optional.  When both are present, the SGDMA config BAR will be the
	 * 2nd BAR detected (config_bar_pos = 1), with the user logic being
	 * detected first and the bypass being detected last. When one is
	 * omitted, the type of BAR present can be identified by whether the
	 * SGDMA config BAR is detected first or last.  When both are omitted,
	 * only the SGDMA config BAR is present.  This somewhat convoluted
	 * approach is used instead of relying on BAR numbers in order to work
	 * correctly with both 32-bit and 64-bit BARs.
	 */

	dbg_init("sgdev 0x%p, bars %d, config at %d.\n", sgdev, num_bars,
		 config_bar_pos);

	switch (num_bars) {
	case 1:
		/* Only one BAR present - no extra work necessary */
		break;

	case 2:
		if (config_bar_pos == 0) {
			sgdev->bypass_bar_idx = bar_id_list[1];
		} else if (config_bar_pos == 1) {
			sgdev->user_bar_idx = bar_id_list[0];
		} else {
			pr_info("2, SGDMA config BAR unexpected %d.\n",
				config_bar_pos);
		}
		break;

	case 3:
	case 4:
		if (config_bar_pos == 0) {
			/* config at first position: user bar next */
			sgdev->user_bar_idx = bar_id_list[1];
			sgdev->bypass_bar_idx = bar_id_list[num_bars - 1];
		} else if ((config_bar_pos == 1) || (config_bar_pos == 2)) {
			/* user bar at bar #0 */
			sgdev->user_bar_idx = bar_id_list[0];
			/* bypass bar at the last bar */
			sgdev->bypass_bar_idx = bar_id_list[num_bars - 1];
		} else {
			pr_info("3/4, SGDMA config BAR unexpected %d.\n",
				config_bar_pos);
		}
		break;

	default:
		/* Should not occur - warn user but safe to continue */
		pr_info("Unexpected # BARs (%d), XDMA config BAR only.\n",
			num_bars);
		break;
	}
	pr_info("%d BARs: config %d, user %d, bypass %d.\n", num_bars,
		config_bar_pos, sgdev->user_bar_idx, sgdev->bypass_bar_idx);
	return 0;
}

/* map_bars() -- map device regions into kernel virtual address space
 *
 * Map the device memory regions into kernel virtual address space after
 * verifying their sizes respect the minimum sizes needed
 */
static int map_bars(struct anlogic_dev *sgdev, struct pci_dev *dev)
{
	int rv;
	int i;
	int bar_id_list[SGDMA_BAR_NUM];
	int config_bar_pos = 0, bar_id_idx = 0;

	/* iterate through all the BARs */
	for (i = 0; i < SGDMA_BAR_NUM; i++) {
		int bar_len;

		bar_len = map_single_bar(sgdev, dev, i);
		pr_err("BAR%d len:%d\n",i,bar_len);
		if (bar_len == 0) {
			continue;
		} else if (bar_len < 0) {
			rv = -EINVAL;
			goto fail;
		}

		/* Try to identify BAR as SGDMA control BAR */
		if ((bar_len >= SGDMA_BAR_SIZE) && (sgdev->config_bar_idx < 0)) {
			if (is_config_bar(sgdev, i)) {
				sgdev->config_bar_idx = i;
				config_bar_pos = bar_id_idx;
				pr_info("config bar %d, pos %d.\n",
					sgdev->config_bar_idx, config_bar_pos);
			}
		}

		bar_id_list[bar_id_idx] = i;
		bar_id_idx++;
	}

	/* The SGDMA config BAR must always be present */
	if (sgdev->config_bar_idx < 0) {
		pr_info("Failed to detect SGDMA config BAR\n");
		rv = -EINVAL;
		goto fail;
	}

	rv = identify_bars(sgdev, bar_id_list, bar_id_idx, config_bar_pos);
	if (rv < 0) {
		pr_err("Failed to identify bars\n");
		return rv;
	}

	/* successfully mapped all required BAR regions */
	return 0;

fail:
	/* unwind; unmap any BARs that we did map */
	unmap_bars(sgdev, dev);
	return rv;
}

static int request_regions(struct anlogic_dev *sgdev, struct pci_dev *pdev)
{
	int rv;

	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	if (!pdev) {
		pr_err("Invalid pdev\n");
		return -EINVAL;
	}

	dbg_init("pci_request_regions()\n");
	rv = pci_request_regions(pdev, sgdev->mod_name);
	/* could not request all regions? */
	if (rv) {
		dbg_init("pci_request_regions() = %d, device in use?\n", rv);
		/* assume device is in use so do not disable it later */
		sgdev->regions_in_use = 1;
	} else {
		sgdev->got_regions = 1;
	}

	return rv;
}

static inline void anlogic_device_flag_set(struct anlogic_dev *sgdev, unsigned int f)
{
	unsigned long flags;

	spin_lock_irqsave(&sgdev->lock, flags);
	sgdev->flags |= f;
	spin_unlock_irqrestore(&sgdev->lock, flags);
}

static struct anlogic_dev *alloc_dev_instance(struct pci_dev *pdev)
{
	int i;
	struct anlogic_dev *sgdev;
	struct anlogic_dma_engine *engine;

	if (!pdev) {
		pr_err("Invalid pdev\n");
		return NULL;
	}

	/* allocate zeroed device book keeping structure */
	sgdev = kzalloc(sizeof(struct anlogic_dev), GFP_KERNEL);
	if (!sgdev) {
		pr_info("OOM, sgdma_dev.\n");
		return NULL;
	}
	spin_lock_init(&sgdev->lock);

	sgdev->magic = MAGIC_DEVICE;
	sgdev->config_bar_idx = -1;
	sgdev->user_bar_idx = -1;
	sgdev->bypass_bar_idx = -1;
	sgdev->irq_line = -1;

	/* create a driver to device reference */
	sgdev->pdev = pdev;
	dbg_init("sgdev = 0x%p\n", sgdev);

	/* Set up data user IRQ data structures */
	for (i = 0; i < 16; i++) {
		sgdev->user_irq[i].sgdev = sgdev;
		spin_lock_init(&sgdev->user_irq[i].events_lock);
		init_waitqueue_head(&sgdev->user_irq[i].events_wq);
		sgdev->user_irq[i].handler = NULL;
		sgdev->user_irq[i].user_idx = i; /* 0 based */
	}

	engine = sgdev->engine_h2c;
	for (i = 0; i < SGDMA_CHANNEL_NUM_MAX; i++, engine++) {
		spin_lock_init(&engine->lock);
		mutex_init(&engine->desc_lock);
		INIT_LIST_HEAD(&engine->transfer_list);
		init_waitqueue_head(&engine->shutdown_wq);
		init_waitqueue_head(&engine->sgdma_perf_wq);
	}

	engine = sgdev->engine_c2h;
	for (i = 0; i < SGDMA_CHANNEL_NUM_MAX; i++, engine++) {
		spin_lock_init(&engine->lock);
		mutex_init(&engine->desc_lock);
		INIT_LIST_HEAD(&engine->transfer_list);
		init_waitqueue_head(&engine->shutdown_wq);
		init_waitqueue_head(&engine->sgdma_perf_wq);
	}

	return sgdev;
}

#if KERNEL_VERSION(3, 5, 0) <= LINUX_VERSION_CODE
static void pci_enable_capability(struct pci_dev *pdev, int cap)
{
	pcie_capability_set_word(pdev, PCI_EXP_DEVCTL, cap);
}
#else
static void pci_enable_capability(struct pci_dev *pdev, int cap)
{
	u16 v;
	int pos;

	pos = pci_pcie_cap(pdev);
	if (pos > 0) {
		pci_read_config_word(pdev, pos + PCI_EXP_DEVCTL, &v);
		v |= cap;
		pci_write_config_word(pdev, pos + PCI_EXP_DEVCTL, v);
	}
}
#endif

static void engine_alignments(struct anlogic_dma_engine *engine)
{
	u32 w;
	u32 align_bytes;
	u32 granularity_bytes;
	u32 address_bits;

	w = read_register(&engine->regs->alignments);
	dbg_init("engine %p name %s alignments=0x%08x\n", engine, engine->name,
		 (int)w);

	align_bytes = (w & 0x00ff0000U) >> 16;
	granularity_bytes = (w & 0x0000ff00U) >> 8;
	address_bits = (w & 0x000000ffU);

	dbg_init("align_bytes = %d\n", align_bytes);
	dbg_init("granularity_bytes = %d\n", granularity_bytes);
	dbg_init("address_bits = %d\n", address_bits);

	if (w) {
		engine->addr_align = align_bytes;
		engine->len_granularity = granularity_bytes;
		engine->addr_bits = address_bits;
	} else {
		/* Some default values if alignments are unspecified */
		engine->addr_align = 1;
		engine->len_granularity = 1;
		engine->addr_bits = 64;
	}
}

static void engine_free_resource(struct anlogic_dma_engine *engine)
{
	struct anlogic_dev *sgdev = engine->sgdev;

	/* Release memory use for descriptor writebacks */
	if (engine->poll_mode_addr_virt) {
		dbg_sg("Releasing memory for descriptor writeback\n");
		dma_free_coherent(&sgdev->pdev->dev, sizeof(struct sgdma_poll_wb),
				  engine->poll_mode_addr_virt,
				  engine->poll_mode_bus);
		dbg_sg("Released memory for descriptor writeback\n");
		engine->poll_mode_addr_virt = NULL;
	}

	if (engine->desc) {
		dbg_init("device %s, engine %s pre-alloc desc 0x%p,0x%llx.\n",
			 dev_name(&sgdev->pdev->dev), engine->name, engine->desc,
			 engine->desc_bus);
		dma_free_coherent(&sgdev->pdev->dev,
				  engine->desc_max * sizeof(struct sgdma_desc),
				  engine->desc, engine->desc_bus);
		engine->desc = NULL;
	}

	if (engine->cyclic_result) {
		dma_free_coherent(
			&sgdev->pdev->dev,
			engine->desc_max * sizeof(struct sgdma_result),
			engine->cyclic_result, engine->cyclic_result_bus);
		engine->cyclic_result = NULL;
	}
}

static int engine_alloc_resource(struct anlogic_dma_engine *engine)
{
	struct anlogic_dev *sgdev = engine->sgdev;

	engine->desc = dma_alloc_coherent(&sgdev->pdev->dev,
					  engine->desc_max *
						  sizeof(struct sgdma_desc),
					  &engine->desc_bus, GFP_KERNEL);
	if (!engine->desc) {
		pr_warn("dev %s, %s pre-alloc desc OOM.\n",
			dev_name(&sgdev->pdev->dev), engine->name);
		goto err_out;
	}

	if (poll_mode) {
		engine->poll_mode_addr_virt =
			dma_alloc_coherent(&sgdev->pdev->dev,
					   sizeof(struct sgdma_poll_wb),
					   &engine->poll_mode_bus, GFP_KERNEL);
		if (!engine->poll_mode_addr_virt) {
			pr_warn("%s, %s poll pre-alloc writeback OOM.\n",
				dev_name(&sgdev->pdev->dev), engine->name);
			goto err_out;
		}
	}

	if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
		engine->cyclic_result = dma_alloc_coherent(
			&sgdev->pdev->dev,
			engine->desc_max * sizeof(struct sgdma_result),
			&engine->cyclic_result_bus, GFP_KERNEL);

		if (!engine->cyclic_result) {
			pr_warn("%s, %s pre-alloc result OOM.\n",
				dev_name(&sgdev->pdev->dev), engine->name);
			goto err_out;
		}
	}

	return 0;

err_out:
	engine_free_resource(engine);
	return -ENOMEM;
}

/**
 *engine_cyclic_stop() - stop a cyclic transfer running on an SG DMA engine
 *
 *engine->lock must be taken
 */
struct sgdma_transfer *engine_cyclic_stop(struct anlogic_dma_engine *engine)
{
	int rv;
	struct sgdma_transfer *transfer = 0;
	int size = engine->sgdma_perf->transfer_size;

	/* transfers on queue? */
	if (!list_empty(&engine->transfer_list)) {
		/* pick first transfer on the queue (was submitted to engine) */
		transfer = list_entry(engine->transfer_list.next,
					  struct sgdma_transfer, entry);
		if (!transfer) {
			pr_err("(engine=%s) has void transfer in queue.\n",
				   engine->name);
			return NULL;
		}
		rv = sgdma_engine_stop(engine);
		if (rv < 0) {
			pr_err("Failed to stop engine\n");
			return NULL;
		}
		engine->running = 0;

		if (transfer->cyclic) {
			if (engine->sgdma_perf)
				dbg_perf("Stopping perf transfer on %s\n",
					 engine->name);
			else
				dbg_perf("Stopping cyclic transfer on %s\n",
					 engine->name);
			/* free up the buffer allocated for perf run */
			if (engine->perf_buf_virt)
				dma_free_coherent(&engine->sgdev->pdev->dev, size,
						  engine->perf_buf_virt,
						  engine->perf_buf_bus);
			engine->perf_buf_virt = NULL;
			list_del(&transfer->entry);
		} else {
			dbg_sg("(engine=%p) running transfer is not cyclic\n",
				   engine);
		}
	} else {
		dbg_sg("(engine=%p) found not running transfer.\n", engine);
	}
	return transfer;
}
EXPORT_SYMBOL_GPL(engine_cyclic_stop);

static int engine_writeback_setup(struct anlogic_dma_engine *engine)
{
	u32 w;
	struct anlogic_dev *sgdev;
	struct sgdma_poll_wb *writeback;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	sgdev = engine->sgdev;
	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	/*
	 * better to allocate one page for the whole device during probe()
	 * and set per-engine offsets here
	 */
	writeback = (struct sgdma_poll_wb *)engine->poll_mode_addr_virt;
	writeback->completed_desc_count = 0;

	dbg_init("Setting writeback location to 0x%llx for engine %p",
		 engine->poll_mode_bus, engine);
	w = cpu_to_le32(PCI_DMA_L(engine->poll_mode_bus));
	write_register(w, &engine->regs->poll_mode_wb_lo,
			   (unsigned long)(&engine->regs->poll_mode_wb_lo) -
				   (unsigned long)(engine->regs));
	w = cpu_to_le32(PCI_DMA_H(engine->poll_mode_bus));
	write_register(w, &engine->regs->poll_mode_wb_hi,
			   (unsigned long)(&engine->regs->poll_mode_wb_hi) -
				   (unsigned long)(engine->regs));

	return 0;
}

/* engine_create() - Create an SG DMA engine bookkeeping data structure
 *
 * An SG DMA engine consists of the resources for a single-direction transfer
 * queue; the SG DMA hardware, the software queue and interrupt handling.
 *
 * @dev Pointer to pci_dev
 * @offset byte address offset in BAR[sgdev->config_bar_idx] resource for the
 * SG DMA * controller registers.
 * @dir: DMA_TO/FROM_DEVICE
 * @streaming Whether the engine is attached to AXI ST (rather than MM)
 */
static int engine_init_regs(struct anlogic_dma_engine *engine)
{
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_common_regs *reg = (struct sgdma_common_regs *)
					(sgdev->bar[sgdev->config_bar_idx] +
					(0x6 * TARGET_SPACING));
	u32 reg_value;
	int rv = 0;

	write_register(SGDMA_CTRL_NON_INCR_ADDR, &engine->regs->control_w1c,
			   (unsigned long)(&engine->regs->control_w1c) -
				   (unsigned long)(engine->regs));

	engine_alignments(engine);

	/* Configure error interrupts by default */
	reg_value = SGDMA_CTRL_IE_DESC_ALIGN_MISMATCH;
	reg_value |= SGDMA_CTRL_IE_MAGIC_STOPPED;
	reg_value |= SGDMA_CTRL_IE_READ_ERROR;
	reg_value |= SGDMA_CTRL_IE_DESC_ERROR;

	/* if using polled mode, configure writeback address */
	if (poll_mode) {
		rv = engine_writeback_setup(engine);
		if (rv) {
			dbg_init("%s descr writeback setup failed.\n",
				 engine->name);
			goto fail_wb;
		}
#if HARDWARE_PATCH
		reg_value |= SGDMA_CTRL_IE_DESC_COMPLETED;
#endif
	} else {
		/* enable the relevant completion interrupts */
		reg_value |= SGDMA_CTRL_IE_DESC_STOPPED;
		reg_value |= SGDMA_CTRL_IE_DESC_COMPLETED;
	}

	/* Apply engine configurations */
	write_register(reg_value, &engine->regs->interrupt_enable_mask,
			   (unsigned long)(&engine->regs->interrupt_enable_mask) -
				   (unsigned long)(engine->regs));

	engine->interrupt_enable_mask_value = reg_value;

	if (engine->dir == DMA_FROM_DEVICE) {
		reg_value = (0x1 << engine->channel) << 16;
		if (st_c2h_credit_enabled(engine)) {
			/* only enable credit mode for AXI-ST C2H */
			pr_info("%s enable credit mode.\n", engine->name);
			write_register(reg_value, &reg->credit_mode_enable_w1s,
				(unsigned long)(&reg->credit_mode_enable_w1s) -
					(unsigned long)(reg));
		} else {
			/* disable credit mode */
			write_register(reg_value, &reg->credit_mode_enable_w1c,
				(unsigned long)(&reg->credit_mode_enable_w1c) -
					(unsigned long)(reg));
		}
	} else {
		reg_value = (0x1 << engine->channel);
		/* disable credit mode */
		write_register(reg_value, &reg->credit_mode_enable_w1c,
			(unsigned long)(&reg->credit_mode_enable_w1c) -
				(unsigned long)(reg));
	}

	return 0;

fail_wb:
	return rv;
}

static int engine_init(struct anlogic_dma_engine *engine, struct anlogic_dev *sgdev,
			   int offset, enum dma_data_direction dir, int channel)
{
	int rv;
	u32 val;

	dbg_init("channel %d, offset 0x%x, dir %d.\n", channel, offset, dir);

	/* set magic */
	engine->magic = MAGIC_ENGINE;

	engine->channel = channel;

	/* engine interrupt request bit */
	engine->irq_bitmask = (1 << SGDMA_ENG_IRQ_NUM) - 1;
	engine->irq_bitmask <<= (sgdev->engines_num * SGDMA_ENG_IRQ_NUM);
	engine->bypass_offset = sgdev->engines_num * BYPASS_MODE_SPACING;

	/* parent */
	engine->sgdev = sgdev;
	/* register address */
	engine->regs = (sgdev->bar[sgdev->config_bar_idx] + offset);
	engine->sgdma_regs = sgdev->bar[sgdev->config_bar_idx] + offset +
				 SGDMA_OFFSET_FROM_CHANNEL;
	val = read_register(&engine->regs->identifier);
	if (val & 0x8000U)
		engine->streaming = 1;

	/* remember SG DMA direction */
	engine->dir = dir;
	sprintf(engine->name, "%d-%s%d-%s", sgdev->idx,
		(dir == DMA_TO_DEVICE) ? "H2C" : "C2H", channel,
		engine->streaming ? "ST" : "MM");

	/* initialize the deferred work for transfer completion */
	INIT_WORK(&engine->work, engine_service_work);

	if (st_c2h_credit_enabled(engine))
			engine->desc_max = SGDMA_ENGINE_CREDIT_XFER_MAX_DESC;
	else
			engine->desc_max = SGDMA_ENGINE_XFER_MAX_DESC;

	dbg_init("engine %p name %s irq_bitmask=0x%08x\n", engine, engine->name,
		 (int)engine->irq_bitmask);
	if (engine->streaming && engine->dir == DMA_FROM_DEVICE)
		pr_info("%s init: st_c2h credit=%u force_wb=%u desc_max=%u.\n",
			engine->name, enable_st_c2h_credit, force_st_c2h_wb,
			engine->desc_max);

	if (dir == DMA_TO_DEVICE)
		sgdev->mask_irq_h2c |= engine->irq_bitmask;
	else
		sgdev->mask_irq_c2h |= engine->irq_bitmask;
	sgdev->engines_num++;

#if DESC_BYPASS
	if (val & 0x1000U) {
		engine->is_desc_bypass = 1;
		engine->desc_bypass_reg = sgdma_desc_bypass_reg(sgdev, channel, (dir == DMA_TO_DEVICE));
		engine->desc_max = DESCBYPASS_DESC_MAX;
		dbg_init("engine %p name %s is desc bypass, desc_max %u, register 0x%lx\n",
			 engine, engine->name, engine->desc_max, (ulong)engine->desc_bypass_reg);
	}
#endif

	rv = engine_alloc_resource(engine);
	if (rv)
		return rv;

	rv = engine_init_regs(engine);
	if (rv)
		return rv;

	if (poll_mode)
		sgdma_thread_add_work(engine);

	return 0;
}

static int get_engine_channel_id(struct engine_regs *regs)
{
	int value;

	if (!regs) {
		pr_err("Invalid engine registers\n");
		return -EINVAL;
	}

	value = read_register(&regs->identifier);

	return (value & 0x00000f00U) >> 8;
}

static int get_engine_id(struct engine_regs *regs)
{
	int value;

	if (!regs) {
		pr_err("Invalid engine registers\n");
		return -EINVAL;
	}

	value = read_register(&regs->identifier);
	return (value & 0xffff0000U) >> 16;
}

static int probe_for_engine(struct anlogic_dev *sgdev, enum dma_data_direction dir,
				int channel)
{
	struct engine_regs *regs;
	int offset = channel * CHANNEL_SPACING;
	u32 engine_id_expected;
	u32 engine_id;
	u32 channel_id;
	struct anlogic_dma_engine *engine;
	int rv;

	/* register offset for the engine */
	/* read channels at 0x0000, write channels at 0x1000,
	 * channels at 0x100 interval
	 */
	if (dir == DMA_TO_DEVICE) {
		engine_id_expected = SGDMA_ID_H2C;
		engine = &sgdev->engine_h2c[channel];
	} else {
		offset += H2C_CHANNEL_OFFSET;
		engine_id_expected = SGDMA_ID_C2H;
		engine = &sgdev->engine_c2h[channel];
	}

	regs = sgdev->bar[sgdev->config_bar_idx] + offset;
	engine_id = get_engine_id(regs);
	channel_id = get_engine_channel_id(regs);

	if ((engine_id != engine_id_expected) || (channel_id != channel)) {
		dbg_init(
			"%s %d engine, reg off 0x%x, id mismatch 0x%x,0x%x,exp 0x%x,0x%x, SKIP.\n",
			dir == DMA_TO_DEVICE ? "H2C" : "C2H", channel, offset,
			engine_id, channel_id, engine_id_expected,
			channel_id != channel);
		return -EINVAL;
	}

	dbg_init("found AXI %s %d engine, reg. off 0x%x.\n",
		 dir == DMA_TO_DEVICE ? "H2C" : "C2H", channel, offset);

	/* allocate and initialize engine */
	rv = engine_init(engine, sgdev, offset, dir, channel);
	if (rv != 0) {
		pr_info("failed to create AXI %s %d engine.\n",
			dir == DMA_TO_DEVICE ? "H2C" : "C2H", channel);
		return rv;
	}

	return 0;
}

static int engine_destroy(struct anlogic_dev *sgdev, struct anlogic_dma_engine *engine)
{
	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	dbg_sg("Shutting down engine %s%d", engine->name, engine->channel);

	engine_service_shutdown(engine);

	/* Disable interrupts to stop processing new events during shutdown */
	write_register(0x0, &engine->regs->interrupt_enable_mask,
			   (unsigned long)(&engine->regs->interrupt_enable_mask) -
				   (unsigned long)(engine->regs));

	if (st_c2h_credit_enabled(engine)) {
		u32 reg_value = (0x1 << engine->channel) << 16;
		struct sgdma_common_regs *reg =
			(struct sgdma_common_regs *)(sgdev->bar[sgdev->config_bar_idx] +
					(0x6 * TARGET_SPACING));

		write_register(reg_value, &reg->credit_mode_enable_w1c,
			   (unsigned long)(&reg->credit_mode_enable_w1c) -
				   (unsigned long)(reg));
	}

	if (poll_mode)
		sgdma_thread_remove_work(engine);

	/* Release memory use for descriptor writebacks */
	engine_free_resource(engine);

	memset(engine, 0, sizeof(struct anlogic_dma_engine));
	/* Decrement the number of engines available */
	sgdev->engines_num--;

	return 0;
}

static void remove_engines(struct anlogic_dev *sgdev)
{
	struct anlogic_dma_engine *engine;
	int i;
	int rv;

	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return;
	}

	/* iterate over channels */
	for (i = 0; i < sgdev->h2c_channel_max; i++) {
		engine = &sgdev->engine_h2c[i];
		if (engine->magic == MAGIC_ENGINE) {
			dbg_sg("Remove %s, %d", engine->name, i);
			rv = engine_destroy(sgdev, engine);
			if (rv < 0)
				pr_err("Failed to destroy H2C engine %d\n", i);
			dbg_sg("%s, %d removed", engine->name, i);
		}
	}

	for (i = 0; i < sgdev->c2h_channel_max; i++) {
		engine = &sgdev->engine_c2h[i];
		if (engine->magic == MAGIC_ENGINE) {
			dbg_sg("Remove %s, %d", engine->name, i);
			rv = engine_destroy(sgdev, engine);
			if (rv < 0)
				pr_err("Failed to destroy C2H engine %d\n", i);
			dbg_sg("%s, %d removed", engine->name, i);
		}
	}
}

static int probe_engines(struct anlogic_dev *sgdev)
{
	int i;
	int rv = 0;

	if (!sgdev) {
		pr_err("Invalid sgdev\n");
		return -EINVAL;
	}

	/* iterate over channels */
	for (i = 0; i < sgdev->h2c_channel_max; i++) {
		rv = probe_for_engine(sgdev, DMA_TO_DEVICE, i);
		if (rv)
			break;
	}
	sgdev->h2c_channel_max = i;

	for (i = 0; i < sgdev->c2h_channel_max; i++) {
		rv = probe_for_engine(sgdev, DMA_FROM_DEVICE, i);
		if (rv)
			break;
	}
	sgdev->c2h_channel_max = i;

	return 0;
}

void *anlogic_device_open(const char *mname, struct pci_dev *pdev,int *user_max,int *h2c_channel_max, int *c2h_channel_max)
{
	struct anlogic_dev *sgdev = NULL;
	int rv = 0;

	pr_info("%s device %s, 0x%p.\n", mname, dev_name(&pdev->dev), pdev);

	/* allocate zeroed device book keeping structure */
	sgdev = alloc_dev_instance(pdev);
	if (!sgdev)
		return NULL;

	sgdev->mod_name = mname;
	sgdev->user_max = *user_max;
	sgdev->h2c_channel_max = *h2c_channel_max;
	sgdev->c2h_channel_max = *c2h_channel_max;

	pr_info("sgdev->h2c_channel_max%d.\n", sgdev->h2c_channel_max);
	pr_info("sgdev->c2h_channel_max%d.\n", sgdev->c2h_channel_max);

	sgdma_device_flag_set(sgdev, XDEV_FLAG_OFFLINE);

	if (sgdev->user_max == 0 || sgdev->user_max > MAX_USER_IRQ)
		sgdev->user_max = MAX_USER_IRQ;
	if (sgdev->h2c_channel_max == 0 || sgdev->h2c_channel_max > SGDMA_CHANNEL_NUM_MAX)
		sgdev->h2c_channel_max = SGDMA_CHANNEL_NUM_MAX;
	if (sgdev->c2h_channel_max == 0 || sgdev->c2h_channel_max > SGDMA_CHANNEL_NUM_MAX)
		sgdev->c2h_channel_max = SGDMA_CHANNEL_NUM_MAX;

	rv = al_dev_list_add(sgdev);
	if (rv < 0)
		goto free_dev;

	rv = pci_enable_device(pdev);
	if (rv) {
		dbg_init("pci_enable_device() failed, %d.\n", rv);
		goto err_enable;
	}

	/* keep INTx enabled */
	pci_check_intr_pend(pdev);

	/* enable relaxed ordering */
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_RELAX_EN);

	/* enable extended tag */
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_EXT_TAG);

	/* enable bus master capability */
	pci_set_master(pdev);

	rv = request_regions(sgdev, pdev);
	if (rv)
		goto err_regions;

	rv = map_bars(sgdev, pdev);
	if (rv)
		goto err_map;

	rv = set_dma_mask(pdev);
	if (rv)
		goto err_mask;

	channel_interrupts_disable(sgdev, ~0);
	user_interrupts_disable(sgdev, ~0);
	read_interrupts(sgdev);

	rv = probe_engines(sgdev);
	if (rv)
		goto err_engines;
	pr_info("%s: poll_mode=%u, probed engines h2c=%d c2h=%d.\n",
		dev_name(&pdev->dev), poll_mode,
		sgdev->h2c_channel_max, sgdev->c2h_channel_max);

	if (poll_mode) {
		pr_info("%s: poll mode active, skip MSI/MSI-X and IRQ setup.\n",
			dev_name(&pdev->dev));
	} else {
		rv = enable_msi_msix(sgdev, pdev);
		if (rv < 0) {
			pr_err("%s: enable_msi_msix failed %d.\n",
				dev_name(&pdev->dev), rv);
			goto err_enable_msix;
		}

		rv = irq_setup(sgdev, pdev);
		if (rv < 0) {
			pr_err("%s: irq_setup failed %d.\n",
				dev_name(&pdev->dev), rv);
			goto err_interrupts;
		}

		channel_interrupts_enable(sgdev, ~0);
		user_interrupts_enable(sgdev, ~0);
	}

	/* Flush writes */
	read_interrupts(sgdev);

	//store real parameter in xpdev
	*user_max = sgdev->user_max;
	*h2c_channel_max = sgdev->h2c_channel_max;
	*c2h_channel_max = sgdev->c2h_channel_max;

	sgdma_device_flag_clear(sgdev, XDEV_FLAG_OFFLINE);

	return (void *)sgdev;
err_interrupts:
	irq_teardown(sgdev);
err_enable_msix:
	disable_msi_msix(sgdev, pdev);

err_engines:
	remove_engines(sgdev);

err_mask:
	unmap_bars(sgdev, pdev);
err_map:
	if (sgdev->got_regions)
		pci_release_regions(pdev);
err_regions:
	if (!sgdev->regions_in_use)
		pci_disable_device(pdev);
err_enable:
	al_dev_list_remove(sgdev);
free_dev:
	kfree(sgdev);

	return NULL;
}

EXPORT_SYMBOL_GPL(anlogic_device_open);

void anlogic_device_close(struct pci_dev *pdev, void *dev_hndl)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;

	dbg_init("pdev 0x%p, sgdev 0x%p.\n", pdev, dev_hndl);

	if (!dev_hndl)
		return;

	dbg_sg("remove(dev = 0x%p) where pdev->dev.driver_data = 0x%p\n", pdev,
		   sgdev);
	if (sgdev->pdev != pdev) {
		dbg_sg("pci_dev(0x%lx) != pdev(0x%lx)\n",
			   (unsigned long)sgdev->pdev, (unsigned long)pdev);
	}

	channel_interrupts_disable(sgdev, ~0);
	user_interrupts_disable(sgdev, ~0);
	read_interrupts(sgdev);

	irq_teardown(sgdev);
	dbg_init("before disable_msi_msix.\n");

	disable_msi_msix(sgdev, pdev);
	dbg_init("before unmap_bars.\n");
	remove_engines(sgdev);

	unmap_bars(sgdev, pdev);

	remove_engines(sgdev);

	if (sgdev->got_regions) {
		dbg_init("pci_release_regions 0x%p.\n", pdev);
		pci_release_regions(pdev);
	}

	if (!sgdev->regions_in_use) {
		dbg_init("pci_disable_device 0x%p.\n", pdev);
		pci_disable_device(pdev);
	}

	al_dev_list_remove(sgdev);

	dbg_init("before kfree.\n");

	kfree(sgdev);
}
EXPORT_SYMBOL_GPL(anlogic_device_close);

int anlogic_user_isr_register(void *dev_hndl, unsigned int mask,
			   irq_handler_t handler, void *dev)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;
	int i;

	if (!dev_hndl)
		return -EINVAL;

	if (debug_check_dev_hndl(__func__, sgdev->pdev, dev_hndl) < 0)
		return -EINVAL;

	for (i = 0; i < sgdev->user_max && mask; i++) {
		unsigned int bit = (1 << i);

		if ((bit & mask) == 0)
			continue;

		mask &= ~bit;
		sgdev->user_irq[i].handler = handler;
		sgdev->user_irq[i].dev = dev;
	}

	return 0;
}
EXPORT_SYMBOL_GPL(anlogic_user_isr_register);

int anlogic_user_isr_enable(void *dev_hndl, unsigned int mask)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;

	if (!dev_hndl)
		return -EINVAL;

	if (debug_check_dev_hndl(__func__, sgdev->pdev, dev_hndl) < 0)
		return -EINVAL;

	sgdev->mask_irq_user |= mask;
	/* enable user interrupts */
	user_interrupts_enable(sgdev, mask);
	read_interrupts(sgdev);

	return 0;
}
EXPORT_SYMBOL_GPL(anlogic_user_isr_enable);

int anlogic_user_isr_disable(void *dev_hndl, unsigned int mask)
{
	struct anlogic_dev *sgdev = (struct anlogic_dev *)dev_hndl;

	if (!dev_hndl)
		return -EINVAL;

	if (debug_check_dev_hndl(__func__, sgdev->pdev, dev_hndl) < 0)
		return -EINVAL;

	sgdev->mask_irq_user &= ~mask;
	user_interrupts_disable(sgdev, mask);
	read_interrupts(sgdev);

	return 0;
}
EXPORT_SYMBOL_GPL(anlogic_user_isr_disable);


void anlogic_unmap_user_buf(struct sgdma_io_cb *cb, bool write)
{
	int i;

	sg_free_table(&cb->sgt);

	if (!cb->pages || !cb->pages_nr)
		return;

	for (i = 0; i < cb->pages_nr; i++) {
		if (cb->pages[i]) {
			if (!write)
				set_page_dirty_lock(cb->pages[i]);
			put_page(cb->pages[i]);
		} else
			break;
	}

	if (i != cb->pages_nr)
		pr_info("sgl pages %d/%u.\n", i, cb->pages_nr);

	kfree(cb->pages);
	cb->pages = NULL;
}

int anlogic_map_user_buf_to_sgl(struct sgdma_io_cb *cb, bool write)
{
	struct sg_table *sgt = &cb->sgt;
	unsigned long len = cb->len;
	void __user *buf = cb->buf;
	struct scatterlist *sg;
	unsigned int pages_nr = (((unsigned long)buf + len + PAGE_SIZE - 1) -
				 ((unsigned long)buf & PAGE_MASK)) >> PAGE_SHIFT;
	int i, j;
	unsigned int nents, nbytes, offset;
	unsigned long pfn0, pfn1;
	int rv;

	if (pages_nr == 0)
		return -EINVAL;

	cb->pages = kcalloc(pages_nr, sizeof(struct page *), GFP_KERNEL);
	if (!cb->pages) {
		pr_err("pages OOM.\n");
		return -ENOMEM;
	}

	rv = get_user_pages_fast((unsigned long)buf, pages_nr, 1/* write */, cb->pages);
	/* No pages were pinned */
	if (rv < 0) {
		pr_err("unable to pin down %u user pages, %d.\n", pages_nr, rv);
		goto err_out;
	}
	/* Less pages pinned than wanted */
	if (rv != pages_nr) {
		pr_err("unable to pin down all %u user pages, %d.\n", pages_nr, rv);
		cb->pages_nr = rv;
		rv = -EFAULT;
		goto err_out;
	}

	nents = 1;
	pfn0 = page_to_pfn(cb->pages[0]);
	for (i = 1; i < pages_nr; i++) {
		if (cb->pages[i - 1] == cb->pages[i]) {
			pr_err("duplicate pages, %d, %d.\n", i - 1, i);
			rv = -EFAULT;
			cb->pages_nr = pages_nr;
			goto err_out;
		}

		pfn1 = page_to_pfn(cb->pages[i]);
		if (pfn1 != pfn0 + 1)
			nents++;
		pfn0 = pfn1;
	}

	if (sg_alloc_table(sgt, nents, GFP_KERNEL)) {
		pr_err("sgl OOM.\n");
		rv = -ENOMEM;
		goto err_out;
	}

	sg = sgt->sgl;
	pfn0 = page_to_pfn(cb->pages[0]);
	offset = offset_in_page(buf);
	for (i = 0, j = 0, nbytes = 0; i < pages_nr; i++, pfn0 = pfn1, offset = 0) {
		nbytes += min_t(unsigned int, PAGE_SIZE - offset, len - nbytes);
		flush_dcache_page(cb->pages[i]);
		if ((i + 1) >= pages_nr || (pfn1 = page_to_pfn(cb->pages[i+1])) != (pfn0 + 1)) {
			sg_set_page(sg, cb->pages[j], nbytes, offset_in_page(buf));
			buf += nbytes;
			len -= nbytes;
			sg = sg_next(sg);
			j = i + 1;
			nbytes = 0;
		}
	}

	if (len) {
		pr_err("Invalid user buffer length. Cannot map to sgl\n");
		return -EINVAL;
	}
	cb->pages_nr = pages_nr;
	return 0;

err_out:
	anlogic_unmap_user_buf(cb, write);
	return rv;
}

size_t sg_copy_user(struct scatterlist *sgl, unsigned int nents, void __user *buf,
		    size_t buflen, off_t skip, bool to_buffer)
{
	unsigned int offset = 0;
	struct sg_mapping_iter miter;
	unsigned int sg_flags = SG_MITER_ATOMIC;
	int ret = 0;

	if (to_buffer)
		sg_flags |= SG_MITER_FROM_SG;
	else
		sg_flags |= SG_MITER_TO_SG;

	sg_miter_start(&miter, sgl, nents, sg_flags);

	if (!sg_miter_skip(&miter, skip))
		return 0;

	while ((offset < buflen) && sg_miter_next(&miter)) {
		unsigned int len;

		len = min(miter.length, buflen - offset);

		if (to_buffer)
			ret = copy_to_user(buf + offset, miter.addr, len);
		else
			ret = copy_from_user(miter.addr, buf + offset, len);

		if (ret) {
			pr_err("copy %s user 0x%lx failed at offset %d, len %d, buflen %lu, ret=%d\n",
			       to_buffer ? "to" : "from", (ulong)buf, offset, len, (ulong)buflen, ret);
			break;
		}

		offset += len;
	}

	sg_miter_stop(&miter);

	return offset;
}

int sg_copy_from_user(struct sg_table *sgt, const void __user *buf, size_t buflen)
{
	unsigned int len;

	len = sg_copy_user(sgt->sgl, sgt->orig_nents, (void __user *)buf, buflen, 0, false);
	if (len < buflen)
		return -EFAULT;
	return 0;
}

int sg_copy_to_user(struct sg_table *sgt, void __user *buf, size_t buflen)
{
	unsigned int len;

	len = sg_copy_user(sgt->sgl, sgt->orig_nents, buf, buflen, 0, true);
	if (len < buflen)
		return -EFAULT;
	return 0;
}

#if RANDOM_TEST
static int engine_service_rtest(struct anlogic_dma_engine *engine, int desc_writeback)
{
	struct sgdma_transfer *transfer = NULL;
	u32 desc_count = desc_writeback & WB_COUNT_MASK;
	u32 err_flag = desc_writeback & WB_ERR_MASK;
	int rv = 0;

	if (!engine) {
		pr_err("dma engine NULL\n");
		return -EINVAL;
	}

	/* Service the engine */
	if (!engine->running) {
		dbg_tfr("Engine was not running!!! Clearing status\n");
		rv = engine_status_read(engine, 1, 0);
		if (rv < 0) {
			pr_err("%s failed to read status\n", engine->name);
			return rv;
		}
		return 0;
	}

	/*
	 * If called by the ISR or polling detected an error, read and clear
	 * engine status. For polled mode descriptor completion, this read is
	 * unnecessary and is skipped to reduce latency
	 */
	if ((desc_count == 0) || (err_flag != 0)) {
		rv = engine_status_read(engine, 1, 0);
		if (rv < 0) {
			pr_err("Failed to read engine status\n");
			return rv;
		}
	} else
		engine->status = 0;

	/*
	 * engine was running but is no longer busy
	 */
	if ((engine->running && !(engine->status & SGDMA_STAT_BUSY))) {
		rv = engine_service_shutdown(engine);
		if (rv < 0) {
			pr_err("Failed to shutdown engine\n");
			return rv;
		}
	}

	/*
	 * If called from the ISR, or if an error occurred, the descriptor
	 * count will be zero.  In this scenario, read the descriptor count
	 * from HW.  In polled mode descriptor completion, this read is
	 * unnecessary and is skipped to reduce latency
	 */
	if (!desc_count)
		desc_count = read_register(&engine->regs->completed_desc_count);

	dbg_tfr("%s wb 0x%x, desc_count %u, err %u, dequeued %u.\n",
		engine->name, desc_writeback, desc_count, err_flag,
		engine->desc_dequeued);

	if (!desc_count)
		goto done;

	/* transfers on queue? */
	if (!list_empty(&engine->transfer_list)) {
		/* pick first transfer on queue (was submitted to the engine) */
		transfer = list_entry(engine->transfer_list.next,
					  struct sgdma_transfer, entry);

		dbg_tfr("head of queue transfer 0x%p has %d descriptors\n",
			transfer, (int)transfer->desc_num);

		dbg_tfr("Engine completed %d desc, %d not yet dequeued\n",
			(int)desc_count,
			(int)desc_count - engine->desc_dequeued);
	}

	if (!transfer) {
		pr_info("%s xfer empty, desc completed %u.\n", engine->name,
			desc_count);
		goto engine_resume;
	}

	/* account for already dequeued transfers during this engine run */
	desc_count -= engine->desc_dequeued;

	if (((engine->dir == DMA_FROM_DEVICE) &&
		  (engine->status & SGDMA_STAT_C2H_ERR_MASK)) ||
		 ((engine->dir == DMA_TO_DEVICE) &&
		  (engine->status & SGDMA_STAT_H2C_ERR_MASK))) {
		pr_info("engine %s, status error 0x%x.\n", engine->name,
			 engine->status);
		engine_status_dump(engine);
		engine_err_handle(engine, transfer, desc_count);
		transfer->state = TRANSFER_STATE_FAILED;
		goto transfer_del;
	}

	if (desc_count < transfer->desc_num) {
		/* Here is telled us not all desc finished on current transfer. */
		if (engine->eop_flush) {
			/* check if eop received */
			struct sgdma_result *result = transfer->res_virt;
			int i;
			int max = desc_count;

			/* Foreach stream result write back addr until find the last desc. */
			for (i = 0; i < max; i++) {
				if ((result[i].status & RX_STATUS_EOP) != 0) {
					transfer->flags |=
					XFER_FLAG_ST_C2H_EOP_RCVED;
					break;
				}
			}

			transfer->desc_cmpl = desc_count;
			if (!(transfer->flags & XFER_FLAG_ST_C2H_EOP_RCVED)) {
				goto engine_resume;
			}

			/* mark transfer as successfully completed */
			engine_service_shutdown(engine);

			transfer->state = TRANSFER_STATE_COMPLETED;

			engine->desc_dequeued += transfer->desc_cmpl;
		}
	} else {
		/* Here is telled us a transfer is finished all desc on it. */
		dbg_tfr("%s, xfer 0x%p, transfer completed, %d/%d.\n",
			 engine->name, transfer, *pdesc_completed,
			 transfer->desc_num);
		/* mark transfer as successfully completed */
		transfer->state = TRANSFER_STATE_COMPLETED;
		transfer->desc_cmpl = transfer->desc_num;
		/* add dequeued number of descriptors during this run */
		engine->desc_dequeued += transfer->desc_num;

		if (engine->eop_flush) {
			/* check if eop received */
			struct sgdma_result *result = transfer->res_virt;
			int i;
			int max = transfer->desc_cmpl;

			for (i = 0; i < max; i++) {
				if ((result[i].status & RX_STATUS_EOP) != 0)
					transfer->flags |= XFER_FLAG_ST_C2H_EOP_RCVED;
			}
		}
	}
transfer_del:
	/* remove completed transfer from list */
	list_del(engine->transfer_list.next);

	/*
	 * Complete transfer - sets transfer to NULL if an asynchronous
	 * transfer has completed
	 */
	transfer = engine_transfer_completion(engine, transfer);

engine_resume:
	/* Restart the engine following the servicing */
	rv = engine_service_resume(engine);
	if (rv < 0)
		pr_err("Failed to resume engine\n");

done:
	/* If polling detected an error, signal to the caller */
	return err_flag ? -1 : 0;
}

static enum hrtimer_restart sgdma_rtest_xfer_start_cb(struct hrtimer *timer)
{
	struct sgdma_rtest *rtest = container_of(timer, struct sgdma_rtest, timer);

	rtest->start_time = 0;
	if (sgdma_rtest_xfer_start(rtest) >= 0) {
		rtest->start_ret = 1;
		if (rtest->engine->cmplthp)
			sgdma_kthread_wakeup(rtest->engine->cmplthp);
	} else {
		pr_err("%s rtest xfer start failed\n", rtest->engine->name);
		rtest->start_ret = -1;
	}
	return HRTIMER_NORESTART;
}

static void sgdma_rtest_iodone_work(struct work_struct *work)
{
	struct sgdma_rtest *rtest = container_of(work, struct sgdma_rtest, work);
	struct sgdma_transfer *xfer = &rtest->tfer;

	if (rtest->do_start) {
		rtest->do_start = 0;
		if (!rtest->tm_inited) {
			rtest->tm_inited = 1;
			hrtimer_init(&rtest->timer, CLOCK_MONOTONIC, HRTIMER_MODE_ABS_PINNED);
		}
		rtest->timer.function = sgdma_rtest_xfer_start_cb;
		hrtimer_start(&rtest->timer, ns_to_ktime(rtest->start_time), HRTIMER_MODE_ABS_PINNED);
	} else if (rtest->done) {
		if (xfer->state == TRANSFER_STATE_COMPLETED) {
			rtest->compl_desc_num += xfer->desc_cmpl;
			rtest->test_cnt++;
		}
		rtest->done(rtest);
	}
}

static void sgdma_rtest_iodone(unsigned long cb_hndl, int err)
{
	struct sgdma_io_cb *cb = (struct sgdma_io_cb *)cb_hndl;
	struct sgdma_rtest *rtest = (struct sgdma_rtest *)cb->private;

	if (rtest->done)
		schedule_work_on(rtest->cpu, &rtest->work);
}

int engine_reset_desc(struct anlogic_dma_engine *engine)
{
	int ret = 0;
	mutex_lock(&engine->desc_lock);
	if (engine->desc_used) {
		ret = -EBUSY;
		goto out;
	}
	engine->desc_idx = 0;
	ret = 0;
out:
	mutex_unlock(&engine->desc_lock);
	return ret;
}

static struct sgdma_rtest *sgdma_rtest_alloc(u32 desc_cnt)
{
	struct sgdma_rtest *rtest;
	unsigned int size = sizeof(struct sgdma_rtest) +
				desc_cnt * sizeof(struct sgdma_rtest_sw_desc);

	rtest = kzalloc(size, GFP_KERNEL);
	if (!rtest) {
		pr_info("OOM, %u sw_desc, %u.\n", desc_cnt, size);
		return NULL;
	}

	rtest->desc_num = desc_cnt;

	return rtest;
}

void sgdma_rtest_free(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;

	mutex_lock(&engine->desc_lock);
	if (engine->rtest == rtest) {
		engine->desc_used -= xfer->desc_num;
		engine->rtest = NULL;
	}
	mutex_unlock(&engine->desc_lock);
	if (rtest->p) {
		dma_free_coherent(&sgdev->pdev->dev, rtest->len,
				  rtest->p, rtest->addr);
		rtest->p = NULL;
	}
	kfree(rtest);
}

#define RTEST_BLEN_MAX		0x10000000
#define RTEST_RANDOM_SIZE	0x40
#define RTEST_RANDOM_MASK	(RTEST_RANDOM_SIZE - 1)
static int sgdma_rtest_random_sdesc_source(struct sgdma_rtest *rtest,
										   struct sgdma_rtest *source)
{
	u64 off0 = rtest->addr - source->addr;
	u64 off1 = rtest->p - source->p;
	int i;
	int ret = 0;

	for (i = 0; i < rtest->desc_num; i++) {
		rtest->sdesc[i].addr = source->sdesc[i].addr + off0;
		rtest->sdesc[i].p = source->sdesc[i].p + off1;
		rtest->sdesc[i].len = source->sdesc[i].len;
		rtest->sdesc[i].ep_addr = source->sdesc[i].ep_addr;
		rtest->sdesc[i].control = source->sdesc[i].control;
	}

	return 0;
}
static int sgdma_rtest_random_sdesc(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	u64 ep_addr = rtest->ep_addr;
	u64 ep_len = rtest->ep_len;
	u32 desc_cnt = rtest->desc_num;
	u64 flags = rtest->flags;
	u64 blen_max, off, ep_off, buf_max, ep_max;
	u8 *random_buf, rval;
	int i;
	int ret = 0;

	random_buf = rtest->p;
	get_random_bytes(random_buf, desc_cnt);

	if ((flags & RTFLG_BUF_LEN) && (!engine->streaming) && engine->non_incr_addr) {
		pr_warn("dev %s, %s invalid random buf len setting.\n",
			dev_name(&sgdev->pdev->dev), engine->name);
		ret = -EINVAL;
		goto out;
	}

	buf_max = rtest->len / rtest->desc_num;
	ep_max = rtest->ep_len / rtest->desc_num;

	if (engine->streaming)
		blen_max = RTEST_BLEN_MAX;
	else if (engine->non_incr_addr)
		blen_max = ep_max = ep_len;
	else
		blen_max = min(ep_max, (u64)RTEST_BLEN_MAX);

	if (!blen_max) {
		pr_warn("dev %s, %s test size %llu too small.\n",
			dev_name(&sgdev->pdev->dev), engine->name, ep_len);
		ret = -EINVAL;
		goto out;
	}

	off = ep_off = 0;
	for (i = 0; i < desc_cnt; i++) {
		rval = (random_buf[i] & RTEST_RANDOM_MASK);
		if (flags & RTFLG_BUF_ADDR) {
			rtest->sdesc[i].addr = rval;
		} else {
			rtest->sdesc[i].addr = 0;
		}

		if (flags & RTFLG_BUF_LEN) {
			if (blen_max > rval)
				rtest->sdesc[i].len = blen_max - rval;
			else if (blen_max < rval)
				rtest->sdesc[i].len = rval - blen_max;
			else
				rtest->sdesc[i].len = blen_max;
		} else {
			rtest->sdesc[i].len = blen_max;
		}

		if (rtest->sdesc[i].len > blen_max)
			rtest->sdesc[i].len = blen_max;

		rtest->sdesc[i].ep_addr = 0;
		if (!engine->streaming) {
			if (!engine->non_incr_addr) {
				if (flags & RTFLG_EP_ADDR)
					rtest->sdesc[i].ep_addr += rval;
			}
			while (rtest->sdesc[i].ep_addr >= ep_max)
				rtest->sdesc[i].ep_addr -= ep_max;
			if (rtest->sdesc[i].ep_addr + rtest->sdesc[i].len > ep_max)
				rtest->sdesc[i].len = ep_max - rtest->sdesc[i].ep_addr;
			rtest->sdesc[i].ep_addr += rtest->ep_addr + ep_off;
		}

		while (rtest->sdesc[i].addr >= buf_max)
			rtest->sdesc[i].addr -= buf_max;
		if (rtest->sdesc[i].addr + rtest->sdesc[i].len > buf_max)
			rtest->sdesc[i].len = buf_max - rtest->sdesc[i].addr;
		rtest->sdesc[i].p = rtest->p + rtest->sdesc[i].addr + off;
		rtest->sdesc[i].addr += rtest->addr + off;

		off += buf_max;
		if (!engine->streaming && !engine->non_incr_addr)
			ep_off += ep_max;

		if ((flags & RTFLG_COMPLETE_F) && (rval & 0x1))
			rtest->sdesc[i].control |= SGDMA_DESC_COMPLETED;
	}
out:
	return ret;
}
struct sgdma_rtest *sgdma_rtest_create(struct anlogic_dev *sgdev, u32 channel, bool write,
					 u64 ep_addr, u64 ep_len, u32 desc_cnt, u64 flags,
					 u32 count, struct sgdma_rtest *source)
{
	struct sgdma_rtest *rtest = NULL;
	struct anlogic_dma_engine *engine = NULL;
	enum dma_data_direction dir = write ? DMA_TO_DEVICE : DMA_FROM_DEVICE;
	struct sgdma_transfer *xfer = NULL;
	int cpu;
	int i;

	if (!sgdev)
		return NULL;

	if (write) {
		if (channel >= sgdev->h2c_channel_max) {
			pr_err("H2C channel %d >= %d.\n", channel,
				sgdev->h2c_channel_max);
			return NULL;
		}
		engine = &sgdev->engine_h2c[channel];
	} else {
		if (channel >= sgdev->c2h_channel_max) {
			pr_err("C2H channel %d >= %d.\n", channel,
				sgdev->c2h_channel_max);
			return NULL;
		}
		engine = &sgdev->engine_c2h[channel];
	}

	if (!engine) {
		pr_err("dma %s engine %u NULL\n", write?"write":"read", channel);
		return NULL;
	}

	if (engine->magic != MAGIC_ENGINE) {
		pr_err("%s has invalid magic number %lx\n", engine->name,
			   engine->magic);
		return NULL;
	}

	if (desc_cnt > engine->desc_max) {
		pr_err("%s rtest too many desc: %u.\n", engine->name, desc_cnt);
		return NULL;
	}

	if (engine_reset_desc(engine) < 0) {
		pr_err("rtest reset engine %s desc fail.\n", engine->name);
		return NULL;
	}

	if (source) {
		if (write || !source->write) {
			pr_err("rtest invalid direction.\n");
			return NULL;
		}
		if (source->desc_num != desc_cnt || source->engine->streaming != engine->streaming ||
			source->ep_addr != ep_addr || source->ep_len != ep_len ||
			source->expect_cnt != count || source->engine->non_incr_addr != engine->non_incr_addr) {
			pr_err("rtest invalid source \n");
			return NULL;
		}
	}

	sgdev = engine->sgdev;
	/* check the direction */
	if (engine->dir != dir) {
		pr_info("0x%p, %s, %d, W %d, 0x%x/0x%x mismatch.\n", engine,
			engine->name, channel, write, engine->dir, dir);
		return NULL;
	}

	rtest = sgdma_rtest_alloc(desc_cnt);
	if (!rtest) {
		pr_warn("dev %s, %s alloc rtest OOM.\n",
			dev_name(&sgdev->pdev->dev), engine->name);
		return NULL;
	}
	rtest->channel = channel;
	rtest->engine = engine;
	rtest->ep_addr = ep_addr;
	rtest->ep_len = ep_len;
	rtest->flags = flags;
	rtest->expect_cnt = count;
	rtest->test_cnt = 0;
	rtest->write = write;
	INIT_WORK(&rtest->work, sgdma_rtest_iodone_work);

	i = 0;
	rtest->cpu = write ? channel : channel + sgdev->h2c_channel_max;
	while (1) {
		for_each_online_cpu(cpu) {
			if (i == rtest->cpu) {
				rtest->cpu = cpu;
				goto found_cpu;
			}
			i++;
		}

		rtest->cpu -= i;
		i = 0;
	}
found_cpu:

	rtest->len = desc_cnt * ALIGN(rtest->ep_len / desc_cnt + RTEST_RANDOM_SIZE * 2, PAGE_SIZE);
	rtest->p = dma_alloc_coherent(&sgdev->pdev->dev,
					  rtest->len,
					  &rtest->addr, GFP_KERNEL);
	if (!rtest->p) {
		pr_warn("dev %s, %s alloc rtest buf OOM.\n",
			dev_name(&sgdev->pdev->dev), engine->name);
		goto err_free_rtest;
	}

	if (!source) {
		if (sgdma_rtest_random_sdesc(rtest) < 0)
			goto err_free_rtest;
	} else {
		if (sgdma_rtest_random_sdesc_source(rtest, source) < 0)
			goto err_free_rtest;
	}

	mutex_lock(&engine->desc_lock);
	if (engine->desc_idx) {
		pr_warn("0x%p, %s, %d, rtest invalid desc_idx %d.\n", engine,
			engine->name, rtest->channel, engine->desc_idx);
		goto err_unlock;
	}

	if (engine->rtest) {
		pr_warn("0x%p, %s, %d, rtest already in use.\n", engine,
			engine->name, rtest->channel);
		goto err_unlock;
	}
	init_waitqueue_head(&rtest->tfer.wq);
	xfer = &rtest->tfer;
	xfer->dir = engine->dir;
	xfer->desc_virt = engine->desc + engine->desc_idx;
	xfer->res_virt = engine->cyclic_result + engine->desc_idx;
	xfer->desc_bus = engine->desc_bus + engine->desc_idx * sizeof(struct sgdma_desc);
	xfer->res_bus = engine->cyclic_result_bus + engine->desc_idx * sizeof(struct sgdma_result);
	xfer->desc_index = engine->desc_idx;
	xfer->desc_num = desc_cnt;
	xfer->desc_adjacent = desc_cnt;
	xfer->last_in_request = 1;
	engine->desc_idx = (engine->desc_idx + desc_cnt) % engine->desc_max;
	engine->desc_used += desc_cnt;
	engine->rtest = rtest;
	mutex_unlock(&engine->desc_lock);
	return rtest;
err_unlock:
	mutex_unlock(&engine->desc_lock);
err_free_rtest:
	sgdma_rtest_free(rtest);
	return NULL;
}

int sgdma_rtest_xfer_destroy(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;

	transfer_destroy(sgdev, xfer);
	return 0;
}

int sgdma_rtest_xfer_init(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;
	u32 desc_cnt = rtest->desc_num;
	dma_addr_t bus = 0;
	int i = 0;
	int last = 0;
	u32 control;

	xfer->state = 0;
	xfer->flags = 0;
	xfer->cyclic = 0;
	xfer->desc_cmpl = 0;
	if (engine->streaming && engine->dir == DMA_FROM_DEVICE
		&& !xfer->cyclic)
		xfer->desc_cmpl_th = 1;
	else
		xfer->desc_cmpl_th = desc_cnt;
	xfer->len = 0;
	xfer->sgt = NULL;
	xfer->cb = NULL;

	transfer_desc_init(xfer, desc_cnt);

	bus = xfer->res_bus;
	for (i = 0; i < xfer->desc_num; i++) {
		u32 next_adj = sgdma_get_next_adj(xfer->desc_num - i - 1,
						(xfer->desc_virt + i)->next_lo);
		sgdma_desc_adjacent(xfer->desc_virt + i, next_adj);
		sgdma_desc_control_set(xfer->desc_virt + i, rtest->sdesc[i].control);
		sgdma_desc_set(xfer->desc_virt + i,
					   rtest->sdesc[i].addr, rtest->sdesc[i].ep_addr,
					   rtest->sdesc[i].len, xfer->dir);
		xfer->len += rtest->sdesc[i].len;
		if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
			memset(xfer->res_virt + i, 0,
				sizeof(struct sgdma_result));
			xfer->desc_virt[i].src_addr_lo =
						cpu_to_le32(PCI_DMA_L(bus));
			xfer->desc_virt[i].src_addr_hi =
						cpu_to_le32(PCI_DMA_H(bus));
			bus += sizeof(struct sgdma_result);
			if (!xfer->cyclic)
				sgdma_desc_control_set(xfer->desc_virt + i, SGDMA_DESC_COMPLETED);
		}
	}

	last = desc_cnt - 1;
	control = SGDMA_DESC_STOPPED;
	control |= SGDMA_DESC_EOP;
	control |= SGDMA_DESC_COMPLETED;
	sgdma_desc_control_set(xfer->desc_virt + last, control);
#ifdef __LIBSGDMA_DEBUG__
	pr_info("%s rtest init transfer\n", engine->name);
	transfer_dump(xfer);
#endif
	return 0;
}

int sgdma_rtest_xfer_submit(struct sgdma_rtest *rtest,
							int (*cb)(struct sgdma_rtest *))
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;
	unsigned long flags;
	int ret = 0;


	if (xfer->desc_num == 0) {
		pr_err("%s no descriptors in the rtest transfer\n",
			   engine->name);
		return -EINVAL;
	}

	if (xfer->state != TRANSFER_STATE_NEW) {
		pr_err("%s rtest transfer not initialized\n", engine->name);
		return -EINVAL;
	}

	if (cb) {
		rtest->done = cb;
		rtest->cb.private = rtest;
		rtest->cb.io_done = sgdma_rtest_iodone;
		xfer->cb = &rtest->cb;
	} else {
		rtest->done = NULL;
		rtest->cb.private = rtest;
		rtest->cb.io_done = NULL;
	}


	spin_lock_irqsave(&engine->lock, flags);

	engine->prev_cpu = get_cpu();
	put_cpu();

	if (engine->shutdown & ENGINE_SHUTDOWN_REQUEST) {
		pr_info("engine %s offline, rtest transfer not queued.\n",
			engine->name);
		ret = -EBUSY;
		goto out;
	}

	if (!list_empty(&engine->transfer_list)) {
		pr_info("engine %s transfer list not empty, rtest transfer not submitted.\n",
			engine->name);
		ret = -EBUSY;
		goto out;
	}

	xfer->state = TRANSFER_STATE_SUBMITTED;
	list_add_tail(&xfer->entry, &engine->transfer_list);

	rtest->first_desc_lo = cpu_to_le32(PCI_DMA_L(xfer->desc_bus));
	rtest->first_desc_hi = cpu_to_le32(PCI_DMA_H(xfer->desc_bus));
	rtest->next_adj = sgdma_get_next_adj(xfer->desc_adjacent,
					 cpu_to_le32(PCI_DMA_L(xfer->desc_bus)));
out:
	spin_unlock_irqrestore(&engine->lock, flags);
	return ret;
}

int sgdma_rtest_xfer_start(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;
	unsigned long flags;
	int ret = 0;

	spin_lock_irqsave(&engine->lock, flags);
	if (xfer->state != TRANSFER_STATE_SUBMITTED) {
		pr_err("engine %s rtest transfer not submitted\n", engine->name);
		ret = -EINVAL;
		goto out;
	}

	if (engine->running) {
		pr_info("engine %s rtest is in running\n",
			engine->name);
		ret = -EINVAL;
		goto out;
	}

	if (list_empty(&engine->transfer_list)) {
		pr_info("engine %s rtest transfer not submitted.\n",
			engine->name);
		ret = -EINVAL;
		goto out;
	}

	if (!rtest->start_time)
		rtest->start_time = ktime_to_ns(ktime_get());
	engine->shutdown = ENGINE_SHUTDOWN_NONE;
	engine->desc_dequeued = 0;
	if (st_c2h_credit_enabled(engine))
		write_register(engine->desc_used,
					&engine->sgdma_regs->credits,
				(unsigned long)(&engine->sgdma_regs->credits) -
					(unsigned long)(engine->sgdma_regs));
	write_register(rtest->first_desc_lo, &engine->sgdma_regs->first_desc_lo,
			   (unsigned long)(&engine->sgdma_regs->first_desc_lo) -
				   (unsigned long)(engine->sgdma_regs));
	write_register(rtest->first_desc_hi, &engine->sgdma_regs->first_desc_hi,
			   (unsigned long)(&engine->sgdma_regs->first_desc_hi) -
				   (unsigned long)(engine->sgdma_regs));
	write_register(
		rtest->next_adj, &engine->sgdma_regs->first_desc_adjacent,
		(unsigned long)(&engine->sgdma_regs->first_desc_adjacent) -
			(unsigned long)(engine->sgdma_regs));
#ifdef HAS_MMIOWB
	mmiowb();
#endif
	engine_start_mode_config(engine);
	engine_status_read(engine, 0, 0);
	engine->running = 1;
out:
	spin_unlock_irqrestore(&engine->lock, flags);
	return ret;
}

int sgdma_rtest_xfer_start_mult(struct sgdma_rtest **rtest, int count)
{
	int i;
	int ret = 0;
	u64 start_time = ktime_to_ns(ktime_add_ms(ktime_get(), 10));

	for (i = 0; i < count; i++) {
		rtest[i]->start_ret = 0;
		rtest[i]->start_time = start_time;
		rtest[i]->do_start = 1;
		schedule_work_on(rtest[i]->cpu, &rtest[i]->work);
	}

	while (1) {
		msleep(10);
		ret = 0;
		for (i = 0; i < count; i++) {
			if (!rtest[i]->start_ret)
				break;

			if (rtest[i]->start_ret > 0)
				ret++;
		}
		if (i == count)
			break;
	}
	return ret;
}

int sgdma_rtest_xfer_cancel(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;
	struct sgdma_transfer *transfer;
	unsigned long flags;
	int ret = 0;

	spin_lock_irqsave(&engine->lock, flags);
	if (xfer->state != TRANSFER_STATE_SUBMITTED) {
		ret = 1;
		goto out;
	}

	transfer = list_first_entry(&engine->transfer_list,
					  struct sgdma_transfer, entry);
	if (transfer == xfer && engine->running)
		sgdma_engine_stop(engine);

	if (!list_empty(&engine->transfer_list))
		list_del(&xfer->entry);
	else
		pr_warn("cancel engine %s rtest transfer empty.\n", engine->name);

	xfer->state = TRANSFER_STATE_ABORTED;
	xfer->cb = NULL;
out:
	spin_unlock_irqrestore(&engine->lock, flags);
	return ret;
}
#endif
