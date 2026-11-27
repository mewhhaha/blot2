# 121 — Qualify and measure the owned applications

- **Status:** Checked-grid and release-engine qualification recorded below. Whole-application storage qualification remains open.
- **Dependencies:** 120 final candidate. Preserve baseline artifacts before
  retirement; do not rebuild the baseline after deleting its implementation.
- **Contract:** [Review](../docs/compiler/STORAGE_REWRITE_REVIEW.md),
  [schedule and gates](STORAGE_REWRITE.md).

## Outcome and ownership

Report whether the replacement works across Squid, Pen, Ink and Gdev and whether
it saves actual compilation time, runtime time and memory. Keep those quantities
separate. This task owns benchmark/gate configuration and durable evidence;
source fixes go to the relevant task owner, followed only by affected rechecks.

## Execute once on a coherent candidate

- [ ] Record baseline/candidate compiler, host, standard library and consumer
  source identities, including uncommitted changes. Keep private Gdev source
  outside public commits; durable reports contain hashes and measurements.
- [ ] Check `zig version` (0.17.0). Run the final compiler gate and zero-finding
  Zig lint. Native tests compile with `-Dllvm=false`; LLVM is for the final
  release compiler and release performance measurements. Record exact executed
  inventory and failures, not just compilation success.
- [ ] Finish the required Ink/Gdev formatting, generation, compilation and
  behavior checks against that artifact. Reuse unchanged consumer evidence from
  checkpoint 3 only if the final candidate and all observed inputs match;
  retirement normally requires replay on the final compiler.
- [ ] Group browser/Pen transport, JSPI settlement/rejection, reentry/dispose,
  persistent state, protocol rejection, explicit save/restore and prepared
  worker recovery checks. Keep one/four worker coverage. A failed worker may be
  recreated; do not claim its partially mutated state survives recreation.
- [ ] Run bounded deterministic gameplay/save/replay and headless render
  witnesses, then measure the final release compiler/runtime. Do not introduce
  a long soak when seeded boundary tests prove generation/capacity behavior.

## Measurement contract

| Metric | Boundary |
| --- | --- |
| Fresh compilation | Game and devtools separately; wall and compiler CPU; identify cold process/cache conditions |
| Retained edits | No-op, literal edit and body edit; report separately from fresh builds |
| Precompiled runtime | Compile/instantiate/warm up before timing; fixed seed, input trace, timestep and frame count |
| Simulation and presentation | Separate guest update, packet encoding/copy and host rendering where observable |
| Memory | Used payload, metadata, reserved/committed Wasm bytes and peak host memory; avoid treating them as one measure |
| Work/output | Wasm size, deterministic state/save witness and changed scene/packet behavior |

Use a small fixed number of paired baseline/candidate samples (five alternating
pairs to start), recording all samples and spread. If the comparison changes
representation, compare semantic state witnesses rather than requiring identical
Wasm bytes. Do not rerun indefinitely seeking significance; report noise or an
unavailable baseline explicitly. Release compiler measurements must not be
presented as development-backend speed, or vice versa.

The earlier 15.61-second Gdev compilation and 189.7-second test suite are
historical, differently scoped evidence. Neither is a gameplay frame-time
baseline. Worker fixture memory likewise is not Gdev world memory.

## Completion

- [ ] Required behavior checks pass or a specific remaining failure keeps the
  affected requirement open. A partial run never closes full qualification.
- [ ] Durable report under `compiler/` links candidate/source identities,
  concise commands, results, raw local evidence locations and limitations.
- [ ] Tables report before/after compile, runtime and memory results without
  inferring gains from architecture alone. If a meaningful gain is absent,
  identify the measured remaining cost instead of claiming the goal achieved.
- [ ] Update the task index, executable guide and active completion notes.
  No commit or push is requested here; the full gate is required before a later
  requested compiler commit. Task-directory cleanup remains a separate action.

## Evidence

Pending. The source review and task files are not benchmark results.

## Checked arrays and release inlining

On 20 November 2026, seven alternating, randomized rounds on a pinned CPU ran the same guest Wasm in both Pen release-engine modes. The two answers for the 120 × 120 tree and hill grids were 1357/565440 and 238/238. All cases matched in Squid and Rust, including recovery from a trapped invocation. Timings below are warm guest p50 / p95 in microseconds across 175 calls per cell.

