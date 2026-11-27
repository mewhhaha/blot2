// Cross-language Rust reference implementations for Squid's Collection Families
// benchmark suite (Suite 8): Vec, VecDeque, manual SoA / split-stream, and
// imbl::Vector (persistent RRB-tree vector).
//
// Usage:
//   rust_collections <bench_id> <variant> <n> <warmup> <samples>
// Prints: "<median_ms> <checksum>"
use std::collections::VecDeque;
use std::hint::black_box;
use std::time::Instant;

#[derive(Clone, Copy)]
enum BigEvent {
    Tick,
    Big {
        a: u64,
        b: u64,
        c: u64,
        d: u64,
        e: u64,
        f: u64,
        g: u64,
        h: u64,
    },
}

#[derive(Clone, Copy)]
struct BigPayload {
    a: u64,
    b: u64,
    c: u64,
    d: u64,
    e: u64,
    f: u64,
    g: u64,
    h: u64,
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
struct Entity {
    id: u32,
    hp: u32,
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
    flags: u32,
}

// 1. flat_scan
fn flat_scan_vec(n: u32) -> u32 {
    let mut xs = Vec::with_capacity(n as usize);
    for i in 0..n {
        xs.push(i.wrapping_mul(3).wrapping_add(1));
    }
    let mut acc = 0u32;
    for _ in 0..10 {
        for &x in &xs {
            acc = acc.wrapping_add(x);
        }
    }
    acc
}
fn flat_scan_deque(n: u32) -> u32 {
    let mut xs = VecDeque::with_capacity(n as usize);
    for i in 0..n {
        xs.push_back(i.wrapping_mul(3).wrapping_add(1));
    }
    let mut acc = 0u32;
    for _ in 0..10 {
        for &x in &xs {
            acc = acc.wrapping_add(x);
        }
    }
    acc
}
fn flat_scan_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = imbl::Vector::new();
    for i in 0..n {
        xs.push_back(i.wrapping_mul(3).wrapping_add(1));
    }
    let mut acc = 0u32;
    for _ in 0..10 {
        for &x in &xs {
            acc = acc.wrapping_add(x);
        }
    }
    acc
}

// 2. random_index
fn random_index_vec(n: u32) -> u32 {
    let mut xs = Vec::with_capacity(n as usize);
    for i in 0..n {
        xs.push(i.wrapping_mul(7).wrapping_add(3));
    }
    let mut acc = 0u32;
    let mut seed = 1234567u32;
    for _ in 0..200_000 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        acc = acc.wrapping_add(xs[(seed % n) as usize]);
    }
    acc
}
fn random_index_deque(n: u32) -> u32 {
    let mut xs = VecDeque::with_capacity(n as usize);
    for i in 0..n {
        xs.push_back(i.wrapping_mul(7).wrapping_add(3));
    }
    let mut acc = 0u32;
    let mut seed = 1234567u32;
    for _ in 0..200_000 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        acc = acc.wrapping_add(xs[(seed % n) as usize]);
    }
    acc
}
fn random_index_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = imbl::Vector::new();
    for i in 0..n {
        xs.push_back(i.wrapping_mul(7).wrapping_add(3));
    }
    let mut acc = 0u32;
    let mut seed = 1234567u32;
    for _ in 0..200_000 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        acc = acc.wrapping_add(xs[(seed % n) as usize]);
    }
    acc
}

