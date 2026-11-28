#if !defined(_WIN32)
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdint.h>
#include <stdatomic.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <direct.h>
#include <psapi.h>
#include <bcrypt.h>
#include <sys/stat.h>
#include <sys/types.h>
#else
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <pthread.h>
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <dirent.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

_Static_assert(sizeof(void *) == 8, "the native port uses the Goose C.2 64-bit host layout");
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24,
               "the compiler requires IEEE binary32");
_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53,
               "the compiler requires IEEE binary64");

static _Atomic uint64_t next_owner = 1;
uint64_t squid_owner_id(void) {
    uint64_t current = atomic_load_explicit(&next_owner, memory_order_relaxed);
    for (;;) {
        if (current == UINT64_MAX) return 0;
        if (atomic_compare_exchange_weak_explicit(&next_owner, &current, current + 1,
                memory_order_relaxed, memory_order_relaxed)) return current;
    }
}
uint32_t squid_f32_bits(float value) { uint32_t bits; memcpy(&bits, &value, 4); return bits; }
float squid_f32_from_bits(uint32_t bits) { float value; memcpy(&value, &bits, 4); return value; }
uint64_t squid_f64_bits(double value) { uint64_t bits; memcpy(&bits, &value, 8); return bits; }
double squid_f64_from_bits(uint64_t bits) { double value; memcpy(&value, &bits, 8); return value; }
void squid_copy_u32(uint32_t *dst, const uint8_t *src, uint64_t count) {
    if (count) memcpy(dst, src, (size_t)(count * 4));
}
void squid_copy_u8(uint8_t *dst, const uint8_t *src, uint64_t count) {
    if (count) memcpy(dst, src, (size_t)count);
}
void squid_copy_flat(const uint8_t *dst, const uint8_t *src, uint64_t count) {
    if (count) memcpy((void *)dst, src, (size_t)count);
}
uint32_t squid_platform_is_linux(void) {
#if defined(__linux__)
    return 1;
#else
    return 0;
#endif
}
uint32_t squid_i32_bits(int32_t value) {
    uint32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
int32_t squid_i32_from_bits(uint32_t value) {
    int32_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}
float squid_f32_mul_add(float left, float right, float addend) {
    return fmaf(left, right, addend);
}
static int squid_argc;
static char **squid_argv;
int64_t squid_argument_count(void) { return squid_argc; }
int64_t squid_argument_size(int64_t index) {
    if (index < 0 || index >= squid_argc) return -EINVAL;
    return (int64_t)strlen(squid_argv[index]);
}
int64_t squid_argument_copy(int64_t index, uint8_t *out, uint64_t capacity) {
    int64_t size = squid_argument_size(index);
    if (size < 0) return size;
    if ((uint64_t)size > capacity) return -ENAMETOOLONG;
    memcpy(out, squid_argv[index], (size_t)size);
    return size;
}
int64_t squid_environment_size(const uint8_t *name) {
    const char *value = getenv((const char *)name);
    if (!value) return -ENOENT;
    return (int64_t)strlen(value);
}
int64_t squid_environment_copy(const uint8_t *name, uint8_t *out, uint64_t capacity) {
    const char *value = getenv((const char *)name);
    if (!value) return -ENOENT;
    size_t size = strlen(value);
    if (size > capacity) return -ENAMETOOLONG;
    memcpy(out, value, size);
    return (int64_t)size;
}

#if defined(_WIN32)
int64_t squid_read(int32_t fd, uint8_t *out, uint64_t count) {
    if (count > (uint64_t)INT_MAX) count = (uint64_t)INT_MAX;
    int result = _read(fd, out, (unsigned int)count);
    if (result < 0) return -(int64_t)errno;
    return (int64_t)result;
}
int64_t squid_write(int32_t fd, const uint8_t *bytes, uint64_t count) {
    if (count > (uint64_t)INT_MAX) count = (uint64_t)INT_MAX;
    int result = _write(fd, bytes, (unsigned int)count);
    if (result < 0) return -(int64_t)errno;
    return (int64_t)result;
}
int32_t squid_open_read(const uint8_t *path) {
    int fd = _open((const char *)path, _O_RDONLY | _O_BINARY | _O_NOINHERIT);
    if (fd < 0) return -errno;
    return fd;
}
int32_t squid_open_regular_sized(const uint8_t *path, uint64_t maximum, int64_t *size_out) {
    int fd = _open((const char *)path, _O_RDONLY | _O_BINARY | _O_NOINHERIT);
    if (fd < 0) return -errno;
    struct __stat64 st;
    if (_fstat64(fd, &st) != 0 || !(st.st_mode & _S_IFREG) || st.st_size < 0 || (uint64_t)st.st_size > maximum) {
        _close(fd);
        return -EINVAL;
    }
    int64_t sz = (int64_t)st.st_size;
    if (size_out) memcpy(size_out, &sz, sizeof(sz));
    return fd;
}
int32_t squid_open_regular(const uint8_t *path, uint64_t maximum) {
    return squid_open_regular_sized(path, maximum, NULL);
}
int32_t squid_open_regular_nofollow_sized(const uint8_t *path, uint64_t maximum, int64_t *size_out) {
    return squid_open_regular_sized(path, maximum, size_out);
}
int32_t squid_open_write(const uint8_t *path, _Bool exclusive) {
    int flags = _O_WRONLY | _O_CREAT | _O_BINARY | _O_NOINHERIT;
    if (exclusive) flags |= _O_EXCL;
    else flags |= _O_TRUNC;
    int fd = _open((const char *)path, flags, _S_IREAD | _S_IWRITE);
    if (fd < 0) return -errno;
    return fd;
}
int32_t squid_close(int32_t fd) { if (_close(fd) < 0) return -errno; return 0; }
int32_t squid_sync(int32_t fd) { if (_commit(fd) < 0) return -errno; return 0; }
int64_t squid_file_size(int32_t fd) {
    struct __stat64 st;
    if (_fstat64(fd, &st) < 0) return -(int64_t)errno;
    if (st.st_size < 0) return -EOVERFLOW;
    return (int64_t)st.st_size;
}
int32_t squid_rename(const uint8_t *before, const uint8_t *after) {
    if (!MoveFileExA((const char *)before, (const char *)after, MOVEFILE_REPLACE_EXISTING)) return -EIO;
    return 0;
}
int32_t squid_remove(const uint8_t *path) { if (_unlink((const char *)path) < 0) return -errno; return 0; }
int32_t squid_mkdir(const uint8_t *path) { if (_mkdir((const char *)path) < 0) return -errno; return 0; }
uint64_t squid_clock_ns(void) {
    static LARGE_INTEGER freq;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    uint64_t q = (uint64_t)now.QuadPart;
    uint64_t f = (uint64_t)freq.QuadPart;
    return (q / f) * UINT64_C(1000000000) + ((q % f) * UINT64_C(1000000000)) / f;
}
uint64_t squid_thread_cpu_ns(void) {
    FILETIME ct, et, kt, ut;
    if (!GetThreadTimes(GetCurrentThread(), &ct, &et, &kt, &ut)) return 0;
    uint64_t k = ((uint64_t)kt.dwHighDateTime << 32) | kt.dwLowDateTime;
    uint64_t u = ((uint64_t)ut.dwHighDateTime << 32) | ut.dwLowDateTime;
    return (k + u) * UINT64_C(100);
}
uint64_t squid_thread_id(void) { return (uint64_t)GetCurrentThreadId(); }
uint64_t squid_peak_rss_kib(void) {
    PROCESS_MEMORY_COUNTERS pmc;
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof pmc)) return 0;
    return (uint64_t)(pmc.PeakWorkingSetSize / 1024);
}
uint64_t squid_random_u64(void) {
    uint64_t value = 0;
    if (BCryptGenRandom(NULL, (PUCHAR)&value, (ULONG)sizeof value, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0)
        return value;
    return squid_clock_ns() ^ ((uint64_t)GetCurrentProcessId() << 32) ^ squid_owner_id();
}
uint32_t squid_process_id(void) { return (uint32_t)GetCurrentProcessId(); }
int64_t squid_real_path(const uint8_t *path, uint8_t *out, uint64_t capacity) {
    char *resolved = _fullpath(NULL, (const char *)path, 0);
    if (!resolved) return -(int64_t)errno;
    DWORD attr = GetFileAttributesA(resolved);
    if (attr == INVALID_FILE_ATTRIBUTES) { free(resolved); return -ENOENT; }
    for (char *p = resolved; *p; ++p) { if (*p == '\\') *p = '/'; }
    size_t length = strlen(resolved);
    if (length < capacity) memcpy(out, resolved, length + 1);
    free(resolved);
    if (length > (size_t)INT64_MAX) return -EOVERFLOW;
    return (int64_t)length;
}
static SRWLOCK scalar_atomic_lock = SRWLOCK_INIT;
static uint64_t scalar_load(const uint64_t *value) { uint64_t r; memcpy(&r, value, sizeof r); return r; }
static void scalar_store(uint64_t *value, uint64_t next) { memcpy(value, &next, sizeof next); }
uint64_t squid_atomic_add(uint64_t *value, uint64_t amount) {
    AcquireSRWLockExclusive(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before + amount);
    ReleaseSRWLockExclusive(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_sub(uint64_t *value, uint64_t amount) {
    AcquireSRWLockExclusive(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before - amount);
    ReleaseSRWLockExclusive(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_max(uint64_t *value, uint64_t candidate) {
    AcquireSRWLockExclusive(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    if (candidate > before) scalar_store(value, candidate);
    ReleaseSRWLockExclusive(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_load(const uint64_t *value) {
    AcquireSRWLockShared(&scalar_atomic_lock);
    uint64_t r = scalar_load(value);
    ReleaseSRWLockShared(&scalar_atomic_lock);
    return r;
}
void squid_atomic_store(uint64_t *value, uint64_t next) {
    AcquireSRWLockExclusive(&scalar_atomic_lock);
    scalar_store(value, next);
    ReleaseSRWLockExclusive(&scalar_atomic_lock);
}
static SRWLOCK debug_print_lock = SRWLOCK_INIT;
void squid_debug_write(const unsigned char *bytes, uint64_t count) {
    AcquireSRWLockExclusive(&debug_print_lock);
    while (count != 0) {
        unsigned int chunk = count > (uint64_t)INT_MAX ? (unsigned int)INT_MAX : (unsigned int)count;
        int written = _write(2, bytes, chunk);
        if (written <= 0) break;
        bytes += (size_t)written;
        count -= (uint64_t)written;
    }
    ReleaseSRWLockExclusive(&debug_print_lock);
}
void squid_platform_entry_init(int argc, char **argv) {
    squid_argc = argc;
    squid_argv = argv;
    (void)_setmode(0, _O_BINARY);
    (void)_setmode(1, _O_BINARY);
    (void)_setmode(2, _O_BINARY);
}
int64_t squid_worker_spawn(uint32_t slot) { (void)slot; return -ENOSYS; }
int32_t squid_worker_descriptor(uint32_t slot, _Bool writing) { (void)slot; (void)writing; return -EBADF; }
void squid_worker_detach(void) {}
int32_t squid_worker_stop(uint32_t slot) { (void)slot; return 0; }
int32_t squid_worker_quiesce(void) { return 0; }
int32_t squid_lock_open(const uint8_t *path) {
    int fd = _open((const char *)path, _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE);
    if (fd < 0) return -errno;
    return fd;
}
int32_t squid_try_lock(int32_t fd, _Bool exclusive) { (void)fd; (void)exclusive; return 0; }
int32_t squid_unlock(int32_t fd) { (void)fd; return 0; }
int32_t squid_truncate(int32_t fd, uint64_t length) {
    if (length > (uint64_t)INT64_MAX) return -EOVERFLOW;
    if (_chsize_s(fd, (__int64)length) != 0) return -errno;
    return 0;
}
int64_t squid_pwrite(int32_t fd, const uint8_t *data, uint64_t count, uint64_t offset) {
    if (count > (uint64_t)INT_MAX || offset > (uint64_t)INT64_MAX) return -EOVERFLOW;
    __int64 saved = _lseeki64(fd, 0, SEEK_CUR);
    if (_lseeki64(fd, (__int64)offset, SEEK_SET) < 0) return -(int64_t)errno;
    int written = _write(fd, data, (unsigned int)count);
    int err = errno;
    if (saved >= 0) (void)_lseeki64(fd, saved, SEEK_SET);
    if (written < 0) return -(int64_t)err;
    return (int64_t)written;
}
void squid_sleep_ms(uint64_t milliseconds) {
    if (milliseconds > (uint64_t)INFINITE - 1) milliseconds = (uint64_t)INFINITE - 1;
    Sleep((DWORD)milliseconds);
}
int64_t squid_fork(void) { return -ENOSYS; }
uint64_t squid_check_reply_open(void) { return 0; }
void squid_check_reply_close(uint64_t handle) { (void)handle; }
_Bool squid_check_reply_append(uint64_t handle, const uint8_t *bytes, uint64_t length) { (void)handle; (void)bytes; (void)length; return 0; }
int64_t squid_check_reply_size(uint64_t handle, uint64_t offset) { (void)handle; (void)offset; return -1; }
int64_t squid_check_reply_copy(uint64_t handle, uint64_t offset, uint8_t *bytes, uint64_t length) { (void)handle; (void)offset; (void)bytes; (void)length; return -1; }
_Noreturn void squid_job_exit(int32_t status) { _Exit(status); }
int32_t squid_detach_session(void) { return -ENOSYS; }
_Bool squid_wait_success(uint32_t pid) { (void)pid; return 0; }
void squid_null_standard_io(void) {}
int32_t squid_path_kind(const uint8_t *path) {
    DWORD attr = GetFileAttributesA((const char *)path);
    if (attr == INVALID_FILE_ATTRIBUTES) {
        DWORD err = GetLastError();
        if (err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND) return 0;
        return -1;
    }
    if (attr & FILE_ATTRIBUTE_DIRECTORY) return 2;
    return 1;
}
struct squid_win_dir { HANDLE handle; WIN32_FIND_DATAA data; int have_data; int done; };
int64_t squid_directory_open(const uint8_t *path) {
    size_t len = strlen((const char *)path);
    char *pat = (char *)malloc(len + 3);
    if (!pat) return -1;
    memcpy(pat, path, len);
    if (len > 0 && pat[len - 1] != '/' && pat[len - 1] != '\\') pat[len++] = '\\';
    pat[len++] = '*'; pat[len] = 0;
    struct squid_win_dir *cursor = (struct squid_win_dir *)calloc(1, sizeof *cursor);
    if (!cursor) { free(pat); return -1; }
    cursor->handle = FindFirstFileA(pat, &cursor->data);
    free(pat);
    if (cursor->handle == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        free(cursor);
        if (err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND) return 0;
        return -1;
    }
    cursor->have_data = 1;
    return (int64_t)(uintptr_t)cursor;
}
int64_t squid_directory_next(int64_t handle, uint8_t *out, uint64_t capacity) {
    if (handle <= 0) return -1;
    struct squid_win_dir *cursor = (struct squid_win_dir *)(uintptr_t)handle;
    for (;;) {
        if (!cursor->have_data) {
            if (cursor->done) return 0;
            if (!FindNextFileA(cursor->handle, &cursor->data)) {
                cursor->done = 1;
                if (GetLastError() == ERROR_NO_MORE_FILES) return 0;
                return -1;
            }
            cursor->have_data = 1;
        }
        DWORD attr = cursor->data.dwFileAttributes;
        if ((attr & FILE_ATTRIBUTE_DIRECTORY) || (attr & FILE_ATTRIBUTE_REPARSE_POINT)) {
            cursor->have_data = 0;
            continue;
        }
        size_t length = strlen(cursor->data.cFileName);
        if (length > capacity) return (int64_t)length;
        if (length) memcpy(out, cursor->data.cFileName, length);
        cursor->have_data = 0;
        return (int64_t)length;
    }
}
int32_t squid_directory_close(int64_t handle) {
    if (handle <= 0) return -1;
    struct squid_win_dir *cursor = (struct squid_win_dir *)(uintptr_t)handle;
    int ok = FindClose(cursor->handle) != 0;
    free(cursor);
    return ok ? 0 : -1;
}
int32_t squid_last_errno(void) { return errno; }
void squid_runtime_memory_mark(void) {}
uint64_t squid_runtime_observation(uint32_t field) { (void)field; return 0; }
#else

int64_t squid_read(int32_t fd, uint8_t *out, uint64_t count) {
    if (count > SSIZE_MAX) return -EINVAL;
    ssize_t result;
    do { result = read(fd, out, (size_t)count); } while (result < 0 && errno == EINTR);
    if (result < 0) return -(int64_t)errno;
    return result;
}
int64_t squid_write(int32_t fd, const uint8_t *bytes, uint64_t count) {
    if (count > SSIZE_MAX) return -EINVAL;
    ssize_t result;
    do { result = write(fd, bytes, (size_t)count); } while (result < 0 && errno == EINTR);
    if (result < 0) return -(int64_t)errno;
    return result;
}
int32_t squid_open_read(const uint8_t *path) {
    int fd;
    do { fd = open((const char *)path, O_RDONLY | O_CLOEXEC); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
/* Import discovery may look ahead of the parser. Only sample bounded regular
   files, and never wait for a pipe that the real project might not import. */
int32_t squid_open_regular(const uint8_t *path, uint64_t maximum) {
    int fd;
    do { fd = open((const char *)path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOCTTY); }
    while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    struct stat status;
    if (fstat(fd, &status) || !S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_size > maximum) {
        close(fd);
        return -EINVAL;
    }
    return fd;
}
int32_t squid_open_regular_sized(const uint8_t *path, uint64_t maximum, int64_t *size_out) {
    int fd;
    do { fd = open((const char *)path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOCTTY); }
    while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    struct stat status;
    if (fstat(fd, &status) || !S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_size > maximum) {
        close(fd);
        return -EINVAL;
    }
    int64_t sz = (int64_t)status.st_size;
    memcpy(size_out, &sz, sizeof(sz));
    return fd;
}
int32_t squid_open_regular_nofollow_sized(const uint8_t *path, uint64_t maximum, int64_t *size_out) {
    int fd;
    do { fd = open((const char *)path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY); }
    while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    struct stat status;
    if (fstat(fd, &status) || !S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_size > maximum) {
        close(fd);
        return -EINVAL;
    }
    int64_t sz = (int64_t)status.st_size;
    memcpy(size_out, &sz, sizeof(sz));
    return fd;
}
int32_t squid_open_write(const uint8_t *path, _Bool exclusive) {
    int flags = O_WRONLY | O_CREAT | O_CLOEXEC;
    if (exclusive) flags |= O_EXCL;
    else flags |= O_TRUNC;
    int fd;
    do { fd = open((const char *)path, flags, 0666); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
int32_t squid_close(int32_t fd) { if (close(fd) < 0) return -errno; return 0; }
int32_t squid_sync(int32_t fd) { if (fsync(fd) < 0) return -errno; return 0; }
int64_t squid_file_size(int32_t fd) {
    struct stat info;
    if (fstat(fd, &info) < 0) return -(int64_t)errno;
    if (info.st_size < 0) return -EOVERFLOW;
    return info.st_size;
}
int32_t squid_rename(const uint8_t *before, const uint8_t *after) {
    if (rename((const char *)before, (const char *)after) < 0) return -errno;
    return 0;
}
int32_t squid_remove(const uint8_t *path) { if (unlink((const char *)path) < 0) return -errno; return 0; }
int32_t squid_mkdir(const uint8_t *path) { if (mkdir((const char *)path, 0777) < 0) return -errno; return 0; }
static uint64_t read_clock(clockid_t clock) {
    struct timespec now;
    if (clock_gettime(clock, &now) < 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
uint64_t squid_clock_ns(void) { return read_clock(CLOCK_MONOTONIC); }
uint64_t squid_thread_cpu_ns(void) { return read_clock(CLOCK_THREAD_CPUTIME_ID); }
uint64_t squid_thread_id(void) {
    /* Goose workers are ordinary single-threaded process programs. Their
     * initial-thread Linux TID is their PID and stays unique across workers. */
    return (uint64_t)getpid();
}
uint64_t squid_peak_rss_kib(void) {
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
#elif defined(__APPLE__)
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage)) return 0;
    return (uint64_t)usage.ru_maxrss / 1024;
#else
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage)) return 0;
    return (uint64_t)usage.ru_maxrss;
#endif
}
uint64_t squid_random_u64(void) {
    uint64_t value = 0;
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        int64_t count = squid_read(fd, (uint8_t *)&value, sizeof value);
        squid_close(fd);
        if (count == sizeof value) return value;
    }
    return squid_clock_ns() ^ ((uint64_t)getpid() << 32) ^ squid_owner_id();
}
uint32_t squid_process_id(void) { return (uint32_t)getpid(); }
int64_t squid_real_path(const uint8_t *path, uint8_t *out, uint64_t capacity) {
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
uint64_t squid_atomic_add(uint64_t *value, uint64_t amount) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before + amount);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_sub(uint64_t *value, uint64_t amount) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    scalar_store(value, before - amount);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_max(uint64_t *value, uint64_t candidate) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t before = scalar_load(value);
    if (candidate > before) scalar_store(value, candidate);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return before;
}
uint64_t squid_atomic_load(const uint64_t *value) {
    pthread_mutex_lock(&scalar_atomic_lock);
    uint64_t result = scalar_load(value);
    pthread_mutex_unlock(&scalar_atomic_lock);
    return result;
}
void squid_atomic_store(uint64_t *value, uint64_t next) {
    pthread_mutex_lock(&scalar_atomic_lock);
    scalar_store(value, next);
    pthread_mutex_unlock(&scalar_atomic_lock);
}

static pthread_mutex_t debug_print_lock = PTHREAD_MUTEX_INITIALIZER;
void squid_debug_write(const unsigned char *bytes, uint64_t count) {
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

void squid_platform_entry_init(int argc, char **argv) {
    squid_argc = argc;
    squid_argv = argv;
    signal(SIGPIPE, SIG_IGN);
#ifdef __linux__
    if (argc > 1 && strcmp(argv[1], "--worker") == 0) {
        prctl(PR_SET_PDEATHSIG, SIGKILL);
        if (getppid() == 1) _exit(1);
    }
#endif
}
struct squid_worker_process { pid_t pid; int input; int output; };
static struct squid_worker_process squid_workers[16];
extern char **environ;
extern int32_t squid_request_stage_capability(void) __attribute__((weak));
extern uint64_t squid_request_token(void) __attribute__((weak));
int64_t squid_worker_spawn(uint32_t slot) {
    if (slot >= 16 || squid_workers[slot].pid) return -EINVAL;
    char executable[PATH_MAX];
#if defined(__APPLE__)
    uint32_t exe_size = (uint32_t)sizeof executable;
    if (_NSGetExecutablePath(executable, &exe_size) != 0) return -ENAMETOOLONG;
#else
    ssize_t size = readlink("/proc/self/exe", executable, sizeof executable - 1);
    if (size < 0) return -errno;
    if ((size_t)size >= sizeof executable - 1) return -ENAMETOOLONG;
    executable[size] = 0;
#endif
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
    int capability = -1;
    uint64_t token = 0;
    if (squid_request_stage_capability && squid_request_token) {
        int source = squid_request_stage_capability();
        if (source >= 0) {
            capability = fcntl(source, F_DUPFD_CLOEXEC, 3);
            if (capability < 0) {
                int saved = errno;
                for (size_t i = 0; i < 4; ++i) close(all[i]);
                return -saved;
            }
            token = squid_request_token();
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
        /* POSIX dup2 file actions clear CLOEXEC, including source == target.
         * Child bootstrap immediately restores it before runtime initialization. */
        if (!error && capability >= 0)
            error = posix_spawn_file_actions_adddup2(&actions, capability, capability);
        char fd_text[32], token_text[32];
        snprintf(fd_text, sizeof fd_text, "%d", capability);
        snprintf(token_text, sizeof token_text, "%llu", (unsigned long long)token);
        char *arguments[] = { executable, "--worker", NULL, NULL, NULL, NULL };
        if (capability >= 0) {
            arguments[2] = "--squid-request-oom";
            arguments[3] = fd_text;
            arguments[4] = token_text;
        }
        pid_t pid = 0;
        if (!error) error = posix_spawn(&pid, executable, &actions, NULL, arguments, environ);
        posix_spawn_file_actions_destroy(&actions);
        if (capability >= 0) close(capability);
        capability = -1;
        if (!error) {
            close(request[0]); close(response[1]);
            squid_workers[slot] = (struct squid_worker_process){ pid, request[1], response[0] };
            return pid;
        }
    }
    if (capability >= 0) close(capability);
    for (size_t i = 0; i < 4; ++i) close(all[i]);
    return -error;
}
int32_t squid_worker_descriptor(uint32_t slot, _Bool writing) {
    if (slot >= 16 || !squid_workers[slot].pid) return -EBADF;
    if (writing) return squid_workers[slot].input;
    return squid_workers[slot].output;
}
/* A forked request candidate owns copied descriptors, never the baseline's
 * worker processes. Detach without signalling or waiting for those workers. */
void squid_worker_detach(void) {
    for (size_t slot = 0; slot < 16; ++slot) {
        struct squid_worker_process worker = squid_workers[slot];
        squid_workers[slot] = (struct squid_worker_process){0};
        if (worker.pid) { close(worker.input); close(worker.output); }
    }
}
int32_t squid_worker_stop(uint32_t slot) {
    if (slot >= 16) return -EINVAL;
    struct squid_worker_process worker = squid_workers[slot];
    if (!worker.pid) return 0;
    squid_workers[slot] = (struct squid_worker_process){0};
    close(worker.input); close(worker.output);
    if (kill(worker.pid, SIGKILL) < 0 && errno != ESRCH) return -errno;
    int status;
    pid_t waited;
    do { waited = waitpid(worker.pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited < 0 && errno != ECHILD) return -errno;
    return 0;
}
/* Finish only candidate-owned jobs through EOF and runtime cleanup, so a
 * response cannot race adoption with a subsequent allocation refusal. All
 * inputs close before any join; the outer supervisor bounds a stuck child. */
int32_t squid_worker_quiesce(void) {
    for (size_t slot = 0; slot < 16; ++slot) {
        if (squid_workers[slot].pid) {
            close(squid_workers[slot].input);
            squid_workers[slot].input = -1;
        }
    }
    int error = 0;
    for (size_t slot = 0; slot < 16; ++slot) {
        struct squid_worker_process worker = squid_workers[slot];
        if (!worker.pid) continue;
        squid_workers[slot] = (struct squid_worker_process){0};
        int status = 0;
        pid_t waited;
        do { waited = waitpid(worker.pid, &status, 0); } while (waited < 0 && errno == EINTR);
        if (waited < 0 || !WIFEXITED(status) || WEXITSTATUS(status)) error = -EPIPE;
        close(worker.output);
    }
    return error;
}

int32_t squid_lock_open(const uint8_t *path) {
    int fd;
    do { fd = open((const char *)path, O_RDWR | O_CREAT | O_CLOEXEC, 0666); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return -errno;
    return fd;
}
int32_t squid_try_lock(int32_t fd, _Bool exclusive) {
    int operation = LOCK_SH | LOCK_NB;
    if (exclusive) operation = LOCK_EX | LOCK_NB;
    if (flock(fd, operation) < 0) return -errno;
    return 0;
}
int32_t squid_unlock(int32_t fd) { if (flock(fd, LOCK_UN) < 0) return -errno; return 0; }
int32_t squid_truncate(int32_t fd, uint64_t length) {
    if (length > INT64_MAX) return -EOVERFLOW;
    if (ftruncate(fd, (off_t)length) < 0) return -errno;
    return 0;
}
int64_t squid_pwrite(int32_t fd, const uint8_t *data, uint64_t count, uint64_t offset) {
    if (count > SSIZE_MAX || offset > INT64_MAX) return -EOVERFLOW;
    ssize_t written;
    do { written = pwrite(fd, data, (size_t)count, (off_t)offset); } while (written < 0 && errno == EINTR);
    if (written < 0) return -(int64_t)errno;
    return written;
}
void squid_sleep_ms(uint64_t milliseconds) {
    struct timespec pause = { (time_t)(milliseconds / 1000), (long)((milliseconds % 1000) * 1000000) };
    while (nanosleep(&pause, &pause) < 0 && errno == EINTR) {}
}
int64_t squid_fork(void) { pid_t pid = fork(); if (pid < 0) return -(int64_t)errno; return pid; }

/* Each checker process gets one bounded, demand-paged reply area. It writes
 * frames in order. The parent reads them only after joining that process. */
#define CHECK_REPLY_CAPACITY (512u * 1024u * 1024u)
struct check_reply {
    uint64_t used;
    uint8_t bytes[];
};
uint64_t squid_check_reply_open(void) {
    void *mapping = mmap(NULL, sizeof(struct check_reply) + CHECK_REPLY_CAPACITY,
                         PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 0;
    return (uint64_t)(uintptr_t)mapping;
}
void squid_check_reply_close(uint64_t handle) {
    munmap((void *)(uintptr_t)handle, sizeof(struct check_reply) + CHECK_REPLY_CAPACITY);
}
_Bool squid_check_reply_append(uint64_t handle, const uint8_t *bytes, uint64_t length) {
    struct check_reply *reply = (void *)(uintptr_t)handle;
    const uint64_t offset = reply->used;
    if (length == 0 || offset > CHECK_REPLY_CAPACITY ||
        CHECK_REPLY_CAPACITY - offset < sizeof(length) ||
        length > CHECK_REPLY_CAPACITY - offset - sizeof(length)) return 0;
    memcpy(reply->bytes + offset, &length, sizeof(length));
    memcpy(reply->bytes + offset + sizeof(length), bytes, length);
    reply->used = offset + sizeof(length) + length;
    return 1;
}
int64_t squid_check_reply_size(uint64_t handle, uint64_t offset) {
    const struct check_reply *reply = (const void *)(uintptr_t)handle;
    if (reply->used > CHECK_REPLY_CAPACITY || offset > reply->used) return -1;
    if (offset == reply->used) return 0;
    if (reply->used - offset < sizeof(uint64_t)) return -1;
    uint64_t length;
    memcpy(&length, reply->bytes + offset, sizeof(length));
    if (length == 0 || length > reply->used - offset - sizeof(length)) return -1;
    return (int64_t)length;
}
int64_t squid_check_reply_copy(uint64_t handle, uint64_t offset, uint8_t *bytes, uint64_t length) {
    if (length == 0 || squid_check_reply_size(handle, offset) != (int64_t)length) return -1;
    const struct check_reply *reply = (const void *)(uintptr_t)handle;
    memcpy(bytes, reply->bytes + offset + sizeof(length), length);
    return (int64_t)(offset + sizeof(length) + length);
}
/* A checker copy releases nothing and flushes nothing at exit. */
_Noreturn void squid_job_exit(int32_t status) { _exit(status); }
int32_t squid_detach_session(void) { if (setsid() < 0) return -errno; return 0; }
_Bool squid_wait_success(uint32_t pid) {
    int status;
    pid_t result;
    do { result = waitpid((pid_t)pid, &status, 0); } while (result < 0 && errno == EINTR);
    return result == (pid_t)pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
void squid_null_standard_io(void) {
    int sink = open("/dev/null", O_RDWR);
    if (sink < 0) return;
    for (int fd = 0; fd < 3; ++fd) dup2(sink, fd);
    if (sink > 2) close(sink);
}

/* Opaque OS directory cursors. Selection and source generation stay in Goose. */
struct squid_directory { DIR *stream; struct dirent *pending; };
int32_t squid_path_kind(const uint8_t *path) {
    struct stat info;
    int result;
    do { result = stat((const char *)path, &info); } while (result < 0 && errno == EINTR);
    if (result < 0) { if (errno == ENOENT) return 0; return -1; }
    if (S_ISREG(info.st_mode)) return 1;
    if (S_ISDIR(info.st_mode)) return 2;
    return -1;
}
int64_t squid_directory_open(const uint8_t *path) {
    DIR *stream = opendir((const char *)path);
    if (!stream) { if (errno == ENOENT) return 0; return -1; }
    int descriptor = dirfd(stream);
    if (descriptor < 0 || fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) { closedir(stream); return -1; }
    struct squid_directory *cursor = malloc(sizeof *cursor);
    if (!cursor) { closedir(stream); return -1; }
    *cursor = (struct squid_directory){stream, NULL};
    return (int64_t)(uintptr_t)cursor;
}
int64_t squid_directory_next(int64_t handle, uint8_t *out, uint64_t capacity) {
    if (handle <= 0) return -1;
    struct squid_directory *cursor = (struct squid_directory *)(uintptr_t)handle;
    for (;;) {
        struct dirent *entry = cursor->pending;
        if (!entry) {
            errno = 0;
            entry = readdir(cursor->stream);
            if (!entry) { if (errno) return -1; return 0; }
            struct stat info;
            int result;
            do { result = fstatat(dirfd(cursor->stream), entry->d_name, &info, AT_SYMLINK_NOFOLLOW); }
            while (result < 0 && errno == EINTR);
            if (result < 0) { if (errno == ENOENT) continue; return -1; }
            if (!S_ISREG(info.st_mode)) continue;
            cursor->pending = entry;
        }
        size_t length = strlen(entry->d_name);
        if (length > INT64_MAX) return -1;
        if (length > capacity) return (int64_t)length;
        if (length) memcpy(out, entry->d_name, length);
        cursor->pending = NULL;
        return (int64_t)length;
    }
}
int32_t squid_directory_close(int64_t handle) {
    if (handle <= 0) return -1;
    struct squid_directory *cursor = (struct squid_directory *)(uintptr_t)handle;
    int result = closedir(cursor->stream);
    free(cursor);
    if (result < 0) return -1;
    return 0;
}
int32_t squid_last_errno(void) { return errno; }

/* The observer is optional in ordinary engines. Field zero snapshots its
 * covered counters and returns the coverage mask; other fields read that
 * snapshot. No linked observer means zero coverage, never invented liveness. */
#if defined(__GNUC__) || defined(__clang__)
extern uint64_t squid_allocation_observer_value(uint32_t field) __attribute__((weak));
#endif
#if defined(__GNUC__) || defined(__clang__)
extern void squid_allocation_observer_mark(void) __attribute__((weak));
#endif
void squid_runtime_memory_mark(void) {
#if defined(__GNUC__) || defined(__clang__)
    if (squid_allocation_observer_mark) squid_allocation_observer_mark();
#endif
}
uint64_t squid_runtime_observation(uint32_t field) {
#if defined(__GNUC__) || defined(__clang__)
    if (squid_allocation_observer_value) return squid_allocation_observer_value(field);
#else
    (void)field;
#endif
    return 0;
}
#endif
