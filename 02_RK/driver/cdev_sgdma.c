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
#include <asm/cacheflush.h>
#include <linux/slab.h>
#include <linux/aio.h>
#include <linux/sched.h>
#include <linux/wait.h>
#include <linux/kthread.h>
#include <linux/version.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 16, 0)
#include <linux/uio.h>
#endif
#include "anlogic_pci_lib.h"
#include "anlogic_pci_cdev.h"
#include "anlogic_thread.h"
#include "anlogic_ring.h"
#include "cdev_sgdma.h"
#include "lossless709_ring.h"

#define AL_USE_RING_READ 0

extern struct kmem_cache *cdev_cache;

static void async_io_handler(unsigned long  cb_hndl, int err)
{
    /* TODO ... */
}

/*
 * character device file operations for SG DMA engine
 */
static loff_t char_sgdma_llseek(struct file *file, loff_t off, int whence)
{
    loff_t newpos = 0;

    switch (whence) {
    case 0: /* SEEK_SET */
        newpos = off;
        break;
    case 1: /* SEEK_CUR */
        newpos = file->f_pos + off;
        break;
    case 2: /* SEEK_END, @TODO should work from end of address space */
        newpos = UINT_MAX + off;
        break;
    default: /* can't happen */
        return -EINVAL;
    }
    if (newpos < 0)
        return -EINVAL;
    file->f_pos = newpos;
    dbg_fops("%s: pos=%lld\n", __func__, (signed long long)newpos);

#if 0
    pr_err("0x%p, off %lld, whence %d -> pos %lld.\n",
        file, (signed long long)off, whence, (signed long long)off);
#endif

    return newpos;
}

/* char_sgdma_read_write() -- Read from or write to the device
 *
 * @buf userspace buffer
 * @count number of bytes in the userspace buffer
 * @pos byte-address in device
 * @dir_to_device If !0, a write to the device is performed
 *
 * Iterate over the userspace buffer, taking at most 255 * PAGE_SIZE bytes for
 * each DMA transfer.
 *
 * For each transfer, get the user pages, build a sglist, map, build a
 * descriptor table. submit the transfer. wait for the interrupt handler
 * to wake us on completion.
 */

static int check_transfer_align(struct anlogic_dma_engine *engine,
    const char __user *buf, size_t count, loff_t pos, int sync)
{
    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }

    /* AXI ST or AXI MM non-incremental addressing mode? */
    if (engine->non_incr_addr) {
        int buf_lsb = (int)((uintptr_t)buf) & (engine->addr_align - 1);
        size_t len_lsb = count & ((size_t)engine->len_granularity - 1);
        int pos_lsb = (int)pos & (engine->addr_align - 1);

        dbg_tfr("AXI ST or MM non-incremental\n");
        dbg_tfr("buf_lsb = %d, pos_lsb = %d, len_lsb = %ld\n", buf_lsb,
            pos_lsb, len_lsb);

        if (buf_lsb != 0) {
            dbg_tfr("FAIL: non-aligned buffer address %p\n", buf);
            return -EINVAL;
        }

        if ((pos_lsb != 0) && (sync)) {
            dbg_tfr("FAIL: non-aligned AXI MM FPGA addr 0x%llx\n",
                (unsigned long long)pos);
            return -EINVAL;
        }

        if (len_lsb != 0) {
            dbg_tfr("FAIL: len %d is not a multiple of %d\n",
                (int)count,
                (int)engine->len_granularity);
            return -EINVAL;
        }
        /* AXI MM incremental addressing mode */
    } else {
        int buf_lsb = (int)((uintptr_t)buf) & (engine->addr_align - 1);
        int pos_lsb = (int)pos & (engine->addr_align - 1);

        if (buf_lsb != pos_lsb) {
            dbg_tfr("FAIL: Misalignment error\n");
            dbg_tfr("host addr %p, FPGA addr 0x%llx\n", buf, pos);
            return -EINVAL;
        }
    }

    return 0;
}