| Kernel | Squid off | Squid on | Rust on |
| --- | ---: | ---: | ---: |
| Tree sightlines | 3384 / 3499 | 1245 / 1287 | 574 / 594 |
| Reverse BFS | 2626 / 2744 | 802 / 820 | 283 / 313 |
| Fixed scalar scan | 67.54 / 73.29 | 13.29 / 16.11 | 8.86 / 11.29 |
| Initialized writes | 269.29 / 282.80 | 42.24 / 54.34 | 13.55 / 15.22 |
| Local view | 36.04 / 40.12 | 8.02 / 8.14 | 2.02 / 2.05 |
| Grid parse | 325.20 / 340.50 | 213.06 / 230.85 | 17.75 / 19.03 |
| Packet length only | 1.74 / 1.79 | 1.72 / 2.15 | 0.05 / 0.06 |

The direct compiler emits checked calls. Inlining removed all three native call sites in `sight`. In `distances` it cut 28 sites to four and removed all 14 calls to `runtime.address`. The scalar scan still had an inner bounds branch with engine inlining enabled.

| Median cold stage | Trees off → on | Hills off → on |
| --- | ---: | ---: |
| AOT compile, ms | 8.66 → 22.92 | 11.25 → 29.04 |
| Deserialize, µs | 96 → 99 | 108 → 112 |
| Instantiate and bind, µs | 319 → 311 | 308 → 321 |
| First whole packet, µs | 3614 → 1521 | 2818 → 1071 |
| AOT bytes | 31,616 → 43,936 | 37,816 → 50,160 |
| Peak process RSS, KiB | 20,572 → 26,808 | 20,668 → 29,160 |

Pen explicitly selects Cranelift inlining for release and portable AOT, with development off. The cache key changes with this setting and Wasmtime rejects artifacts compiled with the other mode in both directions. Inlined frames may be absent from release backtraces. The debug profile preserves their boundaries. The 22 native host laws include traps, effects, cache corruption, native packages, stack diagnostics and guest disposal.

A real Ink ordered hash over 16,384 keys returned 2,809,217,323 in both modes. Median execution fell from 171 to 62 µs. Both modes passed the same 283 Ink checks. Three fresh-cache hardware Gdev launches per mode used identical 2,754,496-byte Main Wasm. All six produced identical 640 × 480 PNGs and guest traces. Median first complete frame was 2225 ms off and 3056 ms on, including startup and rendering. This cost supports retaining the fast development default. No full-game steady-state speedup is claimed from one-frame runs.

[Sources and reproduction](../benchmarks/checked-grid/README.md) · [Matched kernels, metadata and raw distributions](../benchmarks/evidence/measurements/checked-grid/release.json.gz) · [Ink and Gdev application runs](../benchmarks/evidence/measurements/checked-grid/applications.json.gz) · [Pen engine and compatibility test](https://github.com/mewhhaha/pen/commit/3a6a531)

### Reusing the descriptor in a scalar range

A fixed scalar array already validates its owner and generation when the range reads its length. In a small straight-line loop containing only scalar operations and reads at the induction variable, the compiler now loads the base and extent from that same entry. The existing unsigned induction test proves the element is in bounds. The normal member-dispatch target must actually return the primitive length of its parameter. A custom prelude with different length semantics takes the ordinary path. Calls without a scalar forwarding proof, writes, resizes, views and early exits also retain checked lowering. The proof visits at most 96 Core nodes.

With inlining enabled, the old native loop checked the same unsigned bound twice and loaded the array base each iteration. The new loop checks the range once and retains the base in a register. The element address is still a Wasm32 base plus a scaled index. Validation happens at the original range-end expression. The fixed-array scan produced 2,139 Wasm bytes (previously 2,179) and 21,080 native artifact bytes (previously 21,192).

| Scan, 13 randomized rounds | Previous p50 / p95 µs | Checked range p50 / p95 µs | Rust p50 / p95 µs |
| --- | ---: | ---: | ---: |
| Release inlining | 13.45 / 25.86 | 12.87 / 21.84 | 9.16 / 18.52 |
| Inlining off | 70.58 / 115.52 | 11.13 / 17.97 | 8.99 / 18.11 |

The median paired process ratio with inlining was 0.941 and 11 of 13 pairs improved. A separate 13-pair run with the debug compiler producing the candidate Wasm improved 13 of 13 pairs. Source compilation of the small scan, including startup and std, measured 23.60 → 23.92 ms. The writer, view, grid, parser and packet controls produced identical Wasm under both compilers. The 283 Ink results and pinned Gdev's 2,754,496 Wasm bytes matched. Gdev's six paired fresh compiles with eight workers measured 817 → 824 ms under concurrent load, and its rendered frame and trace matched.

[All 546 runtime processes and 182 fresh compiler timings](../benchmarks/evidence/measurements/checked-grid/checked-range.json.gz) · [Native instructions, Gdev timings and integration identities](../benchmarks/evidence/measurements/checked-grid/range-checks.json.gz)
