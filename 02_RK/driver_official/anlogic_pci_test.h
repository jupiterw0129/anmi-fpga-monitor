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
#ifndef __ANLOGIC_PCI_TEST_H__
#define __ANLOGIC_PCI_TEST_H__

#include <linux/list.h>

//#define ENABLE_TEST_DBG 1

#define TEST_CASE_INIT(case, dbgattr, _des, _name, _dir, _is_st, _sub, add) \
	al_testcase_init(case, dbgattr, _des, #_name, _name##_case, _dir, _is_st, _sub, add)


#define TEST_CASE(_des, _name, _dir, _is_st) \
    bool _name##_case (struct al_test_case *cur_case, int argc, char* argv[])

#define TEST_RET(case, res, fmt, args...) \
    do { \
		const char *__dir = ((case)->dir == DMA_TO_DEVICE) ? "h2c" : "c2h"; \
        al_dbg_printk(case->dbg_attr, "\r[%s-%s%d] %s exec %s\n\n\n", (case)->alias, __dir, \
				(case)->engine_num, (case)->desc, \
                ((res) == true) ? "success" : "failed"); \
        return (res); \
    } while(0)

#if defined(ENABLE_TEST_DBG)
#define TEST_DBG(case, fmt, args...) \
    do { \
		const char *__dir = ((case)->dir == DMA_TO_DEVICE) ? "h2c" : "c2h"; \
        al_dbg_printk(case->dbg_attr, "[%s-%s%d] %s "fmt, (case)->alias, __dir, \
				(case)->engine_num, __func__, ##args); \
        printk("[%s-%s%d] %s "fmt, (case)->alias, __dir, \
				(case)->engine_num, __func__, ##args); \
    } while(0)
#else
#define TEST_DBG(case, fmt, args...)
#endif

#define TEST_ERR(case, fmt, args...) \
    do { \
		const char *__dir = ((case)->dir == DMA_TO_DEVICE) ? "h2c" : "c2h"; \
        al_dbg_printk(case->dbg_attr, "Error [%s-%s%d] %s "fmt, (case)->alias, __dir, \
				(case)->engine_num, __func__, ##args); \
        printk("[%s-%s%d] %s "fmt, (case)->alias, __dir, \
				(case)->engine_num, __func__, ##args); \
    } while(0)

#define C2H_ST_CASE_INIT(case, dbgattr, des, name, sub, add) TEST_CASE_INIT(case, dbgattr, des, name, DMA_FROM_DEVICE, true, sub, add)
#define H2C_ST_CASE_INIT(case, dbgattr, des, name, sub, add) TEST_CASE_INIT(case, dbgattr, des, name, DMA_TO_DEVICE, true, sub, add)
#define C2H_MM_CASE_INIT(case, dbgattr, des, name, sub, add) TEST_CASE_INIT(case, dbgattr, des, name, DMA_FROM_DEVICE, false, sub, add)
#define H2C_MM_CASE_INIT(case, dbgattr, des, name, sub, add) TEST_CASE_INIT(case, dbgattr, des, name, DMA_TO_DEVICE, false, sub, add)

#define C2H_TEST_CASE(des, name) TEST_CASE(des, name, DMA_FROM_DEVICE, true)
#define H2C_TEST_CASE(des, name) TEST_CASE(des, name, DMA_TO_DEVICE, true)
#define C2H_ST_CASE(des, name) TEST_CASE(des, name, DMA_FROM_DEVICE, true)
#define H2C_ST_CASE(des, name) TEST_CASE(des, name, DMA_TO_DEVICE, true)
#define C2H_MM_CASE(des, name) TEST_CASE(des, name, DMA_FROM_DEVICE, false)
#define H2C_MM_CASE(des, name) TEST_CASE(des, name, DMA_TO_DEVICE, false)

#define AL_PCIE_DBG_ADD(test_case) list_add_tail(&test_case.node, &tester->case_list);

#define AL_H2C_DATA_WIDTH   (64)

#define CASE_BIND_NEXT(cur_case, _next) do {(cur_case)->next = (_next);} while(0)

#define EXEC_NEXT(cur_case) \
({ \
    struct al_test_case *next = cur_case->next; \
    bool ret = true; \
    if (cur_case->do_next) { \
        if (next && next->ops) { \
            next->do_next = 1; \
            ret = next->ops(cur_case, argc, argv); \
        } \
    } \
    ret; \
})

#define MAX_DESC_NUM 4096

#define to_anlogic_sgdev(dev) (((struct anlogic_pci_dev *)dev_get_drvdata(dev)) -> sgdev)

#define get_case_engine(cur_case) (cur_case->engine)


struct al_test_case;

typedef bool (* al_test_case_t)(struct al_test_case *cur_case, int argc, char* argv[]);

struct al_test_case {
    const char *desc;
    const char *alias;
    char err_info[256];
    bool is_stream;
    bool do_next;
    bool is_prev_req_pending;
    void *priv;
    uint8_t *golden_data;

    void   *desc_virt;
    void   *data_virt;
    void   *res_virt;

    dma_addr_t desc_bus;
    dma_addr_t data_bus;
    dma_addr_t res_bus;

    struct sgdma_desc   *desc_array[MAX_DESC_NUM];
    struct sgdma_result *res_array[MAX_DESC_NUM];
    void   *data_array[MAX_DESC_NUM];

    dma_addr_t desc_bus_array[MAX_DESC_NUM];
    dma_addr_t data_bus_array[MAX_DESC_NUM];
    dma_addr_t res_bus_array[MAX_DESC_NUM];

    size_t desc_size;
    size_t data_size;
    size_t res_size;
    size_t desc_sz[MAX_DESC_NUM];

    struct anlogic_dma_engine *engine;
    uint32_t    test_ring_cnt;
    bool        enable_credit;
    uint32_t    run_status;
    int         result;
    uint32_t    stop_start_test;

    u64 mm_ofs[MAX_DESC_NUM];
    int desc_num;

    enum dma_data_direction dir;
    al_test_case_t ops;
    struct list_head node;

    struct al_test_case *next; /* relative next case */
	struct al_dbg_attr *dbg_attr;
	int engine_num;
	int cpu;
	int complete_wait;
	atomic_t *start_wait;
	uint32_t h2c_pkt_len[4096];
};

static inline int al_testcase_init(struct al_test_case *testcase, struct al_dbg_attr *dbgattr,
		const char *desc, const char *alias, al_test_case_t ops,
		enum dma_data_direction dir, bool is_stream, struct al_test_case *sub,
		bool add)
{
	struct anlogic_dev *sgdev = to_anlogic_sgdev(dbgattr->dev);
	struct al_tester *tester = &dbgattr->tester;

	testcase->desc = desc;
	testcase->alias = alias;
	testcase->ops = ops;
	testcase->dir = dir;
	testcase->is_stream = is_stream;
	testcase->next = sub;
	testcase->dbg_attr = dbgattr;

	if (dir == DMA_TO_DEVICE) {
		testcase->engine = &sgdev->engine_h2c[tester->h2c_eng_num];
		testcase->cpu = al_get_cpu(tester->h2c_eng_num, h2c);
		testcase->engine_num = tester->h2c_eng_num;
	} else {
		testcase->engine = &sgdev->engine_c2h[tester->c2h_eng_num];
		testcase->cpu = al_get_cpu(tester->c2h_eng_num, c2h);
		testcase->engine_num = tester->c2h_eng_num;
	}

	if (add) {
		list_add_tail(&testcase->node, &tester->case_list);
	}

	return 0;
}

extern unsigned int enable_st_c2h_credit;
extern unsigned int enable_st_h2c_credit;
extern unsigned int poll_mode;

extern void channel_interrupts_enable(struct anlogic_dev *sgdev, u32 mask);

extern void channel_interrupts_disable(struct anlogic_dev *sgdev, u32 mask);

int format_desc(char *buf, int len, struct sgdma_desc *desc);

size_t desc_data_size_gen_custom_total_size(int desc_num, bool is_random, uint32_t align,
        size_t *desc_sz, uint64_t *mm_ofs, uint32_t total_sz, uint64_t base);

size_t st_desc_data_size_gen_custom_by_h2c_pkt_size(struct al_test_case *cur_case, bool is_random, uint32_t align, size_t *desc_sz, int *c2h_desc_num,
                int h2c_pkt_num, uint32_t *h2c_pkt_len);

int case_rsc_alloc(struct al_test_case *cur_case, bool is_random, uint32_t align, int desc_num, struct anlogic_dev *sgdev);

void case_rsc_free(struct al_test_case *cur_case, struct anlogic_dev *sgdev);

void desc_data_size_clr(struct al_test_case *cur_case);

int al_pci_test_build_desc(struct al_test_case *test_case, int count, size_t single_size, int is_stream);

void al_pci_test_build_desc_no_alloc(struct al_test_case *test_case, int count, size_t single_size, int is_stream);

void al_pci_test_build_desc_custom(struct al_test_case *test_case, int desc_num, size_t desc_sz[], int is_stream, u64 mm_ofs[]);


void al_pci_test_free_desc(struct al_test_case *test_case);

int al_pci_test_engine_do_transfer(struct al_test_case *test_case, int count);

int al_pci_test_engine_do_transfer_with_no_stop(struct al_test_case *test_case, int count, int is_stop);

bool al_stream_transfer_test(struct al_test_case *curr_test_case);

void al_pci_test_desc_link(struct sgdma_desc *desc_virt_arrary[], dma_addr_t desc_bus_array[], int desc_num);

int al_random_num_gen(int min, int max);

bool al_do_data_check(struct al_test_case *cur_case, void *buf, int len);

bool al_do_desc_data_check(struct al_test_case *cur_case, struct sgdma_desc *desc_virt_array[], int cnt);

bool al_random_length_xfer(struct al_test_case *curr_test_case, struct anlogic_dma_engine *engine, bool set_eop);

bool al_do_h2c_data_check(struct al_test_case *curr_test_case);

int al_do_h2c_data_fill(void *buf, int size, int width, int start);

void al_do_h2c_desc_data_fill(struct sgdma_desc *desc, int cnt);

void al_pci_test_fill_adj_num(struct sgdma_desc *desc_virt_array[], int desc_num);

void al_pci_h2c_case_init(struct al_tester *tester);

void al_pci_c2h_case_init(struct al_tester *tester);

void al_pci_case_st_init(struct al_dbg_attr *aldbg);

/* anlogic pci dbg use */

int al_pci_test_main(struct al_dbg_attr *aldbg, int idx);

void al_pci_test_case_show(struct al_dbg_attr *aldbg);

int al_pci_test_exec(struct al_dbg_attr *aldbg, int index, int argc, char*argv[]);

int al_pci_test_exec_all(struct al_dbg_attr *aldbg);

void al_case_wait_reset(void);

void al_case_wait_init(struct al_test_case *cur_case, int need_wait);

void al_case_wait(struct al_test_case *cur_case);

#endif /* ifndef __ANLOGIC_PCI_TEST_H__ */

