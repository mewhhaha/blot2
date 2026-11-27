// Cross-language C++20 reference implementations for Squid's Collection Families
// benchmark suite (Suite 8), compiled with clang++ -std=c++20 -O3 -march=native.
//
// Usage:
//   cpp_collections <bench_id> <variant> <n> <warmup> <samples>
// Prints: "<median_ms> <checksum>"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <time.h>
#include <vector>

static double now_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec * 1e-6;
}

// Prevent dead-code elimination without disturbing inner loops.
template <class T>
static inline void do_not_optimize(T const &val) {
    asm volatile("" : : "r,m"(val) : "memory");
}

struct BigPayload {
    uint64_t a, b, c, d, e, f, g, h;
};

struct BigEvent {
    uint32_t tag; // 0 = Tick, 1 = Big
    BigPayload big;
};

struct Entity {
    uint32_t id;
    uint32_t hp;
    double x, y, z, vx, vy, vz, mass;
    uint32_t flags;
};

// 1. flat_scan
static uint32_t run_flat_scan_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.push_back(i * 3u + 1u);
    uint32_t acc = 0;
    for (int p = 0; p < 10; p++) {
        for (uint32_t x : xs) acc += x;
    }
    return acc;
}
static uint32_t run_flat_scan_deque(uint32_t n) {
    std::deque<uint32_t> xs;
    for (uint32_t i = 0; i < n; i++) xs.push_back(i * 3u + 1u);
    uint32_t acc = 0;
    for (int p = 0; p < 10; p++) {
        for (uint32_t x : xs) acc += x;
    }
    return acc;
}

// 2. random_index
static uint32_t run_random_index_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.push_back(i * 7u + 3u);
    uint32_t acc = 0, seed = 1234567u;
    for (int k = 0; k < 200000; k++) {
        seed = seed * 1664525u + 1013904223u;
        acc += xs[seed % n];
    }
    return acc;
}
static uint32_t run_random_index_deque(uint32_t n) {
    std::deque<uint32_t> xs;
    for (uint32_t i = 0; i < n; i++) xs.push_back(i * 7u + 3u);
    uint32_t acc = 0, seed = 1234567u;
    for (int k = 0; k < 200000; k++) {
        seed = seed * 1664525u + 1013904223u;
        acc += xs[seed % n];
    }
    return acc;
}

// 3. skewed_sum (idiomatic tagged struct vs hand-written split-stream)
static uint32_t run_skewed_sum_vec(uint32_t n) {
    std::vector<BigEvent> evs;
    evs.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        if (i % 100u == 0u) {
            uint64_t v = i;
            evs.push_back(BigEvent{1u, {v, 1, 2, 3, 4, 5, 6, v + 7}});
        } else {
            BigEvent e{};
            e.tag = 0u;
            evs.push_back(e);
        }
    }
    uint32_t acc = 0;
    for (int p = 0; p < 20; p++) {
        for (const auto &ev : evs) {
            if (ev.tag == 0u) {
                acc += 1u;
            } else {
                acc += (uint32_t)ev.big.a + (uint32_t)ev.big.h;
            }
        }
    }
    return acc;
}
static uint32_t run_skewed_sum_split(uint32_t n) {
    std::vector<uint8_t> tags;
    std::vector<BigPayload> bigs;
    tags.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        if (i % 100u == 0u) {
            uint64_t v = i;
            tags.push_back(1);
            bigs.push_back(BigPayload{v, 1, 2, 3, 4, 5, 6, v + 7});
        } else {
            tags.push_back(0);
        }
    }
    uint32_t acc = 0;
    for (int p = 0; p < 20; p++) {
        size_t bi = 0;
        for (uint8_t t : tags) {
            if (t == 0) {
                acc += 1u;
            } else {
                const auto &b = bigs[bi++];
                acc += (uint32_t)b.a + (uint32_t)b.h;
            }
        }
    }
    return acc;
}

// 4. wide_soa (idiomatic AoS vector vs hand-written SoA)
static uint32_t run_wide_soa_vec(uint32_t n) {
    std::vector<Entity> ps;
    ps.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        ps.push_back(Entity{i, i * 2u + 1u, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 1u});
    }
    uint32_t acc = 0;
    for (int p = 0; p < 80; p++) {
        for (const auto &e : ps) acc += e.id + e.hp;
    }
    return acc;
}
static uint32_t run_wide_soa_manual(uint32_t n) {
    std::vector<uint32_t> id, hp, flags;
    std::vector<double> x, y, z, vx, vy, vz, mass;
    id.reserve(n); hp.reserve(n); flags.reserve(n);
    x.reserve(n); y.reserve(n); z.reserve(n);
    vx.reserve(n); vy.reserve(n); vz.reserve(n); mass.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        id.push_back(i); hp.push_back(i * 2u + 1u); flags.push_back(1u);
        x.push_back(1.0); y.push_back(2.0); z.push_back(3.0);
        vx.push_back(4.0); vy.push_back(5.0); vz.push_back(6.0); mass.push_back(7.0);
    }
    uint32_t acc = 0;
    for (int p = 0; p < 80; p++) {
        for (uint32_t i = 0; i < n; i++) acc += id[i] + hp[i];
    }
    return acc;
}

