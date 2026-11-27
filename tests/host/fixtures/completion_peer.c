/* A native completion peer keeps process startup outside the behavior under
 * test: held replies are released by cancellation, never by a timed sleep.
 *
 * completion_peer MODE LOG COMMAND, with MODE one of completion-hold,
 * completion-stall and completion-restart. It answers the project protocol on
 * stdin and stdout and writes each request's metadata to LOG. */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void write_all(int fd, const char *bytes, size_t length) {
    while (length) {
        ssize_t count = write(fd, bytes, length);
        if (count <= 0) exit(1);
        bytes += count;
        length -= (size_t)count;
    }
}

static void frame(const char *json) {
    uint32_t length = (uint32_t)strlen(json);
    unsigned char header[8] = {0};
    for (int i = 0; i < 4; i++) header[i] = (unsigned char)(length >> (8 * i));
    write_all(1, (const char *)header, 8);
    write_all(1, json, length);
}

/* Reads exactly `length` bytes; 0 at end of input before the first byte. */
static int read_all(char *out, size_t length) {
    size_t done = 0;
    while (done < length) {
        ssize_t count = read(0, out + done, length - done);
        if (count < 0) exit(1);
        if (count == 0) {
            if (done == 0) return 0;
            exit(1);
        }
        done += (size_t)count;
    }
    return 1;
}

/* The end of the JSON value that starts at `at`. */
static const char *value_end(const char *at, const char *end) {
    int depth = 0;
    while (at < end) {
        char c = *at;
        if (c == '"') {
            at++;
            while (at < end && *at != '"') at += *at == '\\' ? 2 : 1;
            at++;
        } else if (c == '{' || c == '[') {
            depth++;
            at++;
        } else if (c == '}' || c == ']') {
            if (depth == 0) return at;
            depth--;
            at++;
        } else if (c == ',' && depth == 0) {
            return at;
        } else {
            at++;
        }
        if (depth == 0 && (at >= end || *at == ',' || *at == '}')) return at;
    }
    return end;
}

/* The text of a top-level member's value, as written; NULL when absent. */
static char *member(const char *json, size_t length, const char *name) {
    const char *end = json + length;
    const char *at = json;
    while (at < end && *at != '{') at++;
    at++;
    size_t wanted = strlen(name);
    while (at < end) {
        while (at < end && (*at == ' ' || *at == ',' || *at == '\n')) at++;
        if (at >= end || *at != '"') return NULL;
        const char *key = at + 1;
        const char *close = key;
        while (close < end && *close != '"') close += *close == '\\' ? 2 : 1;
        at = close + 1;
        while (at < end && (*at == ' ' || *at == ':')) at++;
        const char *stop = value_end(at, end);
        if ((size_t)(close - key) == wanted && memcmp(key, name, wanted) == 0) {
            char *text = malloc((size_t)(stop - at) + 1);
            memcpy(text, at, (size_t)(stop - at));
            text[stop - at] = 0;
            return text;
        }
        at = stop;
    }
    return NULL;
}

static char *required(const char *json, size_t length, const char *name) {
    char *text = member(json, length, name);
    if (!text) exit(1);
    return text;
}

int main(int argc, char **argv) {
    if (argc != 4) return 1;
    const char *mode = argv[1];
    int restart = strcmp(mode, "completion-restart") == 0;
    if (!restart && strcmp(mode, "completion-hold") != 0 && strcmp(mode, "completion-stall") != 0) return 1;
    int first = 0;
    if (restart) {
        char path[4096];
        snprintf(path, sizeof path, "%s.started", argv[2]);
        int marker = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (marker >= 0) {
            close(marker);
            first = 1;
        }
    }
    int log = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (log < 0) return 1;
    char started[8192];
    int at = snprintf(started, sizeof started, "{\"pid\":%ld,\"command\":\"", (long)getpid());
    for (const char *c = argv[3]; *c && at < (int)sizeof started - 16; c++) {
        if (*c == '"' || *c == '\\') started[at++] = '\\';
        started[at++] = *c;
    }
    at += snprintf(started + at, sizeof started - (size_t)at, "\"}\n");
    write_all(log, started, (size_t)at);
    frame("{\"kind\":\"hello\",\"protocol\":\"squid-zig-project\",\"version\":1,"
          "\"compilerIdentity\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\","
          "\"capabilities\":[\"project-build\",\"utf8_bytes\",\"abort-disposes-process\",\"source-buffers-v1\",\"editor-completion-v1\"],"
          "\"maxFrameBytes\":67108864}");
    for (;;) {
        unsigned char header[8];
        if (!read_all((char *)header, 8)) return 0;
        uint32_t length = 0, payload = 0;
        for (int i = 0; i < 4; i++) {
            length |= (uint32_t)header[i] << (8 * i);
            payload |= (uint32_t)header[4 + i] << (8 * i);
        }
        if (length == 0 || length > 1048576 || payload > 67108864 - 8 - length) return 1;
        char *bytes = malloc((size_t)length + payload);
        if (!bytes || !read_all(bytes, (size_t)length + payload)) return 1;
        write_all(log, bytes, length);
        write_all(log, "\n", 1);
        char *kind = required(bytes, length, "kind");
        char *id = required(bytes, length, "id");
        char reply[16384];
        if (strcmp(kind, "\"open\"") == 0 || strcmp(kind, "\"close\"") == 0) {
            snprintf(reply, sizeof reply, "{\"kind\":%s,\"id\":%s,\"epoch\":\"epoch\",\"revision\":0}", kind, id);
            frame(reply);
            if (strcmp(kind, "\"close\"") == 0) return 0;
            free(kind);
            free(id);
            free(bytes);
            continue;
        }
        if (strcmp(kind, "\"complete\"") != 0) return 1;
        if (!restart || first) for (;;) sleep(60);
        char *position = required(bytes, length, "position");
        snprintf(reply, sizeof reply,
                 "{\"kind\":\"complete\",\"id\":%s,\"epoch\":\"epoch\",\"revision\":0,\"snapshot\":%s,\"filename\":%s,"
                 "\"position\":%s,\"success\":true,\"replace\":{\"start\":%s,\"end\":%s},\"context\":null,"
                 "\"items\":[{\"label\":\"value\",\"insertText\":\"value\",\"kind\":\"value\",\"detail\":\"U32\",\"match\":\"exact\"}],"
                 "\"truncated\":false,\"diagnostics\":[]}",
                 id, required(bytes, length, "snapshot"), required(bytes, length, "filename"), position, position, position);
        frame(reply);
        free(kind);
        free(id);
        free(position);
        free(bytes);
    }
}
