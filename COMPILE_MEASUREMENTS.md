# Compile and compiler-build measurements

Latest qualification:
[CT103/CT104 inference reuse and row normalization](zig-native/CT103_QUALIFICATION.md).
Seven alternating pairs against `5412320` show **24.8% less literal-edit CPU**,
**4.2% less body-edit CPU**, and **6.1% less fresh-game CPU** with exact
outputs. Devtools is effectively unchanged. Literal/body wall medians are 7.60 /
12.46 s on the loaded shared host; the body wall median does not improve. The
body 20% and sub-second targets remain open. First-edit checking and previously
unseen later edits are reported separately. The final build also fixes portable
restart replay, includes `faf3f78` and passes a separate 2,551-law exhaustive
native gate, 1,654 guest checks, zero lint and exact frozen-output parity. That
integration check is not a new performance comparison. The matching CLI and
native compiler are installed.

Historical CT102 qualification:
[partial call-memo replay](zig-native/CT102_QUALIFICATION.md) showed 25.1% less
literal CPU against CT97. Earlier measurements below retain their original
baselines; their ratios are not cumulative current measurements.

Historical follow-up:
[CT97, executable reuse and temporary scratch](zig-native/CT97_QUALIFICATION.md).
Seven alternating release pairs reduce fresh game CPU by **32.5%** against CT96;
median build wall falls from **13.60 to 8.68 s**, with identical Wasm. The
original baseline and CT96 measurements below remain historical references; use
the latest qualification for current comparisons and remaining targets.

Follow-up: [CT96 is qualified](zig-native/CT96_QUALIFICATION.md). Computing
spawn contract presence once per compilation reduces fresh game CPU by 28.6% in
seven alternating release pairs (17.24 → 12.16 s median build wall), with
identical Wasm. The measurements below preserve the preceding baseline and its
original profiling evidence; use the follow-up record for the optimized
candidate.
The [post-CT96 review](PERFORMANCE_REVIEW.md) updates the next hills with caller
attribution, retained-admission analysis and 33 new exhaustive sweep profiles.

23 October 2026 baseline. This identified repeated whole-program scans in
`prepareSpawnApplication`, owning **27.6% of sampled CPU**, as the first
application-compile experiment. For compiler development, keep ordinary Zig
caching: real source edits build in about **3.4 seconds**, while `-fincremental`
makes unchanged builds much slower without a useful real-edit gain in this
screen.

The implementation queues are [compile-time hills](COMPILE_HILLS.md) CT95–CT101
and [compiler-build hills](BUILD_HILLS.md) BT1–BT5. That baseline checkpoint
added measurement tools and evidence; it did not implement those optimizations
or close the remaining [completion plan](FINISH_PLAN.md).

## Scope and reproducibility

All application measurements use the already qualified release at `63c931f`,
following the derive/budget commit `58e00c3`. Compiler SHA-256:

```text
fec30aece1dccd18f4709a06a96d70f42e9cd0682f843bc53fa8e3f99fa0ab31
```

The two benchmark variants use this **same executable**. The baseline has
profiling disabled; the candidate has it enabled. These pairs measure profiling
overhead, not an optimization or a comparison with a previous compiler.

Host: Ryzen 7 7800X3D, 16 logical CPUs, Linux 7.2.9, Zig 0.17.0, Deno 2.9.7. The
554-file snapshot freezes gdev, Ink, assets and the configured standard library.
Its unchanged `pen.json` selects a 200,000,000 inference budget and an explicit
text asset import. The benchmark now preserves these settings and rejects a
missing configured standard library. Inputs and compiler bytes are checked
before and after measurement. The historical 130-file manifest remains
unchanged; this workload has its own manifest and output pins.

Fresh means a new compiler process and project session for each sample. The
timed interval is the build request, excluding process start and project open;
OS page caches are not flushed. CPU is Linux process user plus system ticks,
including exited workers, with 10 ms resolution. Live-thread scheduler CPU is
retained separately. Peak RSS is the process high-water mark, so retained phases
cannot attribute it to just one edit. Phase clocks measure wall time, not CPU.

