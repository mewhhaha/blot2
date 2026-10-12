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

[The refinement lookup](src/refinement_receipt.zig) now admits a root by its own
declaration instead of its whole module:

- a body root when its declaration's exact projection and identity are admitted
  (`admitsLocalSource`);
- a closure root when its unit is structural, or when the
  [gate](src/principal_reuse_gate.zig) recorded, during the exact projection of
  a declaration in an edited module, that this declaration reaches that closure
  catalog entry, and that declaration's source and identity are admitted
  (`admitsClosure`). The projection compares the closure entry at the same index
  in both modules, so the old root names the same lexical closure.

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

[The parser](src/parser.zig) numbers `$collection.N` names within each top-level
declaration. Names stay unique where they are visible, and an edit elsewhere no
longer renames them.

## Qualification on 11 October 2026

The baseline is the task-023 compiler sources (`fbe28c8`); the candidate is
pinned with its probe in [the pins](qualification/body-cutoff-pins.json).

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 632 guest/client tests; `deno task lint:zig` reports
  zero findings across 310 files.
- [Native laws](src/body_cutoff_tests.zig): a same-size body edit replays the
  three receipts rooted in unchanged declarations and their closures, with
  fresh-identical output under an allocation-failure sweep; a callee body edit
  with an unchanged interface keeps consumer receipts, declines the region that
  collected the callee's source, and regenerates its executable callers. A
  mutant with the old structural root rule replays none of them.
- [A gate law](src/principal_reuse_gate_tests.zig) checks closure roots in an
  edited module: an unrelated edit keeps both closures, a closure body edit
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
[body_check_cache.zig](src/body_check_cache.zig), beside `Prepared`. Immutable,
independently leased chunks share frozen type graphs from `dependency_snapshot`;
`SchemeCopier` reconstructs fresh live types and rows. Expression facts,
parameter bindings and anonymous closed-row certificates relocate by
declaration-relative syntax positions and binding spellings. No source tree,
solver ID, substitution history, scratch pointer or previous revision owner
escapes into a new preparation.

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

## Integrated followups at2689ad5

The shared-principal, declared/portable qualification, seed-rebuild body offer
and applied-annotation/constructor recipe slices above are jointly qualified
at`2689ad5`. Full native suite,925 guest/client laws, eight unchanged budgets
and349 analyzer files/zero pass. The exact LLVM/Fast release is`9ea894d4…8b21`;
public CPU is mixed (.9946–1.0501), peak deltas zero and teardown zero. Earlier
isolated costs are not substituted for merged costs. General scopes/cases,
producer-unit ordinal relocation and the under100ms total edit target remain
open. The current captured93-unit corpus also has substantial backend work; its
changed input cannot establish a comparison to historical400ms. See
[the combined record](ROW_FUSION.md#integrated-qualification) and ignored
`build/bench/joint-024-035-040/qualification-pins.json`.
