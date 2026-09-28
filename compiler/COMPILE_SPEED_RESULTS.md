# Compile-speed experiments

The [active plan](../PLAN.md) measures small changes before expanding the
compiler redesign. The latest installed Bend-source change updates pending
requirements from the selected choice: native gdev cold compilation improves
from 37.65 to 33.11 seconds and body edits from 37.75 to 33.23 seconds, both
12%, in three alternating pairs each. Earlier batches improve string and numeric
traversal, stop completed searches, and skip retained operation prefixes. Host
conditions changed between batches, so each result uses its own matched control;
the overnight difference from the earlier 62.3-second result is not attributed
to source changes. Generated C and JavaScript remain unchanged. These changes
are separate from the M3 redesign, whose game speedup remains unproven. The
earlier experiments in this report use the JavaScript compiler.

## Native regression: traverse string indexes without branch closures

2026-09-27: reproduced the reported 124-second gdev compile at 126.5 seconds
with the installed native executable. A fresh, unchanged-source Bend 2.0.32
control still took 127.5 seconds and emitted identical Wasm.

`Index.find_work` previously made two closures per Patricia branch, copying the
key and remaining suffix into both. The Bend implementation now chooses the
child as data and moves the key and suffix through one tail loop. A leaf
constructs `Some` only after equality succeeds. The complete key comparison,
Unicode behavior, suffix cursor, and persistent map semantics are retained. The
emitted C and JavaScript are used unchanged; native lookup becomes a direct loop
instead of using the continuation dispatcher.

Both sides use matching Bend 2.0.32, Base, and loader sources. Both also split
the pure native frame type from the foreign transport effects so the newer proof
checker can validate the compiler without importing foreign IO. The performance
delta is confined to `compiler/index.bend`.

The frozen current game has 25 modules and produces 1,161,014 Wasm bytes. Each
sample starts a fresh native process with four workers, 100,000 const steps, and
`analysis: false`, matching gdev's stateless compile call. Parsing and process
startup are measured separately. Cold results are medians of three alternating
A/B, B/A, A/B pairs. The edit is one additional B/A pair changing only the
daylight function's ambient-red constant in the frozen input; live game files
were not edited.

| Request / measure                |   Control | Bend loop | Reduction |
| -------------------------------- | --------: | --------: | --------: |
| Cold compile wall, median        | 126.913 s |  85.363 s |     32.7% |
| Cold native CPU, median          | 128.550 s |  87.050 s |     32.3% |
| Body-edit compile wall, one pair | 124.409 s |  85.690 s |     31.1% |
| Body-edit native CPU, one pair   | 126.510 s |  87.910 s |     30.5% |

All six cold artifacts match exactly, and both edited artifacts match exactly.
The cold hash also matches the original installed compiler. Full Bend proof
passes, along with 24 lookup/dependency tests and 56 native parity, protocol,
session, and output tests. The native ownership regression passes with one and
four workers. Both artifacts also pass the actual game's create/first-frame
checks: schema 8, 2,778 draws, and 10 solids; the edited ambient-red component
changes from 0.29499999 to 0.39499998. The verified source, native executable,
and matching JavaScript modules are installed in the live checkout.

The existing cold benchmark now supplies the `gdev/` package prefix and requests
Wasm-only output to match the application.

Lookup-only compilation still takes about 85 seconds; the following comparison
experiment reduces it further. The historical sub-second result used a smaller
game and native generated-C transformations that are no longer used. These
measurements do not isolate every cause of that historical regression.

Evidence: [paired samples](../build/gdev-regression-20260927/pairs.json),
[summary](../build/gdev-regression-20260927/pairs-summary.json),
[source and output identities](../build/gdev-regression-20260927/artifacts.json),
[lookup tests](../build/gdev-regression-20260927/candidate32-lookup-tests.log),
[native tests](../build/gdev-regression-20260927/candidate32-native-tests.log),
[guest checks](../build/gdev-regression-20260927/guest-checks.log), and
[lookup-only installation](../build/gdev-regression-20260927/integration.json).

Re-run cold comparisons against the saved matching-version control:

```sh
deno run -A compiler/gdev_cold_bench.ts \
  build/gdev-regression-20260927/blotc-control32 \
  build/gdev-regression-20260927/blotc-candidate32 3 4
```

## Native comparison: retain roots during character traversal

2026-09-27: the next source change keeps both owning string roots alive while
`M.name_equal_walk` traverses separate cursors. The walk returns the Boolean
result with the roots; `name_equal_result` then releases the roots. Bend 2.0.32
emits borrowed character reads without per-character allocation or release in
this loop. No emitted code is edited.

The previous comparator already receives borrowed reads in a small standalone
program, but emits consuming traversal in the full native compiler. Retaining
the roots makes the lifetime explicit in that full context. See
[the performance limitation](../BUGS.md) and its saved source/output evidence.

