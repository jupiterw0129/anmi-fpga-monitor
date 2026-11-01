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
#include <linux/random.h>

#include "anlogic_dbg.h"
#include "anlogic_pci_lib.h"
#include "anlogic_pci_drv.h"
#include "anlogic_pci_dbg.h"
#include "anlogic_pci_test.h"
#include "anlogic_ring.h"

#define AL_TEST_VERSION             "v1.0"
#define AL_TEST_COPYRIGHT_YEARS     "2022"
#define AL_TEST_NAME                "Anlogic Driver Tester"

#define AL_DBG_PRINT_SIM_DESC 0

DEFINE_SPINLOCK(reg_spinlock);
static atomic_t start_wait = ATOMIC_INIT(0);

int format_desc(char *buf, int len, struct sgdma_desc *desc_virt)
{
    int offset = 0;

    memset(buf, 0, len);
    offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_virt->bytes)) << 32) | desc_virt->control);
    offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_virt->src_addr_hi)) << 32) | desc_virt->src_addr_lo);
    offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_virt->dst_addr_hi)) << 32) | desc_virt->dst_addr_lo);
    offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_virt->next_hi)) << 32) | desc_virt->next_lo);

    return offset;
}

void format_desc_to_sim(struct sgdma_desc *desc_virt_array[], int cnt, enum dma_data_direction dir)
{
#define AL_SIM_DST_ADDR_START     0x1c001000ULL
#define AL_SIM_SRC_ADDR_START     0x0ULL
#define AL_SIM_DESC_ADDR_START    0x18000000ULL
#define AL_DESC_STR_LEN           256

    struct sgdma_desc desc_sim;
    int offset = 0, i, len = AL_DESC_STR_LEN;
    char buf[AL_DESC_STR_LEN];
    uint64_t src_addr, dst_addr, next_addr;
    struct sgdma_desc *desc_virt;

    if (dir == DMA_FROM_DEVICE) {
        src_addr = AL_SIM_SRC_ADDR_START;
        dst_addr = AL_SIM_DST_ADDR_START;
    } else {
        src_addr = AL_SIM_DST_ADDR_START;
        dst_addr = AL_SIM_SRC_ADDR_START;
    }

    next_addr = AL_SIM_DESC_ADDR_START + sizeof(struct sgdma_desc);

    for (i = 0; i < cnt; i++) {
        desc_virt = desc_virt_array[i];
        memcpy(&desc_sim, desc_virt, sizeof(struct sgdma_desc));
        memset(buf, 0, len);

        desc_sim.src_addr_hi = (src_addr & 0xffffffff00000000) >> 32;
        desc_sim.src_addr_lo = src_addr & 0xffffffff;
        desc_sim.dst_addr_hi = (dst_addr & 0xffffffff00000000) >> 32;
        desc_sim.dst_addr_lo = dst_addr & 0xffffffff;

        /* end do not fix. */
        if (i < cnt - 1) {
            desc_sim.next_hi = (next_addr & 0xffffffff00000000) >> 32;
            desc_sim.next_lo = next_addr & 0xffffffff;
        }

        offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_sim.bytes)) << 32) | desc_sim.control);
        offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_sim.src_addr_hi)) << 32) | desc_sim.src_addr_lo);
        offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_sim.dst_addr_hi)) << 32) | desc_sim.dst_addr_lo);
        offset += snprintf(&buf[offset], len - offset, "%016llx\n", (((uint64_t)(desc_sim.next_hi)) << 32) | desc_sim.next_lo);

        printk("%s", buf);

        /* update next addr. */
        offset = 0;
        dst_addr += desc_virt->bytes;
        next_addr += sizeof(struct sgdma_desc);
    }
}

int al_random_num_gen(int min, int max)
{
    uint64_t num;

    if (min >= max) {
        return min;
    }

    get_random_bytes(&num, sizeof(num));

    return min + (num % (max - min));
}

#define ZERO_DATA_LEN 1

bool al_do_data_check(struct al_test_case *cur_case, void *buf, int len)
{
    uint64_t *pmem = buf;
    uint64_t except, i;

    for (i = 0, except = 0; i < ZERO_DATA_LEN * sizeof(uint64_t); i += sizeof(uint64_t), pmem++) {
        if (*pmem != 0) {
            TEST_ERR(cur_case, "receive: 0x%016llx expect: 0x%016llx, offset: 0x%016llx\n", *pmem, 0ULL, i);
            return false;
        }
    }

    for (except = 1; i < len; i += sizeof(uint64_t), except++, pmem++) {
        if (*pmem != ((except << 32) | except)) {
            TEST_ERR(cur_case, "receive: 0x%016llx expect: 0x%016llx, offset: 0x%016llx\n", *pmem, ((except << 32) | except), i);
            return false;
        }
    }

    return true;
}

bool al_do_desc_data_check(struct al_test_case *cur_case, struct sgdma_desc *desc_virt_array[], int cnt)
{
    int desc_idx = 0;
    uint64_t except = 0, receive, total_bytes = 0, i;
    uint64_t *dst_virt;
    struct sgdma_desc   *desc_virt;
    struct sgdma_result *res_virt;

    desc_virt   = desc_virt_array[desc_idx];
    dst_virt = __va(((uint64_t)desc_virt->dst_addr_hi << 32) | desc_virt->dst_addr_lo);
    /* ???? */
    total_bytes = (cur_case->is_stream) ? res_virt->length : desc_virt->bytes;

    if (total_bytes == 0) {
        return false;
    }

    for (i = 0, except = 0; i < ZERO_DATA_LEN * sizeof(uint64_t); i += sizeof(uint64_t), dst_virt++) {

        receive = *dst_virt;
        if (receive != 0) {
            TEST_ERR(cur_case, "receive: 0x%016llx expect: 0x%016llx, offset: 0x%016llx, desc: %d\n", receive, 0ULL, i, desc_idx);
            return false;
        }

        if (i >= total_bytes) {
            desc_idx++;

            if (desc_idx >= cnt) {
                return true;
            }

            desc_virt   = desc_virt_array[desc_idx];
            res_virt = cur_case->res_array[desc_idx];

            dst_virt = __va(((uint64_t)desc_virt->dst_addr_hi << 32) | desc_virt->dst_addr_lo);
            total_bytes = (cur_case->is_stream) ? res_virt->length : desc_virt->bytes;
        }
    }

    except = 1;

    while (desc_idx < cnt) {

        receive = *dst_virt;

        if (receive != ((except << 32) | except)) {
            TEST_ERR(cur_case, "receive: 0x%016llx expect: 0x%016llx, offset: 0x%016llx, desc: %d\n",
                    receive, ((except << 32) | except), i, desc_idx);
            return false;
        }

        i += sizeof(uint64_t);
        except++;
        dst_virt++;

        if (i >= total_bytes) {
            desc_idx++;

            if (desc_idx >= cnt) {
                return true;
            }

            desc_virt  = desc_virt_array[desc_idx];
            res_virt   = cur_case->res_array[desc_idx];

            dst_virt = __va(((uint64_t)desc_virt->dst_addr_hi << 32) | desc_virt->dst_addr_lo);
            total_bytes += (cur_case->is_stream) ? res_virt->length : desc_virt->bytes;
        }
    }

    return true;
}


