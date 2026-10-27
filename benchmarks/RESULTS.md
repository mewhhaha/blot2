# Initial Goose K1 qualification and measurements

The K1 rewrite passes its frozen correctness gate. The measured synthetic builds and retained edits are below one second at the reported scales, but this candidate is **slower than the pinned legacy compiler on most paired compile workloads**. It also rebuilds unchanged retained projects more slowly than a fresh session. These regressions are part of the result, not excluded samples. This is not a migrated `gdev` measurement.

## Candidate and evidence

Implementation commit: `4d5fe60343d1916ec99baa452f2727c48a408f27` on `rewrite/goose-k1`. The final documentation/evidence commit does not change compiler inputs. Gate input manifest: `5fe240d4ac1b7c08ad609c2444e68cc2a7338e589de479401237fa8d80f6bce6`. Release executable SHA-256: `7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2`. The gate ran before the implementation commit and identified the same compiler/test/tool inputs by content hash.

The complete gate passed **91 native entries, 79 Deno integration tests and the pinned TextMate/Oniguruma editor checks**. It includes required-budget boundaries, canonical artifacts after producer destruction, all fired R01–R12 optimizer rules, actual Wasm validation/certificates, scalar preconditions, the copy bridge, transactional retained edits and corruption/receipt/collision controls. Allocation sweeps covered 343 construction boundaries, 302 decoder boundaries and 251 subsequent retained-revision boundaries; all injected retained failures preserved the previous output. The full-prefix particle test covers every initialized length 0–8, including failure after the final append, with exact release/live-backing checks.

See the [law ledger](../IMPLEMENTATION.md), [qualification record](results/k1-initial/qualification.json), [evidence manifest](results/k1-initial/manifest.json) and [raw sample/source/log archive](results/k1-initial/raw-evidence.tar.gz). The manifest hashes every archived input. Generated binaries/C/cache trees are omitted; their hashes remain in the records. A prior ASLR-dependent allocation-test failure is preserved separately in the archive; reservation-relative commit chunks fixed its unstable fault ordinals.

## Conditions and scope

Host: **AMD Ryzen 7 7800X3D 8-Core Processor**, 16 logical CPUs, 93.4 GiB RAM; `Linux-7.2.9-2-cachyos-x86_64-with-glibc2.44`. Compiler jobs ran sequentially with one internal worker. CPU affinity, frequency and filesystem caches were uncontrolled. Host metadata is recorded by the session/limits/iteration runs; the initial paired metadata omitted its CPU line.

Goose is pinned to `a108677d300cb0e8bbb842c35a353abe67a20c6c` (`v2026.3-120-ga108677`, runtime `fba599d313fe`), using Clang 23.1.1. Deno 2.9.7 / V8 15.0.245.2-rusty executes both languages’ Wasm. The verified Zig 0.17.0/LLVM release baseline is main `1e39b5d8a4268b9edf769c2813d5231abe1c963b`, executable SHA-256 `fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923`.

Paired samples alternate candidate/baseline order, five rounds per point. K1 uses its required baseline lowering (`--opt=off`); the old compiler uses its default pipeline with both worker counts explicitly set to one. Programs have equivalent tested outputs, while K1 performs additional proof/ownership/artifact checks. Each accepted Wasm sample is executed and checksummed. Phase attribution runs separately. All ranges below are observed minimum–maximum, not confidence intervals. No timing threshold or universal speedup is claimed.

## Fresh compilation

Milliseconds, median [minimum–maximum], five fresh processes per compiler and point. Scale is the generator parameter: diamonds emit four functions per unit, closures include local bodies, modules include imported and entry bodies, proofs use eight guarded increments per function, and domains contain distinct static arrays. “Fresh” does not mean cold OS caches.

