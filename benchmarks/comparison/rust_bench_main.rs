use bevy_ecs::prelude::*;
use std::ffi::{CString, c_void};
use std::hint::black_box;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

#[path = "rust_kernels.rs"]
mod rust_kernels;

#[derive(Component, Clone, Copy)]
struct Pos {
    x: f32,
    y: f32,
    z: f32,
}

#[derive(Component, Clone, Copy)]
struct Vel {
    vx: f32,
    vy: f32,
    vz: f32,
}

#[derive(Component, Clone, Copy)]
struct Active;

#[derive(Component, Clone, Copy)]
struct Frozen;

fn median(mut xs: Vec<f64>) -> f64 {
    xs.sort_by(f64::total_cmp);
    let m = xs.len() / 2;
    if xs.len() % 2 == 0 {
        (xs[m - 1] + xs[m]) * 0.5
    } else {
        xs[m]
    }
}

fn time_ms<F: FnMut() -> u32>(warmups: usize, samples: usize, mut f: F) -> (f64, u32) {
    let mut last = 0u32;
    for _ in 0..warmups {
        last = black_box(f());
    }
    let mut times = Vec::with_capacity(samples);
    for _ in 0..samples {
        let t0 = Instant::now();
        last = black_box(f());
        times.push(t0.elapsed().as_secs_f64() * 1000.0);
    }
    (median(times), last)
}

type FnTrapMessage = unsafe extern "C" fn(u8, *mut *const u8, *mut usize) -> i32;
type FnNew = unsafe extern "C" fn(*mut c_void, *const c_void, u64, *mut u8) -> *mut c_void;
type FnDrop = unsafe extern "C" fn(*mut c_void);
type FnCallExport =
    unsafe extern "C" fn(*mut c_void, *const u8, usize, u64, *mut u64, *mut u8) -> i32;
type FnCallFinish = unsafe extern "C" fn(*mut c_void, *mut i32, *mut u8) -> i32;

fn resolve_wtime_aot(squid_root: &Path) -> PathBuf {
    if let Ok(explicit) = std::env::var("WTIME_AOT_BIN") {
        if !explicit.is_empty() {
            return PathBuf::from(explicit);
        }
    }
    if let Some(parent) = squid_root.parent() {
        let sibling = parent.join("wtime/tools/wtime-aot/target/release/wtime-aot");
        if sibling.is_file() {
            return sibling;
        }
    }
    if let Some(home) = std::env::var_os("HOME") {
        let local = PathBuf::from(home).join(".local/bin/wtime-aot");
        if local.is_file() {
            return local;
        }
    }
    PathBuf::from("wtime-aot")
}

unsafe fn load_sym<T>(dl: *mut c_void, name: &str) -> T {
    let cname = CString::new(name).expect("symbol name");
    let ptr = unsafe { libc::dlsym(dl, cname.as_ptr()) };
    assert!(!ptr.is_null(), "missing wtime-aot symbol {name}");
    unsafe { std::mem::transmute_copy(&ptr) }
}

struct WtimeAotModule {
    dl: *mut c_void,
    trap_message: FnTrapMessage,
    new_fn: FnNew,
    drop_fn: FnDrop,
    call_export: FnCallExport,
    call_finish: FnCallFinish,
}

// Each `blot_aot_new` call allocates an independent guest instance + linear memory.
unsafe impl Send for WtimeAotModule {}
unsafe impl Sync for WtimeAotModule {}

impl WtimeAotModule {
    fn compile_and_load(wtime_aot: &Path, wasm_path: &Path, so_path: &Path) -> (Self, f64) {
        let t0 = Instant::now();
        let status = Command::new(wtime_aot)
            .args([
                "--backend",
                "x64",
                "--target-cpu",
                "native",
                "--guard-pages",
                "--blot-cdylib",
                wasm_path.to_str().unwrap(),
                "-o",
                so_path.to_str().unwrap(),
            ])
            .status()
            .unwrap_or_else(|e| panic!("failed to run {}: {e}", wtime_aot.display()));
        assert!(
            status.success(),
            "wtime-aot failed compiling {}",
            wasm_path.display()
        );
        let compile_ms = t0.elapsed().as_secs_f64() * 1000.0;

        let c_so = CString::new(so_path.to_str().unwrap()).expect("so path");
        let dl = unsafe { libc::dlopen(c_so.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        if dl.is_null() {
            let err = unsafe {
                let p = libc::dlerror();
                if p.is_null() {
                    "unknown dlopen error".to_string()
                } else {
                    std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
                }
            };
            panic!("dlopen({}) failed: {err}", so_path.display());
        }

        let module = unsafe {
            Self {
                dl,
                trap_message: load_sym(dl, "blot_aot_trap_message"),
                new_fn: load_sym(dl, "blot_aot_new"),
                drop_fn: load_sym(dl, "blot_aot_drop"),
                call_export: load_sym(dl, "blot_aot_call_export"),
                call_finish: load_sym(dl, "blot_aot_call_finish_invocation"),
            }
        };
        (module, compile_ms)
    }

    fn trap_text(&self, code: u8) -> String {
        let mut ptr: *const u8 = std::ptr::null();
        let mut len: usize = 0;
        let rc = unsafe { (self.trap_message)(code, &mut ptr, &mut len) };
        if rc == 0 && !ptr.is_null() && len > 0 {
            let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
            String::from_utf8_lossy(bytes).into_owned()
        } else {
            format!("trap code {code}")
        }
    }

    fn instantiate(&self) -> WtimeAotGuest<'_> {
        let mut trap: u8 = 0;
        let handle = unsafe { (self.new_fn)(std::ptr::null_mut(), std::ptr::null(), 0, &mut trap) };
        assert!(
            !handle.is_null(),
            "blot_aot_new failed: {}",
            self.trap_text(trap)
        );
        WtimeAotGuest {
            module: self,
            handle,
        }
    }
}

impl Drop for WtimeAotModule {
    fn drop(&mut self) {
        if !self.dl.is_null() {
            unsafe {
                libc::dlclose(self.dl);
            }
        }
    }
}

struct WtimeAotGuest<'a> {
    module: &'a WtimeAotModule,
    handle: *mut c_void,
}