bool al_do_h2c_data_check(struct al_test_case *cur_case)
{
#define H2C_ERR_NUM_CNT_REG 0x80004

    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);
    uint32_t w;

    w = read_register(sgdev->bar[0] + H2C_ERR_NUM_CNT_REG);

    //al_dbg_printk("h2c err data desc_num: %u\n", w);
    sprintf(cur_case->err_info, "h2c err data count: %u\n", w);

    return (w == 0) ? true : false;
}

inline void al_pci_test_desc_link(struct sgdma_desc *desc_virt_arrary[], dma_addr_t desc_bus_array[], int desc_num)
{
    int i;
    struct sgdma_desc *desc_virt;
    dma_addr_t desc_bus;

    /* create singly-linked list for SG DMA controller */
    for (i = 0; i < desc_num - 1; i++) {
        desc_virt = desc_virt_arrary[i];

        //next descriptor bus address
        desc_bus  = desc_bus_array[i + 1];

        /* singly-linked list uses bus addresses */
        desc_virt->next_lo = cpu_to_le32(PCI_DMA_L(desc_bus));
        desc_virt->next_hi = cpu_to_le32(PCI_DMA_H(desc_bus));
        desc_virt->bytes   = cpu_to_le32(0);
        desc_virt->control = cpu_to_le32(DESC_MAGIC);
    }

    /* { i = number - 1 } */
    /* zero the last descriptor next pointer */
    desc_virt = desc_virt_arrary[desc_num - 1];
    desc_virt->next_lo = cpu_to_le32(0);
    desc_virt->next_hi = cpu_to_le32(0);
    desc_virt->bytes   = cpu_to_le32(0);
    desc_virt->control = cpu_to_le32(DESC_MAGIC);
}


inline void al_pci_test_fill_adj_num(struct sgdma_desc *desc_virt_array[], int desc_num)
{
    int i, ret;
    uint32_t offset = 0;
    struct sgdma_desc *desc_virt;

    /* step5: fill in adjacent numbers */
#ifdef AL_IP_VER0
    u32 next_adj;
    for (i = 0; i < desc_num; i++) {
        desc_virt = desc_virt_array[i];
        next_adj = desc_num - i - 1;

        sgdma_desc_adjacent(desc_virt, next_adj);
    }
#else
    ????
    for (i = 0; i < desc_num; i++) {
        u32 next_adj = sgdma_get_next_adj(desc_num - i - 1,
                        (desc_virt + i)->next_lo);

        dbg_desc("set next adj at index %d to %u\n", i, next_adj);
        sgdma_desc_adjacent(desc_virt + i, next_adj);
    }
#endif
}

#define ALIGN_DATA_SIZE (0x1 << 6)

size_t desc_data_size_gen_custom_total_size(int desc_num, bool is_random, uint32_t align,
        size_t *desc_data_sz, uint64_t *mm_ofs, uint32_t total_sz, uint64_t base)
{
#define DESC_DATA_MIN_SZ (1)

    uint32_t i, mm_start;
    uint32_t random_min = (align) ? align : DESC_DATA_MIN_SZ;
    uint32_t random_max = total_sz / desc_num;
    uint32_t pattern = ((total_sz / desc_num) >> 6) << 6;
    uint32_t remain_bytes = total_sz;
    size_t data_size = 0;

    /* desc_data_sz gen */
    for (i = 0; i < desc_num; i++) {
        if (is_random) {
            if (i == (desc_num - 1)) {
                desc_data_sz[i] = remain_bytes;
                break;
            }

            desc_data_sz[i] = al_random_num_gen(random_min, random_max);
            remain_bytes -= desc_data_sz[i];

        } else {
            if (i == (desc_num - 1)) {
                desc_data_sz[i] = pattern + (total_sz % desc_num);
                break;
            }

            desc_data_sz[i] = pattern;
        }
    }

    /*mm_ofs: memory offset*/
    mm_ofs[0] = base;
    data_size += desc_data_sz[0] + ALIGN_DATA_SIZE; /*0x40: reserve data gap between each descr data*/
    for (i = 1; i < desc_num; i++) {
        /* do not overrise last mm range */
        mm_start = mm_ofs[i - 1] + desc_data_sz[i - 1] + ALIGN_DATA_SIZE; /*0x40: data gap between each descr data*/
        mm_ofs[i] = mm_start;
        data_size += desc_data_sz[i] + ALIGN_DATA_SIZE;
    }

    return (data_size + 4 * 1024);
}


size_t st_desc_data_size_gen_custom_by_h2c_pkt_size(struct al_test_case *cur_case, bool is_random, uint32_t align, size_t *desc_data_sz, int *c2h_desc_num,
                int h2c_pkt_num, uint32_t *h2c_pkt_len)
{
#define DESC_DATA_MIN_SZ (1)

    uint32_t i, j;
    uint32_t random_min = (align) ? align : DESC_DATA_MIN_SZ;
    uint32_t random_max;
    uint32_t pattern, total_last_len = 0;
    size_t data_size = 0;
    int desc_num = 0, remain_bytes;

    /* desc_data_sz gen */
    for (i = 0; i < h2c_pkt_num; i++) {
        if (is_random) {

            random_min   = (align) ? align : DESC_DATA_MIN_SZ;
            random_max   = h2c_pkt_len[i];
            remain_bytes = h2c_pkt_len[i];

            while (1) {
                desc_data_sz[desc_num] = (align) ? ((al_random_num_gen(random_min, random_max) >> 6) << 6) :
                                         al_random_num_gen(random_min, random_max);

                total_last_len += desc_data_sz[desc_num];

                TEST_DBG(cur_case, "c2h_desc[%d]: sz 0x%zx\n", desc_num, desc_data_sz[desc_num]);

                if (remain_bytes > desc_data_sz[desc_num]) {
                    remain_bytes -= desc_data_sz[desc_num];
                    desc_num++;
                } else {
                    desc_num++;
                    TEST_DBG(cur_case, "h2c pkt[%d] sz 0x%x full cover, c2h desc total len 0x%x\n", i, h2c_pkt_len[i], total_last_len);
                    total_last_len = 0;
                    break;
                }
            }
        } else {
            desc_num = h2c_pkt_num;
            pattern = h2c_pkt_len[0];
            for (j = 1; j < h2c_pkt_num; j++)
                pattern = (pattern > h2c_pkt_len[j]) ? pattern : h2c_pkt_len[j];

            pattern = (align) ? (((pattern + 64UL) >> 6) << 6) : pattern;

            for (j = 0; j < desc_num; j++)
                desc_data_sz[j] = pattern;
        }
    }

    TEST_DBG(cur_case, "c2h_desc gen info: num %d, is_random %d, align %d\n", desc_num, is_random, align);
    data_size += desc_data_sz[0];
    for (i = 0; i < desc_num; i++) {
        data_size += desc_data_sz[i];
    }

    *c2h_desc_num = desc_num;

    return data_size + 4 * 1024;
}

