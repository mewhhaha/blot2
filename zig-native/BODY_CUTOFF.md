# Body interface cutoff

Task 024 lets semantic work stop at an unchanged interface when a body changes.
Before it, two things defeated this for edits inside a module:

- Refinement receipts, the retained semantic results that drive specialization,
  were admitted only when their root's module was structurally unchanged. Any
  body edit therefore re-inferred every region in the edited module, including
  closures in declarations that had not changed. Inference is the largest part
  of code generation, for example about 3 of 4.4 ms on an ecs edit.
- `for` loops were desugared into hygienic names that embedded the loop's source
  offset and syntax-node count. An edit that changed a module's length renamed
  every later loop variable, changed the project namespace, and so disabled the
  reuse gate for the whole program.

The compiler milestone is `a686304a31d49fe18f9f252e654995de7f10a951`.

## Receipt roots in edited modules

[The refinement lookup](src/reuse/refinement_receipt.zig) now admits a root by
its own declaration instead of its whole module:

- a body root when its declaration's exact projection and identity are admitted
  (`admitsLocalSource`);
- a closure root when its unit is structural, or when the
  [gate](src/reuse/principal_reuse_gate.zig) recorded, during the exact
  projection of a declaration in an edited module, that this declaration reaches
  that closure catalog entry, and that declaration's source and identity are
  admitted (`admitsClosure`). The projection compares the closure entry at the
  same index in both modules, so the old root names the same lexical closure.

Everything else is unchanged. A receipt still replays only if every collected
source body is exact, every consumed call judgment has an unchanged identity
(type, scheme, runtime and function-ness) and is already established in the new
session, and its expected shape, seeds, scalar reads (structural units only),
plain facts (structural units only) and imported results agree. This is the
interface cutoff: a consumer whose region read only a callee's interface replays
after that callee's body changes, while a region that collected the callee's
source re-infers. A projection also compares the binding record of every
same-unit declaration it references, so a changed interface revokes its
referencing owners.

Executable reuse is not widened. Retained fragments still require the transitive
dirty set, so every executable caller of a changed body, its selected evidence,
captures and staged inputs is regenerated; only the semantic inference those
callers need may come from receipts.

## Hygienic loop names

[The parser](src/parse/parser.zig) numbers `$collection.N` names within each
top-level declaration. Names stay unique where they are visible, and an edit
elsewhere no longer renames them.

## Qualification on 11 October 2026

The baseline is the task-023 compiler sources (`fbe28c8`); the candidate is
pinned with its probe in [the pins](qualification/body-cutoff-pins.json).

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 632 guest/client tests; `deno task lint:zig` reports
  zero findings across 310 files.
- [Native laws](src/reuse/body_cutoff_tests.zig): a same-size body edit replays
  the three receipts rooted in unchanged declarations and their closures, with
  fresh-identical output under an allocation-failure sweep; a callee body edit
  with an unchanged interface keeps consumer receipts, declines the region that
  collected the callee's source, and regenerates its executable callers. A
  mutant with the old structural root rule replays none of them.
- [A gate law](src/reuse/principal_reuse_gate_tests.zig) checks closure roots in
  an edited module: an unrelated edit keeps both closures, a closure body edit
  revokes only that closure, a callee body edit keeps the caller's closure, and
  a changed callee annotation (a changed binding record) revokes the referencing
  owner's closure but not an unrelated one.
- [A process-level law](tests/body_cutoff_reuse.test.ts) compares a retained
  server with fresh servers through a callee value change, a same-value body
  rewrite, swapped demand control flow, a changed effect trace, a failing edit
  and recovery; executed results follow every revision, and receipts replay. It
  also edits, reverts, breaks and re-edits five public-example body edits,
  including size-changing ones, with bytes and native work steps equal to fresh.
- `cli_profile.test.ts` compared counters from builds in two random temporary
  directories whose names vary in length; since task 021 the metadata counters
  include the canonical path, so it failed in roughly one run in five. Both
  builds now use equal-length sibling directories (0 failures in 30 runs).

### Measurements

