# Implementation and iterator continuation

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
laws, 1,030 guest/client tests and 977 exhaustive allocation-failure sweeps**.
The unchanged frozen tree and binary were checked again after the gate.

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
**1,651 native tests, 1,043 guest/client tests, 1,002 exhaustive
allocation-failure sweeps and zero findings across 374 analyzer files**. The
source tree and release hash were verified after the gate. Four
local/packaged/standalone/CLI API tests also pass.

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