int case_rsc_alloc(struct al_test_case *cur_case, bool is_random, uint32_t align, int desc_num, struct anlogic_dev *sgdev)
{
    bool ret = true;
    int i = 0;
    uint32_t offset = 0;
    int random_min = (align) ? align : DESC_DATA_MIN_SZ;
    int random_max = ALIGN_DATA_SIZE;

    //description: desc_virt, desc_array
    if (cur_case->desc_virt == NULL) {
        cur_case->desc_size = (sizeof(struct sgdma_desc) + ALIGN_DATA_SIZE) * desc_num;
        cur_case->desc_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->desc_size, &cur_case->desc_bus, GFP_KERNEL);

        if (cur_case->desc_virt == NULL) {
            TEST_ERR(cur_case, "pci desc alloc consistent failed.\n");
            ret = false;
            goto out3;
        }
        memset(cur_case->desc_virt, 0, cur_case->desc_size);

        TEST_DBG(cur_case, "desc_virt: 0x%pK \r\n", cur_case->desc_virt);

        for (i = 0; i < desc_num; i++) {
            cur_case->desc_array[i]     = cur_case->desc_virt + offset;
            cur_case->desc_bus_array[i] = cur_case->desc_bus + offset;

            TEST_DBG(cur_case, "desc_num[%d] 0x%pK 0x%016llx 0x%x 0x%pK 0x%016llx \r\n", i,
                    cur_case->desc_virt, cur_case->desc_bus, offset,
                    cur_case->desc_array[i], cur_case->desc_bus_array[i]);

            offset += (sizeof(struct sgdma_desc) > 32 ? sizeof(struct sgdma_desc) : 32);
        }
    }

    TEST_DBG(cur_case, "\r\n\r\n\r\n");
    //data: data_virt, data_array, data_bus_array
    if (cur_case->data_virt == NULL) {
        cur_case->data_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->data_size, &cur_case->data_bus, GFP_KERNEL);
        if (cur_case->data_virt == NULL) {
            TEST_ERR(cur_case, "pci data alloc data buf failed.\n");
            ret = false;
            cur_case->data_virt = NULL;
            cur_case->data_bus = 0;
            cur_case->data_size = 0;
            goto out1;
        }

        offset = 0;
        for (i = 0; i < desc_num; i++) {
            cur_case->data_array[i]     = cur_case->data_virt + offset;
            cur_case->data_bus_array[i] = cur_case->data_bus + offset;

            TEST_DBG(cur_case, "data_array: %d 0x%pK 0x%016llx\r\n", i,
                    cur_case->data_array[i], cur_case->data_bus_array[i]);

            //offset += cur_case->desc_sz[i] + ((is_random) ? al_random_num_gen(random_min, random_max) : 0);
			offset += cur_case->desc_sz[i];
        }
    }

    TEST_DBG(cur_case, "\r\n\r\n\r\n");

    //result
    if (cur_case->res_virt == NULL && cur_case->is_stream) {
        cur_case->res_size = (sizeof(struct sgdma_result) + ALIGN_DATA_SIZE *2) * desc_num;
        cur_case->res_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->res_size, &cur_case->res_bus, GFP_KERNEL);
        if (cur_case->res_virt == NULL) {
            TEST_ERR(cur_case, "pci data alloc data buf failed.\n");
            ret = false;
            cur_case->res_virt = NULL;
            cur_case->res_bus = 0;
            cur_case->res_size = 0;
            goto out0;
        }

        TEST_DBG(cur_case, "desc_virt: 0x%pK \r\n", cur_case->res_virt);

        offset = 0;
        for (i = 0; i < desc_num; i++) {
            cur_case->res_array[i]     = cur_case->res_virt + offset;
            cur_case->res_bus_array[i] = cur_case->res_bus + offset;

            TEST_DBG(cur_case, "res_array[%d] 0x%pK 0x%016llx %d\r\n", i,
                    cur_case->res_array[i], cur_case->res_bus_array[i], offset);

            offset += sizeof(struct sgdma_result) + ((is_random) ? al_random_num_gen(random_min, random_max) : 0);
        }
    }

    TEST_DBG(cur_case, "desc_virt:0x%pK data_virt:0x%pK res_virt: 0x%pK \r\n", cur_case->desc_virt, cur_case->data_virt, cur_case->res_virt);

    return 0;

out0:
    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->data_size,
            cur_case->data_virt, cur_case->data_bus);
    cur_case->data_virt = NULL;
    cur_case->data_bus = 0;
    cur_case->data_size = 0;
out1:

out2:
    al_dma_free_coherent(&sgdev->pdev->dev,  cur_case->desc_size,
            cur_case->desc_virt, cur_case->desc_bus);
    cur_case->desc_virt = NULL;
    cur_case->desc_bus = 0;
    cur_case->desc_size = 0;
out3:
    TEST_RET(cur_case, ret, "\n");

    return -ENOMEM;
}

void case_rsc_free(struct al_test_case *cur_case, struct anlogic_dev *sgdev)
{
    if (cur_case->data_virt) {
        al_dma_free_coherent(&sgdev->pdev->dev, cur_case->data_size,
                cur_case->data_virt, cur_case->data_bus);
        cur_case->data_virt = NULL;
        cur_case->data_bus = 0;
        cur_case->data_size = 0;
    }

    if (cur_case->golden_data) {
        kfree(cur_case->golden_data);
        cur_case->golden_data = NULL;
    }

    if (cur_case->desc_virt) {
        al_dma_free_coherent(&sgdev->pdev->dev, cur_case->desc_size,
                cur_case->desc_virt, cur_case->desc_bus);
        cur_case->desc_virt = NULL;
        cur_case->desc_bus = 0;
        cur_case->desc_size = 0;
    }

    if (cur_case->res_virt) {
        al_dma_free_coherent(&sgdev->pdev->dev, cur_case->res_size,
                cur_case->res_virt, cur_case->res_bus);
        cur_case->res_virt = NULL;
        cur_case->res_bus = 0;
        cur_case->res_size = 0;
    }

    enable_st_h2c_credit = 0;
    enable_st_c2h_credit = 0;
}

void desc_data_size_clr(struct al_test_case *cur_case)
{
    cur_case->data_size = 0;
}


