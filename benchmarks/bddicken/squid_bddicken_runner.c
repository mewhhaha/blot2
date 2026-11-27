// Standalone native bddicken/languages runner for Squid wtime-aot --blot-cdylib modules.
// Mirrors bddicken/languages lib/c/benchmark.c timing & CSV output format:
//   mean_ms,std_dev_ms,min_ms,max_ms,runs,result
//
// Usage:
//   squid_bddicken_runner <mode: fibonacci|loops|levenshtein|hello-world> <module.so> <run_ms> <warmup_ms> <input>

#include <dlfcn.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef void *(*fn_new)(void *, const void *, uint64_t, uint8_t *);
typedef void (*fn_drop)(void *);
typedef int32_t (*fn_call_export)(void *, const uint8_t *, size_t, uint64_t, uint64_t *, uint8_t *);
typedef int32_t (*fn_call_finish)(void *, int32_t *, uint8_t *);
typedef void (*fn_mem_data)(void *, uint8_t **, size_t *);
typedef int32_t (*fn_trap_message)(uint8_t, const uint8_t **, size_t *);

static int64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

static void print_trap(fn_trap_message trap_msg, uint8_t code) {
    const uint8_t *ptr = NULL;
    size_t len = 0;
    if (trap_msg && trap_msg(code, &ptr, &len) == 0 && ptr && len > 0) {
        fprintf(stderr, "squid trap (%u): %.*s\n", (unsigned)code, (int)len, (const char *)ptr);
    } else {
        fprintf(stderr, "squid trap (%u)\n", (unsigned)code);
    }
}

static uint32_t *pack_words_file(const char *path, uint32_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        exit(2);
    }
    fseek(f, 0, SEEK_END);
    long fsz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *raw = (char *)malloc((size_t)fsz + 1);
    if (fread(raw, 1, (size_t)fsz, f) != (size_t)fsz) {
        fclose(f);
        free(raw);
        exit(2);
    }
    raw[fsz] = '\0';
    fclose(f);

    // Split on '\n' (matching levenshtein/c/run.c strtok(content, "\n"))
    size_t wcap = 128, wcnt = 0;
    const char **ptrs = (const char **)malloc(wcap * sizeof(char *));
    size_t *lens = (size_t *)malloc(wcap * sizeof(size_t));
    size_t total_chars = 0;
    char *p = raw;
    while (*p) {
        while (*p == '\n' || *p == '\r') p++;
        if (!*p) break;
        char *start = p;
        while (*p && *p != '\n' && *p != '\r') p++;
        size_t len = (size_t)(p - start);
        if (wcnt == wcap) {
            wcap *= 2;
            ptrs = (const char **)realloc(ptrs, wcap * sizeof(char *));
            lens = (size_t *)realloc(lens, wcap * sizeof(size_t));
        }
        ptrs[wcnt] = start;
        lens[wcnt] = len;
        total_chars += len;
        wcnt++;
    }

    uint32_t header = 1u + (uint32_t)wcnt * 2u;
    uint32_t total = header + (uint32_t)total_chars;
    uint32_t *buf = (uint32_t *)malloc((size_t)total * sizeof(uint32_t));
    buf[0] = (uint32_t)wcnt;
    uint32_t cur = header;
    for (size_t i = 0; i < wcnt; i++) {
        buf[1 + i * 2] = cur;
        buf[2 + i * 2] = (uint32_t)lens[i];
        for (size_t k = 0; k < lens[i]; k++) {
            buf[cur++] = (uint32_t)(unsigned char)ptrs[i][k];
        }
    }
    free(ptrs);
    free(lens);
    free(raw);
    *out_len = total;
    return buf;
}

typedef struct {
    void *h;
    fn_call_export call;
    fn_call_finish finish;
    fn_mem_data mem_data;
    fn_trap_message trap_msg;
    const char *mode;
    uint32_t arg_u32;
    uint32_t *lev_words;
    uint32_t lev_words_len;
    uint32_t lev_guest_ptr;
} ctx_t;

