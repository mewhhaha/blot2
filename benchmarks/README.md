# K1 measurement corpus

[Current comparison against main](MAIN_COMPARISON.md) measures equivalent loop
kernels and fresh compilation with both exact qualified binaries. It includes
remaining generic runtime regressions and a separate comparison chart.

[Previous/new K1 runtime measurements](RUNTIME.md) cover two bounded lowering changes
with fresh engine processes, exact kernel references and compile controls.

[Earlier structural measurements](STRUCTURAL.md) isolate borrowed validator views,
forward-only proof SCCs and bounded release inlining.

[Earlier parity investigation](PARITY.md) compares the improved rewrite with the
legacy Zig compiler, including remaining regressions and publication costs.
[The earlier Sol review](SOL_REVIEW.md) compares the original and improved K1 releases.
[Initial results](RESULTS.md) retain the legacy comparison, regressions and the
separate 127-depth chain control.

Run after correctness qualification, with a known compiler build:

```sh
deno run --allow-read --allow-write --allow-run scripts/benchmark.ts \
  --rounds=5 --scales=8,32,128 --build-label=goose-release
```

`--baseline=/absolute/path/to/legacy/blotc` adds counterbalanced paired runs of
semantically equivalent old/new source programs. Legacy arithmetic wraps; K1
uses explicit wrapping operations. Both programs export the same scalar entry
functions, and every measured module is executed to check its outputs.

Use `--candidate=PATH` to select a candidate executable (default `build/blot`).
Use `--baseline-kind=k1` for a prior K1 executable: both sides then use the same
K1 source and flags. `--runtime-warmup=N` and `--runtime-calls=N` control the
checksum-checked warmup and timed export sweeps; exports are resolved before
timing. Defaults remain zero warmup and 20,000 calls. Record the exact method
and compare both binaries with it; warmup does not prove a fixed engine tier.

The generated families scale independent declarations, shared-callee calls,
chains, diamonds, imported modules, one generic body with many calls, captured
closures, nested proof guards and distinct static collection domains.
Raw stdout/stderr,
source and Wasm files, source/binary hashes, wall/CPU/RSS samples and metadata are
preserved. Instrumented phase clocks are collected separately from timing
samples. Failed cases remain in the report. There is no timing pass threshold.

Use the separately recorded instruments for the remaining I09 dimensions:

```sh
python3 scripts/benchmark_sessions.py --rounds=5 --scales=8,32,128 \
  --build-label=release-qualified --out=build/bench-sessions-release
python3 scripts/benchmark_limits.py --rounds=5 \
  --build-label=release-qualified --out=build/bench-limits-release
python3 scripts/benchmark_iteration.py --goose=/path/to/goose --cc=clang \
  --modes=debug --rounds=5 --build-label=frozen-debug \
  --out=build/bench-iteration-debug
python3 scripts/benchmark_iteration.py --goose=/path/to/goose --cc=clang \
  --modes=release --rounds=3 --build-label=frozen-release \
  --out=build/bench-iteration-release
deno run --allow-read --allow-write=build --allow-run=build/blot \
  scripts/runtime_telemetry.ts
```

`benchmark_sessions.py --compiler=PATH` selects a prior compiler for paired
retained measurements. Alternate executable order across outer rounds; keep
processes sequential and use separate output directories.

The retained matrix separates unchanged checks, body/interface/static/ABI
changes, rejected edits, valid reverts and moved source origins. It records
completed/reused bodies, semantic/validation visits, retained bytes and process
RSS. Request wall time includes decoding, encoding and publication; internal
phase clocks do not. Linux process CPU measurements have clock-tick granularity.

The limits matrix measures 8,192/32,768/65,536 operations and the rejected
65,537th operation. Artifact-cap failures are separate from source admission.
Successful objects are inspected and rebuilt in fresh processes after their
source files are removed. Restarted source builds always perform fresh source
admission; no disk receipt is treated as trusted work.

Compiler iteration runs copy source into isolated directories. They distinguish
fresh intermediates, unchanged rebuilds and an ordinary comment edit, separately
for debug and release. A separate Goose `--dry-run` measures parsing/checking/C
generation, followed by the exact printed C compiler command. These attribution
samples are not subtracted from unrelated whole-build timing samples.

Runtime timings execute Wasm in the same Deno/V8 process with checksums and
include the language's required scalar-entry ownership wrappers.
These short runtime samples include engine tiering and do not claim steady-state
kernel throughput. Candidate compilation uses `--opt=off`; the pinned legacy
compiler uses its default pipeline, with both worker counts explicitly set to one.
Diagnostic
particle runs separately report cumulative 64-bit counters: rounded backing
bytes, actual frame frontier, canonical result/wire extent, typed initialized
bytes, physical payload copies, source entries and successful loop iterations.
They do not count owner/control metadata as payload. Normal timing runs have no
guest counter instrumentation. This is a synthetic compiler/runtime corpus,
not a migrated `gdev` measurement or a claim of universal application speedup.

