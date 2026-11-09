#define _GNU_SOURCE
#include "request_transport.h"
#include "request_supervisor.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define FRAME_LIMIT UINT64_C(67108864)
#define META_LIMIT UINT64_C(16777216)
#define REVISION_LIMIT UINT64_C(9007199254740991)
struct text { uint64_t start, length; char small[32]; unsigned size; };
struct envelope {
    uint64_t id, revision;
    struct text kind, epoch, entry;
    unsigned seen;
    int success, revision_valid;
};
enum { HAS_ID = 1, HAS_REVISION = 2, HAS_KIND = 4, HAS_EPOCH = 8, HAS_ENTRY = 16, HAS_SUCCESS = 32 };
/* One bounded cursor: no metadata-sized allocation, mapping, or string copies.
 * At most metadata/2 container pairs fit; one bit per open container suffices.
 * Bits are overwritten on push, so ordinary frames never clear the whole stack. */
static uint8_t containers[META_LIMIT / 16];
_Static_assert(sizeof containers * 8 >= META_LIMIT / 2, "metadata-bounded container stack");
struct json {
    int fd, error;
    uint64_t position, length, base;
    size_t used;
    unsigned char buffer[4096];
};
struct value { int kind, overflow, negative; uint64_t number; struct text text; };
enum { OTHER, STRING, NUMBER, TRUE_VALUE, FALSE_VALUE, NULL_VALUE };
static int output = -1;
static struct envelope current, accepted;
static uint64_t revision;

