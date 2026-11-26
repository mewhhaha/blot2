// Standalone native PLB runner for Blot wtime-aot --blot-cdylib modules.
// Usage:
//   blot_plb_runner <mode: int|str|fasta> <module.so> [args...]

#include <dlfcn.h>
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
        fprintf(stderr, "blot trap (%u): %.*s\n", (unsigned)code, (int)len, (const char *)ptr);
    } else {
        fprintf(stderr, "blot trap (%u)\n", (unsigned)code);
    }
}

static uint64_t upload_u32_array(
    void *h, fn_call_export call, fn_mem_data mem_data, fn_trap_message trap_msg,
    const uint32_t *words, uint32_t count
) {
    uint8_t trap = 0;
    uint64_t dummy = 0;
    call(h, (const uint8_t *)"blot:reset", 10, 0, &dummy, &trap);
    uint64_t ptr = 0;
    uint64_t bytes = 4ull + (uint64_t)count * 4ull;
    int32_t rc = call(h, (const uint8_t *)"blot:allocate", 13, bytes, &ptr, &trap);
    if (rc != 0) {
        fprintf(stderr, "blot:allocate(%llu) failed rc=%d\n", (unsigned long long)bytes, rc);
        print_trap(trap_msg, trap);
        exit(4);
    }
    uint8_t *mem = NULL;
    size_t mem_len = 0;
    mem_data(h, &mem, &mem_len);
    memcpy(mem + (uint32_t)ptr, &count, 4);
    if (count > 0) memcpy(mem + (uint32_t)ptr + 4, words, (size_t)count * 4);
    return ptr;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <int|str|fasta> <module.so> [args...]\n", argv[0]);
        return 2;
    }
    const char *mode = argv[1];
    const char *so_path = argv[2];

    void *dl = dlopen(so_path, RTLD_NOW | RTLD_LOCAL);
    if (!dl) { fprintf(stderr, "dlopen(%s): %s\n", so_path, dlerror()); return 2; }
    fn_new blot_new = (fn_new)dlsym(dl, "blot_aot_new");
    fn_drop blot_drop = (fn_drop)dlsym(dl, "blot_aot_drop");
    fn_call_export blot_call = (fn_call_export)dlsym(dl, "blot_aot_call_export");
    fn_call_finish blot_finish = (fn_call_finish)dlsym(dl, "blot_aot_call_finish_invocation");
    fn_mem_data blot_mem = (fn_mem_data)dlsym(dl, "blot_aot_mem_data");
    fn_trap_message trap_msg = (fn_trap_message)dlsym(dl, "blot_aot_trap_message");

    uint8_t trap = 0;
    void *h = blot_new(NULL, NULL, 0, &trap);
    if (!h) { print_trap(trap_msg, trap); return 3; }

    if (strcmp(mode, "str") == 0) {
        const char *arg = argc >= 4 ? argv[3] : "";
        uint32_t slen = (uint32_t)strlen(arg);
        uint32_t nwords = 1u + ((slen + 3u) >> 2);
        uint32_t *words = (uint32_t *)calloc(nwords, sizeof(uint32_t));
        words[0] = slen;
        if (slen > 0) memcpy((uint8_t *)(words + 1), arg, slen);
        uint64_t inp = upload_u32_array(h, blot_call, blot_mem, trap_msg, words, nwords);
        free(words);
        uint64_t out = 0;
        int32_t rc = blot_call(h, (const uint8_t *)"bench", 5, inp, &out, &trap);
        if (rc != 0) { print_trap(trap_msg, trap); blot_drop(h); return 4; }
        uint8_t *mem = NULL; size_t mlen = 0;
        blot_mem(h, &mem, &mlen);
        uint32_t blen = 0;
        memcpy(&blen, mem + (uint32_t)out + 4, 4);
        if (blen > 0) fwrite(mem + (uint32_t)out + 8, 1, blen, stdout);
        if (blot_finish) { int32_t fin = 0; blot_finish(h, &fin, &trap); }
    } else if (strcmp(mode, "fasta") == 0) {
        uint32_t n = argc >= 4 ? (uint32_t)strtoul(argv[3], NULL, 10) : 1000u;
        const uint32_t CHUNK = 60u * 8000u;
        uint32_t sec_totals[3] = {n * 2u, n * 3u, n * 5u};
        uint32_t seed = 42u;
        for (uint32_t sec = 0; sec < 3; sec++) {
            uint32_t total = sec_totals[sec];
            uint32_t off = 0;
            while (off < total) {
                uint32_t cnt = total - off;
                if (cnt > CHUNK) cnt = CHUNK;
                uint32_t args[5] = {sec, seed, off, cnt, off == 0 ? 1u : 0u};
                uint64_t inp = upload_u32_array(h, blot_call, blot_mem, trap_msg, args, 5);
                uint64_t out = 0;
                int32_t rc = blot_call(h, (const uint8_t *)"bench", 5, inp, &out, &trap);
                if (rc != 0) { print_trap(trap_msg, trap); blot_drop(h); return 4; }
                uint8_t *mem = NULL; size_t mlen = 0;
                blot_mem(h, &mem, &mlen);
                uint32_t blen = 0;
                memcpy(&blen, mem + (uint32_t)out + 4, 4);
                memcpy(&seed, mem + (uint32_t)out + 8, 4);
                if (blen > 0) fwrite(mem + (uint32_t)out + 12, 1, blen, stdout);
                if (blot_finish) { int32_t fin = 0; blot_finish(h, &fin, &trap); }
                off += cnt;
            }
        }
    } else {
        uint32_t args[4] = {0, 0, 0, 0};
        uint32_t nargs = 0;
        for (int i = 3; i < argc && nargs < 4; i++) {
            args[nargs++] = (uint32_t)strtoul(argv[i], NULL, 10);
        }
        uint64_t inp = upload_u32_array(h, blot_call, blot_mem, trap_msg, args, nargs > 0 ? nargs : 1);
        uint64_t out = 0;
        int32_t rc = blot_call(h, (const uint8_t *)"bench", 5, inp, &out, &trap);
        if (rc != 0) { print_trap(trap_msg, trap); blot_drop(h); return 4; }
        uint8_t *mem = NULL; size_t mlen = 0;
        blot_mem(h, &mem, &mlen);
        uint32_t blen = 0;
        memcpy(&blen, mem + (uint32_t)out + 4, 4);
        if (blen > 0) fwrite(mem + (uint32_t)out + 8, 1, blen, stdout);
        if (blot_finish) { int32_t fin = 0; blot_finish(h, &fin, &trap); }
    }

    fflush(stdout);
    blot_drop(h);
    dlclose(dl);
    return 0;
}
