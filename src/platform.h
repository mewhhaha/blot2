/* OS adapters only. All package resolution and compiler logic live in Goose. */
#ifndef BLOT_PLATFORM_H
#define BLOT_PLATFORM_H
#include <sys/stat.h>
#include <limits.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
/* 0 = EOF, 1 = complete line, 2 = oversized line (drained, never allocated). */
uint32_t blot_read_line_bounded(uint32_t limit, gs_rref out) {
    uint8_t buf[4096]; size_t used = 0; uint64_t total = 0;
    int c, seen = 0, too_large = 0;
    while ((c = fgetc(stdin)) != EOF) {
        seen = 1;
        if (c == '\n') break;
        if (++total > limit) { too_large = 1; continue; }
        buf[used++] = (uint8_t)c;
        if (used == sizeof(buf)) { gs_bld_append(out, buf, used); used = 0; }
    }
    if (used) gs_bld_append(out, buf, used);
    return too_large ? 2 : seen ? 1 : 0;
}
uint8_t blot_real_path(sl_u8 path, gs_rref out) {
    char input[4096], resolved[4096];
    if (path.len <= 0 || path.len >= sizeof(input) || memchr(path.data, 0, path.len)) return 0;
    memcpy(input, path.data, path.len); input[path.len] = 0;
#ifdef _WIN32
    if (!_fullpath(resolved, input, sizeof(resolved))) return 0;
#else
    if (!realpath(input, resolved)) return 0;
#endif
    gs_bld_append(out, resolved, (int64_t)strlen(resolved));
    return 1;
}
uint8_t blot_read_bounded(sl_u8 path, uint32_t limit, gs_rref out) {
    char input[4096];
    if (path.len <= 0 || path.len >= sizeof(input) || memchr(path.data, 0, path.len)) return 0;
    memcpy(input, path.data, path.len); input[path.len] = 0;
    FILE *f = fopen(input, "rb");
    if (!f) return 0;
    struct stat st;
    if (fstat(fileno(f), &st) || !S_ISREG(st.st_mode) || st.st_size < 0 || st.st_size > limit) {
        fclose(f); return 0;
    }
    uint8_t buf[4096]; uint64_t total = 0; size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) != 0) {
        total += n;
        if (total > limit) { fclose(f); return 0; }
        gs_bld_append(out, buf, (int64_t)n);
    }
    int ok = !ferror(f); fclose(f); return ok;
}
/* Generated Wasm needs atomic replacement, not a power-loss durability
 * acknowledgement. Finish every fallible write/permission/close operation
 * before rename. Deferred media/writeback failures are outside this result. */
uint8_t blot_write_generated_atomic(sl_u8 path, sl_u8 bytes) {
    char raw[4096], directory[4096], output[4096], temporary[4096];
    if (path.len <= 0 || (uint64_t)path.len >= sizeof(raw) || memchr(path.data, 0, path.len) || bytes.len < 0) return 0;
    memcpy(raw, path.data, path.len); raw[path.len] = 0;
    char *slash = strrchr(raw, '/'); const char *base = slash ? slash + 1 : raw;
    if (!*base || !strcmp(base, ".") || !strcmp(base, "..")) return 0;
    if (slash) { *slash = 0; if (!realpath(*raw ? raw : "/", directory)) return 0; }
    else if (!realpath(".", directory)) return 0;
    if (snprintf(output, sizeof(output), "%s/%s", directory, base) >= (int)sizeof(output)) return 0;
    struct stat st; int had_original = 0;
    if (!lstat(output, &st)) { if (!S_ISREG(st.st_mode)) return 0; had_original = 1; }
    else if (errno != ENOENT) return 0;
    int fd = -1;
    for (int attempt = 0; attempt < 8; attempt++) {
        if (snprintf(temporary, sizeof(temporary), "%s.blot-stage-%016llx", output,
                (unsigned long long)gs_os_random_u64()) >= (int)sizeof(temporary)) return 0;
        fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0666);
        if (fd >= 0) break;
        if (errno != EEXIST) return 0;
    }
    if (fd < 0) return 0;
    int ok = !had_original || fchmod(fd, st.st_mode & 0777) == 0;
    int64_t at = 0;
    while (ok && at < bytes.len) {
        size_t chunk = bytes.len - at > (1 << 30) ? (size_t)1 << 30 : (size_t)(bytes.len - at);
        ssize_t n = write(fd, bytes.data + at, chunk);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = 0; break; }
        at += n;
    }
    /* close may already have released fd on failure; never retry it. */
    if (close(fd)) ok = 0;
    if (ok && rename(temporary, output) == 0) return 1;
    unlink(temporary); return 0;
}
/* Stage all data and rollback links before publishing either output. The
 * commit window performs no allocation and defers ordinary cancellation.
 * Arbitrary readers and power loss need a directory/manifest transaction;
 * this adapter guarantees rollback on reported I/O failure, not that model. */
