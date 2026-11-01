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

#include <linux/init.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kobject.h>
#include <linux/slab.h>
#include <linux/device.h>
#include <linux/platform_device.h>

#define OPTPARSE_IMPLEMENTATION
#define OPTPARSE_API static
#include "optparse.h"

#include "anlogic_dbg.h"
#include "anlogic_pci_lib.h"
#include "anlogic_pci_drv.h"
#include "anlogic_pci_dbg.h"
#include "anlogic_pci_test.h"
#include "anlogic_ring.h"
#include "anlogic_thread.h"

#define AL_DBG_VERSION          "v1.0"
#define AL_DBG_COPYRIGHT_YEARS  "2022"
#define AL_DBG_NAME             "Anlogic Driver Debuger"

#define optget_args(options, argc, argv, arg_max) \
    do { \
        char *last; \
        argv[argc++] = options->optarg; \
        while (argc < arg_max && (argv[argc++] = optparse_arg(options))); \
        argc--; \
        last = argv[argc - 1]; \
        last[strlen(last) - 1] = '\0'; \
    } while(0)

#define AL_GET_DMA_ENGINE(dbgattr, engine, mode, ch) \
    do { \
        engine = al_pci_get_engine(dbgattr, mode, ch); \
        if (engine == NULL) { \
            pr_err("Engine %s-%d is not ready.\n", ((mode) == c2h) ? "C2H" : "H2C", ch); \
            return -ENXIO; \
        } \
    } while(0)

struct al_pci_dbg {
    struct optparse options;
    struct anlogic_dma_engine *engine;
    int mode;
    int ch;
};

extern void __engine_status_dump(struct anlogic_dma_engine *engine);

extern int engine_reg_dump(struct anlogic_dma_engine *engine);

extern void dump_desc(struct sgdma_desc *desc_virt);

extern void transfer_dump(struct sgdma_transfer *transfer);

extern void sgt_dump(struct sg_table *sgt);

extern void sgdma_request_cb_dump(struct sgdma_request_cb *req);

static void engine_transfer_list_dump(struct anlogic_dma_engine *engine)
{
    struct sgdma_transfer *transfer;
    unsigned long flags;

    if (engine == NULL) {
        pr_info("Invalid engine.\n");
        return;
    }

    spin_lock_irqsave(&engine->lock, flags);

    if (list_empty(&engine->transfer_list)) {
        pr_info("Engine %s current transfer list is empty.\n", engine->name);
        spin_unlock_irqrestore(&engine->lock, flags);
        return;
    }

    pr_info("Engine %s current transfer list:\n", engine->name);

    list_for_each_entry(transfer, &engine->transfer_list, entry) {
        pr_info("Tansfer (%p):\n", transfer);
        transfer_dump(transfer);
    }

    spin_unlock_irqrestore(&engine->lock, flags);
}

static void engine_info_dump(struct anlogic_dma_engine *engine)
{
    struct sgdma_transfer *transfer;
    unsigned long flags;

    if (engine == NULL) {
        pr_info("Invalid engine.\n");
        return;
    }

    pr_info("------------------------------------------\n");
    pr_info("name:                   %-20s\n", engine->name);
    pr_info("magic:                  0x%-20lx\n", engine->magic);
    pr_info("version:                0x%-20x\n", engine->version);
    pr_info("channel:                %-20d\n", engine->channel);
    pr_info("dir:                    %-20s\n", (engine->dir == DMA_FROM_DEVICE) ? "C2H" : "H2C");
    pr_info("running:                %-20s\n", (engine->running == 1) ? "running" : "stop");
    pr_info("streaming:              %-20s\n", (engine->streaming == 1) ? "true" : "false");
    pr_info("addr_align:             %-20d\n", engine->addr_align);
    pr_info("desc_dequeued:          %-20d\n", engine->desc_dequeued);
    pr_info("desc_max:               %-20d\n", engine->desc_max);
    pr_info("eop_flush:              %-20d\n", engine->eop_flush);
    pr_info("cyclic_result:          0x%-20pK\n", engine->cyclic_result);
    pr_info("cyclic_result_bus:      0x%-20llx\n", engine->cyclic_result_bus);
    pr_info("cyclic_req:             0x%-20pK\n", engine->cyclic_req);
    pr_info("rx_tail:                %-20d\n", engine->rx_tail);
    pr_info("rx_head:                %-20d\n", engine->rx_head);
    pr_info("rx_overrun:             %-20d\n", engine->rx_overrun);
    pr_info("poll_mode_addr_virt:    0x%-20pK\n", engine->poll_mode_addr_virt);
    pr_info("poll_mode_bus:          0x%-20llx\n", engine->poll_mode_bus);
    pr_info("desc:                   0x%-20pK\n", engine->desc);
    pr_info("desc_bus:               0x%-20llx\n", engine->desc_bus);
    pr_info("desc_idx:               %-20d\n", engine->desc_idx);
    pr_info("desc_used:              %-20d\n", engine->desc_used);
    pr_info("cmplthp:                0x%-20pK\n", engine->cmplthp);
    pr_info("cmplthp name:           %-20s\n", engine->cmplthp ? engine->cmplthp->name : "null");
    pr_info("------------------------------------------\n");
}

