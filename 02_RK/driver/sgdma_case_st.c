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

#include "anlogic_dbg.h"
#include "anlogic_pci_lib.h"
#include "anlogic_pci_drv.h"
#include "anlogic_pci_dbg.h"
#include "anlogic_pci_test.h"
#include "anlogic_ring.h"

#undef TEST_DESC_NUM
#undef TEST_DATA_DUMP_SIZE
#define TEST_DATA_TOTAL_SIZE (2048 * 64)
#define TEST_DESC_NUM       64
#define TEST_DATA_DUMP_SIZE 0x200
#define TEST_RING_CNT       1

int do_data_check_1(struct al_test_case *sub_case, struct al_test_case *cur_case);

static int h2c_tx_thread(void *data)
{
    struct al_test_case *cur_case = (struct al_test_case *)data;
    int total_num, credit_cnt = 0;

    if (cur_case) {
        total_num = cur_case->desc_num * TEST_RING_CNT;
        //al_pci_test_engine_do_transfer(cur_case, cur_case->desc_num);
		al_case_wait(cur_case);
        al_pci_test_engine_do_transfer_with_no_stop(cur_case, cur_case->desc_num, 0);
    } else
        return -EINVAL;

    if (cur_case->enable_credit) {
        while (total_num > 0) {
            credit_cnt = (credit_cnt > total_num) ? total_num : al_random_num_gen(1, total_num) & 0xff;
            /* init credit num */
            TEST_DBG(cur_case, "write credits num %d.\n", credit_cnt);
            write_register(credit_cnt,
                        &cur_case->engine->sgdma_regs->credits,
                (unsigned long)(&cur_case->engine->sgdma_regs->credits) -
                    (unsigned long)(cur_case->engine->sgdma_regs));

            total_num -= credit_cnt;
            msleep(al_random_num_gen(1, 10) & 0xf);
        }
    }

    cur_case->run_status = 2;
	return 0;
}

static int c2h_rx_thread(void *data)
{
    struct al_test_case *cur_case = (struct al_test_case *)data;
    int total_num, credit_cnt = 0;

    if (cur_case) {
        total_num = cur_case->desc_num * TEST_RING_CNT;
        //al_pci_test_engine_do_transfer(cur_case, cur_case->desc_num);
		al_case_wait(cur_case);
        al_pci_test_engine_do_transfer_with_no_stop(cur_case, cur_case->desc_num, 0);
    }
    else
        return -EINVAL;

    TEST_DBG(cur_case, "total_num: %d.\n", total_num);

    if (cur_case->enable_credit) {
        while (total_num > 0) {
            credit_cnt = (credit_cnt > total_num) ? total_num : al_random_num_gen(1, total_num) & 0xff;
            TEST_DBG(cur_case, "credit_cnt %d, total_num %d.\n", credit_cnt, total_num);

            /* init credit num */
            TEST_DBG(cur_case, "write credits num %d.\n", credit_cnt);
            write_register(credit_cnt,
                        &cur_case->engine->sgdma_regs->credits,
                (unsigned long)(&cur_case->engine->sgdma_regs->credits) -
                    (unsigned long)(cur_case->engine->sgdma_regs));

            total_num -= credit_cnt;
            msleep(al_random_num_gen(1, 10) & 0xf);
        }
    }

    cur_case->run_status = 2;

	return 0;
}

struct task_struct *kthread_run_node(int (*threadfn)(void *data), void *data, const char *name, uint16_t cpu)
{
    struct task_struct *task;
    int node;

    node = cpu_to_node(cpu);

    task = kthread_create_on_node(threadfn, (void *)data,
                    node, "%s", name);
    if (IS_ERR(task)) {
        pr_err("kthread %s, create task failed: 0x%lx\n",
            name, (unsigned long)IS_ERR(task));
        task = NULL;
        return NULL;
    }

    kthread_bind(task, cpu);

    printk("kthread 0x%p, %s, cpu %u, task 0x%p.\n",
        task, name, cpu, task);

    return task;
}