void al_pci_test_build_desc_custom(struct al_test_case *cur_case, int desc_num, size_t desc_data_sz[], int is_stream, u64 mm_ofs[])
{
    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);
    struct sgdma_desc *desc_virt;
    struct sgdma_result *res_virt;
    void *data_virt;
    dma_addr_t data_bus, res_bus;
    size_t data_size, res_size;
    uint32_t control = 0;
    int i;

    if (desc_data_sz == NULL)
        return;

    if (!is_stream && mm_ofs == NULL)
        return;

    data_size = cur_case->data_size;
    cur_case->desc_num = desc_num;

    TEST_DBG(cur_case, "resource address: 0x%lx %d\n", data_size, desc_num);

    al_pci_test_desc_link(cur_case->desc_array, cur_case->desc_bus_array, desc_num);

    /* step4: config desc data addr and control filed */
    for (i = 0; i < desc_num; i++) {
        // TEST_DBG(cur_case, "mm_ofs[%d]: %llu\n", i, (is_stream) ? 0 : mm_ofs[i]);
        sgdma_desc_set(cur_case->desc_array[i], cur_case->data_bus_array[i], (is_stream) ? 0 : mm_ofs[i], desc_data_sz[i], cur_case->dir);
        sgdma_desc_control_clear(cur_case->desc_array[i], LS_BYTE_MASK);
    }

    /* stop engine, EOP for AXI ST, req IRQ on last descriptor */
    control = SGDMA_DESC_STOPPED;
    control |= (is_stream) ? SGDMA_DESC_EOP : 0;
    control |= SGDMA_DESC_COMPLETED;
    sgdma_desc_control_set(cur_case->desc_array[desc_num - 1], control);

    if (is_stream && cur_case->dir == DMA_FROM_DEVICE) {
        /* replace source addresses with result write-back addresses */
        for (i = 0; i < desc_num; i++) {
            cur_case->desc_array[i]->src_addr_lo = cpu_to_le32(PCI_DMA_L(cur_case->res_bus_array[i]));
            cur_case->desc_array[i]->src_addr_hi = cpu_to_le32(PCI_DMA_H(cur_case->res_bus_array[i]));
            TEST_DBG(cur_case, "desc_array[%d]: 0x%x %d\n", i,
                        cur_case->desc_array[i]->src_addr_lo, cur_case->desc_array[i]->src_addr_hi);
        }
    }

    TEST_DBG(cur_case, "al_pci_test_fill_adj_num \r\n");
    al_pci_test_fill_adj_num(cur_case->desc_array, desc_num);
}



void al_pci_test_build_desc_no_alloc(struct al_test_case *cur_case, int desc_num, size_t single_size, int is_stream)
{
    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);
    struct sgdma_desc *desc_virt;
    struct sgdma_result *res_virt;
    dma_addr_t data_bus, res_bus;
    void *data_virt;
    size_t data_size, res_size;
    uint32_t control = 0, next_adj;
    int i, ret;

    memset(cur_case->desc_virt, 0, cur_case->desc_size);
    memset(cur_case->res_virt, 0, cur_case->res_size);
    memset(cur_case->data_virt, 0, cur_case->data_size);

#if 0
    res_virt = cur_case->res_virt;
    res_bus = cur_case->res_bus;
    res_size = cur_case->res_size;
    data_virt = cur_case->data_virt;
    data_bus = cur_case->data_bus;
    data_size = cur_case->data_size;
    desc_virt = cur_case->desc_virt;

    TEST_DBG(cur_case, "pci alloc resource success:\n"
        "desc virt 0x%pK bus 0x%016llx\n"
        "data virt 0x%pK bus 0x%016llx\n"
        "res  virt 0x%pK bus 0x%016llx\n",
        desc_virt, cur_case->desc_bus,
        data_virt, data_bus,
        res_virt, res_bus);
#endif

    al_pci_test_desc_link(cur_case->desc_array, cur_case->desc_bus_array, desc_num);

    /* step4: config desc data addr and control filed */
    for (i = 0; i < desc_num; i++) {
        sgdma_desc_set(cur_case->desc_array[i], data_bus + single_size * i, (is_stream) ? 0 : (single_size * i), single_size, cur_case->dir);
        sgdma_desc_control_clear(cur_case->desc_array[i], LS_BYTE_MASK);
    }

    /* stop engine, EOP for AXI ST, req IRQ on last descriptor */
    control = SGDMA_DESC_STOPPED;
    control |= SGDMA_DESC_EOP;
    control |= SGDMA_DESC_COMPLETED;
    sgdma_desc_control_set(cur_case->desc_array[desc_num - 1], control);

    if (is_stream && cur_case->dir == DMA_FROM_DEVICE) {
        /* replace source addresses with result write-back addresses */
        for (i = 0; i < desc_num; i++) {
            cur_case->desc_array[i]->src_addr_lo = cpu_to_le32(PCI_DMA_L(cur_case->res_bus_array[i]));
            cur_case->desc_array[i]->src_addr_hi = cpu_to_le32(PCI_DMA_H(cur_case->res_bus_array[i]));
        }
    }

    al_pci_test_fill_adj_num(cur_case->desc_array, desc_num);

    if (cur_case->dir == DMA_TO_DEVICE)
        al_do_h2c_data_fill(cur_case->data_virt, cur_case->data_size, AL_H2C_DATA_WIDTH, 0);
}

int al_pci_test_build_desc(struct al_test_case *cur_case, int desc_num, size_t single_size, int is_stream)
{
    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);
    uint32_t offset = 0;
    int     i;
    int     ret;

    /* step1: alloc transfer desc */
    if (cur_case->desc_virt == NULL) {
        cur_case->desc_size = sizeof(struct sgdma_desc) * desc_num;
        cur_case->desc_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->desc_size, &cur_case->desc_bus, GFP_KERNEL);
        if (cur_case->desc_virt == NULL) {
            TEST_ERR(cur_case, "pci desc alloc consistent failed.\n");
            return -ENOMEM;
        }
        memset(cur_case->desc_virt, 0, cur_case->desc_size);

        for (i = 0; i < desc_num; i++) {
            cur_case->desc_array[i]     = cur_case->desc_virt + offset;
            cur_case->desc_bus_array[i] = cur_case->desc_bus + offset;
            offset += sizeof(struct sgdma_desc);
        }
    }

    /* step2: alloc transfer data buf */
    if (cur_case->data_virt == NULL) {
        cur_case->data_size = single_size * desc_num;
        cur_case->data_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->data_size, &cur_case->data_bus, GFP_KERNEL);
        if (cur_case->data_virt == NULL) {
            TEST_ERR(cur_case, "pci data alloc consistent failed.\n");
            ret = false;
            goto out1;
        }
        memset(cur_case->data_virt, 0, cur_case->data_size);
        offset = 0;
        for (i = 0; i < desc_num; i++) {
            cur_case->data_array[i]     = cur_case->data_virt + offset;
            cur_case->data_bus_array[i] = cur_case->data_bus + offset;
            offset += cur_case->desc_sz[i];
        }
    }

    /* step3: alloc stream wb res */
    if (cur_case->res_virt == NULL && cur_case->is_stream) {
        cur_case->res_size = sizeof(struct sgdma_result) * desc_num;
        cur_case->res_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->res_size, &cur_case->res_bus, GFP_KERNEL);
        if (cur_case->res_virt == NULL) {
            TEST_ERR(cur_case, "pci result alloc consistent failed.\n");
            ret = false;
            goto out2;
        }
        memset(cur_case->res_virt, 0, cur_case->res_size);

        offset = 0;
        for (i = 0; i < desc_num; i++) {
            cur_case->res_array[i]     = cur_case->res_virt + offset;
            cur_case->res_bus_array[i] = cur_case->res_bus + offset;
            offset += sizeof(struct sgdma_result);
        }
    }

    al_pci_test_build_desc_no_alloc(cur_case, desc_num, single_size, is_stream);

    return 0;
