#define pr_fmt(fmt) KBUILD_MODNAME ": %s: " fmt, __func__

#include <linux/init.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kobject.h>
#include <linux/slab.h>
#include <linux/device.h>
#include <linux/string.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/uaccess.h>
#include <linux/hwmon.h>
#include <linux/sched.h>
#include <linux/seq_file.h>
#include <linux/proc_fs.h>

#include "anlogic_dbg.h"

#define argv_mem(idx) (dbg_attr->argv[0] + (idx) * AL_DBG_ARGV_STR_MAX)

static int al_dbg_show(struct seq_file *seq, void *p)
{
	struct al_dbg_attr *dbg_attr = seq->private;

    if (dbg_attr->dbg_main) {
		if (dbg_attr->is_write_pending == 0) {
			dbg_attr->argv[1] = argv_mem(1);
			strcpy(dbg_attr->argv[1], "-h");
			dbg_attr->argc = 2;
			dbg_attr->argv[dbg_attr->argc] = NULL;
		}

        dbg_attr->dbg_main(dbg_attr, dbg_attr->argc, dbg_attr->argv); /* show help info */
        dbg_attr->is_write_pending = 0;
    }

    return 0;
}

static ssize_t al_dbg_write(struct file *file,
		const char __user *ubuf, size_t count, loff_t *pos)
{
#define DELIM " "
	struct al_dbg_attr *dbg_attr = (struct al_dbg_attr *)(long)
#if KERNEL_VERSION(5, 17, 0) <= LINUX_VERSION_CODE
		pde_data(file_inode(file));
#else
		PDE_DATA(file_inode(file));
#endif
    char *str, *buf, *token;

	buf = memdup_user_nul(ubuf, count);
	if (IS_ERR(buf))
		return PTR_ERR(buf);

	str = buf;
    dbg_attr->argc = 1;

    do {
        token = strsep(&str, DELIM);

        if (token == NULL) {
            break;
        }

        if (*token == '\0') {
            continue; /* skip continue delim */
        }

		dbg_attr->argv[dbg_attr->argc] = argv_mem(dbg_attr->argc);
		strcpy(dbg_attr->argv[dbg_attr->argc], token);
		dbg_attr->argc++;
    } while (dbg_attr->argc < AL_DBG_ARGC_MAX);

	dbg_attr->argv[dbg_attr->argc] = NULL;

	kfree(buf);

	if (dbg_attr->argc > 1) {
		dbg_attr->is_write_pending = 1;
	}

    return count;
}

static int al_dbg_open(struct inode *inode, struct file *file)
{
	struct al_dbg_attr *dbg_attr = (struct al_dbg_attr *)(long)
#if KERNEL_VERSION(5, 17, 0) <= LINUX_VERSION_CODE
		pde_data(inode);
#else
		PDE_DATA(inode);
#endif
	int rv;

	rv = single_open_size(file, al_dbg_show,
#if KERNEL_VERSION(5, 17, 0) <= LINUX_VERSION_CODE
		pde_data(inode)
#else
		PDE_DATA(inode)
#endif
		, 640 * PAGE_SIZE
	);
	if (rv < 0) {
		printk("seq file create failed\n");
		return rv;
	}

    dbg_attr->seq = (struct seq_file *)file->private_data;

	return 0;
}

int al_dbg_release(struct inode *inode, struct file *file)
{
	struct al_dbg_attr *dbg_attr = (struct al_dbg_attr *)(long)
#if KERNEL_VERSION(5, 17, 0) <= LINUX_VERSION_CODE
		pde_data(inode);
#else
		PDE_DATA(inode);
#endif

	single_release(inode, file);

	return 0;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
static const struct proc_ops al_dbg_ops = {
	.proc_open	= al_dbg_open,
	.proc_read	= seq_read,
	.proc_lseek	= seq_lseek,
	.proc_release	= al_dbg_release,
	.proc_write	= al_dbg_write,
};
#else
static const struct file_operations al_dbg_ops = {
	.owner = THIS_MODULE,
	.open = al_dbg_open,
    .release = al_dbg_release,
	.read = seq_read,
	.write = al_dbg_write,
	.llseek = seq_lseek,
};
#endif

int al_dbg_node_create(struct al_dbg_attr *node)
{
    if (node == NULL || node->dev == NULL) {
        return -EINVAL;
    }

	node->ent = proc_create_data(node->name, S_IRUGO | S_IWUSR, NULL,
											&al_dbg_ops, (void *)node);

	if (node->ent == NULL) {
		printk("proc file create failed\n");
		return-ENODEV;
	}

	node->argv[0] = devm_kcalloc(node->dev, AL_DBG_ARGC_MAX, AL_DBG_ARGV_STR_MAX, GFP_KERNEL);
	if (node->argv[0] == NULL) {
		printk("dbg_attr alloc argv failed...\n");
		return (-ENOMEM);
	}

	node->argc = 0;
	node->is_write_pending = 0;

	strcpy(node->argv[0], node->name);

    return 0;
}

void al_dbg_node_destory(struct al_dbg_attr *node)
{
    if (node == NULL) {
        return;
    }

    if (node->ent)
        proc_remove(node->ent);

    node->dbg_main = NULL;
}

ATTR_WARN_PRINTF(2, 3) int al_dbg_printk(struct al_dbg_attr *dbgattr, const char *fmt, ...)
{
    int ret = -EBADF;
    va_list args;

    if (!fmt) {
        printk("Format for custom_printk was empty.\n");
        return -EINVAL;
    }

    va_start(args, fmt);
    ret = vscnprintf(dbgattr->al_printf_buf, AL_DBG_PRINTK_MAX, fmt, args);
    va_end(args);

    if (dbgattr && dbgattr->seq) {
        seq_printf(dbgattr->seq, "%s", dbgattr->al_printf_buf);
	}

	return ret;
}

void inline al_dbg_hex_dump(struct al_dbg_attr *dbgattr, const char prefix_str[], int prefix_type, int rowsize, int groupsize, const void *buf, size_t len, bool ascii)
{
    if (dbgattr && dbgattr->seq) {
        seq_hex_dump(dbgattr->seq, prefix_str, prefix_type, rowsize, groupsize, buf, len, ascii);
	}
}

