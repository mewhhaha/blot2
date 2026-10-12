# Frontend, demand and ownership qualification — 12 October 2026

Implementation `46bf8b9` completes tasks 039 and 055. It qualifies conservative
owned-body reuse and ownership subtraction milestones for 024 and 035; their
broader performance/coverage and tracing-removal gates remain open.

## Exact qualified inputs

| Input                      | Pin                                                                |
| -------------------------- | ------------------------------------------------------------------ |
| Incoming implementation    | `dd6a66a`                                                          |
| Incoming LLVM Fast binary  | `c0959e9a375b2ba8d2a2263278417fb917b434e733c9a13f80af1d372e80b060` |
| Release build tree         | `fe338f7062dccfa7214e20fe9687646a53526adc`                         |
| Final qualification tree   | `cfdd18a616412e3416a5169ea18dec38cf67ec28`                         |
| Compiler source tree       | `d96b286cbaa67afa5dc2bc24cc0469776e6fbd6a`                         |
| Qualified LLVM Fast binary | `47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095` |
| Compiler identity          | `ddaac9d20cb2f2e18dd530e5d6c08cb1240496f02c3124e4076c449446d9e4a3` |

The immutable executable is 43,006,168 bytes, retained at
`build/bench/joint-024-035-039-055/blotc-final-candidate`. The qualification
tree adds the corrected independent raw-wire fixture to the release build tree;
compiler source, identity and executable are unchanged. Source patches, pins,
all gate attempts and paired samples remain in the same ignored directory.

## Validation and corrections

Zig 0.17.0 was checked before each build batch. `deno task test:compiler` passes
the complete native suite and **914 guest/client tests**. All eight unchanged
allocation budgets pass. `deno task lint:zig`, using the pinned local analyzer,
checks 348 source files with zero findings. The regenerated host parser,
formatter laws, TreeSitter 0.27.1 corpus and public example parses pass.

Integration retains all three independently reviewed corrections: canonical
closed-row constraints replace cardinality-only equality; declared associated
row recipes and independent generic binders retain their original identities;
optimizer reuse compares complete admission **and frame demand**. The last has a
negative control: an unrelated new allocation requires a frame on an unchanged
reference-returning body, including a portable old candidate.

Strict structural hashing correctly rejected a test snapshot reaching owned
cache leases/map handles. Its replacement snapshots all plain preparation fields
and explicit immutable cache graphs, facts, reference counts, lease indices and
lookup relations. A populated substantial-body fixture and deliberate fact
mutation ensure the new cache is actually observed. Generic hashing still
rejects pointers. Two deprecated test helpers were corrected before
qualification.

One initial full guest run passed 912 tests and rejected its stale exact stats
field list. The independent protocol fixture now requires default null
`demandLowering` and checks the bounded opt-in report, filename/spans and byte
identity. All 36 focused wire controls and the repeated full gate pass. Failed
attempts remain preserved; none is substituted for final qualification.

## Paired release controls

Seven alternating cold pairs across 13 public examples use CPU 8. Diagnostics,
semantic code-instance/constant counters and prepared selection/flow counters
match. CPU ratios range **0.98836–1.02272**; no overall speedup is claimed. Peak
requested-byte deltas are +212–516, and total requested-byte deltas range −9,904
to +116,365 (the largest increase is monads). Every teardown has zero live
bytes. Ownership subtraction intentionally changes 12 public Wasm outputs;
scalar remains identical. Each compiler's output remains stable across rounds.

Monads and prelude each remove one allocation-role run (51→50 and 16→15):
unchanged immutable variant reconstruction now returns its original cell.
Parameter-role function counts remain equal. The original public harness's role
count equality assertion failed on this intended subtraction and remains
preserved; the final harness retains semantic/prepared equality and records
ownership deltas explicitly.

Seven synthetic pairs on CPU 9 preserve cross-compiler, fresh/retained/edit and
restart byte equality, diagnostics and teardown ownership. Millisecond CPU
resolution limits small-workload interpretation. The absent legacy gdev snapshot
is reported explicitly; these controls make no historical private-game claim.
Raw evidence: `public-qualified/{results,pins}.json`, `public-summary.json`,
`synthetic/results.json` and their full logs.

## Task 039: completed demand guarantee

