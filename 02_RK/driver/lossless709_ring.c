#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/slab.h>
#include "anlogic_pci_lib.h"
#include "lossless709_ring.h"
#include "jpg2_884_guard.h"

#define RING_SLOTS 256U
#define SLOT_BYTES 8192U
#define MAX_PACKET_BYTES 4144U

unsigned int lossless709_ring_mode;
module_param(lossless709_ring_mode, uint, 0444);
MODULE_PARM_DESC(lossless709_ring_mode, "Opt-in isolated884 JPG2 O_TRUNC continuous RX ring; default off");
static unsigned int jpg2_denied_baseline;
module_param(jpg2_denied_baseline, uint, 0444);
MODULE_PARM_DESC(jpg2_denied_baseline, "Explicit cumulative denied-write count before JPG2 capture");

extern unsigned int poll_mode;
extern unsigned int enable_st_c2h_credit;

struct lossless709_ring {
    struct sgdma_transfer transfer;
    void *data;
    dma_addr_t data_bus;
    unsigned int head;
    bool started;
    bool failed;
};

static void ring_free(struct anlogic_dma_engine *engine, struct lossless709_ring *ring)
{
    struct device *device = &engine->sgdev->pdev->dev;
    if (ring->transfer.res_virt)
        dma_free_coherent(device, RING_SLOTS * sizeof(struct sgdma_result),
                          ring->transfer.res_virt, ring->transfer.res_bus);
    if (ring->transfer.desc_virt)
        dma_free_coherent(device, RING_SLOTS * sizeof(struct sgdma_desc),
                          ring->transfer.desc_virt, ring->transfer.desc_bus);
    if (ring->data)
        dma_free_coherent(device, RING_SLOTS * SLOT_BYTES, ring->data, ring->data_bus);
    kfree(ring);
}

int lossless709_ring_open(struct anlogic_dma_engine *engine)
{
    struct lossless709_ring *ring;
    struct sgdma_transfer *transfer;
    struct device *device = &engine->sgdev->pdev->dev;
    void __iomem *user;
    unsigned int slot;
    const unsigned int offsets[] = {0x5c,0x1c0,0x1c4,0x1c8,0x1d0,0x1ec,0x1f0,
        0x60,0xa4,0x90,0x1cc,0x104,0x108,0x1d4,0x1d8,0x1dc,0x1e0,0x1e4,0x54,0x1f4};
    unsigned int values[ARRAY_SIZE(offsets)];
    if (engine->sgdev->user_bar_idx < 0 || engine->sgdev->user_bar_idx >= 6)
        return -ENODEV;
    user = engine->sgdev->bar[engine->sgdev->user_bar_idx];
    if (!user || !poll_mode || !enable_st_c2h_credit || !engine->streaming ||
        engine->dir != DMA_FROM_DEVICE || engine->channel || engine->running ||
        engine->lossless709_ring || !list_empty(&engine->transfer_list) ||
        read_register(&engine->regs->status) & SGDMA_STAT_BUSY)
        return -EBUSY;
    for (slot = 0; slot < ARRAY_SIZE(offsets); ++slot)
        values[slot] = ioread32(user + offsets[slot]);
    if (!jpg2_884_ready(values, jpg2_denied_baseline))
        return -EPROTO;
    ring = kzalloc(sizeof(*ring), GFP_KERNEL);
    if (!ring)
        return -ENOMEM;
    transfer = &ring->transfer;
    ring->data = dma_alloc_coherent(device, RING_SLOTS * SLOT_BYTES, &ring->data_bus, GFP_KERNEL);
    transfer->desc_virt = dma_alloc_coherent(device, RING_SLOTS * sizeof(struct sgdma_desc),
                                              &transfer->desc_bus, GFP_KERNEL);
    transfer->res_virt = dma_alloc_coherent(device, RING_SLOTS * sizeof(struct sgdma_result),
                                             &transfer->res_bus, GFP_KERNEL);
    if (!ring->data || !transfer->desc_virt || !transfer->res_virt) {
        ring_free(engine, ring);
        return -ENOMEM;
    }
    memset(transfer->desc_virt, 0, RING_SLOTS * sizeof(struct sgdma_desc));
    memset(transfer->res_virt, 0, RING_SLOTS * sizeof(struct sgdma_result));
    for (slot = 0; slot < RING_SLOTS; ++slot) {
        struct sgdma_desc *descriptor = &transfer->desc_virt[slot];
        dma_addr_t result = transfer->res_bus + slot * sizeof(struct sgdma_result);
        unsigned int next = (slot + 1) % RING_SLOTS;
        descriptor->control = cpu_to_le32(DESC_MAGIC | SGDMA_DESC_EOP | SGDMA_DESC_COMPLETED);
        sgdma_desc_set(descriptor, ring->data_bus + slot * SLOT_BYTES, 0, SLOT_BYTES, DMA_FROM_DEVICE);
        descriptor->src_addr_lo = cpu_to_le32(lower_32_bits(result));
        descriptor->src_addr_hi = cpu_to_le32(upper_32_bits(result));
        sgdma_desc_link(descriptor, &transfer->desc_virt[next],
                        transfer->desc_bus + next * sizeof(struct sgdma_desc));
        sgdma_desc_adjacent(descriptor, 0);
    }
    transfer->desc_num = RING_SLOTS;
    transfer->desc_adjacent = 0;
    transfer->dir = DMA_FROM_DEVICE;
    transfer->cyclic = 1;
    transfer->len = RING_SLOTS * SLOT_BYTES;
    INIT_LIST_HEAD(&transfer->entry);
    init_waitqueue_head(&transfer->wq);
    dma_wmb();
    engine->lossless709_ring = ring;
    pr_info("709 ring prepared: %u slots of %u bytes, per-EOP read without engine restart\n",
            RING_SLOTS, SLOT_BYTES);
    return 0;
}