// 5. reverse_ops
static uint32_t run_reverse_ops_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.push_back(i);
    uint32_t acc = 0;
    for (uint32_t k = 0; k < 100; k++) {
        std::reverse(xs.begin(), xs.end());
        std::reverse(xs.begin() + k * 100u, xs.begin() + (n - k * 100u));
        acc += xs[0] + xs[n / 2u] + xs[n - 1u];
    }
    return acc;
}

// 6. generative_1m
static uint32_t run_generative_1m_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.push_back(10u + i * 3u);
    xs[n / 2u] = 999999u;
    uint32_t acc = 0, seed = 42u;
    for (int k = 0; k < 1000; k++) {
        seed = seed * 1664525u + 1013904223u;
        acc += xs[seed % n];
    }
    for (uint32_t j = 500000u; j < 500100u; j++) acc += xs[j];
    return acc;
}

// 7. snapshot_cow
static uint32_t run_snapshot_cow_vec(uint32_t n) {
    std::vector<uint32_t> base;
    base.reserve(n);
    for (uint32_t i = 0; i < n; i++) base.push_back(i);
    uint32_t acc = 0;
    for (uint32_t v = 0; v < 2000; v++) {
        std::vector<uint32_t> snap = base;
        uint32_t idx = (v * 97u) % n;
        snap[idx] = v + 1000u;
        acc += snap[idx] + snap[(idx + 1u) % n];
    }
    return acc;
}

// 8. cursor_insert
static uint32_t run_cursor_insert_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n + 2000u);
    for (uint32_t i = 0; i < n; i++) xs.push_back(i);
    uint32_t mid = n / 2u;
    for (uint32_t k = 0; k < 2000; k++) {
        xs.insert(xs.begin() + (mid + k), 100000u + k);
    }
    return xs[mid] + xs[mid + 1999u] + xs[mid + 2000u] + (uint32_t)xs.size();
}
static uint32_t run_cursor_insert_deque(uint32_t n) {
    std::deque<uint32_t> xs;
    for (uint32_t i = 0; i < n; i++) xs.push_back(i);
    uint32_t mid = n / 2u;
    for (uint32_t k = 0; k < 2000; k++) {
        xs.insert(xs.begin() + (mid + k), 100000u + k);
    }
    return xs[mid] + xs[mid + 1999u] + xs[mid + 2000u] + (uint32_t)xs.size();
}

// 9. front_deque
static uint32_t run_front_deque_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.insert(xs.begin(), i);
    uint32_t acc = 0;
    for (uint32_t k = 0; k < n / 2u; k++) {
        acc += xs.front();
        xs.erase(xs.begin());
    }
    return acc + (uint32_t)xs.size();
}
static uint32_t run_front_deque_deque(uint32_t n) {
    std::deque<uint32_t> xs;
    for (uint32_t i = 0; i < n; i++) xs.push_front(i);
    uint32_t acc = 0;
    for (uint32_t k = 0; k < n / 2u; k++) {
        acc += xs.front();
        xs.pop_front();
    }
    return acc + (uint32_t)xs.size();
}

// 10. split_concat (copy-split-concat matching value semantics)
static uint32_t run_split_concat_vec(uint32_t n) {
    std::vector<uint32_t> xs;
    xs.reserve(n);
    for (uint32_t i = 0; i < n; i++) xs.push_back(i);
    uint32_t seed = 987654u;
    for (int k = 0; k < 500; k++) {
        seed = seed * 1664525u + 1013904223u;
        uint32_t cut = seed % n;
        std::vector<uint32_t> out;
        out.reserve(n);
        out.insert(out.end(), xs.begin() + cut, xs.end());
        out.insert(out.end(), xs.begin(), xs.begin() + cut);
        xs.swap(out);
    }
    return xs[0] + xs[n / 2u] + xs[n - 1u];
}

