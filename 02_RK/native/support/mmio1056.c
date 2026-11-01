#include <stdint.h>
#include <stddef.h>
/* Device BAR writes must be one aligned word store, with no preliminary clear. */
int mmio1056_write32(void *base, uint32_t offset, uint32_t value) {
    if (!base || ((uintptr_t)base & 3u) || (offset & 3u) || offset > 4092u) return -1;
    __asm__ __volatile__("dmb oshst" ::: "memory");
    *(volatile uint32_t *)((volatile uint8_t *)base + offset) = value;
    __asm__ __volatile__("dsb oshst" ::: "memory");
    return 0;
}
