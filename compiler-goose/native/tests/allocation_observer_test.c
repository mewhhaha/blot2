#include "allocation_observer.h"
#include <assert.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdlib.h>

typedef void (*event_fn)(int, uint64_t, uint64_t, uint64_t, uint64_t);
typedef int (*try_fn)(int, uint64_t, uint64_t);
typedef void (*oom_fn)(int, uint64_t);
static event_fn emit;
static try_fn try_allocation;
static oom_fn refuse;
void gs_runtime_observer_install(event_fn e, try_fn t, oom_fn o) {
    emit = e; try_allocation = t; refuse = o;
}
static void terminal(int kind, uint64_t bytes) {
    assert(kind == BLOT_OBS_POOL_ALLOC && bytes == 16);
    const blot_allocation_stats *s = blot_allocation_observer_stats();
    assert(s->request == 43 && s->refusals == 1 && s->failure_kind == kind);
    _Exit(73);
}
int main(void) {
    blot_allocation_observer_install(terminal);
    blot_allocation_observer_begin(42, 2, BLOT_OBS_POOL_ALLOC);
    assert(!try_allocation(BLOT_OBS_STACK_REQUEST, 1, 24));
    assert(!try_allocation(BLOT_OBS_POOL_ALLOC, 1, 16));
    assert(try_allocation(BLOT_OBS_POOL_ALLOC, 1, 16));
    emit(BLOT_OBS_POOL_ALLOC, 1, 0, 24, 24);
    emit(BLOT_OBS_POOL_CAPACITY_GROW, 1, 0, 24, 0);
    emit(BLOT_OBS_POOL_FREE, 1, 8, 0, 0);
    emit(BLOT_OBS_POOL_ALLOC, 1, 0, 8, 24);
    emit(BLOT_OBS_POOL_REUSE, 1, 0, 8, 0);
    emit(BLOT_OBS_POOL_REALLOC, 1, 24, 40, 40);
    emit(BLOT_OBS_POOL_CAPACITY_GROW, 1, 24, 40, 0);
    emit(BLOT_OBS_POOL_REALLOC, 1, 40, 16, 40);
    emit(BLOT_OBS_REGION_RESERVE, 3, 0, 1024, 1088);
    emit(BLOT_OBS_STACK_REQUEST, 2, 0, 24, 1024);
    emit(BLOT_OBS_REGISTRY_ALLOC, 4, 0, 96, 0);
    const blot_allocation_stats *s = blot_allocation_observer_stats();
    assert(s->attempts == 3 && s->matching_attempts == 2);
    assert(s->pool_allocations == 2 && s->pool_frees == 1);
    assert(s->pool_reallocations == 2 && s->pool_reuses == 1);
    assert(s->pool_payload_allocated_bytes == 48 && s->pool_payload_freed_bytes == 32);
    assert(s->pool_capacity_growth_bytes == 40 && s->region_reserved_bytes == 1088);
    assert(s->explicit_capacity_requested_bytes == 24 && s->registry_allocated_bytes == 96);
    assert(s->coverage == 15 && !s->active_pool_payload_available && !s->scratch_available);
    assert(!s->retained_pool_capacity_available && !s->rss_available && !s->whole_runtime_fault_coverage);
    assert(blot_allocation_observer_value(0) == 15);
    assert(blot_allocation_observer_value(4) == 2);
    emit(BLOT_OBS_POOL_ALLOC, 1, 0, 8, 40);
    assert(blot_allocation_observer_value(4) == 2); /* A pinned reporting snapshot. */
    assert(blot_allocation_observer_value(0) == 15 && blot_allocation_observer_value(4) == 3);
    blot_allocation_observer_begin(43, 1, BLOT_OBS_POOL_ALLOC);
    assert(s->region_reserved_bytes == 1088 && s->pool_allocations == 0 && s->request == 43);
    emit(BLOT_OBS_REGION_RELEASE, 3, 1024, 0, 1088);
    assert(s->region_reserved_bytes == 0 && s->region_reserved_peak_bytes == 1088);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) { refuse(BLOT_OBS_POOL_ALLOC, 16); _Exit(99); }
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 73);
    assert(s->refusals == 0); /* Rejected candidate never mutates its parent. */
    return 0;
}
