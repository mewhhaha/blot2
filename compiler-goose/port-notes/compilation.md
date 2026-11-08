# Compilation repair frontier

The user requested fixing and recompiling the Goose port. Verification is
active. There is no working whole Goose compiler executable yet: whole parsing
passes, but type/lifetime checking still stops before program C emission.
Keep `compiler/`, the default toolchain, the pinned Zig oracle and siblings
unchanged. Source checkpoints are unverified whole-compiler work.

The [scope checkpoint evidence](../../benchmarks/evidence/qualification/2026-11-07-goose-scope-checkpoint.json)
preserves individual component receipts and rejected checker trials. Each
receipt's reduced adapters and source identity limit its qualification.
The [accepted checker evidence](../../benchmarks/evidence/qualification/2026-11-07-goose-identity-checker.json)
pins the nominal-identity candidate and its paired prefix runs. The
[reachability checkpoint](../../benchmarks/evidence/qualification/2026-11-07-goose-reachability-checker.json)
preserves the selected checker, reproducible recipe, later source repair laws
and rejected root-enumeration experiment.

Main checkpoint `30f03db34c8fdd4eee94fe63d3c5caffe5eef6bd` preserves the scalar
cache indexes, snapshot leases and scoped proof repairs through frozen176.
Checkpoint `abe612009229c2a22bb2f12510731643cc0210d5` preserves the exact
frozen185 inputs and the first scoped-frame repair batch, still unverified.
Parser checkpoint `21df1327` qualifies the
isolated parser controls below. Superseded repair narratives and exact previous
frontiers remain in those commits; they are not later-candidate qualification.

## Current build and iteration

Run `compiler-goose/build.py` with explicit Goose, Clang and stdlib paths. Its
default stage cap is 30 seconds; repair attempts use 120 seconds and a 300-second
overall cap. Development uses Goose/C `-O0`; no Zig oracle is invoked by this
build. Runtime/platform C objects are cached by content and toolchain.

One coordinator runs actual emission/link attempts. Evidence is under
`build/goose-port/verification/`: `build-N.log`, `build-N.json` and the selected
source/toolchain manifest. From attempt175, an immutable input copy is kept at
`build-N-inputs/compiler-goose`; capture hashes are checked before and after
copying. Capture175 costs 0.1865 seconds. Later live edits cannot mix with those
inputs. Live artifacts are published only when their hashes still match.
The coordinator collects five seconds of diagnostics after the first error,
then terminates the build and its compiler process group. A timeout is not a pass.

Checkpoint `0e84f55bea07a49cf3fb74957923779ff717ada7` preserves the first
frame, recursive-scratch, constructor and slice-selection repairs. Later repairs
make field spelling optional consistently, use payload-enum predicates, retain
catalog references instead of copying Modules, and capture a compile-time callback
through a nested generic function. All 38 native array appends in four affected
files now use element `push` or slice `append`; numeric counters remain unchanged.
Borrowed report/header lookups use reference iteration. Whole parsing passes 439
files in about one second. No successful whole type check, C program, link, CLI
execution, Wasm comparison or Gdev run exists for the Goose compiler.

The selected checker improves an earlier frozen185 failing prefix; it does not
establish a full-build timing. Actual repair builds remain bounded to 120 seconds
per stage. This checkpoint preserves exact frozen230 inputs with the accepted
global-filter checker. Build222 stops after46.13s at hash/asset/decoder API errors;
223 advances to an unused Instance slice-field escape after46.64s.224 removes
those two unobserved fields; substitution still fills the caller-owned buffers.
Build224 stops after46.82s at a missing implementation-evidence scoped helper,
collection-operation hash hook and asset text ownership. Those follow-on repairs
remain in progress; whole emission/link/CLI/Wasm qualification remains pending.