This comparison uses the lookup-only compiler above as its control. Both sides
retain matching Bend 2.0.32, Base, loader, frozen game inputs, and compile
options. The only Bend source difference is `compiler/model.bend`. Three fresh
process pairs alternate B/A, A/B, B/A, followed by one B/A body-edit pair.

| Request / measure                | Lookup only | Retained roots | Reduction |
| -------------------------------- | ----------: | -------------: | --------: |
| Cold compile wall, median        |    88.151 s |       78.817 s |     10.6% |
| Cold native CPU, median          |    90.100 s |       80.320 s |     10.9% |
| Body-edit compile wall, one pair |    86.228 s |       75.920 s |     12.0% |
| Body-edit native CPU, one pair   |    88.240 s |       77.770 s |     11.9% |

Every pair improves wall and CPU time. Cold control samples span 84.6–92.1
seconds, while candidate samples span 78.5–79.9 seconds; compare adjacent pairs
within this batch rather than treating the earlier lookup-only median as its
control. The cumulative 126.9-to-78.8-second observation spans both experiments,
not a single original-control/final-candidate paired batch.

All six cold artifacts and both edited artifacts retain the earlier exact
hashes. Full Bend proof, the same 80 targeted tests, and both native string and
ownership regressions at one/four workers pass. Both final guest artifacts also
pass the game's create/first-frame checks with the expected ambient change,
schema 8, 2,778 draws, and 10 solids. A separate small JavaScript comparison
screen stays around 0.5 seconds on both sides; it establishes no game-wide JS
speedup. The source and all matching native/JS artifacts are installed.

This stage left native cold compilation around 79 seconds. The following
traversal experiment reduces it further; sub-second compilation has not been
restored.

Evidence: [paired samples](../build/gdev-regression-20260927/borrow/pairs.json),
[summary](../build/gdev-regression-20260927/borrow/pairs-summary.json),
[source and output identities](../build/gdev-regression-20260927/borrow/artifacts.json),
[proof](../build/gdev-regression-20260927/borrow/proof.log),
[lookup tests](../build/gdev-regression-20260927/borrow/lookup-tests.log),
[native tests](../build/gdev-regression-20260927/borrow/native-tests.log),
[guest checks](../build/gdev-regression-20260927/borrow/guest-checks.log), and
[final installation](../build/gdev-regression-20260927/borrow/integration.json).

Re-run against the saved lookup-only control on the current game checkout:

```sh
deno run -A compiler/gdev_cold_bench.ts \
  build/gdev-regression-20260927/blotc-candidate32 \
  generated/compiler/blotc 3 4
```

## Native traversal: numeric branches and repeated character positions

2026-09-28: two further Bend-source changes remove avoidable work from lookup:

- Numeric Patricia lookup selects its next child as data and uses one tail loop,
  replacing three closures per branch. It retains prefix rejection and complete
  leaf-key equality. A Nat48 path has at most 48 branches and one final node, so
  the loop has a 49-step bound. This differs from the earlier parked
  numeric-index experiment, which removed prefix checks.
- String-index lookup tests the requested advance distance before inspecting the
  suffix. Several Patricia bits can refer to the same character; a zero-distance
  advance now returns the suffix directly, avoiding reconstruction of that
  character. Positive advances retain the original traversal behavior.

The generated native numeric lookup is a direct loop. The source, generated C,
executable, Base, and JS loader are recorded for matched Bend 2.0.32 builds;
neither generated C nor JavaScript is patched. The two changes were measured
together, so this batch does not isolate their individual contributions.

The control includes the previously installed string loop and retained-root
comparison. Both sides use the same frozen 25-module game, four workers, 100,000
const steps, and `analysis: false`. Each sample starts a fresh process; source
loading and startup are measured separately. Three cold pairs alternate
candidate/control, control/candidate, candidate/control. A separate scheduler
candidate precedes the first pair and is excluded from these medians. The body
edit is one additional candidate/control pair using the same frozen ambient-red
change as the earlier experiments. Other desktop work continued; only the
benchmark's own process tree had its scheduling normalized.

| Request / measure                |  Control | Traversal | Reduction |
| -------------------------------- | -------: | --------: | --------: |
| Cold compile wall, median        | 75.750 s |  62.333 s |     17.7% |
| Cold native CPU, median          | 77.500 s |  64.120 s |     17.3% |
| Body-edit compile wall, one pair | 70.901 s |  64.999 s |      8.3% |
| Body-edit native CPU, one pair   | 72.990 s |  66.640 s |      8.7% |

