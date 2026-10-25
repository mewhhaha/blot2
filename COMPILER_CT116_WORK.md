# CT116: frontend work reduction and language benchmarks

Authorized scope: remove repeated builder generalization work, introduce safe
module-check parallelism, avoid intermediate imported-interface copies, and
improve large inference-set operations. Add reproducible idiomatic Blot/Rust
compile-time and same-engine Wasm runtime benchmarks, with measured README
results. Preserve existing syntax; consult before language-rule changes.

Baseline: qualified CT114 and the CT115 module census. Existing CT111–114 edits
and concurrent owned-array changes remain preserved. CT110 is installed.

The frozen CT116 compiler is correctness-qualified; release measurements and the
public language benchmark campaign are complete. The development gate passes in
29.80 s with zero Zig lint findings. It compiles the full native inventory, runs
the selected laws with sampled allocation failures, and runs guest/client and
static checks. This is not full qualification.

Implementation sequence:

1. Dependency-indexed generic-requirement analysis with exact mutation and
   rollback guards; ordered membership indexes for larger sets.
2. Immutable producer-interface instantiation and worker ownership boundaries.
3. Independent module checking with deterministic diagnostics and project-wide
   budget accounting.
4. A broad, public Blot/Rust workload suite with equivalent outputs, runtime
   inputs, compiler/source pins, alternating measurements and disclosed limits.

SIMD uses the standard library search primitive; no separate SIMD speedup is
claimed. Algorithmic work elimination takes priority over vectorizing the 26 ms
lexer. The combined release screen measures the retained implementation.

## Implemented boundaries

- Requirement dependencies are retained by pending ordinal. Exact type/effect
  watches invalidate on substitutions, physical writes, rollback, slot reuse,
  future IDs and clock saturation. Projection-bearing stores retain the original
  charged query. A Safe/noLLVM work census records 599,188 hits / 641,867
  candidate queries, 63.6% fewer free-type visits and 49.8% fewer free-row
  visits. These counts are not release timing claims.
- Completed live producers supply immutable sharing summaries. Imports relocate
  type/row IDs into consumer-owned stores and copy flag values, avoiding
  repeated graph walks. Frozen and unpublished summaries use the original
  analysis. Canonical imported type graphs are still copied; full
  direct-from-producer instantiation remains a separate architecture change.
- Fresh independent modules run in joined dependency-ready batches. Each worker
  owns its solver, budgets, counters and diagnostics. Symbols and producer
  interfaces are read-only during a batch. Name misses, diagnostics or aggregate
  budget exhaustion discard speculation and rerun serially. Retained checking,
  source validation, editor queries and small projects keep their existing
  paths. `frontendWorkers` / `--frontend-workers` accepts 1–16; default remains
  1 pending release policy measurements. A Safe four-worker census schedules 188
  jobs in 25 batches with zero fallback and unchanged application Wasm.
- Inference membership keeps original ordered lists, uses the standard library's
  vectorizable scalar search for small sets and builds sparse hash indexes at 64
  items. Boundary/duplicate/sparse-ID and allocation-failure laws cover the
  change.

New laws compare serial/parallel Core, diagnostic ordering, combined forwarding
budgets and allocation failures. Imported-summary laws compare independently
recomputed Core with fresh type and callback-row variables. The executed Wasm
worker matrix covers fresh, dependency edits, reverts and rejection.

## Public language benchmarks

Eighteen idiomatic Blot/Rust program pairs cover arithmetic, arrays, lists,
optional values, searching, text, matrices and recursive trees. Both languages
compile to Wasm and run in Deno/V8. All 18 pairs pass seven independent output
witnesses with the qualified CT114 release. Final CT116 timings and all raw
samples are published in README. The runner records fresh-process wall/CPU/RSS,
runtime samples, exact source and compiler hashes and memory/size observations.
See [methodology and sources](benchmarks/idiomatic/README.md).

## Environment and isolation

The default Zig analyzer executable was missing. A workspace-owned Safe/noLLVM
build of the sibling analyzer and its patched Zig 0.17 backend restores lint;
`ZIG_ANALYZER` points at `build/tooling/zig-analyzer/zig-out/bin/zig-analyzer`.
All current compiler sources pass with zero findings.

Qualification uses a frozen CT114 tree plus the CT116 changes. Concurrent
`owned_arrays.zig`, `owned_arrays_tests.zig` and `owned_array_execution.test.ts`
changes remain preserved and excluded. Raw evidence lives in
`build/bench/ct116`. No syntax change, commit, push or local installation has
occurred.

## Final result

The exact frozen release passes 2,596 native laws with 1,692 full allocation
sweeps and zero sampled sweeps, 1,660 release guests, 48 smoke and 57 tooling
checks. Final Zig lint has zero findings. Full gate elapsed time is 687.33 s.
Source pins cover 1,221 files, including native fixtures; 17 native journal
artifacts are audited. Initial missing-fixture and cancelled runs remain
incomplete evidence, not passes.

Three profiled rounds measure whole frontend 1.600 → 1.036 s and checking 1.214
→ 0.649 s. Final free-type visits fall 79.4%, free-row visits 60.7%, allocation
requests 51.1% and requested allocation bytes 15.7%. Immutable producer metadata
is reused 17,640 times. Canonical interface graphs still copy. No separate SIMD
gain is claimed.

The final unprofiled three-pair screen measures fresh game 7.594 → 7.050 s
(paired CPU −1.81%). Literal/body edits remain 3.234/5.556 s, with no meaningful
ordinary-edit speedup established. The frontend remains slightly above one
second; backend work remains dominant. Read
[the qualification report](zig-native/CT116_QUALIFICATION.md) for full
boundaries.

The public campaign completes 180 compilations and 1,116 runtime batches, with
seven independent witnesses per workload. Blot compiles these small programs in
6–10 ms versus Rust's 42–83 ms, while Rust's median runtime is lower in every
case. Text and persistent-list gaps remain visible. The benchmark runner and
task were finalized after compiler qualification and validated by this complete
campaign; Rust compiler, target-library and linker inputs are pinned. The task
uses Deno's full permission mode because Linux `/proc` affinity reads require
it. No compiler source changed after the full gate.

Portable evidence is linked from the qualification report: 148 files, SHA-256
`96b246fd34793e193ebeb0abe77fe5c98490735bd7920db0e04eea4ef0355abb`; every
manifest entry verifies. The combined checkout's non-documentation sources
differ from the frozen source manifest only in the three preserved concurrent
owned-array files.
