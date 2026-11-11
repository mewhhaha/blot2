// Diagnosis-only LD_PRELOAD heap sampler: attributes live heap to call stacks.
// MEMSAMPLE_OUT=<prefix> writes <prefix>.<n>.txt each time sampled live bytes
// grow by another MEMSAMPLE_STEP_MB (default 1024). Not used by any build.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <malloc.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SAMPLE_BYTES (1u << 20)
#define DEPTH 24
#define LIVE_SLOTS (1u << 22)
#define STACK_SLOTS (1u << 16)

typedef struct { uintptr_t ptr; uint64_t weight; uint32_t stack; } Live;
typedef struct { uint64_t hash; uint32_t depth; void *frames[DEPTH]; uint64_t live; uint64_t total; } Stack;

static void *(*real_malloc)(size_t);
static void (*real_free)(void *);
static void *(*real_calloc)(size_t, size_t);
static void *(*real_realloc)(void *, size_t);
static Live *live;
static Stack *stacks;
static atomic_flag lock = ATOMIC_FLAG_INIT;
static __thread int inside;
static int64_t countdown = SAMPLE_BYTES;
static uint64_t live_bytes, next_dump, step;
static int dumps, ready;
static char prefix[512];
static char bootstrap[1 << 16];
static size_t bootstrap_used;

static void acquire(void) { while (atomic_flag_test_and_set_explicit(&lock, memory_order_acquire)) {} }
static void release(void) { atomic_flag_clear_explicit(&lock, memory_order_release); }

static void init(void) {
    if (ready) return;
    real_malloc = dlsym(RTLD_NEXT, "malloc");
    real_free = dlsym(RTLD_NEXT, "free");
    real_calloc = dlsym(RTLD_NEXT, "calloc");
    real_realloc = dlsym(RTLD_NEXT, "realloc");
    const char *out = getenv("MEMSAMPLE_OUT");
    if (out) snprintf(prefix, sizeof prefix, "%s", out);
    const char *mb = getenv("MEMSAMPLE_STEP_MB");
    step = (uint64_t)(mb ? atoll(mb) : 1024) << 20;
    next_dump = step;
    live = real_calloc(LIVE_SLOTS, sizeof(Live));
    stacks = real_calloc(STACK_SLOTS, sizeof(Stack));
    ready = 1;
}

static uint64_t mix(uint64_t x) { x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33; return x; }

static void dump(void) {
    if (!prefix[0]) return;
    char path[600];
    snprintf(path, sizeof path, "%s.%d.txt", prefix, dumps++);
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    dprintf(fd, "live_sampled_bytes %llu\n", (unsigned long long)live_bytes);
    for (uint32_t i = 0; i < STACK_SLOTS; i++) {
        Stack *s = &stacks[i];
        if (!s->depth || s->live < (8u << 20)) continue;
        dprintf(fd, "stack %llu %llu", (unsigned long long)s->live, (unsigned long long)s->total);
        for (uint32_t k = 0; k < s->depth; k++) dprintf(fd, " %p", s->frames[k]);
        dprintf(fd, "\n");
    }
    int maps = open("/proc/self/maps", O_RDONLY);
    if (maps >= 0) {
        char buffer[4096]; ssize_t n;
        dprintf(fd, "maps\n");
        while ((n = read(maps, buffer, sizeof buffer)) > 0) { ssize_t w = write(fd, buffer, (size_t)n); (void)w; }
        close(maps);
    }
    close(fd);
}

static void sample(void *ptr, size_t size) {
    if (!ptr || inside) return;
    inside = 1;
    void *frames[DEPTH + 2];
    int depth = backtrace(frames, DEPTH + 2) - 2;
    if (depth < 1) { inside = 0; return; }
    if (depth > DEPTH) depth = DEPTH;
    uint64_t hash = 1469598103934665603ULL;
    for (int k = 0; k < depth; k++) hash = mix(hash ^ (uintptr_t)frames[k + 2]);
    uint64_t weight = size > SAMPLE_BYTES ? size : SAMPLE_BYTES;
    acquire();
    uint32_t si = (uint32_t)hash & (STACK_SLOTS - 1);
    while (stacks[si].depth && stacks[si].hash != hash) si = (si + 1) & (STACK_SLOTS - 1);
    if (!stacks[si].depth) {
        stacks[si].hash = hash; stacks[si].depth = (uint32_t)depth;
        memcpy(stacks[si].frames, frames + 2, sizeof(void *) * (size_t)depth);
    }
    stacks[si].live += weight; stacks[si].total += weight;
    uint32_t li = (uint32_t)mix((uintptr_t)ptr) & (LIVE_SLOTS - 1);
    while (live[li].ptr && live[li].ptr != 1) li = (li + 1) & (LIVE_SLOTS - 1);
    live[li].ptr = (uintptr_t)ptr; live[li].weight = weight; live[li].stack = si;
    live_bytes += weight;
    if (live_bytes >= next_dump) { next_dump += step; dump(); }
    release();
    inside = 0;
}

static void forget(void *ptr) {
    if (!ptr || !ready) return;
    acquire();
    uint32_t li = (uint32_t)mix((uintptr_t)ptr) & (LIVE_SLOTS - 1);
    for (uint32_t probes = 0; live[li].ptr && probes < LIVE_SLOTS; probes++) {
        if (live[li].ptr == (uintptr_t)ptr) {
            stacks[live[li].stack].live -= live[li].weight;
            live_bytes -= live[li].weight;
            live[li].ptr = 1; // tombstone
            break;
        }
        li = (li + 1) & (LIVE_SLOTS - 1);
    }
    release();
}

static int counts(size_t size) {
    countdown -= (int64_t)size;
    if (countdown > 0) return 0;
    countdown = SAMPLE_BYTES;
    return 1;
}

void *malloc(size_t size) {
    if (!ready) {
        if (!real_malloc && bootstrap_used + size + 16 < sizeof bootstrap) {
            void *p = bootstrap + bootstrap_used; bootstrap_used += (size + 15) & ~(size_t)15; return p;
        }
        init();
    }
    void *p = real_malloc(size);
    if (!inside && counts(size)) sample(p, size);
    return p;
}

void free(void *ptr) {
    if ((char *)ptr >= bootstrap && (char *)ptr < bootstrap + sizeof bootstrap) return;
    if (!ready) init();
    if (!inside) forget(ptr);
    real_free(ptr);
}

void *calloc(size_t n, size_t size) {
    if (!ready) {
        if (!real_calloc) {
            size_t total = n * size;
            if (bootstrap_used + total + 16 < sizeof bootstrap) {
                void *p = bootstrap + bootstrap_used; bootstrap_used += (total + 15) & ~(size_t)15;
                memset(p, 0, total); return p;
            }
        }
        init();
    }
    void *p = real_calloc(n, size);
    if (!inside && counts(n * size)) sample(p, n * size);
    return p;
}

void *realloc(void *ptr, size_t size) {
    if (!ready) init();
    if ((char *)ptr >= bootstrap && (char *)ptr < bootstrap + sizeof bootstrap) {
        void *p = real_malloc(size); memcpy(p, ptr, size); return p;
    }
    if (!inside) forget(ptr);
    void *p = real_realloc(ptr, size);
    if (!inside && counts(size)) sample(p, size);
    return p;
}
