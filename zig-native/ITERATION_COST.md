# Compiler iteration costs

`deno task build:compiler:dev` uses Safe and the non-LLVM backend. It now uses
Zig's ordinary artifact cache by default; `--incremental` opts into retained
compilation. Focused native checks remain incremental. Safe retains runtime
safety checks while using the production allocator; native tests retain their
validating allocator. Release builds and the full native gate retain LLVM. The
latest measurements and limits are in the 14 October section below.

The 12 October comparison used Zig 0.17.0, CPU 8 and identical source tree
`8cd045d49d5610912ec49b2a63438a6686d636bf` in an isolated checkout. Each mode
had a separate output/cache configuration. Global caches and filesystem caches
were warm; the initial measurements are not cold-machine build claims.

| Wall seconds                     | Debug/noLLVM | Safe/noLLVM |
| -------------------------------- | -----------: | ----------: |
| Initial invocation               |       10.878 |       7.883 |
| Unchanged invocation             |        8.108 |       7.549 |
| Retained source comment edit     |        8.171 |       7.627 |
| Eight unchanged compiler budgets |        8.259 |       2.014 |

The eight budget laws pass in both modes. All 28 merged constant/member, cursor,
iterator, suspension and budget test groups pass in Safe: 11.768 seconds wall,
11.552 seconds child CPU. The earlier Debug run took about 41 seconds; that
broader comparison was not a controlled paired timing experiment.

Ignored `build/bench/dev-iteration-cost/` retains commands, binary/source
hashes, logs and separate build, edit and guest samples. Its original build
report calls the unchanged invocation `retained`; `pins.json` records the
corrected meaning. Only `edit-costs.json` measures an actual source edit.

The first combined 047/086 full gate took 928.947 seconds before its one failing
native law: build 181.270 seconds, native phase 747.666 seconds. These are wall
spans on CPUs 0–3, including scheduling. The failure and pin remain in
`build/bench/joint-047-086/`; the repaired gate has its own directory. These
measurements explain the dominant iteration cost and do not justify weakening
OOM or ownership coverage. Use focused development checks, then one full gate
per frozen batch.

The repaired compiler first ran a full native phase in743.310 seconds, then
972/973 guests in274.516 seconds. After the counter-schema test correction,
unchanged compiler source reused the build and successful native cache:
0.056/0.025 seconds for those task spans,276.872 seconds for all973 guests. The
complete final gate took276.964 seconds and passed. This is retained-cache
reuse, not a fresh native execution or faster changed-source build. Pins/logs
are in `build/bench/joint-047-086-qualified/`.

## Budget-test iteration fix

The earlier profiled gate in `build/bench/iteration/qualified-gate/` took 1,155
seconds: release build 176, native compilation 247, native execution 493, and
guests 227. Two stage-chain tests spent about 214 seconds repeatedly exhausting
the production million-step inference budget.

Routine rejection and recovery now use the ordinary CLI/server compiled with a
build-local 256-step budget. The fixture has a distinct compiler identity; the
production compiler must accept and execute the input it rejects. The tests
still require one positioned diagnostic, no published output, zero reported live
allocations, fresh/retained agreement, and unchanged Wasm and execution after
recovery. The adversarial production-limit case remains in
`deno task test:compiler:stress`.

The first focused run passed both laws in 115 ms (1.12 seconds including Deno
startup/checking), compared with the earlier rounded 214-second test durations.
The fixture build took 4.71 seconds with warm global/filesystem caches. This is
not a cold-machine build measurement. The production stress case passed in 51
seconds. Commands and logs are in `build/bench/iteration/budget-fix/`.

The full profiled gate passed all 1,508 native laws, 973 guests and 884
allocation-failure sweeps. Its guest phase fell from 226.56 to 17.47 seconds.
Native compilation and execution remained about 250 and 498 seconds. The
expanded development smoke check passed all 48 tests in 8.19 seconds, including
its build; keeping the unchanged budget fixture in Zig's artifact cache avoided
a three-second regression in the quick loop. Full-gate logs are in
`build/bench/iteration/budget-qualified/`, and the final quick-loop logs are in
`build/bench/iteration/budget-dev-cached-fixture/`.