// 3. skewed_sum
fn skewed_sum_vec(n: u32) -> u32 {
    let mut evs = Vec::with_capacity(n as usize);
    for i in 0..n {
        if i % 100 == 0 {
            let v = i as u64;
            evs.push(BigEvent::Big {
                a: v,
                b: 1,
                c: 2,
                d: 3,
                e: 4,
                f: 5,
                g: 6,
                h: v + 7,
            });
        } else {
            evs.push(BigEvent::Tick);
        }
    }
    let mut acc = 0u32;
    for _ in 0..20 {
        for ev in &evs {
            match *ev {
                BigEvent::Tick => acc = acc.wrapping_add(1),
                BigEvent::Big { a, h, .. } => {
                    acc = acc.wrapping_add(a as u32).wrapping_add(h as u32);
                }
            }
        }
    }
    acc
}
fn skewed_sum_split(n: u32) -> u32 {
    let mut tags: Vec<u8> = Vec::with_capacity(n as usize);
    let mut bigs: Vec<BigPayload> = Vec::new();
    for i in 0..n {
        if i % 100 == 0 {
            let v = i as u64;
            tags.push(1);
            bigs.push(BigPayload {
                a: v,
                b: 1,
                c: 2,
                d: 3,
                e: 4,
                f: 5,
                g: 6,
                h: v + 7,
            });
        } else {
            tags.push(0);
        }
    }
    let mut acc = 0u32;
    for _ in 0..20 {
        let mut bi = 0usize;
        for &t in &tags {
            if t == 0 {
                acc = acc.wrapping_add(1);
            } else {
                let b = &bigs[bi];
                bi += 1;
                acc = acc.wrapping_add(b.a as u32).wrapping_add(b.h as u32);
            }
        }
    }
    acc
}
fn skewed_sum_imbl(n: u32) -> u32 {
    let mut evs: imbl::Vector<BigEvent> = imbl::Vector::new();
    for i in 0..n {
        if i % 100 == 0 {
            let v = i as u64;
            evs.push_back(BigEvent::Big {
                a: v,
                b: 1,
                c: 2,
                d: 3,
                e: 4,
                f: 5,
                g: 6,
                h: v + 7,
            });
        } else {
            evs.push_back(BigEvent::Tick);
        }
    }
    let mut acc = 0u32;
    for _ in 0..20 {
        for ev in &evs {
            match *ev {
                BigEvent::Tick => acc = acc.wrapping_add(1),
                BigEvent::Big { a, h, .. } => {
                    acc = acc.wrapping_add(a as u32).wrapping_add(h as u32);
                }
            }
        }
    }
    acc
}

// 4. wide_soa
fn wide_soa_vec(n: u32) -> u32 {
    let mut ps = Vec::with_capacity(n as usize);
    for i in 0..n {
        ps.push(Entity {
            id: i,
            hp: i.wrapping_mul(2).wrapping_add(1),
            x: 1.0,
            y: 2.0,
            z: 3.0,
            vx: 4.0,
            vy: 5.0,
            vz: 6.0,
            mass: 7.0,
            flags: 1,
        });
    }
    let mut acc = 0u32;
    for _ in 0..80 {
        for e in &ps {
            acc = acc.wrapping_add(e.id).wrapping_add(e.hp);
        }
    }
    acc
}
fn wide_soa_manual(n: u32) -> u32 {
    let cap = n as usize;
    let mut id = Vec::with_capacity(cap);
    let mut hp = Vec::with_capacity(cap);
    let mut x = Vec::with_capacity(cap);
    let mut y = Vec::with_capacity(cap);
    let mut z = Vec::with_capacity(cap);
    let mut vx = Vec::with_capacity(cap);
    let mut vy = Vec::with_capacity(cap);
    let mut vz = Vec::with_capacity(cap);
    let mut mass = Vec::with_capacity(cap);
    let mut flags = Vec::with_capacity(cap);
    for i in 0..n {
        id.push(i);
        hp.push(i.wrapping_mul(2).wrapping_add(1));
        x.push(1.0f64);
        y.push(2.0f64);
        z.push(3.0f64);
        vx.push(4.0f64);
        vy.push(5.0f64);
        vz.push(6.0f64);
        mass.push(7.0f64);
        flags.push(1u32);
    }
    let mut acc = 0u32;
    for _ in 0..80 {
        for i in 0..cap {
            acc = acc.wrapping_add(id[i]).wrapping_add(hp[i]);
        }
    }
    black_box((x.len(), y.len(), z.len(), vx.len(), vy.len(), vz.len(), mass.len(), flags.len()));
    acc
}
fn wide_soa_imbl(n: u32) -> u32 {
    let mut ps: imbl::Vector<Entity> = imbl::Vector::new();
    for i in 0..n {
        ps.push_back(Entity {
            id: i,
            hp: i.wrapping_mul(2).wrapping_add(1),
            x: 1.0,
            y: 2.0,
            z: 3.0,
            vx: 4.0,
            vy: 5.0,
            vz: 6.0,
            mass: 7.0,
            flags: 1,
        });
    }
    let mut acc = 0u32;
    for _ in 0..80 {
        for e in &ps {
            acc = acc.wrapping_add(e.id).wrapping_add(e.hp);
        }
    }
    acc
}

