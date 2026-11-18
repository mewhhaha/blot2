#ifdef PERSIST_WHITEBOX
#include "../check_queue.c"
#endif

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

uint64_t blot_persist_open(uint32_t count);
bool blot_persist_node(uint64_t h, uint32_t id, uint32_t priority);
bool blot_persist_edge(uint64_t h, uint32_t consumer, uint32_t producer);
int64_t blot_persist_claim(uint64_t h);
bool blot_persist_publish(uint64_t h, uint32_t id, uint32_t kind,
                          const uint8_t *bytes, uint64_t len);
int64_t blot_persist_size(uint64_t h, uint32_t id, uint32_t kind);
bool blot_persist_read(uint64_t h, uint32_t id, uint32_t kind, uint8_t *bytes, uint64_t len);
void blot_persist_fail(uint64_t h);
void blot_persist_close(uint64_t h);

static void wait_exit(pid_t pid, int code) {
    int status;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == code);
}

static int64_t now_ms(void) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return now.tv_sec * INT64_C(1000) + now.tv_nsec / INT64_C(1000000);
}

static void priorities_and_early_release(void) {
    const uint8_t a[] = {1, 2, 3}, b[] = {4, 5, 6};
    uint8_t out[sizeof a];
    uint64_t h = blot_persist_open(4);
    assert(h);
    assert(blot_persist_node(h, 1, 41));
    assert(blot_persist_node(h, 2, 41));
    assert(blot_persist_node(h, 3, 100));
    assert(blot_persist_node(h, 4, 1));
    assert(!blot_persist_node(h, 0, 0) && !blot_persist_edge(h, 5, 1));
    assert(blot_persist_edge(h, 3, 1));
    assert(blot_persist_edge(h, 3, 1));
    assert(blot_persist_claim(h) == 1);
    assert(!blot_persist_node(h, 1, 0) && !blot_persist_edge(h, 2, 1));
    assert(blot_persist_size(h, 1, 1) == 0);
    assert(!blot_persist_publish(h, 1, 2, b, sizeof b));

    int ack[2], start[2];
    assert(pipe(ack) == 0 && pipe(start) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(ack[0]);
        close(start[1]);
        assert(read(start[0], out, 1) == 1);
        close(start[0]);
        assert(blot_persist_claim(h) == 3);
        assert(blot_persist_size(h, 1, 1) == sizeof a);
        assert(blot_persist_read(h, 1, 1, out, sizeof out));
        assert(memcmp(out, a, sizeof out) == 0);
        assert(blot_persist_size(h, 1, 2) == 0);
        assert(!blot_persist_publish(h, 1, 2, b, sizeof b));
        assert(blot_persist_publish(h, 3, 2, b, sizeof b));
        assert(write(ack[1], a, 1) == 1);
        _exit(0);
    }
    close(ack[1]);
    close(start[0]);
    assert(blot_persist_publish(h, 1, 1, a, sizeof a));
    assert(write(start[1], a, 1) == 1);
    close(start[1]);
    assert(read(ack[0], out, 1) == 1);
    close(ack[0]);
    assert(!blot_persist_publish(h, 1, 1, a, sizeof a));
    assert(blot_persist_publish(h, 1, 2, b, sizeof b));
    assert(blot_persist_claim(h) == 2);
    assert(blot_persist_publish(h, 2, 2, b, sizeof b));
    assert(blot_persist_claim(h) == 4);
    assert(blot_persist_publish(h, 4, 2, b, sizeof b));
    assert(blot_persist_claim(h) == 0);
    assert(blot_persist_read(h, 3, 2, out, sizeof out));
    assert(memcmp(out, b, sizeof b) == 0);
    assert(!blot_persist_read(h, 3, 2, out, sizeof out - 1));
    wait_exit(child, 0);
    blot_persist_close(h);
}

static void invalid_graphs(void) {
    uint64_t h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0));
    assert(blot_persist_claim(h) == -EINVAL);
    blot_persist_close(h);
    h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_node(h, 2, 0));
    assert(blot_persist_edge(h, 2, 1) && blot_persist_edge(h, 1, 2));
    assert(blot_persist_claim(h) == -EDEADLK);
    blot_persist_close(h);
    h = blot_persist_open(1);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_claim(h) == 1);
    const uint8_t byte = 0;
    assert(!blot_persist_publish(h, 1, 2, &byte, UINT64_MAX));
    assert(blot_persist_claim(h) == -ENOSPC && blot_persist_size(h, 1, 2) == -ENOSPC);
    blot_persist_close(h);
}

static void worker_dies(void) {
    uint64_t h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_node(h, 2, 0));
    assert(blot_persist_edge(h, 2, 1));
    int ack[2];
    assert(pipe(ack) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(ack[0]);
        assert(blot_persist_claim(h) == 1);
        assert(write(ack[1], "x", 1) == 1);
        _exit(37);
    }
    close(ack[1]);
    char byte;
    assert(read(ack[0], &byte, 1) == 1);
    close(ack[0]);
    int64_t start = now_ms();
    assert(blot_persist_claim(h) == -ECHILD);
    assert(now_ms() - start < 1000);
    wait_exit(child, 37);
    blot_persist_close(h);
}