out2:
    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->desc_size, cur_case->desc_virt, cur_case->desc_bus);
out1:
    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->data_size, cur_case->data_virt, cur_case->data_bus);

    return -ENOMEM;
}

void al_pci_test_free_desc(struct al_test_case *cur_case)
{
    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);

    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->desc_size, cur_case->desc_virt, cur_case->desc_bus);
    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->res_size, cur_case->res_virt, cur_case->res_bus);
    al_dma_free_coherent(&sgdev->pdev->dev, cur_case->data_size, cur_case->data_virt, cur_case->data_bus);

    cur_case->desc_virt = NULL;
    cur_case->desc_bus = 0;
    cur_case->desc_size = 0;

    cur_case->res_virt = NULL;
    cur_case->res_bus = 0;
    cur_case->res_size = 0;

    cur_case->data_virt = NULL;
    cur_case->data_bus = 0;
    cur_case->data_size = 0;
}

int al_pci_test_engine_do_transfer_with_no_stop(struct al_test_case *cur_case,
                                                    int count, int is_stop)
{
	struct anlogic_dma_engine *engine = cur_case->engine;
    int i, status, rv = 0;
    uint32_t next_adj, extra_adj;
    char desc_str[256];
    struct sgdma_poll_wb *wb_data;

    if (poll_mode) {
        /* clear pool addr cnt */
        wb_data = (struct sgdma_poll_wb *)engine->poll_mode_addr_virt;
        wb_data->completed_desc_count = 0;
    }

    /* step4: calc adjacent numbers */
#if 0
    for (i = 0; i < count; i++) {
        next_adj = sgdma_get_next_adj(count - i - 1,
                        (cur_case->desc_virt + i)->next_lo);
    }
#endif

    /* step5: config sgdma regs */
    #ifdef __REG_DEBUG__
    pr_info("%s(%d): %s write first desc\n", __func__, __LINE__, engine->name);
    #endif

    write_register(cpu_to_le32(PCI_DMA_L(cur_case->desc_bus_array[0])),
            &engine->sgdma_regs->first_desc_lo,
            (unsigned long)(&engine->sgdma_regs->first_desc_lo) -
                (unsigned long)(engine->sgdma_regs));

    write_register(cpu_to_le32(PCI_DMA_H(cur_case->desc_bus_array[0])),
            &engine->sgdma_regs->first_desc_hi,
            (unsigned long)(&engine->sgdma_regs->first_desc_hi) -
                (unsigned long)(engine->sgdma_regs));

#ifdef AL_IP_VER0
    if (count > 2) {
        extra_adj = count - 2;
        if (extra_adj > MAX_EXTRA_ADJ) {
            extra_adj = MAX_EXTRA_ADJ;
        }
    } else {
        extra_adj = 0;
    }

    write_register(cpu_to_le32(extra_adj),
            &engine->sgdma_regs->first_desc_adjacent,
            (unsigned long)(&engine->sgdma_regs->first_desc_adjacent) -
                (unsigned long)(engine->sgdma_regs));
#else
    next_adj = sgdma_get_next_adj(count, cpu_to_le32(PCI_DMA_L(cur_case->desc_bus)));
    write_register(cpu_to_le32(next_adj),
            &engine->sgdma_regs->first_desc_adjacent,
            (unsigned long)(&engine->sgdma_regs->first_desc_adjacent) -
                (unsigned long)(engine->sgdma_regs));
#endif
    /* dump desc */
    for (i = 0; i < count; i++) {
        dump_desc(cur_case->desc_array[i]);
    }

#if AL_DBG_PRINT_SIM_DESC
    format_desc_to_sim(cur_case->desc_virt, count, engine->dir);
#endif

#if 0
    if ((engine->dir == DMA_FROM_DEVICE) ? enable_st_c2h_credit : enable_st_h2c_credit) {
        write_register(count,
                    &engine->sgdma_regs->credits,
                    (unsigned long)(&engine->sgdma_regs->credits) - (unsigned long)(engine->sgdma_regs));
    }
#endif

    #ifdef __REG_DEBUG__
    pr_info("%s(%d): %s write first desc\n", __func__, __LINE__, engine->name);
    #endif

    /* step6: start engine */
    engine_start_mode_config(engine);
    engine->running = 1;

    if (is_stop) {
        /* wait some times */
        msleep(2000);
        status = read_register(&engine->regs->status);
        TEST_DBG(cur_case, "engine %s status = 0x%08x\n", engine->name, status);

        /* stop transfer */
        sgdma_engine_stop(engine);
        engine->running = 0;
    }

    return rv;
}

int al_pci_test_engine_do_transfer(struct al_test_case *cur_case, int count)
{
    return al_pci_test_engine_do_transfer_with_no_stop(cur_case, count, 1);
}