static struct anlogic_dma_engine *al_pci_get_engine(struct al_dbg_attr *dbg_attr, int mode, int ch)
{
    struct anlogic_dev *sgdev = ((struct anlogic_pci_dev *)dev_get_drvdata(dbg_attr->dev)) -> sgdev;

    if (ch >= SGDMA_CHANNEL_NUM_MAX || ch < 0 || !sgdev) {
        return NULL;
    }

    return (mode == c2h)? &sgdev->engine_c2h[ch] : &sgdev->engine_h2c[ch];
}

static const struct optparse_long longopts[] = {
    /* Display usage help */
    { "help", 'h', OPTPARSE_NONE },

    /* Engine related options */
    { "dump",    'd', OPTPARSE_REQUIRED },
    { "mode",    'm', OPTPARSE_REQUIRED },
    { "channel", 'c', OPTPARSE_REQUIRED },
    { "run",     'r', OPTPARSE_NONE },
    { "stop",    's', OPTPARSE_NONE },

    /* Transfer related options */
    { "build", 'b', OPTPARSE_REQUIRED },

    /* Test case related options */
    { "test", 't', OPTPARSE_REQUIRED },

    {0},
};

static const char *option_help[] = {
    ['h'] = "Display this help",
    ['m'] = "Set dma engine mode, 0 - c2h, 1 - h2c",
    ['c'] = "Set dma engine channel, 0 ~ 3",
    ['r'] = "Start dma engine transfer.",
    ['s'] = "Stop dma engine transfer.",
    ['b'] = "Build a new transfer.\n\t\t"
            "Example: echo -b [ring | list] [addr] > /proc/al_dbger",
    ['t'] = "Exec a test case.\n\t\t"
            "Example: echo -t [list] / [index] / [all] > /proc/al_dbger",
    ['d'] = "Dump dma engine info.\n\t\t"
            "Example: echo -d [engine | reg | sgreg | tl | desc | rcb | sgt] [addr] > /proc/al_dbger",
};

static void al_pci_dbg_help(struct al_dbg_attr *dbgattr, char *app_name)
{
    int i;

    al_printf(dbgattr, "%s %s (c) %s, "
           "Anlogic Bsp\n", app_name,
           AL_DBG_VERSION, AL_DBG_COPYRIGHT_YEARS);
    al_printf(dbgattr, "\n"
           "Usage: %s [options] <filename>\n"
           "\n"
           "Options:\n\n", app_name ? : AL_DBG_NAME);
    for (i = 0; i < ARRAY_SIZE(longopts) - 1; i++) {
        al_printf(dbgattr, "\t-%c, --%s%s\n" /* "\t-%c%s\n" */,
               longopts[i].shortname,
               longopts[i].longname,
               (longopts[i].argtype != OPTPARSE_NONE) ? " <argument>" : "");
        al_printf(dbgattr, "\t\t%s.\n\n", option_help[longopts[i].shortname]);
    }
}

