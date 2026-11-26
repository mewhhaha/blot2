// Standalone native launcher for a wtime-aot --blot-cdylib benchmark module.
// Calls exported `bench () -> #[U32]` and prints checksum lines matching Goose,
// C++, and Rust byte-for-byte so all languages share identical whole-process
// timing, peak RSS (`wait4` ru_maxrss), and stdout checksum verification.
//
// Each output line is encoded as 3 consecutive U32 words: (mode, lo, hi)
//   mode 0: unsigned 64-bit ((uint64_t)hi << 32) | lo
//   mode 1: signed 64-bit   (int64_t)(((uint64_t)hi << 32) | lo)
//   mode 2: unsigned 32-bit lo

#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void *(*fn_new)(void *, const void *, uint64_t, uint8_t *);
typedef void (*fn_drop)(void *);
typedef int32_t (*fn_call_export)(void *, const uint8_t *, size_t, uint64_t, uint64_t *, uint8_t *);
typedef int32_t (*fn_call_finish)(void *, int32_t *, uint8_t *);
typedef void (*fn_mem_data)(void *, uint8_t **, size_t *);
typedef int32_t (*fn_trap_message)(uint8_t, const uint8_t **, size_t *);

static void print_trap(fn_trap_message trap_msg, uint8_t code) {
    const uint8_t *ptr = NULL;
    size_t len = 0;
    if (trap_msg && trap_msg(code, &ptr, &len) == 0 && ptr && len > 0) {
        fprintf(stderr, "blot_runner trap (%u): %.*s\n", (unsigned)code, (int)len, (const char *)ptr);
    } else {
        fprintf(stderr, "blot_runner trap (%u)\n", (unsigned)code);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <module.so>\n", argv[0]);
        return 2;
    }
    void *dl = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!dl) {
        fprintf(stderr, "dlopen(%s): %s\n", argv[1], dlerror());
        return 2;
    }
    fn_new blot_new = (fn_new)dlsym(dl, "blot_aot_new");
    fn_drop blot_drop = (fn_drop)dlsym(dl, "blot_aot_drop");
    fn_call_export blot_call = (fn_call_export)dlsym(dl, "blot_aot_call_export");
    fn_call_finish blot_finish = (fn_call_finish)dlsym(dl, "blot_aot_call_finish_invocation");
    fn_mem_data blot_mem = (fn_mem_data)dlsym(dl, "blot_aot_mem_data");
    fn_trap_message trap_msg = (fn_trap_message)dlsym(dl, "blot_aot_trap_message");
    if (!blot_new || !blot_drop || !blot_call || !blot_mem) {
        fprintf(stderr, "missing blot_aot_* symbol in %s\n", argv[1]);
        return 2;
    }

    uint8_t trap = 0;
    void *h = blot_new(NULL, NULL, 0, &trap);
    if (!h) {
        print_trap(trap_msg, trap);
        return 3;
    }

    uint64_t res = 0;
    int32_t rc = blot_call(h, (const uint8_t *)"bench", 5, 0, &res, &trap);
    if (rc != 0) {
        fprintf(stderr, "call bench failed rc=%d\n", rc);
        print_trap(trap_msg, trap);
        blot_drop(h);
        return 4;
    }

    uint8_t *mem = NULL;
    size_t mem_len = 0;
    blot_mem(h, &mem, &mem_len);
    uint32_t ptr = (uint32_t)res;
    if (!mem || (size_t)ptr + 4 > mem_len) {
        fprintf(stderr, "invalid result pointer %u (mem_len=%zu)\n", ptr, mem_len);
        blot_drop(h);
        return 5;
    }
    uint32_t count = 0;
    memcpy(&count, mem + ptr, 4);
    if ((size_t)ptr + 4 + (size_t)count * 4 > mem_len) {
        fprintf(stderr, "result array out of bounds count=%u\n", count);
        blot_drop(h);
        return 5;
    }
    for (uint32_t i = 0; i + 2 < count; i += 3) {
        uint32_t mode = 0, lo = 0, hi = 0;
        memcpy(&mode, mem + ptr + 4 + (size_t)i * 4, 4);
        memcpy(&lo, mem + ptr + 4 + (size_t)(i + 1) * 4, 4);
        memcpy(&hi, mem + ptr + 4 + (size_t)(i + 2) * 4, 4);
        uint64_t u64 = ((uint64_t)hi << 32) | (uint64_t)lo;
        if (mode == 0) {
            printf("%" PRIu64 "\n", u64);
        } else if (mode == 1) {
            printf("%" PRId64 "\n", (int64_t)u64);
        } else {
            printf("%" PRIu32 "\n", lo);
        }
    }

    if (blot_finish) {
        int32_t fin = 0;
        blot_finish(h, &fin, &trap);
    }
    blot_drop(h);
    dlclose(dl);
    return 0;
}
