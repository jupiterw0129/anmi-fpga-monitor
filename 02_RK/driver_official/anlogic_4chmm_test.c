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
#include <linux/random.h>
#include <linux/platform_device.h>

#include "anlogic_dbg.h"
#include "anlogic_pci_lib.h"
#include "anlogic_pci_drv.h"
#include "anlogic_pci_dbg.h"
#include "anlogic_pci_test.h"
#include "anlogic_ring.h"
#include "anlogic_thread.h"
#include "cdev_ctrl.h"

#if RANDOM_TEST
struct sgdma_rtest_perf_cnt {
	uint64_t clock_cycle_count;
	uint64_t data_cycle_count;
	uint16_t data_width;
	uint16_t res0;
	uint32_t res1;
};

struct sgdma_rtest_config {
	u64 flags;
	u32 chn_list[SGDMA_CHANNEL_NUM_MAX * 2];
	u32 h2c_cnt;
	u32 c2h_cnt;
	u32 desc_cnt;
	u32 count;
	u64 ep_addr;
	u64 ep_len;
	struct sgdma_rtest_perf_cnt perf[SGDMA_CHANNEL_NUM_MAX * 2];
};

struct sgdma_rtest_case {
	atomic_t done;
	wait_queue_head_t wq;
};

struct sgdma_rtest_data {
	struct sgdma_rtest_case *testcase;
	int result;
};

static inline u64 build_u64(u64 hi, u64 lo)
{
	return ((hi & 0xFFFFFFFULL) << 32) | (lo & 0xFFFFFFFFULL);
}

static inline void sgdma_rtest_perf_get(struct anlogic_dma_engine *engine,
					struct sgdma_rtest_perf_cnt *perf)
{
	struct anlogic_dev *sgdev = engine->sgdev;
	struct config_regs *cfg_regs =
				(struct config_regs *)(sgdev->bar[sgdev->config_bar_idx] + SGDMA_OFS_CONFIG);
	u32 hi, lo;

	hi = read_register(&engine->regs->perf_cyc_hi);
	lo = read_register(&engine->regs->perf_cyc_lo);
	perf->clock_cycle_count = build_u64(hi, lo);
	hi = read_register(&engine->regs->perf_dat_hi);
	lo = read_register(&engine->regs->perf_dat_lo);
	perf->data_cycle_count = build_u64(hi, lo);

	perf->data_width = (read_register(&cfg_regs->data_width) & 0x7);
	perf->data_width = (64 << perf->data_width);
}

static int sgdma_rtest_gen_write_data(struct sgdma_rtest *rtest)
{
	int i, j, k;

	k = 0;
	for (i = 0; i < rtest->desc_num; i++) {
		for (j = 0; j < rtest->sdesc[i].len; j++) {
			rtest->sdesc[i].p[j] = (k & 0xff);
			k++;
		}
	}

	return 0;
}

static int sgdma_rtest_verify_data(struct sgdma_rtest *rtest)
{
	int i, j, k;

	k = 0;
	for (i = 0; i < rtest->desc_num; i++) {
		for (j = 0; j < rtest->sdesc[i].len; j++) {
			if (rtest->sdesc[i].p[j] != (k & 0xff)) {
				pr_err("%s rtest fail: desc %d, offset %d, expect %d, actual %d\n",
						rtest->engine->name, i, j, (k & 0xff), rtest->sdesc[i].p[j]);
				return -EINVAL;
			}
			k++;
		}
	}
	pr_info("%s rtest [%u] verify data pass\n", rtest->engine->name, rtest->test_cnt);
	return 0;
}