Raw reports, samples, input/output hashes, build logs and verification records
are preserved in
[the evidence archive](zig-native/measurements/compile-cost-2026-10-23.tar.gz).
Its `SHA256SUMS` covers each payload file. Private application sources, compiler
binaries and Zig caches are excluded. The local working evidence is under
`build/bench/compile-cost-20261023`; reproducing gdev needs the matching private
snapshot. The public `edit_suite` workload exercises the tooling without it.

## Compiling gdev

Three alternating ordinary/profiled pairs per entry:

| Entry / mode       | Median wall |      Wall range | Median CPU | Median peak RSS |
| ------------------ | ----------: | --------------: | ---------: | --------------: |
| Game, ordinary     |    16.292 s | 16.146–17.013 s |   16.430 s |       476.6 MiB |
| Game, profiled     |    17.469 s | 16.304–18.265 s |   17.240 s |       476.9 MiB |
| Devtools, ordinary |     0.924 s |   0.923–0.943 s |    0.960 s |       169.0 MiB |
| Devtools, profiled |     0.936 s |   0.936–1.024 s |    0.970 s |       164.8 MiB |

Median paired CPU overhead from phase profiling is **4.73%** for the game and
**2.11%** for devtools. Use unprofiled pairs for acceptance decisions. Three
pairs identify major costs; future speedup claims require the seven-pair gate.

Profiled game phase medians:

| Exclusive phase          |       Wall time |
| ------------------------ | --------------: |
| Backend                  |        15.944 s |
| Frontend checking        |         1.161 s |
| Lowering                 |         0.123 s |
| Validation               |         0.107 s |
| Freezing                 |         0.075 s |
| Lexing / parsing         | 0.022 / 0.013 s |
| Assets / loading / other |   about 0.029 s |

Each sample's exclusive clocks partition its profiled wall interval within
microsecond rounding. Separately calculated medians need not sum exactly. Within
the backend, the main child clocks are **9.642 s inference**, **5.077 s constant
preparation**, 0.206 s evaluation, 0.089 s layouts and 0.056 s specialization.
Assembly is only 0.181 s. These child clocks are already inside the backend
phase and must not be added to it. Region observations are inclusive and
overlapping. Raw clock keys end in `_us`; the `costs.*_wall_ms` summaries
convert their values to milliseconds while retaining the raw names.

The first profiled game sample requests 4,216 MiB cumulatively across 12.42
million allocations; this is allocation traffic, not resident memory. Frontend
checking alone accounts for roughly 1 GiB and 7.65 million allocations.
Inference records 18,386 regions and 237,669 scopes, with a largest region of
33,828 scopes. Large-region and allocation costs deserve their own follow-up
after the call-preparation scan is removed.

Two independently sampled game builds contain 1,370 complete GDB sampling
intervals. CPU-weighted stacks cover **99.47%** of their measured process CPU,
with no missing or truncated stacks inside those intervals. Boundary intervals
are excluded. Idle threads have zero weight; the older unweighted stack table is
only an inventory.

| Self CPU location                                | Sampled CPU | Interpretation                                                        |
| ------------------------------------------------ | ----------: | --------------------------------------------------------------------- |
| `backend_emission.Owner.prepareSpawnApplication` |      27.62% | Repeated scan over every unit's bindings at ordinary call preparation |
| `effects.Store.node`                             |      12.38% | Trivial load; inspect caller traversal and locality                   |
| `effects.Store.replacement`                      |       6.60% | Chronological version-chain traversal                                 |
| `types.Store.resolveOperationRow`                |       4.86% | Effect-row resolution                                                 |