The retained probe ran 21 alternating repetitions of nine rounds over seventeen
workloads ([CSV](qualification/body-cutoff.csv)); every phase emits identical
Wasm in both compilers, and retained memory plateaus. One-minute load was 40–49
on 16 threads (other sessions' builds and browsers), which roughly doubles
absolute times; the alternating pairs keep the ratios comparable. Steady medians
per edit:

| Workload                         | Refinement hits | CPU ratio     | Requested bytes |
| -------------------------------- | --------------- | ------------- | --------------- |
| ecs literal (non-scalar)         | 10 → 58 of 82   | 0.850         | −94 KB          |
| ecs body operand swap            | 10 → 58 of 82   | 0.844         | −94 KB          |
| monads literal                   | 6 → 23 of 32    | 0.851         | −24 KB          |
| generic_effects literal          | 0 → 5 of 7      | 0.956         | −3 KB           |
| requests body literal            | 6 → 9 of 18     | 0.994         | +13 KB          |
| lists size-changing literal      | 0 → 6 of 9      | 1.129         | +145 KB         |
| ecs / syntax size-changing edits | 0 → 0           | 1.008 / 0.997 | ~0              |
| other workloads                  | unchanged       | 0.97–1.02     | ~0              |

Steady CPU geomeans are 0.972 (edit) and 0.969 (revert); rejected-edit and no-op
controls are 0.995 and 0.999, and first edits 0.985.

Inference is the largest cost of the code a body edit regenerates, so admitting
receipts per declaration removes most of it when an edited module's other
declarations are unchanged. The size-changing lists edit now keeps its gate,
because loop names no longer move, and reuses one function and six receipts. On
that small program the per-edit verification costs more than they save, as with
effectful edits in task 023. The ecs and syntax size-changing edits still add
type nodes, which changes the type catalog and disables the gate.

The under-100-ms body-edit target is not demonstrated: gdev is not available in
this checkout. A separate session measured the current gdev checkout with the
`fbe28c8` compiler: a top-level scalar literal edit costs about 1.1 s of CPU,
about 60% of it re-evaluating entry constants. It also bisected a 2.3× slowdown
against `632b461` to `099e700` ("Share owned inferred principal graphs without
unfolding open diamonds"); disabling `reuse_principal_graphs` restores the old
cost there. Neither is addressed by this task.

## Remaining scope

- Core node and type IDs are module-global. A body edit that adds nodes
  renumbers every later declaration in its module; one that adds type nodes
  changes the type catalog, which disables the gate for the program.
  Size-changing edits therefore still lose most reuse.
- The project symbol table is ordered by first use. A new identifier spelling
  anywhere still changes the namespace and disables the gate.
- The frontend still rechecks every body of an edited module.
- Executable fragments of transitive callers rebuild even when the callee's
  summaries are unchanged; finer executable dependencies are not recorded.

## Owned frontend body facts (task 024 first slice)

Retained preparations now own sparse checked-body records in
[body_check_cache.zig](src/reuse/body_check_cache.zig), beside `Prepared`.
Immutable, independently leased chunks share frozen type graphs from
`dependency_snapshot`; `SchemeCopier` reconstructs fresh live types and rows.
Expression facts, parameter bindings and anonymous closed-row certificates
relocate by declaration-relative syntax positions and binding spellings. No
source tree, solver ID, substitution history, scratch pointer or previous
revision owner escapes into a new preparation.

Admission compares exact declaration text, parsed syntax and declaration traits.
Every consumed global interface must already be committed, with matching closed
principal type, quantified binder positions, privacy, runtime kind, function
status and external identity. Imported receipts also hash the producer's
original declaration spelling from the current catalog; an equal type at an
equal numeric slot does not admit a renamed producer. Canonical producer paths
must keep their unit ordinals; symbol ordinals need not match. Active SCC
members decline. The initial slice admits scalar literals, primitive U32/F32
intrinsics, applications, typed lambdas, conditionals, products and collection
literals over closed scalar/function/product/collection types. Annotations use
builtin scalar types and plain function/product types. Inferred generic
principals without residual obligations also qualify. Explicit generic
annotations, predicates, nominal/opaque shapes, demands, effects, providers,
operators, selected dispatch and additional metadata forms remain ordinary.
Proof walks stop at 128 levels and 4096 nodes; exhaustion declines reuse.

The scheduler still prepares annotations and dependencies and publishes ordinary
SCC schemes. Only admitted expression elaboration is skipped. Lowering, staging
and executable invalidation remain fresh. A callee body change with an unchanged
interface can keep a consumer's checked facts; its current executable body and
captures are still regenerated. Failed preparations and OOM never replace the
last successful owner. An unchanged preparation retains independent leases to
its immutable facts when needed; ordinary one-shot checks and editor queries
capture no body records. These records are in-memory owners, not a new artifact
wire schema.

Focused native laws cover insertion of earlier AST/type nodes and new spellings,
interface/privacy/runtime revocation, generic and recursive/demand fallback,
snapshot/replay/copy allocation failures, original imported-name revocation, the
actual proof limit, and linear owned payload growth. Executed-Wasm laws compare
retained and fresh output across sibling body edits, insertions, imported
producer renames, nested captures, numeric-array ownership, a failed revision
and recovery. On the focused seven-body server insertion/edit, elaborations fall
7 to 2 while all seven bodies lower and Wasm is fresh-identical.

Before immutable chunk leases, the native parse/check/capture/lower growth law
edits one scalar seed beneath 64/128/256 typed sibling functions. Elaboration
falls 66/130/258 to 1; requested bytes fall 859332/1598032/2843784 to
747352/1358640/2516232, and peak requested live bytes fall 340012/708304/1305387
to 275592/560936/1095299. Owned payloads (excluding container capacity and hash
buckets) are 42400/83992/167320 bytes; shared graph nodes are 265/521/1033.
These are focused safe no-LLVM allocator measurements, not release CPU timings
or whole-program acceptance.

This remains a partial task-024 boundary: broad language-body admission, SCC and
selected-evidence reuse, producer ordinal relocation and finer executable
cutoffs are open. The earlier backend receipt limitations above still apply
outside this frontend slice. Full integration and release measurements are
root-owned and pending.

In that initial implementation, the bare no-record control requests
682880/1274904/2253124 bytes at those sizes. Fresh snapshot capture therefore
adds 25-26% requested allocation; replay still requests 6.6-11.7% more than bare
checking. Its per-preparation peak is lower, but the previous snapshot was
allocated separately and is excluded from these phase peaks. SafeAllocator
growth can also depend on bucket occupancy. These laws establish work reduction
and bounded ownership, not net allocation or CPU improvement over the old
compiler. Release comparisons and retained-session memory must account for the
complete previous owner.

### Immutable chunk leases and measured recapture subtraction

A successful checked-fact replay now retains its immutable chunk directly in its
unpublished preparation. Only newly elaborated eligible bodies are frozen.
Chunks retain allocator provenance, and their graphs, names, source, facts and
bindings survive independently of the previous revision. Failed preparations
release all unpublished leases. The checker still reconstructs fresh live
variables and rows; no live solver state is shared.

Partial chunks compact when obsolete body bytes or bounded type-projection work
dominate the currently leased bodies. This prevents successive edits from
pinning a complete module-sized chunk for one surviving declaration in every
generation. Compaction rebuilds immutable facts from current checked metadata;
it does not re-elaborate admitted bodies or mutate earlier owners. Native laws
replace all but one additional body successively across 32/64 generations:
complete leased body/graph payload grows 19886/38894 to 39317/77177 bytes, with
6/7 chunks, and stays below three times initial payload throughout. Another law
removes a wide result graph while keeping larger scalar syntax payload;
type-work accounting compacts that graph too. Publication and compaction are
covered by exhaustive allocation failures, including unchanged previous lease
counts.

In the current safe no-LLVM growth law, bare checking requests
682880/1276548/2253124 bytes for 64/128/256 siblings. Fresh capture requests
861872/1603304/2859068; replay requests 587138/1097042/2008738, about 11-14%
less than bare. Complete leased payload is 45126/88766/176190 bytes. Phase peaks
still exclude the separately allocated previous owner; process memory is also
measured below.

The first LLVM/Fast candidate, which recaptured every reused body, was rejected
on performance. Seven alternating pairs at 128/512/1024 one-application sibling
functions reduced elaborations to 1.5 per edit but regressed edit wall medians
by 9.7/11.0/10.9%. Populate regressed 5.1/17.3/21.2%. Its incoming binary
SHA-256 is `bb85a4e090f23d1ca6c99eee13740f8e2725d3a657334ea6cf1db153a0ea3e56`;
candidate is `4fa2f947a96e722faba74496192e14bad0308bfdac5bf5bfe09ce538f72a7227`.
Build command: Zig 0.17.0, `taskset -c 5 deno task build:compiler`, standard
Fast with LLVM enabled. Each sample populates one retained server and measures
20 alternating insertion/seed edits. All cross-binary fresh/retained Wasm hashes
and exported execution match. Raw distributions and negative pins are retained
in `build/bench/frontend-body-reuse/paired` and `negative-first-slice.json`.

A matched no-LLVM/Fast development screen of chunk leases brought simple-body
edit wall times within about 1% of bare checking; it did not demonstrate a CPU
gain. Five alternating pairs on CPU 6 with twelve primitive applications per
sibling instead reduced edit CPU 35 to 31 ms at 64 siblings, and 69 to 62 ms at
128. Wall medians were 35.67 to 31.77 and 70.21 to 62.17 ms. Populate remained
about 20% slower; retained process RSS increased about 0.1/1.0 MiB, and process
high-water memory fell about 0.4/0.3 MiB. These are development screens, not
final LLVM qualification; they precede the explicit lease wrapper and
generic-binder extension. Both binaries use
`zig build install compiler-identity
-Doptimize=fast -Dllvm=false`, and every
module hash and executed result matches. Raw reports are in
`build/bench/frontend-body-reuse/chunk-screen` and `deeper-screen`. Simple-body
costs and capture admission remain performance work; no completion or blanket
CPU improvement is claimed.

Generic laws relocate inferred binders across inserted earlier type/syntax nodes
and new spellings, specialize independent scalar/array consumers, and revoke a
consumer when the generic result changes. Binder positions are canonical in
public digests; frozen variables reconstruct as fresh current-store variables.
Native generic replay has an allocation-failure sweep; executed-Wasm laws cover
U32, F32 and owning array specializations, generic body edits, rejected
revisions and recovery. Residual predicates and selected evidence still require
further owned facts and authoritative fallback.

### Current admission and portable identity extension

Production capture now requires at least 64 admitted syntax nodes, matching the
measured positive twelve-application class. The same bounded visitor first
counts without allocating or hashing; skipped bodies check and execute
ordinarily. Native boundary laws explicitly set a zero floor to exercise small
proof shapes; actual Session/OOM and executed-Wasm laws use substantial bodies
and verify the production policy. Final LLVM comparisons retain a simple-body
control as well as the admitted deep-body class.

Inferred generic type binders and symbolic callback rows relocate independently
of previous solver ordinals. Public digests hash quantified type/row positions,
row labels and closure-certificate counts. Reconstructed rows preserve the
relationship between a callback input and its latent output function; a Foreign
callback remains Foreign and executes exactly once. Other operation identities
and residual predicates stay ordinary until their complete reads are owned.

Monomorphic nominal and opaque passthrough/application facts also qualify.
Chunks store owned original producer-unit/name, declaration-kind,
privacy/opacity and storage-recipe receipts. Their frozen nominal nodes contain
chunk-local indices; replay resolves those indices to current catalog identities
rather than retaining previous AST or symbol ordinals. Producer paths still must
keep their unit ordinals. Unknown or redacted original names decline. Local
monomorphic annotation reads separately pin declaration kind, spelling, privacy
and expanded type, so alias retargeting or privacy changes revoke the annotated
body even if its old nominal still exists. Namespaced/imported type annotation
aliases conservatively decline; inferred calls can qualify when the current
nominal catalog is complete.

Native laws insert earlier nominal/AST/type nodes and new spellings, compare
fresh Wasm under exhaustive allocation failures, retarget local aliases, change
alias privacy and change opaque storage from U32 to Array U32. Executed-Wasm
laws exercise source and compiled imports, insertion/seed edits, and the opaque
scalar-to-reference edit with 500 calls per lane. Storage edits re-elaborate
consumers; lowering and ownership always use the current definitions.
Constructor/projection operations, generic nominal parameters, explicit generic
annotations, residual predicates and selected evidence remain ordinary. This
checkpoint extends the admitted boundary and keeps task 024 active.

### LLVM/Fast admission checkpoint

The frozen source tree is `297dc9b0947449799597aec849a5bd4bfc825024`, compiler
source subtree `c61cd0f717a73024f62bd084a0af483182b4d580`. Standard Zig 0.17.0
`taskset -c 4 deno task build:compiler` produced SHA-256
`c733afe3d7490033509e042c2182292cc751dacb824c20596db0e346e46eea86`, identity
`bc90a393f2343cd489b6caeab315a61b79ad78ce3c0c169269d0164574558073`. Incoming is
qualified `f184dde`, source tree `310d60ce85a8ebe26f3c9f4d48fc35811fd98a94`,
binary `5c689ad5caad6952f1c4643f5c40e10d6e41bcf819bf016f751ac105d82020a1`. Both
are LLVM/Fast builds.

Seven alternating pairs on CPU 6 at 128/512/1024 siblings measure twenty warm
insertion/seed edits per sample. Root builds occupied CPUs 0-3; raw environment,
all samples, exact pins and limitations are in
`build/bench/frontend-body-reuse/floor-qualification.json` and its referenced
`floor-small-llvm`/`floor-deep-llvm` directories. Every fresh/retained
cross-binary Wasm hash and exported result agrees.

| Class                   | Edit CPU, incoming → candidate | Edit wall ratio | Populate wall ratio |
| ----------------------- | ------------------------------ | --------------- | ------------------- |
| Small, 128 siblings     | 1.5 → 1.5 ms                   | 1.009           | 0.990               |
| Small, 512 siblings     | 6.5 → 6.5 ms                   | 0.994           | 0.983               |
| Small, 1024 siblings    | 13.5 → 13.5 ms                 | 0.995           | 1.007               |
| Admitted, 128 siblings  | 8.5 → 6.0 ms                   | 0.697           | 1.171               |
| Admitted, 512 siblings  | 34.0 → 23.5 ms                 | 0.689           | 1.248               |
| Admitted, 1024 siblings | 68.5 → 47.0 ms                 | 0.680           | 1.274               |

The admitted twelve-application class improves steady edit CPU about 29-31%
while first capture costs 17-27% wall time. Steady native-process RSS increases
about 1.0/2.5/4.5 MiB; high-water memory changes by about -0.08/+0.19/+1.14 MiB.
The small-body control retains ordinary elaboration and stays near parity, with
about 0.5 MiB more process RSS. `/proc` CPU ticks are 10 ms, so first-populate
CPU and the small edit samples are coarse; wall distributions remain recorded.

The checkpoint passes 32 focused native tests (17 behavior/ownership/OOM laws
and 15 suite anchors), five executed-Wasm laws, all eight unchanged allocation
budgets and zig-analyzer 345 files with zero findings. Formatting and diff
checks pass. Root owns combined full qualification. This is measured acceptance
of the admitted slice; residual/selected evidence, generic nominal parameters
and other ordinary fallback scopes above keep task 024 active.

### Generic records, residual predicates and selected evidence follow-up

The follow-up is based on qualified production `dd6a66a`. The earlier measured
checkpoint and its binary remain immutable. This adds inferred generic nominal
arguments, record parameter shapes and anonymous record values. Field names in
the frozen graph are owned spellings; their numeric words are chunk-local
indices, relocated through the current symbol pool. Public record interfaces are
hashed in lexical field order, with bounded scans. Sparse projections and
selected call signatures occupy side tables only for bodies that use them.
Lowercase annotation variables follow the ordinary annotation rule; local
monomorphic aliases still require their independent expansion/privacy receipt.

Implicit associated and result-associated residual predicates are owned with
frozen type/row graphs and declaration-relative source positions. Replaying a
symbolic helper appends those requirements to the current solver. Qualified
references instantiate their current principal rather than copying forwarded
requirements a second time. Predicate kind, member, operator, quantified
variables, rows and every type part participate in interface equality.

Concrete selected evidence also records the complete set of matching associated
members, including candidates rejected before the winner. Its digest pins
original owner identity, member, binding identity, privacy, runtime mode and
complete admitted interface. An insertion or interface change therefore revokes
old solved caller types, including an implementation that acquires a Foreign
row. Matching catalog keys must be unique, there can be at most 64 candidates,
and all source candidates must already be complete. Active, late, unknown or
exhausted evidence remains ordinary. Source operators additionally re-resolve
the current fixity target before consuming facts; equal body syntax and equal
function types do not admit a retargeted operator.

Chunk compaction now weights reachable graph words, rows and owned field/nominal
spellings, in addition to live body payload. A 16-generation law changes a
4096-byte field spelling supplied by an uncached producer while preserving a
larger scalar AST body. Each generation compacts the obsolete graph, and total
leased payload stays below three times its initial size. Existing 32/64-
generation replacement laws and allocation-failure laws remain in place.

Focused qualification: Zig 0.17.0, Safe/no-LLVM native build, 38 native tests
(23 behavior/ownership/OOM laws and 15 suite anchors); Fast/no-LLVM compiler,
eight executed-Wasm laws and all eight unchanged compile-allocation budgets; 346
analyzer files with zero findings. Executed laws cover generic opaque
scalar/reference specialization, source and compiled opaque representation
edits, reversed field spelling order with owning Array payloads, selected
implementation body edits, Foreign-interface diagnostics and failed-edit
recovery. Every successful retained module is compared byte-for-byte to fresh
output, and failed diagnostics are compared to fresh diagnostics.

The current Safe/no-LLVM, explicit-floor-zero growth control requests
686696/1276548/2253124 bytes for bare checking at 64/128/256 siblings; fresh
capture requests 887084/1653044/2983808, replay 591590/1097678/2010886. Complete
leased payload is 54302/106646/211478 bytes. These phase measurements exclude
the separately allocated previous owner and are not release CPU or whole-process
memory qualification. Final matched LLVM/Fast costs are pending; the earlier
checkpoint's measured gain cannot be attributed to this follow-up.

Task 024 remains active. Explicit qualifications, shared `callee_use`
predicates, other effect-operation identities, namespaces in type annotations,
curried type-constructor heads and unsupported expression/pattern forms remain
ordinary. SCC and late-edge inference remain authoritative. Producer unit
ordinal relocation and the general under-100-ms target also remain open. No
standalone full compiler gate or completion record is claimed here.

### Closed-row certificate review correction

A separate correction to the frozen follow-up replaces the certificate-count
comparison with canonical constraints. Each closed-row entry names either its
position among public row quantifiers or every structural path where its
anonymous variable occurs in the raw binding type. Covariance closing returns a
copy and leaves those raw paths available. Paths and constraint digests are
sorted; numeric solver IDs and field-symbol ordinals are not interface keys.
Unknown targets, more than 128 constraints/paths or exhausted traversal decline.

Imported principal roots have already been closed. Their original producer
therefore supplies a borrowed, independently computed certificate digest from
its checked or portable raw binding type; only the digest survives capture.
Source and compiled imports use the same rule. The interface-validation schema
permits certificates to select different quantified rows, so the native law
constructs equal-arity/equal-row-count schemes whose selected binder positions
differ. It also distinguishes anonymous paths under identical closed public
shapes and rejects an unrelated row target. All 39 focused native laws, eight
executed-Wasm laws, eight unchanged budgets and 346 analyzer files/zero findings
pass with this correction. The preceding frozen patch and binary remain
unchanged; final release costs require the corrected candidate.

### Integrated admitted-body milestone (12 October 2026)

Implementation `46bf8b9` includes the owned immutable chunk floor, generic
nominal/structural and selected/residual evidence slice, and corrected
closed-row certificates. Native tests, 914 guest/client laws, eight unchanged
budgets and 348 analyzer files/zero pass. The populated prefix-guard test
snapshots cache contents rather than lease/map addresses and detects a
deliberately changed fact.

Final matched LLVM Fast
`47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095` versus
`c0959e9a…80b060` measures admitted 128/512/1024-sibling edit CPU 8→6 /33.5→23.5
/67→47 ms with 2.5 body elaborations. Population costs rise 25.3–37.7% wall,
steady RSS .82–4.46 MiB; cheap-body wall rises 3.8–7.2%. These are
combined-candidate limits, not the earlier isolated near-parity claim. Exact
pins, memory deltas and controls are in
[FRONTEND_OWNERSHIP_QUALIFICATION](FRONTEND_OWNERSHIP_QUALIFICATION.md).

Task 024 remains open. Later shared-callee, explicit-qualification and portable
origin/body-offer work is isolated and not in this release. General supported
forms, producer-unit relocation and the under-100-ms target remain unfinished.

## Shared principal edges (task 024 follow-up)

An acyclic shared `callee_use` edge is now an admitted interface read when its
completed principal contains only implicit dispatch/result predicates or other
admitted shared edges. The receipt hashes the complete transitive principal,
original declaration spelling/kind/privacy/runtime and producer identity,
canonical public type/row binder positions, and the sharing recipe flags. A
borrowed current catalog proves completion; the retained owner stores only the
resulting digest. Cycles, unavailable or redacted original names, unsupported
predicates and exhausted proof budgets continue through ordinary checking.

The proof visits at most 64 principals and 4,096 type/predicate nodes.
Closed-row certificates retain their separate bounded path proof. The same
64-principal limit collects all transitive dispatch member names, so candidate
presence and negative candidate interfaces remain reads even behind wrapper
layers. Exact wrapper bodies still undergo syntax and identity checks
independently.

Replay reinstantiates the current qualified reference at its relocated source
node. It does not copy a `callee_use` solver identity into the owner or
duplicate its forwarded predicates. The normal shared-use solver remains
authoritative for selection, generalization, effect propagation and diagnostics;
lowering and executable encoding remain fresh.

Focused evidence: 40 Safe/no-LLVM native laws (25 substantive plus 15 suite
anchors), nine executed-Wasm laws and eight unchanged allocation-budget laws;
346 analyzer files, zero findings. Native laws cover two wrapper layers, an
alias, insertion/new spelling, same-interface selected-body edits, new negative
candidates and every allocation failure. The executed law traverses two generic
wrapper layers, changes the selected operation body, rejects a Foreign interface
edit in a pure consumer with fresh-identical diagnostics, and recovers. Source
and compiled imports relocate shared producer schemes, recover after an
unbound-name revision, and regenerate changed selected implementation values.
This follow-up has no LLVM performance claim yet. Task 024 remains active for
explicit qualifications, other residual predicates and unsupported body forms.

## Source declared qualifications (task 024 follow-up)

Top-level source `associated` and `type_rep` clauses are admitted alongside the
shared-principal proof. A declared predicate includes its explicitness, complete
type/row signature, and original qualification owner's spelling/privacy/runtime
with a span relative to that declaration. A direct owner lookup is constant
work; a forwarded origin uses a bounded scan. Missing owners, higher-rank
scopes, other written clause kinds and explicit effect-row syntax remain
ordinary. Imported explicit clauses remain ordinary: the current compiled
principal schema has no canonical source-owner route for that origin. No
portable-origin identity is invented from a solver ID or a consumer AST
position.

`beginGlobal` recreates the current declared obligations and qualification
boundary before any replay. Capture does not duplicate those declared clauses.
References instantiate their current qualifications, and the ordinary solver
checks coverage and publishes the resulting scheme. Declared dispatch members
also pin the complete positive/negative candidate catalog, preventing solved
body facts from concealing a new effect or operation interface.

Focused evidence: 41 Safe/no-LLVM native tests (26 substantive plus 15 suite
anchors), ten executed-Wasm laws, eight unchanged allocation-budget laws, and
346 analyzer files with zero findings. The new laws relocate quantified clauses
past inserted AST/type nodes and new spellings, specialize U32 and F32 callers,
sweep allocation failures, regenerate same-interface operation values, compare
wrong-clause and Foreign failures with fresh diagnostics, and recover. This
isolated follow-up has no LLVM qualification yet. Task 024 remains active for
portable imported qualification origins, other residual/effect-operation kinds
and unsupported general expression/pattern forms.

## Portable imported qualifications and seed rebuild offers

Imported explicit qualification origins now use a bounded producer receipt
instead of requiring a source tree in the consumer. A source producer identifies
its declaring `where` owner directly. A compiled producer's parallel
`obligation_spans` identifies the original constraint inside its qualification
span, excluding forwarded use sites; its frozen Core binding/body supplies the
same declaration span and runtime flag. The original producer spelling/privacy
and declaration-relative qualification span produce the same owned digest.
Ambiguous, redacted, missing or out-of-bounds owners decline. Each producer scan
is bounded to 4,096 bindings and obligations. The archive schema is unchanged.

The rebuilt-seed consumer path previously passed no previous frontend offer. It
now offers independent body leases while explicitly disabling whole-entry and
whole-module cutoffs. A body-only offer requires unchanged check settings, a
live previous owner with complete paths/cache arrays, and exact filename pairing
in the current checker. Each body still proves its own exact source, current
identities, interfaces, candidate reads, annotations and committed callee
states. Old seed/Core address pairing remains mandatory for whole-entry or
module offers; body leases have their own immutable owners. Executable and
staging invalidation remains authoritative.

Focused evidence: 42 Safe/no-LLVM native tests (27 substantive plus 15 suite
anchors), eleven executed-Wasm laws, eight unchanged allocation budgets, and 346
analyzer files with zero findings. The new executed law covers source and
compiled imports, entry insertion/failure/recovery, an earlier producer body
that adds AST/type nodes and a first-use field spelling, and an operation body
edit with changed execution but unchanged public interface. The new native
allocation-failure sweep exercises a rebuilt producer seed and retained
qualified consumer, checking fresh output, unchanged previous stamps, balanced
chunk lease counts, discard and successful retry. This isolated follow-up is not
LLVM-qualified. Task 024 remains active for other residual/effect-operation
kinds, generic annotation heads, projection/pattern/block/control forms and
producer ordinal relocation.

## Applied annotation and constructor recipe reads

Local applied generic annotations now admit data/opaque heads, shaped
transparent aliases, `Array`/`List` heads and tuple/array/record argument
syntax. The receipt uses the current owned parameter-pattern store to hash
binding, tuple, array and record recipe kinds, canonical type-binder positions
and field spellings. Aliases pin their complete expansion and quantified
effect-row positions. Nominal reads additionally pin constructor spellings,
tags, privacy, record-construction flags and payload types. Symbol/AST ordinals
remain absent from these keys. This strengthens both inferred and explicitly
annotated nominal receipts without adding fields to dense expression facts.

Each recipe and payload traversal shares the existing 4,096-node/128-depth proof
limit. Recursive constructor payloads, unavailable patterns, redacted spellings,
unknown effects, imported/namespaced annotation heads and unsupported forms
remain ordinary. Captures retain only owned digests and frozen semantic types;
borrowed pattern stores remain within the current preparation.

Focused evidence: 43 Safe/no-LLVM native tests (28 substantive plus 15 anchors),
eleven executed-Wasm laws, eight unchanged allocation budgets, and 348 analyzer
files with zero findings. Applied Box, shaped Pair and Array annotations
relocate through inserted AST/type nodes and first-use spellings under every
allocation failure. A constructor payload recipe edit revokes unchanged
consumers and preserves fresh bytes. The executed generic opaque law now
exercises those annotations for U32, F32 and owning numeric-array payloads,
including failure/recovery and repeated calls. No LLVM performance claim is made
for this isolated follow-up. General residual/projection/pattern/control forms
and producer ordinal relocation remain open; task 024 is active.

## Integrated followups at 2689 ad 5

The shared-principal, declared/portable qualification, seed-rebuild body offer
and applied-annotation/constructor recipe slices above are jointly qualified at
`2689ad5`. Full native suite, 925 guest/client laws, eight unchanged budgets and
349 analyzer files/zero pass. The exact LLVM/Fast release is `9ea894d4…8b21`;
public CPU is mixed (.9946–1.0501), peak deltas zero and teardown zero. Earlier
isolated costs are not substituted for merged costs. General scopes/cases,
producer-unit ordinal relocation and the under 100 ms total edit target remain
open. The current captured 93-unit corpus also has substantial backend work; its
changed input cannot establish a comparison to historical 400 ms. See
[the combined record](ROW_FUSION.md#integrated-qualification) and ignored
`build/bench/joint-024-035-040/qualification-pins.json`.

## Ordinary scopes and constructor patterns

Owned body facts now include ordinary blocks, lets, returns, scalar rebinding,
branch joins and case pattern rows. Local declarations, predecessors and join
edges use declaration-relative IDs. Case coverage still runs against the current
checker tables. Constructor reads pin the complete original nominal recipe and
selected tag; constructor and pattern catalog ordinals never survive a revision.
Record-pattern fields relocate by spelling against the restored record type.

This slice admits monomorphic and unqualified polymorphic local schemes.
Qualified local schemes, member projections, resolver blocks, providers and
loops keep ordinary checking. The syntax proof retains its existing depth/node
bounds and the 64-node capture floor. Source/compiled origin, privacy, effects
and current candidate reads retain the same conservative proof requirements.

Focused qualification: 45 native laws including allocation-failure sweeps, 13
executed-Wasm laws, all eight unchanged compile budgets, and 349 analyzer files
with zero findings. Laws cover new AST/type/spelling insertion, scalar mutation
and joins, constructor-tag changes, owning array payloads, failed edits and
recovery. The parent owns full integration qualification.

The current captured 93-unit project still elaborates all 80 bodies in its
edited module after this extension. No captured-project speedup is claimed;
richer scoped forms remain a concrete unfinished hill. The qualified incoming
LLVM diagnostic measured 940 ms child CPU / 1072 ms wall for steady revert, with
backend generation about 755 ms. Diagnostic noLLVM clocks are recorded
separately and never used as a release speed ratio; the under-100-ms goal
remains open. Private captured inputs remain read-only in ignored benchmark
storage.

Sparse unqualified local principals now retain their quantified type variables,
row variables and covariance certificates through the same projector and shared
graph owner as other checked facts. Replay preserves a row identity already
copied through a type when it restores that row's quantifier or certificate.
Local requirements still decline until their source/name/selection reads have a
complete relocation route. No new portable archive schema is introduced.

Focused qualification extends to 46 native/OOM laws and 14 executed-Wasm laws,
with the unchanged eight budgets and 349 analyzer files at zero findings. The
new local-scheme law instantiates U32/F32 and owning array values, preserves a
Foreign callback trace, relocates binders after earlier spelling insertion, and
checks rejected edits/recovery. This is semantic qualification of the admitted
slice, with no new LLVM or captured-project performance claim.

### Dotted-access safety boundary

The owned body cache declines any body with a nonempty checked access path.
Dotted references consume access types and projection metadata during lowering;
copying their result type and binding alone erases the field read. An unchanged
record getter previously returned 73763 after a sibling edit while fresh
execution returned 43. Until these side tables have owned relocation receipts,
ordinary checking and lowering remain authoritative for dotted accesses.

Native allocation-failure and executed-Wasm regressions compare fresh output
through sibling edits, earlier AST/type nodes and reversed field spellings,
failed edits and recovery. This correction adds no cache representation and
claims no admission or performance gain.

## Integrated guarded scopes at `850793f`

The independent guard and scope/local-principal slices are jointly qualified at
`850793f` with the full native suite, 936 guest/client tests, eight unchanged
budgets and 350 analyzer files/zero. The exact LLVM/Fast compiler is
`fa471c09…2387`; merged public CPU .9966–1.0173, peak deltas zero, requested
bytes−227,737..0 and teardown zero. The guard fixes the confirmed main wrong
result; scope admission preserves local predecessors, joins, constructor tags
and complete covariance rows. Complete records never omit dotted-access side
tables: those bodies decline.

The separately frozen explicit-field follow-up is not in this release. The
captured 93-unit project still elaborates 80 edited-module bodies; no total edit
gain is claimed. General requirements/access paths, producer ordinal relocation
and the under 100 ms target remain open. See [NUMERIC_SIMD](NUMERIC_SIMD.md) and
ignored `build/bench/joint-024-035-041/qualification-pins.json` for merged pins;
isolated safety/scopes/local pins remain under
`build/bench/frontend-body-reuse/`.

## Integrated explicit fields at `4013b10`

The frozen `concrete-fields-followup.patch` (`4ed0c57f…f5d8`) is now qualified
with the full native suite, 961 guest/client tests, eight unchanged budgets and
351 analyzer files/zero. Explicit field nodes own their spelling/tag and nominal
receipts, remapping current slots and constructor variants. This does not admit
dotted access paths; their complete side tables are still required.

The sparse field header grows 32 bytes; the 128-sibling owned payload is 119190
versus 114998 bytes. The isolated 48 native/OOM and 16+8 executed controls stay
separate from the merged gate. Joint public CPU ratios are 0.9945–1.0234, peak
deltas zero, and synthetic fresh/retained/restart output remains exact. No LLVM
field-specific speedup or overall retained-edit gain is claimed. General
requirements/access paths, relocation and the under 100 ms target remain open.
Merged pins are in `build/bench/joint-024-035-045-046/qualification-pins.json`.

## Compact concrete dotted paths (isolated checkpoint, 13 October 2026)

Concrete dotted record/nominal references now own one sparse access array. Each
step retains the declaration-relative source position, complete receiver type,
owned field spelling, original nominal recipe and all variant tags. The final
result comes from the expression fact. Intermediate roots share the frozen graph
and field-name owner; replay reconstructs current physical slots and the
complete access-type/path side tables. The same slot planner serves explicit
fields. Qualified root references instantiate against the root receiver type. No
solver, AST, field-symbol or projection-catalog ordinal crosses the owned
boundary.

The body header grows 16 bytes; each step is 32 bytes plus its variant tags and
shared graph/name storage. Paths exceeding 128 steps, more than 4,096 total
steps or variant tags, unsupported types, methods without concrete field
variants and access-node forms decline. Local requirements and
imported/namespaced annotation heads keep their existing ordinary checks.
Imported nominal tests use a local transparent alias and preserve
source/compiled origin, privacy and recipe reads.

Focused qualification passes 50 native laws (35 body laws plus 15 suite
anchors), including retained allocation failures; a separate fresh/retained path
allocation sweep passes 16 tests. Seventeen executed-Wasm laws, eight unchanged
allocation budgets and 371 analyzer files/zero findings pass. The path laws
cover chained structural and two-variant nominal fields, owning Array results,
earlier AST/type nodes and reversed field spelling order, executable producer
edits, revoked missing-field interfaces, fresh-identical diagnostics, rejected
revisions and recovery. Every successful retained output equals fresh Wasm
bytes.

Exact basis tree `344769cece12fdeb4484b63187cfab123a3abe85` and immutable
Safe/noLLVM binaries are recorded in ignored `build/bench/task024-dotted/` in
`/tmp/blot2-task024-completion`. Five alternating pairs on CPU 5, with two
warmups and 20 edited/reverted preparations per sample, measure dotted128/512
edit child CPU 123.5→90 /477.5→350.5 ms (paired median ratios .7317/.7267), body
elaborations 130.5/514.5→2.5 and exact Wasm hashes. Dotted population CPU rises
about 9–12%; 512 steady RSS rises about 2 MiB. Plain controls measure 79→77.5
/294→293 ms and unchanged 2.5 elaborations. Process clocks use Linux 100 Hz
ticks; these development costs are not LLVM/Fast release acceptance or a
captured-project speedup.

Task 024 remains active. General requirements, dotted methods/selector forms,
producer-unit ordinal relocation, richer scoped/control forms and the total
under 100 ms edit target remain open. Root owns the combined full gate and
release qualification; no milestone commit, overall completion or task 053
qualification is claimed by this isolated checkpoint.

## Inferred local requirements (isolated checkpoint, 13 October 2026)

Sparse local principals now own flat inferred associated and result-selection
requirements. Their argument/result/signature roots share the existing frozen
graph; names and source sites belong to the body. Principal obligation spans
refer to the owned predicate array and are restored into the current checker
before qualified local references instantiate. Principal entries do not become
duplicate body obligations. The marker uses existing predicate padding; body and
local-scheme headers stay unchanged. Complete positive/negative member catalogs
remain reads, including requirements on otherwise unreferenced local bindings.

Local requirement traversal shares a 4,096-node proof budget, with at most 4,096
owned predicates across the body. Unsupported or exhausted proofs retain
ordinary checking. Written local qualification origins, shared local callee
edges, field/receiver/update/effect requirements and other residual forms remain
ordinary. No portable artifact schema changes.

The preceding implementation passes 53 focused native laws. Final bounded code
passes 18 owned-body/principal/OOM controls and 16 large-receipt fallback
controls; 21 executed-Wasm laws plus eight unchanged budgets and 371 analyzer
files/zero pass. Source/compiled imports revoke local reuse on selected Foreign
interfaces with fresh-identical diagnostics, then recover. Laws cover
result-directed selection, negative candidate insertion, new AST/type/spelling
positions, scalar U32/F32 and owning Array results, fresh/replayed allocation
failures and positive Foreign callback traces. Every successful retained output
equals fresh bytes.

Against the exact dotted checkpoint `dca23f405a42c208d0cbcccf66656f7a69a09739`,
three alternating CPU 5 pairs with two warmups and 16 edits/reverts per sample
measure Safe/noLLVM local64/128 CPU 98.125→79.375 /188.125→152.5 ms; paired
median ratios .8141/.8040, elaborations 69.5/133.5→5.5. Plain controls are near
parity. Local population CPU rises 22–25%; 128 steady RSS rises 372 KiB. Root's
full gate was running during these development measurements. Immutable binaries,
prior unbounded prototype, samples, exact pins and logs remain in ignored
`build/bench/task024-local-requirements/` in `/tmp/blot2-task024-completion`.

Task 024 and dependent 053 remain open. Root owns combined full-gate and
LLVM/Fast acceptance. This does not complete general local requirements,
producer-unit ordinal relocation, richer scoped/control forms or the total edit
target.

## Merged checkpoint, 13 October 2026

Local `10fab46` qualifies this admitted slice with 1,624 native laws, 1,030
executed guests, 977 exhaustive failure sweeps and zero analyzer findings across
373 files. [Merged qualification](CONTINUATION_QUALIFICATION.md) records the
exact source/binary pins, measured costs and still-open scope. Isolated clocks
above remain separate from the final combined release measurements.

### Isolated declared local qualifications — 13 October 2026

Written associated/result-selection and `type_rep` local principals now keep
exact clause authority through replay. Owned predicate origins store spans
relative to the enclosing declaration; replay restores the current unit and
source span before instantiation. Empty representation names remain zero. The
origin digest names the original enclosing global, its privacy/runtime flags and
the exact local where position, with a distinct local-clause tag. It contains no
local spelling, solver ID or module-global node ID.

A bounded source walker validates the exact where node. Compiled producer lookup
finds the declared local Core principal and its unique enclosing global; public
snapshots can keep redacting private local names/schemes. Missing, ambiguous,
unsupported or exhausted routes decline reuse. The source and compiled routes
share the same digest without changing any artifact schema or body/receipt
header. The public-interface check still validates each predicate's kind, four
type roots and member name, and complete candidate reads precede selection.
Producer binding/unit ordinal changes still force ordinary checking.

Focused Safe/noLLVM validation passes 54 existing body-cache laws, including
fresh/population and retained allocation-failure sweeps, followed by the added
exact-clause/budget law. All 23 body guest laws and eight unchanged budgets
pass; 371 Zig files have zero analyzer findings. U32/F32/owning Array native
controls, source and compiled exported local origins, earlier AST/type/spelling
edits, selected body edits, wrong clauses, missing references, Foreign rejection
and recovery retain fresh-identical bytes or diagnostics and executed results.

Against exact local-requirement checkpoint
`51a2f752db3ec27d98f45925c95fa155bd2b0d1e`, three alternating CPU 5 pairs with
two warmups and 16 hot edits/reverts measure declared64/128 CPU 94.375→81.875 /
183.75→158.125 ms; paired median ratios .8733/.8557. Elaborations
69.5/133.5→5.5. Plain controls remain near parity. Declared population CPU rises
37–44%; steady RSS rises roughly 1.1/1.7 MiB. Root's combined gate ran
concurrently, so these Safe/noLLVM numbers are development measurements.
Immutable binaries, 48 samples, exact pins and logs live in ignored
`build/bench/task024-declared-local/` in `/tmp/blot2-task024-completion`.

Task 024 and 053 remain open for shared local callee edges,
field/receiver/update/ effect residuals, imported annotation heads, producer
ordinal relocation, general scoped/control forms and the total edit target.
Parent integration owns full-gate and LLVM/Fast acceptance; this checkpoint is
reviewable, not an accepted overall milestone.

### Isolated producer ordinal relocation — 13 October 2026

Body offers now resolve the accepted revision's borrowed cache by canonical
producer filename, independently of current loader order. A request-local map
owns only its directory; prior body leases stay with the accepted revision.
Missing or ambiguous old filenames offer nothing. Current checking still
precedes every replay and executable lowering/relinking remains fresh.

Project checking supplies a 32-byte digest of each original loaded module
filename. Nominal recipes, applied annotation reads, associated candidate
catalogs, imported principals and declared qualification authority bind that
origin. Imported values also bind their original declaration name. Numerical
unit/binding targets are current execution data: replay resolves current
nominals by exact origin/name and current value bindings by the unchanged body
spelling, then validates the complete interface and candidate reads. A different
producer with an equal interface revokes reuse. Standalone callers without a
project dictionary retain their exact ordinal authority. No artifact schema or
dense body-fact header changes; each distinct owned nominal read grows 32 bytes.

All 57 focused native body-cache laws pass. Native imported-target
relocation/OOM controls verify rebuilt unit/binding references and
original-module/name revocation. A real retained revision sweep adds a module
and earlier producer declarations, compares fresh bytes, discards every
failed/complete candidate, preserves the successful publication and
retries/commits. All 24 body guest laws plus eight unchanged budgets pass, with
source and compiled module insertion/deletion, declaration renumbering, scalar
aliases, explicit local origins, associated selection, dotted nominal payloads,
owning Array results, selected executable edits, equal-interface producer
retargets, failed edits and recovery. 371 Zig files remain at zero findings.

Against exact declared-local checkpoint
`ade73b43129ffe9822d3a11a0e814d3cd2406ad4`, three alternating CPU 5 Safe/noLLVM
pairs with two warmups and 16 hot edits/reverts measure producer64/128 CPU
172.5→156.875 /341.875→312.5 ms; paired median ratios .9161/.9139. Elaborations
66/130→2. Plain controls stay near parity. Producer population CPU rises 11%;
steady RSS falls roughly 1.0/1.4 MiB in these samples. 48 samples, immutable
binaries, exact source/binary pins and logs remain in ignored
`build/bench/task024-ordinals/` in `/tmp/blot2-task024-completion`. These are
development measurements with other qualification work concurrent, not
captured-project or release acceptance.

Producer ordinal relocation is implemented for admitted receipts. Shared local
callee edges, other residual predicates, imported annotation heads, broader
scoped/control forms, full-gate/LLVM qualification and the total under 100 ms
edit target keep 024 and 053 open. Canonical filenames identify the current
retained project; these receipts do not provide cross-checkout identity.

### Isolated imported annotation heads and bounded recipe proofs — 13 October 2026

Body capture now finishes inside the checker, while its exact nominal-name
lookup still exists. Capture and replay resolve direct imports, imported aliases
and namespace heads through that same lookup. The existing sparse type read owns
the original declaration/recipe digest; an imported alias binds its original
name and module origin even when its instantiated result matches another alias.
No annotation-name table, Checked/Body/Fact header or artifact schema is added.
The redundant project-level capture is removed. Legacy explicit capture remains
conservative without a resolver. Unsupported lookup or recipe proofs decline.

Initial admission reduced elaborations but doubled retained CPU: complete
generic nominal recipes were proved repeatedly. A fixed 64-entry body-local memo
now reuses only complete recipe digests at the exact recursion depth, retaining
the full original proof debit. Exhausted depth/budget declines; a full memo
computes uncached. The memo allocates nothing, owns no solver values and never
persists in a receipt. Replay resets it and refreshes its catalog after checker
mutations while resolving referenced globals. Capture uses completed immutable
facts. The original regression, quick repair comparison and final samples are
preserved separately.

Focused validation covers 59 native body-cache laws, including fresh/population
and retained allocation failures, exact imported alias-name/recipe revocation,
memo depth/budget/capacity controls and successful-publication retry. All 25
body guest laws plus eight unchanged budgets pass; 371 Zig files have zero
analyzer findings. Source and compiled direct/alias/namespace heads retain
fresh-identical bytes, owning Array results, missing-head diagnostics and
recovery through module/producer renumbering. Native controls reject
`Alias a = Wrapper U32` after `Alias a = Wrapper a` even when this use remains
`Wrapper U32`; the broader module cutoff can separately avoid body work for that
equal current result.

Against exact ordinal checkpoint `8879a15b28ad6414b755f9b6bdea968025503fb8`,
three alternating CPU 5 Safe/noLLVM pairs with two warmups and 16 hot
edits/reverts measure imported-head64/128 CPU 115.625→108.125 /223.75→208.125
ms; paired median ratios.9243/.9354. Elaborations 66/130→2. Plain controls stay
near parity. Head population CPU rises 15–17%; steady RSS rises 540/1,748 KiB.
Immutable binaries, the un-memoized regression, quick comparison, final 48
samples, exact pins and logs remain in ignored
`build/bench/task024-imported-heads/` in `/tmp/blot2-task024-completion`. These
concurrent Safe/noLLVM measurements diagnose development costs; release,
captured-project and combined full-gate acceptance belong to the parent.

Imported annotation heads are covered for admitted recipes. Shared local callee
requirements, other residual predicates, broader scoped/control forms and the
total under 100 ms edit target keep 024 and 053 open.

### Isolated shared requirements in local principals — 13 October 2026

Local principals now own shared `callee_use` edges through the existing binding
receipt. Capture replaces the source binding/unit with an owned binding slot;
replay restores the current checked binding/unit before instantiation. Only
completed global/imported targets with complete principal, summary and
transitive candidate reads qualify. Local generalization already moved a
reference's requirements into its local principal; replay preserves that
boundary instead of adding them again to the enclosing pending graph. Ordinary
locals keep their ordinary empty summary. No header or artifact schema grows.

60 focused native body-cache laws, 26 body guests, eight unchanged budgets and
371-file zero analyzer pass. Fresh/population and retained OOM, U32/F32/owning
Array relays, negative candidate insertion and requirement removal, source and
compiled helper body/signature/Foreign changes, producer renumbering, failed
edits and recovery preserve fresh bytes, diagnostics and executed values.

Against `cc6e5e4e25c7be1114e9c6547cd40804f7bb33c5`, three alternating CPU 5
Safe/noLLVM pairs with two warmups and 16 edits/reverts measure local64/128 CPU
120→89.375 /231.875→172.5 ms; paired ratios .7448/.7439 and elaborations
70.5/134.5→6.5. Population rises 9–10%; steady RSS rises 944/720 KiB. An initial
plain64+7% paired result does not repeat in five further plain pairs: 64/128 CPU
70.625/133.75 ms is identical across variants. Both distributions remain in
ignored `build/bench/task024-shared-locals/`, alongside immutable binaries,
exact pins, 88 samples and logs in `/tmp/blot2-task024-completion`.

This covers local requirements forwarded through completed shared summaries.
Other residual predicates, explicit effect/control syntax, broader forms and the
total under 100 ms target keep 024/053 open. Root owns combined release and
captured-project acceptance; these are concurrent development measurements.

### Isolated written Foreign arrows — 13 October 2026

The owned syntax walker now admits function-arrow effect rows whose labels are
exactly the sealed built-in `Foreign`, including empty closed rows and written
variable tails. It hashes each label's spelling/tag/relative span and charges
the existing depth/node bound, without treating the label as a nominal read.
Existing complete type/interface proofs retain the row labels, tails and
quantified variables. This adds no header, graph or solver schema. User-defined
operation/family labels still decline because they need current identity reads;
non-arrow effect annotations remain invalid language syntax.

Native laws cover written and symbolic arrows, exact interface changes, deep
relocation, fresh/retained byte equality and every capture/replay allocation
failure. Executed source and compiled-import laws check callback traces after
producer value edits, pure/Foreign transitions, a rejected closed-row
annotation, a missing reference, recovery and revert. The body-only native
family passes 62 laws; 27 body guests plus 8 unchanged budgets pass; 371
analyzed files have zero findings. Root owns the combined release gate; no
duplicate full gate was run.

CPU 5 Safe/noLLVM development comparisons use three alternating pairs at 64/128,
two warmups and 16 retained edits/reverts, with exact Wasm hashes and executed
callbacks. Final retained CPU 70→63.125 /136.875→120 ms (paired 0.902/0.881),
while elaborations 66.5/130.5→2.5. Population CPU 60→80 /120→150 ms (paired
1.333/1.25); retained RSS rises 604/1792 KiB. Plain retained controls
61.875→61.875 / 119.375→118.75 ms have paired medians 1.0. Two 48-sample
distributions, immutable binaries, logs and exact pins remain
under`build/bench/task024-foreign-arrows/`. The final rebuild followed an intact
mutable-cache relocation from full `/tmp` to `/var/tmp`; the interrupted build
and unlogged native run are not counted.

Field/receiver/update and user-operation residuals, remaining control forms,
LLVM/captured-project acceptance and the under 100 ms total target keep 024 and
its dependent 053 open. Written Foreign rows close one exact exclusion.

### Isolated ordinary array selectors — 13 October 2026

Array index expressions now use the existing two-child syntax receipt. The
checker constrains an array owner and a U32 selector, and lowering reads only
those expression types and children; no new metadata, schema or replay branch is
needed. Field and index mutation paths remain declined because their update
plans have different ownership requirements.

The focused generic-selector law covers scalar, F32 and owning nested arrays,
changed selector values, spelling/type relocation, fresh/retained bytes and all
capture/replay allocation failures. Source and compiled-import executions cover
selector and producer body edits, floating-selector rejection, recovery and
revert. 63 body native laws, 28 body guests plus 8 unchanged budgets and
371-file zero analyzer pass in isolation. Root owns combined release acceptance.

CPU 5 Safe/noLLVM comparisons retain three alternating pairs for plain/indexed
forms at 64/128, two warmups and 16 edits/reverts, exact Wasm hashes and
executed results. Indexed retained CPU 64.375→56.25 /122.5→106.875 ms (paired
0.874/0.868); elaborations 66.5/130.5→2.5. Population 60→70 /100→130 ms (paired
1.167/1.3); retained RSS+96/+1224 KiB. Initial plain128 CPU 101.875→109.375 ms
(paired 1.074) did not repeat in five further pairs: 101.25→101.25 ms (paired
1.0); plain64 repeat 51.875→52.5 ms (paired 1.012). Both distributions remain;
88 samples, immutable binaries and pins live under
`build/bench/task024-array-index/`.

General residual projection/receiver/update/effect ownership, other control
forms, LLVM/captured-project acceptance and the under 100 ms total target remain
open for 024/053. Generic field templates still need exact current plans before
admission; an empty physical variant list cannot be treated as a concrete path.

### Isolated generic explicit fields — 13 October 2026

Implicit field predicates with no secondary operand now participate in complete
interface and member-catalog proofs. An explicit postfix field may own an empty
projection template only when its receiver remains a plain variable, its nominal
identity is zero and its spelling matches the source selector. Replay
reconstructs that same generic template; concrete projections still require
their complete variant tags and current physical slots. Global and local
principals retain the field roots, signatures, spelling and current selection
reads through existing owners. No receipt header or graph schema grows.

Two new native laws exercise global and local requirements through every
fresh/retained capture/replay allocation failure, exact byte equality and
unselected candidate insertion. Executed source/compiled laws preserve current
record and nominal slots, scalar/owning payload changes and local field scopes.
Selected method body edits change results; a selected Foreign interface fails a
pure consumer, and missing fields/rejected edits recover and revert. The full
body-only native family passes 65 laws; 29 body guests plus 8 unchanged budgets
and 371-file zero analyzer pass. Root owns combined release qualification.

CPU 5 Safe/noLLVM 64/128 field retained CPU 79.375→63.125 /151.875→119.375 ms
(paired 0.795/0.783), elaborations 66.5/130.5→2.5. Population 70→80 /130→150 ms
(paired 1.143/1.154), retained RSS+1096/+644 KiB. Plain retained controls
53.75→53.75 /103.75→103.75 ms have paired 1.0/1.006. Three alternating pairs,
two warmups and 16 edits/reverts per workload verify exact hashes and executed
results. Initial and final 48-sample distributions, immutable binaries and pins
remain under `build/bench/task024-generic-fields/`.

Generic dotted templates, projected receivers, declared field requirements,
receiver/update/user-operation residuals and other control forms remain
conservative exclusions. LLVM/captured-project acceptance and the under 100 ms
total target keep 024/053 open. Empty templates are admitted as generic
evidence, never as concrete physical paths.

### Isolated generic dotted templates — 13 October 2026

Generic dotted paths now own their direct field predicates and zero-tag steps
through the existing sparse path receipt. Every empty step requires a plain
variable receiver, zero nominal identity and an unqualified parameter/local
root. Qualified principals remain declined for generic paths so their forwarded
requirements cannot be mistaken for direct projection requirements. Concrete
steps retain their existing tag, nominal and physical-slot guards. The complete
member catalog covers every generic step. No header/schema grows.

Nineteen focused dotted laws include the prior concrete owning paths and method
exclusion, plus global/local two-step generic paths through every fresh/retained
capture/replay allocation failure and unselected candidate insertion. The
source/compiled field law now executes both postfix and dotted forms, including
local principals, current slots, owning payloads, method body/effect changes,
rejected fields, recovery and revert. 29 body guests plus 8 unchanged budgets
and 371-file zero analyzer pass. The inherited 65-law family qualified the
explicit field basis; this delta ran targeted dotted controls. Root owns the
next combined full compiler gate.

CPU 5 Safe/noLLVM 64/128 dotted retained CPU 79.375→62.5 /153.75→120 ms (paired
0.781/0.780), elaborations 66.5/130.5→2.5. Population 70→80 /140→150 ms (paired
1.143/1.071), retained RSS+252/+88 KiB. Plain retained 50.625→50.625 /
98.75→98.75 ms has paired 1.0. Three alternating pairs, two warmups and 16
edits/ reverts produce 48 samples with exact hashes and executed results.
Immutable binaries and pins remain under `build/bench/task024-generic-paths/`.

Qualified generic roots, projected/declared fields, receiver/update/user-effect
residuals, remaining control forms and LLVM/captured-project/total-edit
acceptance keep 024/053 open. This closes ordinary variable-root dotted fields.

### Isolated compatible pure forms — 13 October 2026

One syntax bundle admits ordinary if-let scopes/joins, scalar negation, value
patterns, product projection and the shared pure Array/List operation class. The
collection registry supplies operation names/arity; cursor operations remain
ordinary. Existing expression types, references, projections, closures and
merges already own the required lowering facts. No header/schema or persistent
solver state is added. This is the last small compatible syntax bundle before
evaluating one bounded source-Core recipe for broader forms.

Native if-let and collection/value-pattern laws cover scalar/owning joins,
fallthrough, captures, changed value patterns and every fresh/retained capture/
replay allocation failure. Source/compiled executions cover active/fallback
callback traces, variant-tag insertion, owning results, negation, collection
operations, product/value patterns, rejected edits, correction and revert. The
68-law body family passed 65 laws initially; the three failures expected an
Array.concat body to remain ordinary. Updating those work counters for the new
admission and rerunning all three laws (including their OOM and negative reads)
passes. No semantic mismatch occurred. 30 body guests plus 8 unchanged budgets
and 371-file zero analyzer pass. Root owns the combined full compiler gate.

CPU 5 Safe/noLLVM 64/128 if-let retained 70.625→63.75 /135→120 ms (paired
0.903/0.889), elaborations 66.5/130.5→2.5. Population 60→80 /110→150 ms (paired
1.333/1.364), retained RSS−52/+1100 KiB. Collection retained 67.5→59.375
/131.25→114.375 ms (paired 0.872/0.871), the same elaboration reduction;
population 60→70 /110→140 ms (paired 1.167/1.364), retained RSS+644/+1088 KiB.
Plain controls are near parity. Initial if-let and two final 48-sample
distributions remain under `build/bench/task024-if-let/`, with immutable
binaries/logs/pins.

The remaining eligibility/acceptance inventory and architectural comparison are
in `build/bench/task024-architecture/REMAINING.md`. Whole Checked/module copying
is rejected. Qualified/projected/declared fields, receiver/update/demand/loop/
user-effect/implementation proof owners and total edit acceptance keep 024/053
open; the proposed broader source-Core path remains a prototype.

### Combined replay qualification, 13 October 2026

`ae001bb` includes these field and pure-form recipes. Replay preserves the
validated current catalog's monomorphic constructor-pattern payload roots,
including ordinary transparent-record canonicalization. Annotation roots stay
independent. This prevents four copied nominal roots from invalidating the next
captured revision's strict type-catalog gate. Third-revision full Core
type-table parity, Wasm parity, nominal-recipe invalidation and complete replay
OOM pass.

The combined gate and release measurements are in
[merged qualification](CONTINUATION_QUALIFICATION.md). Retained synthetic CPU
falls about 22–29%; population costs about 15–39% more. General owned
source-Core replay remains isolated and unqualified; this checkpoint does not
close task 024.

## Mixed implementation modules, 14 October 2026

Ordinary declaration receipts can now survive an implementation in the same
module. Selected members and implementation prerequisites remain fresh until a
complete owned proof receipt exists. Four focused native laws and fourteen
source/compiled/restart revisions preserve fresh bytes and diagnostics,
including wrong or missing heads, changed associated types, overlap and removed
prerequisites. General implementation cutoff remains open.

A bounded development screen uses 48 independent bodies of 32 primitive steps
and four alternating pairs. Median CPU is 135→155 ms on population, 145→90 ms on
independent edit/revert, and 145→85 ms on a selected method edit (10 ms clock
resolution). Two allocator pairs reduce edited allocations from about 31,000 to
6,400–7,100; population adds about 1.47 MB cumulative allocation and retained
metadata adds 0.36–0.38 MiB. All 60 samples preserve bytes, execution and source
fuel. These are isolated Safe/noLLVM results, not general or release targets.
Exact patch, measurements and limits are retained under
`build/bench/continuation-20261014/mixed-implementation-cache/`.

The next subtraction admits nominal/alias annotations through their existing
owned recipe reads. It removes the blanket annotation decline; explicit selected
uses, member templates, selection digests and predicates retain their guards.
Same-layout nominal retargets and privacy changes revoke the recipe. An alias
hiding an associated projection remains uncaptured. No proof graph or cache
schema was added.

Five native laws pass, including 1,054-position annotation replay OOM and the
existing 758-position mixed-module sweep. Four guest groups exercise ordinary
14-revision and annotated 23-revision sequences in both tiers, preserving fresh
bytes, execution, diagnostics and source fuel. The annotated method edit checks
two bodies instead of three; genuine selected-call receipts and broad cutoff
remain open. These are focused checks awaiting root's combined gate. Evidence:
`build/bench/continuation-20261014/annotation-recipes/`.

### Current selected-name callers, 14 October 2026

The next uncommitted slice admits selected-name calls by reading the complete
bounded semantic implementation catalog. The digest includes losing heads,
contract/member signatures, prerequisites, privacy, original declaration owners
and capability relationships. Method bodies stay executable dependencies. Replay
reinstantiates current references and reconstructs selected proofs; it never
imports an old proof or method target. Catalogs above 64
contracts/implementations or the 4,096-step proof budget decline to ordinary
checking.

Existing owned type graphs now relocate contract identities and associated
member spellings alongside nominal identities. This covers generic global and
local requirements, projection annotations and import ordinal changes. Unused
global binding types no longer add redundant graph roots. Unsupported selection
forms, row-parameter catalogs and authority-bearing schemes remain ordinary;
broader cutoff and task 053 qualification are still open.

A separate baseline backend defect surfaced during these checks: lexical sharing
treated an associated projection's physical-result entry as a free type
variable, even when its argument was quantified. Argument variables now own
lexical sharing. Uninstantiated projection results publish no physical hint;
concrete uses still resolve through ordinary implementation selection. Executed
U32/F32 uses and captures remain independent.

Ten focused body laws, including allocation-failure sweeps and storage growth,
and twelve guest groups pass. Guest revisions cover changed methods, heads,
associated types, overlap, prerequisites, privacy, missing members, failures and
recovery in both code-generation tiers. Source and compiled dependencies retain
fresh-identical Wasm and fuel through relocation; source producer-body edits
also update execution. The pinned analyzer reports zero findings in the selected
322-file dependency closure. The final full gate remains pending.

Two three-pair development screens use 32 selected callers and precise child CPU
clocks. Method/revert CPU is about 72→56–57 ms; literal edits are 63→47 ms
(paired ratios 0.74–0.78). Edited body elaborations fall from 34 to 2. Initial
population costs roughly 70→78–80 ms; ordinary retained edits stay near parity,
while fresh samples vary. These are Safe/noLLVM screens, not release or captured
project targets. The ordinary 64/128/256-body storage probe retains the same
allocation counts and removes one 36-byte graph node.

Exact source delta, binary pins, samples and logs are under
`build/bench/finish-program-20261014/`. The source patch is
`selected-body-source/source.patch`, SHA-256
`18f59e84416cd42c8ab9f5df136b05ec5839159e6e2767772fe19dbeb74273c3`;
`selected-body-pairs-first.json` and `selected-body-pairs.json` retain both
screens. The qualified release executable is unchanged.

## Ordinary loop and use receipts, 15 October 2026

The immutable body cache owns carried predecessor bindings and lexical break
snapshots by declaration-relative source positions. Replay reconstructs current
loop metadata before ordinary Core lowering. Existing expression facts own
ordinary `use` names, annotations and monomorphic bindings. Generated iterator
bodies, Request loops and resolver blocks retain ordinary checking.

Two complete capture/replay OOM laws, six loop/owner guest groups and 384-file
zero lint pass for loops. The use extension adds one capture/replay OOM law and
both executed tiers; the combined row/use union passes 388-file zero lint. Exact
source and qualification are in
`build/bench/complete-program-20261015/body-loop-receipts/` and
`body-use-values/`.

Five alternating CPU 7 development pairs over 128 loop declarations preserve
cross-compiler and fresh/replayed Wasm. Edit/revert CPU falls from 150/160 to
120 ms, with elaborations 130 to 2. Population rises from 110 to 160 ms. Plain
128 controls stay at 130 ms population, 90 ms edit and 100 ms revert. Linux CPU
tick granularity is 10 ms. These costs do not complete the general body
interface or total edit targets; tasks 024/053 and release qualification remain
open.

## Field and indexed update receipts, 15 October 2026

One sparse update record retains root and old-leaf `self` bindings. Replay
reconstructs selector paths and type endpoints from existing expression facts
and physical projection proofs. Exact same-owner comparison admits separately
allocated generic Array roots while preserving binder identity. Complete
capture/ replay OOM and fresh/replayed Wasm pass for mixed nominal/Array updates
and inferred generic replacement. Five root guest groups and 384-file zero lint
pass; source and costs are pinned in
`build/bench/complete-program-20261015/body-path-updates/`.

Five alternating CPU 7 development pairs over 128 update declarations reduce
edit/revert CPU from 190/190 to 130/140 ms and elaborations from 130 to 2.
Population rises from 130 to 180 ms. Plain wall controls stay within 0.3%; CPU
sampling has 10 ms granularity. Broader residual/effect/control receipts,
release qualification and tasks 024/053 remain open.

## Ordinary demanded-body receipts, 15 October 2026

Demanded parameters and supported Demand types now retain exact suspended-call
signatures in the existing sparse signature list. Replay restores the original
lazy classification and type. Later inference does not recreate that decision.
Binary demand rewrites and unsupported operation/scoped/resource recipes remain
ordinary; existing interface, identity and capture proofs are unchanged.

Two native laws, two neighbors and complete allocation failures pass. Both new
guest tiers preserve once-only/ignored Foreign effects, demanded owning arrays,
lazy-to-eager signature changes, source/archive/checkpoint, failed revisions,
recovery and sync/JSPI. Four loop/path neighbors and 400 affected zero-finding
analyzer files pass. Five balanced development pairs reduce 128 demanded-body
retained edit/revert 160/150→120/120 ms and elaborations 130→2; population rises
120→160 ms. Plain retained controls stay 100 ms. All 60 phases preserve
cross-binary bytes and executed values; process CPU has 10 ms resolution. This
does not close the release/general under 100 ms gate. Source/binary pins, raw
phases and failed controls are in
`build/bench/complete-program-20261015/body-demand-receipts/`.

## Nested callable fragment owners, 15 October 2026

Callable-layout records inside a retained caller's range belong to their own
checked jobs. Admission now validates the record's exact owner, function and
declared layout before the existing callable-layout import. It previously used
the outer caller's job and declined valid nested fragments. Missing/out-of-range
owners and changed layouts still decline; no interface or import guard is
relaxed.

One native law with complete allocation failures, 26 executed groups and 112
affected zero-finding analyzer files pass. The unchanged captured project
recovers 489 fragments, retaining 1152 named+369 closures with 240 declines;
every phase keeps its prior Wasm hash and 70,330 source steps. A single
development wall screen changes edit/revert 14.032/13.466→11.782/11.287s; fresh
remains 25.0s. This is compatibility and attribution evidence, not the
release/CPU target. Exact sources, failed-before control and pins are in
`build/bench/complete-program-20261015/nested-callable-reuse/`.

## Chains with no clean dependency, 15 October 2026

A private leaf edit can dirty every transitive dependency while leaving public
interfaces unchanged. The retained loader now offers that complete dirty set to
the existing mixed checker. Previously it required at least one clean dependency
and rebuilt every semantic caller. Each cutoff still compares the current
checked interface and namespace; executable lowering reads the current producer.

An opaque 3-module law now reuses the intermediate and entry callers, with
fallback elaborations 5→3. One native law with complete candidate allocation
failures, 10 executed groups, TypeScript and 19 affected zero-finding analyzer
files pass. Source/archive/checkpoint, invalid-signature rollback, recovery and
both codegen tiers/sync/JSPI preserve fresh bytes and values. Scalar wrappers
still export no guest memory. No CPU target or general module-abstraction
completion is claimed. Exact source/compiler pins and before/after counters:
`build/bench/complete-program-20261015/all-dirty-module-cutoff/`.

## User-effect callback rows, 15 October 2026

Nongenerative declaration rows now retain the original producer, family/member
names and complete bounded family/signature recipe, including privacy, callable
form, parameters and patterns. Annotation lookup follows the actual checker
catalog and import aliases. Frozen operation identities relocate through a
separate current validated map; function and Demand traversals retain operation
arguments. No spelling, physical layout or raw ordinal supplies authority.
Invocation, scoped/generative and incomplete recipes remain ordinary.

Root 8 native laws, 4 complete allocation sweeps, 6 executed groups, TypeScript
and 400 affected zero-finding analyzer files pass. Controls cover changed
declarations, wrong origins/aliases, ordinal relocation, malformed/ambiguous
catalogs, open rows, Foreign compatibility and Demand boundaries. Both
tiers/sync/JSPI preserve source/archive/checkpoint bytes, effects, host failure
and recovery. One source dependency edit uses 4 retained versus 5 fresh
elaborations. Archive parity is qualified; archive work reduction is not. Exact
source/binary pins and logs:
`build/bench/complete-program-20261015/body-user-effect-rows/`.

## Inert principal suffixes, 15 October 2026

Retained names may form an exact prefix of the current namespace. Every old
symbol spelling and producer still matches. A checked interface can add/remove
only a suffix of canonical empty local/parameter binding slots, with every
shared slot, graph, catalog and recipe unchanged. Validating the shorter view
proves no principal reference reaches an omitted slot. Export targets remain
exact. This comparison neither changes the stored format nor relocates bindings.
Edits that shift shared slots retain ordinary checking.

An opaque dependency's last function can now add/remove a private local while
its intermediate and entry callers retain semantic reuse. Root 3 native laws,
complete candidate allocation failures, 10 executed groups, TypeScript and 56
affected zero-finding analyzer files pass. Changed spellings/producers,
malformed views, suffix payloads, changed prefixes and references into omitted
slots reject. Source/archive/checkpoint, invalid signatures/recovery and both
tiers/sync/JSPI preserve fresh bytes/results. Ordinary Cost stays exact 11958B.
No general edit CPU or final qualification is claimed. Source/compiler pins and
logs: `build/bench/complete-program-20261015/inert-principal-slot-cutoff/`.

The lightweight principal validator also checks proof-header binding bounds and
self-unit external/implementation/selected-member/predicate targets before slots
are omitted. A new forged-header control fails before this guard and rejects
after it. Eight focused native laws, 22 executed groups and 60 affected
zero-finding analyzer files pass; cache-disabled ordinary Cost is unchanged.
Exact delta, Debug counterexample and pins:
`build/bench/complete-program-20261015/principal-local-target-bounds/`.

The comparison now omits each interface's maximal canonical inert local suffix,
then compares every remaining principal field exactly. This also handles earlier
function edits that shift only erased local/parameter markers. Validation bounds
all local shared-callee and self/unit0 target references; foreign predicates
must resolve to an exact retained external alias. An ordinary scheme's
shared-callee slot remains owner-local. No graph, export target or stored
binding is remapped. Root 8 native laws/3complete allocation sweeps, 25 executed
groups and 266 affected zero-finding analyzer files pass; general CPU
qualification remains open. Exact counterexamples, source/binary pins and logs:
`build/bench/complete-program-20261015/principal-local-suffix-normalization/`.

## Static operation calls, 15 October 2026

Receipts now retain static calls to unparameterized effect families through the
existing sparse signature graph. Replay resolves the current Source name and
requires the exact owned operation identity, complete family recipe and origin.
It reconstructs operation-use metadata for fresh Core lowering. Scoped/State
calls, parameterized families and invocation owners still use ordinary checking.
The body/signature headers and portable format do not grow.

Eight root native laws pass, including capture/replay allocation failures,
producer relocation and equal-signature imported alias retarget rejection. Six
selected guest groups cover source/archive dependencies, changed effects,
failure recovery, checkpoint restart and sync/JSPI in both tiers. Shared
affected analyzer coverage is 402/455 files with zero findings; TypeScript
checks pass. Ordinary Cost remains byte-exact 11958 bytes.

A five-pair combined development screen of 128 static-operation bodies reduces
retained edit/revert CPU 240/250 to 110/110 ms and elaborations 130 to 2. Fresh
population rises 220 to 240 ms; plain controls stay at 130/100/100 ms. Every
before/after output is byte-exact and executes. CPU uses whole-process 10 ms
ticks; this small screen includes the separate cursor proof and is neither an
isolated feature ratio nor release qualification. Exact source pins and raw
samples:
`build/bench/complete-program-20261015/static-operation-body-receipts/`.