The scoped implementation-evidence owner now initializes, invokes and cleans up
through one callback boundary. Actual core/snapshot admission methods use explicit
buffer items, stable Host locals and recursive annotations. Focused laws execute
all twelve owner buffers and both maps, release/reuse/failure paths and admission
budget/error conversion; resolver/projection/import leaves remain controlled.
Collection operations retain their native four-byte enum ordinal hash. Asset text
cleanup stores scalar ranges at allocation, and Candidate stores its exact slot
index; cleanup validates its canonical reference before freeing. Type-safe null
slices replace temporary defaults, retaining allocation and cleanup order.
Specialization initialization preserves five borrowed tables, admits a shared or
fresh stamped gate, leaves the target unchanged on failure and uses an empty
scratch policy. Both native fixtures execute on official and selected checkers.
225 was cancelled after22.5s when its concurrent focused fixture caught the
scratch-policy initializer omission;226 includes that repair. Source-only checkpoint
and focused controls do not establish whole-program qualification.

Frozen227 also contains46 mechanically typed empty-slice returns and23 direct
pool frees. Identical pointer/length runs can be freed without first recovering
an index from a borrowed reference; official and selected native probes execute
that API. Asset TextRun sidecars were therefore removed in favor of the original
slice registry. Build227 collects282 diagnostics across51 files after56.43s
(15s after the first error), revealing broad generated identity/enum-codec,
archive/reuse and frontend/driver API repair groups. Whole program C is absent.
Later actual resolve tests expose/fix copied Host state through reference binding;
these and final asset laws qualify their exact recorded working-tree hashes.
They do not retroactively qualify frozen227 or the full compiler.

Frozen228 contains the broad serialization/API fixes and eight mandatory query
adapter contracts. Canonical receipts validate each owned run against its named
pool at unchanged length. They retain pointers, allocation/copy order, scalar
metadata and cleanup. The actual Portable/Optimizer adapters execute40-record
16->32->64 table growth, and all eight concrete schema mappings pass focused
checks. Stack-backed and wrong-pool payloads abort at receipt validation before
publication, as the Goose runtime pool contract requires; no escape rule changes.
InputPin stores two scalar range words into its original pool instead of a slice
header, with identical layout/allocation count and tested failure cleanup.
Build228 stops after17.66s with nine captured diagnostics across eight files;
its15s collection window is bounded and is not a complete remaining-error list.
Later worker/archive/hash/cleanup fixes and request-reader API repairs are active.
Latest diagnostic/cache-offer component laws qualify their recorded source hashes,
including working-tree edits after228; whole compiler qualification remains pending.

Frozen230 includes a return-value JSON reader with six explicit record heads,
retaining readonly slices and avoiding writes through readonly-header references.
Forty-five input cases, three reuse rounds and24 injected registration failures
return every byte/record/link pool to zero on both binaries. A high-water native
frame buffer grows only as needed; each Frame exposes its exact packet prefix.
Split I/O, EOF/error, shorter-frame reuse and writer controls pass without packet
copies. Proof terms clear at their actual local native-array owners before Store
index/identity teardown; reusable-pool and live-slice shrink negatives reject.
The tempting by-value aggregate clear helper passed positive but failed strict
negatives, and was rejected. Build230 stops after17.77s with19 diagnostics across
14 files in its15s collection window; protocol/schema and publication fixes continue.

ScopeKey and three principal-interface enum hash hooks now match native golden
streams. Decoder allocations dispatch by the actual owner type at121 generated
sites, with idempotent generator repair support. Checkpoint nullable cells use
single-field nominal slots, preserving live-cell references and mutation order.
Typed empty asset and restart-path defaults avoid references into temporaries.
Diagnostic JSON methods return sticky writer errors; explanation publication
snapshots candidate/step text before releasing Builder originals. Focused native
execution covers publication lifetimes, aliases, bounds, failure cleanup and pool
reuse. The bounded extra text copy is measured separately from compiler timing.
Eight remaining confirmed native element appends use push; slice and custom-buffer
append APIs retain their behavior. Whole-program qualification remains pending.

Given-equation normalization uses lexical memo-hit scopes and fixed pooled scratch
instead of native dynamic locals across its recursive cycle.123 executed controls
per checker cover normalization, rank/ties, rows/effects, memo/depth/fuel/error
order and six scratch failures; active runs return to zero. Body audit reconstructs
the original algorithms modulo storage/cleanup. TypeStore semantics are controlled
leaves. Declaration projection work now has a checked nonnullable borrow, retaining
the original assertion and fuel behavior across calls;27 controls and old-bug/local
escape negatives pass both checkers.

