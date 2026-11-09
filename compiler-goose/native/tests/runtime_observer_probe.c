#include "allocation_observer.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>
extern void goose_init(int, char **);
extern int64_t observer_probe(void);
extern void observer_invalid(int64_t);
extern void observer_report(void);
extern void gs_release_regions(void);
extern void gs_panic(const char *);
static void oom(int kind, uint64_t bytes) {
    (void)kind; (void)bytes;
    static const char marker[]="OBSERVER_OOM\n";
    (void)write(STDERR_FILENO, marker, sizeof marker-1);
    _Exit(73);
}
int main(int argc, char **argv) {
    const char *mode="normal";
    if (argc>1) mode=argv[1];
    blot_allocation_observer_install(oom);
    uint64_t ordinal=0;
    int kind=0;
    if (!strcmp(mode,"inject")) {
        assert(argc==4);
        ordinal=strtoull(argv[2],NULL,10);
        kind=atoi(argv[3]);
    }
    blot_allocation_observer_begin(123,ordinal,kind);
    if (!strcmp(mode,"allocator-refusal")) {
        struct rlimit limit={1,1};
        assert(!setrlimit(RLIMIT_AS,&limit));
    }
    goose_init(argc,argv);
    if (!strcmp(mode,"panic")) gs_panic("probe panic");
    if (!strcmp(mode,"signal")) *(volatile unsigned char *)(uintptr_t)1=0;
    if (!strcmp(mode,"kill")) kill(getpid(),SIGKILL);
    if (!strcmp(mode,"invalid")) observer_invalid(-1);
    assert(observer_probe()==18);
    const blot_allocation_stats *s=blot_allocation_observer_stats();
    assert(s->pool_allocations==6 && s->pool_reallocations==2 && s->pool_frees==4);
    assert(s->pool_reuses==2 && s->pool_payload_allocated_bytes==112);
    assert(s->pool_payload_freed_bytes==96 && s->pool_capacity_growth_bytes==104);
    assert(s->region_reserved_bytes>0 && s->region_reservations>0);
    assert(s->explicit_capacity_requests>0 && s->registry_allocated_bytes>0);
    assert(!s->active_pool_payload_available && !s->retained_pool_capacity_available);
    assert(!s->scratch_available && !s->rss_available && !s->whole_runtime_fault_coverage);
    if (!strcmp(mode,"report")) { observer_report(); return 0; }
    uint64_t reserved=s->region_reserved_bytes;
    gs_release_regions();
    assert(s->region_reserved_bytes==0 && s->region_releases==s->region_reservations);
    printf("{\"attempts\":%llu,\"matchingAttempts\":%llu,\"poolAllocations\":%llu,"
           "\"poolReallocations\":%llu,\"poolFrees\":%llu,\"poolReuses\":%llu,"
           "\"poolPayloadAllocatedBytes\":%llu,\"poolPayloadFreedBytes\":%llu,"
           "\"poolCapacityGrowthBytes\":%llu,\"regionReservedBytesBeforeRelease\":%llu,"
           "\"activePoolPayload\":null,\"retainedPoolCapacity\":null,\"scratch\":null,\"rss\":null}\n",
           (unsigned long long)s->attempts,(unsigned long long)s->matching_attempts,
           (unsigned long long)s->pool_allocations,(unsigned long long)s->pool_reallocations,
           (unsigned long long)s->pool_frees,(unsigned long long)s->pool_reuses,
           (unsigned long long)s->pool_payload_allocated_bytes,(unsigned long long)s->pool_payload_freed_bytes,
           (unsigned long long)s->pool_capacity_growth_bytes,(unsigned long long)reserved);
    return 0;
}