// 11. frozen_span
static uint32_t run_frozen_span_vec(uint32_t n) {
    std::vector<uint32_t> base;
    base.reserve(n);
    for (uint32_t i = 0; i < n; i++) base.push_back(i * 5u + 7u);
    uint32_t acc = 0, seed = 314159u;
    for (int k = 0; k < 500; k++) {
        seed = seed * 1664525u + 1013904223u;
        uint32_t start = seed % (n - 20000u);
        std::vector<uint32_t> sub(base.begin() + start, base.begin() + start + 20000u);
        std::reverse(sub.begin(), sub.end());
        for (uint32_t j = 0; j < 100u; j++) acc += sub[j];
    }
    return acc;
}

// 12. packed_sum_cow
static uint32_t run_packed_sum_cow_vec(uint32_t n) {
    std::vector<BigEvent> evs;
    evs.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        if (i % 100u == 0u) {
            uint64_t v = i;
            evs.push_back(BigEvent{1u, {v, 1, 2, 3, 4, 5, 6, v + 7}});
        } else {
            BigEvent e{};
            e.tag = 0u;
            evs.push_back(e);
        }
    }
    uint32_t acc = 0;
    for (uint32_t v = 0; v < 1000; v++) {
        std::vector<BigEvent> snap = evs;
        uint32_t idx = (v * 97u) % n;
        uint64_t vv = v;
        snap[idx] = BigEvent{1u, {vv, 0, 0, 0, 0, 0, 0, vv + 1}};
        const auto &e1 = snap[idx];
        acc += (e1.tag == 0u) ? 1u : ((uint32_t)e1.big.a + (uint32_t)e1.big.h);
        const auto &e2 = snap[(idx + 1u) % n];
        acc += (e2.tag == 0u) ? 1u : ((uint32_t)e2.big.a + (uint32_t)e2.big.h);
    }
    return acc;
}

static uint32_t dispatch(const std::string &id, const std::string &var, uint32_t n) {
    if (id == "flat_scan" && var == "vector") return run_flat_scan_vec(n);
    if (id == "flat_scan" && var == "deque") return run_flat_scan_deque(n);
    if (id == "random_index" && var == "vector") return run_random_index_vec(n);
    if (id == "random_index" && var == "deque") return run_random_index_deque(n);
    if (id == "skewed_sum" && var == "vector") return run_skewed_sum_vec(n);
    if (id == "skewed_sum" && var == "manual_split") return run_skewed_sum_split(n);
    if (id == "wide_soa" && var == "vector") return run_wide_soa_vec(n);
    if (id == "wide_soa" && var == "manual_soa") return run_wide_soa_manual(n);
    if (id == "reverse_ops" && var == "vector") return run_reverse_ops_vec(n);
    if (id == "generative_1m" && var == "vector") return run_generative_1m_vec(n);
    if (id == "snapshot_cow" && var == "vector") return run_snapshot_cow_vec(n);
    if (id == "cursor_insert" && var == "vector") return run_cursor_insert_vec(n);
    if (id == "cursor_insert" && var == "deque") return run_cursor_insert_deque(n);
    if (id == "front_deque" && var == "vector") return run_front_deque_vec(n);
    if (id == "front_deque" && var == "deque") return run_front_deque_deque(n);
    if (id == "split_concat" && var == "vector") return run_split_concat_vec(n);
    if (id == "frozen_span" && var == "vector") return run_frozen_span_vec(n);
    if (id == "packed_sum_cow" && var == "vector") return run_packed_sum_cow_vec(n);
    fprintf(stderr, "unknown bench/variant: %s/%s\n", id.c_str(), var.c_str());
    exit(2);
}

int main(int argc, char **argv) {
    if (argc < 6) {
        fprintf(stderr, "usage: %s <bench_id> <variant> <n> <warmup> <samples>\n", argv[0]);
        return 2;
    }
    std::string id = argv[1];
    std::string var = argv[2];
    uint32_t n = (uint32_t)strtoul(argv[3], nullptr, 10);
    int warmup = atoi(argv[4]);
    int samples = atoi(argv[5]);
    uint32_t chk = 0;
    for (int i = 0; i < warmup; i++) {
        chk = dispatch(id, var, n);
        do_not_optimize(chk);
    }
    std::vector<double> times;
    times.reserve(samples);
    for (int i = 0; i < samples; i++) {
        double t0 = now_ms();
        uint32_t r = dispatch(id, var, n);
        double dt = now_ms() - t0;
        do_not_optimize(r);
        if (warmup > 0 && r != chk) {
            fprintf(stderr, "checksum mismatch\n");
            return 6;
        }
        chk = r;
        times.push_back(dt);
    }
    std::sort(times.begin(), times.end());
    printf("%.6f %u\n", times[samples / 2], chk);
    return 0;
}