/*
 * Map a user memory range into a scatterlist
 * inspired by vhost_scsi_map_to_sgl()
 * Returns the number of scatterlist entries used or -errno on error.
 */
static inline void sgdma_io_cb_release(struct sgdma_io_cb *cb)
{
    int i;

    for (i = 0; i < cb->pages_nr; i++)
        put_page(cb->pages[i]);

    sg_free_table(&cb->sgt);
    kfree(cb->pages);

    memset(cb, 0, sizeof(*cb));
}

static ssize_t char_sgdma_read_write(struct file *file, const char __user *buf,
        size_t count, loff_t *pos, bool write)
{
    int rv;
    ssize_t res = 0;
    struct anlogic_cdev *sgcdev = (struct anlogic_cdev *)file->private_data;
    struct anlogic_dev *sgdev;
    struct anlogic_dma_engine *engine;
    struct sgdma_io_cb cb;

    rv = sgcdev_check(__func__, sgcdev, 1);
    if (rv < 0)
        return rv;
    sgdev = sgcdev->sgdev;
    engine = sgcdev->engine;

    dbg_tfr("file 0x%p, priv 0x%p, buf 0x%p,%llu, pos %llu, W %d, %s.\n",
        file, file->private_data, buf, (u64)count, (u64)*pos, write,
        engine->name);

    if ((write && engine->dir != DMA_TO_DEVICE) ||
        (!write && engine->dir != DMA_FROM_DEVICE)) {
        pr_err("r/w mismatch. W %d, dir %d.\n",
            write, engine->dir);
        return -EINVAL;
    }

    rv = check_transfer_align(engine, buf, count, *pos, 1);
    if (rv) {
        pr_info("Invalid transfer alignment detected\n");
        return rv;
    }

    memset(&cb, 0, sizeof(struct sgdma_io_cb));
    cb.buf = (char __user *)buf;
    cb.len = count;
    cb.ep_addr = (u64)*pos;
    cb.write = write;
    rv = anlogic_map_user_buf_to_sgl(&cb, write);
    if (rv < 0)
        return rv;

    res = sgdma_xfer_submit(sgdev, engine->channel, write, *pos, &cb.sgt,
			    0, write ? h2c_timeout * 1000 :
			    c2h_timeout * 1000, NULL);

    anlogic_unmap_user_buf(&cb, write);

    return res;
}


static ssize_t char_sgdma_write(struct file *file, const char __user *buf,
        size_t count, loff_t *pos)
{
    return char_sgdma_read_write(file, buf, count, pos, 1);
}

static ssize_t char_sgdma_read(struct file *file, char __user *buf,
                size_t count, loff_t *pos)
{
    struct anlogic_cdev *ring_cdev = file->private_data;
    if (ring_cdev->engine->lossless709_ring)
        return lossless709_ring_read(ring_cdev->engine, buf, count);
#if AL_USE_RING_READ /* XXX FIXME use ring desc ? */
    struct anlogic_cdev *sgcdev = (struct anlogic_cdev *)file->private_data;
    struct anlogic_dma_engine *engine;
    int rv;

    rv = sgcdev_check(__func__, sgcdev, 1);
    if (rv < 0)
        return rv;

    engine = sgcdev->engine;

    if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
        rv = sgdma_cyclic_transfer_setup(engine);
        if (rv < 0 && rv != -EBUSY)
            return rv;
        /* 600 sec. timeout */
        return sgdma_engine_read_cyclic(engine, buf, count, 600000);
    }
#endif
    return char_sgdma_read_write(file, buf, count, pos, 0);
}

static ssize_t cdev_aio_write(struct kiocb *iocb, const struct iovec *io,
                unsigned long count, loff_t pos)
{
    return -EIOCBQUEUED;
}

static ssize_t cdev_aio_read(struct kiocb *iocb, const struct iovec *io,
                unsigned long count, loff_t pos)
{
    return -EIOCBQUEUED;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 16, 0)
static ssize_t cdev_write_iter(struct kiocb *iocb, struct iov_iter *io)
{
    return -ENOSYS;
}