Both tiers qualify aliases, imported forwarding, custom fixities, immutable
captures, compiled dependencies, checkpoints and failed edit recovery. Source
site reports own bounded data and never select a lowering. Exact no-op reports
remain independent; explained trivia refreshes spans. Unknown, recursive,
escaping and exhausted proofs retain shared storage under the documented limits.

Seven compiler pairs through 1/8/64/256 operators preserve incoming bytes.
Demand compile CPU is 1.273/1.908/7.394/30.568 ms; explicit controls cost
1.180/1.582/5.002/15.974 ms. Demand requested bytes are
279,314/734,981/4,367,381/14,993,902, 76 bytes above the isolated task-039
release. Proof visits are 16/128/1024/4096 and summary visits 16. All eight
forms have zero demand construction, memo-slot and indirect-force sites, with no
Memory/table.

Three complete guest batches retain all 32 taken/skipped/loop cases, 12 warm-ups
and 31 alternating CPU-7 pairs each. Median-of-three ratios to explicit controls
are **0.95096–1.01174**; individual outliers remain in the raw batches. Compiler
checking a demand chain still costs more than checking its explicit control.
Accepted harness pins are `06fe73ac…522d10` / `5467bf2f…18c4f`; the rejected
identical-predicate screen remains separate. Full pins and samples are in
`chains/{compiler-report,manifest,guest-report-1,guest-report-2,guest-report-3,guest-summary}.json`.
See [DEMANDS](DEMANDS.md) for semantics and bounds.

## Task 055: completed associated members

Defined equations, abstract applications and complete abstract signatures retain
scope/origin through type, row and operation substitution and portable wire3.
Exact equality coverage preserves independent binders; output projections never
invert to select inputs. Closed abstract storage reports
`missing_implementation`, open generic storage `missing_predicate`.
Admission/OOM/forgery/cycle laws and both-tier
execution/edit/failure/no-op/restart laws pass.

Final no-feature allocation counts and type nodes match incoming exactly;
requested-byte growth is 0.029–0.160%. First-edit CPU ratios are
1.044/1.042/1.063/1.018; subsequent edits 1.021/1.024/1.031/1.027. Distinct
projection DAG work remains bounded, and 128 levels reject at the documented
limit with all owners released. Exact graphs, CPU, named solver/scratch scopes
and handshake verification are in
[ASSOCIATED_TYPES_QUALIFICATION](ASSOCIATED_TYPES_QUALIFICATION.md).
Implementation declarations/selection/method execution now belong to 056.

## Tasks 024 and 035: qualified partial milestones

For the admitted 64-node body class, seven alternating CPU-6 pairs with 20 hot
edits preserve fresh/retained bytes within each compiler and expected execution
across both. At 128/512/1024 siblings, edit CPU drops **8→6 /33.5→23.5 /67→47
ms**, wall ratios are .720/.708/.710 and body elaborations fall to 2.5.
Population wall rises 25.3/35.2/37.7%; steady RSS rises .82/2.38/4.46 MiB, peak
deltas are −.36/−.79/+.20 MiB. Cheap bodies retain their elaborations: CPU
1.5/6.5/13→1.5/6.5/13.5 ms, wall +7.2/+3.8/+4.1%. These combined costs do not
claim the near-parity of the isolated corrected-024 binary. Exact controls are
in `build/bench/frontend-body-reuse/final-floor-llvm-qualification.json` and its
frozen small/deep harnesses. General forms and the under-100-ms target remain
open; later shared-callee and qualification followups are not in this release.
See [BODY_CUTOFF](BODY_CUTOFF.md).

Complete ownership admission, checked indirect results, scalar stores and
unchanged variants qualify without weakening conservative partial/raw routes.
The nested 90-row 8/40/200×8192-word discarded-Array law reclaims inner values
before exit while preserving outer rows, roots/leases and the one-page memory
bound. The frame-demand cache correction is included. Tracing remains for
uncovered paths; physical removal and CPU acceptance remain open. In the
separate pre-integration screen, cycles are about 5.65× the old tracing baseline
and sync scalar calls about 39.8% slower. These are failures to address, not
completed performance gates. Later flag/slot prototypes are separate. See
[TRACING_REPLACEMENT](TRACING_REPLACEMENT.md).