// 5. reverse_ops
fn reverse_ops_vec(n: u32) -> u32 {
    let mut xs: Vec<u32> = (0..n).collect();
    let mut acc = 0u32;
    for k in 0..100u32 {
        xs.reverse();
        let lo = (k * 100) as usize;
        let hi = (n - k * 100) as usize;
        xs[lo..hi].reverse();
        acc = acc
            .wrapping_add(xs[0])
            .wrapping_add(xs[(n / 2) as usize])
            .wrapping_add(xs[(n - 1) as usize]);
    }
    acc
}
fn reverse_ops_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = (0..n).collect();
    let mut acc = 0u32;
    for k in 0..100u32 {
        xs = xs.iter().copied().rev().collect();
        let lo = (k * 100) as usize;
        let hi = (n - k * 100) as usize;
        let right = xs.split_off(hi);
        let mid = xs.split_off(lo);
        let mid_rev: imbl::Vector<u32> = mid.iter().copied().rev().collect();
        xs.append(mid_rev);
        xs.append(right);
        acc = acc
            .wrapping_add(xs[0])
            .wrapping_add(xs[(n / 2) as usize])
            .wrapping_add(xs[(n - 1) as usize]);
    }
    acc
}

// 6. generative_1m
fn generative_1m_vec(n: u32) -> u32 {
    let mut xs = Vec::with_capacity(n as usize);
    for i in 0..n {
        xs.push(10u32.wrapping_add(i.wrapping_mul(3)));
    }
    xs[(n / 2) as usize] = 999999;
    let mut acc = 0u32;
    let mut seed = 42u32;
    for _ in 0..1000 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        acc = acc.wrapping_add(xs[(seed % n) as usize]);
    }
    for j in 500_000..500_100 {
        acc = acc.wrapping_add(xs[j]);
    }
    acc
}
fn generative_1m_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = (0..n).map(|i| 10u32.wrapping_add(i.wrapping_mul(3))).collect();
    xs.set((n / 2) as usize, 999999);
    let mut acc = 0u32;
    let mut seed = 42u32;
    for _ in 0..1000 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        acc = acc.wrapping_add(xs[(seed % n) as usize]);
    }
    for &x in xs.slice(500_000..500_100).iter() {
        acc = acc.wrapping_add(x);
    }
    acc
}

// 7. snapshot_cow
fn snapshot_cow_vec(n: u32) -> u32 {
    let base: Vec<u32> = (0..n).collect();
    let mut acc = 0u32;
    for v in 0..2000u32 {
        let mut snap = base.clone();
        let idx = ((v * 97) % n) as usize;
        snap[idx] = v + 1000;
        acc = acc
            .wrapping_add(snap[idx])
            .wrapping_add(snap[(idx + 1) % (n as usize)]);
    }
    acc
}
fn snapshot_cow_imbl(n: u32) -> u32 {
    let base: imbl::Vector<u32> = (0..n).collect();
    let mut acc = 0u32;
    for v in 0..2000u32 {
        let mut snap = base.clone();
        let idx = ((v * 97) % n) as usize;
        snap.set(idx, v + 1000);
        acc = acc
            .wrapping_add(snap[idx])
            .wrapping_add(snap[(idx + 1) % (n as usize)]);
    }
    acc
}

// 8. cursor_insert
fn cursor_insert_vec(n: u32) -> u32 {
    let mut xs = Vec::with_capacity((n + 2000) as usize);
    for i in 0..n {
        xs.push(i);
    }
    let mid = (n / 2) as usize;
    for k in 0..2000u32 {
        xs.insert(mid + (k as usize), 100000 + k);
    }
    xs[mid]
        .wrapping_add(xs[mid + 1999])
        .wrapping_add(xs[mid + 2000])
        .wrapping_add(xs.len() as u32)
}
fn cursor_insert_deque(n: u32) -> u32 {
    let mut xs = VecDeque::with_capacity((n + 2000) as usize);
    for i in 0..n {
        xs.push_back(i);
    }
    let mid = (n / 2) as usize;
    for k in 0..2000u32 {
        xs.insert(mid + (k as usize), 100000 + k);
    }
    xs[mid]
        .wrapping_add(xs[mid + 1999])
        .wrapping_add(xs[mid + 2000])
        .wrapping_add(xs.len() as u32)
}
fn cursor_insert_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = (0..n).collect();
    let mid = (n / 2) as usize;
    for k in 0..2000u32 {
        xs.insert(mid + (k as usize), 100000 + k);
    }
    xs[mid]
        .wrapping_add(xs[mid + 1999])
        .wrapping_add(xs[mid + 2000])
        .wrapping_add(xs.len() as u32)
}

