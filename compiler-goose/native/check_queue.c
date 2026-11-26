#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __linux__
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
extern uint64_t blot_clock_ns(void);
#endif

/* Inherited by the fixed fork group. The graph and packet descriptors are
 * shared, while the arena commits pages only as producers publish bytes. */
#ifdef __linux__
enum {
    PERSIST_MAX_NODES = 16384,
    PERSIST_WAIT_NS = 20 * 1000 * 1000,
};
/* Demand-paged virtual reservation: untouched pages consume zero RSS. */
static const size_t PERSIST_ARENA_CAPACITY = (size_t)2 * 1024 * 1024 * 1024;
static const uint64_t persist_timeout = UINT64_C(15000000000);

struct persist_packet {
    uint64_t offset;
    uint64_t length;
    bool ready;
};
struct persist_node {
    struct persist_packet packets[2];
    uint32_t priority;
    uint32_t pending;
    uint32_t consumers;
    pid_t owner;
    bool configured;
    bool finished;
};
struct persist_queue {
    pthread_mutex_t mutex;
    _Atomic uint32_t generation;
    _Atomic uint32_t waiters;
    uint64_t deadline;
    size_t map_length;
    uint64_t arena_used;
    uint32_t count;
    uint32_t edge_words;
    uint32_t configured;
    uint32_t active;
    uint32_t finished;
    uint32_t ready_len;
    int failure;
    bool sealed;
    struct persist_node nodes[];
};

static struct persist_queue *persist_queue(uint64_t handle) {
    return (struct persist_queue *)(uintptr_t)handle;
}

static uint32_t *persist_heap(struct persist_queue *queue) {
    size_t end = offsetof(struct persist_queue, nodes) +
                 queue->count * sizeof(struct persist_node);
    return (uint32_t *)((uint8_t *)queue + (end + 7) / 8 * 8);
}

static uint64_t *persist_edges(struct persist_queue *queue) {
    size_t end = offsetof(struct persist_queue, nodes) +
                 queue->count * sizeof(struct persist_node);
    size_t heap_end = (end + 7) / 8 * 8 + queue->count * sizeof(uint32_t);
    return (uint64_t *)((uint8_t *)queue + (heap_end + 7) / 8 * 8);
}

static uint8_t *persist_arena(struct persist_queue *queue) {
    return (uint8_t *)(persist_edges(queue) + queue->count * queue->edge_words);
}

static bool persist_higher(const struct persist_queue *queue, uint32_t a, uint32_t b) {
    uint32_t pa = queue->nodes[a].priority;
    uint32_t pb = queue->nodes[b].priority;
    return pa > pb || (pa == pb && a < b);
}

static void persist_heap_push(struct persist_queue *queue, uint32_t idx) {
    uint32_t *heap = persist_heap(queue);
    uint32_t pos = queue->ready_len++;
    while (pos > 0) {
        uint32_t parent = (pos - 1) >> 1;
        if (!persist_higher(queue, idx, heap[parent])) break;
        heap[pos] = heap[parent];
        pos = parent;
    }
    heap[pos] = idx;
}

static uint32_t persist_heap_pop(struct persist_queue *queue) {
    uint32_t *heap = persist_heap(queue);
    uint32_t top = heap[0];
    uint32_t last = heap[--queue->ready_len];
    uint32_t n = queue->ready_len;
    if (n > 0) {
        uint32_t pos = 0;
        for (;;) {
            uint32_t left = (pos << 1) + 1;
            if (left >= n) break;
            uint32_t best = left;
            uint32_t right = left + 1;
            if (right < n && persist_higher(queue, heap[right], heap[left])) best = right;
            if (!persist_higher(queue, heap[best], last)) break;
            heap[pos] = heap[best];
            pos = best;
        }
        heap[pos] = last;
    }
    return top;
}