static int sgdma_rtest_done(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_transfer *xfer = &rtest->tfer;
	struct sgdma_rtest_data *rdata = rtest->private;
	struct sgdma_rtest_case *testcase = rdata->testcase;
	u32 val;
	int ret = 0;

	if (xfer->state != TRANSFER_STATE_COMPLETED) {
		if (engine->running)
			sgdma_engine_stop(engine);
		pr_err("%s rtest fail: compl_desc %d, status %d\n",
				rtest->engine->name,
				rtest->compl_desc_num, xfer->state);
		ret = -1;
		goto finish_rtest;
	}

	if ((rtest->flags & RTFLG_CHKDATA)) {
		if (rtest->write) {
#if 0
			val = read_register(sgdev->bar[sgdev->config_bar_idx] + 0x80004);
			if (val & (0x1 << rtest->channel))
				ret = -1;
			else
				ret = 0;
#endif
		} else {
			ret = sgdma_rtest_verify_data(rtest);
		}

		if (ret < 0) {
			pr_err("%s rtest verify data failed\n", rtest->engine->name);
			goto finish_rtest;
		}
	}

	if (!rtest->link || !rtest->link->start) {
finish_rtest:
		rdata->result = ret;
		pr_info("%s rtest %s, count %u\n", rtest->engine->name, ret ? "failed" : "successful", rtest->test_cnt);
		atomic_inc(&testcase->done);
		wake_up(&testcase->wq);
		return 0;
	}

	if (!(rtest->flags & RTFLG_LOOPBACK) || !rtest->write) {
		if (rtest->test_cnt >= rtest->expect_cnt) {
			ret = 0;
			goto finish_rtest;
		}
	}

	rdata->result = 0;

	ret = rtest->link->start(rtest->link);
	if (ret < 0) {
		pr_err("%s rtest link %s start failed\n",  rtest->engine->name,
				rtest->link->engine->name);
		goto finish_rtest;
	}
	return 0;
}

static int sgdma_rtest_restart(struct sgdma_rtest *rtest)
{
	struct anlogic_dma_engine *engine = rtest->engine;
	struct sgdma_rtest_data *rdata = rtest->private;
	int canceled = 0;
	int ret;

restart:
	rdata->result = -1;
	ret = sgdma_rtest_xfer_init(rtest);
	if (ret < 0) {
		pr_err("%s rtest xfer init failed, compl_desc %u\n", rtest->engine->name,
				rtest->compl_desc_num);
		goto err_out;
	}
	ret = sgdma_rtest_xfer_submit(rtest, sgdma_rtest_done);
	if (ret < 0) {
		pr_err("%s rtest xfer submit failed, compl_desc %u\n", rtest->engine->name,
				rtest->compl_desc_num);
		goto err_xfer_destroy;
	}
	ret = sgdma_rtest_xfer_start(rtest);
	if (ret < 0) {
		pr_err("%s rtest xfer start failed, compl_desc %u\n", rtest->engine->name,
				rtest->compl_desc_num);
		goto err_xfer_cancel;
	}

	if (!canceled && (rtest->flags & RTFLG_CANCEL) &&
		(!engine->streaming || !(rtest->flags & RTFLG_LOOPBACK) || rtest->write)) {
		if (!sgdma_rtest_xfer_cancel(rtest)) {
			pr_info("%s rtest xfer canceled successfully\n", rtest->engine->name);
			canceled = 1;
			schedule_timeout_interruptible(HZ / 2);
			goto restart;
		} else {
			pr_info("%s rtest xfer cancel failed\n", rtest->engine->name);
		}
	}

	if (rtest->engine->cmplthp)
		sgdma_kthread_wakeup(rtest->engine->cmplthp);

	return 0;
err_xfer_cancel:
	sgdma_rtest_xfer_cancel(rtest);
err_xfer_destroy:
	sgdma_rtest_xfer_destroy(rtest);
err_out:
	return ret;
}