// 9. front_deque
fn front_deque_vec(n: u32) -> u32 {
    let mut xs = Vec::with_capacity(n as usize);
    for i in 0..n {
        xs.insert(0, i);
    }
    let mut acc = 0u32;
    for _ in 0..(n / 2) {
        acc = acc.wrapping_add(xs.remove(0));
    }
    acc.wrapping_add(xs.len() as u32)
}
fn front_deque_deque(n: u32) -> u32 {
    let mut xs = VecDeque::with_capacity(n as usize);
    for i in 0..n {
        xs.push_front(i);
    }
    let mut acc = 0u32;
    for _ in 0..(n / 2) {
        acc = acc.wrapping_add(xs.pop_front().unwrap());
    }
    acc.wrapping_add(xs.len() as u32)
}
fn front_deque_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = imbl::Vector::new();
    for i in 0..n {
        xs.push_front(i);
    }
    let mut acc = 0u32;
    for _ in 0..(n / 2) {
        acc = acc.wrapping_add(xs.pop_front().unwrap());
    }
    acc.wrapping_add(xs.len() as u32)
}

// 10. split_concat
fn split_concat_vec(n: u32) -> u32 {
    let mut xs: Vec<u32> = (0..n).collect();
    let mut seed = 987654u32;
    for _ in 0..500 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let cut = (seed % n) as usize;
        let mut out = Vec::with_capacity(n as usize);
        out.extend_from_slice(&xs[cut..]);
        out.extend_from_slice(&xs[..cut]);
        xs = out;
    }
    xs[0]
        .wrapping_add(xs[(n / 2) as usize])
        .wrapping_add(xs[(n - 1) as usize])
}
fn split_concat_imbl(n: u32) -> u32 {
    let mut xs: imbl::Vector<u32> = (0..n).collect();
    let mut seed = 987654u32;
    for _ in 0..500 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let cut = (seed % n) as usize;
        let mut right = xs.split_off(cut);
        right.append(xs);
        xs = right;
    }
    xs[0]
        .wrapping_add(xs[(n / 2) as usize])
        .wrapping_add(xs[(n - 1) as usize])
}

// 11. frozen_span
fn frozen_span_vec(n: u32) -> u32 {
    let base: Vec<u32> = (0..n).map(|i| i.wrapping_mul(5).wrapping_add(7)).collect();
    let mut acc = 0u32;
    let mut seed = 314159u32;
    for _ in 0..500 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let start = (seed % (n - 20_000)) as usize;
        let mut sub = base[start..start + 20_000].to_vec();
        sub.reverse();
        for j in 0..100 {
            acc = acc.wrapping_add(sub[j]);
        }
    }
    acc
}
fn frozen_span_imbl(n: u32) -> u32 {
    let base: imbl::Vector<u32> = (0..n).map(|i| i.wrapping_mul(5).wrapping_add(7)).collect();
    let mut acc = 0u32;
    let mut seed = 314159u32;
    for _ in 0..500 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let start = (seed % (n - 20_000)) as usize;
        let sub = base.clone().slice(start..start + 20_000);
        for &x in sub.iter().rev().take(100) {
            acc = acc.wrapping_add(x);
        }
    }
    acc
}

// 12. packed_sum_cow
fn packed_sum_cow_vec(n: u32) -> u32 {
    let mut evs = Vec::with_capacity(n as usize);
    for i in 0..n {
        if i % 100 == 0 {
            let v = i as u64;
            evs.push(BigEvent::Big {
                a: v,
                b: 1,
                c: 2,
                d: 3,
                e: 4,
                f: 5,
                g: 6,
                h: v + 7,
            });
        } else {
            evs.push(BigEvent::Tick);
        }
    }
    let mut acc = 0u32;
    for v in 0..1000u32 {
        let mut snap = evs.clone();
        let idx = ((v * 97) % n) as usize;
        let vv = v as u64;
        snap[idx] = BigEvent::Big {
            a: vv,
            b: 0,
            c: 0,
            d: 0,
            e: 0,
            f: 0,
            g: 0,
            h: vv + 1,
        };
        for j in [idx, (idx + 1) % (n as usize)] {
            match snap[j] {
                BigEvent::Tick => acc = acc.wrapping_add(1),
                BigEvent::Big { a, h, .. } => {
                    acc = acc.wrapping_add(a as u32).wrapping_add(h as u32);
                }
            }
        }
    }
    acc
}
fn packed_sum_cow_imbl(n: u32) -> u32 {
    let mut evs: imbl::Vector<BigEvent> = imbl::Vector::new();
    for i in 0..n {
        if i % 100 == 0 {
            let v = i as u64;
            evs.push_back(BigEvent::Big {
                a: v,
                b: 1,
                c: 2,
                d: 3,
                e: 4,
                f: 5,
                g: 6,
                h: v + 7,
            });
        } else {
            evs.push_back(BigEvent::Tick);
        }
    }
    let mut acc = 0u32;
    for v in 0..1000u32 {
        let mut snap = evs.clone();
        let idx = ((v * 97) % n) as usize;
        let vv = v as u64;
        snap.set(
            idx,
            BigEvent::Big {
                a: vv,
                b: 0,
                c: 0,
                d: 0,
                e: 0,
                f: 0,
                g: 0,
                h: vv + 1,
            },
        );
        for j in [idx, (idx + 1) % (n as usize)] {
            match snap[j] {
                BigEvent::Tick => acc = acc.wrapping_add(1),
                BigEvent::Big { a, h, .. } => {
                    acc = acc.wrapping_add(a as u32).wrapping_add(h as u32);
                }
            }
        }
    }
    acc
}