The global-filter checker improves frozen220 first-error medians99.138 ->42.461s
(57.17%) over two rotated matched pairs; sampled VmHWM is essentially unchanged.
Both reviews,14 AST laws,256 ordered comparisons,201 frontend and eight runtime
parity controls pass. These are not completed compiler timings. The
[accepted receipt](../../benchmarks/evidence/qualification/2026-11-08-goose-global-filter.json)
pins the candidate and incremental source patch. The tracked builder recipe now
reconstructs all108 candidate source files byte-for-byte with zero fuzz or offset;
no rebuild was needed to verify adoption. Installed Goose and Zig are unchanged.


Generic implementation admission selects first matching contracts by scalar
index into its actual immutable owner, supporting both core.Module and Interface
without nominal record conversions. ScopeImport/ScopeAnchor carry that index;
four append-only local arrays use grow-only storage so their scoped views are
legal. Forty-two template cases,126 actual scope-anchor calls, bounds and
copy-failure controls pass on both checkers; Copier equality/type-copy leaves
are controlled, and full scope/declaration algorithms are not runtime-qualified.
WordMap is a nominal record with exactly the old count/slots layout. This fixes
method lookup in all five Copier maps and external callers; wrappers, pools and
counters are unchanged. Growth/update/physical restore/clear/lease reuse laws
pass both checkers; restoring only the alias reproduces the original failure.

A separate source audit covers81 single-element native-array append-to-push
repairs. Five custom IdBuffer substitutions were identified and reverted before
frozen220. Receiver/RHS declarations and source hashes are pinned; the broad
batch remains source-audited rather than a completed checker/runtime result.


The entire staging capture checker checks alongside the actual capability engine
in about 0.42 seconds. Twenty-three runtime capture/report/fuel/cleanup laws pass
on official, baseline585 and selected46, including leased report reuse/deinit,
cycle/contents rejection and exact budget7/budget6 boundaries. PhysicallyCaptures
is a controlled false-returning leaf with its actual signature; its semantics
are not qualified here. Mutable cleanup iteration, native scalar pushes and
optional report narrowing are repaired. Restoring each old bug independently
rejects on official and selected46.


The complete capability expression fixture checks 770 specializations across
37 files in about 0.37 seconds and executes nested success/error/fuel controls.
It uses the full production capability functions, Scan/Tables/Environment and
Module layout, actual report pool and real evidence/project/effect engine.
Graph edges/bounds, contract proof, relocation, rank equality and cleanup/task
admission remain controlled semantic leaves; this is not whole-runtime parity.
One Scan and an invocation-local active-call table replace cloned scoped views
and scalar publication. Newest-first lookup, per-entry fuel, stack marks and
error cleanup are retained. Reports copy directly from Scan into the same 13
pools in the original order; success preserves existing owner IDs and consumes
no extra fresh-owner allocation. Source arrays can be cleared after copying.
Tests cover pool reuse, stale leases and full cleanup. Task operand getters
retain original subspan bounds at each original access, including malformed
short spans with trailing data. The raw-offset prototype is superseded.


Eight module-extra range accesses now carry scalar core.List receipts; seven
loops load each Id before recursion. Validation stays once at the original point,
with unchanged fuel/error ordering and separate record-field validation. Accessor
narrowing alone still fails the alternating-root alias witness, so it is rejected.
No list copy is added. Exit swap-removal uses a typed same-array helper at its
original statement point, retaining removal order and exact Module references.


Callable, Control and Exit construction/append use narrow nonrecursive helpers.
Official and selected46 tests retain exact references while recursive activations
alternate current/foreign modules; both reject local and recursive-local module
escapes into ancestor tables. Operation construction and its eventual append
remain at their original points around validation/projection. Operation equality
uses scalar lookup indices, preserving last-match selection, per-item fuel and
comparison order without constructing a default Module reference. Graph capture
keeps its i64 index and direct module indexing; no narrowing is introduced.