| Family | Scale | K1 ms | Pinned baseline ms |
| --- | ---: | ---: | ---: |
| independent | 8 | 35.72 [24.54–113.43] | 2.81 [1.92–10.30] |
| independent | 32 | 9.50 [7.86–13.66] | 3.06 [2.89–26.47] |
| independent | 128 | 26.41 [16.89–73.24] | 5.92 [4.65–11.65] |
| calls | 8 | 7.11 [6.55–7.36] | 2.24 [1.99–3.34] |
| calls | 32 | 10.25 [9.23–22.66] | 3.45 [2.56–8.95] |
| calls | 128 | 26.30 [19.78–45.15] | 5.41 [5.11–28.20] |
| chains | 8 | 7.53 [7.11–27.09] | 2.49 [2.24–5.47] |
| chains | 32 | 11.71 [9.01–54.06] | 4.13 [3.31–12.59] |
| chains | 128 | rejected (5/5) | 9.44 [8.20–98.02] |
| diamonds | 8 | 18.04 [8.82–46.95] | 3.51 [2.74–8.57] |
| diamonds | 32 | 31.75 [24.14–101.61] | 7.38 [6.08–24.92] |
| diamonds | 128 | 101.83 [76.77–115.56] | 33.81 [17.64–109.46] |
| generics | 8 | 9.29 [6.90–22.82] | 2.98 [1.91–5.07] |
| generics | 32 | 13.93 [12.39–22.68] | 2.96 [2.55–88.69] |
| generics | 128 | 23.26 [21.84–40.50] | 6.26 [5.29–10.63] |
| closures | 8 | 8.37 [7.57–17.48] | 4.78 [3.45–55.88] |
| closures | 32 | 14.97 [11.32–30.97] | 4.63 [4.17–11.71] |
| closures | 128 | 59.04 [35.10–540.69] | 12.10 [9.99–19.06] |
| modules | 8 | 12.74 [7.39–20.15] | 2.42 [2.34–2.58] |
| modules | 32 | 12.63 [12.19–37.96] | 4.62 [4.10–42.21] |
| modules | 128 | 44.43 [36.39–492.31] | 16.48 [10.50–28.17] |
| proofs | 8 | 10.18 [9.32–13.83] | 3.31 [3.26–4.12] |
| proofs | 32 | 41.71 [31.81–95.48] | 7.31 [7.15–455.43] |
| proofs | 128 | 405.15 [307.85–850.95] | 22.44 [20.66–23.91] |
| domains | 8 | 13.60 [9.47–97.58] | 2.72 [2.40–2.78] |
| domains | 32 | 20.96 [20.21–25.01] | 3.68 [3.51–6.72] |
| domains | 128 | 114.45 [98.06–174.55] | 7.58 [6.86–8.85] |

The chain at 128 is rejected by K1 in all five timing runs and the attribution run: 128 source calls plus its scalar entry wrapper exceed the 128-depth envelope. The baseline accepts it. This is a documented language/resource boundary, not a timing sample. A separate paired **127-deep** control, preserving the original failures, passes:
K1 **20.97 [18.55–34.19] ms**, baseline **8.25 [7.99–9.11] ms**.

Large outliers remain visible: the 128-closure K1 build reached 540.69 ms and the proof case 850.95 ms. No scheduler, page-fault or hardware-counter trace established their individual cause; they have not been removed.

CPU time and peak child RSS at scale 128 (medians; rejected chain excluded):

| Family | K1 CPU ms | Baseline CPU ms | K1 RSS MiB | Baseline RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| independent | 17.42 | 5.19 | 12.79 | 12.84 |
| calls | 18.24 | 5.22 | 12.89 | 12.68 |
| diamonds | 80.07 | 20.67 | 12.64 | 14.30 |
| generics | 20.04 | 5.45 | 12.89 | 13.30 |
| closures | 36.17 | 10.88 | 12.69 | 15.11 |
| modules | 34.68 | 13.00 | 12.79 | 15.02 |
| proofs | 302.00 | 21.83 | 13.26 | 13.85 |
| domains | 84.97 | 7.31 | 12.92 | 14.42 |

RSS describes the compiler process, not guest linear-memory capacity or simultaneous process-tree memory.

## Retained edits

Five fresh session processes per scale; each receives the same ordered edit matrix. The table is the 128-caller point. Wall time includes cache decode/admission, candidate compilation, canonical encoding and output publication. The bridge rows use a separate fixed bridge fixture, not 128 bridge functions.

| Revision | Wall ms, median [min–max] | Bodies completed | Bodies reused |
| --- | ---: | ---: | ---: |
| fresh | 34.70 [33.46–44.44] | 131 | 0 |
| unchanged | 53.44 [52.29–54.23] | 2 | 129 |
| body-edit | 50.42 [48.86–52.02] | 3 | 128 |
| interface-edit | 44.90 [43.50–46.28] | 131 | 0 |
| static-edit | 53.13 [49.96–53.90] | 130 | 1 |
| rejected-edit | 5.83 [5.50–6.17] | 0 | 0 |
| valid-revert | 51.94 [50.63–53.33] | 2 | 129 |
| source-origins | 50.45 [49.75–51.90] | 2 | 129 |
| bridge-first | 9.64 [9.49–10.38] | 1 | 0 |
| abi-edit | 4.57 [4.55–5.35] | 1 | 0 |

The two completed staging bodies on unchanged revisions implement the scalar static value. Reuse is semantically effective but currently costs more than checking these small bodies afresh. At scale 128, median clocks for the unchanged request are:

