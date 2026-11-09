#ifndef BLOT_REQUEST_CACHE_H
#define BLOT_REQUEST_CACHE_H
#include <stdint.h>

/* Optional Linux restart-cache queue. Exactly three artifact parts belonging
 * to one lock key; paths are owned, OS-bounded copies, payloads sealed memfds.
 * Staging never creates directories, locks or external artifact files. */
int32_t blot_request_cache_active(void);
int32_t blot_request_cache_stage_write(uint32_t part,
    const uint8_t *directory, uint64_t directory_length,
    const uint8_t *lock, uint64_t lock_length,
    const uint8_t *target, uint64_t target_length,
    const uint8_t *temporary, uint64_t temporary_length,
    const uint8_t *bytes, uint64_t length);
int32_t blot_request_cache_stage_remove(uint32_t part,
    const uint8_t *directory, uint64_t directory_length,
    const uint8_t *lock, uint64_t lock_length,
    const uint8_t *target, uint64_t target_length);
uint32_t blot_request_cache_pending(void);
void blot_request_cache_discard(void);
/* Register as the supervisor's post-adoption hook. It uses fixed storage and
 * syscalls only, holds the key's exclusive lock, and drains even on optional
 * filesystem failure. Must finish before QUIESCENT/accepted-close retirement.
 * Size/queue bounds and a ten-second userspace retry budget apply; an individual
 * filesystem syscall is subject to the host kernel's normal I/O scheduling. */
void blot_request_cache_publish(void);
#endif