static ssize_t cdev_read_iter(struct kiocb *iocb, struct iov_iter *io)
{
    return -ENOSYS;
}
#endif

static int ioctl_do_perf_start(struct anlogic_dma_engine *engine, unsigned long arg)
{
    int rv;
    struct anlogic_dev *sgdev;

    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }

    sgdev = engine->sgdev;
    if (!sgdev) {
        pr_err("Invalid sgdev\n");
        return -EINVAL;
    }

    /* performance measurement already running on this engine? */
    if (engine->sgdma_perf) {
        dbg_perf("IOCTL_SGDMA_PERF_START failed!\n");
        dbg_perf("Perf measurement already seems to be running!\n");
        return -EBUSY;
    }
    engine->sgdma_perf = kzalloc(sizeof(struct sgdma_performance_ioctl),
        GFP_KERNEL);

    if (!engine->sgdma_perf)
        return -ENOMEM;

    rv = copy_from_user(engine->sgdma_perf,
        (struct sgdma_performance_ioctl __user *)arg,
        sizeof(struct sgdma_performance_ioctl));

    if (rv < 0) {
        dbg_perf("Failed to copy from user space 0x%lx\n", arg);
        return -EINVAL;
    }
    if (engine->sgdma_perf->version != IOCTL_SGDMA_PERF_V1) {
        dbg_perf("Unsupported IOCTL version %d\n",
            engine->sgdma_perf->version);
        return -EINVAL;
    }

    enable_perf(engine);
    dbg_perf("transfer_size = %d\n", engine->sgdma_perf->transfer_size);
    /* initialize wait queue */
    init_waitqueue_head(&engine->sgdma_perf_wq);

    rv = sgdma_performance_submit(sgdev, engine);
    if (rv < 0)
        pr_err("Failed to submit dma performance\n");
    return rv;
}

static int ioctl_do_perf_stop(struct anlogic_dma_engine *engine, unsigned long arg)
{
    struct sgdma_transfer *transfer = NULL;
    int rv;

    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }

    dbg_perf("IOCTL_SGDMA_PERF_STOP\n");

    /* no performance measurement running on this engine? */
    if (!engine->sgdma_perf) {
        dbg_perf("No measurement in progress\n");
        return -EINVAL;
    }

    /* stop measurement */
    transfer = engine_cyclic_stop(engine);
    if (!transfer) {
        pr_err("Failed to stop cyclic transfer\n");
        return -EINVAL;
    }
    dbg_perf("Waiting for measurement to stop\n");

    get_perf_stats(engine);

    rv = copy_to_user((void __user *)arg, engine->sgdma_perf,
            sizeof(struct sgdma_performance_ioctl));
    if (rv) {
        dbg_perf("Error copying result to user\n");
        return rv;
    }

    kfree(transfer);

    kfree(engine->sgdma_perf);
    engine->sgdma_perf = NULL;

    return 0;
}

static int ioctl_do_perf_get(struct anlogic_dma_engine *engine, unsigned long arg)
{
    int rc;

    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }

    dbg_perf("IOCTL_SGDMA_PERF_GET\n");

    if (engine->sgdma_perf) {
        get_perf_stats(engine);

        rc = copy_to_user((void __user *)arg, engine->sgdma_perf,
            sizeof(struct sgdma_performance_ioctl));
        if (rc) {
            dbg_perf("Error copying result to user\n");
            return rc;
        }
    } else {
        dbg_perf("engine->sgdma_perf == NULL?\n");
        return -EPROTO;
    }

    return 0;
}

static int ioctl_do_addrmode_set(struct anlogic_dma_engine *engine, unsigned long arg)
{
    return -ENOSYS;
}

static int ioctl_do_addrmode_get(struct anlogic_dma_engine *engine, unsigned long arg)
{
    int rv;
    unsigned long src;

    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }
    src = !!engine->non_incr_addr;

    dbg_perf("IOCTL_SGDMA_ADDRMODE_GET\n");
    rv = put_user(src, (int __user *)arg);

    return rv;
}

