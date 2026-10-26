/* Linux descriptor-relative K1 source resolver adapter. The package-root file
   descriptor is opened by trusted compiler code and kept live until close.
   Source paths are opened with openat2 beneath that descriptor. Relative
   symlinks confined to the root work; escapes and magic links fail closed.
   An unsupported kernel fails closed.
   C scratch allocations/read failures never append partial bytes to Goose.
   This adapter is compiler host code, not part of generated K1 programs. */
#define _GNU_SOURCE
#include "goose.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__)
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#if defined(__has_include)
#if __has_include(<linux/openat2.h>)
#include <linux/openat2.h>
#define K1_HAVE_OPENAT2_HEADER 1
#endif
#endif
#endif

typedef struct { const uint8_t *data; int64_t len; } k1_resolver_bytes;
enum { K1_RESOLVER_LIMIT = 16777216, K1_RESOLVER_PATH_LIMIT = 131068 };
/* Root open: nonnegative owned descriptor, -1 invalid/open error, -2 unsupported. */
int64_t k1_source_root_open(k1_resolver_bytes path) {
#if defined(__linux__) && defined(K1_HAVE_OPENAT2_HEADER) && defined(SYS_openat2)
    if (path.len <= 0 || path.len > K1_RESOLVER_PATH_LIMIT || !path.data ||
        memchr(path.data, 0, (size_t)path.len)) return -1;
    char *name = malloc((size_t)path.len + 1);
    if (!name) return -1;
    memcpy(name, path.data, (size_t)path.len); name[path.len] = 0;
    int fd = open(name, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    free(name);
    return fd >= 0 ? (int64_t)fd : -1;
#else
    (void)path; return -2;
#endif
}
/* Returns 0 on success. Regardless of close result the caller must discard
   this descriptor: retrying close after EINTR can close an unrelated fd. */
int64_t k1_source_root_close(int64_t root) {
#if defined(__linux__) && defined(K1_HAVE_OPENAT2_HEADER) && defined(SYS_openat2)
    if (root < 0 || root > INT32_MAX) return 1;
    return close((int)root) == 0 ? 0 : 1;
#else
    (void)root; return 1;
#endif
}

/* Verify path components again at the syscall boundary. No NULs, empty
   components, absolute paths, dot components, or backslashes are allowed. */
#if defined(__linux__) && defined(K1_HAVE_OPENAT2_HEADER) && defined(SYS_openat2)
static int k1_resolver_valid_path(k1_resolver_bytes path) {
    if (!path.data || path.len <= 0 || path.len > K1_RESOLVER_PATH_LIMIT || path.data[0] == '/') return 0;
    int64_t start = 0;
    for (int64_t i = 0; i <= path.len; ++i) {
        if (i < path.len && (path.data[i] == 0 || path.data[i] == '\\')) return 0;
        if (i == path.len || path.data[i] == '/') {
            int64_t n = i - start;
            if (n == 0 || (n == 1 && path.data[start] == '.') ||
                (n == 2 && path.data[start] == '.' && path.data[start + 1] == '.')) return 0;
            start = i + 1;
        }
    }
    return 1;
}
#endif

/* 0 success; 1 open/read/close/path failure; 2 source over 16 MiB;
   3 C scratch allocation failure; 4 unsupported platform/kernel.
   No bytes are appended unless open, fstat, bounded read and close all pass. */
int64_t k1_source_read_under(int64_t root, k1_resolver_bytes path, gs_rref out) {
#if defined(__linux__) && defined(K1_HAVE_OPENAT2_HEADER) && defined(SYS_openat2)
    if (root < 0 || root > INT32_MAX || !k1_resolver_valid_path(path)) return 1;
    struct stat root_stat;
    if (fstat((int)root, &root_stat) != 0 || !S_ISDIR(root_stat.st_mode)) return 1;
    char *name = malloc((size_t)path.len + 1);
    if (!name) return 3;
    memcpy(name, path.data, (size_t)path.len); name[path.len] = 0;
    struct open_how how = {0};
    how.flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
    int fd = (int)syscall(SYS_openat2, (int)root, name, &how, sizeof(how));
    int saved_errno = errno;
    free(name);
    if (fd < 0) return (saved_errno == ENOSYS || saved_errno == EINVAL) ? 4 : 1;
    struct stat st;
    int64_t status = 0;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0) status = 1;
    else if ((uint64_t)st.st_size > K1_RESOLVER_LIMIT) status = 2;
    size_t capacity = 65536, used = 0;
    uint8_t *scratch = NULL;
    if (status == 0) { scratch = malloc(capacity); if (!scratch) status = 3; }
    while (status == 0 && used < K1_RESOLVER_LIMIT) {
        if (used == capacity) {
            size_t next = capacity * 2;
            if (next > K1_RESOLVER_LIMIT) next = K1_RESOLVER_LIMIT;
            uint8_t *grown = realloc(scratch, next);
            if (!grown) { status = 3; break; }
            scratch = grown; capacity = next;
        }
        ssize_t n = read(fd, scratch + used, capacity - used);
        if (n > 0) { used += (size_t)n; continue; }
        if (n == 0) break;
        if (errno != EINTR) status = 1;
    }
    if (status == 0 && used == K1_RESOLVER_LIMIT) {
        uint8_t extra;
        ssize_t n;
        do { n = read(fd, &extra, 1); } while (n < 0 && errno == EINTR);
        if (n > 0) status = 2;
        else if (n < 0) status = 1;
    }
    /* Detect ordinary concurrent file mutation or truncation before
       publication. This is not an atomic filesystem snapshot: timestamp
       granularity and hostile writers can still defeat metadata checks. */
    if (status == 0) {
        struct stat after;
        if (fstat(fd, &after) != 0 || !S_ISREG(after.st_mode) ||
            after.st_dev != st.st_dev || after.st_ino != st.st_ino ||
            after.st_size != st.st_size || (uint64_t)after.st_size != (uint64_t)used ||
            after.st_mtim.tv_sec != st.st_mtim.tv_sec || after.st_mtim.tv_nsec != st.st_mtim.tv_nsec ||
            after.st_ctim.tv_sec != st.st_ctim.tv_sec || after.st_ctim.tv_nsec != st.st_ctim.tv_nsec) status = 1;
    }
    if (close(fd) != 0) status = 1;
    if (status == 0 && used) gs_bld_append(out, scratch, (int64_t)used);
    free(scratch);
    return status;
#else
    (void)root; (void)path; (void)out; return 4;
#endif
}
