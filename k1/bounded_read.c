/* File handles are not currently exposed by Goose's os module. This small
   host-side adapter reads at most the admitted source size, plus one byte
   to distinguish an exact-limit file from an oversized one. It is not part
   of generated K1 programs. */
#include "goose.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#endif

typedef struct { const uint8_t *data; int64_t len; } k1_bytes;
enum { K1_SOURCE_LIMIT = 16777216, K1_PATH_LIMIT = 131068 };

/* 0 success, 1 open/read/close/path failure, 2 file exceeds the limit. */
int64_t k1_read_bounded(k1_bytes path, gs_rref out) {
    if (path.len <= 0 || path.len > K1_PATH_LIMIT ||
        memchr(path.data, 0, (size_t)path.len) != NULL) return 1;
    FILE *f = NULL;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                (const char *)path.data, (int)path.len, NULL, 0);
    if (!n) return 1;
    wchar_t *wide = malloc(((size_t)n + 1) * sizeof *wide);
    if (!wide) return 1;
    int written = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      (const char *)path.data, (int)path.len, wide, n);
    if (written == n) {
        wide[n] = 0;
        f = _wfopen(wide, L"rb");
    }
    free(wide);
#else
    char *name = malloc((size_t)path.len + 1);
    if (!name) return 1;
    memcpy(name, path.data, (size_t)path.len);
    name[path.len] = 0;
    f = fopen(name, "rb");
    free(name);
#endif
    if (!f) return 1;
    uint8_t buffer[65536];
    size_t total = 0;
    int64_t status = 0;
    while (total < K1_SOURCE_LIMIT) {
        size_t want = K1_SOURCE_LIMIT - total;
        if (want > sizeof buffer) want = sizeof buffer;
        size_t n = fread(buffer, 1, want, f);
        if (n != 0) {
            gs_bld_append(out, buffer, (int64_t)n);
            total += n;
        }
        if (n < want) {
            if (ferror(f)) status = 1;
            else if (!feof(f)) status = 1;
            break;
        }
    }
    if (status == 0 && total == K1_SOURCE_LIMIT) {
        int c = fgetc(f);
        if (c != EOF) status = 2;
        else if (ferror(f)) status = 1;
    }
    if (fclose(f) != 0) status = 1;
    return status;
}
