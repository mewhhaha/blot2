# K1 measurement corpus

[Initial results and qualification](RESULTS.md) include all samples, regressions
and the separate 127-depth chain control.

Run after correctness qualification, with a known compiler build:

```sh
deno run --allow-read --allow-write --allow-run scripts/benchmark.ts \
  --rounds=5 --scales=8,32,128 --build-label=goose-release
```

`--baseline=/absolute/path/to/legacy/blotc` adds counterbalanced paired runs of
semantically equivalent old/new source programs. Legacy arithmetic wraps; K1
uses explicit wrapping operations. Both programs export the same scalar entry
functions, and every measured module is executed to check its outputs.

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