All three cold pairs improve wall and CPU time. Control wall samples span
73.7–78.3 seconds; candidate samples span 60.6–63.6 seconds. Median native
`VmHWM` is essentially unchanged: 278.9 versus 279.1 MiB. This is a reduction in
lookup work, not evidence of a smaller retained heap. One exploratory one-worker
candidate sample takes 59.5 seconds; it is not a paired scaling measurement and
establishes no general worker-count recommendation.

Every cold artifact retains the earlier exact hash, including the one-worker run
and scheduler screen. Both edited artifacts also match the earlier edited hash.
All contain 1,161,014 Wasm bytes. The actual game's create/first-frame checks
pass for both cold and edited outputs on both sides: schema 8, 2,778 draws, 10
solids, and the expected ambient-red change. Full Bend proof, 52 targeted
traversal/inference tests, 56 native parity/protocol/session/output tests, and
native numeric-boundary/ownership regressions at one and four workers pass. The
source and matching native/JS artifacts are installed. After installation, the
full compiler suite passes all 924 tests and a fresh `bend PROOF.bend` passes
again.

### Concurrency screen and remaining work

A separate unchanged-executable GDB profile of the control found one active
worker at 208 of 213 sampled instants. Ownership helpers (`term_drop`,
`span_fade`, `rfc_wrap`, and `ctr_take`) accounted for 96 of 228 active-stack
self samples, about 42%. These diagnostic samples locate work; they are not
additive phase timings or measurements of allocation volume.

The checking graph has 650 jobs across 48 independent regions. One region
contains 603 jobs and about 98% of estimated cost. The outer weighted fork
assigns it one lane, preventing its inner forks from using idle sibling lanes. A
candidate keeps that outer sequence serial when one internally parallel task
exceeds 75% of estimated cost. Its small reproducer improves from about 0.52 to
0.19 seconds with four workers, but the gdev screen regresses from 63.6 to 70.3
seconds and from 65.16 to 76.75 CPU seconds against traversal alone. **Decision:
park the scheduler change.** Available parallelism alone did not offset its
costs on this workload.

Retaining a numeric-list root alongside its membership cursor also failed to
produce borrowed reads in the full native compiler. It kept consuming each list
cell and added root ownership work, so that experiment was discarded. See
[BUGS.md](../BUGS.md) for both limitations and their source reproducers.

The control phase trace spends about 32 seconds in initial checking, followed by
roughly 38–44 seconds around shared-constant preparation. These separate
debugger runs include diagnostic overhead and changing desktop load. Each shared
constant updates the module, inferred shapes, and identity counter before the
next constant is processed. Reduce repeated traversal and catalog work within
that dependency order before attempting a wider parallel plan.

A fresh trace of the installed candidate reaches the end of initial checking and
dispatch after about 23 seconds, enters shared-constant preparation at 24.25
seconds, and reaches the next specialization phase at 55.25 seconds. It exits at
59.62 seconds with a byte-identical complete native response. The remaining
interval around shared constants is about 31 seconds; this diagnostic run is
excluded from the latency medians above.

Evidence: [paired samples](../build/gdev-traversal-20260927/pairs.json),
[summary](../build/gdev-traversal-20260927/pairs-summary.json),
[source identities](../build/gdev-traversal-20260927/source-identities.json),
[toolchain](../build/gdev-traversal-20260927/toolchain.json),
[generated-loop inspection](../build/gdev-traversal-20260927/generated-loop-summary.json),
[profile](../build/gdev-traversal-20260927/current-profile-summary.json),
[phase entries](../build/gdev-traversal-20260927/control-deep-phases.json),
[candidate phase entries](../build/gdev-traversal-20260927/candidate-phases.json),
[checking graph](../build/gdev-traversal-20260927/jobs.json),
[targeted tests](../build/gdev-traversal-20260927/traversal-tests-r2.log),
[native tests](../build/gdev-traversal-20260927/native-tests-r2.log),
[native regressions](../build/gdev-traversal-20260927/native-regressions-r2.json),
[full integrated suite](../build/gdev-traversal-20260927/integrated-tests.log),
[integrated proof](../build/gdev-traversal-20260927/integrated-proof.log),
[guest checks](../build/gdev-traversal-20260927/guest-checks.log), and
[installation identities](../build/gdev-traversal-20260927/integration.json).
The `build/` evidence is kept locally and excluded from Git.

Re-run against the saved matching-version control on the current game:

```sh
deno run -A compiler/gdev_cold_bench.ts \
  build/gdev-traversal-20260927/blotc-control \
  generated/compiler/blotc 3 4
```

## Shared constants: stop completed searches and skip retained operations

2026-09-28: the current-source profile includes repeated name comparisons in
dependency lookup, definition-predicate lookup, and operation merging. Two
lookups passed their recursive tail scan to `Bool.pick`, whose arguments are
eager. They now carry the match result through a tail loop and return at the
first match, including a match whose references or predicates are empty.