#ifdef PERSIST_WHITEBOX
static void worker_dies_in_metadata(void) {
    uint64_t h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_node(h, 2, 0));
    assert(blot_persist_edge(h, 2, 1));
    int ack[2];
    assert(pipe(ack) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(ack[0]);
        assert(blot_persist_claim(h) == 1);
        assert(persist_lock(persist_queue(h)) == 0);
        assert(write(ack[1], "x", 1) == 1);
        _exit(43);
    }
    close(ack[1]);
    char byte;
    assert(read(ack[0], &byte, 1) == 1);
    close(ack[0]);
    assert(blot_persist_claim(h) == -EOWNERDEAD);
    assert(blot_persist_size(h, 1, 1) == -EOWNERDEAD);
    wait_exit(child, 43);
    blot_persist_close(h);
}
#endif

static void release_on_abort(void) {
    uint64_t h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_node(h, 2, 0));
    assert(blot_persist_edge(h, 2, 1) && blot_persist_claim(h) == 1);
    pid_t child = fork();
    assert(child >= 0);
    int64_t start = now_ms();
    if (child == 0) _exit(blot_persist_claim(h) == -ECANCELED ? 0 : 1);
    usleep(1000);
    blot_persist_fail(h);
    wait_exit(child, 0);
    assert(now_ms() - start < 1000);
    blot_persist_close(h);
}

enum { COUNT = 269, INTERFACE = 97126, CORE = 179058 };

static void bulk_worker(uint64_t h) {
    uint8_t data[CORE];
    int64_t item;
    while ((item = blot_persist_claim(h)) > 0) {
        uint32_t id = (uint32_t)item;
        if (id > 16) {
            for (uint32_t dep = id - 12; dep >= id - 13; --dep) {
                assert(blot_persist_size(h, dep, 1) == INTERFACE);
                assert(blot_persist_read(h, dep, 1, data, INTERFACE));
                for (uint32_t j = 0; j < INTERFACE; ++j)
                    assert(data[j] == (uint8_t)(dep ^ j));
            }
        }
        for (uint32_t j = 0; j < CORE; ++j) data[j] = (uint8_t)(id ^ j);
        assert(blot_persist_publish(h, id, 1, data, INTERFACE));
        assert(blot_persist_publish(h, id, 2, data, CORE));
    }
    assert(item == 0);
}

static void bulk_forks(unsigned width) {
    uint64_t h = blot_persist_open(COUNT);
    assert(h);
    for (uint32_t i = 1; i <= COUNT; ++i) assert(blot_persist_node(h, i, i));
    for (uint32_t i = 17; i <= COUNT; ++i) {
        assert(blot_persist_edge(h, i, i - 12));
        assert(blot_persist_edge(h, i, i - 13));
    }
    pid_t pids[8];
    for (unsigned n = 1; n < width; ++n) {
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            bulk_worker(h);
            _exit(0);
        }
        pids[n] = child;
    }
    bulk_worker(h);
    for (unsigned n = 1; n < width; ++n) wait_exit(pids[n], 0);
    uint8_t data[CORE];
    for (uint32_t i = 1; i <= COUNT; ++i) {
        assert(blot_persist_size(h, i, 2) == CORE);
        assert(blot_persist_read(h, i, 2, data, CORE));
        for (uint32_t j = 0; j < CORE; ++j)
            assert(data[j] == (uint8_t)(i ^ j));
    }
    blot_persist_close(h);
}

static void deadline(void) {
    uint64_t h = blot_persist_open(2);
    assert(h && blot_persist_node(h, 1, 0) && blot_persist_node(h, 2, 0));
    assert(blot_persist_edge(h, 2, 1));
    int ack[2];
    assert(pipe(ack) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(ack[0]);
        assert(blot_persist_claim(h) == 1);
        assert(write(ack[1], "x", 1) == 1);
        pause();
        _exit(17);
    }
    close(ack[1]);
    char byte;
    assert(read(ack[0], &byte, 1) == 1);
    close(ack[0]);
    int64_t start = now_ms();
    assert(blot_persist_claim(h) == -ETIMEDOUT);
    int64_t elapsed = now_ms() - start;
    assert(elapsed >= 14000 && elapsed < 16500);
    assert(kill(child, SIGTERM) == 0);
    int status;
    assert(waitpid(child, &status, 0) == child && WIFSIGNALED(status));
    blot_persist_close(h);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "deadline") == 0) {
        alarm(20);
        deadline();
        return 0;
    }
    alarm(8);
    for (unsigned attempt = 0; attempt < 4; ++attempt) {
        priorities_and_early_release();
        invalid_graphs();
        worker_dies();
#ifdef PERSIST_WHITEBOX
        worker_dies_in_metadata();
#endif
        release_on_abort();
        bulk_forks(1);
        bulk_forks(4);
        bulk_forks(8);
    }
}
