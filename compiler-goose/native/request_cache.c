#define _GNU_SOURCE
#include "request_cache.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define PARTS 3
#define MAX_BYTES UINT64_C(67108864)
#define PUBLISH_MS 10000
struct artifact {
    char directory[PATH_MAX], lock[PATH_MAX], target[PATH_MAX], temporary[PATH_MAX];
    uint64_t length;
    int fd;
    uint8_t occupied, remove;
};
static struct artifact queue[PARTS];
/* Ordinary CLI builds need no supervisor. A request exists only while the
 * candidate owns its immutable input; after finish, publication uses no Goose. */
extern int32_t blot_request_input_fd(void) __attribute__((weak));
int32_t blot_request_cache_active(void) {
    if (blot_request_input_fd) return blot_request_input_fd() >= 0;
    return 0;
}
static void close_artifact(struct artifact *item) {
    if (item->occupied && item->fd >= 0) close(item->fd);
    memset(item, 0, sizeof *item);
}
uint32_t blot_request_cache_pending(void) {
    uint32_t count = 0;
    for (unsigned i = 0; i < PARTS; i++) if (queue[i].occupied) count++;
    return count;
}
void blot_request_cache_discard(void) {
    for (unsigned i = 0; i < PARTS; i++) close_artifact(&queue[i]);
}
static int copy_path(char out[PATH_MAX], const uint8_t *in, uint64_t length) {
    if (!in || !length || length >= PATH_MAX || in[0] != '/') return -EINVAL;
    size_t component = 0;
    for (uint64_t i = 0; i < length; i++) {
        if (!in[i]) return -EINVAL;
        if (in[i] == '/') component = 0;
        else if (++component > NAME_MAX) return -ENAMETOOLONG;
    }
    memcpy(out, in, (size_t)length); out[length] = 0;
    return 0;
}
static int child_path(const char *directory, const char *path) {
    size_t n = strlen(directory);
    while (n > 1 && directory[n - 1] == '/') n--;
    if (strncmp(directory, path, n)) return 0;
    if (n == 1) return path[1] != 0 && !strchr(path + 1, '/');
    return path[n] == '/' && path[n + 1] && !strchr(path + n + 1, '/');
}
static int prepare(struct artifact *next, uint32_t part,
    const uint8_t *directory, uint64_t directory_length,
    const uint8_t *lock, uint64_t lock_length,
    const uint8_t *target, uint64_t target_length,
    const uint8_t *temporary, uint64_t temporary_length) {
    if (!blot_request_cache_active() || part >= PARTS) return -EINVAL;
    memset(next, 0, sizeof *next); next->fd = -1;
    int error = copy_path(next->directory, directory, directory_length);
    if (!error) error = copy_path(next->lock, lock, lock_length);
    if (!error) error = copy_path(next->target, target, target_length);
    if (!error && temporary) error = copy_path(next->temporary, temporary, temporary_length);
    if (error) return error;
    if (!child_path(next->directory, next->lock) ||
        !child_path(next->directory, next->target) || !strcmp(next->lock, next->target))
        return -EINVAL;
    if (temporary && (!child_path(next->directory, next->temporary) ||
        !strcmp(next->temporary, next->target) || !strcmp(next->temporary, next->lock)))
        return -EINVAL;
    for (unsigned i = 0; i < PARTS; i++) {
        const struct artifact *old = &queue[i];
        if (!old->occupied) continue;
        if (strcmp(next->directory, old->directory) || strcmp(next->lock, old->lock))
            return -ENOSPC;
        if (i != part && (!strcmp(next->target, old->target) ||
            !strcmp(next->target, old->temporary) ||
            (temporary && (!strcmp(next->temporary, old->target) ||
                           !strcmp(next->temporary, old->temporary))))) return -EINVAL;
    }
    return 0;
}
int32_t blot_request_cache_stage_write(uint32_t part,
    const uint8_t *directory, uint64_t directory_length,
    const uint8_t *lock, uint64_t lock_length,
    const uint8_t *target, uint64_t target_length,
    const uint8_t *temporary, uint64_t temporary_length,
    const uint8_t *bytes, uint64_t length) {
    if (length > MAX_BYTES || (length && !bytes)) return -EFBIG;
    struct artifact next;
    int error = prepare(&next, part, directory, directory_length, lock, lock_length,
                        target, target_length, temporary, temporary_length);
    if (error) return error;
    if (!temporary) return -EINVAL;
    int fd = memfd_create("blot-request-cache", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) return -errno;
    uint64_t offset = 0;
    while (offset < length) {
        size_t count = (size_t)(length - offset);
        if (count > 65536) count = 65536;
        ssize_t n = write(fd, bytes + offset, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { error = -EIO; break; }
        offset += (uint64_t)n;
    }
    if (!error && fcntl(fd, F_ADD_SEALS,
            F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) error = -errno;
    if (error) { close(fd); return error; }
    next.fd = fd; next.length = length; next.occupied = 1;
    close_artifact(&queue[part]); queue[part] = next;
    return 0;
}
int32_t blot_request_cache_stage_remove(uint32_t part,
    const uint8_t *directory, uint64_t directory_length,
    const uint8_t *lock, uint64_t lock_length,
    const uint8_t *target, uint64_t target_length) {
    struct artifact next;
    int error = prepare(&next, part, directory, directory_length, lock, lock_length,
                        target, target_length, NULL, 0);
    if (error) return error;
    next.occupied = 1; next.remove = 1;
    close_artifact(&queue[part]); queue[part] = next;
    return 0;
}
static int64_t now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
static int in_time(int64_t deadline) {
    int64_t now = now_ms();
    return now >= 0 && now < deadline;
}
static int directories(const char *directory) {
    char path[PATH_MAX];
    size_t length = strlen(directory);
    memcpy(path, directory, length + 1);
    for (size_t i = 1; i <= length; i++) {
        if (path[i] && path[i] != '/') continue;
        char saved = path[i]; path[i] = 0;
        int status = mkdir(path, 0777);
        path[i] = saved;
        if (status && errno != EEXIST) return -1;
    }
    return 0;
}
static int lock_key(const struct artifact *item, int64_t deadline) {
    if (directories(item->directory)) return -1;
    int fd = open(item->lock, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0666);
    if (fd < 0) return -1;
    while (in_time(deadline)) {
        if (!flock(fd, LOCK_EX | LOCK_NB)) return fd;
        if (errno != EWOULDBLOCK && errno != EINTR) break;
        struct timespec pause = { .tv_nsec = 10000000 };
        nanosleep(&pause, NULL);
    }
    close(fd); return -1;
}
static int publish_one(const struct artifact *item, int64_t deadline) {
    if (item->remove) return unlink(item->target);
    int fd = open(item->temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0666);
    if (fd < 0) return -1;
    uint8_t buffer[16384];
    uint64_t offset = 0;
    int good = 1;
    while (offset < item->length && good) {
        if (!in_time(deadline)) { good = 0; break; }
        size_t count = sizeof buffer;
        if (item->length - offset < count) count = (size_t)(item->length - offset);
        ssize_t n = pread(item->fd, buffer, count, (off_t)offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { good = 0; break; }
        ssize_t used = 0;
        while (used < n) {
            if (!in_time(deadline)) { good = 0; break; }
            ssize_t wrote = write(fd, buffer + used, (size_t)(n - used));
            if (wrote < 0 && errno == EINTR) continue;
            if (wrote <= 0) { good = 0; break; }
            used += wrote;
        }
        offset += (uint64_t)n;
    }
    if (good && (!in_time(deadline) || fsync(fd))) good = 0;
    if (close(fd)) good = 0;
    if (good && in_time(deadline) && !rename(item->temporary, item->target)) return 0;
    unlink(item->temporary); return -1;
}
void blot_request_cache_publish(void) {
    unsigned first = 0;
    while (first < PARTS && !queue[first].occupied) first++;
    if (first == PARTS) return;
    int64_t now = now_ms();
    int fd = -1;
    if (now >= 0) fd = lock_key(&queue[first], now + PUBLISH_MS);
    if (fd >= 0) {
        int64_t deadline = now + PUBLISH_MS;
        for (unsigned i = 0; i < PARTS; i++)
            if (queue[i].occupied && in_time(deadline)) publish_one(&queue[i], deadline);
        flock(fd, LOCK_UN); close(fd);
    }
    blot_request_cache_discard();
}
