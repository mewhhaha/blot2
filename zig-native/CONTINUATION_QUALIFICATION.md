# Implementation and iterator continuation

The latest uncommitted batch passes the complete compiler gate on15 October:
2,223 native laws, 1,404 guest/client tests, 1,366 complete allocation sweeps
plus two expected-error harness laws, and zero analyzer findings across 455
files. Tasks 070/071 are complete;27 program tasks remain open. Exact final pins
and remaining boundaries are in
[the current checkpoint](#qualified-continuation-15-october-2026). Earlier
sections below retain their historical qualification scope.

Local `b145c5e` extends the qualified `10fab46` checkpoint with private child
fields, scoped capability contracts, body reuse and shared constant scratch.
Both full gates pass. The later qualification appears below; the broader tasks
and task 084's iteration targets remain open.

## Frozen inputs

Zig 0.17.0, LLVM/Fast compiler SHA-256
`25232004dd54b576e41c467693eba585ae7abb1543ce39a1d0ebeed541e30dd6`. Frozen tree
`46b8d009c1cb51cf8cb195e5ddfc2a406ea4659a`, native source tree
`c9fe14fd7fa33d4572f337d47f3833106b5b65ba`, parent `c48d4a7`. The frozen patch
SHA-256 is `e83bd5316d84e1967d43147dc88c4a6564977c55260f17ef33df610ebafe89d2`.
The comparison is qualified compiler `6a57437`, SHA-256
`904b1ac1558ae3d5c9b1c11744f6cf45a096297753b4b8e572fc4bb99935adb2`.

Ignored evidence is under `build/bench/continuation-20261013/`. Binary, source,
input manifests, scripts and individual samples are retained. The private
93-unit captured project stays outside commits. Its scalar edit changes one
floor extent from 60 to 61; current measurements do not replace older workload
measurements from a different source snapshot.

## Behavior and boundaries

[Implementation declarations](IMPLEMENTATIONS_QUALIFICATION.md) enforce coherent
visible heads, owned associated substitutions and bounded diagnostics through
source, compiled dependencies, re-exports and retained/restarted revisions. A
separately compiled facade preserves original producer and opaque identities.

[Body cutoff](BODY_CUTOFF.md) now admits qualified dotted accesses and inferred
local requirements through complete owned recipes. General declared local
qualification, producer relocation and every edited-module body remain work for
024/093. In the isolated local-requirement workload, 64/128 edited bodies fall
from 98.125/188.125 ms to 79.375/152.5 ms in Safe/noLLVM; initial population
costs 22–25% more. Those isolated clocks are not release captured-project
timings.

Private iterator changes include table projections, packed cursor word positions
and leaf directories, eager row-tail handling, and
[tagged step fields](STATIC_CONSTRUCTOR_FIELDS.md). Unknown/escaping state keeps
ordinary ownership. Empty alternatives use exact symbolic facts and shared roots
only within the proved activation. Further child aggregates and adapters remain
in task 047.

[Scoped effects](SCOPED_EFFECTS_QUALIFICATION.md) include symbolic operation
arguments, fresh direct instances, State/request routing, activation revocation,
callback captures and checked longer-lived value forwarding. General public
dependent capability parameters, selected identity and complete escape graphs
remain in 058/059. Portable interfaces use wire version 4.

Constant receipts add an enclosing selected-member judgment for the admitted
closed empty-array receiver. Ordinary principal and publication work stays in
place. The captured project's largest unchanged constant still runs 57,019 of
70,330 total source steps. Diagnostic instrumentation identifies collection
growth as its first unsupported observation, followed by 227 expression-time
inference observations on the retained edit. There are no productive constant
receipts or dedicated graph indexes in this workload. General graph/data,
growth, query and typed-view publication remain in 086.

Effect-row normalization copies operation arguments only when they actually
change and refreshes closed-node certificates after ordinary normalization.
Rollback acknowledges its already-invalidated effect epoch, avoiding a second
worklist wake-up. Worklist frontiers include symbolic operation arguments,
scoped payloads and associated projection arguments, including nested open rows.
Physical edits, rollback, bounds and OOM retain explicit laws.

Development fixtures now install beside the selected development compiler;
fixture consumers derive their paths from that executable. The compiler,
identity and ordinary fixtures share one Zig configure call.

## Qualification and discovered failures

The first combined gate passed 1,610 native laws and failed an existing generic
effect-alias guest. A full guest sweep also found an obsolete symbolic-row
rejection and inconsistent optional diagnostic JSON fields. All three were
repaired. A development fixture path mistake initially failed 38 tests; deriving
paths from the selected compiler fixed it without weakening their assertions.

The second frozen gate passed 1,622 of 1,623 native laws. Its worklist test
exposed a duplicate generation change after rollback. The repair also adds the
missing symbolic-argument frontier law. The repaired preflight passes 67 type
laws, 19 worklist/harness laws, all 1,030 guest/client tests, and the analyzer
with zero findings across 373 files. The final full gate passes **1,624 native
laws, 1,030 guest/client tests and 975 complete allocation-failure sweeps** plus
two expected-error sweep laws. The unchanged frozen tree and binary were checked
again after the gate.

Tree-sitter generation/corpus/highlights/examples and six editor checks pass.
Deno checking, formatter tests and packaging dry run pass. No package is
published. Ordinary and forced (`--cache-poison=poisoned`) configure runs agree
on identity `16cb9158f9a5c0c7e564ba00e40cddf3f0a636641f14a5f8e099c11d1c6516e2`.
The release binary remains unchanged.

The full gate used `DENO_JOBS=4`, CPUs 0–3/8–11 and
`deno task test:compiler --oom-profile`. Wall time was 839.91 seconds: 199.90
release build, 277.96 native compilation, 331.97 native execution and 18.17
guests. The profiled gate preserves every failure index; timing is not a quiet
isolated machine comparison.

## Release measurements

Measurements below use the exact final LLVM/Fast binary. Root measurements ran
on CPU 6 while isolated work used other CPUs; machine load and filesystem caches
were uncontrolled. Compiler CPU is process user plus system time. Work counters,
requested allocation and committed guest memory are separate quantities.

Seven alternating captured-project pairs preserve fresh/retained diagnostics,
Wasm hashes and fuel. Each compiler/phase has an independent fresh reference.

| Phase  | Baseline median CPU | Candidate median CPU | Median paired ratio |
| ------ | ------------------: | -------------------: | ------------------: |
| Fresh  |        1,956.134 ms |         2,184.885 ms |              1.1164 |
| Edit   |        1,097.851 ms |         1,191.868 ms |              1.0923 |
| Revert |          998.108 ms |         1,096.061 ms |              1.0938 |

Fresh paired ratios are 1.1143, 1.0327, 1.0306, 1.6446, 1.1223, 1.1169 and
1.1164; the broad distribution is retained. Edit ratios span 1.0635–1.0960;
revert spans 0.8637–1.1046. Thirteen public programs, seven pairs each, cost
1.0435–1.0636 times baseline CPU, with zero live requested compiler storage
after teardown. All deterministic per-compiler outputs and diagnostics match.
New runtime lowering intentionally changes most cross-compiler Wasm bytes.

Implementation scaling has 98 whole-check samples, seven per case/size, and zero
live requested storage after teardown. Projection DAG depth 4→64 takes
0.733→6.352 ms and 111,063→6,191,282 requested bytes; disjoint heads 8→64 take
0.728→1.831 ms and 83,356→1,896,528 bytes; prerequisite chains 4→64 take
0.730→1.249 ms and 53,667→652,458 bytes. Preparation is polynomial, not linear.
The former compiler does not accept this feature, so there is no equivalent
before-feature timing. A separate 98-sample lifecycle covers both compiler
tiers, fresh/body/equation edits, failed overlaps, recovery, no-op and portable
restart; independent fresh bytes, diagnostics and executed answers 42/43 agree.

For 4,096 pipeline rows, objects fall 53,254→36,870 and requested payload bytes
409,648→294,960. Guest CPU ratio is 0.8308; array cursor is 0.9545 and scalar
cursor 1.0000. Journal roots, leases and ownership teardown remain zero.

Three packed comparison batches use the reconstructed boxed reference, 31
alternating CPU pairs, 20 warmups and 16 traversals per sample. Record widths
1–16 and tuple widths 2–16 are all included. The ranges below are width medians
across the three batches; individual samples and batch medians are retained.

| Representation | Fold CPU ratio range | Cursor CPU ratio range |
| -------------- | -------------------: | ---------------------: |
| U32 record     |        0.2207–0.5646 |          0.5806–0.9432 |
| U32 tuple      |        0.2668–0.6048 |          0.4423–0.9668 |
| F32 record     |        0.4224–0.9955 |          0.5186–0.8584 |
| F32 tuple      |        0.9204–0.9944 |          0.5212–0.8587 |

Output equality and actual snapshot/bounds laws pass. These results qualify the
packed cursor tail of 047; child aggregates and broader adapters remain open.
The owner's earlier waiver of missing historical artifacts remains in force.

Ownership guest controls cover four workloads in sync/JSPI modes, 25 alternating
pairs and 400 samples per batch. All three batches retain 131,072 committed
bytes. The first async-scalar ratio of medians was 1.2844; two follow-ups on the
same Wasm gave 1.0963 and 1.0194. Other ratios span 0.9518–1.0295. The anomaly
is preserved rather than discarded; these noisy clocks do not close task 035's
CPU qualification. All 1,200 samples and both aggregation methods remain
available.

Raw evidence: `qualified-batch3/`, `public-batch3/`,
`implementations-scaling-batch3/`, `implementations-lifecycle-batch3/`,
`runtime-batch3/`, `packed-batch3/`, `ownership-batch3-repeat-{2,3}/`,
`measurement-summary-batch3.json` and `ownership-repeat-summary-batch3.json`.
Earlier batch-1/2 samples keep their original pins. A guest-runtime improvement
and a passing gate do not close compiler iteration targets 084/086/093.

## Child fields and retained graphs, 13 October 2026

Local `b145c5e` is frozen tree `a576172aa23e937ee5abdad6326a056adc880203`,
native source `dda64a9fad2855179f5846d8774477b217398ad3`, based on `7cb2b3e`.
Its LLVM/Fast binary SHA-256 is
`b47b376058beecb41c22703a8e360985259fe79d878a7e3545e97e3a1d73faab`; the patch
SHA-256 is `5a3ca96435f71b5554030503554df9c0137f5ff68e5c51f221b8dc1af8651745`.
The comparison is the qualified `10fab46` binary pinned above. All later raw
paths below are under the same ignored `build/bench/continuation-20261013/`.

Body recipes now preserve declared local qualifications, producer-unit/binding
relocation and imported type heads. Capability contracts preserve exact public
identity/Unit invocation, generic parameter transport, curried callbacks and
trusted local State storage. A smaller initial specialization mapping allocation
restores the existing allocation budgets. Complete dependent-arrow annotations,
multiple inputs, selected identities and general hidden stores remain outside
this checkpoint. [Body cutoff](BODY_CUTOFF.md) and
[scoped qualification](SCOPED_EFFECTS_QUALIFICATION.md) retain the isolated laws
and boundaries.

[Private child fields](PRIVATE_CHILD_FIELDS.md) remove proved aggregate and
journal-only carrier allocations, with bounded per-loop root-cost admission.
Escapes, unknown ownership and unprofitable strict/window loops retain ordinary
storage. Constant graph inspection uses sparse pages, and successive receipts
share their request-owned matching/materialization scratch. This changes
bookkeeping cost, not receipt authority: only the existing primitive payloads
and scalar ready reads are admitted. Collection-growth receipts are a separate,
unmerged follow-up at this checkpoint.

The first gate passed 1,649 of 1,651 native tests. A forged cycle fixture had
kept a newly introduced identity claim after replacing its body; a Foreign-row
fixture still rejected a now-supported explicit result annotation. Correcting
only those two fixtures passes all 30 focused laws and the complete retry:
**1,651 native tests, 1,043 guest/client tests, 1,000 complete
allocation-failure sweeps, two expected-error sweep laws and zero findings
across 374 analyzer files**. The source tree and release hash were verified
after the gate. Four local/packaged/standalone/CLI API tests also pass.

The failed gate took 880.62 seconds, including a 212.88-second release build.
The successful retry took 682.24 seconds: release reuse 0.05, native compilation
280.89, native execution 370.03 and guests 18.93. Test-only fingerprint
exclusion preserved the measured release binary across both fixture repairs.
Commands, failure logs, full timing records and post-gate pins remain in
`next-full-gate.log`, `next-repaired-gate/` and `next-qualified-pins.json`.

Seven alternating captured-project pairs use the same 93-unit input manifest and
independent fresh comparisons for every compiler/phase. CPU 6 was pinned; other
isolated work and filesystem caches remained uncontrolled.

| Phase  | Control median CPU | Candidate median CPU | Median paired ratio |
| ------ | -----------------: | -------------------: | ------------------: |
| Fresh  |       2,218.216 ms |         2,220.961 ms |              1.0262 |
| Edit   |       1,214.444 ms |         1,263.002 ms |              1.0486 |
| Revert |       1,089.874 ms |         1,151.709 ms |              1.0577 |

Fresh ratios span 0.9873–1.0382, edit 1.0268–1.0777 and revert 1.0412–1.0759.
The paired median is computed from pairs and can differ from the ratio of
independent medians. Backend assembly adds about 47 ms on edits/reverts. Both
pins report 2,864 optimized functions, zero reused bodies and one ownership-role
conflict; the reason for zero reuse is under investigation. Constant receipt and
index activity remain zero in this capture. Thirteen public programs, seven
pairs each, cost 1.0000–1.0357 times control CPU. Peak requested storage is
unchanged and teardown is zero; requested allocation increases 176–943,445
bytes. These results retain a compiler regression, not an iteration-speed win.

The constant-scratch workload has 196 samples: sixteen expensive primitive
constants, seven alternating pairs, population and six edits at two unrelated
snapshot sizes. With 32,768 old values, retained median CPU falls 18.005→15.158
ms; median paired ratio is 0.8419, range 0.8266–0.8670. Population is near
parity at 0.9971. Graph-index payload on the first edit falls 8,288,176→529,662
bytes and later edits 7,876,016→510,342. All sixteen receipts replay 2,608
source steps. With only 64 old values, retained CPU is near parity at 1.0052;
later index accounting rises 27,056→68,838 bytes because the new counter also
includes shared mapping/order buffer capacity. These are requested scratch
payloads, not RSS. An earlier development comparison using the wrong compiler
path is explicitly invalid and supplies no performance claim.

Ten iterator workloads use 4,096 rows, 31 alternating pairs, 20 warmups and
sixteen calls per sample. Physical profiling copies count objects separately
from CPU measured on ordinary Wasm. The final combined binary preserves the
isolated allocation reductions:

| Adapter           | Objects before→after | CPU ratio |
| ----------------- | -------------------: | --------: |
| range             |             12,290→0 |    0.0384 |
| map               |             24,580→0 |    0.0192 |
| filter            |             20,484→0 |    0.0345 |
| take              |             12,292→0 |    0.0252 |
| take_while        |             14,345→2 |    0.0169 |
| enumerate         |         32,772→8,192 |    0.3185 |
| zip               |         22,537→4,096 |    0.2647 |
| zip_strict        |        49,158→49,158 |    1.0226 |
| windows           |        81,894→81,894 |    1.0217 |
| map/take pipeline |             36,870→0 |    0.0121 |

The pipeline's requested payload falls 294,960→0 bytes. TakeWhile's two
allocations belong to predicate creation. Every answer passes; committed guest
memory remains 131,072 bytes, roots/leases finish at zero and journal reset
retains one 4 KiB page. Strict/window controls keep their allocation counts and
show about 2% higher measured CPU. All 62 packed width/type Wasm files are
byte-identical to the previously qualified pin, so the earlier boxed-reference
qualification remains applicable without claiming a new packed improvement.

Raw measurements: `captured-next/pairs.json`, `public-next/results.json`,
`next-constant-pairs.json`, `next-runtime/`, `next-packed/equality.json` and
`next-measurement-summary.json`. Tasks 024/035/047/058/086/093 remain open.

## Growth, scalar callbacks and complete arrows, 13 October 2026

Local `38e822d` is frozen tree `52b6c36abad5f25f589fb0a6ba0e17d0e681f090`,
native source `101404d4442bfa27373199d1a7885ad6cffaaa62`, based on `59fcd6b`.
Its LLVM/Fast binary SHA-256 is
`bbf4fb62168a056aa3b55b439c2a509cd0781e2d691f000a809e09ec1bcbd9a3`; patch
SHA-256 is `892eef28f57c6b245435af5b4471cd96c3723302bda92d469f60d6ba5c77f576`.
The control is the qualified `b145c5e` binary above. Raw paths below remain
under ignored `build/bench/continuation-20261013/`.

Body recipes add shared local declarations, explicit Foreign arrows and array
index operations. Complete scoped arrows now have parser, checker, formatter and
editor support, including grouping that distinguishes a returned arrow's
invocation row from its producer's row. Bounded private scalar callback
expansion exposes additional child allocations to the existing optimizer.
Constant receipts preserve primitive collection growth and exact buffer debt.
[Body cutoff](BODY_CUTOFF.md),
[scoped effects](SCOPED_EFFECTS_QUALIFICATION.md),
[private callbacks](PRIVATE_SCALAR_CONSUMERS.md) and
[constant reuse](CONSTANT_REUSE.md) define the admitted cases and rejections.

The frozen combined gate passes **1,664 native tests and 1,053 guest/client
tests**, with **zero findings across 374 analyzer files**. All 1,011 ordinary
allocation-failure sweeps complete. Two additional profiler records are the
harness laws that intentionally return `UnexpectedScenarioError`; they correctly
report `completed: false`. The aggregate timing file counts 1,013 records.
Source tree, native subtree, patch and release binary hashes match after the
gate. The gate took 889.65 seconds: release build 200.39, native compilation
280.54, native execution 375.67 and guest/client tests 20.56. These are separate
costs; guest execution accounts for about 2% of the full gate.

Before the full gate, 943 native guest tests and the focused budget group pass.
Frontend tests pass 18 with one existing ignored test; both new arrow tests run.
The regenerated Baba parser matches checked-in output. Official tree-sitter
0.27.1 passes seven corpus cases, fifteen highlight fixtures, example parses and
six editor configuration tests. A development invocation without positional
guest files runs only smoke tests; `following-all-guests-preflight.log` records
that smaller run. The actual 943-test preflight is
`following-native-guests-preflight.log`.

Seven alternating captured-project pairs use the same 93-unit snapshot and a
fresh byte/source-fuel oracle for each phase. CPU 6 is pinned; other isolated
work and filesystem caches remain uncontrolled. Results stay near parity:

| Phase  | Control median CPU | Candidate median CPU | Median paired ratio |
| ------ | -----------------: | -------------------: | ------------------: |
| Fresh  |       2,228.430 ms |         2,233.960 ms |              1.0040 |
| Edit   |       1,253.996 ms |         1,253.111 ms |              1.0009 |
| Revert |       1,153.501 ms |         1,152.476 ms |              1.0021 |

Paired ranges are 0.9999–1.0069, 0.9987–1.0059 and 0.9984–1.0063 respectively.
Earlier regressions remain; this batch does not recover them. Captured constants
still have zero receipt/index activity. Thirteen public programs, seven pairs
each, keep exact Wasm, source fuel and requested/peak allocation counts, with
zero teardown and CPU ratios 0.9832–1.0005.

Growing primitive constants use seven alternating pairs, population and six
edits per size: 392 samples. Every phase preserves fresh bytes and source fuel.

| Elements | Retained CPU before→after | Retained paired ratio | Population paired ratio |
| -------: | ------------------------: | --------------------: | ----------------------: |
|       32 |            1.035→1.002 ms |                0.9665 |                  0.9937 |
|      512 |            1.630→1.172 ms |                0.7187 |                  1.0336 |
|    2,048 |            3.710→1.746 ms |                0.4718 |                  1.0560 |
|    4,096 |            6.565→6.802 ms |                1.0362 |                  1.0479 |

The 2,048-element retained ratio spans 0.4493–0.5626. At 4,096, the existing
typed-view observation bound declines receipt capture; its overhead is retained
in the result. Initial partial samples and a debugger trace preserve the
incorrect earlier expectation of reuse at that size. Existing constant-scratch
controls have 196 samples: retained ratios are 1.0034 with 64 old values and
0.9759 with 32,768. These smaller changes do not establish a general speedup.

Ten iterator workloads use 4,096 rows, 31 alternating pairs, twenty warmups and
sixteen calls per sample. Profiling copies count objects separately from CPU on
ordinary Wasm. The additional callback admission gives:

| Adapter    | Objects before→after | Requested payload before→after | CPU ratio |
| ---------- | -------------------: | -----------------------------: | --------: |
| enumerate  |              8,192→0 |                 49,152→0 bytes |    0.0460 |
| zip        |              4,096→0 |                 24,576→0 bytes |    0.0344 |
| zip_strict |        49,158→45,062 |          376,880→360,496 bytes |    0.9082 |
| windows    |        81,894→81,894 |      1,277,540→1,277,540 bytes |    1.0049 |

Range/map/filter/take/pipeline retain zero objects; takeWhile retains two
predicate-creation objects. Their CPU ratios span 0.9962–1.0088. Answers pass,
committed guest memory stays 131,072 bytes, roots/leases finish at zero and
journal reset retains 4,096 bytes. All 62 packed width/type outputs are exactly
the prior qualified Wasm, preserving the existing boxed-reference evidence.

Raw evidence: `following-qualified-pins.json`, `following-gate/`,
`following-final-analyzer.log`, `following-measurement-summary.json`,
`captured-following/pairs.json`, `public-following/results.json`,
`following-growth-pairs.json`, `following-constant-pairs.json`,
`following-runtime/` and `following-packed/equality.json`. Tasks
024/035/047/058/086/093 remain open. Later optimizer matching and capability
input prototypes are separate from this frozen checkpoint.

## Shape-only members and retained graphs, 13 October 2026

Local `ae001bbb033809e79842e17918244ec9f084aafc` is frozen tree
`b9e400071b8e432bd8190cf8c49d12faacada9d9`, native source
`14c627c76cbfef133137c600c286f1a381e93e59`, based on `1a34c50`. Its Zig 0.17.0
LLVM/Fast binary SHA-256 is
`cad370ab8c149d1d009adae2c709b6cac6544bcc59691bc0884c3baac7a60d3a`; compiler
identity is `4d2a0e35de50a85c0fce0dc28843900e4978b0a903926a2114c9a7548d1afce1`.
Patch SHA-256:
`8dc6ab8ac772c4360bcea3da74654448ceeb6ee291e10d5cd0380052c88313ae`. The control
is the qualified `38e822d` binary from the preceding section.

The batch adds exact shape-only Array/List length evaluation, a bounded reverse
worklist for optimizer invalidation, generic explicit/dotted field body recipes,
compatible pure collection/pattern forms and ordered multiple-capability member
inputs. The linked component documents define their conservative boundaries:
[shape members](COLLECTION_SHAPE_MEMBERS.md), [body cutoff](BODY_CUTOFF.md),
[retained assembly](RETAINED_ASSEMBLY_WORKLIST.md) and
[scoped effects](SCOPED_EFFECTS_QUALIFICATION.md).

The final frozen gate passes **1,679 native tests, 1,061 guest/client tests and
375 analyzer files with zero findings**. All 1,029 ordinary allocation-failure
sweeps complete; two additional harness sweeps intentionally report an
unexpected scenario error with zero allocations. The 1,031-record profiler total
includes those expected-error laws. The full gate took 906.88 seconds: release
build 202.67, native compilation 279.34, native execution 388.36 and guests
19.56. Source, native subtree, patch and executable hashes are unchanged after
the gate. Main's executable and compressed compiler bundle match the qualified
binary.

The earlier combined run passed all 1,678 native laws but failed a guest law
whose exact-length fixture no longer required lexical interface projections. The
corrected fixture invokes an ordinary generic member that still exercises those
projections. That failed run remains under `later-gate/`; it is not the final
gate.

Its first release measurement also exposed a real revert regression: 1.0622
paired CPU ratio, with all selected reuse lost. Replay copied monomorphic
constructor-pattern payload roots that ordinary checking shares with the current
validated catalog. Four extra nominal type nodes changed the next revision's
ordered type graph and invalidated the whole selected-reuse gate. The repair
seeds only those zero-quantifier pattern payload mappings, preserving ordinary
annotation instances and record-pattern canonicalization. Strict catalog
validation remains unchanged. The new law compares the full Core type table,
Wasm, a changed nominal recipe and every replay allocation-failure point.

Seven alternating release pairs on CPU 6 give:

| Phase  | Control CPU ms | Candidate CPU ms | Median paired ratio |   Ratio range |
| ------ | -------------: | ---------------: | ------------------: | ------------: |
| Fresh  |       2225.518 |         1950.672 |              0.8767 | 0.8665–0.8832 |
| Edit   |       1247.822 |          906.212 |              0.7266 | 0.7249–0.7322 |
| Revert |       1147.918 |          813.715 |              0.7084 | 0.7071–0.7153 |

Every phase matches fresh compilation and the control in Wasm and source fuel
(70,330 steps). Edit/revert select 66/69 reusable judgments, evaluate
1,274/1,269 inference regions, and reuse 2,862 of 2,864 optimizer bodies.
Matcher work is 820,898 with no exhaustion. Constant receipts remain inactive on
this capture. Other isolated work and filesystem caches remain uncontrolled;
these paired results apply to the pinned current snapshot, not the historical
task 093 input.

Thirteen public programs, seven pairs each, preserve exact Wasm, diagnostics,
source fuel and zero teardown. CPU ratios are 0.9922–1.0065; requested
allocation falls by 128–3,056 bytes, while peak requested memory is unchanged.
All 62 packed width/type outputs match the previously qualified machine code
exactly.

Four body-cache suites have three alternating pairs at 64 and 128 siblings, with
population and sixteen edits measured separately: 192 samples including plain
controls. Linux process CPU clocks replace the earlier inadequate 10 ms sampling
ticks; original low-resolution runs remain preserved.

| Recipe           | Edit paired ratio, 64 / 128 | Population paired ratio, 64 / 128 |
| ---------------- | --------------------------: | --------------------------------: |
| Explicit field   |             0.7175 / 0.7075 |                   1.1843 / 1.1896 |
| Dotted field     |             0.7254 / 0.7169 |                   1.1528 / 1.1854 |
| If-let           |             0.7816 / 0.7748 |                   1.3260 / 1.3854 |
| Pure collections |             0.7587 / 0.7481 |                   1.2932 / 1.3256 |

The faster retained path costs more at population on these workloads. Plain
controls have retained ratios 0.9794–0.9873 and population 0.9871–1.0138. Guest
answers and cross-compiler output assertions pass throughout. RSS varies across
processes and is recorded in raw samples; it is not a deterministic allocation
claim.

Evidence under `build/bench/continuation-20261013/`:
`later-repaired-qualified-pins.json`, `later-repaired-gate/`,
`later-repaired-analyzer.log`, `later-repaired-measurement-summary.json`,
`captured-later-repaired/`, `public-later-repaired/`,
`later-repaired-body-summary.json`, `later-repaired-body-*/` and
`later-repaired-packed/equality.json`. Earlier failed/regressed combined runs
and diagnostic isolation worktrees remain separate. Tasks
024/035/047/058/086/093 remain open; proof task 070 and later iterator/effect
prototypes are unmerged.

## Selected effects and strict zip, 13 October 2026

Local `121eb59ccd751e6a61cb7ecf676d7a5253e73e1b` is frozen tree
`7b19d7a427ab1cf2a798b60a07cf585ce85d6e12`, native source
`adb955cc7c88209bc738b6246ec44bf83610a04c`, based on `ab4ab86`. Its Zig 0.17.0
LLVM/Fast binary SHA-256 is
`9414b47707e14fd2818453a643113d275a497271e7d967fd4fc241d77b9b6642`; compiler
identity is `d11c232cacab12e5a0d25db31c10555b7dfaa469c48ac9fbebeea0796a38c9a3`.
Patch SHA-256:
`0e748723f849fa11419ca3c111058cf08f1858c1680696d08d81cce4c0fdf55e`. The control
is the qualified `ae001bb` compiler from the preceding section.

[Selected effect identities](SCOPED_EFFECTS_QUALIFICATION.md) own both possible
origins and preserve identity through payload normalization. Their bounded local
scope excludes loops, nested ordinary callbacks and public generative selection
schemes. Structured Wasm control analysis now distinguishes reachable outward
exits, dead fallthrough and loop backedges; this removes fictitious joins that
blocked strict-zip scalar replacement. Optimized archive semantics advance to
version 23. Executed laws preserve nested alternatives, outward returns and
loop-carried snapshots in both codegen tiers.

The complete frozen gate passes **1,688 native tests, 1,066 guest/client tests
and zero findings across 375 analyzer files**. All 1,036 ordinary allocation
failure sweeps complete; the profiler also includes two intentional
expected-error harness laws. The gate took 933.29 seconds: release compilation
203.61, native compilation 298.96, native execution 396.76 and guests 21.39.
Post-gate source, patch and binary hashes are unchanged. Main's ignored compiler
and compressed bundle match. The release handshake and an independent fresh Zig
configure agree on identity. An isolated experiment with copied configure cache
returned an obsolete identity; that binary remains rejected and preserved.

Seven alternating captured-project pairs on CPU 6 preserve every phase's fresh
oracle, cross-compiler Wasm and source fuel (70,330 steps):

| Phase  | Control CPU ms | Candidate CPU ms | Median paired ratio |   Ratio range |
| ------ | -------------: | ---------------: | ------------------: | ------------: |
| Fresh  |       2014.867 |         2003.632 |              0.9980 | 0.9703–1.0223 |
| Edit   |        934.130 |          941.311 |              0.9973 | 0.9935–1.0736 |
| Revert |        835.391 |          834.855 |              0.9988 | 0.9741–1.0386 |

These paired medians describe near parity. Thirteen public programs, seven pairs
each, retain exact Wasm, fuel, results and zero teardown. CPU ratios span
0.9917–1.0118; requested allocation increases by 0–2,144 bytes and peak is
unchanged. All 62 packed width/type modules remain byte-identical, preserving
the previous packed qualification. Captured constant receipt activity stays
zero.

At 4,096 rows, strict zip falls **45,062→0 objects, 360,496→0 requested payload
bytes, 20,486→0 stores and 53,261→4,099 root reserve events**. Ordinary Wasm CPU
falls 2.899125→0.030000 ms (ratio 0.01035), with 31 alternating pairs, twenty
warmups and sixteen calls per sample. A second batch after the gate reproduces
ratio 0.0103. Allocation instrumentation uses separate Wasm copies and does not
affect those runtime clocks.

Windows remains at 81,894 objects and 1,277,540 requested bytes. Its first
runtime ratio is 1.0264; the follow-up is 0.9868. Both batches are retained and
no window improvement is claimed. The other eight adapters remain near parity
and preserve earlier allocation counts. Every workload checks boundary answers;
roots and leases finish at zero, journal reset retains 4,096 bytes and committed
guest memory stays 131,072 bytes. Other isolated work and filesystem caches are
uncontrolled; these are pinned workload measurements, not whole-project targets.

Evidence under `build/bench/continuation-20261013/`:
`selected-qualified-pins.json`, `selected-handshake-identity.json`,
`selected-full-gate.log`, `selected-gate/`, `selected-analyzer.log`,
`selected-measurement-summary.json`, `captured-selected/`, `public-selected/`,
`selected-packed/equality.json`, `selected-runtime.json`,
`selected-runtime-repeat.json` and `selected-adapters-ownership.jsonl`. Tasks
024/035/047/058/086/093 remain open. Later window, footprint and
[numeric-proof](NUMERIC_PROOF_QUALIFICATION.md) prototypes are separate.

## Pure product capability dependencies, 13 October 2026

Local `5378347d13b4dca9924335b73517252f9751a860` is frozen tree
`2a33efd3d26cfc4d2962caff4cfba752bfef6640`, native source
`77ce61121fb82567643514669d71ea1d1a2e5ef4`, based on `12e737c`. Zig 0.17.0
LLVM/Fast binary SHA-256 is
`88dcaa76609f7381de8ad79c10be5378bd79037ed4d6060c9a2e1b5d81f9b16a`; compiler
identity is `e7a53c2c2601822fc21c6ef9a330f072b258939b8a7a06b02a8dacd036f71bad`.
Patch SHA-256 is
`c78232fe253b5ab19a36d36c5409c3ea6584e367fbabe7007c9e0f1a1d9eaa99`. The release
handshake matches an independent clean configure; main's executable and
compressed bundle match that immutable binary.

Pure named helpers carry an owned mask of at most sixteen formal inputs through
nested products and constants. Exact private Core references validate decoded
claims, including coordinated interface/body tampering. Present summaries have
an explicit digest domain; absent summaries retain prior hashes. This permits
precise discard/return lifetimes without granting authority to unknown captures,
nonstructural calls, stores or general generative schemes.

The full frozen gate passes **1,693 native tests, 1,068 guest/client tests,
1,040 complete allocation-failure sweeps plus two expected-error laws, and zero
analyzer findings across 375 files**. Total 918.64 seconds: release 210.40,
native compilation 282.18, native execution 390.87 and guests 21.20. The
standalone maximum-binder/mask test in capability_flow.zig was discovered to
lack suite registration; it is excluded from this coverage claim. The executed
checker, emitter and artifact-forgery laws did run. Its separate registration
amendment belongs to the next batch; the frozen qualified source stays intact.

Seven alternating captured-project pairs against `121eb59`, on CPU 6, preserve
fresh/retained and cross-compiler Wasm and 70,330 source steps:

| Phase  | Control CPU ms | Candidate CPU ms | Median paired ratio |   Ratio range |
| ------ | -------------: | ---------------: | ------------------: | ------------: |
| Fresh  |       1957.040 |         1965.854 |              1.0047 | 1.0002–1.0102 |
| Edit   |        910.228 |          916.744 |              1.0073 | 1.0052–1.0115 |
| Revert |        815.505 |          816.032 |              1.0002 | 0.9978–1.0031 |

This is a feature qualification with a small measured compiler cost. Thirteen
public programs, seven pairs each, retain exact Wasm/fuel and zero teardown. CPU
ratios span 0.9965–1.0117; requested allocation increases 10,448–19,228 bytes
and peak increases 4,412–8,092. All 62 packed modules and the complete adapter
module are byte-identical. Boundary-oracle runtime controls pass; previous
strict-zip allocation evidence therefore remains applicable. No new runtime
improvement is claimed.

Evidence: `build/bench/continuation-20261013/footprints-qualified-pins.json`,
`footprints-handshake-identity.json`, `footprints-full-gate.log`,
`footprints-gate/`, `footprints-analyzer.log`,
`footprints-measurement-summary.json`, `captured-footprints/`,
`public-footprints/`, `footprints-packed/equality.json` and
`footprints-runtime.json`. Tasks 058/059 and the other 31 open tasks remain
open. The next invocation slice, window experiment, sparse body replay and proof
checker remain isolated.

## Callback and record footprints; completed window producers, 13 October 2026

Local `0d77afc91aedd8046050c2295c2e1d63b6a8f933` is frozen tree
`6ccad03d86cf095786689121cbc888a1cd54ebdb`, native source
`971d1a215326ce2e86db54ada1f11ef892f9f7c6`, based on `2992c80`. Patch SHA-256:
`2b5dc018980b31b2942729bd72f9f4e14e8fb443b9886409dfe05bd21eb7bb80`. Zig 0.17.0
LLVM/Fast executable SHA-256:
`b4fb67ca4eab5de4dfb923cab4b0c24c759b484f5817453fe4d19af8e26793a8`; identity
`826b02f2ad66e81b9f971120797935f7d5ecf4b10fa70534d0bcb54b663528c9`. Independent
clean configure, server handshake, main's executable and its compressed bundle
match. Source and patch hashes remain unchanged after testing.

Owned parameter recipes now describe a direct Unit callback invocation and
nested records/products. Exact callback ordinals, private body references and
retained field masks validate across dependency artifacts. Generic callback
payloads are recovered only from an already-bound exact owner and matching
operation evidence; ambiguity declines. Repeated row labels retain their
multiplicity. The standalone maximum-16 domain law is now registered.

Window production yields after its filling loop. Scalar replacement admits only
exact empty constructor aliases across completed nested producer loops; real
allocations and nonempty uses must retain the same outer activation. Reentered
producers, active inner uses, raw pointer words and disabled ownership decline.
The optimized artifact domain advances to v24. Wider no-gain root variants
remain excluded and preserved.

The frozen full gate passes **1,701 native tests, 1,075 guest/client tests,
1,050 complete OOM sweeps plus two expected-error harness laws, and 375 analyzer
files with zero findings**. Total 911.55s: release 203.27, native compilation
280.31, native execution 392.46, guests 21.50. Focused integration preflight
passed before freezing. The expected harness errors each exercise one failed
scenario with zero discovered allocations; they are not incomplete feature
sweeps.

Seven alternating captured-project pairs against `5378347`, on CPU 6, use each
compiler's own pinned standard library. Retained/fresh oracles and
cross-compiler Wasm are exact, with 70,330 source steps:

| Phase  | Control CPU ms | Candidate CPU ms | Median paired ratio |   Ratio range |
| ------ | -------------: | ---------------: | ------------------: | ------------: |
| Fresh  |       1959.049 |         1969.134 |              1.0049 | 1.0010–1.0125 |
| Edit   |        913.947 |          919.545 |              1.0074 | 0.9947–1.0131 |
| Revert |        814.800 |          818.481 |              1.0051 | 0.9928–1.0084 |

This is a feature qualification with a small measured compiler cost. Thirteen
public programs, seven pairs each, retain exact Wasm/fuel, requested allocation,
peak memory and zero teardown. Public CPU ratios span 0.9924–1.0103. All 62
packed U32/F32 record/tuple width outputs match prior qualified modules exactly.
The initial benchmark launch used an incorrect PATH and exited before executing
any measurement; its log is preserved separately.

At 4,096 rows, windows fall **81,894→77,800 objects** and **1,277,540→1,244,788
payload bytes**. Root stores increase 143,315→155,598 because the explicit break
carries roots; reserve events fall 167,888→163,795. Strict zip remains at zero
objects/bytes/stores and 4,099 reserve events. Boundary oracles pass; roots and
leases finish at zero, journal reset retains 4,096 bytes and committed guest
memory stays 131,072 bytes. Counters use separate instrumented copies, leaving
runtime clocks unaffected.

The root 31-pair window runtime is 9.064938→9.004063 ms, ratio 0.9933, near
parity. The isolated slice's three earlier ratios were 0.9788/0.9714/0.9966; all
are retained. The allocation reduction is established; a broad runtime win is
not. Remaining window fold, cursor and semantic-buffer work keeps 047 open.
Generative public contracts and general capture/store relationships keep 058/059
open. There are still 33 open tasks.

Evidence under `build/bench/continuation-20261013/`:
`invocation-qualified-pins.json`, `invocation-handshake-identity.json`,
`invocation-full-gate.log`, `invocation-gate/`, `invocation-analyzer.log`,
`invocation-oom-summary.json`, `invocation-measurement-summary.json`,
`captured-invocation/`, `public-invocation/`, `invocation-packed/equality.json`,
`invocation-runtime.json`, and `invocation-{control,candidate}-ownership.jsonl`.
The frozen worktree is `/var/tmp/blot2-continuation-invocation-20261013`.

## Qualified continuation, 14 October 2026

This is a qualified **uncommitted batch**, based on local HEAD `ef57ec5`. It
does not complete the program: 71 tasks are complete, 15 in progress and 14
pending. No commit, push or remote workflow is claimed. The complete pre-gate
handoff remains in the immutable source snapshot.

Frozen source: `/var/tmp/blot2-continuation-reuse-repaired-20261014`. The
manifest contains 1,177 files and 24,341,867 bytes; SHA-256
`1e6c2804d823e09ec96f2e75a0bd463e06d5c8280427665f7274c087e9e1d4cc`. All file
contents and the complete tracked/untracked file set matched after the gate. The
later qualification-note edits do not change compiler inputs.

Zig 0.17.0 LLVM/Fast release SHA-256:
`2693207b2dada8bd6305b510cab2efecb8ba524f429711854e64293760be6666`. Compressed
bundle SHA-256:
`398c616eecc7aab21bc80853ffb18eeaddd093a7f29101633190b9da283835f8`.
Decompression matches the release executable. The release handshake and an
independent configure with a new external cache both report identity
`a953759fdac4d10db77c5f4f55bc9820a16f43e07daea831a78dabcf0f60964c`. The
unrelated `deno.lock` remains at SHA-256
`9ca792a967d134b10168500f68a576a67008431574b7007e14978d22d7e4e781`.

The batch includes complete production ownership admission, scalar publication
and generalized-local storage repairs; exact constructor and generic forwarding;
single-leaf List traversal; capability, lexical-loan and scalar resource scopes;
runtime package carriers; numeric proof propagation; and owned typed staging
with bounded producer-local named calls. Each remains within its documented
admitted frontier. Reference resource payloads/transfer, general rank
publication, broader staging authority and generative capability contracts
remain open.

Ordinary body reuse now survives implementation modules and annotation-only
nominal/alias reads using the existing recipes. Explicit selected-call proofs
remain fresh. Retained executable reuse of static captures uses the existing
owned graph importer; promoted local initializers still require exact wrapper
reads and fresh code. The original cache-reuse guest assertions remain intact,
and the new initializer-owner law fails when its safeguard is removed.

The complete compiler gate passes **1,869 native laws, 1,170 guest/client tests,
1,133 complete allocation-failure sweeps and two expected-error harness laws**.
Both shards report zero skips, failed tests, leaks and logged errors. Full lint
under a working Zig/backend checks **417 files with zero findings**. A prior
isolated analyzer zero without Zig on PATH was invalid evidence; lint now checks
that prerequisite before every mode and keys local passes by actual toolchain
contents.

| Phase                 | Seconds |
| --------------------- | ------: |
| Preflight regressions |  14.686 |
| Smoke                 |   1.920 |
| Harness               |  16.886 |
| Release compilation   | 224.611 |
| Native compilation    | 309.869 |
| Native execution      | 177.299 |
| Bundle packing        |   1.778 |
| Complete guests       |  39.154 |
| Whole gate            | 564.842 |

Release and native compilation start together; native execution follows its
compile. A process sample records both LLVM workers running, about 5.4 GB
combined RSS. The native shards start 0.303 ms apart: 934 laws take 135.191 s,
935 laws take 177.261 s. The preceding failed gate took 619.700 s, but it used a
different source/test batch; their totals are not a controlled scheduler A/B.
The runner's ordering law passes and fails against the preceding runner. The
full fourteen-hill record and test-only build measurements remain in
[iteration costs](ITERATION_COST.md).

Three alternating captured-project pairs compare this release against qualified
`b4fb67c…`, using each compiler's own pinned standard library. The complete
screen takes 26.217 s; Linux child CPU clocks measure compilation, with no
concurrent agent builds. Project, compiler, client, script and standard-library
contents are pinned alongside every raw sample.

| Phase  | Control median CPU ms | Candidate median CPU ms | Geometric paired ratio |   Ratio range |
| ------ | --------------------: | ----------------------: | ---------------------: | ------------: |
| Fresh  |              1951.795 |                1941.131 |                 0.9990 | 0.9910–1.0135 |
| Edit   |               918.778 |                 843.265 |                 0.9178 | 0.9074–0.9258 |
| Revert |               806.954 |                 732.553 |                 0.9117 | 0.9030–0.9283 |

Fresh compilation is near parity; retained edit/revert CPU falls about 8–9% in
this bounded screen. Within each compiler, fresh, retained and repeated output
bytes and source work agree. Cross-compiler Wasm differs. Source work stays
70,330 and every constant-receipt counter remains zero: this is no constant
replay win. These three pairs do not replace task 093's complete performance
qualification or task 084's final targets.

Failed evidence is retained separately: the 653.382 s batch failed five native
laws; the following 619.700 s batch passed 1,864 native laws but failed static
capture reuse. Its separate guest sweep gave 1,165 passes and one failure. The
failed executables and source manifests remain immutable. A broad development
guest attempt stopped at its 60 s budget after 323 passes, without an assertion
failure; it was incomplete. The complete release gate above supersedes that
coverage gap, without reclassifying the timed-out attempt as a pass.

Evidence under `build/bench/continuation-20261014/`:
`reuse-repaired-qualified-pins.json`, `reuse-repaired-frozen-inputs.json`,
`reuse-repaired-release/`, `reuse-repaired-clean-identity.json`,
`full-gate-reuse-repaired/run-df20dfe025a99233/`,
`captured-reuse-repaired-pairs/`, `reuse-repaired-lint.log`,
`static-capture-reuse/`, `annotation-recipes/`, `types-test-extraction/`,
`build-overlap-control/` and `overlap-process-sample.json`.

A later isolated diagnostic against this exact frozen source completes three
captured phases within 60 s. The 57,019-step constant is nominal and excluded
before installing a receipt recorder; no inference query occurs in its value
work. The observed query in another constant already uses the retained principal
owner without ledger changes. This supersedes the older inference first-decline
attribution for the current workload. Compound constant value/slot/fuel
authority is the next measured frontier, with graph cost and
publication/rollback controls still required. The logging patch is unmerged; it
establishes no release timing claim. Pins, logs and assessment are preserved in
`constant-current-diagnostic/` under the evidence directory.

## Native gate repairs —15 October 2026

The later combined gate failed after 2,182/2,209 native laws passed; 27 failed,
with no skips, leaks or logged errors. LLVM/Fast release and LLVM/Safe native
compilation passed, but guest/pack phases did not run. Wall 667.702 s. The
frozen 1,302-file source manifest is
8d28eff26b6bc673591cc9fde56a033c5a15e2d0db6345961ce3d842e2a3b3c3; all files
matched after the run, before repair. Exact evidence is under
`build/bench/complete-program-20261015/final-qualified-gate/`.

Repairs retain the real negative controls. Shared usage/associated DAGs now
visit exact IDs once within unchanged work/depth limits; query-local negative
memoization invalidates on solver and owned nominal-catalog mutations. Optional
no-store publication declines exhausted proofs instead of rejecting ordinary
compilation. Completed generative/scalar roles are synchronized; named callback
composition requires executable no-store roles. Scoped partial application
reconstructs captures from its actual residual body. Tests repair malformed
owners, mutate the executed universal instance, accept supported packages/rank
closures while retaining witness/body forgery controls, and propagate injected
OOM correctly.

Ordinary body receipts now pay one optional pointer for loop metadata instead of
three always-present slices: 40 B saved per body without loops. The unchanged
sparse-budget law passes at 64/128/256 declarations (owned
65,522/128,618/254,954 B). Function provider indices occupy one byte, preserving
the preexisting 104 B machine-body header; existing known-role limits admit only
indices 0–31, with two byte sentinels. Journal/archive indices remain 16-bit and
validate before narrowing. Wide-index and stale archive controls remain
permanent laws. The compaction fixture now grows syntax without adding unrelated
type graphs; the qualified rebuilt seed correctly replays both wrapper and entry
(zero body elaborations). Demand explanation retains all four storage categories
and adds the existing unknown-callee case to exercise real indirect forcing.

The integrated repair union passes 35 focused native laws, 23 complete OOM
sweeps, 11 executed guests and 455-file zero analyzer. Each native group
finishes within 60 s. Ordinary Cost remains 11,958 B, byte-exact SHA
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. Development
compiler SHA baafbd63d7bfc8f35400d4b89f86796dd7218e58304988f9cc9ae85b23f0c3d9.
This is focused qualification; the final full compiler gate is still required.

Exact private/integrated patches, before/source pins, failure matrix, full logs
and selection/count records are retained in `native-gate-root-repairs/`,
`rank-package-gate-repair/`, `shared-dag-gate-repair-v2/`, `scope-gate-repair/`
and `combined-gate-repairs/` under the same evidence base. No task is closed,
commit made or source pushed by this repair batch.

The next full attempt stopped during native compilation: a test snapshot helper
correctly refused to hash the new optional loop owner as a borrowed address. The
helper now hashes presence and owned loop contents, leaving generic structural
hashing strict. Its existing mutation/rollback law also changes a real cached
loop carry and verifies the stamp changes/restores. The first added loop fixture
was below the existing syntax threshold; growing its actual body fixes the
fixture without reducing that threshold. Focused law, unfiltered Safe/noLLVM
compilation (2,215-law inventory) and 455-file zero analyzer pass. Evidence:
`sparse-owner-snapshot-repair/`. The failed attempt remains pinned in
`repaired-final-gate/`; it is not counted as a completed native run.

## Release guest repairs —15 October 2026

The next exact full attempt (`repaired-final-v2-gate/`) compiled release and
native programs, then passed 2,214/2,215 native laws. Wall 652.497 s; release
261.71 s, native compilation 385.69 s, native execution 245.20 s. The one failed
shared test helper incorrectly expected zero elaborations after a producer
ordinal change. It now takes explicit expected counts: unchanged entry zero,
relocated producer one. Both full allocation-failure sweeps pass separately
(2,362 and 3,072 allocation sites). `qualified-seed-expectations/` retains the
exact test-only patch and complete logs; no publication/rollback guard changed.

Release-only guest inventory in 13 bounded groups, without fail-fast, passed
1,393 tests and failed seven, with zero ignores. `bounded-release-guests/`
contains all file selections, JUnit reports and failures. The unchanged LLVM
binary is 13fe1a558ee6e5bba5383c9589fec9948ae7b0aa4a4a269858d0d2be7d23e16f.
Packing succeeded but does not qualify that executable or bundle.

The selected callback repair projects the checked reference signature through
its current owned implementation context before physical wrapper layout. Its
original callback law, both-tier U32/F32/Array Source/edit/checkpoint/JSPI laws,
Foreign and same-ABI Bool forgery negatives pass. Quantified numeric annotations
now replace temporary annotation representatives in persistent parameter types,
just as in their returned signature. Imported proof aliases use actual proof
kinds even without local proof syntax. Package readers traverse proof guards;
independent numeric validation remains authoritative, and existential data
witnesses still reject erased proofs. Portable Core copy/archive/OOM and forged
slots/guards/storage/owners pass. The integrated executed set passes 18 tests.
Opaque scalar-to-reference recovery counts primary plus fallback elaborations;
its original byte equality and 500 calls remain, and the integrated law passes.
Exact deltas: `selected-method-guest-repair/`, `quantified-proof-guest-repair/`,
`opaque-invalidation-metrics/`.

`pooled-call-regions/` recycles CallSummaries-owned ClosureRegion shells with
Zig's MemoryPool. Each new job still initializes all solver/scratch state; every
retired job deinitializes it before returning only raw shell storage. Session
teardown frees the pool. Full OOM retry/SCC/no-store controls pass.
Identical-path LLVM/Fast allocation falls 8,538,580 to 8,469,472 B (chain) and
16,361,857 to 15,426,859 B (fanout), with identical work counters. All eight
original release budgets pass unchanged. Development chain allocation is still
8,177 B over its release-oriented threshold; it is not reported as a development
budget pass.

Two original guest failures still need integration: compound buffer constant
receipts and public-example executable fragment reuse. No task is closed and no
full-gate success is claimed by these repairs.

## Retained-reuse repair union —15 October 2026

The final two failures from the 1,393/7 release inventory are repaired without
weakening either original reuse assertion. `buffer-creation-order-repair/`
canonicalizes immutable primitive container types and empty-argument nominal
identities, then retains original checker binding creation order in existing
body recipes. An exact scratch permutation relocates facts, branch merges, loop
carries/exits and path rebindings before publication. Ordered recipes pay no
scratch allocation. Either omitted type normalization still fails the original
law; source/catalog/receipt admission stays strict. Actual complete
fresh/replayed Core references, carries, bindings and types agree through both
capture and replay allocation-failure sweeps. All eight original receipt guests
pass unchanged in both codegen tiers.

`literal-fragment-repair/` admits semantic emission sites only through their
existing exact executable declaration or closure owner. Sparse exact node
membership is cached per immutable root; unrelated nodes, changed producers,
wrong owners, mappings and rows still decline. The same declaration projection
serves both declaration and expression proofs. A separate immutable capability
reader fix accepts only a discarded canonical Unit constant, matching ordinary
Source `use ()`. Noncanonical constants and effectful Unit calls still reject;
this fixes a legitimate published summary in `examples/scalar.blot`. The two
original public literal/state-provider laws pass unchanged, including positive
ECS and scalar reuse assertions.

The integrated union passes 29 executed tests (28
callback/proof/constant/literal plus opaque import recovery), the new receipt
capture/replay OOM law and two new fragment/Unit OOM laws. Private neighboring
native/OOM and 32 literal/import/state executed controls are retained with each
frozen patch. Unfiltered Safe/noLLVM compilation inventories 2,223 native laws;
the full 455-file analyzer is zero. Development compiler
SHA4356987350c7f18e5db58032a01e3fcaceda685079213ee471e119c0254fe223. Ordinary
Cost remains 11,958 B,
SHA1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad.
Identical-path development chain/fanout allocations are unchanged versus the
pooled-only control (8,514,140/15,584,621 B), with exact work counters.
Explicitly disabling persistent cache storage also gives equality at
8,253,857/14,039,271 B; those are separate environments, not a second budget
baseline.

All seven original guest failures now have integrated focused repairs. A new
full release/native/guest gate is still mandatory. Task035's private ownership
union and guard candidate require current-source performance qualification;
these functional results do not promote either candidate or close any task.

## Combined native failures and complete guest pass —15 October 2026

The frozen `functional-final-gate/` attempt takes878.659s and passes smoke,
harness, LLVM/Fast build308.176s and native compilation377.638s. Native
execution 479.533s passes2220/2223 with zero skips/leaks/logged errors; packing
and guests are not reached. Post-run verification matches all1303 source and41
external pins. The two native shards execute sequentially (226.394s
and253.054s), despite independent graph dependencies and -j2; no scheduler cause
is established.

Two body-cutoff laws depended on aggregate counts changed by successful fragment
reuse. `targeted-cutoff-test-repair/` preserves refinement fallback with only
the optional executable index disabled, actual refinement work and exact fresh
bytes through854 allocation failures. The second law uses a value-changing edit,
requires changed bytes and exact retained bytes, rejects the actual helper and
caller targets through the existing executable gate, and admits an unrelated
target. No production admission was weakened.

The third failure is a real numeric alias regression: a let before the first
proof introduction was omitted when tracking tested only current proof types.
`check-proof-alias-repair/` combines the existing local syntax flag with actual
imported proof kinds. The12 unchanged native laws pass3964 allocation failures;
12 executed numeric/universal groups and affected402-file analyzer pass. The
combined release/native gate remains required after this production correction.

Separately, `functional-release-guests/` packs the unchanged failed-gate release
and passes all1404 guest/client tests with zero failures/ignores, in33.268s.
All8 original compilation allocation budgets also pass. Release SHA
2c6834a7123bbe01876fb215507fd31fd5e7ff7cf0e50c473a9c5f62e872d83a and bundle
SHA08312874b4accd365082feb703facbee3827a0d3721c44e01b672e0e9bf3b856 are not
qualified by combining this guest-only pass with repaired native subsets.

## Current ownership compiler screen rejected —15 October 2026

`current035-screen/` preserves one CPU7 campaign with five balanced rounds, 15
records, one discarded warm round, positive whole-server CPU deltas and no
retries. Each record uses five fresh servers and20 retained edits. All three
current-source development builds, actual HELLO identities, bytes and closed
cycle counters pass preflight. Guard/control fresh1.114286 and edit1.010309
produce geometric mean1.0610245972, above1.05. Union/control also fails1.066424.
Guard caching changes union work by about0.5%, insufficient for admission.
Timing stops here: no runtime screen, LLVM/release qualification or promotion.
The private ownership changes stay out of the production source. Task035 and its
dependent tasks073/074 remain open.

## Qualified continuation, 15 October 2026

The final full gate passes in 697.812 s: 2,223 native laws, 1,404 guest/client
tests, 1,366 complete allocation-failure sweeps and two expected-error harness
laws. Both shards have zero skips/failures/leaks/logged errors. All 455 Zig
files have zero analyzer findings. Smoke/harness, LLVM release/native
compilation, native execution, packing and all guest/client tests pass together;
repaired subsets and preceding failed attempts remain separate.

Frozen source `/var/tmp/blot2-final-proof-repaired-20261015/source` is based on
uncommitted HEAD `ef57ec5b99b5ea25fc5532fd2d3023108d3f10bb`. Manifest SHA-256
3548546cb8660905de9a83922bab67270376a2b955f840f2bc7cf13fcefa53ec; all 1,303
source and 41 external pins match after the gate. Documentation/status updates
have separate hashes; no compiler source changes after verification. Evidence:
`build/bench/complete-program-20261015/final-proof-repaired-gate/`.

Release/decompressed bundle SHA-256
`6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`; packed
bundle SHA-256
`77ad409f11b952ba39fc3f752ceec30ffc1c762c95a76063ed4c2f77b75e1075`. Actual
development/release HELLO values match installed identities and fresh
independent configure runs: development
`8784e4a5b9145fda7464d75d13f865fb977469416fd8e871157cf39ccc556cfd`; release
`f6629ff06db42e26605376b8a4a3a81d0e0413dc492af05e541826a54003a2a2`. Qualified
copies and exact Zig pins are retained with the input manifest. Nothing is
committed or pushed.

The final delta repairs local aliases before the first proof introduction
without losing imported proof-kind activation. The two cutoff tests exercise
refinement fallback and exact changed-target invalidation instead of obsolete
aggregate counts. These repairs pass in the full native run. Tasks 070/071 now
satisfy their finite design, import/ownership/erasure and bounded-cost criteria;
the remaining 27 tasks retain their own broader acceptance requirements.

Captured compatibility verifies 415 input pins before/after fresh/edit/revert,
exact expected bytes and 70,330 source steps. Retained revisions reuse 1,152
named and 369 closure bodies. Concurrent timings do not qualify CPU or the 100
ms goal. Ordinary Cost remains 11,958 B/SHA-256
1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad. One capture
helper initially reused its prior evidence-directory template and reran the
older release; this is explicitly recorded in capture-history.json and
attempt1-error.json. The corrected capture pins the actual qualified release.
The original compatibility summary is preserved; repeated raw output is named
capture-repeat-20261015.json. No performance claim uses either repeat.

The last ownership screen remains rejected on its own earlier 2cbbc4c3… source
freeze; the final alias repair does not qualify that candidate. No private
ownership code is promoted, runtime performance gate rerun or cache deletion is
performed. Tasks 035/073/074, broader implementation/performance tasks,
exact-source remote CI 082 and owner choice 083 remain open. CONTINUE.md stays.