unsafe impl<'a> Send for WtimeAotGuest<'a> {}

impl<'a> WtimeAotGuest<'a> {
    fn call_raw(&mut self, name: &str, arg: u32) -> u32 {
        let mut res: u64 = 0;
        let mut trap: u8 = 0;
        let rc = unsafe {
            (self.module.call_export)(
                self.handle,
                name.as_ptr(),
                name.len(),
                arg as u64,
                &mut res,
                &mut trap,
            )
        };
        assert_eq!(
            rc,
            0,
            "call {name}({arg}) failed (rc={rc}): {}",
            self.module.trap_text(trap)
        );
        res as u32
    }

    fn call_u32(&mut self, name: &str, arg: u32) -> u32 {
        let res = self.call_raw(name, arg);
        let mut fin_res: i32 = 0;
        let mut trap: u8 = 0;
        let rc = unsafe { (self.module.call_finish)(self.handle, &mut fin_res, &mut trap) };
        assert!(
            rc == 0 || rc == 3,
            "finish_invocation after {name} failed (rc={rc}): {}",
            self.module.trap_text(trap)
        );
        res
    }

    fn call_proc_init(&mut self, proc_name: &str, arg: u32) {
        let name = format!("squid:proc_init:{proc_name}");
        let rc = self.call_raw(&name, arg) as i32;
        assert_eq!(rc, 0, "{name}({arg}) returned error status {rc}");
    }

    fn call_proc_step(&mut self, proc_name: &str, cmd: u32) -> u32 {
        let name = format!("squid:proc_step:{proc_name}");
        self.call_raw(&name, cmd)
    }
}

impl<'a> Drop for WtimeAotGuest<'a> {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                (self.module.drop_fn)(self.handle);
            }
        }
    }
}

fn build_bevy_world(count: u32) -> (World, Vec<Entity>) {
    let mut world = World::new();
    let mut entities = Vec::with_capacity(count as usize);
    for i in 0..count {
        let fp = (i & 1023) as f32;
        let fv = ((i & 63) + 1) as f32;
        let pos = Pos {
            x: fp * 0.25,
            y: fp * 0.5,
            z: fp * 0.125,
        };
        let vel = Vel {
            vx: fv * 0.01,
            vy: fv * 0.02,
            vz: fv * 0.005,
        };
        let e = match (i % 10 == 0, i % 20 == 0) {
            (true, true) => world.spawn((pos, vel, Active, Frozen)).id(),
            (true, false) => world.spawn((pos, vel, Active)).id(),
            (false, true) => world.spawn((pos, vel, Frozen)).id(),
            (false, false) => world.spawn((pos, vel)).id(),
        };
        entities.push(e);
    }
    (world, entities)
}

fn bevy_checksum_pos(world: &mut World) -> u32 {
    let mut q = world.query::<&Pos>();
    let mut sum = 0u32;
    for p in q.iter(world) {
        sum = sum.wrapping_add(((p.x + p.y + p.z) * 16.0) as u32);
    }
    sum
}

fn bench_compile_ms(mut make_cmd: impl FnMut() -> Command, warmups: usize, samples: usize) -> f64 {
    for _ in 0..warmups {
        let st = make_cmd().status().expect("spawn compiler");
        assert!(st.success(), "compile warmup failed");
    }
    let mut times = Vec::with_capacity(samples);
    for _ in 0..samples {
        let t0 = Instant::now();
        let st = make_cmd().status().expect("spawn compiler");
        assert!(st.success(), "compile sample failed");
        times.push(t0.elapsed().as_secs_f64() * 1000.0);
    }
    median(times)
}