int sgdma_rtest_do_test(struct anlogic_dev *sgdev, struct sgdma_rtest_config *rtc)
{
	u64 ep_addr = rtc->ep_addr;
	u64 off = 0;
	u64 ep_len;
	struct sgdma_rtest *rtest[SGDMA_CHANNEL_NUM_MAX * 2];
	struct sgdma_rtest_data rdata[SGDMA_CHANNEL_NUM_MAX * 2];
	struct sgdma_rtest_case testcase;
	struct sgdma_rtest *source;
	int i, j;
	int init_cnt = 0;
	int submit_cnt = 0;
	int cnt;
	int ret = 0;
	bool write;

	if ((rtc->h2c_cnt + rtc->c2h_cnt) == 0) {
		pr_err("no channel specified\n");
		return -EINVAL;
	}

	if (rtc->flags & RTFLG_HWPERF) {
		struct anlogic_dma_engine *engine;

		for (i = 0; i < rtc->h2c_cnt + rtc->c2h_cnt; i++) {
			if (rtc->chn_list[i] >= SGDMA_CHANNEL_NUM_MAX) {
				pr_err("channel number too large\n");
				return -EINVAL;
			}

			if (i < rtc->h2c_cnt)
				engine = &sgdev->engine_h2c[rtc->chn_list[i]];
			else
				engine = &sgdev->engine_c2h[rtc->chn_list[i]];

			if (rtc->flags & 1)
				enable_perf(engine);
			else
				sgdma_rtest_perf_get(engine, &rtc->perf[i]);
		}
		return 0;
	}

	if (rtc->h2c_cnt > SGDMA_CHANNEL_NUM_MAX || rtc->c2h_cnt > SGDMA_CHANNEL_NUM_MAX) {
		pr_err("channel number too large\n");
		return -EINVAL;
	}

	if (!rtc->count || !rtc->desc_cnt) {
		pr_err("no count or desc_cnt specified\n");
		return -EINVAL;
	}

	if (rtc->flags & RTFLG_LOOPBACK) {
		if (rtc->h2c_cnt != rtc->c2h_cnt) {
			pr_err("h2c and c2h channel mismatch\n");
			return -EINVAL;
		}
		ep_len = rtc->ep_len / rtc->h2c_cnt;
	} else {
		ep_len = rtc->ep_len / (rtc->h2c_cnt + rtc->c2h_cnt);
	}

	if (ep_len < 256) {
		pr_err("ep_len too small\n");
		return -EINVAL;
	}

	memset(rdata, 0, sizeof(rdata));
	memset(&testcase, 0, sizeof(testcase));
	init_waitqueue_head(&testcase.wq);
	atomic_set(&testcase.done, 0);

	memset(rtest, 0, sizeof(rtest));
	off = 0;
	for (i = 0; i < rtc->h2c_cnt + rtc->c2h_cnt; i++) {
		source = NULL;
		if (i < rtc->h2c_cnt) {
			write = 1;
		} else {
			write = 0;
			if (rtc->flags & RTFLG_LOOPBACK) {
				source = rtest[i - rtc->h2c_cnt];
				if (i == rtc->h2c_cnt)
					off = 0;
			}
		}
		rtest[i] = sgdma_rtest_create(sgdev, rtc->chn_list[i], write, ep_addr + off, ep_len,
									 rtc->desc_cnt, rtc->flags, rtc->count, source);
		if (!rtest[i]) {
			pr_err("create rtest %d failed\n", i);
			ret = -ENOMEM;
			goto err_out;
		}
		off += ep_len;

		if (write)
			sgdma_rtest_gen_write_data(rtest[i]);
	}

	for (i = 0; i < rtc->h2c_cnt + rtc->c2h_cnt; i++) {
		ret = sgdma_rtest_xfer_init(rtest[i]);
		if (ret) {
			pr_err("%s rtest xfer init failed\n", rtest[i]->engine->name);
			goto err_destroy_xfer;
		}
		init_cnt++;
		rdata[i].result = -1;
		rdata[i].testcase = &testcase;
		rtest[i]->private = rdata + i;
		rtest[i]->link = rtest[i];
		rtest[i]->start = sgdma_rtest_restart;
		if ((rtc->flags & RTFLG_LOOPBACK) && (i >= rtc->h2c_cnt)) {
			rtest[i]->link = rtest[i - rtc->h2c_cnt];
			rtest[i - rtc->h2c_cnt]->link = rtest[i];
		}

		enable_perf(rtest[i]->engine);
	}

	cnt = (rtc->flags & RTFLG_LOOPBACK) ? rtc->h2c_cnt : rtc->h2c_cnt + rtc->c2h_cnt;
	for (i = 0; i < cnt; i++) {
		ret = sgdma_rtest_xfer_submit(rtest[i], sgdma_rtest_done);
		if (ret) {
			pr_err("%s rtest xfer start failed\n", rtest[i]->engine->name);
			goto err_cancel_xfer;
		}
		submit_cnt++;
	}

#if 1
	for (i = 0; i < cnt; i++) {
		ret = sgdma_rtest_xfer_start(rtest[i]);
		if (ret) {
			pr_err("%s rtest xfer start failed\n", rtest[i]->engine->name);
			rtest[i]->start_ret = -1;
			goto err_cancel_xfer;
		}
		rtest[i]->start_ret = 1;
		if (rtest[i]->engine->cmplthp)
			sgdma_kthread_wakeup(rtest[i]->engine->cmplthp);
	}
#else
	cnt = sgdma_rtest_xfer_start_mult(rtest, cnt);
#endif

	submit_cnt = rtc->h2c_cnt + rtc->c2h_cnt;

	if (wait_event_interruptible(testcase.wq, (atomic_read(&testcase.done) == cnt))) {
		pr_err("rtest is canceled\n");
		ret = -EINTR;
		for (i = 0; i < rtc->h2c_cnt + rtc->c2h_cnt; i++) {
			unsigned long flags;
			spin_lock_irqsave(&rtest[i]->engine->lock, flags);
			rtest[i]->tfer.cb = NULL;
			spin_unlock_irqrestore(&rtest[i]->engine->lock, flags);
			cancel_work_sync(&rtest[i]->work);
			pr_info("%s rtest result = %d, count = %u\n", rtest[i]->engine->name,
					rdata[i].result, rtest[i]->test_cnt);
		}
		goto err_cancel_xfer;
	}

	pr_info("****************************************\n");
	ret = 0;
	for (i = 0; i < rtc->h2c_cnt + rtc->c2h_cnt; i++) {
		sgdma_rtest_perf_get(rtest[i]->engine, &rtc->perf[i]);

		if (rdata[i].result) {
			pr_err("* %s rtest fail, %d\n", rtest[i]->engine->name, rdata[i].result);
			ret = -EIO;
		} else
			pr_info("* %s rtest pass\n", rtest[i]->engine->name);
	}

	if (!ret)
		pr_info("* rtests all passed\n");
	pr_info("****************************************\n");

err_cancel_xfer:
	for (j = 0; j < submit_cnt; j++) {
		sgdma_rtest_xfer_cancel(rtest[j]);
	}
err_destroy_xfer:
	for (j = 0; j < init_cnt; j++) {
		sgdma_rtest_xfer_destroy(rtest[j]);
	}
err_out:
	for (j = 0; j < rtc->h2c_cnt + rtc->c2h_cnt; j++) {
		if (rtest[j])
			sgdma_rtest_free(rtest[j]);
	}
	return ret;
}

