#ifndef LOSSLESS709_RING_H
#define LOSSLESS709_RING_H

extern unsigned int lossless709_ring_mode;
int lossless709_ring_open(struct anlogic_dma_engine *engine);
ssize_t lossless709_ring_read(struct anlogic_dma_engine *engine,
                             char __user *buffer, size_t capacity);
int lossless709_ring_close(struct anlogic_dma_engine *engine);

#endif
