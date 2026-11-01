# Compiler experiments

For the owned backend, start with the bounded scalar call graph:

```sh
deno run --no-config --no-lock -A scripts/bench/scoped_calls.ts --blotc zig-native/zig-out-dev/bin/blotc --sizes 1,4,8 --depth 12
```

Each fresh session has a five-second build deadline, executes its Wasm against
an independent recurrence, and reports source/compiler hashes, build latency,
bytes and work counters. Add `--profile` for attribution; keep instrumented
samples separate from throughput measurements. `--timeout-ms` caps at 30,000.
Timeouts are incomplete and kill the active compiler. The
[first paired record](../../zig-native/measurements/scoped-call-sharing-2026-10-31.json)
is a Safe/noLLVM synthetic result; whole-Gdev subsecond compilation remains
open.

For nested generic field access on anonymous records:

```sh
deno run --no-config --no-lock -A scripts/bench/scoped_calls.ts --blotc zig-native/zig-out-native-dev/bin/blotc --fields 64 --sizes 4 --depth 5
```

`--fields` selects the record workload; `--sizes` then counts repeated calls.
Each stage calls its predecessor twice. Runtime checks independently sum the
fields and apply the stage/repetition counts. The
[concrete-field record](../../zig-native/measurements/concrete-fields-2026-10-31.json)
includes five alternating pairs and an unchanged scalar control. A 64-field
depth-six probe reaches the existing source-validation budget; it is a rejected
workload, not a timing result. Do not raise compiler limits for the benchmark.

Add `--nominal --fields 3 --depth 6 --sizes 1,4,8` to compare generic field
access through a named data constructor. The independent field recurrence is
unchanged. The
[nominal record](../../zig-native/measurements/nominal-call-sharing-2026-11-01.json)
includes five alternating pairs per size. Depth-eight/eight-call probes still
hit source-proof validation on that candidate. The later
[proof/type-sharing record](../../zig-native/measurements/proof-and-type-sharing-2026-11-01.json)
preserves that rejection and the completed proof-instance fix. Run its six-cell
acceptance matrix with unchanged limits:

```sh
deno run --no-config --no-lock -A scripts/bench/source_proof.ts --blotc zig-native/zig-out-native-dev/bin/blotc
```

For frontend type-graph copying, use unused generic pair helpers:

```sh
deno run --no-config --no-lock -A scripts/bench/open_type_dag.ts --blotc zig-native/zig-out-native-dev/bin/blotc --depths 8,12,16,20
```

This instrumented development-tier probe reports phase clocks, type-node counts,
source/compiler/output hashes and executed entry checks. Its output stays 2,935
bytes while the signature depth grows. Each startup/build has a five-second
deadline. Keep these profiled samples separate from unprofiled throughput.

For nested storage readers and Unit writers:

```sh
deno run --no-config --no-lock -A scripts/bench/storage_calls.ts --blotc zig-native/zig-out-native-dev/bin/blotc --sizes 1,4,8 --depth 10
```

Both graphs call their predecessor twice per level. Each build executes seven
inputs, including wraparound and repeated invocations, against independent
results. Reports include Wasm bytes/functions, emission and admission counters,
source/compiler hashes and a five-second deadline. The
[descriptor-call record](../../zig-native/measurements/storage-call-graph-2026-11-01.json)
contains five alternating pairs at four calls. The real-game 1 MB expectation
and subsecond compilation target remain open.

Run measurements on an otherwise idle host, using a preserved release binary for
each variant. Keep the frozen workload manifest, output hashes, commands and raw
samples with the report. Safe/noLLVM builds qualify development behavior; they
do not predict release performance.

## Paired builds and semantic workers

`deno task bench:compile --help` documents the paired harness. It alternates
variant order and verifies fresh/retained outputs. Use seven pairs for an
optimization decision, including game edits and the devtools guard. Supply the
frozen `--snapshot`, `--manifest` and `--hashes` explicitly.

`--semantic-workers N` enables the existing semantic worker policy for both
variants. `--candidate-semantic-workers N` overrides only the candidate, so the
same binary can compare the default policy with two or four workers. Omitting
both flags preserves the existing default. The flags do not bypass recording,
refinement, dependency or budget eligibility checks. Worker counts must be
between one and sixteen.

`--workload review` explicitly selects a held-out matrix of wide
records/effects, 32- and 64-variable generic schemes, deep closures, a shared
diamond, 32 producer modules plus an entry, and a small program. Each has a body
edit and fresh/revert controls. It is separate from the historical budget corpus
selected by `synthetic` or `all`; individual `review_*` names can also be
selected. Public generators live in `review_corpus.ts`.

## Long retained sessions

```sh
deno run -A scripts/bench/session_memory.ts \
  --baseline /absolute/qualified-blotc --candidate /absolute/candidate-blotc \
  --snapshot /absolute/frozen-snapshot --manifest /absolute/manifest.json \
  --out build/bench/new-memory-run --edits 200 --control-every 20
```

The Linux harness runs distinct literal edits, periodic no-ops, errors and
recovery, a final restoration and an idle observation. Fresh baseline controls
cover the original, first, final and periodically sampled revisions. Other
revisions have no fresh-output control; the completion record states that
limitation. Every sampled output, recovery and restoration must match its
control. Sources and compiler hashes are checked again before completion.

`samples.jsonl` records RSS, lifetime RSS peak, faults, process CPU ticks and
compiler statistics. RSS is not allocator-live memory. These are observations of
a retained process, not an isolated latency comparison. `complete.json` exists
only after all checks pass. A new output directory is required.