Projection scratch now owns binder snapshots addressed by scalar ranges. The
rejected source-relative List spans read the wrong binder during cross-source
resolver reentry: they return level0 where original semantics require level1.
That countercontrol compiles and fails on official, baseline585 and selected46;
the owned snapshots pass on all three. Final payload is 16 bytes per frame plus
four bytes per copied binder and one additional snapshot allocation. Header
reserve stays first; fuel and stack order are unchanged. Physical OOM remains
unqualified; no whole-runtime memory or speed gain is claimed.

The actual projection/interner fixture emits, links and runs in under 0.75 seconds
per selected toolchain. It includes real effect evidence, cache and validators,
with unused diagnostic fields omitted. Cases cover shifted/nested scopes,
cross-source reentry, retained answer/label cache fuel, resolver behavior,
malformed binders, cleanup, depth and abstract-type recursion. Binary, runtime,
stdlib and source/extraction identities are pinned in the evidence. Recursive
lifetime branch/match/callback scratch uses pooled fixed-size descriptors;
36 actual-record SCC cases pass official and selected46, with zero active scratch
runs after every return and exact frame restoration. Semantic leaves remain
controlled. Old native recursive buffers still reject. Boolean binding and two
fixed result-array initializations are repaired; their algorithm order is kept.


All 67 affected nullable-reference getters now return through direct slot probes,
removing temporary Map facades. The audited 66-site follow-on changes no lookup
algorithm; pooled_map.get already delegates to the same slot function. Numeric
proof storage/view construction uses narrow boundaries while retaining owner,
limits, account and visits. Dictionary access follows native get/insert/contains
and count. The take method borrows its destination holder; its append, source
clear and result construction order are unchanged. Both checkers execute the
actual clone/take/builder/term-intern records and methods in the focused fixture,
with original ownership and indexing failures retained as negative controls.


Finite implicit-binder normalization now calls a shared nonrecursive body,
preserving binder order and the former normalization body exactly. Seventy
isolated differential cases cover bounds, errors, fingerprints, IDs and cleanup,
with lower storage controlled. Actual recursive validator walks pass with nested
quantifiers, row traversal, exact fuel and seen writes. Typed mutable empty
slices and a small frame setter preserve roots; negative local-frame escapes
still reject. The follow-on fixture includes the entire real projection comparator and actual
effect getters; shifted scopes, type/row recursion, unordered operations, depth
and exact fuel pass on both checkers. Thirteen additional native-array appends in
capability/numeric-proof clone and builder methods use push/append. All source
law limitations remain explicit in the checkpoint evidence.


The independent CLI/Wasm smoke runner is prepared under
`build/goose-port/compiler-smoke/`. Its oracle-against-itself control passes;
that is runner validation, not Goose compiler execution.

## Qualified components and source repairs

The parser closure falls from 436 to 14 files. Official Goose execution matches
the pinned Zig oracle on 44 fixtures plus 19 malformed/UTF8/fixity/depth controls:
token/node/extra/symbol counts and every diagnostic field match. This is not
whole-AST equality for those 63 cases. Tracked parser laws separately inspect AST
shape, precedence, fixities, recovery, staging/proof recognition and depth limits.
Emission/link/runtime for the differential runner take 0.587/0.343/0.020 seconds.

`python3 compiler-goose/tools/test_engines.py --cc clang-23` executes live
coalescing, interning, owner-frame and parser sources. The latest four suites
pass in 0.289/0.207/0.151/1.698 seconds. Their small import closures qualify those
controls only. The owner-frame laws include 513 nested scopes, masking, independent
control chains, error cleanup and reuse with zero active frames afterward.

Staging's actual-record controls instantiate all 15 new scope helpers and cover
nested frames, outgoing carries, partial state on errors, shared loop/decision
flags, handler order and cleanup. Five other frame families use co-scoped views;
both checkers reject their old local-to-caller escapes. Numeric and usage scratch
tables use pooled descriptors across recursion. Eight cleanup wrappers per
family execute nested success/error controls with zero live scratch afterward;
16 transformed body comparisons preserve their explicit continuation tokens.
Controlled semantic leaves limit these witnesses to their stated boundaries.

The source checkpoint makes 202 local native-array constructions and 73 native
dictionary constructions explicitly empty, and selects borrowed slices through
pure branch-return helpers. Whole parsing passes in about one second. These
repairs do not establish full type/lifetime acceptance or compilation speed.