struct blot_output_stage {
    char path[4096], temporary[4096], backup[4096];
    int had_original, published;
};
static int blot_output_prepare(struct blot_output_stage *s, sl_u8 path, sl_u8 bytes) {
    char raw[4096], directory[4096];
    if (path.len <= 0 || path.len >= sizeof(raw) || memchr(path.data, 0, path.len)) return 0;
    memcpy(raw, path.data, path.len); raw[path.len] = 0;
    char *slash = strrchr(raw, '/'); const char *base = slash ? slash + 1 : raw;
    if (!*base || !strcmp(base, ".") || !strcmp(base, "..")) return 0;
    if (slash) { *slash = 0; if (!realpath(*raw ? raw : "/", directory)) return 0; }
    else if (!realpath(".", directory)) return 0;
    if (snprintf(s->path, sizeof(s->path), "%s/%s", directory, base) >= sizeof(s->path)) return 0;
    struct stat st;
    if (!lstat(s->path, &st)) { if (!S_ISREG(st.st_mode)) return 0; s->had_original = 1; }
    else if (errno != ENOENT) return 0;
    if (snprintf(s->temporary, sizeof(s->temporary), "%s.blot-stage-XXXXXX", s->path) >= sizeof(s->temporary)) { s->temporary[0] = 0; return 0; }
    int fd = mkstemp(s->temporary); if (fd < 0) { s->temporary[0] = 0; return 0; }
    int64_t at = 0; int ok = 1;
    while (at < bytes.len) { ssize_t n = write(fd, bytes.data + at, (size_t)(bytes.len - at)); if (n < 0 && errno == EINTR) continue; if (n <= 0) { ok = 0; break; } at += n; }
    if (ok && fsync(fd)) ok = 0;
    if (close(fd)) ok = 0;
    if (!ok) return 0;
    if (s->had_original) {
        if (snprintf(s->backup, sizeof(s->backup), "%s.blot-backup-XXXXXX", s->path) >= sizeof(s->backup)) { s->backup[0] = 0; return 0; }
        fd = mkstemp(s->backup); if (fd < 0) { s->backup[0] = 0; return 0; }
        close(fd); unlink(s->backup);
        if (link(s->path, s->backup)) { s->backup[0] = 0; return 0; }
    }
    return 1;
}
static void blot_output_cleanup(struct blot_output_stage *s) {
    if (*s->temporary) unlink(s->temporary);
    if (*s->backup) unlink(s->backup);
}
uint8_t blot_write_output_pair(sl_u8 first_path, sl_u8 first_bytes, sl_u8 second_path, sl_u8 second_bytes) {
    struct blot_output_stage a = {0}, b = {0}; int ok = 0;
    if (!blot_output_prepare(&a, first_path, first_bytes) || !blot_output_prepare(&b, second_path, second_bytes)) goto done;
    if (!strcmp(a.path, b.path)) goto done;
    sigset_t blocked, previous; sigemptyset(&blocked);
    sigaddset(&blocked, SIGINT); sigaddset(&blocked, SIGTERM); sigaddset(&blocked, SIGHUP);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous)) goto done;
    if (!rename(a.temporary, a.path)) {
        a.published = 1; a.temporary[0] = 0;
        if (!rename(b.temporary, b.path)) { b.published = 1; b.temporary[0] = 0; ok = 1; }
        else if (a.had_original) {
            if (!rename(a.backup, a.path)) a.backup[0] = 0;
            else { /* Preserve the recovery link on unexpected external interference. */
                fprintf(stderr, "k1_io_error: recovery output retained at %s\n", a.backup); a.backup[0] = 0;
            }
        } else unlink(a.path);
    }
    blot_output_cleanup(&a); blot_output_cleanup(&b);
    sigprocmask(SIG_SETMASK, &previous, NULL);
    return ok;
done:
    blot_output_cleanup(&a); blot_output_cleanup(&b); return 0;
}
#endif