An expanded constant retains the operation catalog used to infer it. Merging
that catalog previously searched the retained list again for each incoming
operation. The new merge skips an aligned concrete-operation prefix with one
identity comparison per entry, then uses the original ordered merge at the first
mismatch or new suffix. Existing definitions, duplicate precedence, generic
entries, and insertion order are preserved. These three changes were measured
together; their individual contributions are not isolated.

Both sides use Bend 2.0.32, matching Base and the official JavaScript loader,
and unchanged generated output. The control is commit `45b8eac`. The frozen
25-module game still matches current source. There are three alternating cold
pairs and three alternating body-edit pairs, each with a fresh four-worker
process, 100,000 const steps, and `analysis: false`. The edit changes the same
ambient coefficient as earlier batches. Loading and startup are separate. Only
the benchmark's process tree has scheduling normalized; other desktop work
continues.

| Request / measure              |  Control | Candidate | Reduction |
| ------------------------------ | -------: | --------: | --------: |
| Cold compile wall, median      | 41.368 s |  39.983 s |      3.3% |
| Cold native CPU, median        | 42.840 s |  41.490 s |      3.2% |
| Body-edit compile wall, median | 42.507 s |  41.897 s |      1.4% |
| Body-edit native CPU, median   | 44.040 s |  43.960 s |      0.2% |

All three cold pairs improve, but the smallest gain is only 0.7%. Cold wall
samples span 41.11–41.51 seconds for the control and 39.57–40.82 seconds for the
candidate. Body-edit samples vary more: 42.48–45.97 versus 38.99–43.46 seconds;
two pairs improve and the last regresses by 2.2%. This supports a small cold
improvement, not a reliable body-edit speedup. Median peak native RSS rises
slightly: 278.8 to 280.6 MiB cold, and 278.9 to 280.3 MiB edited. No memory
reduction is claimed.

Every sample preserves the expected cold or edited Wasm hash and 1,161,014-byte
size. Game create/frame checks pass for both variants and both sides: schema 8,
2,778 draws, 10 solids, and the expected ambient coefficient. Full Bend proof,
all 927 compiler tests, host type checks, and native ownership regressions with
one and four workers pass. The new tests cover first-match precedence and
compare operation merges with an independent identity-set oracle over mixed
kinds, duplicates, altered signatures, prefixes, and divergent order. Source and
matching artifacts are installed with verified hashes; an integrated proof check
also passes.

A separate first-entry debugger trace reduces the shared-constant interval from
22.27 to 21.05 seconds. Both sides enter five shared constants; the interval
after the fifth entry accounts for 21.97 and 20.76 seconds respectively,
including work before the following specialization phase. The complete native
responses are identical. These diagnostic runs are excluded from the medians.
The next investigation should distinguish that last constant's inference and
solver work from the preparation that follows it, before changing concurrency.

Evidence:
[measurement plan](../build/gdev-shared-20260928/measurement-plan.json),
[samples](../build/gdev-shared-20260928/pairs.json),
[summary](../build/gdev-shared-20260928/pairs-summary.json),
[source identities](../build/gdev-shared-20260928/source-identities.json),
[toolchain](../build/gdev-shared-20260928/toolchain.json),
[phase comparison](../build/gdev-shared-20260928/diagnostics-summary.json),
[full suite](../build/gdev-shared-20260928/full-tests.log),
[native regressions](../build/gdev-shared-20260928/native-regressions.json),
[integrated proof](../build/gdev-shared-20260928/integrated-proof.log),
[game behavior](../build/gdev-shared-20260928/guest-checks.log), and
[installation identities](../build/gdev-shared-20260928/integration.json). The
`build/` evidence remains local and excluded from Git.

## Shared constants: update pending work from the selected choice

2026-09-28: a detailed trace of the preceding checkpoint identifies five shared
constants. The first four finish quickly; the fifth spends about 9.9 seconds in
solving, 5.4 in finalization, and 2.7 in expansion. Accepting its result is
cheap. The solver previously refreshed its pending cache by looking up every old
requirement in the choice map after each successful selection.

Each selector changes one ordinary choice or adds one solved predicate at a
qualified site. The old cache is already unresolved against all other choices.
The solver now carries that change through selection and removes matching
requirements by numeric site, comparing predicates only at the affected
qualified site. Ordinary and qualified namespaces remain separate, including
when they share a numeric site. Fresh definitions still use the full choice map
and retain their order before the older pending requirements. Unknown changes or
shrinking definition counts retain the full-refresh fallback. The existing
full-refresh implementation remains available as a test oracle.

The control is commit `8213821`, including the prior lookup and merge changes.
Both sides use matching Bend 2.0.32 compiler, Base, and official JS loader with
unchanged generated output. The same frozen 25-module game still matches current
source. Three alternating cold pairs and three alternating body-edit pairs use
fresh four-worker processes, 100,000 const steps, and `analysis: false`. Loading
and startup are separate; the benchmark normalizes only its own process tree's
scheduling, with other desktop work continuing.