- old-cache decode/admission: **5.48 ms**.
- source completion and relocation: **15.98 ms**.
- planning/schema/fingerprint work: **12.81 ms**.
- candidate validation: **5.20 ms**.
- canonical encoding and retained copy: **10.99 ms**.
- publication: **2.03 ms**.

These are medians of individual clocks, not components of one selected median sample. Cache admission visits, dependency invalidations, retained bytes and every raw response are in the archive. Rejected edits preserve the prior Wasm; valid reverts reuse only justified bodies.

## Where compilation time goes

Separate instrumented build samples at scale 128; milliseconds. These are individual attribution runs, not the paired timing medians. Required validation checks Core; lowering includes Wasm emission, byte-level validation and the certificate.

| Family | Load | Source completion | Plan/schema/keys | Required validation | Lowering | Semantic visits | Validation visits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| independent | 0.33 | 0.71 | 7.36 | 4.89 | 0.47 | 5,128 | 208,438 |
| generics | 0.22 | 0.60 | 7.90 | 4.52 | 0.47 | 5,293 | 194,148 |
| closures | 0.29 | 1.03 | 12.41 | 18.13 | 1.72 | 12,040 | 782,523 |
| modules | 1.75 | 2.98 | 12.97 | 13.17 | 1.19 | 27,400 | 688,424 |
| proofs | 0.98 | 17.61 | 6.76 | 281.84 | 3.48 | 2,438,920 | 16,881,606 |
| domains | 0.39 | 2.26 | 45.39 | 75.12 | 1.62 | 45,704 | 3,549,408 |

All accepted attribution samples report zero active regions, downstream inference regions and general inference nodes. The generic point performs 128 interface instantiations with 129 semantic/runtime bodies: one shared generic body and 128 callers. The proof point records 2,226,560 source proof visits and 2,264,454 validation proof visits; its 16,881,606 total validation visits show substantial work beyond proof reasoning.

## Operation limit and source-less artifact restart

A single function scales Unit operations to the exact 65,536-operation bound, including its return. Five samples per point; phase clocks are separate. Original source is removed before independent Core inspection and local Wasm rebuilding. This measures the operation limit, not the separate 16 MiB byte cap.

| Operations | Source check ms | Build + Core ms | Core bytes | Rebuild without source ms |
| ---: | ---: | ---: | ---: | ---: |
| 8,192 | 10.32 [9.73–10.83] | 19.06 [18.48–21.29] | 864071 | 12.34 [12.29–12.94] |
| 32,768 | 30.73 [29.34–31.61] | 51.87 [50.68–52.66] | 3444552 | 33.21 [32.41–33.58] |
| 65,536 | 58.30 [56.75–60.25] | 106.02 [95.18–110.67] | 6885192 | 59.64 [58.14–61.79] |
| 65,537 | 22.78 [21.10–23.17] (rejected) | — | — | — |

Every 65,537-operation sample rejects with `k1_core_limit`. Every accepted restarted artifact executes the same checksum as its source-built guest. Canonical transport may renumber tables and change certificate/Wasm bytes; semantic equality is checked by execution. No disk receipt bypasses source admission.

## Wasm runtime and storage

Nanoseconds per exported call at scale 128, median [min–max] across five short samples in the same Deno/V8 engine. Each sample executes about 20,000 total calls over the exports and verifies its checksum. JS/Wasm crossings and required entry wrappers are included. Engine tiering is not isolated, so these numbers are not steady-state kernel throughput.

| Family | K1 ns/call | Baseline ns/call |
| --- | ---: | ---: |
| independent | 84.2 [80.6–179.8] | 85.0 [72.5–147.4] |
| calls | 106.1 [93.5–148.0] | 90.6 [61.1–106.9] |
| diamonds | 176.3 [159.6–243.4] | 77.2 [60.7–168.0] |
| generics | 109.4 [82.4–131.4] | 66.1 [60.0–74.0] |
| closures | 103.4 [88.5–122.3] | 139.6 [91.7–993.9] |
| modules | 119.6 [83.6–1886.4] | 61.2 [60.1–118.8] |
| proofs | 167.0 [140.1–322.4] | 85.5 [63.6–112.3] |
| domains | 138.3 [88.6–178.3] | 119.6 [94.8–390.0] |
| chains (127-depth control) | 1253.6 [635.3–1280.5] | 129.2 [108.0–156.1] |

Instrumented particle runs are separate from those timings. Counters are cumulative per fresh instance; backing bytes include granule rounding, result bytes include the wire descriptor, and initialized/copied bytes count typed payload rather than control metadata.

