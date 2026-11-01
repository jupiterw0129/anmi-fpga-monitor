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

#define pr_fmt(fmt)     KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/types.h>
#include "anlogic_pci_lib.h"
#include "anlogic_desc_bypass.h"

#define DESCBYPASS_DESCCTRL_CTL_SHIFT		0
#define DESCBYPASS_DESCCTRL_CTL_MASK		0x000000FFUL
#define DESCBYPASS_DESCCTRL_IDX_SHIFT		16
#define DESCBYPASS_DESCCTRL_IDX_MASK		0xFFFF0000UL

#define DESCBYPASS_CONTROL_RUN		0x00000001
#define DESCBYPASS_CONTROL_LOOP		0x00000002

#define MKFIELD(val,field) \
	(((val) << DESCBYPASS_##field##_SHIFT) & DESCBYPASS_##field##_MASK)

struct desc_bypass_reg_map {
    uint32_t   desc_ctrl;
    uint32_t   dst_hi;
    uint32_t   dst_lo;
    uint32_t   src_hi;
    uint32_t   src_lo;
    uint32_t   len;
    uint32_t   rsv0;
    uint32_t   control;
} __packed;

#define descbypass_reg(eng, reg)	\
	((struct desc_bypass_reg_map *)eng->desc_bypass_reg)->reg

#define descbypass_write_reg(eng, reg, val)	\
	write_register(val, (void __iomem *)&descbypass_reg(eng, reg), \
		(((unsigned long)&descbypass_reg(eng, reg)) - \
		((unsigned long)eng->desc_bypass_reg)))

#define descbypass_read_reg(eng, reg) \
	read_register((void __iomem *)&descbypass_reg(eng, reg))

void *sgdma_desc_bypass_reg(struct anlogic_dev *sgdev, int channel, int write)
{
	return (sgdev->bar[sgdev->user_bar_idx] + (channel * 0x100) \
		+ (write ? 0x0 : (1UL << 12)));
}

int sgdma_desc_bypass_init(struct anlogic_dma_engine *engine, struct sgdma_transfer *xfer)
{
	struct sgdma_desc *desc = xfer->desc_virt;
	int num = xfer->desc_num;
	int i;

	for (i = 0; i < num; i++) {
		descbypass_write_reg(engine, desc_ctrl,
			MKFIELD(i, DESCCTRL_IDX) |
			MKFIELD(le32_to_cpu(desc[i].control), DESCCTRL_CTL));
		descbypass_write_reg(engine, dst_hi, le32_to_cpu(desc[i].dst_addr_hi));
		descbypass_write_reg(engine, dst_lo, le32_to_cpu(desc[i].dst_addr_lo));
		descbypass_write_reg(engine, src_hi, le32_to_cpu(desc[i].src_addr_hi));
		descbypass_write_reg(engine, src_lo, le32_to_cpu(desc[i].src_addr_lo));
		descbypass_write_reg(engine, len, le32_to_cpu(desc[i].bytes));
	}
	return 0;
}

int sgdma_desc_bypass_start(struct anlogic_dma_engine *engine)
{
	u32 val = descbypass_read_reg(engine, control);
	descbypass_write_reg(engine, control, val & ~DESCBYPASS_CONTROL_RUN);
	descbypass_write_reg(engine, control, val | DESCBYPASS_CONTROL_RUN);
	return 0;
}

int sgdma_desc_bypass_stop(struct anlogic_dma_engine *engine)
{
	u32 val = descbypass_read_reg(engine, control);
	descbypass_write_reg(engine, control, val & ~DESCBYPASS_CONTROL_RUN);
	return 0;
}