| Request / measure              |  Control | Candidate | Reduction |
| ------------------------------ | -------: | --------: | --------: |
| Cold compile wall, median      | 37.649 s |  33.112 s |     12.0% |
| Cold native CPU, median        | 39.160 s |  34.620 s |     11.6% |
| Body-edit compile wall, median | 37.753 s |  33.229 s |     12.0% |
| Body-edit native CPU, median   | 39.260 s |  34.760 s |     11.5% |

Every pair improves wall and CPU time. Cold wall samples span 37.58–37.99
seconds for the control and 33.04–33.33 for the candidate. Edited samples span
37.61–37.81 versus 32.95–33.37 seconds. Peak native RSS stays around 280 MiB:
median 279.6 versus 278.8 MiB cold, and 279.8 versus 280.7 MiB edited. This is a
reduction in repeated lookup work, with no consistent memory reduction.

A separate matched debugger trace reduces the fifth constant's solver interval
from 9.66 to 5.16 seconds and the shared-constant interval from 20.03 to 15.49
seconds. Its initial inference remains about 1.76 seconds, finalization about
5.1 seconds, and expansion about 2.6 seconds. Both complete native responses
match exactly. These diagnostic timings are excluded from the benchmark medians.
Initial checking and finalization remain substantial work; dependency order and
worker scheduling are unchanged.

All twelve Wasm artifacts retain the exact expected cold or edited hash and
1,161,014-byte size. Game create/frame checks pass for both sides and variants,
including schema, draw and solid counts, and the expected ambient change. Full
Bend proof, all 930 compiler tests, and native regressions with one and four
workers pass. The new tests compare the change-based refresh with the full
refresh over 200 randomized cases, duplicate requirements, both namespaces,
maximum Nat48 sites, newly inferred execution needs, and fallback conditions.
Native regressions also exercise changed substitutions, qualified predicates,
new-definition ordering, and shrinking counts. Verified source and matching
native/JS artifacts are installed; the integrated proof passes again.

Evidence:
[measurement plan](../build/gdev-pending-20260928/measurement-plan.json),
[samples](../build/gdev-pending-20260928/pairs.json),
[summary](../build/gdev-pending-20260928/pairs-summary.json),
[source identities](../build/gdev-pending-20260928/source-identities.json),
[toolchain](../build/gdev-pending-20260928/toolchain.json),
[phase comparison](../build/gdev-pending-20260928/diagnostics-summary.json),
[full suite](../build/gdev-pending-20260928/full-tests.log),
[native regressions](../build/gdev-pending-20260928/native-regressions.json),
[integrated proof](../build/gdev-pending-20260928/integrated-proof.log),
[game checks](../build/gdev-pending-20260928/guest-checks.log), and
[installation identities](../build/gdev-pending-20260928/integration.json). The
`build/` evidence remains local and excluded from Git.

## Current gdev baseline: first working sample

2026-09-27: r31 compiler source plus the JS loader compatibility fix, built with
Bend 2.0.31. Full proof passed in 79.24 seconds; emitting only `compiler.js`
took 55.01 seconds. Generated output was used unchanged. Deno 2.9.7 / V8
15.0.245.2-rusty ran the benchmark.

The frozen current game has 25 loaded source modules. The benchmark calls its
actual `createBlotCompiler` JS route, retains the project loader for subsequent
requests, and edits only an isolated copy of `src/daylight.blot`.

| Request   | Wall time | Inside compiler | Compiler calls |
| --------- | --------: | --------------: | -------------: |
| Cold      | 52,433 ms |       52,107 ms |              1 |
| Unchanged |    4.5 ms |            0 ms |              0 |
| Body edit | 53,252 ms |       53,220 ms |              1 |

Fresh-process startup through the first Wasm result was 52,919 ms. The whole
process group peaked at approximately 1,492 MiB, including subsequent headless
guest checks. Filesystem caches were not flushed, and other desktop work
continued. This is one smoke sample, not a stable median or an optimization
gain.

Both guest checks passed. The body edit changed the first frame's ambient red
component from 0.29499999 to 0.39499998, preserving schema 8, 2,778 draws, and
10 solids. The unchanged request reused the same byte-array object with zero
compile calls. The edited request changed the project key and compiled once. No
browser, GPU renderer, or native compiler was involved.

The cold Wasm hash also matches the previously verified browser artifact:
`b4b52bd6312025d78801a9e589b00b14365bd87e8c919519ee8d5988bd86783e`. Raw samples
and behavior hashes are in
[`iterate-smoke-3/report.json`](../build/perf-overhaul/logs/iterate-smoke-3/report.json).

