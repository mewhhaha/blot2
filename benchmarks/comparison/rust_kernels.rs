// Matching Rust implementations of the 6 kernels in blot_kernels.blot.
// Compiled both as a standalone wasm32-unknown-unknown cdylib (-C opt-level=3 -C target-feature=+simd128)
// and directly into the native x86_64 (-O3) benchmark harness.

#[unsafe(no_mangle)]
pub extern "C" fn lcg_recurrence(seed: u32) -> u32 {
    let mut state = seed | 1;
    let mut acc: u32 = 0;
    for _ in 0..1_000_000u32 {
        state = state.wrapping_mul(1664525).wrapping_add(1013904223);
        acc ^= state >> 16;
    }
    acc
}

#[unsafe(no_mangle)]
pub extern "C" fn prime_sieve(seed: u32) -> u32 {
    let limit = (100_000 + (seed % 256)) as usize;
    let mut flags = vec![true; limit];
    if limit > 0 {
        flags[0] = false;
    }
    if limit > 1 {
        flags[1] = false;
    }
    let mut p = 2usize;
    while p * p < limit {
        if flags[p] {
            let mut m = p * p;
            while m < limit {
                flags[m] = false;
                m += p;
            }
        }
        p += 1;
    }
    let mut sum: u32 = 0;
    let mut count: u32 = 0;
    for i in 2..limit {
        if flags[i] {
            count = count.wrapping_add(1);
            sum = sum.wrapping_add(i as u32);
        }
    }
    sum ^ count.wrapping_mul(2654435761)
}

#[unsafe(no_mangle)]
pub extern "C" fn matmul_64(seed: u32) -> u32 {
    let n = 64usize;
    let total = n * n;
    let mut a = vec![0.0f32; total];
    let mut b = vec![0.0f32; total];
    let mut c = vec![0.0f32; total];
    let mut s = seed | 1;
    for i in 0..total {
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        a[i] = ((s & 1023) as f32) * 0.0009765625;
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        b[i] = ((s & 1023) as f32) * 0.0009765625;
    }
    for row in 0..n {
        let row_off = row * n;
        for k in 0..n {
            let aik = a[row_off + k];
            let k_off = k * n;
            for col in 0..n {
                c[row_off + col] += aik * b[k_off + col];
            }
        }
    }
    let mut sum = 0.0f32;
    for &v in &c {
        sum += v;
    }
    (sum * 100.0) as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn mandelbrot_f32(seed: u32) -> u32 {
    let size = 256u32;
    let inv = 1.0f32 / (size as f32);
    let bias = ((seed & 7) as f32) * 0.001;
    let mut total: u32 = 0;
    for py in 0..size {
        let ci = (py as f32) * inv * 2.4 - 1.2 + bias;
        for px in 0..size {
            let cr = (px as f32) * inv * 3.0 - 2.0;
            let mut zr = 0.0f32;
            let mut zi = 0.0f32;
            let mut it = 0u32;
            while it < 100 {
                let zr2 = zr * zr;
                let zi2 = zi * zi;
                if zr2 + zi2 > 4.0 {
                    break;
                }
                let next_zi = 2.0 * zr * zi + ci;
                zr = zr2 - zi2 + cr;
                zi = next_zi;
                it += 1;
            }
            total = total.wrapping_add(it);
        }
    }
    total
}

fn integrate_particles(px: &[f32], vx: &[f32], ax: &[f32], dt: f32) -> Vec<f32> {
    let half_dt2 = 0.5 * dt * dt;
    let n = px.len();
    let mut out = vec![0.0f32; n];
    for i in 0..n {
        out[i] = px[i] + vx[i] * dt + ax[i] * half_dt2;
    }
    out
}

#[unsafe(no_mangle)]
pub extern "C" fn particle_spark_simd(seed: u32) -> u32 {
    let n = 65536usize;
    let mut px = vec![0.0f32; n];
    let mut vx = vec![0.0f32; n];
    let mut ax = vec![0.0f32; n];
    let base = (seed & 15) as f32;
    for i in 0..n {
        let fi = (i & 1023) as f32;
        px[i] = base + fi * 0.01;
        vx[i] = fi * 0.02;
        ax[i] = 0.5 - fi * 0.001;
    }
    let mut out = px;
    for _ in 0..32 {
        out = integrate_particles(&out, &vx, &ax, 0.016);
    }
    let mut sum = 0.0f32;
    for &v in &out {
        sum += v;
    }
    (sum * 10.0) as u32
}

fn merge_range(src: &[u32], dst: &mut [u32], lo: usize, mid: usize, hi: usize) {
    let mut i = lo;
    let mut j = mid;
    let mut k = lo;
    while i < mid && j < hi {
        if src[i] <= src[j] {
            dst[k] = src[i];
            i += 1;
        } else {
            dst[k] = src[j];
            j += 1;
        }
        k += 1;
    }
    while i < mid {
        dst[k] = src[i];
        i += 1;
        k += 1;
    }
    while j < hi {
        dst[k] = src[j];
        j += 1;
        k += 1;
    }
}

fn merge_pass(src: &[u32], dst: &mut [u32], width: usize, n: usize) {
    let mut lo = 0usize;
    let step = width << 1;
    while lo < n {
        let mid = (lo + width).min(n);
        let hi = (lo + step).min(n);
        merge_range(src, dst, lo, mid, hi);
        lo += step;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn merge_sort(seed: u32) -> u32 {
    let n = 100_000usize;
    let mut a = vec![0u32; n];
    let mut b = vec![0u32; n];
    let mut s = seed | 1;
    for i in 0..n {
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        a[i] = s;
    }
    let mut width = 1usize;
    let mut in_b = false;
    while width < n {
        merge_pass(&a, &mut b, width, n);
        width <<= 1;
        if width >= n {
            in_b = true;
            break;
        }
        merge_pass(&b, &mut a, width, n);
        width <<= 1;
    }
    let sorted = if in_b { &b } else { &a };
    let mut hash: u32 = 0;
    for i in 0..n {
        if i > 0 && sorted[i] < sorted[i - 1] {
            panic!("not sorted");
        }
        hash = hash.wrapping_mul(31) ^ sorted[i];
    }
    hash
}
