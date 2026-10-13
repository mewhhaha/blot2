# Implementation and iterator continuation

This merged checkpoint implements task 056 and extends tasks 024, 047, 058 and
086 at local commit `10fab46`. The full gate passes. The broader tasks and task
084's iteration targets remain open.

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