## First candidate: numeric-index lookup

A separate V8 profile confirmed that compilation dominates this request. Exact
name equality accounted for about 13.2% of sampled time including its children;
numeric division/remainder accounted for 5.7% of self time across several uses.
These are diagnostic samples, not independent additive pipeline phases. The
profiled cold request took 57.4 seconds and is excluded from latency
comparisons. The
[profile summary](../build/perf-overhaul/logs/iterate-profile-2/1-A/profile-summary.json)
records the breakdown.

The first small candidate removes repeated prefix checks while looking up a key
in the numeric Patricia index. Trees constructed by `new`/`set` already route
stored keys by branch bits, and the leaf checks the complete key. Insertion
keeps its prefix checks. Present keys require less work; some absent keys may
require more traversal. Hand-constructed malformed trees are outside this
invariant.

This candidate passed full proof, unchanged JS emission, and 35 focused tests
covering numeric keys, persistence, free variables, dependency graphs,
scheduling, and inference. Three paired gdev samples completed in approximately
11 minutes. Each side used a fresh process, with order A/B, B/A, A/B. All six
samples passed the original/edited guest checks, and each phase produced
byte-identical Wasm across the baseline and candidate.

| Request   | Baseline median | Candidate median | Median paired B/A |
| --------- | --------------: | ---------------: | ----------------: |
| Cold      |         51.07 s |          55.15 s |     1.080 (+8.0%) |
| Body edit |         56.65 s |          55.62 s |     0.982 (-1.8%) |

The individual cold differences were -5.2%, +10.7%, and +8.0%; edit differences
were -2.4%, -1.2%, and -1.8%. The median of paired ratios is reported separately
from the ratio of component medians. Unchanged requests remained output-cache
hits at 3–8 ms and performed no compilation.

**Decision: park this candidate.** The small edit-time reduction does not
justify the measured cold regression. Three pairs under changing desktop load
are not a precise estimate of the effect, but they provide no reason to expand
or land this change. No extra repetitions were run to seek a favorable result.
The source experiment is preserved in `build/perf-overhaul/iterate-nat-lookup`;
the live compiler is unchanged by this optimization.

The
[paired report](../build/perf-overhaul/logs/iterate-nat-lookup-pairs/report.json)
contains all timings, CPU samples, build/source identities, memory observations,
and behavior hashes. The first experiment produced a working measurement loop
and a decision, not an accepted compiler speedup.

The next investigation is repeated name comparison in dependency membership and
inference binding lookup, the two largest immediate callers in the profile.
Choose one bounded change there before reopening broader M3 implementation.

## Identity experiments: current control

2026-09-27: rebuilt the control with matched Bend 2.0.32, Base, and JS loader.
The source is the previous r31 control plus the pure frame/foreign transport
import split required by the new proof checker. Full proof passed in 18.58 s;
main-only JS emission took 42.30 s. Seventeen focused compiler cases pass after
correcting two old test-only constructor tags exposed by the stricter loader.

A separate diagnostic profile of the frozen game took 88.36 s for the cold
request. Its Wasm was byte-identical to the earlier control, and the headless
frame check passed. Exact name comparison occupied 10.68 s inclusive out of
88.33 s of samples (about 12.1%); binding list lookup occupied 2.78 s and
`external_fixed_rows` occupied 1.26 s. These figures overlap; they are not
additive savings or evidence that strings explain the entire compile time. This
profiled timing is not used as an ordinary latency sample or as a cross-version
speed comparison.

The two bounded source experiments are numeric ownership membership shared
across row-finalization passes, and an immutable shape-binding catalog shared
across specialization tasks. Both must preserve declaration order, duplicate
bindings, exact diagnostics, and persistent semantic keys. They remain
unaccepted until complete-cost screening and matching-version game measurements.
The distinction between Symbol IDs, Declaration IDs, and occurrence IDs is in
[the design note](../build/perf-overhaul/ids-design.md).

Current evidence:
[proof](../build/perf-overhaul/logs/iterate-ids-control32-proof/receipt.json),
[JS build](../build/perf-overhaul/logs/iterate-ids-control32-js/receipt.json),
[profile](../build/perf-overhaul/logs/iterate-ids-control32-profile/1-A/identity-profile-summary.json).

## Declaration membership: no overall gain in the first game pair

The isolated `iterate-external-ids32` candidate shares one declaration catalog
between two row-finalization ownership checks. Duplicate spellings map to all of
their declaration IDs; the traversal uses a numeric membership set and preserves
source order, diagnostics, and union order. Independent review, full proof
(19.73 s), unchanged JS emission (41.90 s), and 21 targeted tests pass. The new
test file needed two fixture corrections; the corrected test ran against the
same emitted artifact without rebuilding compiler code.

