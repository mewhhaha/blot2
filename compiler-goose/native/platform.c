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
    static _Thread_local uint64_t identity;
    if (!identity) identity = blot_owner_id();
    return identity;
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