Borrowed construction uses typed pure factories. Fresh and copied Principals
preserve all seven borrowed roots and 15 owned fields. A local projected proof
keeps the real Resolver; only owned state is published after success. Extracted
laws execute nested projection selection, rollback, budget boundaries and state
publication on official/private checkers. Reduced graph matcher/endpoint and
principalInstantiated stubs limit those laws; they do not qualify full bodies
or returned-Principal provenance.

Solver construction binds immutable obligation slices at initialization. Its
shared authority snapshot contains owned fields only; slice identity/length
checks retain the original cache-match criteria. This relies on the audited
two construction paths preserving those roots before first capture, with an
assertion and negative controls for violations. Actual-schema laws cover view
construction, cleanup, eligibility and cache roots; reduced store adapters do
not qualify the complete solver.

Pack projection owns its Resolver, Context and Walker in one scope. All owned
Context/Walker fields are published on success and failure. A newly populated
borrowed source-row cache is reconstructed from its exact live snapshot lease;
an inherited cache retains its original owner. Actual-schema scope laws and
real projection-selection/budget controls pass on both checkers, with reduced
matching adapters disclosed in `build/goose-port/pack-scope-laws/`.

Returned call Principals preserve the canonical current/foreign graph and the
caller's shared budget. Qualified staging returns its 15 owned Principal fields
across local Views, then reconstructs borrowed roots at the consumer. Laws cover
distinct but equal-valued foreign headers, both catalog forms, mutation through
the returned budget alias, cleanup and error ordering. Reduced mapping/leaf
adapters mean these are boundary controls, not whole call/staging qualification.

Certified scheme comparison uses the same scalar Principal state boundary.
Both checkers execute 192 scope controls and reject the old escaping wrapper:
early length/limit rejection leaves state untouched; success and matching errors
publish partial owned state and clear the temporary certificate. The matching
leaf is controlled, so these do not qualify the full certificate algorithm.

The main checker's arm capture is an owned optional scalar receipt into its
existing equation-ID run, with no new pool or allocation. An actual `caseArms`
fixture executes 33 controls per checker, covering empty/large runs, nested
capture, parent restoration and binding/expression/constraint errors. Engine,
tree and expression leaves are controlled, and two Buffer append calls adapt to
native array push; full Engine and block-body execution remain pending.

Nested executable/call entries use local scalar Workspace copies when no parent
admission exists, publishing scalar results on every return. Existing-parent
calls retain admission and budget identity. Construction/alias/cleanup laws pass;
real returned-proof integration remains for the whole build. Recursive importer
scratch uses fixed pooled descriptors with original lazy growth and fuel order;
all 22 selected fuel boundaries and recursive cleanup controls pass.

Cache target values are scalar pool ranges. Source rows/definitions retain only
their existing snapshot lease; a generation-checked accessor supplies the data.
Actual extracted laws cover growth, transfer, reserve failure, 64 fuel failure
points, empty spans, stale/reused generations and complete cleanup.

Body name indexes contain scalar retained-body indices and tags, comparing the
actual owned name bytes. Actual helper laws cover duplicate names across chunks,
collisions, backshift deletion, compaction, clone, reference counts and reuse.
Growth now allocates/rehashes a new run before freeing the old one; transient
allocation behavior differs from the old realloc path. Canonical chunk lookup
now precedes lease publication, so an invalid-owner assertion occurs earlier.

Packet generators reconstruct the previous name-slot wire format and use explicit
optional-value dispatch. Official/private native laws match an explicit legacy
wire model, including byte encoding, depth failures, malformed index/name/count/
capacity rejection and unchanged bad-tag acceptance. This is not comparison
against an old compiled packet binary. Edit generators, not generated output.
ABI 8, guest session 2, saved schema 26, public project protocol 1 and private worker
protocol 2 remain required.

The constructor-order batch was independently reviewed: 64 temporary groups and
700 initializer expressions retain their original evaluation points and values.
Build165 was stopped after a review found misplaced declarations; it is rejected
as qualification evidence. Build174 also predates a final live name-cache edit;
its diagnostics qualify its recorded input tree only.

