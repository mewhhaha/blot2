#include "allocation_observer.h"
#include <string.h>
#include <stdlib.h>

typedef void (*event_fn)(int, uint64_t, uint64_t, uint64_t, uint64_t);
typedef int (*try_fn)(int, uint64_t, uint64_t);
typedef void (*oom_fn)(int, uint64_t);
extern void gs_runtime_observer_install(event_fn, try_fn, oom_fn) __attribute__((weak));

static blot_allocation_stats stats;
static uint64_t selected_failure;
static int selected_kind;
static oom_fn terminal_oom;

static int attempt(int kind, uint64_t owner, uint64_t bytes) {
    (void)owner;
    (void)bytes;
    stats.attempts++;
    if (selected_kind && kind != selected_kind) return 0;
    stats.matching_attempts++;
    return selected_failure && stats.matching_attempts == selected_failure;
}

static void refusal(int kind, uint64_t bytes) {
    stats.refusals++;
    stats.failure_kind = kind;
    stats.failure_bytes = bytes;
    if (terminal_oom) terminal_oom(kind, bytes);
    /* Returning from a half-mutated heap is not a supported recovery path. */
    _Exit(125);
}

static void event(int kind, uint64_t owner, uint64_t old_bytes,
                  uint64_t new_bytes, uint64_t capacity) {
    (void)owner;
    switch (kind) {
        case BLOT_OBS_POOL_ALLOC:
            stats.pool_allocations++;
            stats.pool_payload_allocated_bytes += new_bytes;
            break;
        case BLOT_OBS_POOL_REALLOC:
            stats.pool_reallocations++;
            if (new_bytes > old_bytes)
                stats.pool_payload_allocated_bytes += new_bytes - old_bytes;
            else
                stats.pool_payload_freed_bytes += old_bytes - new_bytes;
            break;
        case BLOT_OBS_POOL_FREE:
            stats.pool_frees++;
            stats.pool_payload_freed_bytes += old_bytes;
            break;
        case BLOT_OBS_POOL_CAPACITY_GROW:
            stats.pool_capacity_growth_bytes += new_bytes - old_bytes;
            break;
        case BLOT_OBS_POOL_REUSE:
            stats.pool_reuses++;
            break;
        case BLOT_OBS_REGION_RESERVE:
            stats.region_reservations++;
            stats.region_reserved_bytes += capacity;
            if (stats.region_reserved_bytes > stats.region_reserved_peak_bytes)
                stats.region_reserved_peak_bytes = stats.region_reserved_bytes;
            break;
        case BLOT_OBS_REGION_RELEASE:
            stats.region_releases++;
            /* The runtime supplies the original mapping's size, including gap. */
            stats.region_reserved_bytes -= capacity;
            break;
        case BLOT_OBS_STACK_REQUEST:
            stats.explicit_capacity_requests++;
            stats.explicit_capacity_requested_bytes += new_bytes;
            break;
        case BLOT_OBS_REGISTRY_ALLOC:
            stats.registry_allocated_bytes += new_bytes;
            break;
        default:
            /* A mismatched private ABI is a bug, never an OOM. */
            abort();
    }
}

void blot_allocation_observer_install(void (*oom)(int, uint64_t)) {
    if (!gs_runtime_observer_install) return;
    terminal_oom = oom;
    stats.coverage = BLOT_OBS_POOL_OPERATIONS | BLOT_OBS_REGION_RESERVATIONS |
        BLOT_OBS_EXPLICIT_CAPACITY_REQUESTS | BLOT_OBS_REGISTRY_ALLOCATION;
    gs_runtime_observer_install(event, attempt, refusal);
}

void blot_allocation_observer_begin(uint64_t request, uint64_t fail_at, int fail_kind) {
    uint64_t reserved = stats.region_reserved_bytes;
    uint64_t peak = stats.region_reserved_peak_bytes;
    uint32_t coverage = stats.coverage;
    memset(&stats, 0, sizeof stats);
    stats.request = request;
    stats.region_reserved_bytes = reserved;
    stats.region_reserved_peak_bytes = peak;
    stats.coverage = coverage;
    selected_failure = fail_at;
    selected_kind = fail_kind;
}

const blot_allocation_stats *blot_allocation_observer_stats(void) {
    return &stats;
}

uint64_t blot_allocation_observer_value(uint32_t field) {
    static blot_allocation_stats snapshot;
    if (field == 0) {
        snapshot = stats;
        return snapshot.coverage;
    }
    switch (field) {
        case 1: return snapshot.request;
        case 2: return snapshot.attempts;
        case 3: return snapshot.refusals;
        case 4: return snapshot.pool_allocations;
        case 5: return snapshot.pool_reallocations;
        case 6: return snapshot.pool_frees;
        case 7: return snapshot.pool_reuses;
        case 8: return snapshot.pool_payload_allocated_bytes;
        case 9: return snapshot.pool_payload_freed_bytes;
        case 10: return snapshot.pool_capacity_growth_bytes;
        case 11: return snapshot.region_reservations;
        case 12: return snapshot.region_releases;
        case 13: return snapshot.region_reserved_bytes;
        case 14: return snapshot.region_reserved_peak_bytes;
        case 15: return snapshot.explicit_capacity_requests;
        case 16: return snapshot.explicit_capacity_requested_bytes;
        case 17: return snapshot.registry_allocated_bytes;
        case 18: return snapshot.matching_attempts;
        case 19: return snapshot.failure_kind;
        default: abort();
    }
}
