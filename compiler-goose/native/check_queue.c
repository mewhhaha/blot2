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
    PERSIST_MAX_NODES = 2048,
    PERSIST_ARENA_CAPACITY = 192 * 1024 * 1024,
    PERSIST_WAIT_NS = 20 * 1000 * 1000,
};
static const uint64_t persist_timeout = UINT64_C(15000000000);

struct persist_packet {
    uint32_t offset;
    uint32_t length;
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
    uint64_t deadline;
    size_t map_length;
    uint32_t count;
    uint32_t edge_words;
    uint32_t configured;
    uint32_t active;
    uint32_t finished;
    uint32_t arena_used;
    int failure;
    bool sealed;
    struct persist_node nodes[];
};

static struct persist_queue *persist_queue(uint64_t handle) {
    return (struct persist_queue *)(uintptr_t)handle;
}

static uint64_t *persist_edges(struct persist_queue *queue) {
    size_t end = offsetof(struct persist_queue, nodes) +
                 queue->count * sizeof(struct persist_node);
    return (uint64_t *)((uint8_t *)queue + (end + 7) / 8 * 8);
}

static uint8_t *persist_arena(struct persist_queue *queue) {
    return (uint8_t *)(persist_edges(queue) + queue->count * queue->edge_words);
}

static void persist_notify(struct persist_queue *queue) {
    atomic_fetch_add_explicit(&queue->generation, 1, memory_order_release);
    (void)syscall(SYS_futex, &queue->generation, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
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
    if (count > 8) return 8;
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
    size_t graph_bytes = (end + 7) / 8 * 8 + count * words * sizeof(uint64_t);
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
            if (queue->count != queue->configured) persist_fail_locked(queue, EINVAL);
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

        uint32_t best = UINT32_MAX;
        for (uint32_t i = 0; i < queue->count; ++i) {
            const struct persist_node *node = &queue->nodes[i];
            if (node->finished || node->owner != 0 || node->pending != 0) continue;
            if (best == UINT32_MAX || node->priority > queue->nodes[best].priority) best = i;
        }
        if (best != UINT32_MAX) {
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
        uint64_t remaining = queue->deadline - now;
        if (remaining > PERSIST_WAIT_NS) remaining = PERSIST_WAIT_NS;
        struct timespec wait = { .tv_nsec = (long)remaining };
        pthread_mutex_unlock(&queue->mutex);
        (void)syscall(SYS_futex, &queue->generation, FUTEX_WAIT, generation, &wait, NULL, 0);
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
    uint32_t offset = queue->arena_used;
    packet->offset = offset;
    packet->length = (uint32_t)len;
    queue->arena_used += (uint32_t)len;
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
                queue->nodes[consumer].pending--;
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
#endif