## Toolchains and remaining qualification

The installed upstream Goose remains unchanged, SHA256
`b27ab168cfc9bcd51e5801c5e0c2c520e98db9c2db54fe15d5206d3168c59bb2`.
Repair attempts explicitly select the optional private checker, SHA256
`8335db022b43cd0054747e29155edf54646bc170c8e30b5a17556a8e01b10f43`.
Its baseline46 recipe is tracked; the accepted delta is pinned in the receipt
above while combined-recipe verification finishes.
`tools/build_goose_checker.py` and `tools/goose-containment.patch` preserve its
reproducible recipe without modifying the sibling installation. A zero-context
patch applies without fuzz and reproduces all 108 candidate source hashes;
patch, full-source and three resulting-header pins are checked before compilation.

Nominal equality needs the declaration and closed arguments, independently of
whether this equal type node has an attached instance cache. The identity proof
checks declaration validity, exact generic arity and closed arguments; the
by-value walk separately requires validated, nonfailed instances before fields.
This passes 53 actual-AST laws, 178 graph controls, 201 exact frontend controls
and eight runtime controls. Three frozen185 pairs measure 87.430 -> 54.749 seconds
median to the identical diagnostic, a 37.38% reduction. All six runs are stopped
after that error. This is not a completed compiler or Gdev timing.

The selected follow-on gate qualifies only reference reachability. Nominal
arguments use closed identity; actual fields require validated, nonfailed
instances. Reference and slice subtypes are traversed conservatively, and only
whole-root success is cached. Shared graph readiness and reached-element
publication retain their previous rules. This adds 41 AST laws and passes the
178 graph, 201 frontend and eight runtime controls. Two fresh frozen185 pairs
measure 48.017 -> 29.326 seconds median (38.925%) to the identical error. Their
conditions differ from the earlier identity pairs, so the percentages are not
combined. All four runs are stopped after that error.

The previous f211 checker matches the earlier 201/eight controls, with three
expected-acceptance mismatches shared by baseline and candidate. Its older
failing-prefix median is 7.601 -> 4.379 seconds; those frozen inputs differ from
the current measurements. Earlier O0/unmatched experiments remain rejected.

A subsequent exact-pointer visited-set experiment passes 201 frontend and eight
runtime parity cases, but fails its small-case performance gate. One explicitly
approved whole-prefix trial measures 71.738 -> 70.735 seconds to the identical
frozen181 diagnostic (1.4%, below the required 20%). Both runs are terminated
after that error; neither is a completed check. The experiment is rejected and
the selected checker at that point remained f211; these experiments were not adopted.

Bulk successful-subgraph publication also passes the semantic controls but
measures only 84.273 -> 83.872 seconds to the same frozen185 error (0.48%).
It is rejected. Synthetic graph wins do not establish a port improvement.

Reusing root candidates at the last callee-store depth also passes isolated
semantic controls, but its actual frozen185 trial regresses 32.924 -> 34.322
seconds. It is rejected. Owner-local adapter reorganization changes too little
of the main closure to justify a broad rewrite; no full-build gain is claimed.

The Zig oracle remains
`build/goose-port/oracle/bin/blotc`, SHA256
`7c8027242749ccc1027c6d855a7bd91f7cba72f27a39df307e36ea29aace3ac8`.
Its fresh 120-second gate passes smoke, harness, release build and compilation of
all 2,965 native laws without LLVM. Execution stops after 60 native passes and 30
completed exhaustive allocation sweeps, without a failing law. Full qualification
remains pending; these results do not qualify the Goose port.

Owner IDs certify immutable admission headers, not arbitrary mutable revisions;
rewritten headers need fresh IDs and cache catalog ownership checks. Removing
the optional bounds cache keeps validation/fuel behavior but may add transient
allocation, failure opportunities and runtime cost. Measure those differences
once a runnable compiler exists.

Recoverable physical OOM and retention/allocation observation remain separate
production requirements. Null/unavailable metrics do not close them. Full compiler,
public API, executed Wasm, copied-worker, library and Gdev qualification remain
pending. Subsecond compilation and 1–2MB Gdev Wasm remain unmet.