static int ioctl_do_align_get(struct anlogic_dma_engine *engine, unsigned long arg)
{
    if (!engine) {
        pr_err("Invalid DMA engine\n");
        return -EINVAL;
    }

    dbg_perf("IOCTL_SGDMA_ALIGN_GET\n");
    return put_user(engine->addr_align, (int __user *)arg);
}

static int ioctl_do_aperture_dma(struct anlogic_dma_engine *engine, unsigned long arg,
                bool write)
{
    struct sgdma_aperture_ioctl io;
    struct sgdma_io_cb cb;
    ssize_t res;
    int rv;

    rv = copy_from_user(&io, (struct sgdma_aperture_ioctl __user *)arg,
                sizeof(struct sgdma_aperture_ioctl));
    if (rv < 0) {
        dbg_tfr("%s failed to copy from user space 0x%lx\n",
            engine->name, arg);
        return -EINVAL;
    }

    dbg_tfr("%s, W %d, buf 0x%lx,%lu, ep %llu, aperture %u.\n",
        engine->name, write, io.buffer, io.len, io.ep_addr,
        io.aperture);

    if ((write && engine->dir != DMA_TO_DEVICE) ||
        (!write && engine->dir != DMA_FROM_DEVICE)) {
        pr_err("r/w mismatch. W %d, dir %d.\n", write, engine->dir);
        return -EINVAL;
    }

    rv = check_transfer_align(engine, (char *)io.buffer, io.len,
                io.ep_addr, 1);
    if (rv) {
        pr_info("Invalid transfer alignment detected\n");
        return rv;
    }

    memset(&cb, 0, sizeof(struct sgdma_io_cb));
    cb.buf = (char __user *)io.buffer;
    cb.len = io.len;
    cb.ep_addr = io.ep_addr;
    cb.write = write;
    rv = anlogic_map_user_buf_to_sgl(&cb, write);
    if (rv < 0)
        return rv;

    io.error = 0;
    res = sgdma_xfer_aperture(engine, write, io.ep_addr, io.aperture,
                &cb.sgt, 0, write ? h2c_timeout * 1000 :
                        c2h_timeout * 1000);

    anlogic_unmap_user_buf(&cb, write);
    if (res < 0)
        io.error = res;
    else
        io.done = res;

    rv = copy_to_user((struct sgdma_aperture_ioctl __user *)arg, &io,
                sizeof(struct sgdma_aperture_ioctl));
    if (rv < 0) {
        dbg_tfr("%s failed to copy to user space 0x%lx, %ld\n",
            engine->name, arg, res);
        return -EINVAL;
    }

    return io.error;
}

