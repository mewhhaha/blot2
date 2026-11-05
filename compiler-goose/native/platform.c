#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdatomic.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <math.h>
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/file.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif

_Static_assert(sizeof(void *) == 8, "the native port uses the Goose C.2 64-bit host layout");
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24,
               "the compiler requires IEEE binary32");
_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53,
               "the compiler requires IEEE binary64");

static _Atomic uint64_t next_owner = 1;
uint64_t blot_owner_id(void) {
    uint64_t current = atomic_load_explicit(&next_owner, memory_order_relaxed);
    for (;;) {
        if (current == UINT64_MAX) return 0;
        if (atomic_compare_exchange_weak_explicit(&next_owner, &current, current + 1,
                memory_order_relaxed, memory_order_relaxed)) return current;
    }
}
uint32_t blot_f32_bits(float value) { uint32_t bits; memcpy(&bits, &value, 4); return bits; }
float blot_f32_from_bits(uint32_t bits) { float value; memcpy(&value, &bits, 4); return value; }
uint64_t blot_f64_bits(double value) { uint64_t bits; memcpy(&bits, &value, 8); return bits; }
double blot_f64_from_bits(uint64_t bits) { double value; memcpy(&value, &bits, 8); return value; }

int64_t blot_read(int32_t fd, uint8_t *out, uint64_t count) {
    if (count > SSIZE_MAX) return -EINVAL;
    ssize_t result;
    do { result = read(fd, out, (size_t)count); } while (result < 0 && errno == EINTR);
    if (result < 0) return -(int64_t)errno;
    return result;
}
int64_t blot_write(int32_t fd, const uint8_t *bytes, uint64_t count) {
    if (count > SSIZE_MAX) return -EINVAL;
    ssize_t result;
    do { result = write(fd, bytes, (size_t)count); } while (result < 0 && errno == EINTR);
    if (result < 0) return -(int64_t)errno;
    return result;
}
int32_t blot_open_read(const uint8_t *path) {
    int fd;
    do { fd = open((const char *)path, O_RDONLY | O_CLOEXEC); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
int32_t blot_open_write(const uint8_t *path, _Bool exclusive) {
    int flags = O_WRONLY | O_CREAT | O_CLOEXEC;
    if (exclusive) flags |= O_EXCL;
    else flags |= O_TRUNC;
    int fd;
    do { fd = open((const char *)path, flags, 0666); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
int32_t blot_close(int32_t fd) { if (close(fd) < 0) return -errno; return 0; }
int32_t blot_sync(int32_t fd) { if (fsync(fd) < 0) return -errno; return 0; }
int64_t blot_file_size(int32_t fd) {
    struct stat info;
    if (fstat(fd, &info) < 0) return -(int64_t)errno;
    if (info.st_size < 0) return -EOVERFLOW;
    return info.st_size;
}
int32_t blot_rename(const uint8_t *before, const uint8_t *after) {
    if (rename((const char *)before, (const char *)after) < 0) return -errno;
    return 0;
}
int32_t blot_remove(const uint8_t *path) { if (unlink((const char *)path) < 0) return -errno; return 0; }
int32_t blot_mkdir(const uint8_t *path) { if (mkdir((const char *)path, 0777) < 0) return -errno; return 0; }
static uint64_t read_clock(clockid_t clock) {
    struct timespec now;
    if (clock_gettime(clock, &now) < 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
uint64_t blot_clock_ns(void) { return read_clock(CLOCK_MONOTONIC); }
uint64_t blot_thread_cpu_ns(void) { return read_clock(CLOCK_THREAD_CPUTIME_ID); }
uint64_t blot_thread_id(void) {
    /* Goose workers are ordinary single-threaded process programs. Their
     * initial-thread Linux TID is their PID and stays unique across workers. */
    return (uint64_t)getpid();
}
uint64_t blot_peak_rss_kib(void) {
#ifdef __linux__
    FILE *file = fopen("/proc/self/status", "r");
    if (!file) return 0;
    char line[256];
    uint64_t value = 0;
    while (fgets(line, sizeof line, file)) {
        unsigned long long parsed;
        if (sscanf(line, "VmHWM: %llu kB", &parsed) == 1) { value = parsed; break; }
    }
    fclose(file);
    return value;
#else
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage)) return 0;
    return (uint64_t)usage.ru_maxrss;
#endif
}
uint64_t blot_random_u64(void) {
    uint64_t value = 0;
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        int64_t count = blot_read(fd, (uint8_t *)&value, sizeof value);
        blot_close(fd);
        if (count == sizeof value) return value;
    }
    return blot_clock_ns() ^ ((uint64_t)getpid() << 32) ^ blot_owner_id();
}
uint32_t blot_process_id(void) { return (uint32_t)getpid(); }
int64_t blot_real_path(const uint8_t *path, uint8_t *out, uint64_t capacity) {
    char *resolved = realpath((const char *)path, NULL);
    if (!resolved) return -(int64_t)errno;
    size_t length = strlen(resolved);
    if (length < capacity) memcpy(out, resolved, length + 1);
    free(resolved);
    if (length > INT64_MAX) return -EOVERFLOW;
    return (int64_t)length;
}
/* Goose C.2 packs scalar fields; callers may supply an unaligned u64.
 * memcpy under one mutex avoids both misaligned atomics and torn accesses. */
static pthread_mutex_t scalar_atomic_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t scalar_load(const uint64_t *value) {
    uint64_t result;
    memcpy(&result, value, sizeof(result));
    return result;
}
static void scalar_store(uint64_t *value, uint64_t next) {
    memcpy(value, &next, sizeof(next));
}
uint64_t blot_atomic_add(uint64_t *value, uint64_t amount) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before + amount);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t blot_atomic_sub(uint64_t *value, uint64_t amount) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before - amount);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t blot_atomic_max(uint64_t *value, uint64_t candidate) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    if (candidate > before) scalar_store(value, candidate);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t blot_atomic_load(const uint64_t *value) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t result = scalar_load(value);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return result;
}
void blot_atomic_store(uint64_t *value, uint64_t next) {
    pthread_mutex_lock(&scalar_atomic_lock);
    scalar_store(value, next);
    pthread_mutex_unlock(&scalar_atomic_lock);
}

