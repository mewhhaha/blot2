#ifndef BLOT_ALLOCATION_OBSERVER_H
#define BLOT_ALLOCATION_OBSERVER_H
#include <stdint.h>

/* Must match the optional private runtime ABI. These are mutation/capacity
 * failpoints, not a count of malloc calls or physical committed pages. */
enum {
    BLOT_OBS_POOL_ALLOC = 1, BLOT_OBS_POOL_REALLOC = 2, BLOT_OBS_POOL_FREE = 3,
    BLOT_OBS_REGION_RESERVE = 4, BLOT_OBS_REGISTRY_ALLOC = 5,
    BLOT_OBS_STACK_REQUEST = 6, BLOT_OBS_REGION_RELEASE = 7,
    BLOT_OBS_POOL_CAPACITY_GROW = 8, BLOT_OBS_POOL_REUSE = 9
};
enum {
    BLOT_OBS_POOL_OPERATIONS = 1u << 0,
    BLOT_OBS_REGION_RESERVATIONS = 1u << 1,
    BLOT_OBS_EXPLICIT_CAPACITY_REQUESTS = 1u << 2,
    BLOT_OBS_REGISTRY_ALLOCATION = 1u << 3,
};
typedef struct {
    uint64_t request, attempts, matching_attempts, refusals;
    uint64_t pool_allocations, pool_reallocations, pool_frees, pool_reuses;
    uint64_t pool_payload_allocated_bytes, pool_payload_freed_bytes;
    uint64_t pool_capacity_growth_bytes;
    uint64_t region_reservations, region_releases;
    uint64_t region_reserved_bytes, region_reserved_peak_bytes;
    uint64_t explicit_capacity_requests, explicit_capacity_requested_bytes;
    uint64_t registry_allocated_bytes;
    uint32_t coverage;
    int failure_kind;
    uint64_t failure_bytes;
    /* No complete pool lifetime, scratch, libc/thread/OS allocation or RSS
     * observer exists here. Consumers must emit null for those quantities. */
    uint8_t active_pool_payload_available, retained_pool_capacity_available;
    uint8_t scratch_available, rss_available, whole_runtime_fault_coverage;
} blot_allocation_stats;

/* Install before goose_init. A supplied OOM callback must terminate the failed
 * process; it may call blot_request_fail_oom(request_token). No callback or
 * observer bookkeeping allocates. Single-threaded request candidates only. */
void blot_allocation_observer_install(void (*oom)(int, uint64_t));
/* fail_at is one-based among fail_kind attempts; zero disables injection.
 * fail_kind=0 selects every covered attempt. Counters are request-local except
 * live/peak region reservations, which remain process totals across begin. */
void blot_allocation_observer_begin(uint64_t request, uint64_t fail_at, int fail_kind);
const blot_allocation_stats *blot_allocation_observer_stats(void);
/* Internal scalar bridge: field zero freezes a consistent snapshot and returns
 * its coverage; fields 1..19 follow the metrics documented in memory.goose. */
uint64_t blot_allocation_observer_value(uint32_t field);
#endif
