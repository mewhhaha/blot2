#define _GNU_SOURCE
#include "../request_transport.h"
#include "../request_supervisor.h"
#include <assert.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static uint32_t get32(const unsigned char *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void put32(unsigned char *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (unsigned char)(v >> (i * 8)); }
static int file(void) { int fd = memfd_create("transport-test", MFD_CLOEXEC); assert(fd >= 0); return fd; }
static void frame(int fd, const char *metadata, const char *payload) {
    unsigned char header[8]; size_t m = strlen(metadata), p = strlen(payload);
    put32(header, (uint32_t)m); put32(header + 4, (uint32_t)p);
    assert(write(fd, header, 8) == 8 && write(fd, metadata, m) == (ssize_t)m && write(fd, payload, p) == (ssize_t)p);
}
/* Fake request semantics exist only in this native boundary test. The production
 * transport knows framing/envelopes; it never parses or evaluates compiler input. */
static void worker(void) {
    int *state = malloc(sizeof *state); assert(state); *state = 0;
    unsigned revision = 0;
    while (!blot_request_begin()) {
        unsigned char header[8]; int input = blot_request_input_fd();
        assert(pread(input, header, 8, 0) == 8);
        uint32_t metadata = get32(header), payload = get32(header + 4);
        size_t prefix = metadata;
        if (prefix > 4095) prefix = 4095;
        char request[4096] = {0}; assert(pread(input, request, prefix, 8) == (ssize_t)prefix);
        char operation = 0;
        if (payload) assert(pread(input, &operation, 1, 8 + metadata) == 1);
        if (operation == 'm') { *state = 999; blot_request_fail_oom(blot_request_token()); }
        if (operation == 'a') { write(STDOUT_FILENO, "partial", 7); abort(); }
        const char *kind = "build";
        if (strstr(request, "\"open\"")) kind = "open";
        else if (strstr(request, "\"complete\"")) kind = "complete";
        else if (strstr(request, "\"close\"")) kind = "close";
        if (operation >= '0' && operation <= '9') { *state = operation - '0'; revision++; }
        unsigned reply_revision = revision;
        if (operation == 'r') reply_revision++;
        uint64_t id = blot_request_token();
        if (operation == 'i') id++;
        char reply[65536]; int n = snprintf(reply, sizeof reply,
            "{\"kind\":\"%s\",\"id\":%llu,\"epoch\":\"1\",\"revision\":%u,\"success\":true,\"value\":%d}",
            kind, (unsigned long long)id, reply_revision, *state);
        assert(n > 0 && (size_t)n < sizeof reply);
        if (operation == 'j') reply[n - 1] = ',';
        if (operation == 'd' || operation == 'D' || operation == 'b') {
            int depth = 65; if (operation != 'd') depth = 4096;
            n--; const char *field = ",\"details\":";
            memcpy(reply + n, field, strlen(field)); n += (int)strlen(field);
            for (int i = 0; i < depth; i++) {
                if (i & 1) { memcpy(reply + n, "{\"v\":", 5); n += 5; }
                else reply[n++] = '[';
            }
            const char *leaf = "[[],{},true,false,null,1.25e-3,\"\\uD83D\\uDC0E\"]";
            memcpy(reply + n, leaf, strlen(leaf)); n += (int)strlen(leaf);
            for (int i = depth - 1; i >= 0; i--) {
                char end = ']'; if (i & 1) end = '}';
                if (operation == 'b' && i == depth / 2) end = '}';
                reply[n++] = end;
            }
            reply[n++] = '}'; reply[n] = 0; assert((size_t)n < sizeof reply);
        }
        int output = blot_request_transport_reply_open(); assert(output >= 0);
        assert(pwrite(output, "x", 1, 67108864) == -1 && errno == EPERM);
        unsigned char wire[8] = {0}; put32(wire, (uint32_t)n);
        if (operation == 't') put32(wire, (uint32_t)n + 1);
        assert(write(output, wire, 8) == 8 && write(output, reply, (size_t)n) == n);
        if (operation == 'x') frame(output, "{}", "");
        assert(blot_request_transport_finish(blot_request_token()) == 0);
    }
    _exit(0);
}
static int run(int input, int output) {
    assert(lseek(input, 0, SEEK_SET) == 0);
    int role = blot_request_start(67108864, 67108864, 1000); assert(role >= 0);
    if (role == BLOT_REQUEST_WORKER) worker();
    int result = blot_request_transport_run(input, output);
    int status; assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
    assert(lseek(output, 0, SEEK_SET) == 0); return result;
}
static int reply(int fd, char *metadata, size_t capacity) {
    unsigned char header[8]; ssize_t count = read(fd, header, 8);
    if (!count) return 0;
    assert(count == 8); uint32_t length = get32(header), payload = get32(header + 4);
    assert(length < capacity && payload == 0 && read(fd, metadata, length) == length);
    metadata[length] = 0; return 1;
}
static void open_frame(int fd) { frame(fd, "{\"kind\":\"open\",\"id\":1,\"version\":1,\"entry\":\"/a\\\".blot\",\"revision\":null}", ""); }
static int fd_count(void) {
    DIR *directory = opendir("/proc/self/fd"); assert(directory);
    int count = 0; while (readdir(directory)) count++;
    closedir(directory); return count;
}
int main(void) {
    int initial_fds = fd_count();
    struct rlimit core = {0}; assert(!setrlimit(RLIMIT_CORE, &core));
    char metadata[2048];
    int input = file(), output = file();
    /* Caller emits Hello once; transport never emits another one. */
    frame(output, "{\"kind\":\"hello\",\"version\":1}", "");
    open_frame(input);
    frame(input, "{\"kind\":\"build\",\"id\":2,\"epoch\":\"1\",\"revision\":0}", "7");
    frame(input, "{\"kind\":\"build\",\"id\":3,\"epoch\":\"1\",\"revision\":1}", "m");
    frame(input, "{\"kind\":\"complete\",\"\\u0069d\":4,\"nested\":{\"id\":999},\"revision\":1}", "");
    frame(input, "{\"kind\":\"close\",\"id\":5}", "");
    assert(run(input, output) == 0);
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"hello\""));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"open\""));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"revision\":1"));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"code\":\"out_of_memory\"") &&
           strstr(metadata, "\"id\":3") && strstr(metadata, "\"revision\":1") && strstr(metadata, "\"filename\":\"/a\\\".blot\""));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"id\":4") && strstr(metadata, "\"revision\":1") && strstr(metadata, "\"value\":7"));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"close\""));
    assert(!reply(output, metadata, sizeof metadata)); close(input); close(output);

    char malformed[] = { 't', 'j', 'i', 'r', 'x', 'a', 'b' };
    for (unsigned i = 0; i < sizeof malformed; i++) {
        input = file(); output = file(); open_frame(input);
        char payload[] = { malformed[i], 0 };
        frame(input, "{\"kind\":\"complete\",\"id\":2}", payload);
        assert(run(input, output) == -EIO);
        assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"open\""));
        assert(!reply(output, metadata, sizeof metadata)); /* neither partial nor fake OOM */
        close(input); close(output);
    }
    input = file(); output = file(); open_frame(input);
    frame(input, "{\"kind\":\"build\",\"id\":2}", "m");
    frame(input, "{\"kind\":\"complete\",\"id\":2}", "");
    assert(run(input, output) == -EPROTO);
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "\"open\""));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "out_of_memory"));
    assert(!reply(output, metadata, sizeof metadata)); close(input); close(output);

    const char *invalid[] = {
        "{\"kind\":\"open\",\"id\":1,\"id\":2}",
        "{\"kind\":\"open\",\"id\":1,\"\\u0069d\":2}",
        "{\"kind\":\"open\",\"id\":4294967296}",
        "{\"kind\":\"open\",\"id\":01}",
        "{\"kind\":\"open\",\"id\":1.0}",
        "{\"kind\":\"open\",\"id\":1,\"entry\":\"\\ud800\"}",
        "{\"kind\":\"open\",\"id\":1,\"entry\":\"\xc0\x80\"}",
        "{\"kind\":\"open\",\"id\":1} trailing",
        "{\"kind\":\"open\",\"id\":1,\"nested\":{\"x\" 1}}",
        "{\"kind\":\"open\",\"id\":1,\"nested\":[1,]}",
        "{\"kind\":\"open\",\"id\":1,\"nested\":{\"x\":1,}}",
        "{\"kind\":\"open\",\"id\":1,\"nested\":[1 2]}",
        "{\"kind\":\"open\",\"id\":1,\"nested\":[}}",
    };
    for (unsigned i = 0; i < sizeof invalid / sizeof invalid[0]; i++) {
        input = file(); output = file(); frame(input, invalid[i], "");
        assert(run(input, output) == -EPROTO && !reply(output, metadata, sizeof metadata));
        close(input); close(output);
    }
    input = file(); output = file(); assert(write(input, "123", 3) == 3);
    assert(run(input, output) == -EPROTO && !reply(output, metadata, sizeof metadata)); close(input); close(output);
    input = file(); output = file(); unsigned char too_large[8] = {0}; put32(too_large, 16777217);
    assert(write(input, too_large, 8) == 8);
    assert(run(input, output) == -EFBIG && !reply(output, metadata, sizeof metadata)); close(input); close(output);
    input = file(); output = file();
    char large[8192]; const char *prefix = "{\"kind\":\"open\",\"padding\":\"";
    size_t at = strlen(prefix); memcpy(large, prefix, at); memset(large + at, 'x', 5000); at += 5000;
    strcpy(large + at, "\",\"\\u0069d\":1,\"entry\":\"/large.blot\"}");
    frame(input, large, "");
    frame(input, "{\"kind\":\"build\",\"id\":2}", "m");
    assert(run(input, output) == 0);
    assert(reply(output, metadata, sizeof metadata));
    assert(reply(output, metadata, sizeof metadata) && strstr(metadata, "/large.blot"));
    assert(!reply(output, metadata, sizeof metadata)); close(input); close(output);
    /* Opaque reply details may exceed both the typed-request depth 64 and
     * ordinary writer depth 256. Raw JSON output has no such depth policy. */
    char depths[] = { 'd', 'D' };
    for (unsigned i = 0; i < sizeof depths; i++) {
        input = file(); output = file(); open_frame(input);
        char payload[] = { depths[i], 0 };
        frame(input, "{\"kind\":\"complete\",\"id\":2}", payload);
        assert(run(input, output) == 0);
        assert(reply(output, metadata, sizeof metadata));
        char deep[65536];
        assert(reply(output, deep, sizeof deep) && strstr(deep, "\"details\":") && strstr(deep, "1.25e-3"));
        assert(!reply(output, metadata, sizeof metadata)); close(input); close(output);
    }
    input = file(); output = file(); frame(input, "{\"kind\":\"open\",\"id\":1}", "x");
    struct stat truncated; assert(!fstat(input, &truncated) && !ftruncate(input, truncated.st_size - 1));
    assert(run(input, output) == -EPROTO && !reply(output, metadata, sizeof metadata)); close(input); close(output);
    assert(fd_count() == initial_fds);
    puts("request transport: framing/envelope validation, retained revision/OOM id, one Hello, no partial output pass");
}