uint32_t blot_platform_is_linux(void) {
#if defined(__linux__)
    return 1;
#else
    return 0;
#endif
}

uint32_t blot_i32_bits(int32_t value) {
    uint32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
int32_t blot_i32_from_bits(uint32_t value) {
    int32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
float blot_f32_mul_add(float left, float right, float addend) {
    return fmaf(left, right, addend);
}

static pthread_mutex_t debug_print_lock = PTHREAD_MUTEX_INITIALIZER;
void blot_debug_write(const unsigned char *bytes, uint64_t count) {
    pthread_mutex_lock(&debug_print_lock);
    while (count != 0) {
        size_t chunk = (size_t)count;
        if (chunk > (size_t)SSIZE_MAX) chunk = (size_t)SSIZE_MAX;
        ssize_t written = write(STDERR_FILENO, bytes, chunk);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) break;
        bytes += (size_t)written;
        count -= (uint64_t)written;
    }
    pthread_mutex_unlock(&debug_print_lock);
}

/* The C host retains only process arguments and operating-system handles. */
static int blot_argc;
static char **blot_argv;
void blot_platform_entry_init(int argc, char **argv) {
    blot_argc = argc;
    blot_argv = argv;
    signal(SIGPIPE, SIG_IGN);
#ifdef __linux__
    if (argc > 1 && strcmp(argv[1], "--worker") == 0) {
        prctl(PR_SET_PDEATHSIG, SIGKILL);
        if (getppid() == 1) _exit(1);
    }
#endif
}
int64_t blot_argument_count(void) { return blot_argc; }
int64_t blot_argument_size(int64_t index) {
    if (index < 0 || index >= blot_argc) return -EINVAL;
    return (int64_t)strlen(blot_argv[index]);
}
int64_t blot_argument_copy(int64_t index, uint8_t *out, uint64_t capacity) {
    int64_t size = blot_argument_size(index);
    if (size < 0) return size;
    if ((uint64_t)size > capacity) return -ENAMETOOLONG;
    memcpy(out, blot_argv[index], (size_t)size);
    return size;
}
int64_t blot_environment_size(const uint8_t *name) {
    const char *value = getenv((const char *)name);
    if (!value) return -ENOENT;
    return (int64_t)strlen(value);
}
int64_t blot_environment_copy(const uint8_t *name, uint8_t *out, uint64_t capacity) {
    const char *value = getenv((const char *)name);
    if (!value) return -ENOENT;
    size_t size = strlen(value);
    if (size > capacity) return -ENAMETOOLONG;
    memcpy(out, value, size);
    return (int64_t)size;
}
struct blot_worker_process { pid_t pid; int input; int output; };
static struct blot_worker_process blot_workers[16];
extern char **environ;
int64_t blot_worker_spawn(uint32_t slot) {
    if (slot >= 16 || blot_workers[slot].pid) return -EINVAL;
    char executable[PATH_MAX];
    ssize_t size = readlink("/proc/self/exe", executable, sizeof executable - 1);
    if (size < 0) return -errno;
    if ((size_t)size >= sizeof executable - 1) return -ENAMETOOLONG;
    executable[size] = 0;
    int request[2], response[2];
    if (pipe(request) < 0) return -errno;
    if (pipe(response) < 0) { int saved = errno; close(request[0]); close(request[1]); return -saved; }
    int all[4] = { request[0], request[1], response[0], response[1] };
    for (size_t i = 0; i < 4; ++i) {
        if (fcntl(all[i], F_SETFD, FD_CLOEXEC) < 0) {
            int saved = errno;
            for (size_t j = 0; j < 4; ++j) close(all[j]);
            return -saved;
        }
    }
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    if (!error) {
        error = posix_spawn_file_actions_adddup2(&actions, request[0], STDIN_FILENO);
        if (!error) error = posix_spawn_file_actions_adddup2(&actions, response[1], STDOUT_FILENO);
        for (size_t i = 0; !error && i < 4; ++i) {
            if (all[i] != STDIN_FILENO && all[i] != STDOUT_FILENO)
                error = posix_spawn_file_actions_addclose(&actions, all[i]);
        }
        char *arguments[] = { executable, "--worker", NULL };
        pid_t pid = 0;
        if (!error) error = posix_spawn(&pid, executable, &actions, NULL, arguments, environ);
        posix_spawn_file_actions_destroy(&actions);
        if (!error) {
            close(request[0]); close(response[1]);
            blot_workers[slot] = (struct blot_worker_process){ pid, request[1], response[0] };
            return pid;
        }
    }
    for (size_t i = 0; i < 4; ++i) close(all[i]);
    return -error;
}
int32_t blot_worker_descriptor(uint32_t slot, _Bool writing) {
    if (slot >= 16 || !blot_workers[slot].pid) return -EBADF;
    if (writing) return blot_workers[slot].input;
    return blot_workers[slot].output;
}
int32_t blot_worker_stop(uint32_t slot) {
    if (slot >= 16) return -EINVAL;
    struct blot_worker_process worker = blot_workers[slot];
    if (!worker.pid) return 0;
    blot_workers[slot] = (struct blot_worker_process){0};
    close(worker.input); close(worker.output);
    if (kill(worker.pid, SIGKILL) < 0 && errno != ESRCH) return -errno;
    int status;
    pid_t waited;
    do { waited = waitpid(worker.pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited < 0 && errno != ECHILD) return -errno;
    return 0;
}

int32_t blot_lock_open(const uint8_t *path) {
    int fd;
    do { fd = open((const char *)path, O_RDWR | O_CREAT | O_CLOEXEC, 0666); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
int32_t blot_try_lock(int32_t fd, _Bool exclusive) {
    int operation = LOCK_SH | LOCK_NB;
    if (exclusive) operation = LOCK_EX | LOCK_NB;
    if (flock(fd, operation) < 0) return -errno;
    return 0;
}
int32_t blot_unlock(int32_t fd) { if (flock(fd, LOCK_UN) < 0) return -errno; return 0; }
int32_t blot_truncate(int32_t fd, uint64_t length) {
    if (length > INT64_MAX) return -EOVERFLOW;
    if (ftruncate(fd, (off_t)length) < 0) return -errno;
    return 0;
}
int64_t blot_pwrite(int32_t fd, const uint8_t *data, uint64_t count, uint64_t offset) {
    if (count > SSIZE_MAX || offset > INT64_MAX) return -EOVERFLOW;
    ssize_t written;
    do { written = pwrite(fd, data, (size_t)count, (off_t)offset); } while (written < 0 && errno == EINTR);
    if (written < 0) return -(int64_t)errno;
    return written;
}
void blot_sleep_ms(uint64_t milliseconds) {
    struct timespec pause = { (time_t)(milliseconds / 1000), (long)((milliseconds % 1000) * 1000000) };
    while (nanosleep(&pause, &pause) < 0 && errno == EINTR) {}
}
int64_t blot_fork(void) { pid_t pid = fork(); if (pid < 0) return -(int64_t)errno; return pid; }
int32_t blot_detach_session(void) { if (setsid() < 0) return -errno; return 0; }
_Bool blot_wait_success(uint32_t pid) {
    int status;
    pid_t result;
    do { result = waitpid((pid_t)pid, &status, 0); } while (result < 0 && errno == EINTR);
    return result == (pid_t)pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
void blot_null_standard_io(void) {
    int sink = open("/dev/null", O_RDWR);
    if (sink < 0) return;
    for (int fd = 0; fd < 3; ++fd) dup2(sink, fd);
    if (sink > 2) close(sink);
}