ssize_t lossless709_ring_read(struct anlogic_dma_engine *engine,
                             char __user *buffer, size_t capacity)
{
    struct lossless709_ring *ring = engine->lossless709_ring;
    struct sgdma_result *result;
    unsigned long deadline = jiffies + msecs_to_jiffies(2000);
    u32 status, length;
    int error;
    if (!ring || ring->failed || capacity < SLOT_BYTES)
        return -EINVAL;
    if (!ring->started) {
        engine->desc_used = RING_SLOTS;
        error = transfer_queue(engine, &ring->transfer);
        if (error) {
            ring->failed = true;
            return error;
        }
        ring->started = true;
    }
    result = &ring->transfer.res_virt[ring->head];
    for (;;) {
        status = le32_to_cpu(READ_ONCE(result->status));
        if (status)
            break;
        if (signal_pending(current) || time_after_eq(jiffies, deadline)) {
            ring->failed = true;
            return signal_pending(current) ? -EINTR : -ETIMEDOUT;
        }
        usleep_range(10, 20);
    }
    dma_rmb();
    length = le32_to_cpu(READ_ONCE(result->length));
    if ((status >> 16) != C2H_WB || !(status & RX_STATUS_EOP) ||
        length < 64 || length > MAX_PACKET_BYTES || length % 16) {
        pr_err("709 ring invalid result head=%u status=%08x length=%u\n", ring->head, status, length);
        ring->failed = true;
        return -EPROTO;
    }
    if (copy_to_user(buffer, ring->data + ring->head * SLOT_BYTES, length)) {
        ring->failed = true;
        return -EFAULT;
    }
    WRITE_ONCE(result->length, 0);
    WRITE_ONCE(result->status, 0);
    dma_wmb();
    ring->head = (ring->head + 1) % RING_SLOTS;
    write_register(1, &engine->sgdma_regs->credits, 0);
    return length;
}

int lossless709_ring_close(struct anlogic_dma_engine *engine)
{
    struct lossless709_ring *ring = engine->lossless709_ring;
    u32 status;
    unsigned long flags;
    int error;
    if (!ring)
        return 0;
    if (ring->started) {
        sgdma_engine_stop(engine);
        error = readl_poll_timeout(&engine->regs->status, status,
                                   !(status & SGDMA_STAT_BUSY), 100, 100000);
        if (error) {
            ring->failed = true;
            __module_get(THIS_MODULE);
            pr_err("709 ring stop unconfirmed: retain DMA allocations and pin module; PCIe recovery required\n");
            return error;
        }
        spin_lock_irqsave(&engine->lock, flags);
        list_del_init(&ring->transfer.entry);
        engine->running = 0;
        engine->desc_used = 0;
        engine->desc_dequeued = 0;
        engine->shutdown = ENGINE_SHUTDOWN_NONE;
        spin_unlock_irqrestore(&engine->lock, flags);
    }
    engine->lossless709_ring = NULL;
    ring_free(engine, ring);
    pr_info("709 ring stopped and all DMA allocations released\n");
    return 0;
}