static uint64_t upload_u32_array(ctx_t *c, const uint32_t *data, uint32_t count) {
    uint8_t trap = 0;
    uint64_t dummy = 0;
    c->call(c->h, (const uint8_t *)"squid:reset", 10, 0, &dummy, &trap);
    uint64_t ptr = 0;
    uint64_t bytes = 4ull + (uint64_t)count * 4ull;
    int32_t rc = c->call(c->h, (const uint8_t *)"squid:allocate", 13, bytes, &ptr, &trap);
    if (rc != 0) {
        fprintf(stderr, "squid:allocate failed rc=%d\n", rc);
        print_trap(c->trap_msg, trap);
        exit(4);
    }
    uint8_t *mem = NULL;
    size_t mem_len = 0;
    c->mem_data(c->h, &mem, &mem_len);
    memcpy(mem + (uint32_t)ptr, &count, 4);
    memcpy(mem + (uint32_t)ptr + 4, data, (size_t)count * 4);
    return ptr;
}

static void prepare_call(ctx_t *c) {
    if (strcmp(c->mode, "levenshtein") == 0) {
        c->lev_guest_ptr = (uint32_t)upload_u32_array(c, c->lev_words, c->lev_words_len);
    }
}

static uint64_t invoke_once(ctx_t *c, int64_t *out_number) {
    uint8_t trap = 0;
    uint64_t res = 0;
    int32_t rc = 0;
    if (strcmp(c->mode, "fibonacci") == 0) {
        rc = c->call(c->h, (const uint8_t *)"fibonacci", 9, (uint64_t)c->arg_u32, &res, &trap);
        if (rc != 0) { print_trap(c->trap_msg, trap); exit(4); }
        *out_number = (int64_t)(uint32_t)res;
    } else if (strcmp(c->mode, "loops") == 0) {
        uint32_t r = (uint32_t)(rand() % 10000);
        uint32_t packed = (c->arg_u32 << 16) | r;
        rc = c->call(c->h, (const uint8_t *)"loops", 5, (uint64_t)packed, &res, &trap);
        if (rc != 0) { print_trap(c->trap_msg, trap); exit(4); }
        *out_number = (int64_t)(uint32_t)res;
    } else if (strcmp(c->mode, "levenshtein") == 0) {
        rc = c->call(c->h, (const uint8_t *)"distances", 9, (uint64_t)c->lev_guest_ptr, &res, &trap);
        if (rc != 0) { print_trap(c->trap_msg, trap); exit(4); }
    }
    return res;
}

static void finish_call(ctx_t *c, uint64_t res, int capture_lev_sum, int64_t *out_number) {
    uint8_t trap = 0;
    if (capture_lev_sum && strcmp(c->mode, "levenshtein") == 0) {
        uint8_t *mem = NULL;
        size_t mem_len = 0;
        c->mem_data(c->h, &mem, &mem_len);
        uint32_t ptr = (uint32_t)res;
        uint32_t count = 0;
        memcpy(&count, mem + ptr, 4);
        int64_t sum = 0;
        for (uint32_t i = 0; i < count; i++) {
            uint32_t v = 0;
            memcpy(&v, mem + ptr + 4 + (size_t)i * 4, 4);
            sum += (int64_t)v;
        }
        *out_number = sum;
    }
    if (c->finish) {
        int32_t fin = 0;
        c->finish(c->h, &fin, &trap);
    }
}

typedef struct {
    double mean_ms, sd_ms, min_ms, max_ms;
    int runs;
    int64_t result;
} stats_t;