## Six implemented improvements

Local implementation commit: `9080f6b`. The recorded source and binary hashes
were rechecked unchanged on 13 October before committing this checkpoint.

Measurements are local samples with warm global/filesystem caches, including
cache-miss compilations. Other compilation was active. They describe actual
iteration costs here, not cold-machine or repeatable benchmark guarantees.

| Improvement                            |                                              Before |                                                               Measured after | Coverage                                                                                                                                                                                                                                                 |
| -------------------------------------- | --------------------------------------------------: | ---------------------------------------------------------------------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Focused Safe/noLLVM native checks      |           78.47 s for the canonical constructor law |              5.04 s for separate compile/run phases; 12.46 s including smoke | Same 16 tests passed. Full production gate stays LLVM; `--native-llvm` is available for longer executions.                                                                                                                                               |
| Rolling/summary fault fixtures         |                                             174.1 s |                                                            23.75 s whole law | Original scalar/reference integration matrix remains, plus retained/nonretained byte equality. Two exhaustive representatives cover rolling state and retained reference trees: 6,694 failure indices. Artifact publication/replacement laws remain.     |
| Typed-path fault fixtures              |                                             56.25 s |                                                      18.59 s of fault sweeps | Full eight-entry matrix stays. Exhaustive frontend, evaluator, shallow, deep unobserved and deep Foreign emission coverage: 10,490 failure indices. Source types stay immutable.                                                                         |
| Prepared/retained revision fault setup |                                             31.51 s |                                                 7.68 s across all ten sweeps | 6,828 exhaustive failure indices. Fixture decode/validation is separate; immutable emission inputs are stamped per unrelated fault, then byte-checked without sources. Shared-owner candidate faults still verify old outputs and seed at every failure. |
| Native subsystem roots                 |               247 s / about 4 GiB for the full root | Syntax 20.12 s / 552 MiB; types 26.63 s / 603 MiB; runtime 47.75 s / 955 MiB | These are optional focused roots. The default complete `production_suite.zig` is unchanged, and the full gate refuses partial selectors. All three roots also pass noLLVM checks.                                                                        |
| Pinned prebuilt analyzer in CI         | Source build exceeded 60 s before backend bootstrap |                                              Install 1.088 s; doctor 0.009 s | Exact workflow shell bodies verified the pinned archive checksum, release tag/commit and compatible Zig backend. Workflow YAML parsed. Source timing is only a lower bound.                                                                              |

Choose a subsystem without narrowing the full production gate:

```sh
deno task test:compiler:dev --native-suite syntax
deno task test:compiler:dev --native-suite types
deno task test:compiler:dev --native-suite runtime --native-llvm
```

LLVM executes the complete types/runtime roots faster on unchanged artifacts;
noLLVM makes changed native code cheap to compile. The backend is recorded in
the timing report. Native root measurements include test execution. The isolated
syntax source-comment experiment passed all 34 tests in both runs: 18.97 seconds
for its initial artifact compilation and 18.56 seconds for the retained edit,
with 566 MiB peak compile memory. Those samples are separate in
`build/bench/iteration/all-hills/shard-edit/`.