static int ioctl_do_cus_dma(struct anlogic_dma_engine *engine, unsigned long arg)
{
	struct anlogic_dev *sgdev = engine->sgdev;
	struct sgdma_cus_rw_ioctl io;
	struct sgdma_desc_info *info;
	struct sg_table sgt;
	struct scatterlist *sg;
	dma_addr_t bufaddr;
	void *buf;
	void **buf_array;
	int write, i;
	u32 len = 0, *controls;
	ssize_t res;
	int rv;

	rv = copy_from_user(&io, (struct sgdma_cus_rw_ioctl __user *)arg,
			    sizeof(struct sgdma_cus_rw_ioctl));
	if (rv) {
		dbg_tfr("%s failed to copy from user space 0x%lx\n",
		engine->name, arg);
		return -EINVAL;
	}

	write = io.write;
	if ((write && engine->dir != DMA_TO_DEVICE) ||
	    (!write && engine->dir != DMA_FROM_DEVICE)) {
		pr_err("r/w mismatch. W %d, dir %d.\n", write, engine->dir);
		return -EINVAL;
	}

	if (!io.desc_cnt) {
		pr_err("Invalid desc_cnt %d\n", io.desc_cnt);
		return -EINVAL;
	}

	info = kmalloc(io.desc_cnt * (sizeof(struct sgdma_desc_info) + sizeof(u32)), GFP_KERNEL);
	if (!info) {
		pr_err("Failed to allocate desc info\n");
		return -ENOMEM;
	}

	rv = copy_from_user(info, ((struct sgdma_cus_rw_ioctl __user *)arg)->desc,
			    io.desc_cnt * sizeof(struct sgdma_desc_info));
	if (rv) {
		pr_err("%s failed to copy from desc info 0x%lx\n",
			engine->name, arg);
		goto free_info;
	}

	controls = (u32 *)&info[io.desc_cnt];
	for (i = 0; i < io.desc_cnt; i++) {
		if (!info[i].len || info[i].len > desc_blen_max) {
			pr_err("Invalid desc len %d\n", info[i].len);
			rv = -EINVAL;
			goto free_info;
		}
		len += info[i].len;
		controls[i] = info[i].control;
		dbg_tfr("%s [%d] len 0x%x, control 0x%x\n", engine->name,
			i, info[i].len, info[i].control);
	}

	if (!access_ok((void __user *)(uintptr_t)io.buffer, len)) {
		pr_err("%s, Invalid user space buffer 0x%lx, len %u\n",
			engine->name, (ulong)io.buffer, len);
		rv = -EFAULT;
		goto free_info;
	}

	pr_info("%s, W %d, buf 0x%lx,%u, ep %llu.\n",
		engine->name, write, (ulong)io.buffer, len,
		(unsigned long long)io.ep_addr);

	buf_array = kmalloc_array(io.desc_cnt, sizeof(void *), GFP_KERNEL);
	if (!buf_array) {
		pr_err("Failed to allocate buffer array\n");
		rv = -ENOMEM;
		goto free_info;
	}
	memset(buf_array, 0, io.desc_cnt * sizeof(void *));

	if (sg_alloc_table(&sgt, io.desc_cnt, GFP_KERNEL)) {
		pr_err("sgl OOM.\n");
		rv = -ENOMEM;
		goto free_bufa;
	}

	for_each_sgtable_sg((&sgt), sg, i) {
		buf = dma_alloc_coherent(&engine->sgdev->pdev->dev, info[i].len, &bufaddr, GFP_KERNEL);
		if (!buf) {
			pr_err("Failed to allocate buffer: 0x%x\n", info[i].len);
			rv = -ENOMEM;
			goto free_buf;
		}
		buf_array[i] = buf;
		sg_set_buf(sg, buf, info[i].len);
		sg_dma_address(sg) = bufaddr;
		sg_dma_len(sg) = info[i].len;
	}

	if (write) {
		rv = sg_copy_from_user(&sgt, (char __user *)io.buffer, len);
		if (rv < 0) {
			pr_err("%s failed to copy from user space buffer 0x%lx\n",
			       engine->name, (ulong)io.buffer);
			goto free_buf;
		}
	}

	io.error = 0;
	res = sgdma_xfer_submit(sgdev, engine->channel, write, io.ep_addr, &sgt,
				1, write ? h2c_timeout * 1000 : c2h_timeout * 1000,
				(io.flags & SGDMA_CUSRW_FLG_CTRL) ? controls : NULL);

	if (res < 0) {
		io.error = res;
	} else {
		io.done = res;
		if (!write) {
			rv = sg_copy_to_user(&sgt, (char __user *)io.buffer, res);
			if (rv < 0) {
				pr_err("%s failed to copy to user space buffer 0x%lx, 0x%lx\n",
				       engine->name, (ulong)io.buffer, (ulong)res);
				goto free_buf;
			}
		}
	}

	rv = copy_to_user((struct sgdma_cus_rw_ioctl __user *)arg, &io,
			  sizeof(struct sgdma_cus_rw_ioctl));
	if (rv) {
		pr_err("%s failed to update info 0x%lx\n",
		       engine->name, arg);
		goto free_buf;
	}
	rv = 0;
free_buf:
	for_each_sgtable_sg((&sgt), sg, i) {
		if (buf_array[i]) {
			dma_free_coherent(&engine->sgdev->pdev->dev,
				info[i].len, buf_array[i], sg_dma_address(sg));
		}
	}
free_sgt:
	sg_free_table(&sgt);
free_bufa:
	kfree(buf_array);
free_info:
	kfree(info);
	return rv;
}

