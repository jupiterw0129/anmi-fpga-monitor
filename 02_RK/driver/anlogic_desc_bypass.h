/*
 * This file is part of the Anlogic DMA IP Core driver for Linux
 *
 * Copyright (c) 2016-present,  Anlogic, Inc.
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

#ifndef _ANLOGIC_DESCBYPASS_H_
#define _ANLOGIC_DESCBYPASS_H_

#define DESCBYPASS_DESC_MAX	(0x800)

void *sgdma_desc_bypass_reg(struct anlogic_dev *sgdev, int channel, int write);
int sgdma_desc_bypass_init(struct anlogic_dma_engine *engine, struct sgdma_transfer *xfer);
int sgdma_desc_bypass_start(struct anlogic_dma_engine *engine);
int sgdma_desc_bypass_stop(struct anlogic_dma_engine *engine);

#endif
