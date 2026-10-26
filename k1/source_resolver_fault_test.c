/* Standalone Linux fault-injection test; linked with --wrap for host syscalls.
   It verifies that errors after a partial read never append to the builder. */
#define _GNU_SOURCE
#include "goose.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <linux/openat2.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } k1_resolver_bytes;
int64_t k1_source_root_open(k1_resolver_bytes path);
int64_t k1_source_root_close(int64_t root);
int64_t k1_source_read_under(int64_t root, k1_resolver_bytes path, gs_rref out);
void *__real_malloc(size_t);
void *__real_realloc(void *, size_t);
ssize_t __real_read(int, void *, size_t);
int __real_close(int);
long __real_syscall(long, ...);
static int mode, root_fd, allocs, reads;
static int grow_once;

enum { FAIL_ALLOC = 1, FAIL_REALLOC = 2, FAIL_READ = 3, FAIL_CLOSE = 4,
       GROW_OVER = 5, NO_SYSCALL = 6, BAD_KERNEL = 7, PATH_RACE = 8 };
long __wrap_syscall(long number, ...) {
    assert(number == SYS_openat2);
    if (mode == NO_SYSCALL || mode == BAD_KERNEL || mode == PATH_RACE) {
        errno = mode == NO_SYSCALL ? ENOSYS : mode == BAD_KERNEL ? EINVAL : EAGAIN;
        return -1;
    }
    va_list args;
    va_start(args, number);
    int root = va_arg(args, int);
    const char *path = va_arg(args, const char *);
    struct open_how *how = va_arg(args, struct open_how *);
    size_t size = va_arg(args, size_t);
    va_end(args);
    return __real_syscall(number, root, path, how, size);
}
void *__wrap_malloc(size_t n) {
    if (mode == FAIL_ALLOC && ++allocs == 2) { errno = ENOMEM; return NULL; }
    return __real_malloc(n);
}
void *__wrap_realloc(void *p, size_t n) {
    if (mode == FAIL_REALLOC) { errno = ENOMEM; return NULL; }
    return __real_realloc(p, n);
}
ssize_t __wrap_read(int fd, void *p, size_t n) {
    if (mode == FAIL_READ && ++reads == 2) { errno = EIO; return -1; }
    if (mode == GROW_OVER && !grow_once) {
        grow_once = 1;
        int writer = openat(root_fd, "growing.blot", O_WRONLY | O_APPEND | O_CLOEXEC);
        assert(writer >= 0 && write(writer, "x", 1) == 1 && __real_close(writer) == 0);
    }
    return __real_read(fd, p, n);
}
int __wrap_close(int fd) {
    int result = __real_close(fd);
    if (mode == FAIL_CLOSE && fd != root_fd) { errno = EIO; return -1; }
    return result;
}
static k1_resolver_bytes bytes(const char *s) { return (k1_resolver_bytes){(const uint8_t *)s, (int64_t)strlen(s)}; }
int main(int argc, char **argv) {
    assert(argc == 2);
    root_fd = (int)k1_source_root_open(bytes(argv[1]));
    assert(root_fd >= 0);
    uint8_t *out = malloc(200000);
    assert(out);
    for (int fault = FAIL_ALLOC; fault <= PATH_RACE; ++fault) {
        memcpy(out, "sentinel", 8);
        gs_rhdr hdr = { out, 8 }; gs_stack stack = { out + 8 }; gs_rref builder = { &hdr, &stack };
        allocs = reads = grow_once = 0; mode = fault;
        int64_t status = k1_source_read_under(root_fd,
            bytes(fault == GROW_OVER ? "growing.blot" : "safe/big.blot"), builder);
        mode = 0;
        int64_t expected = fault == GROW_OVER ? 2 :
            (fault == FAIL_ALLOC || fault == FAIL_REALLOC ? 3 :
             (fault == NO_SYSCALL || fault == BAD_KERNEL ? 4 : 1));
        assert(status == expected);
        assert(hdr.len == 8 && stack.top == out + 8 && memcmp(out, "sentinel", 8) == 0);
        if (fault == FAIL_READ) assert(reads == 2);
        if (fault == GROW_OVER) assert(grow_once == 1);
    }
    assert(k1_source_root_close(root_fd) == 0);
    free(out);
    puts("source resolver allocation/read/close/growth failure laws passed");
}