fn dispatch(id: &str, var: &str, n: u32) -> u32 {
    match (id, var) {
        ("flat_scan", "vec") => flat_scan_vec(n),
        ("flat_scan", "deque") => flat_scan_deque(n),
        ("flat_scan", "imbl") => flat_scan_imbl(n),
        ("random_index", "vec") => random_index_vec(n),
        ("random_index", "deque") => random_index_deque(n),
        ("random_index", "imbl") => random_index_imbl(n),
        ("skewed_sum", "vec") => skewed_sum_vec(n),
        ("skewed_sum", "manual_split") => skewed_sum_split(n),
        ("skewed_sum", "imbl") => skewed_sum_imbl(n),
        ("wide_soa", "vec") => wide_soa_vec(n),
        ("wide_soa", "manual_soa") => wide_soa_manual(n),
        ("wide_soa", "imbl") => wide_soa_imbl(n),
        ("reverse_ops", "vec") => reverse_ops_vec(n),
        ("reverse_ops", "imbl") => reverse_ops_imbl(n),
        ("generative_1m", "vec") => generative_1m_vec(n),
        ("generative_1m", "imbl") => generative_1m_imbl(n),
        ("snapshot_cow", "vec") => snapshot_cow_vec(n),
        ("snapshot_cow", "imbl") => snapshot_cow_imbl(n),
        ("cursor_insert", "vec") => cursor_insert_vec(n),
        ("cursor_insert", "deque") => cursor_insert_deque(n),
        ("cursor_insert", "imbl") => cursor_insert_imbl(n),
        ("front_deque", "vec") => front_deque_vec(n),
        ("front_deque", "deque") => front_deque_deque(n),
        ("front_deque", "imbl") => front_deque_imbl(n),
        ("split_concat", "vec") => split_concat_vec(n),
        ("split_concat", "imbl") => split_concat_imbl(n),
        ("frozen_span", "vec") => frozen_span_vec(n),
        ("frozen_span", "imbl") => frozen_span_imbl(n),
        ("packed_sum_cow", "vec") => packed_sum_cow_vec(n),
        ("packed_sum_cow", "imbl") => packed_sum_cow_imbl(n),
        _ => panic!("unknown bench/variant: {id}/{var}"),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 6 {
        eprintln!("usage: {} <bench_id> <variant> <n> <warmup> <samples>", args[0]);
        std::process::exit(2);
    }
    let id = &args[1];
    let var = &args[2];
    let n: u32 = args[3].parse().unwrap();
    let warmup: usize = args[4].parse().unwrap();
    let samples: usize = args[5].parse().unwrap();

    let mut chk = 0u32;
    for _ in 0..warmup {
        chk = black_box(dispatch(id, var, black_box(n)));
    }
    let mut times = Vec::with_capacity(samples);
    for _ in 0..samples {
        let t0 = Instant::now();
        let r = black_box(dispatch(id, var, black_box(n)));
        let dt = t0.elapsed().as_secs_f64() * 1000.0;
        if warmup > 0 {
            assert_eq!(r, chk, "checksum mismatch");
        }
        chk = r;
        times.push(dt);
    }
    times.sort_by(f64::total_cmp);
    println!("{:.6} {}", times[samples / 2], chk);
}