static void al_pci_dbg_setup_transfer(struct al_dbg_attr *dbgattr, struct optparse *options)
{
    char *argv[AL_DBG_ARGC_MAX] = {NULL};
    int argc = 0, ret;
    struct anlogic_dma_engine *engine =
        ((struct al_pci_dbg *)container_of(options, struct al_pci_dbg, options))->engine;

    optget_args(options, argc, argv, AL_DBG_ARGC_MAX);

    if (strcmp(argv[0], "ring") == 0) {
        ret = sgdma_cyclic_transfer_setup(engine);
        if (ret == 0) {
            pr_info("Engine %s setup rx ring transfer %p success.\n", engine->name, &engine->cyclic_req->tfer[0]);
        } else {
            pr_info("Engine %s setup rx ring transfer failed.\n", engine->name);
        }
        return;
    }
}

static void al_pci_dbg_dump(struct al_dbg_attr *dbgattr, struct optparse *options)
{
    char *argv[AL_DBG_ARGC_MAX] = {NULL};
    int argc = 0;
    unsigned long addr = 0;
    struct anlogic_dma_engine *engine =
        ((struct al_pci_dbg *)container_of(options, struct al_pci_dbg, options))->engine;

    optget_args(options, argc, argv, AL_DBG_ARGC_MAX);

    if (strcmp(argv[0], "status") == 0) {
        __engine_status_dump(engine);
        return;
    }

    if (strcmp(argv[0], "tl") == 0) {
        engine_transfer_list_dump(engine);
        return;
    }

    if (strcmp(argv[0], "transfer") == 0) {
        DBG_FORMART_INT_ARG(argv[1], addr, 16);
        transfer_dump((struct sgdma_transfer *)addr);
        return;
    }

    if (strcmp(argv[0], "desc") == 0) {
        DBG_FORMART_INT_ARG(argv[1], addr, 16);
        dump_desc((struct sgdma_desc *)addr);
        return;
    }

    if (strcmp(argv[0], "rcb") == 0) {
        DBG_FORMART_INT_ARG(argv[1], addr, 16);
        sgdma_request_cb_dump((struct sgdma_request_cb *)addr);
        return;
    }

    if (strcmp(argv[0], "sgt") == 0) {
        DBG_FORMART_INT_ARG(argv[1], addr, 16);
        sgt_dump((struct sg_table *)addr);
        return;
    }

    if (strcmp(argv[0], "reg") == 0) {
        engine_reg_dump(engine);
        return;
    }

    if (strcmp(argv[0], "sgreg") == 0) {
        __engine_status_dump(engine);
        return;
    }

    if (strcmp(argv[0], "engine") == 0) {
        engine_info_dump(engine);
        return;
    }
}

static void al_pci_dbg_test(struct al_dbg_attr *dbgattr, struct optparse *options)
{
    char *argv[AL_DBG_ARGC_MAX] = {NULL};
    int argc = 0;
    unsigned long idx = 0;

    optget_args(options, argc, argv, AL_DBG_ARGC_MAX);

    if (strcmp(argv[0], "list") == 0) {
        al_pci_test_case_show(dbgattr);
        return;
    }

    if (strcmp(argv[0], "all") == 0) {
        al_pci_test_exec_all(dbgattr);
        return;
    }

    /* test a case */
    DBG_FORMART_INT_ARG(argv[0], idx, 10);

    al_pci_test_exec(dbgattr, idx, argc - 1, &argv[1]);

    return;
}