static stats_t run_loop(ctx_t *c, int run_ms) {
    stats_t s = {0};
    if (run_ms <= 0) return s;
    int64_t run_ns = (int64_t)run_ms * 1000000LL;
    int64_t total_ns = 0;
    int cap = 1024, cnt = 0;
    int64_t *samples = (int64_t *)malloc((size_t)cap * sizeof(int64_t));
    int64_t last_val = 0;

    while (total_ns < run_ns) {
        prepare_call(c);
        int64_t t0 = now_ns();
        uint64_t raw_res = invoke_once(c, &last_val);
        int64_t t1 = now_ns();
        int64_t dt = t1 - t0;
        total_ns += dt;
        int is_last = total_ns >= run_ns;
        finish_call(c, raw_res, is_last, &last_val);
        if (cnt == cap) {
            cap *= 2;
            samples = (int64_t *)realloc(samples, (size_t)cap * sizeof(int64_t));
        }
        samples[cnt++] = dt;
    }

    double sum = 0.0, lo = samples[0] / 1e6, hi = lo;
    for (int i = 0; i < cnt; i++) {
        double ms = samples[i] / 1e6;
        sum += ms;
        if (ms < lo) lo = ms;
        if (ms > hi) hi = ms;
    }
    double mean = sum / cnt;
    double sq = 0.0;
    for (int i = 0; i < cnt; i++) {
        double d = samples[i] / 1e6 - mean;
        sq += d * d;
    }
    free(samples);
    s.mean_ms = mean;
    s.sd_ms = sqrt(sq / cnt);
    s.min_ms = lo;
    s.max_ms = hi;
    s.runs = cnt;
    s.result = last_val;
    return s;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <mode> <module.so> [run_ms warmup_ms input]\n", argv[0]);
        return 2;
    }
    const char *mode = argv[1];
    const char *so_path = argv[2];

    void *dl = dlopen(so_path, RTLD_NOW | RTLD_LOCAL);
    if (!dl) { fprintf(stderr, "dlopen(%s): %s\n", so_path, dlerror()); return 2; }
    fn_new squid_new = (fn_new)dlsym(dl, "blot_aot_new");
    fn_drop squid_drop = (fn_drop)dlsym(dl, "blot_aot_drop");
    fn_call_export squid_call = (fn_call_export)dlsym(dl, "blot_aot_call_export");
    fn_call_finish squid_finish = (fn_call_finish)dlsym(dl, "blot_aot_call_finish_invocation");
    fn_mem_data squid_mem = (fn_mem_data)dlsym(dl, "blot_aot_mem_data");
    fn_trap_message trap_msg = (fn_trap_message)dlsym(dl, "blot_aot_trap_message");

    uint8_t trap = 0;
    void *h = squid_new(NULL, NULL, 0, &trap);
    if (!h) { print_trap(trap_msg, trap); return 3; }

    if (strcmp(mode, "hello-world") == 0) {
        uint64_t res = 0;
        int32_t rc = squid_call(h, (const uint8_t *)"hello", 5, 0, &res, &trap);
        if (rc != 0) { print_trap(trap_msg, trap); squid_drop(h); return 4; }
        uint8_t *mem = NULL;
        size_t mem_len = 0;
        squid_mem(h, &mem, &mem_len);
        uint32_t ptr = (uint32_t)res;
        uint32_t count = 0;
        memcpy(&count, mem + ptr, 4);
        for (uint32_t i = 0; i < count; i++) {
            uint32_t cp = 0;
            memcpy(&cp, mem + ptr + 4 + (size_t)i * 4, 4);
            putchar((int)(cp & 0x7F));
        }
        putchar('\n');
        if (squid_finish) { int32_t fin = 0; squid_finish(h, &fin, &trap); }
        squid_drop(h);
        dlclose(dl);
        return 0;
    }

    if (argc < 6) {
        fprintf(stderr, "missing run_ms warmup_ms input\n");
        squid_drop(h);
        return 2;
    }
    int run_ms = atoi(argv[3]);
    int warmup_ms = atoi(argv[4]);
    const char *input = argv[5];

    srand((unsigned)time(NULL));
    ctx_t ctx = {0};
    ctx.h = h;
    ctx.call = squid_call;
    ctx.finish = squid_finish;
    ctx.mem_data = squid_mem;
    ctx.trap_msg = trap_msg;
    ctx.mode = mode;

    if (strcmp(mode, "levenshtein") == 0) {
        ctx.lev_words = pack_words_file(input, &ctx.lev_words_len);
    } else {
        ctx.arg_u32 = (uint32_t)strtoul(input, NULL, 10);
    }

    run_loop(&ctx, warmup_ms);
    stats_t st = run_loop(&ctx, run_ms);
    printf("%.6f,%.6f,%.6f,%.6f,%d,%" PRId64 "\n",
           st.mean_ms, st.sd_ms, st.min_ms, st.max_ms, st.runs, st.result);

    free(ctx.lev_words);
    squid_drop(h);
    dlclose(dl);
    return 0;
}