fn git_short_rev(repo: &Path) -> String {
    Command::new("git")
        .args(["-C", repo.to_str().unwrap(), "rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

fn main() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let squid_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("squid repository root");
    let workspace_parent = squid_root.parent().expect("workspace parent");
    let ink_lib = workspace_parent.join("ink/lib");
    let ink_alias = format!("ink/={}", ink_lib.display());
    let squidc = squid_root.join("compiler-goose/build/squidc-goose");
    let wtime_aot = resolve_wtime_aot(squid_root);
    let squid_kernels_src = squid_root.join("benchmarks/comparison/squid_kernels.sq");
    let ink_ecs_src = squid_root.join("benchmarks/comparison/ink_ecs_bench.sq");
    let rust_kernels_src = squid_root.join("benchmarks/comparison/rust_kernels.rs");
    let squid_kernels_wasm = Path::new("/tmp/squid_kernels.wasm");
    let rust_kernels_wasm = Path::new("/tmp/rust_kernels.wasm");
    let ink_ecs_wasm = Path::new("/tmp/ink_ecs_bench.wasm");
    let squid_kernels_so = Path::new("/tmp/squid_kernels_wtime.so");
    let rust_kernels_so = Path::new("/tmp/rust_kernels_wtime.so");
    let ink_ecs_so = Path::new("/tmp/ink_ecs_bench_wtime.so");

    // 1. Compile speed comparison (cold single-file 6-kernel suite + Ink ECS app vs rustc -O3).
    let squid_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new(&squidc);
            c.args([
                "build-project",
                squid_kernels_src.to_str().unwrap(),
                squid_kernels_wasm.to_str().unwrap(),
                "--std-root",
                squid_root.join("std").to_str().unwrap(),
                "--prelude",
                squid_root.join("std/prelude.sq").to_str().unwrap(),
            ])
            .stdout(std::process::Stdio::null());
            c
        },
        2,
        9,
    );
    let ink_ecs_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new(&squidc);
            c.args([
                "build-project",
                ink_ecs_src.to_str().unwrap(),
                ink_ecs_wasm.to_str().unwrap(),
                "--std-root",
                squid_root.join("std").to_str().unwrap(),
                "--prelude",
                squid_root.join("std/prelude.sq").to_str().unwrap(),
                "--alias",
                &ink_alias,
            ])
            .stdout(std::process::Stdio::null());
            c
        },
        2,
        9,
    );
    let rust_wasm_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new("rustc");
            c.args([
                "--edition=2024",
                "--crate-type=cdylib",
                "--target=wasm32-unknown-unknown",
                "-C",
                "opt-level=3",
                "-C",
                "target-feature=+simd128",
                "-C",
                "panic=abort",
                rust_kernels_src.to_str().unwrap(),
                "-o",
                rust_kernels_wasm.to_str().unwrap(),
            ]);
            c
        },
        2,
        9,
    );
    let rust_native_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new("rustc");
            c.args([
                "--edition=2024",
                "--crate-type=rlib",
                "-C",
                "opt-level=3",
                rust_kernels_src.to_str().unwrap(),
                "-o",
                "/tmp/librust_kernels.rlib",
            ]);
            c
        },
        2,
        9,
    );

    let (squid_mod, blot_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, squid_kernels_wasm, squid_kernels_so);
    let (rust_wasm_mod, rust_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, rust_kernels_wasm, rust_kernels_so);
    let (ink_ecs_mod, ink_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, ink_ecs_wasm, ink_ecs_so);

    let mut squid_guest = squid_mod.instantiate();
    let mut rust_wasm_guest = rust_wasm_mod.instantiate();

    // 2. Language kernels: Squid (wtime-aot x64) vs Rust -O3 (wasm32 wtime-aot x64) vs Rust -O3 (native x86_64).
    let seed = 42u32;
    let kernel_specs: Vec<(&str, extern "C" fn(u32) -> u32)> = vec![
        ("lcg_recurrence", rust_kernels::lcg_recurrence),
        ("prime_sieve", rust_kernels::prime_sieve),
        ("matmul_64", rust_kernels::matmul_64),
        ("mandelbrot_f32", rust_kernels::mandelbrot_f32),
        ("particle_spark_simd", rust_kernels::particle_spark_simd),
        ("merge_sort", rust_kernels::merge_sort),
    ];

    let mut kernel_rows = Vec::new();
    for (name, native_fn) in kernel_specs {
        let (squid_ms, squid_chk) = time_ms(3, 15, || squid_guest.call_u32(name, seed));
        let (rust_wasm_ms, rwasm_chk) = time_ms(3, 15, || rust_wasm_guest.call_u32(name, seed));
        let (rust_native_ms, rnat_chk) = time_ms(3, 15, || native_fn(black_box(seed)));
        let exact_match = squid_chk == rwasm_chk && squid_chk == rnat_chk;
        let close_match = squid_chk.abs_diff(rwasm_chk) <= 2 && squid_chk.abs_diff(rnat_chk) <= 2;
        assert!(
            close_match,
            "checksum mismatch for {name}: squid={squid_chk}, rust_wasm={rwasm_chk}, rust_native={rnat_chk}"
        );
        kernel_rows.push(serde_json::json!({
            "name": name,
            "squid_wtime_ms": squid_ms,
            "rust_wtime_ms": rust_wasm_ms,
            "rust_native_ms": rust_native_ms,
            "squid_vs_rust_wasm": squid_ms / rust_wasm_ms,
            "squid_vs_rust_native": squid_ms / rust_native_ms,
            "checksum_exact": exact_match,
            "checksum_squid": squid_chk,
            "checksum_rust_native": rnat_chk,
        }));
    }

    // 3. Ink ECS (Squid -> wtime-aot x64) vs Bevy ECS 0.20.1 (native Rust -O3).
    let n_entities = 10_000u32;
    let mut ecs_rows = Vec::new();

    // 3a. Dense iteration (10,000 entities x 100 ticks: Pos += Vel)
    let (ink_dense_direct_ms, ink_dense_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("ink_world", n_entities);
        let chk1 = g.call_proc_step("ink_world", 1);
        let (ms, _) = time_ms(2, 15, || g.call_proc_step("ink_world", 1));
        (ms, chk1)
    };
    let (ink_dense_query_ms, ink_query_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("ink_world", n_entities);
        let chk1 = g.call_proc_step("ink_world", 2);
        let (ms, _) = time_ms(2, 15, || g.call_proc_step("ink_world", 2));
        (ms, chk1)
    };
    let (ink_soa_spark_ms, ink_soa_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("soa_world", n_entities);
        let chk1 = g.call_proc_step("soa_world", 0);
        let (ms, _) = time_ms(2, 15, || g.call_proc_step("soa_world", 0));
        (ms, chk1)
    };
    let (bevy_dense_ms, bevy_dense_chk) = {
        let (mut world, _) = build_bevy_world(n_entities);
        let mut q = world.query::<(&mut Pos, &Vel)>();
        let mut run_100 = |w: &mut World| -> u32 {
            for _ in 0..100 {
                for (mut p, v) in q.iter_mut(w) {
                    p.x += v.vx;
                    p.y += v.vy;
                    p.z += v.vz;
                }
            }
            bevy_checksum_pos(w)
        };
        let chk1 = run_100(&mut world);
        let (ms, _) = time_ms(2, 15, || run_100(&mut world));
        (ms, chk1)
    };
    assert_eq!(
        ink_dense_chk, bevy_dense_chk,
        "dense checksum mismatch: ink={ink_dense_chk} query={ink_query_chk} soa={ink_soa_chk} bevy={bevy_dense_chk}"
    );
    assert_eq!(ink_dense_chk, ink_query_chk);
    assert_eq!(ink_dense_chk, ink_soa_chk);

    ecs_rows.push(serde_json::json!({
        "name": "dense_iter_10k_x100",
        "ink_pool_direct_ms": ink_dense_direct_ms,
        "ink_cached_query_ms": ink_dense_query_ms,
        "ink_soa_spark_simd_ms": ink_soa_spark_ms,
        "bevy_native_ms": bevy_dense_ms,
        "checksum_ink": ink_dense_chk,
        "checksum_bevy": bevy_dense_chk,
    }));

    // 3b. Sparse filtered iteration (With Active, Without Frozen => 500 of 10,000 entities x 100 ticks)
    let (ink_sparse_ms, ink_sparse_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("ink_world", n_entities);
        let chk1 = g.call_proc_step("ink_world", 3);
        let (ms, _) = time_ms(2, 15, || g.call_proc_step("ink_world", 3));
        (ms, chk1)
    };
    let (bevy_sparse_ms, bevy_sparse_chk) = {
        let (mut world, _) = build_bevy_world(n_entities);
        let mut q = world.query_filtered::<(&mut Pos, &Vel), (With<Active>, Without<Frozen>)>();
        let mut run_100 = |w: &mut World| -> u32 {
            for _ in 0..100 {
                for (mut p, v) in q.iter_mut(w) {
                    p.x += v.vx;
                    p.y += v.vy;
                    p.z += v.vz;
                }
            }
            bevy_checksum_pos(w)
        };
        let chk1 = run_100(&mut world);
        let (ms, _) = time_ms(2, 15, || run_100(&mut world));
        (ms, chk1)
    };
    assert_eq!(
        ink_sparse_chk, bevy_sparse_chk,
        "sparse checksum mismatch: ink={ink_sparse_chk} bevy={bevy_sparse_chk}"
    );
    ecs_rows.push(serde_json::json!({
        "name": "sparse_filtered_iter_500_of_10k_x100",
        "ink_cached_query_ms": ink_sparse_ms,
        "bevy_native_ms": bevy_sparse_ms,
        "checksum_ink": ink_sparse_chk,
        "checksum_bevy": bevy_sparse_chk,
    }));

    // 3c. Batch spawn 10,000 entities (Pos + Vel + 10% Active)
    let (ink_spawn_ms, ink_spawn_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        time_ms(3, 15, || g.call_u32("ecs_spawn_batch", n_entities))
    };
    let (bevy_spawn_ms, bevy_spawn_chk) = time_ms(3, 15, || {
        let mut world = World::new();
        let batch_active: Vec<(Pos, Vel, Active)> = (0..n_entities)
            .filter(|i| i % 10 == 0)
            .map(|i| {
                let fp = (i & 1023) as f32;
                let fv = ((i & 63) + 1) as f32;
                (
                    Pos { x: fp * 0.25, y: fp * 0.5, z: fp * 0.125 },
                    Vel { vx: fv * 0.01, vy: fv * 0.02, vz: fv * 0.005 },
                    Active,
                )
            })
            .collect();
        let batch_plain: Vec<(Pos, Vel)> = (0..n_entities)
            .filter(|i| i % 10 != 0)
            .map(|i| {
                let fp = (i & 1023) as f32;
                let fv = ((i & 63) + 1) as f32;
                (
                    Pos { x: fp * 0.25, y: fp * 0.5, z: fp * 0.125 },
                    Vel { vx: fv * 0.01, vy: fv * 0.02, vz: fv * 0.005 },
                )
            })
            .collect();
        world.spawn_batch(batch_active);
        world.spawn_batch(batch_plain);
        bevy_checksum_pos(&mut world)
    });
    assert_eq!(
        ink_spawn_chk, bevy_spawn_chk,
        "spawn checksum mismatch: ink={ink_spawn_chk} bevy={bevy_spawn_chk}"
    );
    ecs_rows.push(serde_json::json!({
        "name": "batch_spawn_10k",
        "ink_ms": ink_spawn_ms,
        "bevy_native_ms": bevy_spawn_ms,
        "checksum_ink": ink_spawn_chk,
        "checksum_bevy": bevy_spawn_chk,
    }));

    // 3d. Structural churn: 2,000 balanced insert/remove Active tag ops on 10,000-entity world
    let (ink_churn_ms, ink_churn_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("ink_world", n_entities);
        time_ms(3, 15, || g.call_proc_step("ink_world", 4))
    };
    let (bevy_churn_ms, bevy_churn_chk) = {
        let (mut world, entities) = build_bevy_world(n_entities);
        let mut ops: u32 = 0;
        time_ms(3, 15, || {
            for step in 0..500usize {
                world.entity_mut(entities[step * 10]).remove::<Active>();
            }
            for step in 0..500usize {
                world.entity_mut(entities[step * 10 + 5]).insert(Active);
            }
            for step in 0..500usize {
                world.entity_mut(entities[step * 10 + 5]).remove::<Active>();
            }
            for step in 0..500usize {
                world.entity_mut(entities[step * 10]).insert(Active);
            }
            ops = ops.wrapping_add(2000);
            ops
        })
    };
    ecs_rows.push(serde_json::json!({
        "name": "structural_churn_2000_tag_ops",
        "ink_ms": ink_churn_ms,
        "bevy_native_ms": bevy_churn_ms,
        "checksum_ink": ink_churn_chk,
        "checksum_bevy": bevy_churn_chk,
    }));

    // 3e. Full world snapshot / checkpoint copy (10,000 entities: Pos + Vel + Active + Frozen)
    let (ink_snap_ms, ink_snap_chk) = {
        let mut g = ink_ecs_mod.instantiate();
        g.call_proc_init("ink_world", n_entities);
        time_ms(3, 15, || g.call_proc_step("ink_world", 5))
    };
    let (bevy_snap_world_ms, bevy_snap_chk) = {
        let (mut world, _) = build_bevy_world(n_entities);
        let mut q = world.query::<(&Pos, &Vel, Option<&Active>, Option<&Frozen>)>();
        time_ms(3, 15, || {
            let mut snap = World::new();
            let mut a = Vec::new();
            let mut b = Vec::new();
            let mut c = Vec::new();
            let mut d = Vec::new();
            for (&p, &v, act, frz) in q.iter(&world) {
                match (act.is_some(), frz.is_some()) {
                    (true, true) => a.push((p, v, Active, Frozen)),
                    (true, false) => b.push((p, v, Active)),
                    (false, true) => c.push((p, v, Frozen)),
                    (false, false) => d.push((p, v)),
                }
            }
            snap.spawn_batch(a);
            snap.spawn_batch(b);
            snap.spawn_batch(c);
            snap.spawn_batch(d);
            snap.entities().len()
        })
    };
    ecs_rows.push(serde_json::json!({
        "name": "world_snapshot_copy_10k",
        "ink_ms": ink_snap_ms,
        "bevy_native_world_rebuild_ms": bevy_snap_world_ms,
        "checksum_ink": ink_snap_chk,
        "checksum_bevy": bevy_snap_chk,
    }));

    // 4. Wasm 3.0 opt-in (--wasm3: --tail-calls + --relaxed-simd) on wtime-aot 0.1.7,
    //    generalized AoS Vec2/Vec4 record auto-SIMD, multi-core isolated-guest scaling,
    //    and persistent #process throughput.
    let squid_kernels_w3_wasm = Path::new("/tmp/squid_kernels_w3.wasm");
    let squid_kernels_w3_so = Path::new("/tmp/squid_kernels_w3_wtime.so");
    let st = Command::new(&squidc)
        .args([
            "build-project",
            squid_kernels_src.to_str().unwrap(),
            squid_kernels_w3_wasm.to_str().unwrap(),
            "--std-root",
            squid_root.join("std").to_str().unwrap(),
            "--prelude",
            squid_root.join("std/prelude.sq").to_str().unwrap(),
            "--wasm3",
        ])
        .stdout(std::process::Stdio::null())
        .status()
        .expect("compile squid_kernels --wasm3");
    assert!(st.success(), "squid_kernels --wasm3 compile failed");
    let (squid_w3_mod, squid_w3_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, squid_kernels_w3_wasm, squid_kernels_w3_so);
    let mut squid_w3_guest = squid_w3_mod.instantiate();
    let mut wasm3_kernel_rows = Vec::new();
    for (idx, name) in [
        "lcg_recurrence",
        "prime_sieve",
        "matmul_64",
        "mandelbrot_f32",
        "particle_spark_simd",
        "merge_sort",
    ]
    .iter()
    .enumerate()
    {
        let (w3_ms, w3_chk) = time_ms(3, 15, || squid_w3_guest.call_u32(name, seed));
        let def_ms = kernel_rows[idx]["squid_wtime_ms"].as_f64().unwrap();
        let def_chk = kernel_rows[idx]["checksum_squid"].as_u64().unwrap() as u32;
        wasm3_kernel_rows.push(serde_json::json!({
            "name": name,
            "default_wtime_ms": def_ms,
            "wasm3_wtime_ms": w3_ms,
            "speedup_vs_default": def_ms / w3_ms,
            "checksum_default": def_chk,
            "checksum_wasm3": w3_chk,
        }));
    }

    // 4b. Generalized AoS #[Vec4] & #[Vec2] record auto-SIMD + multi-core scaling + #process.
    let mc_src = squid_root.join("benchmarks/comparison/multicore_aos_bench.sq");
    let mc_def_wasm = Path::new("/tmp/multicore_aos_def.wasm");
    let mc_w3_wasm = Path::new("/tmp/multicore_aos_w3.wasm");
    let mc_def_so = Path::new("/tmp/multicore_aos_def_wtime.so");
    let mc_w3_so = Path::new("/tmp/multicore_aos_w3_wtime.so");
    for (out_wasm, extra) in [(mc_def_wasm, false), (mc_w3_wasm, true)] {
        let mut cmd = Command::new(&squidc);
        cmd.args([
            "build-project",
            mc_src.to_str().unwrap(),
            out_wasm.to_str().unwrap(),
            "--std-root",
            squid_root.join("std").to_str().unwrap(),
            "--prelude",
            squid_root.join("std/prelude.sq").to_str().unwrap(),
        ]);
        if extra {
            cmd.arg("--wasm3");
        }
        let st = cmd
            .stdout(std::process::Stdio::null())
            .status()
            .expect("compile multicore_aos_bench");
        assert!(st.success(), "multicore_aos_bench compile failed");
    }
    let (mc_def_mod, _) = WtimeAotModule::compile_and_load(&wtime_aot, mc_def_wasm, mc_def_so);
    let (mc_w3_mod, _) = WtimeAotModule::compile_and_load(&wtime_aot, mc_w3_wasm, mc_w3_so);
    let mut mc_def_guest = mc_def_mod.instantiate();
    let mut mc_w3_guest = mc_w3_mod.instantiate();

    #[derive(Clone, Copy)]
    struct Vec4 { x: f32, y: f32, z: f32, w: f32 }
    #[derive(Clone, Copy)]
    struct Vec2 { x: f32, y: f32 }

    let native_aos_vec4 = |s: u32| -> u32 {
        let n = 65536usize;
        let base = (s & 15) as f32;
        let mut pos = vec![Vec4 { x: 0.0, y: 0.0, z: 0.0, w: 0.0 }; n];
        let mut vel = vec![Vec4 { x: 0.0, y: 0.0, z: 0.0, w: 0.0 }; n];
        for i in 0..n {
            let fi = (i & 1023) as f32;
            pos[i] = Vec4 {
                x: base + fi * 0.01,
                y: base + fi * 0.02,
                z: base + fi * 0.03,
                w: 1.0 + fi * 0.001,
            };
            vel[i] = Vec4 {
                x: 0.5 + fi * 0.002,
                y: -0.25 + fi * 0.001,
                z: 0.125 - fi * 0.0005,
                w: 0.01,
            };
        }
        let dt = 0.016f32;
        for _ in 0..32 {
            for i in 0..n {
                pos[i].x += vel[i].x * dt;
                pos[i].y += vel[i].y * dt;
                pos[i].z += vel[i].z * dt;
                pos[i].w += vel[i].w * dt;
            }
        }
        let mut sum = 0.0f32;
        for p in &pos {
            sum = (((sum + p.x) + p.y) + p.z) + p.w;
        }
        (sum * 4.0) as u32
    };
    let native_aos_vec2 = |s: u32| -> u32 {
        let n = 65536usize;
        let base = (s & 15) as f32;
        let mut pos = vec![Vec2 { x: 0.0, y: 0.0 }; n];
        let mut vel = vec![Vec2 { x: 0.0, y: 0.0 }; n];
        for i in 0..n {
            let fi = (i & 1023) as f32;
            pos[i] = Vec2 { x: base + fi * 0.01, y: base + fi * 0.02 };
            vel[i] = Vec2 { x: 0.5 + fi * 0.002, y: -0.25 + fi * 0.001 };
        }
        let dt = 0.016f32;
        for _ in 0..32 {
            for i in 0..n {
                pos[i].x += vel[i].x * dt;
                pos[i].y += vel[i].y * dt;
            }
        }
        let mut sum = 0.0f32;
        for p in &pos {
            sum = (sum + p.x) + p.y;
        }
        (sum * 8.0) as u32
    };

    let (v4_def_ms, v4_def_chk) = time_ms(3, 15, || mc_def_guest.call_u32("aos_vec4_euler", seed));
    let (v4_w3_ms, v4_w3_chk) = time_ms(3, 15, || mc_w3_guest.call_u32("aos_vec4_euler", seed));
    let (v4_nat_ms, v4_nat_chk) = time_ms(3, 15, || native_aos_vec4(black_box(seed)));
    assert!(v4_def_chk.abs_diff(v4_nat_chk) <= 2, "aos_vec4 mismatch: squid={v4_def_chk} nat={v4_nat_chk}");

    let (v2_def_ms, v2_def_chk) = time_ms(3, 15, || mc_def_guest.call_u32("aos_vec2_euler", seed));
    let (v2_w3_ms, v2_w3_chk) = time_ms(3, 15, || mc_w3_guest.call_u32("aos_vec2_euler", seed));
    let (v2_nat_ms, v2_nat_chk) = time_ms(3, 15, || native_aos_vec2(black_box(seed)));
    assert!(v2_def_chk.abs_diff(v2_nat_chk) <= 2, "aos_vec2 mismatch: squid={v2_def_chk} nat={v2_nat_chk}");

    let aos_rows = vec![
        serde_json::json!({
            "name": "aos_vec4_euler_65k_x32",
            "squid_wtime_ms": v4_def_ms,
            "squid_wasm3_wtime_ms": v4_w3_ms,
            "rust_native_ms": v4_nat_ms,
            "squid_vs_rust_native": v4_def_ms / v4_nat_ms,
            "wasm3_vs_rust_native": v4_w3_ms / v4_nat_ms,
            "checksum_squid": v4_def_chk,
            "checksum_wasm3": v4_w3_chk,
            "checksum_rust_native": v4_nat_chk,
        }),
        serde_json::json!({
            "name": "aos_vec2_euler_65k_x32",
            "squid_wtime_ms": v2_def_ms,
            "squid_wasm3_wtime_ms": v2_w3_ms,
            "rust_native_ms": v2_nat_ms,
            "squid_vs_rust_native": v2_def_ms / v2_nat_ms,
            "wasm3_vs_rust_native": v2_w3_ms / v2_nat_ms,
            "checksum_squid": v2_def_chk,
            "checksum_wasm3": v2_w3_chk,
            "checksum_rust_native": v2_nat_chk,
        }),
    ];

    // 4c. Multi-core isolated-guest scaling (8 x 256x256 Mandelbrot tiles across 1, 2, 4, 8 threads).
    let mut multicore_rows = Vec::new();
    let mut squid_1t_ms = 0.0f64;
    let mut squid_mc_chk = 0u32;
    for threads in [1usize, 2, 4, 8] {
        let mut guests: Vec<WtimeAotGuest<'_>> = (0..threads).map(|_| mc_def_mod.instantiate()).collect();
        let tiles_per_thread = 8 / threads;
        let (squid_ms, bchk) = time_ms(2, 11, || {
            std::thread::scope(|s| {
                let mut handles = Vec::with_capacity(threads);
                for (tid, g) in guests.iter_mut().enumerate() {
                    let start = (tid * tiles_per_thread) as u32;
                    let end = start + tiles_per_thread as u32;
                    handles.push(s.spawn(move || {
                        let mut acc = 0u32;
                        for tile in start..end {
                            acc = acc.wrapping_add(g.call_u32("mandelbrot_tile", tile));
                        }
                        acc
                    }));
                }
                handles.into_iter().fold(0u32, |a, h| a.wrapping_add(h.join().unwrap()))
            })
        });
        let (nat_ms, nchk) = time_ms(2, 11, || {
            std::thread::scope(|s| {
                let mut handles = Vec::with_capacity(threads);
                for tid in 0..threads {
                    let start = (tid * tiles_per_thread) as u32;
                    let end = start + tiles_per_thread as u32;
                    handles.push(s.spawn(move || {
                        let mut acc = 0u32;
                        for tile in start..end {
                            acc = acc.wrapping_add(rust_kernels::mandelbrot_f32(black_box(tile)));
                        }
                        acc
                    }));
                }
                handles.into_iter().fold(0u32, |a, h| a.wrapping_add(h.join().unwrap()))
            })
        });
        assert_eq!(bchk, nchk, "multicore checksum mismatch at threads={threads}: squid={bchk} nat={nchk}");
        if threads == 1 {
            squid_1t_ms = squid_ms;
            squid_mc_chk = bchk;
        } else {
            assert_eq!(bchk, squid_mc_chk);
        }
        multicore_rows.push(serde_json::json!({
            "threads": threads,
            "squid_wtime_ms": squid_ms,
            "squid_scaling": squid_1t_ms / squid_ms,
            "rust_native_ms": nat_ms,
            "squid_vs_rust_native": squid_ms / nat_ms,
            "checksum": bchk,
        }));
    }

    // 4d. Persistent ABI 8 `#process` zero-alloc step throughput on wtime-aot 0.1.7.
    let (proc_noop_us, proc_phys_us) = {
        let mut g = mc_def_mod.instantiate();
        g.call_proc_init("particle_sim", 4096);
        let (noop_batch_ms, _) = time_ms(2, 15, || {
            let mut last = 0u32;
            for _ in 0..10_000 {
                last = g.call_proc_step("particle_sim", 0);
            }
            last
        });
        let (phys_batch_ms, _) = time_ms(2, 15, || {
            let mut last = 0u32;
            for _ in 0..200 {
                last = g.call_proc_step("particle_sim", 1);
            }
            last
        });
        ((noop_batch_ms * 1000.0) / 10_000.0, (phys_batch_ms * 1000.0) / 200.0)
    };

    let squid_commit = git_short_rev(squid_root);
    let wtime_dir = workspace_parent.join("wtime");
    let wtime_commit = git_short_rev(&wtime_dir);
    let wtime_version = std::fs::read_to_string(wtime_dir.join("tools/wtime-aot/Cargo.toml"))
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.trim_start().starts_with("version = "))
                .and_then(|l| l.split('"').nth(1))
                .map(|v| v.to_string())
        })
        .unwrap_or_else(|| "0.1.7".to_string());
    let x64_profile = {
        #[cfg(target_arch = "x86_64")]
        {
            if std::arch::is_x86_feature_detected!("avx512f")
                && std::arch::is_x86_feature_detected!("avx512vl")
                && std::arch::is_x86_feature_detected!("avx512bw")
                && std::arch::is_x86_feature_detected!("avx512dq")
            {
                "x64-v4"
            } else if std::arch::is_x86_feature_detected!("avx2")
                && std::arch::is_x86_feature_detected!("bmi2")
                && std::arch::is_x86_feature_detected!("fma")
            {
                "x64-v3"
            } else {
                "x64-v2"
            }
        }
        #[cfg(not(target_arch = "x86_64"))]
        {
            "native"
        }
    };
    let rustc_version = Command::new("rustc")
        .arg("--version")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.split_whitespace().nth(1).map(|v| v.to_string()))
        .unwrap_or_else(|| "unknown".to_string());
    let report = serde_json::json!({
        "hardware": "AMD Ryzen 7 7800X3D (8-core / 16-thread)",
        "toolchains": {
            "squid_commit": squid_commit,
            "wtime_aot": format!("{wtime_version} ({x64_profile}, {wtime_commit})"),
            "bevy_ecs": "0.20.1",
            "rustc": rustc_version,
        },
        "compile_speed_ms": {
            "squid_6_kernels_ms": squid_compile_ms,
            "squid_ink_ecs_app_ms": ink_ecs_compile_ms,
            "rust_wasm32_opt3_ms": rust_wasm_compile_ms,
            "rust_native_opt3_ms": rust_native_compile_ms,
            "wtime_aot_squid_kernels_ms": blot_aot_ms,
            "wtime_aot_squid_kernels_wasm3_ms": squid_w3_aot_ms,
            "wtime_aot_ink_ecs_ms": ink_aot_ms,
            "wtime_aot_rust_kernels_ms": rust_aot_ms,
            "squid_wasm_bytes": std::fs::metadata(squid_kernels_wasm).unwrap().len(),
            "squid_wasm3_bytes": std::fs::metadata(squid_kernels_w3_wasm).unwrap().len(),
            "rust_wasm_bytes": std::fs::metadata(rust_kernels_wasm).unwrap().len(),
            "ink_ecs_wasm_bytes": std::fs::metadata(ink_ecs_wasm).unwrap().len(),
        },
        "kernels": kernel_rows,
        "wasm3_kernels": wasm3_kernel_rows,
        "aos_record_simd": aos_rows,
        "multicore_wtime_mandelbrot_8_tiles": multicore_rows,
        "persistent_process_wtime_particle_sim_4096": {
            "noop_commit_us_per_step": proc_noop_us,
            "noop_steps_per_sec": 1_000_000.0 / proc_noop_us,
            "aos_vec4_physics_us_per_step": proc_phys_us,
        },
        "ecs": ecs_rows,
    });
    println!("{}", serde_json::to_string_pretty(&report).unwrap());
}