| Rows | Reservations/releases | Backing high-water B | Scratch high-water B | Result high-water B | Initialized B | Copied B | Calls/iterations |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 1/1 | 24576 | 256 | 16 | 100 | 20 | 1/0 |
| 1 | 1/1 | 24576 | 256 | 16 | 132 | 44 | 1/1 |
| 1024 | 1/1 | 24576 | 256 | 8200 | 32868 | 24596 | 1/1024 |

All three end with zero live backing. The unoptimized particle loop is independently inspected for four F32 loads, two stores, two multiplies, two adds and no loop helper/callback calls. The final helper/certificate gate rejects memory growth, managed retain/release/collector paths and unexpected imports; telemetry is not a substitute for that structural check.

## Rebuilding the compiler

Isolated source and Goose-home snapshots distinguish fresh intermediates, unchanged rebuilds and appending an ordinary comment. Debug has five rounds; release has three. Every produced compiler is smoke-checked. Seconds, median [min–max]; peak RSS is the largest child/descendant, not a simultaneous process-tree sum.

| Mode | Case | Seconds | CPU seconds | Peak RSS MiB |
| --- | --- | ---: | ---: | ---: |
| debug | fresh | 37.36 [35.22–42.11] | 37.07 | 1125.3 |
| debug | unchanged | 37.82 [34.58–43.22] | 37.40 | 1125.1 |
| debug | comment-edit | 37.08 [34.72–42.32] | 36.78 | 1124.5 |
| release | fresh | 57.67 [56.76–57.83] | 57.19 | 803.1 |
| release | unchanged | 57.15 [56.70–57.33] | 56.64 | 803.2 |
| release | comment-edit | 57.14 [56.34–57.39] | 56.69 | 803.4 |

Separate first-round attribution runs Goose with `--dry-run` (parse/check/C generation), then replays the exact printed Clang command. They are not subtractions from whole-build samples.

| Mode | Goose frontend + C generation s | C backend s | Clang optimization |
| --- | ---: | ---: | --- |
| debug | 30.05 | 6.78 | `-O0 -g` |
| release | 28.11 | 28.76 | `-O2` |

Goose reruns its frontend and C compiler even for unchanged/comment-only builds. This is separate from Blot user-program checking. Fresh/repeated/edit generated-C hashes are retained so a future skip or incremental strategy can be measured against this baseline.

## Concrete follow-up levers

The phase costs above are measured. The following helper-level explanations come from code inspection; no CPU/cache profiler has yet quantified each helper or demonstrated a speedup. Preserve all exact validation and authority checks.

1. **Use function-local affine state.** `validate.goose` currently sizes live-state arrays to every program Value for each block, copies them per edge and scans them on exits—even for scalar functions without affine values. Derive sparse local authority indexes instead.
2. **Compute CFG facts once.** Cache validated predecessor/dominance/operation-position information and evidence availability by evidence/block/position, retaining SSA version and scope distinctions.
3. **Reuse layout/canonicalization scratch.** `canonical.goose` initializes two 131,072-entry U32 tables (1 MiB) per call. Batch bottom-up layouts and use generation-stamped scratch/exact schema interning with binder context and collision checks.
4. **Relocate only the reused declaration.** Whole-table remap initialization and scans recur per reused function. Per-revision owner/identity indexes and sparse remapping could reduce the 15.98 ms unchanged completion cost.
5. **Retain owned immutable Core directly.** The current process serializes, decodes and revalidates its private revision each request. Bounded immutable declaration ownership could avoid that transport while keeping transaction rollback and full external-artifact admission.

Compiler iteration needs a separate Goose-level investigation: the attribution distinguishes its frontend/C-generation cost from Clang. None of these proposals is counted as an implemented or measured improvement. SIMD or additional workers should follow profiling of the remaining work, not conceal repeated global scans.

## Reproduction and limits

Use the commands in [the corpus README](README.md), with `--baseline=/path/to/the/verified/blotc` for paired runs. The extra depth control uses `--families=chains --scales=127 --rounds=5 --out=build/bench-k1-release/chains-boundary`. `scripts/package_evidence.py` checks source/binary/evidence hashes before publication.

This branch deliberately replaces the legacy implementation and edition at the user’s request; main and the installed legacy compiler remain separate. Linux is the exercised platform. Release-only inlining/fusion/SIMD, persistent source-admission caches, zero-copy host access and internally parallel compilation are not claimed. The first two are optional future optimization/cache choices; excluded language/host features are listed in [scope](../docs/features.md). The tests and certificates are implementation evidence, not a mechanized proof or authentication of arbitrary external executable bytes.
