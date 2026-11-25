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

fn resolve_wtime_aot(blot_root: &Path) -> PathBuf {
    if let Ok(explicit) = std::env::var("WTIME_AOT_BIN") {
        if !explicit.is_empty() {
            return PathBuf::from(explicit);
        }
    }
    if let Some(parent) = blot_root.parent() {
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

impl WtimeAotModule {
    fn compile_and_load(wtime_aot: &Path, wasm_path: &Path, so_path: &Path) -> (Self, f64) {
        let t0 = Instant::now();
        let status = Command::new(wtime_aot)
            .args([
                "--backend",
                "x64",
                "--target-cpu",
                "native",
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
        let name = format!("blot:proc_init:{proc_name}");
        let rc = self.call_raw(&name, arg) as i32;
        assert_eq!(rc, 0, "{name}({arg}) returned error status {rc}");
    }

    fn call_proc_step(&mut self, proc_name: &str, cmd: u32) -> u32 {
        let name = format!("blot:proc_step:{proc_name}");
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
    let blot_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("blot2 repository root");
    let workspace_parent = blot_root.parent().expect("workspace parent");
    let ink_lib = workspace_parent.join("ink/lib");
    let ink_alias = format!("ink/={}", ink_lib.display());
    let blotc = blot_root.join("compiler-goose/build/blotc-goose");
    let wtime_aot = resolve_wtime_aot(blot_root);
    let blot_kernels_src = blot_root.join("benchmarks/comparison/blot_kernels.blot");
    let ink_ecs_src = blot_root.join("benchmarks/comparison/ink_ecs_bench.blot");
    let rust_kernels_src = blot_root.join("benchmarks/comparison/rust_kernels.rs");
    let blot_kernels_wasm = Path::new("/tmp/blot_kernels.wasm");
    let rust_kernels_wasm = Path::new("/tmp/rust_kernels.wasm");
    let ink_ecs_wasm = Path::new("/tmp/ink_ecs_bench.wasm");
    let blot_kernels_so = Path::new("/tmp/blot_kernels_wtime.so");
    let rust_kernels_so = Path::new("/tmp/rust_kernels_wtime.so");
    let ink_ecs_so = Path::new("/tmp/ink_ecs_bench_wtime.so");

    // 1. Compile speed comparison (cold single-file 6-kernel suite + Ink ECS app vs rustc -O3).
    let blot_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new(&blotc);
            c.args([
                "build-project",
                blot_kernels_src.to_str().unwrap(),
                blot_kernels_wasm.to_str().unwrap(),
                "--std-root",
                blot_root.join("std").to_str().unwrap(),
                "--prelude",
                blot_root.join("std/prelude.blot").to_str().unwrap(),
            ])
            .stdout(std::process::Stdio::null());
            c
        },
        2,
        9,
    );
    let ink_ecs_compile_ms = bench_compile_ms(
        || {
            let mut c = Command::new(&blotc);
            c.args([
                "build-project",
                ink_ecs_src.to_str().unwrap(),
                ink_ecs_wasm.to_str().unwrap(),
                "--std-root",
                blot_root.join("std").to_str().unwrap(),
                "--prelude",
                blot_root.join("std/prelude.blot").to_str().unwrap(),
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

    let (blot_mod, blot_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, blot_kernels_wasm, blot_kernels_so);
    let (rust_wasm_mod, rust_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, rust_kernels_wasm, rust_kernels_so);
    let (ink_ecs_mod, ink_aot_ms) =
        WtimeAotModule::compile_and_load(&wtime_aot, ink_ecs_wasm, ink_ecs_so);

    let mut blot_guest = blot_mod.instantiate();
    let mut rust_wasm_guest = rust_wasm_mod.instantiate();

    // 2. Language kernels: Blot (wtime-aot x64) vs Rust -O3 (wasm32 wtime-aot x64) vs Rust -O3 (native x86_64).
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
        let (blot_ms, blot_chk) = time_ms(3, 15, || blot_guest.call_u32(name, seed));
        let (rust_wasm_ms, rwasm_chk) = time_ms(3, 15, || rust_wasm_guest.call_u32(name, seed));
        let (rust_native_ms, rnat_chk) = time_ms(3, 15, || native_fn(black_box(seed)));
        let exact_match = blot_chk == rwasm_chk && blot_chk == rnat_chk;
        let close_match = blot_chk.abs_diff(rwasm_chk) <= 2 && blot_chk.abs_diff(rnat_chk) <= 2;
        assert!(
            close_match,
            "checksum mismatch for {name}: blot={blot_chk}, rust_wasm={rwasm_chk}, rust_native={rnat_chk}"
        );
        kernel_rows.push(serde_json::json!({
            "name": name,
            "blot_wtime_ms": blot_ms,
            "rust_wtime_ms": rust_wasm_ms,
            "rust_native_ms": rust_native_ms,
            "blot_vs_rust_wasm": blot_ms / rust_wasm_ms,
            "blot_vs_rust_native": blot_ms / rust_native_ms,
            "checksum_exact": exact_match,
            "checksum_blot": blot_chk,
            "checksum_rust_native": rnat_chk,
        }));
    }

    // 3. Ink ECS (Blot -> wtime-aot x64) vs Bevy ECS 0.20.1 (native Rust -O3).
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

    let blot_commit = git_short_rev(blot_root);
    let wtime_commit = git_short_rev(&workspace_parent.join("wtime"));
    let report = serde_json::json!({
        "hardware": "AMD Ryzen 7 7800X3D (8-core / 16-thread)",
        "toolchains": {
            "blot_commit": blot_commit,
            "wtime_aot": format!("0.1.1 (x64-v3, {wtime_commit})"),
            "bevy_ecs": "0.20.1",
            "rustc": "1.96.0-nightly",
        },
        "compile_speed_ms": {
            "blot_6_kernels_ms": blot_compile_ms,
            "blot_ink_ecs_app_ms": ink_ecs_compile_ms,
            "rust_wasm32_opt3_ms": rust_wasm_compile_ms,
            "rust_native_opt3_ms": rust_native_compile_ms,
            "wtime_aot_blot_kernels_ms": blot_aot_ms,
            "wtime_aot_ink_ecs_ms": ink_aot_ms,
            "wtime_aot_rust_kernels_ms": rust_aot_ms,
            "blot_wasm_bytes": std::fs::metadata(blot_kernels_wasm).unwrap().len(),
            "rust_wasm_bytes": std::fs::metadata(rust_kernels_wasm).unwrap().len(),
            "ink_ecs_wasm_bytes": std::fs::metadata(ink_ecs_wasm).unwrap().len(),
        },
        "kernels": kernel_rows,
        "ecs": ecs_rows,
    });
    println!("{}", serde_json::to_string_pretty(&report).unwrap());
}