static long char_sgdma_ioctl(struct file *file, unsigned int cmd,
        unsigned long arg)
{
    struct anlogic_cdev *sgcdev = (struct anlogic_cdev *)file->private_data;
    struct anlogic_dev *sgdev;
    struct anlogic_dma_engine *engine;

    int rv = 0;

    rv = sgcdev_check(__func__, sgcdev, 1);
    if (rv < 0)
        return rv;

    sgdev = sgcdev->sgdev;
    engine = sgcdev->engine;

    switch (cmd) {
    case IOCTL_SGDMA_PERF_START:
        rv = ioctl_do_perf_start(engine, arg);
        break;
    case IOCTL_SGDMA_PERF_STOP:
        rv = ioctl_do_perf_stop(engine, arg);
        break;
    case IOCTL_SGDMA_PERF_GET:
        rv = ioctl_do_perf_get(engine, arg);
        break;
    case IOCTL_SGDMA_ADDRMODE_SET:
        rv = ioctl_do_addrmode_set(engine, arg);
        break;
    case IOCTL_SGDMA_ADDRMODE_GET:
        rv = ioctl_do_addrmode_get(engine, arg);
        break;
    case IOCTL_SGDMA_ALIGN_GET:
        rv = ioctl_do_align_get(engine, arg);
        break;
    case IOCTL_SGDMA_APERTURE_R:
        rv = ioctl_do_aperture_dma(engine, arg, 0);
        break;
    case IOCTL_SGDMA_APERTURE_W:
        rv = ioctl_do_aperture_dma(engine, arg, 1);
        break;
    case IOCTL_SGDMA_CUS_RW:
	rv = ioctl_do_cus_dma(engine, arg);
	break;
    default:
        dbg_perf("Unsupported operation\n");
        rv = -EINVAL;
        break;
    }

    return rv;
}

static int char_sgdma_open(struct inode *inode, struct file *file)
{
    struct anlogic_cdev *sgcdev;
    struct anlogic_dma_engine *engine;

    char_open(inode, file);

    sgcdev = (struct anlogic_cdev *)file->private_data;
    engine = sgcdev->engine;

    if (engine->streaming && engine->dir == DMA_FROM_DEVICE) {
        if (engine->device_open == 1)
            return -EBUSY;
        engine->device_open = 1;

        engine->eop_flush = (file->f_flags & O_TRUNC) ? 1 : 0;
        if (lossless709_ring_mode && engine->eop_flush) {
            int error = lossless709_ring_open(engine);
            if (error) {
                engine->device_open = 0;
                return error;
            }
        }
    }

    return 0;
}

static int char_sgdma_close(struct inode *inode, struct file *file)
{
    struct anlogic_cdev *sgcdev = (struct anlogic_cdev *)file->private_data;
    struct anlogic_dma_engine *engine;
    int rv;

    rv = sgcdev_check(__func__, sgcdev, 1);
    if (rv < 0)
        return rv;

    engine = sgcdev->engine;

    if (engine->lossless709_ring) {
        rv = lossless709_ring_close(engine);
        if (rv)
            return rv;
    }
    if (engine->streaming && engine->dir == DMA_FROM_DEVICE)
        engine->device_open = 0;

    return 0;
}
static const struct file_operations sgdma_fops = {
    .owner = THIS_MODULE,
    .open = char_sgdma_open,
    .release = char_sgdma_close,
    .write = char_sgdma_write,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 16, 0)
    .write_iter = cdev_write_iter,
#else
    .aio_write = cdev_aio_write,
#endif
    .read = char_sgdma_read,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 16, 0)
    .read_iter = cdev_read_iter,
#else
    .aio_read = cdev_aio_read,
#endif
    .unlocked_ioctl = char_sgdma_ioctl,
    .llseek = char_sgdma_llseek,
};

void cdev_sgdma_init(struct anlogic_cdev *sgcdev)
{
    cdev_init(&sgcdev->cdev, &sgdma_fops);
}
