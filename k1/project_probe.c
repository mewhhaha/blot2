/* Bounded negative-path probe for the private project graph fixture. Root is
   a trusted live descriptor owned by source_resolver; no path-based fallback.
   A negative observation is returned only for kernel ENOENT. */
#define _GNU_SOURCE
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
#define K1_PROJECT_HAVE_OPENAT2 1
#endif
#endif
#endif

typedef struct { const uint8_t *data; int64_t len; } k1_project_bytes;
#if defined(__linux__) && defined(K1_PROJECT_HAVE_OPENAT2) && defined(SYS_openat2)
static int path_valid(k1_project_bytes p) {
    if (!p.data || p.len <= 0 || p.len > 131068 || p.data[0] == '/') return 0;
    int64_t start = 0;
    for (int64_t i = 0; i <= p.len; ++i) {
        if (i < p.len && (p.data[i] == 0 || p.data[i] == '\\')) return 0;
        if (i == p.len || p.data[i] == '/') {
            int64_t n = i - start;
            if (!n || (n == 1 && p.data[start] == '.') ||
                (n == 2 && p.data[start] == '.' && p.data[start + 1] == '.')) return 0;
            start = i + 1;
        }
    }
    return 1;
}
#endif
/* 0 absent, 1 regular entry present, 2 error/unsafe/nonregular, 4 unsupported.
   Existence is only an observation at the syscall, not a directory snapshot. */
int64_t k1_project_probe(int64_t root, k1_project_bytes path) {
#if defined(__linux__) && defined(K1_PROJECT_HAVE_OPENAT2) && defined(SYS_openat2)
    if (root < 0 || root > INT32_MAX || !path_valid(path)) return 2;
    struct stat root_stat;
    if (fstat((int)root, &root_stat) != 0 || !S_ISDIR(root_stat.st_mode)) return 2;
    char *name = malloc((size_t)path.len + 1);
    if (!name) return 2;
    memcpy(name, path.data, (size_t)path.len); name[path.len] = 0;
    struct open_how how = {0};
    how.flags = O_PATH | O_CLOEXEC;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
    int fd = (int)syscall(SYS_openat2, (int)root, name, &how, sizeof how);
    int saved = errno;
    free(name);
    if (fd < 0) {
        if (saved == ENOENT) return 0;
        if (saved == ENOSYS || saved == EINVAL) return 4;
        return 2;
    }
    struct stat st;
    int valid = fstat(fd, &st) == 0 && S_ISREG(st.st_mode);
    if (close(fd) != 0) valid = 0;
    return valid ? 1 : 2;
#else
    (void)root; (void)path; return 4;
#endif
}