bool do_data_check(struct al_test_case *cur_case, uint32_t total_sz, uint8_t *golden_data, uint8_t *pdata)
{
    char prefix[64];
    bool ret = true;
    int i;

    /* do data check */
    for (i = 0; i < total_sz; i++)
        if (golden_data[i] != pdata[i]) {
#define DUMP_RANGE 512
            if (i < DUMP_RANGE) {
                sprintf(prefix, "target(base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i): total_sz, true);
                sprintf(prefix, "got   (base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i) : total_sz, true);
            } else {
                sprintf(prefix, "target(base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
                sprintf(prefix, "got   (base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
            }

            TEST_ERR(cur_case, "mem read and write data check failed, target: 0x%02x, got: 0x%02x, offset: 0x%08x\n",
                golden_data[i], pdata[i], i);
            printk(KERN_ERR"mem read and write data check failed, target: 0x%02x, got: 0x%02x, offset: 0x%08x\n",
                golden_data[i], pdata[i], i);
            ret = false;
            goto test_failed;
        }

test_failed:
    return ret;
}

bool desc_comp_wb_chek(struct al_test_case *cur_case, struct anlogic_dma_engine *engine, uint32_t desc_num)
{
    bool ret = true;
    struct sgdma_poll_wb *wb_data;
    uint32_t w;

    /* step3: check write back data */
    wb_data = (struct sgdma_poll_wb *)engine->poll_mode_addr_virt;

    w = read_register(&engine->regs->completed_desc_count);

    TEST_DBG(cur_case, "%s hw write back completed cnt: %d, register comp desc cnt: %d\n", engine->name, wb_data->completed_desc_count, w);
    printk(KERN_ERR"%s hw write back completed cnt: %d, register comp desc cnt: %d\n", engine->name, wb_data->completed_desc_count, w);

    if (wb_data->completed_desc_count != desc_num || w  != desc_num) {
        TEST_ERR(cur_case, "%s expected comp desc cnt: %d\n", engine->name, desc_num);
        printk(KERN_ERR"%s expected comp desc cnt: %d\n", engine->name, desc_num);

        ret = false;
        goto out1;
    }

out1:
    return ret;
}

H2C_TEST_CASE("sgdma(mm) sim: [case30_2_sub]", case30_2_sub)
{
    TEST_RET(cur_case, true, "\n");
}

C2H_ST_CASE("sgdma st case30_2", case30_2)
{
#undef TEST_DESC_NUM
#undef TEST_DATA_DUMP_SIZE
#define TEST_DESC_NUM       64
#define TEST_DATA_DUMP_SIZE 0x200

	struct anlogic_dma_engine *engine = cur_case->engine;
    struct al_test_case *sub_case = cur_case->next;
	struct anlogic_dma_engine *sub_engine = sub_case->engine;
    struct anlogic_dev *sgdev = engine->sgdev;
    struct sgdma_poll_wb *wb_data;
    uint8_t *golden_data, *pdata;
    uint32_t control = 0, status, next_adj, w, total_sz = TEST_DATA_TOTAL_SIZE;
    uint32_t desc_num = TEST_DESC_NUM, is_random = 0, thread_delay_ms = 0, align = 0;
    char prefix[64], err_info[256] = {0};
    bool ret = true;
    struct task_struct *h2c_kthread, *c2h_kthread;
    int cpu, thread_cnt = 0;
    int i, rv;

    DBG_FORMART_INT_ARG_WTIH_RET(argv[0], desc_num, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[1], is_random, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[2], thread_delay_ms, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[3], align, 10, false);

    cur_case->data_size += desc_data_size_gen_custom_total_size(desc_num, is_random, 64,
            &cur_case->desc_sz[0], &cur_case->mm_ofs[0], total_sz, 0);

    rv = case_rsc_alloc(cur_case, is_random, align, desc_num, sgdev);
    if (rv < 0)
        goto out1;

    pdata = cur_case->data_virt;
    memset(cur_case->data_virt, 0, total_sz);

    al_pci_test_build_desc_custom(cur_case, desc_num, &cur_case->desc_sz[0], cur_case->is_stream, &cur_case->mm_ofs[0]);

    /* run h2c transfer */
    sub_case->data_size += desc_data_size_gen_custom_total_size(desc_num, is_random, align,
            &sub_case->desc_sz[0], &sub_case->mm_ofs[0], total_sz, 0);

    rv = case_rsc_alloc(sub_case, is_random, align, desc_num, sgdev);
    if (rv < 0)
        goto out1;

    golden_data = sub_case->data_virt;
    for (i = 0; i < total_sz; i++)
        golden_data[i] = (is_random) ? al_random_num_gen(0, 0xff) : i;

    al_pci_test_build_desc_custom(sub_case, desc_num, &sub_case->desc_sz[0], sub_case->is_stream, &sub_case->mm_ofs[0]);

    wmb();

	cur_case->run_status = 1;
	sub_case->run_status = 1;
	h2c_kthread = kthread_run_node(h2c_tx_thread, sub_case, "h2c_tx_thread", sub_case->cpu);
    if (!h2c_kthread) {
        return -ECHILD;
    }
	c2h_kthread = kthread_run_node(c2h_rx_thread, cur_case, "c2h_rx_thread", cur_case->cpu);
    if (!c2h_kthread) {
        return -ECHILD;
    }

    wake_up_process(h2c_kthread);
    if (thread_delay_ms) msleep(thread_delay_ms);
    wake_up_process(c2h_kthread);

    msleep(1000);
	while (cur_case->run_status != 2 || sub_case->run_status != 2)
		msleep(1);

    /* step3: check write back data */
    ret = desc_comp_wb_chek(cur_case, sub_engine, desc_num);
    if (ret == false)
        goto out1;

    ret = desc_comp_wb_chek(cur_case, engine, desc_num);
    if (ret == false)
        goto out1;

    /* do data check */
    for (i = 0; i < total_sz; i++)
        if (golden_data[i] != pdata[i]) {
#define DUMP_RANGE 512
            if (i < DUMP_RANGE) {
                sprintf(prefix, "target(base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i): total_sz, true);
                sprintf(prefix, "got   (base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i) : total_sz, true);
            } else {
                sprintf(prefix, "target(base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
                sprintf(prefix, "got   (base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
            }

            TEST_ERR(cur_case, "mem read and write data check failed, target: 0x%02x, got: 0x%02x, offset: 0x%08x\n",
                golden_data[i], pdata[i], i);
            ret = false;
            goto out1;
        }

out1:
    printk(KERN_ERR"ret = %d \r\n", ret);
    sgdma_engine_stop(sub_engine);
    sub_engine->running = 0;
    sgdma_engine_stop(engine);
    engine->running = 0;

    case_rsc_free(cur_case, sgdev);
    desc_data_size_clr(cur_case);
    case_rsc_free(sub_case, sgdev);
    desc_data_size_clr(sub_case);
    TEST_RET(cur_case, ret, "%s\n", err_info);
}

H2C_ST_CASE("sgdma(mm) sim: [case33_2_sub]", case33_2_sub)
{
    TEST_RET(cur_case, true, "\n");
}


/* return 0 for fail, 1 for success */
int do_data_check_1(struct al_test_case *sub_case, struct al_test_case *cur_case)
{
    u32 idx_src = 0;
    u32 idx_dst = 0;
    u64 src_addr;
    u64 dst_addr;
    u32 src_len;
    u32 dst_len;
    u32 align_4_flag = 0;
    u32 align_8_flag = 0;
    u32 cmp_len = 0;
    u32 loop_count = 0;
    u32 align_step = 0;
    u8  loop_start = 1;

    u32 src_idx_flag = 0;
    u32 dst_idx_flag = 0;

    if (!sub_case || !cur_case)
    {
        return 0;
    }

    src_addr = (u64)(uint8_t *)sub_case->data_array[idx_src];
    dst_addr = (u64)(uint8_t *)cur_case->data_array[idx_dst];

    src_len = sub_case->desc_array[idx_src]->bytes;
    dst_len = cur_case->res_array[idx_dst]->length;
    printk("idx_src: %d, idx_dst: %d, status: %d, src_len: %d, dst_len: %d, src_addr: 0x%llx, dst_addr: 0x%llx\n", idx_src, idx_dst, (cur_case->res_array[idx_dst]->status) & 1, src_len, dst_len,
                    (((u64)sub_case->desc_array[idx_src]->src_addr_hi << 32) | sub_case->desc_array[idx_src]->src_addr_lo),
                    (((u64)cur_case->desc_array[idx_dst]->dst_addr_hi << 32) | cur_case->desc_array[idx_dst]->dst_addr_lo));
    idx_src++;
    idx_dst++;

    while (1) {
        loop_start = 1;
        cmp_len = src_len < dst_len ? src_len : dst_len;
        loop_count = cmp_len;
        src_len -= loop_count;
        dst_len -= loop_count;
        while (loop_count--) {
            if (*(u8 *)src_addr != *(u8 *)dst_addr) {
                if (loop_count != (cmp_len-1)) {
                    printk("pre src data = 0x%x, pre dst data = 0x%x", *(u8 *)(src_addr-1), *(u8 *)(dst_addr-1));
                }
                printk("src data = 0x%x, dst data = 0x%x", *(u8 *)src_addr, *(u8 *)dst_addr);
                if (loop_count != 0) {
                    printk("nxt src data = 0x%x, nxt dst data = 0x%x", *(u8 *)(src_addr+1), *(u8 *)(dst_addr+1));
                }
                return 0;
            }
            src_addr++;
            dst_addr++;
        }


        if (src_len == 0 && dst_len == 0 && sub_case->desc_num == idx_src && cur_case->desc_num != idx_dst) {
            return 1;
        }

        if (src_len == 0 && sub_case->desc_num != idx_src) {
            src_addr = (u64)sub_case->data_array[idx_src];
            src_len = sub_case->desc_array[idx_src]->bytes;

            // printk("idx_src: %d, src_len: %d, src_addr: 0x%lx\n", idx_src, src_len,
            //         (((u64)sub_case->desc_array[idx_src]->src_addr_hi << 32) | sub_case->desc_array[idx_src]->src_addr_lo));
            idx_src++;
            src_idx_flag = 1;
        }

        if (dst_len == 0 && cur_case->desc_num != idx_dst) {
            dst_addr = (u64)cur_case->data_array[idx_dst];
            dst_len = cur_case->res_array[idx_dst]->length;

            // printk("idx_dst: %d, status: %d, dst_len: %d, dst_addr: 0x%lx\n", idx_dst, cur_case->res_array[idx_dst]->status, dst_len,
            //         (((u64)cur_case->desc_array[idx_dst]->dst_addr_hi << 32) | cur_case->desc_array[idx_dst]->dst_addr_lo));
            idx_dst++;
            dst_idx_flag = 1;
        }

        printk("idx_src: %d, idx_dst: %d, status: %d, src_len: %d, dst_len: %d, src_addr: 0x%llx, dst_addr: 0x%llx, dst_hi: 0x%x, dst_lo: 0x%x\n",
                    idx_src - 1, idx_dst - 1, (cur_case->res_array[idx_dst - 1]->status) & 1, src_len, dst_len,
                    (((u64)sub_case->desc_array[idx_src - 1]->src_addr_hi << 32) | sub_case->desc_array[idx_src - 1]->src_addr_lo),
                    (((u64)cur_case->desc_array[idx_dst - 1]->dst_addr_hi << 32) | cur_case->desc_array[idx_dst - 1]->dst_addr_lo),
                    cur_case->desc_array[idx_dst - 1]->dst_addr_hi,
                    cur_case->desc_array[idx_dst - 1]->dst_addr_lo);
        src_idx_flag = 0;
        dst_idx_flag = 0;

        if (src_len == 0 && dst_len == 0) {
            return 1;
        } else if (!src_len) {
            printk(KERN_ERR"critical_error, src_len = 0");
            return 0;
        } else if (!dst_len) {
            printk(KERN_ERR"critical_error, dst_len = 0");
            return 0;
        }
    }

    return 0;
}



C2H_ST_CASE("sgdma st case33_2", case33_2)
{
	struct anlogic_dma_engine *engine = cur_case->engine;
	struct al_test_case *sub_case = cur_case->next;
	struct anlogic_dma_engine *sub_engine = sub_case->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
    struct sgdma_poll_wb *wb_data;
    struct sgdma_common_regs *reg;
    struct sgdma_desc *desc_virt;

    uint32_t control = 0, status, next_adj, w, total_sz = TEST_DATA_TOTAL_SIZE;
    uint32_t h2c_desc_num = TEST_DESC_NUM, is_random = 0, thread_delay_ms = 0, align = 0, pkt_len = 0, pkt = 0;
    uint64_t pkt_len_sum=0;
    char err_info[256] = {0};
    bool ret = true;
    int i, pkt_idx = 0, rv, is_find_eop = 0, c2h_desc_num = 0;
    struct task_struct *h2c_kthread, *c2h_kthread;
    int cpu, thread_cnt = 0;
    uint8_t *golden_data, *pdata;

    DBG_FORMART_INT_ARG_WTIH_RET(argv[0], h2c_desc_num, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[1], is_random, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[2], thread_delay_ms, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[3], align, 10, false);

    TEST_DBG(sub_case, "config: h2c_desc_num:%d %d %d %d\r\n", h2c_desc_num, is_random, thread_delay_ms, align);
    /*
     *
     * config h2c
     *
     * */
    sub_case->data_size = desc_data_size_gen_custom_total_size(h2c_desc_num, is_random, align,
            &sub_case->desc_sz[0], &sub_case->mm_ofs[0], total_sz, 0);

    TEST_DBG(sub_case, "sub_case->data_size 0x%lx (%ld)\r\n", sub_case->data_size, sub_case->data_size);
    TEST_DBG(sub_case, "%ld %ld %ld %ld \r\n", sub_case->desc_sz[0], sub_case->desc_sz[1], sub_case->desc_sz[2], sub_case->desc_sz[3]);

    rv = case_rsc_alloc(sub_case, is_random, align, h2c_desc_num, sgdev);
    if (rv < 0)
        goto out;

    TEST_DBG(sub_case, "%ld %ld %ld %ld \r\n", sub_case->desc_sz[0], sub_case->desc_sz[1], sub_case->desc_sz[2], sub_case->desc_sz[3]);
    al_pci_test_build_desc_custom(sub_case, h2c_desc_num, &sub_case->desc_sz[0], sub_case->is_stream, &sub_case->mm_ofs[0]);

    pkt = 0;
    memset(cur_case->h2c_pkt_len, 0, sizeof(cur_case->h2c_pkt_len));
    for (i = 0; i < h2c_desc_num; i++) {
        control = 0;
        desc_virt = sub_case->desc_array[i];
        control |= (((al_random_num_gen(0, 1000) % 2) == 1) || ((i == (h2c_desc_num - 1)))) ? SGDMA_DESC_COMPLETED : 0;

        if ((sub_case->desc_sz[i] < 64) || ((al_random_num_gen(0, 1000) % 2) == 1) || (i == (h2c_desc_num - 1))) {
            control |= SGDMA_DESC_EOP;
            cur_case->h2c_pkt_len[pkt] += sub_case->desc_sz[i];
            pkt++; /* record pkt number */
        } else {
            desc_virt->bytes = ((desc_virt->bytes >> 6) << 6); /* record pkt len */
            cur_case->h2c_pkt_len[pkt] += desc_virt->bytes;
        }

        sgdma_desc_control_set(desc_virt, control);
    }

    /* create a linked loop */
    TEST_DBG(sub_case, "sgdma_desc_link\r\n");
    sgdma_desc_link(sub_case->desc_array[h2c_desc_num - 1], sub_case->desc_array[0], sub_case->desc_bus_array[0]);

    /* init credit mode */
    sub_case->enable_credit = 1;

    w = (0x1 << sub_engine->channel); /* h2c: bit0 ~ 3 */
    reg = (struct sgdma_common_regs
             *)(sgdev->bar[sgdev->config_bar_idx] +
                (0x6 * TARGET_SPACING));

    write_register(w, &reg->credit_mode_enable_w1s,
        (unsigned long)(&reg->credit_mode_enable_w1s) -
               (unsigned long)(reg));

    /*
     *
     * config c2h
     *
     * */
    TEST_DBG(cur_case, "\r\n\r\n");
    TEST_DBG(cur_case, "config c2h\r\n");
    cur_case->data_size = st_desc_data_size_gen_custom_by_h2c_pkt_size(cur_case, is_random, align,
                &cur_case->desc_sz[0], &c2h_desc_num, pkt, cur_case->h2c_pkt_len);
    TEST_DBG(cur_case, "sub_case->data_size 0x%lx (%ld)\r\n", cur_case->data_size, cur_case->data_size);

    rv = case_rsc_alloc(cur_case, is_random, align, c2h_desc_num, sgdev);
    if (rv < 0)
        goto out;

    TEST_DBG(cur_case, "al_pci_test_build_desc_custom cur_case->data_bus = 0x%llx\r\n", cur_case->data_bus);
    al_pci_test_build_desc_custom(cur_case, c2h_desc_num, &cur_case->desc_sz[0], cur_case->is_stream, &cur_case->mm_ofs[0]);

    for (i = 0; i < c2h_desc_num; i++) {
        desc_virt = cur_case->desc_array[i];
        control = 0;
        control |= (((al_random_num_gen(0, 1000) % 2) == 1) || ((i == (c2h_desc_num - 1)))) ? SGDMA_DESC_COMPLETED : 0;
        sgdma_desc_control_set(desc_virt, control);
    }

    /* create a linked loop */
    TEST_DBG(cur_case, "sgdma_desc_link\r\n");
    sgdma_desc_link(cur_case->desc_array[c2h_desc_num - 1], cur_case->desc_array[0], cur_case->desc_bus_array[0]);

    /* init credit mode */
    cur_case->enable_credit = 1;

    w = (0x1 << engine->channel) << 16; /* c2h: bit16 ~ 19 */
    reg = (struct sgdma_common_regs
             *)(sgdev->bar[sgdev->config_bar_idx] +
                (0x6 * TARGET_SPACING));

    write_register(w, &reg->credit_mode_enable_w1s,
        (unsigned long)(&reg->credit_mode_enable_w1s) -
               (unsigned long)(reg));

    /*
     * init thread
     */
    cur_case->run_status = 1;
    sub_case->run_status = 1;
	h2c_kthread = kthread_run_node(h2c_tx_thread, sub_case, "h2c_tx_thread", sub_case->cpu);
    if (!h2c_kthread) {
        return -ECHILD;
    }
    c2h_kthread = kthread_run_node(c2h_rx_thread, cur_case, "c2h_rx_thread", cur_case->cpu);
    if (!c2h_kthread) {
        return -ECHILD;
    }

    pdata = cur_case->data_virt;

    golden_data = sub_case->data_virt;
    for (i = 0; i < total_sz; i++)
        golden_data[i] = (is_random) ? al_random_num_gen(0, 0xff) : i;

    wmb();

    wake_up_process(c2h_kthread);
    while (cur_case->run_status != 2) msleep(1);
    msleep(10);
    wake_up_process(h2c_kthread);
    while (sub_case->run_status != 2) msleep(1);

    msleep(10);

    pkt_len_sum = 0;
    for (i = 0; i < pkt; i++) {
        TEST_DBG(cur_case, "h2c pkt[%d] len 0x%x\n", i, cur_case->h2c_pkt_len[i]);
        pkt_len_sum += cur_case->h2c_pkt_len[i];
    }
    TEST_DBG(cur_case, "h2c pkt len sum = [0x%llx]\n", pkt_len_sum);

    /* step3: check write back data */
    ret = desc_comp_wb_chek(cur_case, sub_engine, h2c_desc_num);
    if (ret == false)
        goto test_failed;

    ret = desc_comp_wb_chek(cur_case, engine, c2h_desc_num);
    if (ret == false)
        goto test_failed;

    ret = do_data_check_1(sub_case, cur_case);
    if (ret == false)
        goto test_failed;

test_failed:
	if (h2c_kthread) {
		printk("h2c_kthread kthread_stop");
		h2c_kthread = NULL;
	}

	if (c2h_kthread) {
		printk("c2h_kthread kthread_stop");
		c2h_kthread = NULL;
	}
out:

    sgdma_engine_stop(sub_engine);
    sub_engine->running = 0;
    sgdma_engine_stop(engine);
    engine->running = 0;

    case_rsc_free(cur_case, sgdev);
    desc_data_size_clr(cur_case);

    case_rsc_free(sub_case, sgdev);
    desc_data_size_clr(sub_case);

    printk(KERN_ERR"ret = %d \r\n", ret);

    TEST_RET(cur_case, ret, "\n");
}

C2H_ST_CASE("sgdma st case36 sub", case36_sub)
{
	TEST_RET(cur_case, true, "\n");
}
C2H_ST_CASE("sgdma st case36", case36)
{
	struct anlogic_dma_engine *engine = cur_case->engine;
	struct al_test_case *sub_case = cur_case->next;
	struct anlogic_dma_engine *sub_engine = sub_case->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
    struct sgdma_poll_wb *wb_data;
    struct sgdma_common_regs *reg;
    uint32_t control = 0, status, next_adj, w, total_sz = TEST_DATA_TOTAL_SIZE;
    uint32_t h2c_desc_num = TEST_DESC_NUM, is_random = 0, thread_delay_ms = 0, align = 0, pkt_len = 0, pkt = 0, stop_cnt = 0;
    uint32_t pkt_offset = 0;
    char err_info[256] = {0};
    bool ret = true;
    int i, pkt_idx = 0, rv, is_find_eop = 0, c2h_desc_num = 0;
    struct task_struct *h2c_kthread, *c2h_kthread;
    int cpu, thread_cnt = 0;
    uint8_t *golden_data, *pdata;
    uint8_t timeout = 0;
    struct sgdma_desc *desc_virt;

    DBG_FORMART_INT_ARG_WTIH_RET(argv[0], h2c_desc_num, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[1], is_random, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[2], thread_delay_ms, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[3], align, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[4], stop_cnt, 10, false);

    /*
     *
     * config h2c
     *
     * */
    cur_case->stop_start_test = 1;
    sub_case->stop_start_test = 1;

    sub_case->data_size = desc_data_size_gen_custom_total_size(h2c_desc_num, is_random, align,
            &sub_case->desc_sz[0], &sub_case->mm_ofs[0], total_sz, 0);

    rv = case_rsc_alloc(sub_case, is_random, align, h2c_desc_num, sgdev);
    if (rv < 0)
        goto out;

    al_pci_test_build_desc_custom(sub_case, h2c_desc_num, &sub_case->desc_sz[0], sub_case->is_stream, &sub_case->mm_ofs[0]);

    pkt = 0;
    memset(cur_case->h2c_pkt_len, 0, sizeof(cur_case->h2c_pkt_len));
    for (i = 0; i < h2c_desc_num; i++) {
        control = 0;
        desc_virt = sub_case->desc_array[i];
        control |= (((al_random_num_gen(0, 1000) % 2) == 1) || ((i == (h2c_desc_num - 1)))) ? SGDMA_DESC_COMPLETED : 0;

        cur_case->h2c_pkt_len[pkt] += sub_case->desc_sz[i];

        if (((al_random_num_gen(0, 1000) % 2) == 1) || (i == (h2c_desc_num - 1))) {
            control |= SGDMA_DESC_EOP;
            pkt++; /* record pkt number */
        }

        sgdma_desc_control_set(desc_virt, control);
    }

    /* create a linked loop */
    sgdma_desc_link(sub_case->desc_array[h2c_desc_num - 1], sub_case->desc_array[0], sub_case->desc_bus_array[0]);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // /* init credit mode */
    // // enable_st_h2c_credit = 1;
    // enable_st_h2c_credit = 0;

    // // w = (0x1 << sub_engine->channel); /* h2c: bit0 ~ 3 */
    // w = (0x0 << sub_engine->channel); /* h2c: bit0 ~ 3 */
    // reg = (struct sgdma_common_regs
    //          *)(sgdev->bar[sgdev->config_bar_idx] +
    //             (0x6 * TARGET_SPACING));

    // write_register(w, &reg->credit_mode_enable_w1s,
    //     (unsigned long)(&reg->credit_mode_enable_w1s) -
    //            (unsigned long)(reg));
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /*
     *
     * config c2h
     *
     * */
    cur_case->data_size = st_desc_data_size_gen_custom_by_h2c_pkt_size(cur_case, is_random, align,
                &cur_case->desc_sz[0], &c2h_desc_num, pkt, cur_case->h2c_pkt_len);

    rv = case_rsc_alloc(cur_case, is_random, align, c2h_desc_num, sgdev);
    if (rv < 0)
        goto out;

    al_pci_test_build_desc_custom(cur_case, c2h_desc_num, &cur_case->desc_sz[0], cur_case->is_stream, &cur_case->mm_ofs[0]);

    for (i = 0; i < c2h_desc_num; i++) {
        desc_virt = cur_case->desc_array[i];
        control = 0;
        control |= (((al_random_num_gen(0, 1000) % 2) == 1) || ((i == (c2h_desc_num - 1)))) ? SGDMA_DESC_COMPLETED : 0;
        sgdma_desc_control_set(desc_virt, control);
    }

    /* create a linked loop */
    sgdma_desc_link(cur_case->desc_array[c2h_desc_num - 1], cur_case->desc_array[0], cur_case->desc_bus_array[0]);

    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    // /* init credit mode */
    // // enable_st_c2h_credit = 1;
    // enable_st_c2h_credit = 0;

    // // w = (0x1 << engine->channel) << 16; /* c2h: bit16 ~ 19 */
    // w = (0x0 << engine->channel) << 16; /* c2h: bit16 ~ 19 */
    // reg = (struct sgdma_common_regs
    //          *)(sgdev->bar[sgdev->config_bar_idx] +
    //             (0x6 * TARGET_SPACING));

    // write_register(w, &reg->credit_mode_enable_w1s,
    //     (unsigned long)(&reg->credit_mode_enable_w1s) -
    //            (unsigned long)(reg));
    /////////////////////////////////////////////////////////////////////////////////////////////////////

    pdata = cur_case->data_virt;

    golden_data = sub_case->data_virt;
    // for (i = 0; i < total_sz /4; i++)
    for (i = 0; i < total_sz; i++)
        // golden_data[i] = (is_random) ? al_random_num_gen(0, 0xff) : i;
        golden_data[i] = i;

    wmb();

    for (i = 0; i <= stop_cnt; i++) {
        uint32_t reg_val_h2c, reg_val_c2h;
        cpu = 0;
        thread_cnt = 0;

        if (i == stop_cnt) {
            cur_case->stop_start_test = 0;
            sub_case->stop_start_test = 0;

        } else {
            cur_case->stop_start_test = 1;
            sub_case->stop_start_test = 1;
        }

        ///////////////////////////////////////////////////////
        reg_val_h2c = read_register(&sub_engine->regs->control);

        write_register( (reg_val_h2c & (~0x1)), &sub_engine->regs->control,
               (unsigned long)(&sub_engine->regs->control) -
                   (unsigned long)(sub_engine->regs));

        reg_val_c2h = read_register(&engine->regs->control);

        write_register( (reg_val_c2h & (~0x1)), &engine->regs->control,
               (unsigned long)(&engine->regs->control) -
                   (unsigned long)(engine->regs));

        timeout = 0;
        do {
            timeout++;
            if (timeout > 100) {
                return 0;
            }
            msleep(100);
            reg_val_h2c = read_register(&sub_engine->regs->status) & 0x1;
            reg_val_c2h = read_register(&engine->regs->status) & 0x1;
        } while (reg_val_h2c | reg_val_c2h);

        if (i == stop_cnt) {
            sub_case->enable_credit = 1;
            cur_case->enable_credit = 1;
            reg = (struct sgdma_common_regs
                   *)(sgdev->bar[sgdev->config_bar_idx] +
                        (0x6 * TARGET_SPACING));
            write_register(0x00010001, &reg->credit_mode_enable,
                (unsigned long)(&reg->credit_mode_enable) -
                    (unsigned long)(reg));

        } else {
            sub_case->enable_credit = 0;
            cur_case->enable_credit = 0;
            reg = (struct sgdma_common_regs
                   *)(sgdev->bar[sgdev->config_bar_idx] +
                        (0x6 * TARGET_SPACING));
            write_register(0x0, &reg->credit_mode_enable,
                (unsigned long)(&reg->credit_mode_enable) -
                    (unsigned long)(reg));
        }

        //start h2c & c2h again
        write_register(reg_val_h2c, &sub_engine->regs->control,
               (unsigned long)(&sub_engine->regs->control) -
                   (unsigned long)(sub_engine->regs));

        write_register(reg_val_c2h, &engine->regs->control,
               (unsigned long)(&engine->regs->control) -
                   (unsigned long)(engine->regs));

        ///////////////////////////////////////////////////////
        printk("stop_cnt i %d %d\n", stop_cnt, i);
        /*
        * init thread
        */
		cur_case->run_status = 1;
		sub_case->run_status = 1;
	   	h2c_kthread = kthread_run_node(h2c_tx_thread, sub_case, "h2c_tx_thread", sub_case->cpu);
		if (!h2c_kthread) {
			return -ECHILD;
		}
		c2h_kthread = kthread_run_node(c2h_rx_thread, cur_case, "c2h_rx_thread", cur_case->cpu);
		if (!c2h_kthread) {
			return -ECHILD;
		}

        wake_up_process(h2c_kthread);
        if (thread_delay_ms) msleep(thread_delay_ms);
        wake_up_process(c2h_kthread);

        msleep(al_random_num_gen(1000, 20000));

		while (cur_case->run_status != 2 || sub_case->run_status != 2)
			msleep(1);

#if 0
        //stop h2c and c2h
        reg_val_h2c = read_register(&sub_engine->regs->control);

        write_register( (reg_val_h2c & (~0x1)), &sub_engine->regs->control,
               (unsigned long)(&sub_engine->regs->control) -
                   (unsigned long)(sub_engine->regs));

        reg_val_c2h = read_register(&engine->regs->control);

        write_register( (reg_val_c2h & (~0x1)), &engine->regs->control,
               (unsigned long)(&engine->regs->control) -
                   (unsigned long)(engine->regs));

        //start h2c & c2h again
        write_register(reg_val_h2c, &sub_engine->regs->control,
               (unsigned long)(&sub_engine->regs->control) -
                   (unsigned long)(sub_engine->regs));

        write_register(reg_val_c2h, &engine->regs->control,
               (unsigned long)(&engine->regs->control) -
                   (unsigned long)(engine->regs));

        TEST_DBG(cur_case, "stop here, stop_cnt = %d\n", i);
#endif
    };

    for (i = 0; i < pkt; i++)
        TEST_DBG(cur_case, "h2c pkt[%d] len 0x%x\n", i, cur_case->h2c_pkt_len[i]);

    /* step3: check write back data */
    ret = desc_comp_wb_chek(cur_case, sub_engine, h2c_desc_num);
    if (ret == false)
        goto test_failed;

    ret = desc_comp_wb_chek(cur_case, engine, c2h_desc_num);
    if (ret == false)
        goto test_failed;

    pkt_idx = 0;
    pkt_len = 0;
    pkt_offset = 0;

    ret = do_data_check_1(sub_case, cur_case);
#if 1
    for (i = 0; i < c2h_desc_num; i++) {
        /* Foreach stream result write back addr until find the last desc. */
        if ((cur_case->res_array[i]->status & RX_STATUS_EOP) != 0) {
            uint8_t *pbuf = (uint8_t *)cur_case->data_array[i];

            if (cur_case->res_array[i]->length == 0) {
                ret = false;
                TEST_ERR(cur_case, "st desc[%d] wb length: 0x%x\n",
                        i, cur_case->res_array[i]->length);
                goto test_failed;
            }
            TEST_DBG(cur_case, "[%d]: pkt_len=0x%x res_array[i]->length=0x%x \n", i, pkt_len, cur_case->res_array[i]->length);

            ret = do_data_check(cur_case, cur_case->res_array[i]->length, &golden_data[pkt_offset], pbuf);

            if (ret == false) {
                TEST_ERR(cur_case, "pkt[%d] data check failed in desc %d\n", pkt_idx, i);
                goto test_failed;
            }

            pkt_len += cur_case->res_array[i]->length;
            pkt_offset += cur_case->res_array[i]->length;

            is_find_eop = true;

        } else {
            uint8_t *pbuf = (uint8_t *)cur_case->data_array[i];

            if (cur_case->res_array[i]->length == 0) {
                ret = false;
                TEST_ERR(cur_case, "st desc[%d] wb length: 0x%x\n",
                        i, cur_case->res_array[i]->length);
                goto test_failed;
            }
            TEST_DBG(cur_case, "[%d]: pkt_len=0x%x res_array[i]->length=0x%x \n", i, pkt_len, cur_case->res_array[i]->length);

            ret = do_data_check(cur_case, cur_case->res_array[i]->length, &golden_data[pkt_offset], pbuf);

            if (ret == false) {
                TEST_ERR(cur_case, "pkt[%d] data check failed in desc %d\n", pkt_idx, i);
                goto test_failed;
            }

            pkt_len += cur_case->res_array[i]->length;
            pkt_offset += cur_case->res_array[i]->length;
        }

        if (is_find_eop) {
            if (pkt_len != cur_case->h2c_pkt_len[pkt_idx]) {
                TEST_ERR(cur_case, "pkt[%d] length check failed, h2c_pkt_len: 0x%02x, c2h_pkt_len: 0x%02x\n",
                    pkt_idx, cur_case->h2c_pkt_len[pkt_idx], pkt_len);
                goto test_failed;
            }

            is_find_eop = false;
            pkt_len = 0;
            pkt_idx++;
        }
    }
#endif

test_failed:
    TEST_DBG(cur_case, "checked c2h pkt cnt %d, h2c pkt num %d\n", pkt_idx, pkt);

	if (h2c_kthread) {
		printk("h2c_kthread kthread_stop");
		h2c_kthread = NULL;
	}

	if (c2h_kthread) {
		printk("c2h_kthread kthread_stop");
		c2h_kthread = NULL;
	}
out:
    sgdma_engine_stop(sub_engine);
    sub_engine->running = 0;
    sgdma_engine_stop(engine);
    engine->running = 0;

    case_rsc_free(cur_case, sgdev);
    desc_data_size_clr(cur_case);

    case_rsc_free(sub_case, sgdev);
    desc_data_size_clr(sub_case);

    TEST_RET(cur_case, ret, "\n");
}


C2H_ST_CASE("sgdma st case34_0", case34_0)
{
    bool ret = false;
    TEST_RET(cur_case, ret, "\n");
}

C2H_ST_CASE("sgdma st case34_1", case34_1)
{
    bool ret = false;
    TEST_RET(cur_case, ret, "\n");
}

C2H_ST_CASE("sgdma st case34_2", case34_2)
{
    bool ret = false;
    TEST_RET(cur_case, ret, "\n");
}


H2C_ST_CASE("sgdma st case37_sub", case37_sub)
{
    TEST_RET(cur_case, true, "\n");
}

C2H_ST_CASE("sgdma st case37", case37)
{
	struct anlogic_dma_engine *engine = cur_case->engine;
	struct al_test_case *sub_case = cur_case->next;
	struct anlogic_dma_engine *sub_engine = sub_case->engine;
	struct anlogic_dev *sgdev = engine->sgdev;
    struct sgdma_poll_wb *wb_data;
    struct sgdma_common_regs *reg;
    uint32_t control = 0, status, next_adj, w, total_sz = TEST_DATA_TOTAL_SIZE;
    uint32_t desc_num = TEST_DESC_NUM, is_random = 0, thread_delay_ms = 0, align = 0;
    char prefix[64], err_info[256] = {0};
    bool ret = true;
    int i, rv;
    struct task_struct *h2c_kthread, *c2h_kthread;
    uint8_t *golden_data, *pdata;
    int cpu, thread_cnt = 0;

    DBG_FORMART_INT_ARG_WTIH_RET(argv[0], desc_num, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[1], is_random, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[2], thread_delay_ms, 10, false);
    DBG_FORMART_INT_ARG_WTIH_RET(argv[3], align, 10, false);

    TEST_DBG(cur_case, "desc_num: %d, is_random: %d, offset: %d\n", desc_num, is_random, thread_delay_ms);

    cur_case->data_size += desc_data_size_gen_custom_total_size(desc_num, is_random, 64,
            &cur_case->desc_sz[0], &cur_case->mm_ofs[0], total_sz, 0);

    rv = case_rsc_alloc(cur_case, is_random, align, desc_num, sgdev);
    if (rv < 0)
        goto out;

    al_pci_test_build_desc_custom(cur_case, desc_num, &cur_case->desc_sz[0], cur_case->is_stream, &cur_case->mm_ofs[0]);

    /* create a linked loop */
    sgdma_desc_link(cur_case->desc_virt + desc_num - 1, cur_case->desc_virt, cur_case->desc_bus);

    /* init credit mode */
    cur_case->enable_credit = 1;

    w = (0x1 << engine->channel) << 16; /* c2h: bit16 ~ 19 */
    reg = (struct sgdma_common_regs
             *)(sgdev->bar[sgdev->config_bar_idx] +
                (0x6 * TARGET_SPACING));

    write_register(w, &reg->credit_mode_enable_w1s,
        (unsigned long)(&reg->credit_mode_enable_w1s) -
               (unsigned long)(reg));

    /*
     *
     * config h2c
     *
     * */
    sub_case->data_size += desc_data_size_gen_custom_total_size(desc_num, is_random, align,
            &sub_case->desc_sz[0], &sub_case->mm_ofs[0], total_sz, 0);

    rv = case_rsc_alloc(sub_case, is_random, align, desc_num, sgdev);
    if (rv < 0)
        goto out;

    al_pci_test_build_desc_custom(sub_case, desc_num, &sub_case->desc_sz[0], sub_case->is_stream, &sub_case->mm_ofs[0]);

    for (i = 0; i < (desc_num - 1); i++) {
        control = 0;
        control |= ((al_random_num_gen(0, 1000) % 2) == 1) ? SGDMA_DESC_EOP : 0;
        control |= ((al_random_num_gen(0, 1000) % 2) == 1) ? SGDMA_DESC_COMPLETED : 0;
        sgdma_desc_control_set(sub_case->desc_array[i], control);
    }

    /* create a linked loop */
    sgdma_desc_link(sub_case->desc_virt + desc_num - 1, sub_case->desc_virt, sub_case->desc_bus);

    /* init credit mode */
    sub_case->enable_credit = 1;

    w = (0x1 << sub_engine->channel); /* h2c: bit0 ~ 3 */
    reg = (struct sgdma_common_regs
             *)(sgdev->bar[sgdev->config_bar_idx] +
                (0x6 * TARGET_SPACING));

    write_register(w, &reg->credit_mode_enable_w1s,
        (unsigned long)(&reg->credit_mode_enable_w1s) -
               (unsigned long)(reg));

    wmb();

	cur_case->run_status = 1;
	sub_case->run_status = 1;

	h2c_kthread = kthread_run_node(h2c_tx_thread, sub_case, "h2c_tx_thread", sub_case->cpu);
    if (!h2c_kthread) {
        return -ECHILD;
    }
    c2h_kthread = kthread_run_node(c2h_rx_thread, cur_case, "c2h_rx_thread", cur_case->cpu);
    if (!c2h_kthread) {
        return -ECHILD;
    }

    pdata = cur_case->data_virt;

    golden_data = sub_case->data_virt;
    for (i = 0; i < cur_case->data_size; i++)
        golden_data[i] = (is_random) ? al_random_num_gen(0, 0xff) : i;

    wake_up_process(h2c_kthread);
    if (thread_delay_ms) msleep(thread_delay_ms);
    wake_up_process(c2h_kthread);

    msleep(5000);

	while (cur_case->run_status != 2 || sub_case->run_status != 2)
		msleep(1);

    ret = true;

    /* do data check */
    for (i = 0; i < total_sz; i++)
        if (golden_data[i] != pdata[i]) {
#define DUMP_RANGE 512
            if (i < DUMP_RANGE) {
                sprintf(prefix, "target(base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i): total_sz, true);
                sprintf(prefix, "got   (base: 0x%x) ", 0);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[0], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE + i) : total_sz, true);
            } else {
                sprintf(prefix, "target(base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &golden_data[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
                sprintf(prefix, "got   (base: 0x%x) ", i-DUMP_RANGE);
                print_hex_dump(KERN_INFO, prefix, DUMP_PREFIX_OFFSET, 16, 1, &pdata[i-DUMP_RANGE], ((total_sz - i) > DUMP_RANGE) ? (DUMP_RANGE * 2) : (DUMP_RANGE + total_sz - i), true);
            }

            TEST_ERR(cur_case, "mem read and write data check failed, target: 0x%02x, got: 0x%02x, offset: 0x%08x\n",
                golden_data[i], pdata[i], i);
            ret = false;
            goto test_failed;
        }

test_failed:
	if (h2c_kthread) {
		printk("h2c_kthread kthread_stop");
		// kthread_stop(h2c_kthread);
		h2c_kthread = NULL;
	}

	if (c2h_kthread) {
		printk("c2h_kthread kthread_stop");
		// kthread_stop(c2h_kthread);
		c2h_kthread = NULL;
	}
out:
    sgdma_engine_stop(sub_engine);
    sub_engine->running = 0;
    sgdma_engine_stop(engine);
    engine->running = 0;

    case_rsc_free(cur_case, sgdev);
    desc_data_size_clr(cur_case);

    case_rsc_free(sub_case, sgdev);
    desc_data_size_clr(sub_case);

    TEST_RET(cur_case, ret, "\n");
}

void al_pci_case_st_init(struct al_dbg_attr *aldbg)
{
	struct al_tester *tester = &aldbg->tester;
    struct anlogic_dev *sgdev = to_anlogic_sgdev(tester->dev);
	static struct anlogic_dma_engine *h2c_engine;
	static struct anlogic_dma_engine *c2h_engine;
    extern unsigned int poll_mode;
	struct al_test_case *testcase;

    h2c_engine = &sgdev->engine_h2c[tester->h2c_eng_num];
    c2h_engine = &sgdev->engine_c2h[tester->c2h_eng_num];

    /* if interrupt mode, alloc wb first */
    if (poll_mode == 0) {
        h2c_engine->poll_mode_addr_virt =
            al_dma_alloc_coherent(&sgdev->pdev->dev,
                        sizeof(struct sgdma_poll_wb),
                        &h2c_engine->poll_mode_bus, GFP_KERNEL);

        c2h_engine->poll_mode_addr_virt =
            al_dma_alloc_coherent(&sgdev->pdev->dev,
                        sizeof(struct sgdma_poll_wb),
                        &c2h_engine->poll_mode_bus, GFP_KERNEL);
    }

	if (!h2c_engine->poll_mode_addr_virt || !c2h_engine->poll_mode_addr_virt) {
		pr_err("malloc poll mode addr failed\n");
		return;
	}

	testcase = kmalloc(sizeof(struct al_test_case) * 8, GFP_KERNEL);
	if (!testcase) {
		pr_err("malloc test cases failed\n");
		return;
	};

	memset(testcase, 0, sizeof(struct al_test_case) * 8);

	H2C_ST_CASE_INIT(&testcase[0], aldbg, "sgdma(mm) sim: [case30_2_sub]", case30_2_sub, &testcase[1], false);
	C2H_ST_CASE_INIT(&testcase[1], aldbg, "sgdma st case30_2", case30_2, &testcase[0], true);

	H2C_ST_CASE_INIT(&testcase[2], aldbg, "sgdma(mm) sim: [case33_2_sub]", case33_2_sub, &testcase[3], false);
	C2H_ST_CASE_INIT(&testcase[3], aldbg, "sgdma st case33_2", case33_2, &testcase[2], true);

	H2C_ST_CASE_INIT(&testcase[4], aldbg, "sgdma st sim: [case36_sub]", case36_sub, &testcase[5], false);
	C2H_ST_CASE_INIT(&testcase[5], aldbg, "sgdma st case36", case36, &testcase[4], true);

	H2C_ST_CASE_INIT(&testcase[6], aldbg, "sgdma st case37_sub", case37_sub, &testcase[7], false);
	C2H_ST_CASE_INIT(&testcase[7], aldbg, "sgdma st case37", case37, &testcase[6], true);
}