The synthetic screen includes catalog construction and both checks behind one
Bend call on each side. Five alternating pairs found 84.85 -> 36.43 ms for 900
quantified bindings with long names, but 0.079 -> 0.213 ms for 24 duplicate
bindings. Those results justified a real-game screen, not a speedup claim.

| Request          |  Control | Candidate | Difference |
| ---------------- | -------: | --------: | ---------: |
| Cold             |  85.32 s |   90.52 s |      +6.1% |
| Body edit        |  96.94 s |   91.76 s |      -5.3% |
| Cold + body edit | 182.26 s |  182.28 s | about 0.0% |

This is **one A/B screening pair**, with the control first. It cannot estimate
variation or establish a regression or gain. All four original/edited guest
checks passed with byte-identical Wasm, and unchanged requests remained output
cache hits with zero compiler calls.

**Decision: park the narrow membership variant.** It has not demonstrated an
overall iteration benefit, so spend the next verification cycle on the catalog
shared across an entire specialization batch. Do not merge the parked variant
into that experiment or attribute the synthetic benefit to game compilation.

Raw evidence:
[complete-cost screen](../build/perf-overhaul/logs/iterate-external-ids32-micro.json),
[game A/B screen](../build/perf-overhaul/logs/iterate-external-ids32-screen/report.json),
[existing tests](../build/perf-overhaul/logs/iterate-external-ids32-existing-tests.log),
[corrected ID tests](../build/perf-overhaul/logs/iterate-external-ids32-fixed-tests.log).

## Shape catalog: correctness passes, no game gain

The isolated `iterate-shape-ids32-r2` candidate assigns separate Symbol IDs and
Declaration IDs to an immutable shape snapshot, indexes first-match lookup, and
carries a resolved method's declaration ID through schema selection and
fallback. One catalog is shared per specialization batch. Changed shared
constants get a fresh catalog; cache-key-only and fully reused task paths skip
construction. This is a bounded catalog experiment, not compiler-wide symbol
interning: most ingress lookups still use string keys.

Full Bend 2.0.32 proof passed in 22.90 s, unchanged main JS emission in 46.16 s,
and 26 focused tests passed. An additional differential check found identical
`context_module` cache inputs for duplicate/reordered shapes and schema, source,
and entry edits. This does not claim native-session runtime verification.
Independent source review found no semantic blocker.

The complete-cost synthetic screen uses eight alternating timed samples and
includes construction plus 128 queries behind one Bend call. Medians recomputed
from all raw samples show wide late hits improving from 195.61 to 74.22 ms and
misses from 124.03 to 72.86 ms; easy first hits with duplicate names regressed
from 0.095 to 1.946 ms. The original harness reported the upper middle sample
for its even sample count; these figures average the two middle values. The raw
log is retained unchanged.

| Request          |  Control | Candidate | Difference |
| ---------------- | -------: | --------: | ---------: |
| Cold             |  83.01 s |   84.16 s |      +1.4% |
| Body edit        |  87.86 s |   92.75 s |      +5.6% |
| Cold + body edit | 170.87 s |  176.91 s |      +3.5% |

This is one control-first A/B screening pair. It cannot establish the size of a
regression, but provides no reason to accept a speedup or expand measurement.
All original/edited guest checks passed, both phases produced byte-identical
Wasm across sides, and unchanged requests made zero compiler calls.

**Decision: park the shape catalog version.** Neither tested identity catalog
has shown a game iteration gain. Numeric identity remains the right semantic
distinction, but building extra maps around unchanged string references has not
paid off here. A future identity slice should carry resolved IDs from a producer
through repeated consumers, avoiding an added conversion/index per phase. The
live compiler is unchanged by either experiment.

Evidence:
[proof](../build/perf-overhaul/logs/iterate-shape-ids32-r2-proof/receipt.json),
[JS build](../build/perf-overhaul/logs/iterate-shape-ids32-r2-js/receipt.json),
[focused tests](../build/perf-overhaul/logs/iterate-shape-ids32-r2-tests.log),
[field tests](../build/perf-overhaul/logs/iterate-shape-ids32-r2-field-tests.log),
[cache-input parity](../build/perf-overhaul/logs/iterate-shape-ids32-r2-context-parity.log),
[synthetic screen](../build/perf-overhaul/logs/iterate-shape-ids32-r2-micro.log),
[game screen](../build/perf-overhaul/logs/iterate-shape-ids32-r2-screen/report.json).

## First shared generic body executes at two types

The isolated `m3-r18-collector-dev-bend32` prototype now runs one checked
generic `twice` body at both U32 and F32, with statically selected addition
evidence. Its two exports return 42 and 2.5. The release path emits two
specialized `twice` bodies; the development path emits one shared body.