bool al_stream_transfer_test(struct al_test_case *cur_case)
{
#undef  TEST_DATA_SIZE
#undef  TEST_DESC_NUM
#undef  TEST_DATA_DUMP_SIZE
#define TEST_DATA_SIZE      0x1000
#define TEST_DESC_NUM       500
#define TEST_DATA_DUMP_SIZE 0x100

    struct anlogic_dev *sgdev = to_anlogic_sgdev(cur_case->dbg_attr->dev);
    struct anlogic_dma_engine *engine = cur_case->engine;
    volatile struct sgdma_poll_wb *wb_data;
    struct sgdma_desc *desc_virt;
    struct sgdma_result *res_virt;
    dma_addr_t desc_bus, data_bus, res_bus;
    size_t data_size, res_size;
    uint32_t control = 0, status, next_adj, w;
    uint64_t ep_addr = 0;
    char *data_virt;
    char prefix[64];
    bool ret = true;
    int i, rv, num;

    /* step1: build desc */
    rv = al_pci_test_build_desc(cur_case, TEST_DESC_NUM, TEST_DATA_SIZE, 1);
    if (rv < 0) {
        ret = false;
        goto out1;
    }

#if 0
    desc_virt = cur_case->desc_virt;
    data_virt = cur_case->data_virt;
    res_virt = cur_case->res_virt;
    desc_bus = cur_case->desc_bus;
    data_bus = cur_case->data_bus;
    res_bus = cur_case->res_bus;
#endif

    /* add all desc comp flag */
    for (i = 0; i < TEST_DESC_NUM - 1; i++) {
        sgdma_desc_control_set(cur_case->desc_array[i], SGDMA_DESC_COMPLETED);
    }

    /* step2: run engine do transfer */
    rv = al_pci_test_engine_do_transfer(cur_case, TEST_DESC_NUM);
    if (rv < 0) {
        ret = false;
    }

    /* step3: check write back data */
    wb_data = (volatile struct sgdma_poll_wb *)engine->poll_mode_addr_virt;
    TEST_DBG(cur_case, "hw write back addr completed cnt: %d\n", wb_data->completed_desc_count);

    /* check completed result. */
    w = read_register(&engine->regs->completed_desc_count);
    TEST_DBG(cur_case, "reg completed desc cnt: %d\n", w);

    if (cur_case->dir == DMA_FROM_DEVICE) {
        TEST_DBG(cur_case, "hw stream write back result:\n");
        do {
            num = (wb_data->completed_desc_count < TEST_DESC_NUM) ? wb_data->completed_desc_count : TEST_DESC_NUM;
            udelay(10);
        } while (num < TEST_DESC_NUM);

        ret = al_do_desc_data_check(cur_case, cur_case->desc_array, TEST_DESC_NUM);

        data_virt = cur_case->data_virt;
        for (i = 0; i < 10; i++) {
            snprintf(prefix, 64, "[%s desc%d start]", cur_case->alias, i);

            print_hex_dump(KERN_NOTICE, prefix, DUMP_PREFIX_OFFSET, 16, 8, data_virt,
                min((u32)TEST_DATA_DUMP_SIZE, cur_case->res_array[i]->length), true);

            snprintf(prefix, 64, "[%s desc%d   end]", cur_case->alias, i);

            printk("\n");
            data_virt += TEST_DATA_SIZE;
        }

        data_virt = cur_case->data_virt + TEST_DATA_SIZE * (TEST_DESC_NUM - 10);
        for (i = TEST_DESC_NUM - 10; i < TEST_DESC_NUM - 1; i++) {
            snprintf(prefix, 64, "[%s desc%d end start]", cur_case->alias, i);

            print_hex_dump(KERN_NOTICE, prefix, DUMP_PREFIX_OFFSET, 16, 8, data_virt,
                min((u32)TEST_DATA_DUMP_SIZE, cur_case->res_array[i]->length), true);

            snprintf(prefix, 64, "[%s desc%d   end]", cur_case->alias, i);

            printk("\n");
            data_virt += TEST_DATA_SIZE;
        }
    }

    al_pci_test_free_desc(cur_case);
out1:
    return ret;
}

bool al_random_length_xfer(struct al_test_case *cur_case, struct anlogic_dma_engine *engine, bool set_eop)
{
#undef  TEST_DATA_SIZE
#undef  TEST_DESC_NUM
#undef  TEST_DATA_DUMP_SIZE
#define TEST_DATA_SIZE      256
#define TEST_DESC_NUM       (4096)
#define TEST_DATA_DUMP_SIZE 0x100
#define TEST_IS_STREAM_MODE 0
#define TEST_PAGES_NUM      2
#define DATA_ALIGN_BYTES    64
#define DATA_ALIGN_MASK     (DATA_ALIGN_BYTES - 1)

    struct anlogic_dev *sgdev = engine->sgdev;
    struct sgdma_poll_wb *wb_data;
    struct sgdma_desc *desc_virt;
    struct sgdma_result *res_virt;
    dma_addr_t desc_bus, data_bus, res_bus;
    size_t data_size, res_size;
    uint32_t control = 0, status, extra_adj, w;
    void *data_virt;
    char prefix[64], desc_str[256], err_info[256] = {0};
    bool ret = true;
    int i, rv, num, desc_num = TEST_DESC_NUM;
    struct sg_table test_sgt;
    struct scatterlist *sg;
    int offset = 0;

#if 1
    int *buf_size = (int *)kzalloc(sizeof(int) * TEST_DESC_NUM, GFP_KERNEL);
    if (buf_size == NULL) {
        TEST_ERR(cur_case, "%s desc_virt %lu OOM\n",
            engine->name, sizeof(int) * TEST_DESC_NUM);
        ret = false;
        goto out2;
    }
#else
    int buf_size[TEST_DESC_NUM] = {
        [0] = 512,
        [1] = 64,
        [2] = 128,
        [3] = 256,
        [4] = 512,
        [5] = 1024,
        [6] = 2048,
        [7] = 4096,
        [8] = 96,
        [9] = 160,
        [10] = 192,
        [11] = 387,
        [12] = 497,
        [13] = 699,
        [14] = 147,
        [15] = 833,
        [16] = 743,
        [17] = 996,
        [18] = 1994,
        [19] = 3753,
    };
#endif

#if 0
    /* gen random data length */
    for (i = 0; i < ARRAY_SIZE(buf_size); i++) {
        buf_size[i] = al_random_num_gen(64, 4096);
    }

    count = (count < ARRAY_SIZE(buf_size)) ? count : ARRAY_SIZE(buf_size);
#else
    /* gen data length from 1 ~ 4096 */
    for (i = 0; i < TEST_DESC_NUM; i++) {
        buf_size[i] = i + 1;
    }

    desc_num = TEST_DESC_NUM;
#endif

#if 0
    /* step1: build 64bit addr desc */
    rv = sgt_alloc_with_pages(&test_sgt, TEST_PAGES_NUM, engine->dir, sgdev->pdev);
    if (rv < 0) {
        TEST_DBG(cur_case, "%s cyclic pages %u OOM, ret %d\n",
            engine->name, TEST_PAGES_NUM, rv);
        ret = false;
        goto out2;
    }

    /* first page used to desc */
    sg = test_sgt.sgl;

    count = sg_dma_len(sg) / sizeof(struct sgdma_desc);
    count = (count < TEST_DESC_NUM) ? count : TEST_DESC_NUM;

    desc_virt = (struct sgdma_desc *)page_address(sg_page(sg));
    desc_bus = sg_dma_address(sg);

    cur_case->desc_virt = desc_virt;
    cur_case->desc_bus = desc_bus;

    /* 2th page used to desc res */
    sg = sg_next(sg);

    count = sg_dma_len(sg) / sizeof(struct sgdma_result);
    count = (count < TEST_DESC_NUM) ? count : TEST_DESC_NUM;

    res_virt = (struct sgdma_result *)page_address(sg_page(sg));
    res_bus = sg_dma_address(sg);

    cur_case->res_virt = res_virt;
    cur_case->res_bus = res_bus;
#else
    desc_num = TEST_DESC_NUM;

    cur_case->desc_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, desc_num * sizeof(struct sgdma_desc), &cur_case->desc_bus, GFP_KERNEL);
    if (cur_case->desc_virt == NULL) {
        TEST_ERR(cur_case, "%s desc_virt %lu OOM\n",
            engine->name, desc_num * sizeof(struct sgdma_desc));
        ret = false;
        goto out2;
    }

    offset = 0;
    for (i = 0; i < desc_num; i++) {
        cur_case->desc_array[i]     = (struct sgdma_desc *)(cur_case->desc_virt + offset);
        cur_case->desc_bus_array[i] = cur_case->desc_bus + offset;
        offset += sizeof(struct sgdma_desc);
    }

    cur_case->res_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, desc_num * sizeof(struct sgdma_result), &cur_case->res_bus, GFP_KERNEL);
    if (res_virt == NULL) {
        al_dma_free_coherent(&sgdev->pdev->dev, desc_num * sizeof(struct sgdma_desc), cur_case->desc_virt, cur_case->desc_bus);
        TEST_ERR(cur_case, "%s res_virt %lu OOM\n",
            engine->name, desc_num * sizeof(struct sgdma_result));
        ret = false;
        goto out2;
    }