static void persist_notify(struct persist_queue *queue) {
    atomic_fetch_add_explicit(&queue->generation, 1, memory_order_release);
    if (atomic_load_explicit(&queue->waiters, memory_order_acquire) != 0) {
        (void)syscall(SYS_futex, &queue->generation, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
    }
}

static int persist_lock(struct persist_queue *queue) {
    int error = pthread_mutex_lock(&queue->mutex);
    if (error == EOWNERDEAD) {
        queue->failure = EOWNERDEAD;
        int recovered = pthread_mutex_consistent(&queue->mutex);
        persist_notify(queue);
        if (recovered != 0) {
            pthread_mutex_unlock(&queue->mutex);
            return recovered;
        }
        return 0;
    }
    return error;
}

static void persist_fail_locked(struct persist_queue *queue, int error) {
    if (queue->failure == 0) queue->failure = error;
    persist_notify(queue);
}

uint8_t blot_available_workers(void) {
    cpu_set_t cpus;
    if (sched_getaffinity(0, sizeof(cpus), &cpus) < 0) return 1;
    int count = CPU_COUNT(&cpus);
    if (count < 1) return 1;
    if (count > 16) return 16;
    return (uint8_t)count;
}

// These unreaped children belong to the current build. Abort all siblings
// before joining, including a lane that stopped while outside the queue.
void blot_persist_kill_child(uint32_t pid) {
    if (pid > 0) (void)kill((pid_t)pid, SIGKILL);
}

uint64_t blot_persist_open(uint32_t count) {
    if (count == 0 || count > PERSIST_MAX_NODES) return 0;
    uint32_t words = (count + 63) / 64;
    size_t end = offsetof(struct persist_queue, nodes) + count * sizeof(struct persist_node);
    size_t heap_end = (end + 7) / 8 * 8 + count * sizeof(uint32_t);
    size_t graph_bytes = (heap_end + 7) / 8 * 8 + count * words * sizeof(uint64_t);
    size_t map_length = graph_bytes + PERSIST_ARENA_CAPACITY;
    struct persist_queue *queue = mmap(NULL, map_length, PROT_READ | PROT_WRITE,
                                      MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (queue == MAP_FAILED) return 0;

    pthread_mutexattr_t attrs;
    int error = pthread_mutexattr_init(&attrs);
    if (error == 0) {
        error = pthread_mutexattr_setpshared(&attrs, PTHREAD_PROCESS_SHARED);
        if (error == 0) error = pthread_mutexattr_setrobust(&attrs, PTHREAD_MUTEX_ROBUST);
        if (error == 0) error = pthread_mutex_init(&queue->mutex, &attrs);
        pthread_mutexattr_destroy(&attrs);
    }
    if (error != 0) {
        munmap(queue, map_length);
        return 0;
    }

    atomic_init(&queue->generation, 0);
    atomic_init(&queue->waiters, 0);
    queue->map_length = map_length;
    queue->count = count;
    queue->edge_words = words;
    return (uint64_t)(uintptr_t)queue;
}

bool blot_persist_node(uint64_t h, uint32_t id, uint32_t priority) {
    struct persist_queue *queue = persist_queue(h);
    if (!queue || id == 0 || id > queue->count || persist_lock(queue) != 0) return false;
    bool valid = !queue->sealed && queue->failure == 0 && !queue->nodes[id - 1].configured;
    if (valid) {
        struct persist_node *node = &queue->nodes[id - 1];
        node->configured = true;
        node->priority = priority;
        queue->configured++;
    }
    pthread_mutex_unlock(&queue->mutex);
    return valid;
}

bool blot_persist_edge(uint64_t h, uint32_t consumer, uint32_t producer) {
    struct persist_queue *queue = persist_queue(h);
    if (!queue || consumer == 0 || producer == 0 || consumer == producer ||
        consumer > queue->count || producer > queue->count || persist_lock(queue) != 0)
        return false;

    --consumer;
    --producer;
    bool valid = !queue->sealed && queue->failure == 0 &&
                 queue->nodes[consumer].configured && queue->nodes[producer].configured;
    if (valid) {
        uint64_t *words = persist_edges(queue) + producer * queue->edge_words;
        uint64_t bit = UINT64_C(1) << (consumer % 64);
        if ((words[consumer / 64] & bit) == 0) {
            words[consumer / 64] |= bit;
            queue->nodes[consumer].pending++;
            queue->nodes[producer].consumers++;
        }
    }
    pthread_mutex_unlock(&queue->mutex);
    return valid;
}

static bool persist_worker_exited(pid_t pid, pid_t caller) {
    if (pid == 0 || pid == caller) return false;
    siginfo_t result = {0};
    if (waitid(P_PID, (id_t)pid, &result, WEXITED | WNOHANG | WNOWAIT) == 0)
        return result.si_pid == pid;
    return kill(pid, 0) < 0 && errno == ESRCH;
}

int64_t blot_persist_claim(uint64_t h) {
    struct persist_queue *queue = persist_queue(h);
    if (!queue) return -EINVAL;
    pid_t caller = getpid();
    for (;;) {
        int error = persist_lock(queue);
        if (error != 0) return -error;
        uint64_t now = blot_clock_ns();
        if (!queue->sealed) {
            queue->sealed = true;
            queue->deadline = now + persist_timeout;
            if (queue->count != queue->configured) {
                persist_fail_locked(queue, EINVAL);
            } else {
                queue->ready_len = 0;
                for (uint32_t i = 0; i < queue->count; ++i) {
                    if (queue->nodes[i].pending == 0) persist_heap_push(queue, i);
                }
            }
        }
        if (queue->failure == 0 && queue->finished == queue->count) {
            pthread_mutex_unlock(&queue->mutex);
            return 0;
        }
        if (queue->failure == 0 && now >= queue->deadline)
            persist_fail_locked(queue, ETIMEDOUT);
        if (queue->failure != 0) {
            error = queue->failure;
            pthread_mutex_unlock(&queue->mutex);
            return -error;
        }

        if (queue->ready_len != 0) {
            uint32_t best = persist_heap_pop(queue);
            queue->nodes[best].owner = caller;
            queue->active++;
            pthread_mutex_unlock(&queue->mutex);
            return best + 1;
        }
        if (queue->active == 0) {
            persist_fail_locked(queue, EDEADLK);
            pthread_mutex_unlock(&queue->mutex);
            return -EDEADLK;
        }
        for (uint32_t i = 0; i < queue->count; ++i) {
            if (!persist_worker_exited(queue->nodes[i].owner, caller)) continue;
            persist_fail_locked(queue, ECHILD);
            pthread_mutex_unlock(&queue->mutex);
            return -ECHILD;
        }
        uint32_t generation = atomic_load_explicit(&queue->generation, memory_order_relaxed);
        atomic_fetch_add_explicit(&queue->waiters, 1, memory_order_acq_rel);
        uint64_t remaining = queue->deadline - now;
        if (remaining > PERSIST_WAIT_NS) remaining = PERSIST_WAIT_NS;
        struct timespec wait = { .tv_nsec = (long)remaining };
        pthread_mutex_unlock(&queue->mutex);
        (void)syscall(SYS_futex, &queue->generation, FUTEX_WAIT, generation, &wait, NULL, 0);
        atomic_fetch_sub_explicit(&queue->waiters, 1, memory_order_release);
    }
}

static bool persist_valid_packet(const struct persist_queue *queue, uint32_t id, uint32_t kind) {
    return queue && id != 0 && id <= queue->count && kind != 0 && kind <= 2;
}

bool blot_persist_publish(uint64_t h, uint32_t id, uint32_t kind,
                          const uint8_t *bytes, uint64_t len) {
    struct persist_queue *queue = persist_queue(h);
    if (!persist_valid_packet(queue, id, kind) || !bytes || len == 0 ||
        persist_lock(queue) != 0)
        return false;
    struct persist_node *node = &queue->nodes[id - 1];
    struct persist_packet *packet = &node->packets[kind - 1];
    bool valid = queue->failure == 0 && node->owner == getpid() && packet->length == 0 &&
                 (kind == 1 || node->consumers == 0 || node->packets[0].ready);
    if (valid && len > PERSIST_ARENA_CAPACITY - queue->arena_used) {
        persist_fail_locked(queue, ENOSPC);
        valid = false;
    }
    if (!valid) {
        pthread_mutex_unlock(&queue->mutex);
        return false;
    }
    uint64_t offset = queue->arena_used;
    packet->offset = offset;
    packet->length = len;
    queue->arena_used += len;
    pthread_mutex_unlock(&queue->mutex);

    /* Readers only see a length after the copy commits under the mutex. */
    memcpy(persist_arena(queue) + offset, bytes, (size_t)len);

    if (persist_lock(queue) != 0) return false;
    if (queue->failure != 0) {
        pthread_mutex_unlock(&queue->mutex);
        return false;
    }
    packet->ready = true;
    if (kind == 1) {
        const uint64_t *words = persist_edges(queue) + (id - 1) * queue->edge_words;
        for (uint32_t w = 0; w < queue->edge_words; ++w) {
            for (uint64_t bits = words[w]; bits != 0; bits &= bits - 1) {
                uint32_t consumer = w * 64 + (uint32_t)__builtin_ctzll(bits);
                if (--queue->nodes[consumer].pending == 0) {
                    persist_heap_push(queue, consumer);
                }
            }
        }
    } else {
        node->owner = 0;
        node->finished = true;
        queue->active--;
        queue->finished++;
    }
    persist_notify(queue);
    pthread_mutex_unlock(&queue->mutex);
    return true;
}

int64_t blot_persist_size(uint64_t h, uint32_t id, uint32_t kind) {
    struct persist_queue *queue = persist_queue(h);
    if (!persist_valid_packet(queue, id, kind)) return -EINVAL;
    int error = persist_lock(queue);
    if (error != 0) return -error;
    const struct persist_packet *packet = &queue->nodes[id - 1].packets[kind - 1];
    int64_t result = 0;
    if (queue->failure != 0) result = -queue->failure;
    else if (packet->ready) result = packet->length;
    pthread_mutex_unlock(&queue->mutex);
    return result;
}

bool blot_persist_read(uint64_t h, uint32_t id, uint32_t kind, uint8_t *bytes, uint64_t len) {
    struct persist_queue *queue = persist_queue(h);
    if (!persist_valid_packet(queue, id, kind) || !bytes || len == 0 ||
        persist_lock(queue) != 0)
        return false;
    struct persist_packet packet = queue->nodes[id - 1].packets[kind - 1];
    bool valid = queue->failure == 0 && packet.ready && packet.length == len;
    pthread_mutex_unlock(&queue->mutex);
    if (valid) memcpy(bytes, persist_arena(queue) + packet.offset, (size_t)len);
    return valid;
}

void blot_persist_fail(uint64_t h) {
    struct persist_queue *queue = persist_queue(h);
    if (!queue || persist_lock(queue) != 0) return;
    persist_fail_locked(queue, ECANCELED);
    pthread_mutex_unlock(&queue->mutex);
}

void blot_persist_close(uint64_t h) {
    struct persist_queue *queue = persist_queue(h);
    if (queue) munmap(queue, queue->map_length);
}

/* Persistent lock-free shared-memory wave pool for parallel Wasm emission.
 * Forked once per emitAll; waves wake workers with a single futex wake and
 * claim job chunks with a single atomic fetch_add (no mutexes, no per-job
 * syscalls, no per-wave forks). */
enum {
    EMIT_POOL_MAX_WORKERS = 16,
    EMIT_POOL_SYNC_CAP = 64 * 1024 * 1024,
    EMIT_POOL_LANE_CAP = 64 * 1024 * 1024,
};
struct emit_pool {
    _Atomic uint32_t wave_gen;
    _Atomic uint32_t next_job;
    _Atomic uint32_t done_workers;
    _Atomic uint32_t failed;
    pid_t parent_pid;
    uint32_t worker_count;
    uint32_t job_count;
    uint32_t chunk_size;
    uint64_t sync_len;
    uint64_t lane_used[EMIT_POOL_MAX_WORKERS];
    size_t map_length;
};
static struct emit_pool *emit_pool_ptr(uint64_t h) {
    return (struct emit_pool *)(uintptr_t)h;
}
static size_t emit_pool_header_size(void) {
    size_t s = sizeof(struct emit_pool);
    return (s + 4095) & ~(size_t)4095;
}
static uint8_t *emit_pool_sync_buf(struct emit_pool *p) {
    return (uint8_t *)p + emit_pool_header_size();
}
static uint8_t *emit_pool_lane_buf(struct emit_pool *p, uint32_t lane) {
    return emit_pool_sync_buf(p) + (size_t)EMIT_POOL_SYNC_CAP +
           (size_t)lane * (size_t)EMIT_POOL_LANE_CAP;
}
uint64_t blot_emit_pool_open(uint32_t workers) {
    if (workers == 0 || workers > EMIT_POOL_MAX_WORKERS) return 0;
    size_t map_len = emit_pool_header_size() + (size_t)EMIT_POOL_SYNC_CAP +
                     (size_t)workers * (size_t)EMIT_POOL_LANE_CAP;
    struct emit_pool *p = mmap(NULL, map_len, PROT_READ | PROT_WRITE,
                               MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return 0;
    atomic_init(&p->wave_gen, 0);
    atomic_init(&p->next_job, 0);
    atomic_init(&p->done_workers, 0);
    atomic_init(&p->failed, 0);
    p->parent_pid = getpid();
    p->worker_count = workers;
    p->map_length = map_len;
    return (uint64_t)(uintptr_t)p;
}
void blot_emit_pool_close(uint64_t h) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (p) munmap(p, p->map_length);
}
void blot_emit_pool_stop(uint64_t h) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p) return;
    atomic_store_explicit(&p->wave_gen, UINT32_MAX, memory_order_release);
    (void)syscall(SYS_futex, &p->wave_gen, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
}
bool blot_emit_pool_begin_wave(uint64_t h, uint32_t job_count, uint32_t chunk_size,
                               const uint8_t *sync_bytes, uint64_t sync_len) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p || sync_len > EMIT_POOL_SYNC_CAP || chunk_size == 0) return false;
    if (sync_len != 0) memcpy(emit_pool_sync_buf(p), sync_bytes, (size_t)sync_len);
    p->job_count = job_count;
    p->chunk_size = chunk_size;
    p->sync_len = sync_len;
    for (uint32_t i = 0; i < p->worker_count; ++i) p->lane_used[i] = 0;
    atomic_store_explicit(&p->next_job, 0, memory_order_relaxed);
    atomic_store_explicit(&p->done_workers, 0, memory_order_relaxed);
    atomic_fetch_add_explicit(&p->wave_gen, 1, memory_order_release);
    (void)syscall(SYS_futex, &p->wave_gen, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
    return true;
}
bool blot_emit_pool_wait_wave(uint64_t h, const uint32_t *pids, uint32_t pid_count) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p) return false;
    pid_t caller = getpid();
    uint64_t deadline = blot_clock_ns() + persist_timeout;
    for (;;) {
        uint32_t done = atomic_load_explicit(&p->done_workers, memory_order_acquire);
        if (atomic_load_explicit(&p->failed, memory_order_acquire) != 0) return false;
        if (done >= p->worker_count) return true;
        uint64_t now = blot_clock_ns();
        if (now >= deadline) {
            atomic_store_explicit(&p->failed, 1, memory_order_release);
            return false;
        }
        for (uint32_t i = 0; i < pid_count; ++i) {
            if (pids[i] != 0 && persist_worker_exited((pid_t)pids[i], caller)) {
                atomic_store_explicit(&p->failed, 1, memory_order_release);
                return false;
            }
        }
        uint64_t remaining = deadline - now;
        if (remaining > PERSIST_WAIT_NS) remaining = PERSIST_WAIT_NS;
        struct timespec wait = { .tv_nsec = (long)remaining };
        (void)syscall(SYS_futex, &p->done_workers, FUTEX_WAIT, done, &wait, NULL, 0);
    }
}
int64_t blot_emit_pool_worker_wait(uint64_t h, uint32_t last_gen) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p) return 0;
    for (;;) {
        uint32_t gen = atomic_load_explicit(&p->wave_gen, memory_order_acquire);
        if (gen == UINT32_MAX || atomic_load_explicit(&p->failed, memory_order_acquire) != 0)
            return 0;
        if (gen != last_gen) return (int64_t)gen;
        if (getppid() != p->parent_pid) return 0;
        struct timespec wait = { .tv_nsec = PERSIST_WAIT_NS };
        (void)syscall(SYS_futex, &p->wave_gen, FUTEX_WAIT, last_gen, &wait, NULL, 0);
    }
}
uint64_t blot_emit_pool_sync_len(uint64_t h) {
    struct emit_pool *p = emit_pool_ptr(h);
    return p ? p->sync_len : 0;
}
bool blot_emit_pool_sync_read(uint64_t h, uint8_t *out, uint64_t len) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p || len > p->sync_len) return false;
    if (len != 0) memcpy(out, emit_pool_sync_buf(p), (size_t)len);
    return true;
}
uint64_t blot_emit_pool_claim_chunk(uint64_t h) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p) return 0;
    uint32_t start = atomic_fetch_add_explicit(&p->next_job, p->chunk_size, memory_order_relaxed);
    if (start >= p->job_count) return 0;
    uint32_t end = start + p->chunk_size;
    if (end > p->job_count) end = p->job_count;
    return ((uint64_t)start << 32) | (uint64_t)end;
}
bool blot_emit_pool_lane_append(uint64_t h, uint32_t lane, uint32_t job_idx,
                                const uint8_t *pkt, uint64_t len) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p || lane >= p->worker_count) return false;
    uint64_t used = p->lane_used[lane];
    if (len > EMIT_POOL_LANE_CAP || used + 8 + len > EMIT_POOL_LANE_CAP) return false;
    uint8_t *dst = emit_pool_lane_buf(p, lane) + used;
    uint32_t hdr[2] = { job_idx, (uint32_t)len };
    memcpy(dst, hdr, 8);
    if (len != 0) memcpy(dst + 8, pkt, (size_t)len);
    p->lane_used[lane] = used + 8 + len;
    return true;
}
void blot_emit_pool_worker_done(uint64_t h, bool ok) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p) return;
    if (!ok) atomic_store_explicit(&p->failed, 1, memory_order_release);
    uint32_t prev = atomic_fetch_add_explicit(&p->done_workers, 1, memory_order_acq_rel);
    if (prev + 1 >= p->worker_count || !ok) {
        (void)syscall(SYS_futex, &p->done_workers, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
    }
}
uint64_t blot_emit_pool_lane_size(uint64_t h, uint32_t lane) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p || lane >= p->worker_count) return 0;
    return p->lane_used[lane];
}
bool blot_emit_pool_lane_read(uint64_t h, uint32_t lane, uint8_t *out, uint64_t len) {
    struct emit_pool *p = emit_pool_ptr(h);
    if (!p || lane >= p->worker_count || len > p->lane_used[lane]) return false;
    if (len != 0) memcpy(out, emit_pool_lane_buf(p, lane), (size_t)len);
    return true;
}
#else
uint8_t blot_available_workers(void) { return 1; }
void blot_persist_kill_child(uint32_t pid) { (void)pid; }
uint64_t blot_persist_open(uint32_t count) { (void)count; return 0; }
bool blot_persist_node(uint64_t h, uint32_t id, uint32_t priority) {
    (void)h; (void)id; (void)priority; return false;
}
bool blot_persist_edge(uint64_t h, uint32_t consumer, uint32_t producer) {
    (void)h; (void)consumer; (void)producer; return false;
}
int64_t blot_persist_claim(uint64_t h) { (void)h; return -ENOTSUP; }
bool blot_persist_publish(uint64_t h, uint32_t id, uint32_t kind,
                          const uint8_t *bytes, uint64_t len) {
    (void)h; (void)id; (void)kind; (void)bytes; (void)len; return false;
}
int64_t blot_persist_size(uint64_t h, uint32_t id, uint32_t kind) {
    (void)h; (void)id; (void)kind; return -ENOTSUP;
}
bool blot_persist_read(uint64_t h, uint32_t id, uint32_t kind,
                       uint8_t *bytes, uint64_t len) {
    (void)h; (void)id; (void)kind; (void)bytes; (void)len; return false;
}
void blot_persist_fail(uint64_t h) { (void)h; }
void blot_persist_close(uint64_t h) { (void)h; }
uint64_t blot_emit_pool_open(uint32_t workers) { (void)workers; return 0; }
void blot_emit_pool_close(uint64_t h) { (void)h; }
void blot_emit_pool_stop(uint64_t h) { (void)h; }
bool blot_emit_pool_begin_wave(uint64_t h, uint32_t job_count, uint32_t chunk_size,
                               const uint8_t *sync_bytes, uint64_t sync_len) {
    (void)h; (void)job_count; (void)chunk_size; (void)sync_bytes; (void)sync_len; return false;
}
bool blot_emit_pool_wait_wave(uint64_t h, const uint32_t *pids, uint32_t pid_count) {
    (void)h; (void)pids; (void)pid_count; return false;
}
int64_t blot_emit_pool_worker_wait(uint64_t h, uint32_t last_gen) { (void)h; (void)last_gen; return 0; }
uint64_t blot_emit_pool_sync_len(uint64_t h) { (void)h; return 0; }
bool blot_emit_pool_sync_read(uint64_t h, uint8_t *out, uint64_t len) { (void)h; (void)out; (void)len; return false; }
uint64_t blot_emit_pool_claim_chunk(uint64_t h) { (void)h; return 0; }
bool blot_emit_pool_lane_append(uint64_t h, uint32_t lane, uint32_t job_idx,
                                const uint8_t *pkt, uint64_t len) {
    (void)h; (void)lane; (void)job_idx; (void)pkt; (void)len; return false;
}
void blot_emit_pool_worker_done(uint64_t h, bool ok) { (void)h; (void)ok; }
uint64_t blot_emit_pool_lane_size(uint64_t h, uint32_t lane) { (void)h; (void)lane; return 0; }
bool blot_emit_pool_lane_read(uint64_t h, uint32_t lane, uint8_t *out, uint64_t len) {
    (void)h; (void)lane; (void)out; (void)len; return false;
}
#endif
