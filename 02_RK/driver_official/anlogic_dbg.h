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
#ifndef __ANLOGIC_DBG_H__
#define __ANLOGIC_DBG_H__

#define al_dma_alloc_coherent dma_alloc_coherent
#define al_dma_free_coherent dma_free_coherent

#define AL_DBG_ARGC_MAX      20
#define AL_DBG_ARGV_STR_MAX  128

#define AL_DBG_ATTR_DEF(_attr) \
    static struct al_dbg_attr _attr = { \
        .name = # _attr, \
    }

#define AL_DBG_NODE_CREATE(_attr, _dbg_main, _priv) \
    ({\
        (_attr)->dbg_main = _dbg_main; \
        (_attr)->priv = _priv; \
        al_dbg_node_create(_attr); \
    })

#define AL_DBG_NODE_DESTORY(_attr) \
    al_dbg_node_destory(_attr)


struct al_tester {
    struct device *dev;
    struct list_head case_list;
	int c2h_eng_num;
	int h2c_eng_num;
};

/**
 * struct al_dbg_attr - driver's dbg node attr:
 *
 * @dev: dbg related device;
 * @priv: dbg resv;
 * @hwmon: hwmon device;
 * @dbg_attr: sysfs attributes array;
 * @dbg_dev_attr: sysfs sensor device attribute array;
 * @group: sysfs attribute group;
 * @groups: list of sysfs attribute group for hwmon registration;
 * @name: dbg node name;
 * @dbg_main: size of a register value;
 */
#define AL_DBG_PRINTK_MAX 2048
struct al_dbg_attr {
    struct device *dev;
    void *priv;
    char name[32];
    int (*dbg_main)(struct al_dbg_attr *dbg_attr, int argc, char *argv[]);

    struct proc_dir_entry *ent;
    struct seq_file *seq;
    char *argv[AL_DBG_ARGC_MAX];
	int index;
    int argc;
    int is_write_pending;
	int need_wait;
	struct al_tester tester;
	char al_printf_buf[AL_DBG_PRINTK_MAX];
};

#if defined(__GNUC__) && ((__GNUC__ == 4 && __GNUC_MINOR__>= 4) || __GNUC__ > 4)
#  define ATTR_WARN_PRINTF(X,Y) __attribute__((format(gnu_printf,X,Y)))
#elif defined(__GNUC__)
#  define ATTR_WARN_PRINTF(X,Y) __attribute__((format(printf,X,Y)))
#else
#  define ATTR_WARN_PRINTF(X,Y)
#endif

#define al_printf(dbgattr, fmt, ...) al_dbg_printk(dbgattr, fmt, ##__VA_ARGS__)

#define DBG_FORMART_INT_ARG_WTIH_RETVAL(arg, val, base, is_ret, _ret) \
    do { \
        unsigned long ul_data = 0; \
        if ((arg) == NULL) { \
            al_printf(cur_case->dbg_attr, "Invalid (%s) arg: null\n", #val); \
            if (is_ret) return (_ret); \
        } \
        if (kstrtoul(arg, base, (unsigned long*)&(ul_data)) != 0) { \
            al_printf(cur_case->dbg_attr, "Invalid (%s) arg: %s\n", #val, arg); \
            if (is_ret) return (_ret); \
        } \
        (val) = ul_data; \
    } while (0)

#define DBG_FORMART_INT_ARG_WTIHOUT_RETVAL(arg, val, base, is_ret) \
    do { \
        unsigned long ul_data = 0; \
        if ((arg) == NULL) { \
            al_printf(cur_case->dbg_attr, "Invalid (%s) arg: null\n", #val); \
            if (is_ret) return; \
        } \
        if (kstrtoul(arg, base, (unsigned long*)&(ul_data)) != 0) { \
            al_printf(cur_case->dbg_attr, "Invalid (%s) arg: %s\n", #val, arg); \
            if (is_ret) return; \
        } \
        (val) = ul_data; \
    } while (0)

#define DBG_FORMART_INT_ARG(arg, val, base) \
    do { \
        unsigned long ul_data = 0; \
        if ((arg) == NULL) { \
            al_printf(dbgattr, "Invalid (%s) arg: null\n", #val); \
            return; \
        } \
        if (kstrtoul(arg, base, (unsigned long*)&(ul_data)) != 0) { \
            al_printf(dbgattr, "Invalid (%s) arg: %s\n", #val, arg); \
            return; \
        } \
        (val) = ul_data; \
    } while (0)

#define DBG_FORMART_INT_ARG_WTIH_RET(arg, val, base, _ret) DBG_FORMART_INT_ARG_WTIH_RETVAL(arg, val, base, 1, _ret)

int al_dbg_node_create(struct al_dbg_attr *node);

void al_dbg_node_destory(struct al_dbg_attr *node);

ATTR_WARN_PRINTF(2, 3) int al_dbg_printk(struct al_dbg_attr *dbgattr, const char *fmt, ...);

void al_dbg_hex_dump(struct al_dbg_attr *dbgattr, const char prefix_str[], int prefix_type, int rowsize, int groupsize, const void *buf, size_t len, bool ascii);

#endif /* ifndef __ANLOGIC_DBG_H__ */