#endif
    /* alloc some data buf */
    /* calc desc total size */
    cur_case->data_size = 0;
    for (i = 0; i < desc_num; i++) {
        /* must keep 64 byte align. */
        //buf_size[i] &= ~DATA_ALIGN_MASK;
        //buf_size[i] &= 0xff;
        cur_case->data_size += buf_size[i];
    }

#if 0
    cur_case->data_virt = al_dma_alloc_coherent(&sgdev->pdev->dev, cur_case->data_size, &cur_case->data_bus, GFP_KERNEL);
    if (cur_case->data_virt == NULL) {
        TEST_DBG(cur_case, "pci desc alloc consistent failed.\n");
        ret = false;
        goto out1;
    }
    memset(cur_case->data_virt, 0, cur_case->data_size);
#else
    /* step1: build 64bit data buf */
    rv = sgt_alloc_with_pages(&test_sgt, desc_num, engine->dir, sgdev->pdev);
    if (rv < 0) {
        TEST_ERR(cur_case, "%s cyclic pages %u OOM, ret %d\n",
            engine->name, desc_num, rv);
        ret = false;
        goto out1;
    }

#endif

    al_pci_test_desc_link(cur_case->desc_array, cur_case->desc_bus_array, desc_num);

#if 0
    /* step4: config desc data addr and control filed */
    for (data_bus = cur_case->data_bus, i = 0; i < desc_num; i++) {
        sgdma_desc_set(&desc_virt[i], data_bus, 0, buf_size[i], cur_case->dir);
        sgdma_desc_control_clear(&desc_virt[i], LS_BYTE_MASK);

        if (set_eop)
            sgdma_desc_control_set(&desc_virt[i], SGDMA_DESC_EOP); /* set eop for every desc. */

        data_bus += buf_size[i];
    }
#else
    for (sg = test_sgt.sgl, i = 0; i < desc_num; i++, sg = sg_next(sg)) {

        cur_case->data_bus_array[i] = sg_dma_address(sg);
        sgdma_desc_set(cur_case->desc_array[i], sg_dma_address(sg), 0, buf_size[i], cur_case->dir);
        sgdma_desc_control_clear(cur_case->desc_array[i], LS_BYTE_MASK);

        if (set_eop)
            sgdma_desc_control_set(cur_case->desc_array[i], SGDMA_DESC_EOP); /* set eop for every desc. */
    }
#endif

    /* stop engine, EOP for AXI ST, req IRQ on last descriptor */
    control = SGDMA_DESC_STOPPED;
    control |= SGDMA_DESC_EOP;
    control |= SGDMA_DESC_COMPLETED;
    sgdma_desc_control_set(cur_case->desc_array[desc_num - 1], control);

    if (TEST_IS_STREAM_MODE) {
        /* replace source addresses with result write-back addresses */
        for (i = 0; i < desc_num; i++) {
            cur_case->desc_array[i]->src_addr_lo = cpu_to_le32(PCI_DMA_L(res_bus));
            cur_case->desc_array[i]->src_addr_hi = cpu_to_le32(PCI_DMA_H(res_bus));
            res_bus += sizeof(struct sgdma_result);
        }
    }

    al_pci_test_fill_adj_num(cur_case->desc_array, desc_num);

    /* step2: add all desc comp flag */
    for (i = 0; i < TEST_DESC_NUM - 1; i++) {
        ;//sgdma_desc_control_set(&desc_virt[i], SGDMA_DESC_COMPLETED);
    }

    /* step3: run engine do transfer */
    rv = al_pci_test_engine_do_transfer(cur_case, desc_num);
    if (rv < 0) {
        ret = false;
        goto out3;
    }

    /* step4: check write back data */
    wb_data = (struct sgdma_poll_wb *)engine->poll_mode_addr_virt;
    TEST_DBG(cur_case, "hw write back completed cnt: %d\n", wb_data->completed_desc_count);

    /* check completed result. */
    w = read_register(&engine->regs->completed_desc_count);
    TEST_DBG(cur_case, "register comp desc cnt: %d\n", w);

#if 0
    TEST_DBG(cur_case, "hw stream write back result:\n");
    num = (wb_data->completed_desc_count < TEST_DESC_NUM) ? wb_data->completed_desc_count : TEST_DESC_NUM;
    for (i = 0; i < num; i++) {
        TEST_DBG(cur_case, "result[%d]: 0x%08x, length[%d]\n",
            i, res_virt[i].status, res_virt[i].length);
    }
#endif

    if (wb_data->completed_desc_count != TEST_DESC_NUM || w != TEST_DESC_NUM) {
        ret = false;
        sprintf(err_info, "data write back desc_num check failed, dst %d, real wb %d, reg %d", TEST_DESC_NUM, wb_data->completed_desc_count, w);
    }

out3:
    //al_dma_free_coherent(&sgdev->pdev->dev, cur_case->data_size, cur_case->data_virt, cur_case->data_bus);
    sgt_free_with_pages(&test_sgt, engine->dir, sgdev->pdev);
out1:
    //sgt_free_with_pages(&test_sgt, engine->dir, sgdev->pdev);
    kfree(buf_size);
    al_dma_free_coherent(&sgdev->pdev->dev, desc_num * sizeof(struct sgdma_desc), cur_case->desc_virt, cur_case->desc_bus);
    al_dma_free_coherent(&sgdev->pdev->dev, desc_num * sizeof(struct sgdma_result), cur_case->res_virt, cur_case->res_bus);
out2:
    TEST_RET(cur_case, ret, "%s\n", err_info);
}