static int byte(struct json *j) {
    if (j->error || j->position >= j->length) return -1;
    if (!j->used || j->position < j->base || j->position - j->base >= j->used) {
        j->base = j->position;
        size_t size = sizeof j->buffer;
        if (j->length - j->base < size) size = (size_t)(j->length - j->base);
        ssize_t n;
        do { n = pread(j->fd, j->buffer, size, (off_t)(8 + j->base)); } while (n < 0 && errno == EINTR);
        if (n <= 0) { j->error = 1; return -1; }
        j->used = (size_t)n;
    }
    return j->buffer[j->position - j->base];
}
static int take(struct json *j) { int c = byte(j); if (c >= 0) j->position++; return c; }
static void space(struct json *j) {
    for (;;) { int c = byte(j); if (c != ' ' && c != '\n' && c != '\r' && c != '\t') return; j->position++; }
}
static int want(struct json *j, int expected) { space(j); if (take(j) != expected) { j->error = 1; return 0; } return 1; }
static int hex(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static int code_unit(struct json *j) {
    int value = 0;
    for (int i = 0; i < 4; i++) { int digit = hex(take(j)); if (digit < 0) { j->error = 1; return 0; } value = value * 16 + digit; }
    return value;
}
static void small_character(struct text *t, int c) {
    if (t->size < sizeof t->small && c < 128) t->small[t->size] = (char)c;
    if (t->size < sizeof t->small) t->size++;
    if (c >= 128) t->size = sizeof t->small;
}
static struct text string(struct json *j) {
    struct text result = { .start = j->position };
    if (take(j) != '"') { j->error = 1; return result; }
    while (!j->error) {
        int c = take(j);
        if (c == '"') { result.length = j->position - result.start; return result; }
        if (c < 32) { j->error = 1; break; }
        if (c == '\\') {
            c = take(j);
            if (c == 'u') {
                c = code_unit(j);
                if (c >= 0xd800 && c <= 0xdbff) {
                    if (take(j) != '\\' || take(j) != 'u') { j->error = 1; break; }
                    int low = code_unit(j);
                    if (low < 0xdc00 || low > 0xdfff) { j->error = 1; break; }
                    c = 0x10000 + (c - 0xd800) * 1024 + low - 0xdc00;
                } else if (c >= 0xdc00 && c <= 0xdfff) { j->error = 1; break; }
            } else if (c == 'b') c = '\b';
            else if (c == 'f') c = '\f';
            else if (c == 'n') c = '\n';
            else if (c == 'r') c = '\r';
            else if (c == 't') c = '\t';
            else if (c != '"' && c != '\\' && c != '/') { j->error = 1; break; }
        } else if (c >= 128) {
            int width = 0, point = 0, minimum = 0;
            if (c >= 0xc2 && c <= 0xdf) { width = 1; point = c & 31; minimum = 0x80; }
            else if (c >= 0xe0 && c <= 0xef) { width = 2; point = c & 15; minimum = 0x800; }
            else if (c >= 0xf0 && c <= 0xf4) { width = 3; point = c & 7; minimum = 0x10000; }
            else { j->error = 1; break; }
            for (int i = 0; i < width; i++) {
                int continuation = take(j);
                if (continuation < 0x80 || continuation > 0xbf) { j->error = 1; break; }
                point = point * 64 + (continuation & 63);
            }
            if (point < minimum || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) j->error = 1;
            c = point;
        }
        small_character(&result, c);
    }
    return result;
}
static int equals(struct text t, const char *s) { size_t n = strlen(s); return t.size == n && !memcmp(t.small, s, n); }
static void field(struct json *j, struct envelope *out, struct text key, struct value v) {
    unsigned flag = 0;
    if (equals(key, "id")) flag = HAS_ID;
    else if (equals(key, "revision")) flag = HAS_REVISION;
    else if (equals(key, "kind")) flag = HAS_KIND;
    else if (equals(key, "epoch")) flag = HAS_EPOCH;
    else if (equals(key, "entry")) flag = HAS_ENTRY;
    else if (equals(key, "success")) flag = HAS_SUCCESS;
    if (!flag) return;
    if (out->seen & flag) { j->error = 1; return; }
    out->seen |= flag;
    if (flag == HAS_ID || flag == HAS_REVISION) {
        if (flag == HAS_REVISION && v.kind == NULL_VALUE) return;
        if (v.kind != NUMBER || v.overflow || (v.negative && v.number)) { j->error = 1; return; }
        if (flag == HAS_ID) out->id = v.number;
        else { out->revision = v.number; out->revision_valid = 1; }
    } else if (flag == HAS_SUCCESS) {
        if (v.kind != TRUE_VALUE && v.kind != FALSE_VALUE) { j->error = 1; return; }
        out->success = v.kind == TRUE_VALUE;
    } else if (v.kind == STRING) {
        if (flag == HAS_KIND) out->kind = v.text;
        else if (flag == HAS_EPOCH) out->epoch = v.text;
        else out->entry = v.text;
    }
}
static struct value scalar(struct json *j) {
    struct value result = {0};
    space(j); int c = byte(j);
    if (c == '"') { result.kind = STRING; result.text = string(j); return result; }
    if (c == 't' || c == 'f' || c == 'n') {
        const char *word = "null"; result.kind = NULL_VALUE;
        if (c == 't') { word = "true"; result.kind = TRUE_VALUE; }
        if (c == 'f') { word = "false"; result.kind = FALSE_VALUE; }
        while (*word) if (take(j) != *word++) { j->error = 1; break; }
        return result;
    }
    result.kind = NUMBER;
    if (c == '-') { result.negative = 1; take(j); c = byte(j); }
    if (c < '0' || c > '9') { j->error = 1; return result; }
    int leading = c, digits = 0;
    do {
        unsigned digit = (unsigned)(take(j) - '0'); digits++;
        if (result.number > UINT64_MAX / 10 || (result.number == UINT64_MAX / 10 && digit > UINT64_MAX % 10)) result.overflow = 1;
        if (!result.overflow) result.number = result.number * 10 + digit;
        c = byte(j);
    } while (c >= '0' && c <= '9');
    if (leading == '0' && digits > 1) j->error = 1;
    if (c == '.') {
        result.kind = OTHER; take(j); c = byte(j);
        if (c < '0' || c > '9') j->error = 1;
        while ((c = byte(j)) >= '0' && c <= '9') take(j);
    }
    c = byte(j);
    if (c == 'e' || c == 'E') {
        result.kind = OTHER; take(j); c = byte(j);
        if (c == '+' || c == '-') take(j);
        c = byte(j); if (c < '0' || c > '9') j->error = 1;
        while ((c = byte(j)) >= '0' && c <= '9') take(j);
    }
    return result;
}
/* JSON lexical traversal only. Unknown field schemas remain Goose's concern;
 * matching bracket kinds, object keys/colons, commas and scalar syntax do not. */
static void skip_container(struct json *j) {
    size_t depth = 0; int member = 0;
    while (!j->error) {
        if (member) { space(j); string(j); if (!want(j, ':')) return; }
        space(j); int c = byte(j);
        if (c == '{' || c == '[') {
            if (depth == sizeof containers * 8) { j->error = 1; return; }
            int object = c == '{', end = ']';
            if (object) end = '}';
            uint8_t mask = (uint8_t)(1u << (depth & 7));
            containers[depth >> 3] &= (uint8_t)~mask;
            if (object) containers[depth >> 3] |= mask;
            depth++; take(j); space(j);
            if (byte(j) == end) { take(j); depth--; }
            else { member = object; continue; }
        } else scalar(j);
        member = 0;
        while (depth && !j->error) {
            int object = (containers[(depth - 1) >> 3] >> ((depth - 1) & 7)) & 1;
            space(j); c = take(j);
            if (c == ',') { member = object; break; }
            int end = ']'; if (object) end = '}';
            if (c != end) { j->error = 1; return; }
            depth--;
        }
        if (!depth) return;
    }
}
static struct value value(struct json *j) {
    space(j); int c = byte(j);
    if (c == '{' || c == '[') { skip_container(j); return (struct value){0}; }
    return scalar(j);
}
static int envelope(int fd, uint64_t metadata, struct envelope *out) {
    memset(out, 0, sizeof *out);
    struct json j = { .fd = fd, .length = metadata };
    if (!want(&j, '{')) return -EPROTO;
    space(&j);
    if (byte(&j) == '}') take(&j);
    else while (!j.error) {
        space(&j); struct text key = string(&j);
        if (!want(&j, ':')) break;
        struct value v = value(&j); field(&j, out, key, v);
        space(&j); int c = take(&j);
        if (c == '}') break;
        if (c != ',') { j.error = 1; break; }
    }
    space(&j);
    if (j.error || j.position != j.length || !(out->seen & HAS_ID) ||
        !(out->seen & HAS_KIND) || !out->id || out->id > UINT32_MAX) return -EPROTO;
    return 0;
}
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void put32(uint8_t *p, uint32_t value) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)(value >> (i * 8)); }
static int write_all(int fd, const void *data, size_t length) {
    const uint8_t *p = data;
    while (length) {
        ssize_t n = write(fd, p, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -EIO;
        p += n; length -= (size_t)n;
    }
    return 0;
}
static int read_all(int fd, void *data, size_t length, int allow_eof) {
    uint8_t *p = data; size_t done = 0;
    while (done < length) {
        ssize_t n = read(fd, p + done, length - done);
        if (n < 0 && errno == EINTR) continue;
        if (!n && !done && allow_eof) return 0;
        if (n <= 0) return -EPROTO;
        done += (size_t)n;
    }
    return 1;
}
static int copy(int from, uint64_t offset, uint64_t length, int to) {
    uint8_t buffer[16384];
    while (length) {
        size_t count = sizeof buffer;
        if (length < count) count = (size_t)length;
        ssize_t n = pread(from, buffer, count, (off_t)offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -EIO;
        int error = write_all(to, buffer, (size_t)n); if (error) return error;
        offset += (uint64_t)n; length -= (uint64_t)n;
    }
    return 0;
}
static int lengths(uint8_t header[8], uint64_t *total) {
    uint64_t metadata = le32(header), payload = le32(header + 4);
    if (!metadata || metadata > META_LIMIT || payload > FRAME_LIMIT - 8 - metadata) return -EFBIG;
    *total = 8 + metadata + payload; return 0;
}
static int read_frame(int reader, int *fd, uint64_t *total, struct envelope *out) {
    uint8_t header[8]; *fd = -1;
    int status = read_all(reader, header, sizeof header, 1);
    if (status <= 0) return status;
    int error = lengths(header, total); if (error) return error;
    int spool = memfd_create("blot-frame", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (spool < 0) return -errno;
    error = write_all(spool, header, 8);
    uint64_t remaining = *total - 8;
    uint8_t buffer[16384];
    while (!error && remaining) {
        size_t count = sizeof buffer; if (remaining < count) count = (size_t)remaining;
        int n = read_all(reader, buffer, count, 0);
        if (n < 0) { error = n; break; }
        error = write_all(spool, buffer, count); remaining -= count;
    }
    if (!error && fcntl(spool, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) error = -errno;
    if (!error) error = envelope(spool, le32(header), out);
    if (error) { close(spool); return error; }
    *fd = spool; return 1;
}
static int32_t validate_reply(int32_t fd, uint64_t length, uint64_t token) {
    uint8_t header[8]; uint64_t total;
    if (pread(fd, header, 8, 0) != 8 || lengths(header, &total) || total != length ||
        envelope(fd, le32(header), &accepted)) return -EPROTO;
    if (accepted.id != token || accepted.kind.size != current.kind.size ||
        memcmp(accepted.kind.small, current.kind.small, current.kind.size) ||
        !equals(accepted.epoch, "1") || !accepted.revision_valid ||
        accepted.revision > REVISION_LIMIT) return -EPROTO;
    if (equals(current.kind, "open")) { if (accepted.revision) return -EPROTO; }
    else if (equals(current.kind, "build")) {
        if (!(accepted.seen & HAS_SUCCESS)) return -EPROTO;
        uint64_t expected = revision;
        if (accepted.success) expected++;
        if (accepted.revision != expected) return -EPROTO;
    } else if (accepted.revision != revision) return -EPROTO;
    return 0;
}
int32_t blot_request_transport_reply_open(void) {
    if (output >= 0) return -EBUSY;
    output = memfd_create("blot-reply", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (output < 0) return -errno;
    /* Sparse capacity plus a grow seal bounds writes in the kernel, before a
     * candidate can consume unbounded spool space. Writer uses sequential I/O. */
    if (ftruncate(output, FRAME_LIMIT) || fcntl(output, F_ADD_SEALS, F_SEAL_GROW)) {
        int error = errno; close(output); output = -1; return -error;
    }
    return output;
}
int32_t blot_request_transport_finish(uint64_t token) {
    off_t length = -1;
    if (output >= 0) length = lseek(output, 0, SEEK_CUR);
    if (length < 0 || (uint64_t)length > FRAME_LIMIT || ftruncate(output, length)) blot_request_fail(token);
    int result = blot_request_finish(output, (uint64_t)length, token);
    close(output); output = -1; return result;
}
static size_t decimal(uint64_t value, char out[20]) {
    char reversed[20]; size_t length = 0;
    do { reversed[length++] = (char)('0' + value % 10); value /= 10; } while (value);
    for (size_t i = 0; i < length; i++) out[i] = reversed[length - i - 1];
    return length;
}
static int oom_reply(int writer, uint32_t id, int entry_fd, struct text entry) {
    static const char head[] = "{\"kind\":\"build\",\"id\":";
    static const char middle[] = ",\"epoch\":\"1\",\"revision\":";
    static const char tail[] = ",\"success\":false,\"diagnostics\":[{\"filename\":";
    char id_bytes[20], revision_bytes[20];
    struct chunk { const char *data; size_t length; } prefix[] = {
        { head, sizeof head - 1 }, { id_bytes, decimal(id, id_bytes) },
        { middle, sizeof middle - 1 }, { revision_bytes, decimal(revision, revision_bytes) },
        { tail, sizeof tail - 1 },
    };
    size_t prefix_length = 0;
    for (size_t i = 0; i < sizeof prefix / sizeof prefix[0]; i++) prefix_length += prefix[i].length;
    static const char suffix[] = ",\"stage\":\"build-project\",\"code\":\"out_of_memory\",\"start\":0,\"end\":0,\"message\":\"Out of memory\",\"offset_encoding\":\"utf8_bytes\",\"utf16\":null,\"details\":null}],\"attemptStats\":null}";
    if (!entry.length || entry.length > META_LIMIT - 1024) { entry_fd = -1; entry.length = 2; }
    uint64_t metadata = (uint64_t)prefix_length + entry.length + sizeof suffix - 1;
    int fd = memfd_create("blot-oom", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) return -errno;
    uint8_t header[8] = {0}; put32(header, (uint32_t)metadata);
    int error = write_all(fd, header, 8);
    for (size_t i = 0; !error && i < sizeof prefix / sizeof prefix[0]; i++)
        error = write_all(fd, prefix[i].data, prefix[i].length);
    if (!error && entry_fd >= 0) error = copy(entry_fd, entry.start, entry.length, fd);
    else if (!error) error = write_all(fd, "\"\"", 2);
    if (!error) error = write_all(fd, suffix, sizeof suffix - 1);
    if (!error && fcntl(fd, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) error = -errno;
    if (!error) error = copy(fd, 0, 8 + metadata, writer);
    close(fd); return error;
}
int32_t blot_request_transport_run(int32_t reader_fd, int32_t writer_fd) {
    int entry_fd = -1, result = 0;
    struct text entry = {0}; uint64_t last_id = 0; revision = 0;
    blot_request_reply_validator(validate_reply);
    for (;;) {
        int request = -1; uint64_t total;
        int status = read_frame(reader_fd, &request, &total, &current);
        if (status <= 0) { result = status; break; }
        if (current.id <= last_id || (!equals(current.kind, "open") && !equals(current.kind, "build") &&
            !equals(current.kind, "complete") && !equals(current.kind, "checkpoint") && !equals(current.kind, "close"))) {
            close(request); result = -EPROTO; break;
        }
        last_id = current.id;
        int outcome = blot_request_submit(request, total, current.id);
        if (outcome == BLOT_REQUEST_ACCEPTED) {
            revision = accepted.revision;
            if (equals(current.kind, "open") && current.entry.length) {
                /* Keep only the encoded path, not a potentially 64 MiB opening
                 * checkpoint payload. This is bounded by metadata size. */
                int saved = memfd_create("blot-entry", MFD_CLOEXEC | MFD_ALLOW_SEALING);
                if (saved < 0) result = -errno;
                else {
                    result = copy(request, 8 + current.entry.start, current.entry.length, saved);
                    if (!result && fcntl(saved, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) result = -errno;
                    if (result) close(saved);
                    else { if (entry_fd >= 0) close(entry_fd); entry_fd = saved; entry = current.entry; entry.start = 0; }
                }
            }
            if (!result) result = copy(blot_request_reply_fd(), 0, blot_request_reply_length(), writer_fd);
        } else if (outcome == BLOT_REQUEST_OOM) {
            int name_fd = entry_fd; struct text name = entry;
            if (name_fd < 0 && equals(current.kind, "open")) { name_fd = request; name = current.entry; name.start += 8; }
            result = oom_reply(writer_fd, (uint32_t)current.id, name_fd, name);
        } else { result = -EIO; }
        if (request >= 0) close(request);
        if (result || (outcome == BLOT_REQUEST_ACCEPTED && equals(current.kind, "close"))) break;
    }
    blot_request_reply_validator(NULL);
    if (entry_fd >= 0) close(entry_fd);
    blot_request_stop(); return result;
}
