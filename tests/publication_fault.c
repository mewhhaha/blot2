/* Exercise the rollback after the first of two staged outputs was published. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
int rename(const char *from, const char *to) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    const char *target = getenv("BLOT_FAIL_RENAME_TARGET");
    if (target && !strcmp(target, to)) { errno = EIO; return -1; }
    return real_rename(from, to);
}