/* fill increasing data for h2c test */
int al_do_h2c_data_fill(void *buf, int size, int width, int start)
{
    uint64_t i, dat;
    int pos;
    int bytes = DIV_ROUND_UP(width, 8);
    int cnt = DIV_ROUND_UP(size, bytes);
    uint8_t *pbuf = buf;
    char *prefix = "fill data";

    for (i = 0, pos = 0; i < cnt; i++, pos += bytes) {
        dat = cpu_to_le64(i + start);
        memcpy(&pbuf[pos], &dat, bytes);
    }

//    printk("data fill buf phy addr: 0x%lx\n", __pa(buf));
//    print_hex_dump(KERN_NOTICE, prefix, DUMP_PREFIX_OFFSET, 16, bytes, buf, size, true);
    //print_hex_dump(KERN_NOTICE, prefix, DUMP_PREFIX_OFFSET, 16, bytes, buf, 0x100, true);

    return i;
}

void al_do_h2c_desc_data_fill(struct sgdma_desc *desc, int cnt)
{
#undef DATA_ALIGN_BYTES
#define DATA_ALIGN_BYTES     8//64

    uint64_t i, dat, idx = 0;
    int pos;
    int bytes = DIV_ROUND_UP(DATA_ALIGN_BYTES, 8);
    uint8_t *pbuf;

    pbuf = (uint8_t *)phys_to_virt((((uint64_t)desc[idx].src_addr_hi) << 32) | desc[idx].src_addr_lo);

    for (i = 0, pos = 0; idx < cnt; i++, pos += bytes) {

        if (pos >= desc[idx].bytes) {
            //printk("data fill buf phy addr: 0x%lx\n", __pa(pbuf));
            //print_hex_dump(KERN_NOTICE, "fill data ", DUMP_PREFIX_OFFSET, 16, bytes, pbuf, desc[idx].bytes, true);
            //print_hex_dump(KERN_NOTICE, "fill data ", DUMP_PREFIX_OFFSET, 16, bytes, pbuf, 64, true);
            pos = 0;
            idx++;

            if (idx >= cnt) {
                break;
            }

            pbuf = (uint8_t *)phys_to_virt((((uint64_t)desc[idx].src_addr_hi) << 32) | desc[idx].src_addr_lo);
        }

        dat = cpu_to_le64(i);
        memcpy(&pbuf[pos], &dat, bytes);
    }
}

int al_pci_test_main(struct al_dbg_attr *aldbg, int idx)
{
    if (aldbg->dev == NULL) {
        return -EINVAL;
    }

    aldbg->tester.dev = aldbg->dev;
	aldbg->tester.c2h_eng_num = idx;
	aldbg->tester.h2c_eng_num = idx;

    INIT_LIST_HEAD(&aldbg->tester.case_list);

#if 0
    al_pci_c2h_case_init(&aldbg->tester);

    al_pci_h2c_case_init(&aldbg->tester);
#endif

    al_pci_case_st_init(aldbg);
    return 0;
}

void al_pci_test_case_show(struct al_dbg_attr *dbgattr)
{
    struct al_test_case *cur_case;
    int i = 0;

    if (dbgattr->dev == NULL) {
        al_dbg_printk(dbgattr, "please init first.\n");
        return;
    }

    al_dbg_printk(dbgattr, "\nselect a case to exec. (after case exec, you need to reinstall driver before use user app.)\n\n");
    list_for_each_entry(cur_case, &dbgattr->tester.case_list, node) {
        if (cur_case) {
            al_dbg_printk(dbgattr, "%3d - %s\n", i++, cur_case->desc);
        }
    }
    al_dbg_printk(dbgattr, "\n");
}

void al_case_wait_reset(void)
{
	atomic_set(&start_wait, 0);
}

void al_case_wait_init(struct al_test_case *cur_case, int need_wait)
{
	cur_case->complete_wait = 0;
	cur_case->start_wait = NULL;
	if (need_wait) {
		cur_case->start_wait = &start_wait;
		spin_lock(&reg_spinlock);
		if (need_wait == 1 && (atomic_read(&start_wait) & 3) == 0) {
			atomic_set(&start_wait, 1);
		} else if (need_wait == 2 && (atomic_read(&start_wait) & 3) < 2) {
			atomic_set(&start_wait, 2);
			cur_case->complete_wait = 1;
        }
		spin_unlock(&reg_spinlock);
    }

	if (cur_case->next) {
		cur_case->next->start_wait = cur_case->start_wait;
		cur_case->next->complete_wait = cur_case->complete_wait;
}

	if (cur_case->complete_wait)
		msleep(1000);
}

void al_case_wait(struct al_test_case *cur_case)
{
	int v;

	if (!cur_case->start_wait) {
		return;
	}

	if (atomic_read(cur_case->start_wait) & 3) {
		if (cur_case->complete_wait) {
			atomic_set(cur_case->start_wait, 4);
		} else {
			while (atomic_read(cur_case->start_wait) & 3)
				;
		}
	}
}

int al_pci_test_exec(struct al_dbg_attr *dbgattr, int index, int argc, char*argv[])
{
	struct anlogic_dev *sgdev = to_anlogic_sgdev(dbgattr->dev);
	struct al_test_case *cur_case;
	int i = 0, cnt, is_next_pending = 0;

	channel_interrupts_disable(sgdev, ~0);

    list_for_each_entry(cur_case, &dbgattr->tester.case_list, node) {
        if (i++ == index) {
            if (cur_case && cur_case->ops) {
                for (cnt = 0; cnt < argc; cnt++) {
                    is_next_pending = (strcmp(argv[cnt], "-n") == 0) ? 1 : 0;
                }
				al_case_wait_init(cur_case, dbgattr->need_wait);
                cur_case->do_next = is_next_pending; /* exec relative next case ? */
                cur_case->ops(cur_case, argc, argv);
            } else {
                al_dbg_printk(dbgattr, "%s ops is null\n", cur_case->desc);
            }
            break;
        }
    }

	if (!poll_mode)
		channel_interrupts_enable(sgdev, ~0);

    return 0;
}

int al_pci_test_exec_all(struct al_dbg_attr *dbgattr)
{
	struct anlogic_dev *sgdev = to_anlogic_sgdev(dbgattr->dev);
	struct al_test_case *cur_case;

	channel_interrupts_disable(sgdev, ~0);

    list_for_each_entry(cur_case, &dbgattr->tester.case_list, node) {
        if (cur_case && cur_case->ops) {
            al_dbg_printk(dbgattr, "exec %s\n", cur_case->desc);
			al_case_wait_init(cur_case, 0);
            cur_case->ops(cur_case, 0, NULL);
        } else {
            al_dbg_printk(dbgattr, "%s ops is null\n", cur_case->desc);
        }
    }

	if (!poll_mode)
		channel_interrupts_enable(sgdev, ~0);

    return 0;
}