After all runs, `python3 scripts/package_evidence.py` verifies the frozen source,
qualified executable and evidence hashes, then packages raw samples, source
inputs and logs under `benchmarks/results/k1-initial/`. Generated binaries and
compiler intermediates are excluded; their hashes remain in the records.

When reproducing an already published run, choose an unused evidence directory
with `scripts/package_evidence.py --out=benchmarks/results/NEW_NAME`. The packager
refuses to overwrite published evidence.

The Sol review has a separate `benchmarks/package_review.py` packager for its
paired K1/runtime/session scope. It checks source and executable identities,
expected sample counts, matching runtime checksums and guest storage counters,
then archives qualified inputs and raw evidence. See [its report](SOL_REVIEW.md)
for the exact commands; the initial packager remains specific to the initial
full I09 matrix.

The parity investigation uses `benchmarks/package_parity.py`; its publication
follow-up uses `benchmarks/package_publication.py`. Each freezes its own
qualification, raw samples and source hashes and refuses to overwrite an
existing package. The latter also verifies byte-identical Wasm from the K1
before/after publication pair. `PARITY.md` distinguishes default-engine timing,
`--no-liftoff` diagnostics, the debug-only local-compaction probe and the retained
comparison. The publication follow-up records CLI `setup_ns`, `pipeline_ns`,
`artifact_encode_ns` and `publication_ns` so disk waits cannot be mistaken for
frontend/validator time. Ordinary Wasm publication guarantees atomic visibility,
not durable media acknowledgement; explicit Core and paired output retain their
existing synchronization paths.

## Structural and inlining comparisons

The fresh-process harness accepts `--opt=off|fast|release` and
`--baseline-opt=off|fast|release` for paired K1 compilers. Compare release against
fast on the same qualified binary to isolate inlining:

```sh
deno run -A scripts/benchmark.ts --baseline=build/blot --baseline-kind=k1 \
  --opt=release --baseline-opt=fast --families=calls,diamonds,generics,modules \
  --scales=128 --rounds=5 --runtime-warmup=1000000 --runtime-calls=500000 \
  --build-label=qualified-release --out=build/bench-inline
deno run -A scripts/benchmark_workloads.ts --baseline-opt=fast \
  --out=build/bench-workloads
```

The second harness runs wrapping-integer recurrence and F32 affine loops with
varying seeds and exact reference models. It records paired compile wall/CPU/RSS,
Wasm runtime, hashes, checksums and separate phase builds. Source fixtures are in
`benchmarks/workloads/`. These kernels are complementary to the synthetic scaling
corpus; they do not represent a migrated application.

`benchmarks/package_structural.py` freezes the structural investigation, including
its isolated ablation overlays, previous/final qualified inputs, sampling reports,
raw pairs, full gate and new workload sources. Its manifest refuses changed
inputs or overwritten evidence. Historical packagers remain tied to their own
candidates; they are not general commands for packaging an arbitrary new build.

## Isolated runtime kernel comparisons

The workload harness now starts a fresh Deno process for every artifact. Default
and optimizing-only engine results are separate. Five kernels cover ordinary
integer/F32 loops, scalar generic transfers and an eight-byte generic fallback.
Reference checks and warmup are outside runtime timing; complete checksums guard
the measured loop. The default is 20,000 warmup and 20,000 timed kernel calls.

```sh
deno run -A scripts/benchmark_workloads.ts \
  --baseline=build/runtime-pass-baseline/blot --opt=off --baseline-opt=off \
  --engine=default --rounds=5 --out=build/bench-runtime-default
deno run -A scripts/benchmark_workloads.ts \
  --baseline=build/runtime-pass-baseline/blot --opt=off --baseline-opt=off \
  --engine=optimizing --rounds=5 --out=build/bench-runtime-optimizing
```

`--workloads=recurrence,affine_loop` selects a subset. The worker and independent
models are `scripts/benchmark_runtime_worker.ts` and `scripts/runtime_workloads.ts`.
The public harness accepts other compiler paths; the baseline above is the saved
local candidate for this investigation. `benchmarks/package_runtime.py` freezes
this specific qualified pass and verifies its baseline, source hashes and exact
paired outputs. Historical packages retain their original harness versions.

## Current main comparison

`benchmarks/compare_main.ts` is the snapshot-specific loop harness for main
`1e39b5d` versus the qualified rewrite. It pairs `workloads-main/` source with
`workloads/`, shares exact reference models, and runs each artifact in
`main_runtime_worker.ts`. Optional ownership export hooks run inside each timed
invocation when present. The packager verifies the pinned main binary identity;
use this harness with the recorded main release.

See [MAIN_COMPARISON.md](MAIN_COMPARISON.md#reproduction) for commands and limits.
`package_main.py` freezes its 209 records, committed main provenance, current gate
and all source/log evidence. `plot_main.py` renders Gnorp-inspired vertical charts
from the verified published JSON, without new measurements. Runtime uses paired
throughput (`Zig time / Goose time`, taller is faster); compile time uses each
compiler's median milliseconds (shorter is quicker). All observed ranges remain
visible. Zig/main and Goose/new K1 have explicit labels and consistent colors.
Earlier packages remain unchanged.