Commands, logs, source pins and individual timings are under
`build/bench/iteration/all-hills/`. The pinned analyzer bundle is
[v0.17.0-1](https://github.com/mewhhaha/zig-analyzer/releases/tag/v0.17.0-1),
SHA-256 `398b48dfbf71cf7eba40cfff277db5b1680c701feffa2fdbe3178dcf525c94d3`.

The final complete profiled gate passed 1,508 native tests, 973 guests and 894
exhaustive allocation-failure sweeps, with zero findings across 360 Zig files.
It took 743.57 seconds (12.39 minutes), compared with 958.76 seconds before
these six changes. Native execution fell from 498.20 to 281.32 seconds; release
build/native compilation remained 176.14/250.33 seconds. Guest wall time was
23.34 seconds in this run. The increased sweep count reflects splitting large
products into independent exhaustive phases, rather than sampling faults. The CI
installer was validated locally; no remote Actions run was triggered.

## Development fixture paths, 13 October 2026

`10fab46` installs the compiler, identity and ordinary fixtures in one configure
call under `zig-out-dev` during development. Fixture tests derive paths from the
selected compiler. This repairs 38 failures caused by looking in the release
output directory; all 1,030 development guests then pass.

The combined full gate now covers 1,624 native laws and 977 exhaustive sweeps.
It takes 839.91 seconds: 199.90 release build, 277.96 native compilation, 331.97
native execution and 18.17 guests. The changed workload prevents treating this
as a like-for-like regression from the earlier 743.57-second gate. Full native
execution remains LLVM; focused changed-code work uses Safe/noLLVM. Exact pins
and all phases are in [the merged qualification](CONTINUATION_QUALIFICATION.md).

## Explicit development checks, 13 October 2026

Explicit native selections now check Zig's version and run `zig build test`
once. They omit the compiler/fixture build and unrelated guest smoke tests. The
previous separate `test-compile` and `test` invocations both performed an
incremental compilation. Explicit guest selections build the development
compiler and run their selected guests; combined selections also run the native
laws. Bare development and full qualification retain smoke coverage. The full
gate still rejects filtering and measures native compilation/execution
separately.

The same `--native-filter 'typed staging rejects'` invocation produced these
local samples on Zig 0.17.0:

| Development path                       | Runner wall seconds | Result                                         |
| -------------------------------------- | ------------------: | ---------------------------------------------- |
| Original wrapper                       |              10.479 | Unrelated smoke failed before native tests ran |
| Selected native, two build invocations |               3.102 | 17 native tests passed                         |
| Selected native, one build invocation  |               1.294 | 17 native tests passed                         |

The original compiler build and smoke phases cost 8.431 and 2.046 seconds. The
intermediate native phases cost 1.776 and 1.317 seconds, with a 4 ms test body.
These are single warm-cache samples, not cold builds or retained source edit
measurements. The failed original run is not a passing baseline. Logs and phase
timings are in `build/bench/iteration-resume-20261013/`. CLI regression tests
exercise selection, compiler paths, toolchain rejection and default/full-gate
scope using a temporary Zig executable, without compiling the compiler.
Development `native-run` wall time includes its compilation.

## Fourteen iteration hills, 14 October 2026

This batch preserves the pending compiler work. It is implemented locally but
**not release-qualified**: imported staging still returns `InvalidArtifact`, and
the two-stage budget recovery example still returns `ownership_unproved`.
Neither acceptance law was weakened. The full gate catches a recorded failure in
0.84 s (0.06 s cached development build, 0.78 s preflight), before LLVM work.

| Hill | Change                                                                                                            | Verification and limit                                                                                                                                                                                              |
| ---- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Separate full rolling/summary semantics from minimal exhaustive ownership fixtures.                               | 404 and 832 allocation faults, plus success runs, all checked. Integrated sweeps: 0.53/2.90 s Safe/noLLVM. Earlier LLVM timings are not a paired comparison.                                                        |
| 2    | Build only fixtures needed by selected guest files; whole directories include all fixtures.                       | Zero fixture steps for staging/usage/budget tests. The isolated initial-build sample did not show a wall-time win because fixture compilation overlapped the compiler.                                              |
| 3    | Move lexer, symbols and syntax-diagnostic laws/helpers into test modules.                                         | 20 laws relocated; actual test edit/revert leaves compiler identity and executable hashes unchanged. Other inline tests still contribute exact production bytes; their extraction remains future work.              |
| 4    | Independently compile syntax/types/runtime/checker/evaluator/backend/retained suites.                             | Integrated inventories union to exactly 1,803 named laws. Original 1,799 named laws preserved, with four new laws; 16 empty import-only registrations removed. Independent Safe/noLLVM compilation: 0.88–6.85 s.    |
| 5    | Run two native shards from one compiled binary, each with its own validating allocator.                           | Exact partitions checked; assertions, leaks, logged errors and panics propagate failure. Eleven integrated selected laws pass across both processes. Full execution speedup is unmeasured.                          |
| 6    | Use bounded 4 KiB scratch for ownership proofs, falling back to the caller allocator.                             | Original rolling case: 2,829→2,123 allocations (25% fewer), 38.646→37.930 ms warmed median. Summary: 3,492→3,013, 54.049→53.554 ms. Wasm hashes identical. Overflow/OOM and depth-160 laws pass.                    |
| 7    | Compile native tests first, then overlap release compilation and native execution with bounded jobs.              | Failure cancels and reaps the other process tree. `--serial` permits comparison. Full wall-time/RSS/swap qualification awaits repaired preflight laws.                                                              |
| 8    | Configure inference budget on the existing CLI/server, eliminating the second compiler.                           | Default equals explicit 1,000,000 identity; a reduced limit has a distinct identity and cannot reuse a production cache success. CLI rejection passes; existing retained recovery still fails earlier on ownership. |
| 9    | Save failed guest files from JUnit and run them immediately after the development build.                          | Real full-gate retry catches the known failure in 0.84 s. Failed files persist in the chosen timing directory. Full final guest coverage is unchanged.                                                              |
| 10   | Cache successful local lint results using tool/configuration and transitive source contents.                      | Combined unchanged local check: 0.214 s. Isolated leaf edit: 0.127 s; shared edit affecting 214 files: 4.634 s; revert: 0.188 s. Complete lint always scans all 403 files (zero findings).                          |
| 11   | Resume successful native phases only after exact input/toolchain/binary/log verification.                         | Full-runner fixture proves guest repair reuses both native phases and a native edit reruns both. Missing/changed evidence and aborted/failed runs cannot qualify. Real resumed LLVM gate remains unmeasured.        |
| 12   | Preserve ownership rejection function/fallback, owned detail, useful source location and failed generated source. | Existing stage failure now points to bytes 155–185 and explains missing ownership roots; the test prints its retained `main.blot` path.                                                                             |
| 13   | Read production fingerprint inputs once; remove duplicate budget fingerprint/build work.                          | Exact source bytes and configuration still define identity. ABBA revealed an additional unchanged incremental-build cost; cached development builds are now the default (details below).                            |
| 14   | Add whole-run/per-phase budgets, heartbeats, process-group cancellation and durable partial reports.              | A deliberately uncooperative descendant is killed; partial logs survive. Development defaults: 60 s total/phase. Full gate: 900 s total, 600 s per phase. Timeout is failure, never a completed check.              |

The development-build ABBA experiment uses two samples per mode with distinct
actual production edits, followed by exact reverts. Zig 0.17.0, Safe/noLLVM,
filesystem/global caches warm; these are not cold-machine measurements:

| Seconds, mean of two | Ordinary artifact cache | Forced incremental |
| -------------------- | ----------------------: | -----------------: |
| Unchanged            |                   0.026 |              3.601 |
| Production edit      |                   4.322 |              3.909 |
| Revert               |                   0.310 |              3.952 |

Ordinary caching wins repeated checks/reverts; explicit incremental mode retains
its roughly 10% advantage for this actual edit. The complete cached development
wrapper measured 0.061 s in isolation and 0.05–0.06 s in the integrated checks.
The production allocation experiment uses 16 warmed samples per case in ABBA
order. Its small elapsed-time gains concern backend compilation, not whole
project or retained-server performance.

Useful commands:

```sh
deno task test:compiler:dev --native-suite checker --native-filter 'test name'
deno task test:compiler:dev zig-native/tests/inference_budget_config.test.ts
deno task build:compiler:dev --incremental --fixtures=
deno task lint:zig:dev
deno task test:native:inventory
deno task test:compiler --resume --native-shards 2 --build-jobs 2
```

Use the same `--timings-dir` for resume and recent-failure preflight state.
Automatic preflight remembers up to eight existing failed files. Explicit
`--preflight` selections are all retained, so feature selections cannot displace
a remembered failure or silently lose a ninth requested regression. The
nine-file runner control fails at its last regression before LLVM work in 0.8 s.
`--force-native` executes the native laws again; `--oom-profile` can reuse only
a verified completed profiled run. Each invocation retains its own logs and
report; the directory's `timings.json` points to the latest invocation. Reports
mark reused phases `resumed`, separately from Zig artifact/run cache hits.

Evidence: `build/bench/iteration-hills-20261014/` contains integrated phase
logs, inventories, lint results and source/binary pins. `build/` beneath it
holds raw build ABBA samples, test-only edit hashes and original/current named
inventories; `allocations/` holds raw backend samples, probes, OOM logs and
pins. The complete harness passes 27 tests. Eleven focused native laws and all
inventories pass; complete compiler qualification remains blocked as described
above.

## Continuation, 14 October 2026

The stage-chain ownership blocker is repaired in the working tree; both budget
laws and both generic-word guest groups pass. Imported staging admission is
being strengthened separately. The full gate has not yet qualified this batch.

Another 24 inline laws and their helpers moved into separate test modules for
runtime flags, layout bridging, project frames and numeric contracts. All 25
original names are preserved: the numeric graph oracle remains beside its
private implementation. No production API was expanded. The relocated laws pass
in 1.88 seconds, including compilation and exhaustive fault tests. After the
initial compiler rebuild, an actual test edit/revert takes 0.057/0.055 seconds
and preserves both executable and compiler-identity hashes. This brings the
extracted total to 44 laws; other inline tests remain.

An unmatched native filter now fails explicitly, while an empty individual
execution shard remains valid. The runner regression covers both cases. Local
lint through the documented task now has the write permission its cache needs;
318 affected production files pass with zero findings after extraction.

Native resume now inventories compilation inputs and the actual runtime corpus
roots instead of every Git file. It reads 606 files rather than 983 in the
current tree. An actual `CONTINUE.md` update preserves the key; tests prove
guide, build configuration, ignored source, new source and sibling corpus edits
still invalidate it. Sixteen runner/journal regressions pass. The two
inventory/hash samples take 157/94 ms; the main benefit is avoiding a native
rerun after writing qualification notes. Future native runtime fixture roots
must join this manifest.

Two five-pair Safe/noLLVM fanout screens retain identical Wasm and deterministic
work counters. Fresh/restart CPU ratios change from 0.972/1.063 to 1.058/0.931
on repetition; there is no stable directional result. This synthetic screen is
not captured-project or LLVM/Fast qualification. Exact binaries, samples,
commands and test-edit hashes are under
`build/bench/continuation-20261014/{control-fanout,control-fanout-repeat,test-extraction}/`.

## Combined gate diagnosis, 14 October 2026

The second continuation gate took 653.382 s before five native-law failures.
Preflight/build/harness work preceded a 304.396 s native compilation; native
execution took 311.485 s while the 246.729 s release build overlapped it. The
1,849-law run selected all laws, with 1,844 passes, zero leaks/logged errors and
1,125 complete allocation sweeps plus two expected-error harness laws. It did
not qualify the compiler or reach the complete guest phase.

Tiny system-command and real native-runner probes both execute two shards
concurrently, including the installed-artifact dependency shape. The long run's
shard overlap is not yet established. The runner now emits one
`BLOT_NATIVE_SHARD` timing record per executing shard (monotonic start/end and
selected count); list mode and failure behavior stay unchanged. Its harness
passes. Measure the next complete run before changing the scheduler. Logs and
probe sources are under `build/bench/continuation-20261014/`.

The pinned analyzer can report zero findings with no Zig on PATH because it
omits standard-library diagnostics. Full root checking exposed three deprecated
allocator calls after isolated zero reports. Lint now requires a successful
backend doctor check and an available standard library before every mode. Local
cache keys hash resolved Zig, stdlib and backend inputs alongside the analyzer.
Missing/incompatible tools reject before either checking or reusing a pass. A
real one-file cache-hit screen rises from 47.4 to 291.2 ms; the added 243.8 ms
is explicit. Full mode performs the prerequisite check without content hashing.
Evidence: `build/bench/continuation-20261014/lint-backend/`.

The next frozen run passes all 1,864 native laws and 1,131 complete allocation
sweeps plus two expected-error harness laws. Both native shards start within
0.133 ms; their 932 laws take 137.832 and 178.242 s. Native execution is 178.279
s overall, so shard serialization is ruled out for this run. Do not attribute
the difference from the earlier failed run to a scheduler change.

The 619.700 s gate still fails one guest cache-reuse law; a complete guest sweep
gives 1,165 passes and that one failure. Native compilation takes 299.096 s,
while release compilation takes 267.144 s and starts only after native
compilation. Those independent builds now start together, with native execution
still depending on native compilation. The serial option is unchanged. The next
combined gate will measure the actual effect; no speedup is claimed from adding
their isolated times. Exact records:
`build/bench/continuation-20261014/full-gate-final/`.

Another 39 type-store laws and 16 helpers now live in `types_tests.zig`,
removing 986 test/helper lines from the production module. Three laws that need
private methods remain inline; no API was expanded. All 42 law bodies and the
moved helper bodies remain byte-identical. The types suite passes 72 laws; its
old/new inventories agree after the recorded module-prefix mapping. The
working-backend analyzer checks 417 files with zero findings.

The actual `deno task build:compiler:dev --fixtures=` baseline, test-only edit
and revert all hit the executable cache and preserve executable/identity hashes.
Zig reports 6–11 ms for the cached compile step, not the whole command. An
explicit `-fincremental` control still recompiles for about 3 s despite
unchanged output; use the ordinary development task for test-only changes.
Evidence: `build/bench/continuation-20261014/types-test-extraction/`.

## Qualified combined run, 14 October 2026

The repaired batch passes all 1,869 native laws and 1,170 guest/client tests in
564.842 s. It retains 1,133 complete allocation sweeps and two expected-error
harness laws, with zero analyzer findings across 417 files. Release/native
compilation now overlap (224.611/309.869 s); native execution follows its
compile and takes 177.299 s. The two shards start 0.303 ms apart and run 934/935
laws in 135.191/177.261 s. A process sample records both LLVM workers running
and about 5.4 GB combined RSS. The preceding 619.700 s failed batch had
different source and tests; this is not a controlled scheduler speedup
measurement.

The overlap ordering regression passes with the current runner and fails in
4.524 s against the preceding runner. The original serial option remains. Logs,
source pins and the negative control are in
`build/bench/continuation-20261014/{full-gate-reuse-repaired,build-overlap-control}/`.

The qualified release's three captured-project pairs take 26.217 s. Against
qualified `b4fb67c…`, geometric paired fresh/edit/revert CPU ratios are
0.9990/0.9178/0.9117. Exact within-version fresh/reuse checks pass;
cross-version Wasm differs. Source fuel stays 70,330 and constant receipt
activity is zero. Full measurements and limits are in
[the continuation qualification](CONTINUATION_QUALIFICATION.md#qualified-continuation-14-october-2026).

The subsequent current-source diagnostic completes fresh/edit/revert within a
60-second cap and changes the next hill. The 57,019-step constant has a nominal
result excluded before receipt recording; no inference query runs inside its
value work. A different constant's principal query already hits its existing
owner on retained edits with no ledger changes. The older 177-step inference
trace does not identify this batch's first blocker.

The next measured experiment should own compound nominal constant values, slot
publication and source-fuel replay. Existing graph transport cannot grant that
authority, and earlier dense graph indexes cost too much. Preserve ready reads,
aliasing, captures, views, quota ordering and rollback while measuring net saved
work. This is a diagnostic conclusion, not a new cache implementation or timing
claim. Exact diagnostic source, logs and pins:
`build/bench/continuation-20261014/constant-current-diagnostic/`.

## Generative artifact failure sweeps, 14 October 2026

Compilation/encoding failures and decoded artifact validation failures now run
as separate complete sweeps. Artifact faults reuse immutable encoded bytes;
every existing mutant and all 4,362 failure indices remain covered. The two
focused native laws fall from 25.264 s to 17.924 s in the private development
screen (ratio 0.7095), with 17.795 s after integration. All four phase sweeps
complete with no leaks or failures. Exact source, profiles and counts are in
`build/bench/finish-program-20261014/generative-test-cost/`. This is a test
runtime measurement; the final combined compiler gate remains outstanding.

## Generative presence scans, 15 October 2026

Repeated source guards raised the captured retained specialization phase from
about 122 ms to 2,434 ms. Session and retained Gate now summarize feature
presence once over their immutable source owners. Negative presence skips only
the deep generative scan; current/old root and source ownership stays mandatory,
and positive presence preserves the exact deep guards. No receipt, Core schema
or inference authority is added.

One development pair lowers edit/revert CPU from 12,840/12,550 to 10,690/10,270
ms (ratios 0.833/0.818), with unchanged 24,340 ms fresh CPU. Specialization is
128 ms; inference regions, allocation counts and bytes agree. Both sides retain
exact fresh/edit/revert Wasm, 70,330 source steps, eleven constant hits and
61,383 replayed steps. Peak RSS is 304,044/304,980 KiB. Five integrated native
laws, ten receipt/generation guest groups and selected 233-file analyzer checks
pass, including complete owner/Gate allocation failures. Exact source, profiles
and own-side binary pins are in
`build/bench/finish-program-20261014/guard-presence/`. This single development
pair does not establish release performance or finish task 093. The rejected
call-proof header experiment remains private.

The List proof/runtime law now runs its three independent, fully destroyed
fixtures as separate complete OOM sweeps. One sequential Safe/noLLVM pair cuts
sweep time from 46.068 to 14.711 seconds (ratio 0.3193), preserving all 3,968
allocation failures and every input/assertion. Successful discovery runs
increase from 3,969 to 3,971. Production behavior and compiler identity are
unchanged. Exact sources, raw profiles and pins are in
`build/bench/finish-program-20261014/list-test-cost/`. This is a test-only
measurement; the final full compiler gate remains outstanding.

Associated bodies without get/set/proof guards now skip numeric preparation. The
flag is recorded during existing node visits. An eight-helper allocation
discovery reduces attempts from 2,341 to 2,286 and bytes from 1,086,888 to
1,081,696, all freed. Eight paired 80-associated-helper workloads preserve exact
Wasm, work and reuse; generation stays near parity or improves slightly. The
two-file delta and raw measurements are in
`build/bench/finish-program-20261014/associated-candidate/`. No new whole-Core
scan or cache is added; final qualification remains outstanding.

## Final combined measurement, 15 October 2026

The qualified full gate takes 697.812 s, with the source manifest
3548546cb8660905de9a83922bab67270376a2b955f840f2bc7cf13fcefa53ec. Release/native
compilation overlap at 336.370/386.708 s. Native execution takes 258.509 s;
231.904/258.475 s shards start 0.063 ms apart and select 1,111/1,112 laws. All
2,223 pass, including 1,366 complete allocation sweeps and two expected-error
harness laws. Guest execution takes 28.867 s for 1,404 tests; all 455 analyzer
files are zero.

The preceding failed run genuinely serialized its shards for 479.533 s. Fresh
one-second probes using the current runner/install graph overlap in both default
and forced modes, so no unconditional ordering bug was established and no
scheduler code was changed. The final run enables full OOM profiling/forced
execution. Different source/options prevent a controlled speedup claim. LLVM
compilation remains the largest measured iteration cost; use focused noLLVM
checks between final gates. Evidence:
`build/bench/complete-program-20261015/final-proof-repaired-gate/` and
`build/bench/complete-program-20261015/native-launch-probe/`.