The first hotspot is the loop at
[backend_emission.zig](zig-native/src/backend/backend_emission.zig#L7553). Of
its 9.276 CPU seconds across both sampled builds, 8.217 seconds occur under
`Generator.constant` and static-data preparation in the stack. Thus the broad
constant clock includes preparing runtime callables. Removing the scan and
reducing constants are not independent savings. CT96 should prepare immutable
capability-presence/index information once per generator, then preserve the
existing positive-path authority checks. Reprofile afterward.

### Retained edits

One ordinary/profiled pair screens retained game behavior, separately from the
fresh campaign. It is not a percentile or a stable speedup estimate. The
ordinary fresh control in this interval took 19.412 s; compare edits to that
interval, not directly to the earlier 16.292 s median.

| Ordinary retained action |              Wall |                                              CPU |
| ------------------------ | ----------------: | -----------------------------------------------: |
| Populate                 |          20.149 s |                                         19.930 s |
| No-op                    |           20.2 ms |                                            10 ms |
| Trivia edit / revert     |    20.8 / 17.8 ms | tick resolution is too coarse for precise ratios |
| Literal in body / revert | 18.383 / 17.280 s |                                18.590 / 17.490 s |
| Body change / revert     | 17.407 / 17.396 s |                                17.600 / 17.560 s |

Literal/body edits recheck one module but offer **zero backend candidates** and
rebuild **4,266 named functions and 1,424 closures**. CT98 should explain the
first retained-seed rejection before changing reuse admission. Every measured
edit matches its fresh control, and every revert restores the original output.
The two unchanged entry hashes are:

```text
game     5230712 bytes  7cdefcb761628a6043e04d3a515e85e77074914d3ba67d275ec1672e2a09d071
devtools 1107529 bytes  229a8b1833c5cf2505c6d325422082e4242cf0b9e6ee8426e233b46028de75c3
```

## Building and checking the compiler

Isolated source copies compare ordinary caching with `-fincremental`, always
Safe/noLLVM. Each mode has its own initially empty Zig global/local caches.
Three rounds use distinct leaf-constant, checker-diagnostic and native-fixture
edits, with exact source reverts. Both the compiler and complete native test
inventory are compiled for every cell. Modes run sequentially, not as
alternating pairs; small differences are inconclusive.

Median wall seconds across the three rounds:

| Change           | Ordinary compiler | Ordinary native compile | Incremental compiler | Incremental native compile |
| ---------------- | ----------------: | ----------------------: | -------------------: | -------------------------: |
| Unchanged        |             0.015 |                   0.016 |                2.986 |                      6.112 |
| Leaf edit        |             3.387 |                   5.511 |                3.487 |                      5.770 |
| Checker edit     |             3.456 |                   5.330 |                3.388 |                      6.211 |
| Test-only edit   |             0.015 |                   5.561 |                3.400 |                      5.817 |
| Leaf revert      |             0.319 |                   5.614 |                3.359 |                      5.993 |
| Checker revert   |             0.300 |                   5.442 |                3.430 |                      5.817 |
| Test-only revert |             0.016 |                   5.804 |                3.269 |                      5.804 |

Empty-cache build-system initialization (`zig build --help`) costs **56.099 s**
in ordinary mode and 69.107 s in incremental mode. Repeating it costs 10–11 ms.
After initialization, the first compiler artifact takes 5.014 / 6.079 s and the
native artifact 5.259 / 7.624 s. Do not attribute the entire empty-cache command
to compiling Blot's source. Stable writable caches are the immediate iteration
win; explicitly enabling incremental mode is not justified by this result.

The final report has all 92 measurement cells and zero failed build commands.
Compiler source identity and the 2,539-test inventory are restored after edits;
three budget regressions execute on each restored native binary. CPU, peak
single-process RSS, commands, Zig summaries and executable hashes remain in the
raw report. Two earlier controls stopped on an overly strict executable-byte
equality assertion. Rebuilt unstripped executables can differ even when source
identity/inventory match; their hashes remain visible. The second control was
resumed after correcting that assertion, with previous results preserved. These
runs are build measurements, not full behavioral qualification.

Two warm `check:dev --area type-effects` cycles pass in **4.715 and 4.640 s**.
Each compiles the complete 2,539-test inventory, executes 12 native laws with
sampled allocation failures and nine guest checks, then runs formatting, types
and local Zig analysis. The second run's breakdown is:

| Work                                  |                    Wall |
| ------------------------------------- | ----------------------: |
| Development compiler wrapper/build    |                 0.189 s |
| Native compile / inventory            |         0.016 / 0.011 s |
| Selected native execution             |                 0.734 s |
| Guest checks                          |                 1.539 s |
| Formatting / types / Zig lint         | 0.067 / 0.720 / 0.512 s |
| Input and executable identity checks  |                 0.835 s |
| Zig version / remaining orchestration |                 0.015 s |

Both cycles already had warm build caches; neither is an edited-cycle or p95
claim. They ran from the qualification snapshot with the current compiler source
and measurement scripts, using stable writable caches. The reports explicitly
leave full qualification pending. BT1's cache-hit target and BT3's warm target
are met on this host; edited end-to-end cycles remain to be measured.

The preceding
[qualified release gate](zig-native/ASSOCIATED_WORK_QUALIFICATION.md) takes
669.831 s overall. Native exhaustive execution takes **595.972 s**, while the
LLVM release build takes **194.378 s** and overlaps native work. They must not
be summed. Four native shards take 558.32, 595.75, 586.06 and 554.94 s; perfect
rebalancing would save only about 4% of the native interval. The three slowest
allocation-failure laws take 86.22, 82.46 and 72.14 s: generic-accessor staging,
retained State captures, and request-backend teardown respectively. BT4 targets
repeated setup/work inside those fixtures while preserving every fault case. Do
not weaken exhaustive qualification to improve a timing number.

## Running the measurements

Keep private snapshots and new pins under ignored `build/`. To repeat the
existing local comparison:

```sh
deno task bench:compile \
  --baseline build/bench/compile-cost-20261023/baseline/blotc \
  --candidate zig-native/zig-out/bin/blotc \
  --snapshot build/bench/compile-cost-20261023/snapshot \
  --manifest build/bench/compile-cost-20261023/manifest.json \
  --hashes build/bench/compile-cost-20261023/wasm.json \
  --workload game,devtools --runs 3 --no-retained --candidate-profile \
  --out build/bench/compile-cost-next
```

Use `--write-manifest --write-hashes` only to initialize deliberately new pins.
For a real optimization comparison, omit `--candidate-profile`, use seven pairs
and `--guard-cpu`, and separately measure retained scenarios. To sample CPU:

```sh
deno task profile:compile --blotc zig-native/zig-out/bin/blotc \
  --snapshot build/bench/compile-cost-20261023/snapshot \
  --manifest build/bench/compile-cost-20261023/manifest.json \
  --workload game --runs 2 --min-ms 15 --max-ms 30 \
  --out build/bench/compile-stacks-next
python3 scripts/bench/summarize_stacks.py build/bench/compile-stacks-next
zig version
deno task bench:compiler-build --out build/bench/compiler-iteration-next --runs 3
```

The build experiment requires Linux, Python 3.11+ and Zig 0.17.0. It edits only
its isolated copies. `--resume` is for interrupted measurements with unchanged
pins, not qualification reuse. For ordinary development on this host, set stable
writable cache paths from the repository root before running `check:dev`:

```sh
export ZIG_GLOBAL_CACHE_DIR="$PWD/build/task-regions-global"
export ZIG_LOCAL_CACHE_DIR="$PWD/build/task-regions-local"
zig version
deno task check:dev --area type-effects
```

The benchmark changes are checked by the tooling harness and a complete public
`edit_suite` fresh/edit/revert run. No compiler source changed in this
checkpoint; its existing full qualification remains the release evidence.
