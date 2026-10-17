# Numeric witnesses and finite check removal

Tasks 070/071 are complete under the approved bounded proof design. The final
[combined compiler gate](CONTINUATION_QUALIFICATION.md#qualified-continuation-15-october-2026)
passes 2,223 native laws, 1,404 guest/client tests and 1,366 complete allocation
sweeps, with 455 analyzer files at zero. The finite acceptance audit below
supersedes older checkpoint lists of unfinished selected-body support. Unknown,
wrapping, effectful or exhausted optional analysis retains checks as designed.

The final correction preserves local aliases created before the first proof
introduction while retaining imported proof-kind activation. The 12 unchanged
native neighbors cover 3,964 allocation failures; their contracts and all public
numeric/universal guests also pass in the combined gate. Exact final source,
release and identity pins are in
`build/bench/complete-program-20261015/final-proof-repaired-gate/`.

Witnesses have a distinct erased kind. Owned positional contracts name exact
value versions and collection lengths, including public parameters/results.
Source and compiled imports clone these contracts. Portable admission
reconstructs authority from executed guards, parameters, aliases and control
flow; coordinated header changes or deleted guards reject. Ordinary
polymorphism, aggregates and escaping closures cannot store witnesses.

Finite unsigned reasoning supports equality, strict/non-strict transitivity,
constant bounds, fit complements and exact index/length equivalence.
Contradictions grant no access. Owned plans track dominated true/false edges,
equality exclusions, resolved short-circuit edges and exact joins. Rebinding
creates a new identity; loop-body facts do not escape. Literal, fill/generate
and intrinsic length-preserving updates retain exact lengths. Optional analysis
failure keeps checks; invalid or exhausted required contracts reject. Plans are
recomputed, never imported as authority.

Both Wasm tiers omit proof parameters, closure words, locals, results and alias
operations. Necessary constructors keep ordered operand evaluation and traps.
Proven constructors and Array accesses lose redundant comparisons; reads and
earlier effects remain. The initial List batch retained internal runtime checks;
the later batch below removes repeated checks at proved access sites.

The later batch reconstructs finite comparison facts from selected named bodies,
using exact parameter order and collection identity. Unknown dispatch and
computed comparison operands decline. Directed nonwrapping addition/subtraction
and range bounds preserve versions; a failed refutable pattern's facts do not
escape into its success path.

Proved private List get/set use lazily emitted runtime helpers without a bounds
trap. Unproved accesses retain the checked helpers. Cursor reads retain their
required bounds check and avoid repeating it when resolving an uncached leaf.
Packed rows also avoid repeated word-address checks after their logical bounds
check. Journal replay preserves these helpers; absent proof work keeps them
absent. This does not add source-visible List indexing.

Zig 0.17.0 Safe/noLLVM checks on 13 October 2026:

- Combined source: 56 numeric native laws pass, including complete allocation
  failure sweeps. Development IR inspection finds one bounds comparison for an
  unproved access, zero for a proven access and one after a wrapping increment.
  Named-call inspection confirms erased argument/result signatures and only the
  two ordinary access temporaries.
- Six combined guest groups pass: three proof groups, two wide-ownership groups
  and one effect-footprint group. Proof execution covers both tiers, unsigned
  boundaries, changed collections, rebinding, ordered host effects before traps,
  failed-edit recovery and source/compiled imports.
- Isolated proof source: zero analyzer findings across 382 files.

Later combined focused evidence uses `zig-native/zig-out-dev/bin/blotc`, the
actual `build:compiler:dev` output:

- 18 selected-comparison native laws pass, including complete deterministic
  allocation failure and reversed/computed operand controls.
- 17 List native laws pass, including required versus removed runtime traps,
  lazy helper presence, emission-journal replay and complete allocation failure.
  Safe/noLLVM execution takes about 60 seconds for the latter sweep; broad OOM
  qualification continues to use LLVM.
- 16 combined guest groups pass: proofs, packages, closed universal contracts,
  bottom cancellation, sharing, mixed ownership, packed Lists and value-flow
  effects. Proof helpers execute through source/compiled imports in both tiers.
- Typed-staging frontend additions pass 17 native syntax laws and 25 client
  syntax/formatter tests with one existing ignored test.

Initial main guest logs used the older `zig-out/bin/blotc` and cannot qualify
the new integration. Corrected evidence is in `numeric-list-correct-guests.log`
and `combined-checked-production-guests.log`. The build command now prints the
exact executable path to prevent that selection error.

Logs:
`build/bench/continuation-20261013/combined-proof-{build,native,guests}.log`,
`proof-erasure-inspection-native-v3.log` and `proof-flow-analyzer-v2.log`. The
private proof worktree `/var/tmp/blot2-erased-proofs-070` preserves staged
production base `d55ab1cd`; its actual index is untouched. Main includes its
reviewed delta and later ownership/effect work. These focused results establish
neither full release qualification nor a speedup.

## Selected demand and forwarding bodies, 14 October 2026

The current source reconstructs Boolean conditions from exact captured demand
values and selected named call arguments. Negation, conjunction and disjunction
publish only facts justified by the observed result edge. Inspecting a demand
does not force it. Ignored arguments, reversed comparisons, wrapping arithmetic,
unknown dispatch and exhausted analysis retain the required checks. No source
name confers proof authority.

Two focused native ownership sweeps pass 2,577 and 2,747 injected allocation
failures plus their success runs. Development IR retains one bounds comparison
for an ignored condition and removes it for the selected valid guard. Two guest
groups execute both tiers through source/compiled imports, a named forwarding
chain, failed edits, revert and restart; skipped and forced panics remain
ordered. The combined 22-guest screen also passes. Evidence is under
`build/bench/continuation-20261014/proof-*` and `combined-guests/`.

This is focused development evidence. The full compiler gate, general associated
dispatch and release performance qualification remain outstanding.

## Exact helper-local aliases, 14 October 2026

Selected comparison bodies now preserve exact input versions through local
aliases, collection-length bindings and Boolean result bindings. The proof reads
the immutable body under its formal argument owner; nested blocks share the
existing work and depth limits. Unknown prefixes, wrapping computations and
unrelated rebound operands retain checks. No stored summary supplies authority.

Two new native laws pass, including a complete allocation-failure sweep. Four
neighbor/IR laws pass: an exact alias removes the bounds comparison, while a
wrapping alias retains one. Source and compiled imports, changed helper bodies,
failed edits, revert and restart execute in both tiers; the two guest groups
pass in 0.508 s. The changed wrapping helper traps at U32 maximum and matches an
independent fresh build. Type checking passes, and the pinned analyzer checks
226 of 418 files with zero findings.

The three-file delta and executable pin are in
`build/bench/finish-program-20261014/proof-local-aliases-source/`; focused logs
use `proof-local-aliases-*` and `proof-receipt-*`. This removes a redundant
runtime comparison for the admitted case; no compiler CPU speedup is claimed.

Selected result operands also reconstruct exact index identities and collection
lengths through forwarding and local blocks. Three new native laws pass after
integration, including portable teardown, complete OOM, forged body/parameter
controls and bounded fallback. Both import/archive/edit/restart guest tiers
pass. The admitted identity helper has zero bounds comparisons; wrapping plus
one retains one. Exact before/after source and compiler pins are in
`build/bench/finish-program-20261014/selected-numeric-operands/`. The private
neighbor screen passed eleven native laws, seven guest groups and 233-file lint
with zero findings. General associated bodies and final qualification remain
open.

Direct two-argument associated methods consume targets already selected during
body preparation. The optional plan belongs to that exact resolved body; the
numeric reader does not select targets again. Selected helper reads require
fresh code only when they remove an additional check. Ordinary bodies skip the
scan, and associated calls that add no proof keep reusable jobs.

Six integrated native laws pass, including 515 source/Core/plan, 1,378
backend/journal and nine resolved-body allocation failures. Both associated
guest tiers pass source/archive imports, method edits, changed order, failed
revisions, revert and restart. Identity bounds comparisons measure 1 to 0;
wrapping remains 1 to 1. Twelve ordinary development pairs preserve exact Wasm,
work and preparation counts, with generation timing near parity. Delta and pins
are in `build/bench/finish-program-20261014/associated-numeric/`. Nested
selected helper association, general shapes and final qualification remain open.

Exact U32 identity arithmetic in selected bodies shares the ordinary reader:
`i + 0`, `0 + i`, `i - 0` and `i - i` preserve their bit-pattern guarantees.
Four integrated native laws, 1,270 complete allocation failures and both guest
tiers pass with unsigned-max, source/archive imports, changed bodies and
restart. Independent before/after IR controls remove each identity's bounds
comparison; wrapping retains it. Production changes by 19 added and two removed
lines. Pins are in `build/bench/finish-program-20261014/numeric-identities/`.
General arithmetic and final qualification remain open.

Conditional selected results now join exact operands common to both arms. A
changed or wrapping arm retains its check; Boolean conditions keep the existing
reader. Four native laws and six guest groups pass, including condition traps,
branch edits, failed revisions, imports and restart in both tiers. The admitted
identity removes one bounds comparison. The affected 236-file analyzer pass has
zero findings. Exact pins and focused logs are in
`build/bench/complete-program-20261015/numeric-conditional/`; the full compiler
gate and general selected-body coverage remain pending.

## Returned selected closures, 15 October 2026

Exact prepared associated calls may now finish their two arguments through an
owned returned closure. The existing reader preserves its parameters and
literal/ alias captures under the same bounded work and depth. It does not
select a target again. Unknown bodies/captures and wrapping arithmetic retain
required checks. Root five focused native laws (complete OOM and journal
replay), five executed groups and 244-file zero analyzer pass.
Source/archive/checkpoint/restart, changed capture values, failure recovery and
sync/JSPI execute in both tiers. Development IR has 0 identity bounds
comparisons and 1 wrapping comparison; ordinary Cost Wasm stays exact.
Source/binary/log pins are in
`build/bench/complete-program-20261015/numeric-curried-methods/`. Nested
selected helper graphs, broader inference and final qualification remain.

## Exact U32 bit identities, 15 October 2026

Checked operand inference preserves unit multiplication/division, all-ones
masks,self AND/OR,zero OR/XOR and shifts with masked-zero counts. The value
identity is independent of input bits; arithmetic evaluation remains in place.
Root five native/full-OOM/replay laws,four executed groups,both tiers,archives,
checkpoint/restart,changed shift/revert,trap recovery and maximum-bit controls
pass. Exact identities emit zero bounds comparisons; changed operands retain
one. Selected analyzer 244/445 and TypeScript pass; ordinary Cost Wasm is exact.
Pins and failed-fixture provenance:
`../build/bench/complete-program-20261015/numeric-bit-identities/`. General
selected helper graphs and final combined qualification remain open.

## Remaining selected-method arguments, 15 October 2026

The immutable proof reader now follows additional applications of an exactly
prepared associated method. Receiver, initial argument and remaining arguments
are read in source order under the same work budget. The selected target and its
owned body remain the authority; absent selection or exhausted analysis retains
the bounds check. Additional erased/ordinary arguments do not become witness
evidence.

Three native laws pass, including complete owned-plan and emission/replay
allocation failures; three selected/curried/conditional neighbors pass. Six
guest groups cover both tiers, captured values, source/archive imports, edits,
traps, recovery and checkpoint restart. An exact three-argument identity emits
zero bounds comparisons; changing its final argument to one retains one.
Selected analyzer 251/453 files is zero and TypeScript checks pass. Ordinary
Cost stays byte-identical11958B; no compiler/runtime CPU improvement is claimed.
Pins and the initial fixture failures are preserved in
`build/bench/complete-program-20261015/numeric-remaining-arguments/`. The direct
literal-receiver lowering case is repaired by the next checkpoint; general
selected helper graphs and the final compiler gate remain open.

## Partially applied selected literals, 15 October 2026

A known selected method returning a function uses the same curried reference/
application representation as ordinary function values. It no longer creates a
saturated named call while source parameters remain unapplied. Existing exact
call signatures, evaluation order, effects and partial-closure ownership apply.

Two root native laws pass, including complete emission/replay allocation
failures after frontend teardown. Both new guest tiers cover a literal nominal
receiver, returned closure, final argument changes, bounds traps, archives,
checkpoint/restart and sync/JSPI. Exact identity emits zero bounds comparisons;
changing the last argument to one retains one. Four hundred affected analyzer
files report zero findings; TypeScript/lint/format pass. No CPU speedup is
claimed. Pins and the failing original control remain in
`build/bench/complete-program-20261015/numeric-literal-dispatch/`.

## Finite acceptance audit, 15 October 2026

Current owned summaries compose selected methods, nested named helpers, block
aliases, partial applications and returned captures. The finite design does not
require arbitrary helper execution or theorem solving. Earlier notes about
general selected helpers describe historical checkpoints; this audit found no
missing finite inference rule. Unknown/effectful callbacks, unmatched selection,
wrapping computations and exhausted optional analysis retain checks.

The composed selected-method example emits zero bounds comparisons. Changing its
result, passing an unknown callback or invoking a Foreign callback retains one;
the Foreign effect occurs exactly once before the required trap. Source/archive,
edits, failed revisions, revert, checkpoint restart and sync/JSPI pass in both
tiers. Root three native laws, including complete portable allocation failures,
eight guest groups and the shared 266-file zero-finding analyzer pass qualify
this slice. The private acceptance map also reruns nine prepared-body and 26
checker laws. The final combined compiler/release gate remains required.

The only production correction records consumed `Plan.visits` before returning
the plan, including optional fallback. The previous deferred assignment happened
after the returned copy. Budgets, proof authority and generated code are
unchanged.

| Query                                    | Visits | Peak bytes | Allocations |
| ---------------------------------------- | -----: | ---------: | ----------: |
| No-feature body                          |      0 |          0 |           0 |
| Nested selected returned closure         |    385 |       2144 |          39 |
| Equal-identity conditional helper        |    455 |       2144 |          47 |
| Optional budget of two                   |      2 |        460 |           4 |
| 256 required consistency requirements    |   4902 |      44620 |          21 |
| Shared 2049-term graph, 256 propositions |   2817 |      11560 |           4 |

All tracked storage is released. Twenty-five balanced whole-process CPU pairs
measure proof fresh/edit ratios 1.003/1.001 and ordinary ratios 0.987/1.005;
ordinary fresh samples are noisy. This is near-parity evidence for the counter
repair, with exact before/after Wasm, rather than a speedup or release result.
The acceptance map, workloads, raw samples and source pins are preserved in
`/var/tmp/blot2-numeric-finite-qualification-20261015/build/bench/numeric-finite-qualification/`;
root integration pins and logs are in
`build/bench/complete-program-20261015/numeric-finite-qualification/`.