static int al_pci_dbg_main(struct al_dbg_attr *dbg_attr, int argc, char *argv[])
{
    int option, ret;

    struct al_pci_dbg pci_dbg = {
        .mode = 0,
        .ch = 0,
        .engine = NULL,
    };

	dbg_attr->need_wait = 0;
	if (!strcmp(argv[1], "w0")) {
		// need wait for next case
		dbg_attr->need_wait = 1;
		argc -= 1;
		argv += 1;
	} else if (!strcmp(argv[1], "w1")) {
		// complete wait
		dbg_attr->need_wait = 2;
		argc -= 1;
		argv += 1;
	} else if (!strcmp(argv[1], "wc")) {
		// reset wait
		al_case_wait_reset();
		argc -= 1;
		argv += 1;
		return 0;
	}

    /* init a start engine. */
    AL_GET_DMA_ENGINE(dbg_attr, pci_dbg.engine, pci_dbg.mode, pci_dbg.ch);

    optparse_init(&pci_dbg.options, argv);
    while ((option = optparse_long(&pci_dbg.options, longopts, NULL)) != -1) {
        switch (option) {
        case 'm':
            pci_dbg.mode = pci_dbg.options.optarg ? simple_strtol(pci_dbg.options.optarg, NULL, 10) : 1;
            AL_GET_DMA_ENGINE(dbg_attr, pci_dbg.engine, pci_dbg.mode, pci_dbg.ch);
            break;
        case 'c':
            pci_dbg.ch = pci_dbg.options.optarg ? simple_strtol(pci_dbg.options.optarg, NULL, 10) : 1;
            AL_GET_DMA_ENGINE(dbg_attr, pci_dbg.engine, pci_dbg.mode, pci_dbg.ch);
            break;
        case 'r':
            if (NULL == engine_start(pci_dbg.engine)) {
                al_printf(dbg_attr, "engine start failed\n");
            }
            break;
        case 's':
            ret = engine_service_shutdown(pci_dbg.engine);
            if (ret < 0) {
                al_printf(dbg_attr, "engine stop failed with %d\n", ret);
            }
            break;
        case 'd':
            al_pci_dbg_dump(dbg_attr, &pci_dbg.options);
            break;
        case 'b':
            al_pci_dbg_setup_transfer(dbg_attr, &pci_dbg.options);
            break;
        case 't':
            al_pci_dbg_test(dbg_attr, &pci_dbg.options);
            break;
        case 'h': // help
            al_pci_dbg_help(dbg_attr, argv[0]);
            break;
        }
    }

    return ret;
}

static struct al_dbg_attr al_dbgs[SGDMA_CHANNEL_NUM_MAX];
static int c2h_cpu[SGDMA_CHANNEL_NUM_MAX];
static int h2c_cpu[SGDMA_CHANNEL_NUM_MAX];

int al_get_cpu(int ch, enum dma_mode mode)
{
	if (ch >= SGDMA_CHANNEL_NUM_MAX) {
		return 0;
	}

	if (mode == c2h) {
		return c2h_cpu[ch];
	} else {
		return h2c_cpu[ch];
	}
}

int al_pci_drv_dbg_init(struct device *dev)
{
	int cpu, rv, i;

	for (i = 0; i < 2 * SGDMA_CHANNEL_NUM_MAX; ) {
		for_each_online_cpu(cpu) {
			if (i >= 2 * SGDMA_CHANNEL_NUM_MAX) {
				break;
			}

			if (i < SGDMA_CHANNEL_NUM_MAX) {
				c2h_cpu[i] = cpu;
			} else {
				h2c_cpu[i - SGDMA_CHANNEL_NUM_MAX] = cpu;
			}

			i++;
		}
	}

	for (i = 0; i < SGDMA_CHANNEL_NUM_MAX; i++) {
		if (!i)
			snprintf(al_dbgs[i].name, 32, "al_dbger");
		else
			snprintf(al_dbgs[i].name, 32, "al_dbger%d", i);

		al_dbgs[i].dev = dev;
		al_dbgs[i].index = i;
		al_pci_test_main(&al_dbgs[i], i);

		rv = AL_DBG_NODE_CREATE(&al_dbgs[i], al_pci_dbg_main, NULL);
		if (rv < 0) {
			pr_info("Create %s failed.\n", al_dbgs[i].name);
			return rv;
		}
	}

    return 0;
}

void al_pci_drv_dbg_exit(void)
{
	int i;
	for (i = 0; i < SGDMA_CHANNEL_NUM_MAX; i++) {
		al_dbgs[i].dev = NULL;

		AL_DBG_NODE_DESTORY(&al_dbgs[i]);
	}
}