Execution initially exposed an ABI bug: the arena's three-argument mark/collect
helpers were assigned the development language's four-argument function type.
The fix appends a separate arena signature in development output and preserves
existing public type indexes. Release output keeps its original signature. A
qualified-forwarding test fixture also now uses `@type.call` explicitly, since
that fixture deliberately loads no operator prelude.

Full Bend 2.0.32 proof passed in 42.28 s; main-only JS emission took 55.96 s.
All 58 focused tests pass: shared-body execution/rejection, private ABI,
captured closures, callbacks, initialization, arrays, arena collection, source
collector cold/reuse/edit behavior, producer epochs, local scopes, and staging.

The screen uses the same pre-parsed CST and a single Bend call returning Wasm
bytes on both paths. A `compile_source_bytes` helper keeps release analysis
inside Bend, matching the private emitter's host boundary. Parsing, guest
execution, and untimed job-count inspection are excluded. Two warmups per path
precede eight alternating pairs, all of which validate both exports.

| Measure            | Release specialization | Private shared body |
| ------------------ | ---------------------: | ------------------: |
| Median compile     |               11.04 ms |             5.60 ms |
| Observed range     |         10.00–18.19 ms |        5.14–6.50 ms |
| `twice` bodies     |                      2 |                   1 |
| Total codegen jobs |                     12 |                   9 |
| Wasm size          |            1,726 bytes |         1,742 bytes |

The median paired ratio is 0.500. The improvement measures this entire private
path, including its deliberately narrower preparation; it cannot be attributed
solely to the three fewer jobs. The evidence/ABI overhead adds 16 Wasm bytes.

**Decision: retain this as a working, measured prototype.** It supports exactly
a five-declaration pure program with one certified generic body and two literal
U32/F32 callers. It is not a public development mode, arbitrary generic sharing,
or a gdev compile-speed result. Effects/reflection, wider source admission,
cache integration, and game adoption remain. The live compiler is unchanged.

Evidence:
[proof](../build/perf-overhaul/logs/M3-r18-collector-dev32-proof/receipt.json),
[JS build](../build/perf-overhaul/logs/M3-r18-collector-dev32-js/receipt.json),
[58 tests](../build/perf-overhaul/logs/M3-r18-focused-tests.log),
[raw timing/job data](../build/perf-overhaul/logs/M3-r18-dev-shared-micro.jsonl),
[command and input identities](../build/perf-overhaul/logs/M3-r18-dev-shared-micro-command.json).

## Collector correctness checkpoint on Bend 2.0.32

The isolated r25 candidate passes full proof (48.85 s), unchanged regression JS
emission (107.60 s), and all 475 collector/source/development tests (19 s test
time). Nested qualified requirements replay to closure, lambda requirements must
have exact checked-use coverage, and a pure computed producer transfers its
evidence once per enclosing clone. Conflicting producer proof remains private.
The offset-key regression now reindexes its isolated local-answer fragment and
compares the actual U32/F32 outer choices.

This is correctness evidence, not a new speed measurement. The four selected
JavaScript session cases currently pass three and fail one: a checked generic
associated call still takes the ordinary fallback. The r26 candidate addresses
its annotated forwarding lambda and inferred caller requirements. No new
compiler performance change has been adopted in the live checkout.

Evidence:
[proof](../build/perf-overhaul/logs/M3-r25-collector-dev32-proof/receipt.json),
[JS build](../build/perf-overhaul/logs/M3-r25-regression-js/receipt.json),
[475 tests](../build/perf-overhaul/logs/M3-r25-collector-and-source-tests.log),
[session tests](../build/perf-overhaul/logs/M3-r25-session-js-tests-r3.log).
Session checks reuse the same unchanged bundle through explicit host adapters
for the entry module's export names and constructor namespaces; earlier attempts
with missing aliases are retained as harness failures.

## Reproduce and compare

The reusable runner consumes passed JS build receipts and never starts a build:

```sh
python3 scripts/perf_iteration.py \
  --baseline build/perf-overhaul/logs/iterate-baseline-js/receipt.json \
  --workload build/perf-overhaul/logs/M3-r31-live-capture-gdev-vulkan-r1/project/gdev \
  --workload-manifest build/perf-overhaul/logs/M3-r31-live-capture-gdev-vulkan-r1/gdev-source.json \
  --output build/perf-overhaul/logs/iterate-measurements \
  --rounds 3
```

Use a new output directory each time. Add `--candidate PATH_TO_BUILD_RECEIPT`
for alternating A/B samples. Add `--profile` for a separate diagnostic cold run
that writes `compile.cpuprofile`; its timings are not ordinary benchmark
samples. The runner verifies matching toolchains and std sources, frozen input
hashes, compile/cache branches, deterministic output within each side, and
matching headless frame results across sides. A new installed Bend release
requires fresh matched builds before comparison.
