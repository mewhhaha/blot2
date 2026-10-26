/* Target-scoped staging failures; ordinary compiler diagnostics and unrelated
 * files remain writable. The close fault releases the fd before reporting EIO. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static int staged_fd(int fd) {
    const char *target = getenv("BLOT_PUBLICATION_TARGET");
    if (!target) return 0;
    char descriptor[64], path[4096];
    snprintf(descriptor, sizeof(descriptor), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(descriptor, path, sizeof(path) - 1);
    if (n < 0) return 0;
    path[n] = 0;
    size_t size = strlen(target);
    return !strncmp(path, target, size) && !strncmp(path + size, ".blot-stage-", 12);
}
ssize_t write(int fd, const void *bytes, size_t count) {
    static ssize_t (*real_write)(int, const void *, size_t);
    static unsigned calls;
    if (!real_write) real_write = dlsym(RTLD_NEXT, "write");
    const char *fault = getenv("BLOT_PUBLICATION_WRITE");
    if (!fault || !staged_fd(fd)) return real_write(fd, bytes, count);
    calls++;
    if (!strcmp(fault, "eintr-short")) {
        if (calls == 1) { errno = EINTR; return -1; }
        if (calls == 2 && count > 7) count = 7;
    } else if (!strcmp(fault, "zero")) return 0;
    else if (!strcmp(fault, "partial-error") && calls == 1) {
        if (count > 7) count = 7;
    } else { errno = EIO; return -1; }
    return real_write(fd, bytes, count);
}
int close(int fd) {
    static int (*real_close)(int);
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");
    int fail = getenv("BLOT_PUBLICATION_CLOSE") && staged_fd(fd);
    int result = real_close(fd);
    if (fail) { errno = EIO; return -1; }
    return result;
}
int fchmod(int fd, mode_t mode) {
    static int (*real_fchmod)(int, mode_t);
    if (!real_fchmod) real_fchmod = dlsym(RTLD_NEXT, "fchmod");
    if (getenv("BLOT_PUBLICATION_CHMOD") && staged_fd(fd)) { errno = EIO; return -1; }
    return real_fchmod(fd, mode);
}
int fsync(int fd) {
    static int (*real_fsync)(int);
    if (!real_fsync) real_fsync = dlsym(RTLD_NEXT, "fsync");
    if (getenv("BLOT_PUBLICATION_FSYNC") && staged_fd(fd)) { errno = EIO; return -1; }
    return real_fsync(fd);
}
int rename(const char *from, const char *to) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    const char *target = getenv("BLOT_FAIL_RENAME_TARGET");
    if (target && !strcmp(target, to)) { errno = EIO; return -1; }
    return real_rename(from, to);
}