int ioc_sgdma_rtest(struct anlogic_dev *sgdev, unsigned long arg)
{
	struct anlogic_ioc_rtest ioc_rtest;
	struct sgdma_rtest_config rtc;
	int res, i;

	if (copy_from_user((void *)&ioc_rtest, (void __user *)arg,
					   sizeof(struct anlogic_ioc_rtest))) {
		return -EFAULT;
	}

	memset(&rtc, 0, sizeof(rtc));
	rtc.flags = ioc_rtest.flags;
	rtc.h2c_cnt = ioc_rtest.h2c_cnt;
	rtc.c2h_cnt = ioc_rtest.c2h_cnt;
	rtc.desc_cnt = ioc_rtest.desc_cnt;
	rtc.count = ioc_rtest.count;
	rtc.ep_addr = ioc_rtest.ep_addr;
	rtc.ep_len = ioc_rtest.ep_len;
	memcpy(rtc.chn_list, ioc_rtest.chn_list, sizeof(u32) * (rtc.h2c_cnt + rtc.c2h_cnt));
	res = sgdma_rtest_do_test(sgdev, &rtc);
	if (res)
		return res;

	for (i = 0; i < rtc.h2c_cnt + rtc.c2h_cnt; i++) {
		if (copy_to_user(((struct anlogic_ioc_rtest __user *)arg)->perf + i,
				 (void *)&rtc.perf[i], sizeof(struct anlogic_perf_cnt))) {
			return -EFAULT;
		}
	}
	return 0;
}

#endif