Add `--profile` for phase counters and small-heap occupancy. This changes the
measurement mode; compare like modes and retain the unprofiled control. Heap
occupancy is observed before publication, while old and pending revision owners
can overlap. The process RSS sample follows the completed response.

## Whole-process hardware counters

`process_pmu.ts` accepts `--binary`, `--snapshot`, `--manifest`, `--hashes` and
a new `--out` directory. It records fresh, literal, body and revert requests
using `process_pmu.py`. Linux x86-64 and permission to open hardware events are
required. Every thread present at attachment receives counter groups; future
threads inherit them. A changing thread inventory during attachment is rejected.

The report retains raw counts, enabled/running times and scaled estimates for
generic cycles, instructions, branches and cache events. It covers user space
and whole requests; it does not isolate internal compiler phases or identify a
specific cache/TLB bottleneck. Keep scheduling ratios and scope with any claim.
The collector uses individual counter reads because Linux does not support
inherited `PERF_FORMAT_GROUP` reads; see the
[perf event interface](https://man7.org/linux/man-pages/man2/perf_event_open.2.html).

## Zig compilation timing

Check `zig version` first: these scripts target Zig 0.17.0. Add `--time-report`
to the next necessary `deno task build:compiler` release build, or to a `--dev`
build when studying native development compilation. Zig forces a rebuild for
this option and starts a persistent local timing web server. The command remains
running after compilation completes.

Capture the server's WebSocket URL into a new directory:

```sh
deno run -A scripts/bench/zig_time_report.ts \
  'ws://[::1]:PORT/' build/bench/new-zig-report
```

The collector saves every raw message, per-step timing, declaration timing and
LLVM text. It sends no rebuild requests. It succeeds only when every step has
succeeded and has a report. Stop the original build's idle web server after
capturing that evidence; an intentional server stop is not a compiler failure.
Keep CPU categories separate from elapsed stages: they need not add to wall
time. The decoder follows the installed Zig 0.17.0 build-web format and must be
rechecked when Zig changes.

`compiler_iteration.py` measures isolated Safe/noLLVM construction, including
production/test edits, reverts and full native inventory compilation. It does
not execute the full gate and its percentile is not a complete edit/check cycle
percentile. Keep those measurements separate.

`development_cycles.py --out NEW_DIRECTORY` runs 20 complete static-sharing
edit/check cycles in a disposable checkout with frozen sibling corpus fixtures.
It groups leaf, checker and test-only edits, restores every input, and reports
the initial check and group restoration checks separately. Set `ZIG_ANALYZER`
first. Its p95 is the observed sample percentile, not a universal latency bound.

### Asset reply copying

`deno run --allow-all scripts/bench/asset_reply.ts --baseline OLD --candidate NEW
--out NEW_DIRECTORY --runs 5 --asset-mib 8`
compares alternating compiler pairs with two binary reference assets. It
measures end-to-end client build latency and compiler process CPU/RSS for fresh,
unchanged, source-edit and revert requests. Every asset has an independent
byte-hash oracle, every guest executes, and compiler/output identities are
checked. Compiler RSS excludes client RSS; startup is outside request timing.
Use a fresh output directory and run without competing local builds. The
asset-only segment optimization does not imply a copy saving for ordinary
Wasm-only responses.

Profiled backend reports include an inclusive per-caller region census,
exclusive coordinator thread CPU on Linux and separate backend worker CPU/finish
times. `costSummary` keeps `backend_work_thread_cpu_ms` separate from wall
clocks. Nested region times overlap; do not sum them. Profiling may add
significant clock overhead, so throughput decisions require unprofiled
alternating pairs.

For frontend investigations, use `stats.phaseProfile.phases` for exclusive
clocks and `stats.phaseProfile.checking` for work aggregated across completed
module checks. The latter includes candidate scans, scheme imports and frontend
normalization; `stats.frontend` alone describes the entry module. Sum every
phase except `backend` for the whole frontend. Keep this instrumented total
separate from unprofiled process CPU and end-to-end latency. See the
[frontend architecture review](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILER_FRONTEND_REVIEW.md)
for the CT114 findings and remaining representation changes.

`deno run -A scripts/bench/render_producer.ts --compiler PATH` checks the actual
Gdev `pen/protocol_render` import with its native-asset settings and a five-second
deadline. It emits and executes only a tiny identity entry. Compare alternating
compiler runs using `phaseProfile.checking`; the emitted size does not measure
the renderer or whole game.

## Idiomatic Blot/Rust programs

`deno task bench:idiomatic` measures eighteen public source pairs with fresh
optimized compiler processes and same-engine Wasm execution. Every output is
checked against independent witnesses. Commands, compiler/source hashes,
wall/CPU/RSS, runtime distributions and Wasm sizes remain in the report. See
[workloads and methodology](../../benchmarks/idiomatic/README.md); this is a
small-program comparison, not a whole-application build-system comparison.

For module-check policy measurements, `bench:compile --frontend-workers N` pins
both compilers; `--candidate-frontend-workers N` changes only the candidate.
Leave the baseline option omitted when comparing against an older compiler that
does not recognize the new flag. These options are separate from evaluator
semantic workers and optimizer workers.

## Runtime representation boundaries

`deno run -A scripts/bench/runtime_boundaries.ts --baseline OLD/blotc
--candidate NEW/blotc`
compares the 28 public numeric-row and reference-scratch cases. It checks
runtime ownership budgets and records alternating samples, fresh compilation
costs, output sizes and input hashes. See
[the methodology](../../benchmarks/runtime-boundaries/README.md).
