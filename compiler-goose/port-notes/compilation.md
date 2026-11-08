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
The coordinator uses an explicit diagnostic collection window after the first error
(currently 3 seconds from attempt 285; previously 15 and 45), then terminates the build and its compiler process group. A timeout is not a pass.

Frozen412 is the current source checkpoint. The selected private checker is
`0c235f038e1b40a7ff59abd140b666abef2b6b33d98b18753b33172f6dcef653`.
It retains 57bb's exported-root scheduling, raw-store identity skip and
visited-type buckets, adding live historical event indexing. Candidate queries
check current keys/classread normalization and return original ascending IDs. All 201 frontend,
8 runtime / 7 focused / 12 emitted-C controls and eight extra store controls pass. 8,192 extracted store
comparisons (also ASan/UBSan) and 300 visited-type laws preserve original order,
relevant lookups and error/effect traces. The tracked recipe reconstructs all 108
source files byte-exactly. Ordinary tools, siblings and Zig oracle are unchanged.

Telemetry 400 measures 814.7 million raw-store examinations and 12.78 billion TypeEq
entries by 114.914s while body checking progresses; held/slot fixedpoint work is
small. It is instrumented work evidence, not compiler timing. Static callback
and ChildVisitor allocation prototypes remain unselected after capped 398/399.
The raw-store candidate reaches a new pattern lifetime error in 108.520s; after
its source repair, the type-bucket candidate reaches Engine? dispatch in 100.647s.
These are failing-prefix progress, not completed compilation speed results.

Source repairs keep current-frame/generation/owner identity guards, immutable
catalog scalar reloads, live owned-pool receipts, existing lease ownership and
callback cleanup/error ordering. RegionSnapshot is only its existing lease and
generation; the lease owns State/solver metadata. Do not infer arbitrary live
ownership from bounds or an ID, cache mutable roots, or patch generated output.
The complete superseded repair narrative is pinned in
[72295746](https://github.com/mewhhaha/blot2/blob/72295746740d1f74c8860129368b198023ffb23f/compiler-goose/port-notes/compilation.md).
Qualification still applies only to its exact named source and fixture.

405 narrowly changes two fresh packet-decoder temporaries to mutable byte slices;
no checker const-rule change. 36 extracted codec laws pass on both checkers,
including readonly record fields and error/cursor/owner cleanup. Its 100.473s
attempt clears that assignment and reaches missing project::Range decoding.
406 adds Range through the generator and fixes BodyOffers to logical symbol,
presence and cache payload, reconstructing child-owned handles. Both checkers
pass 20 offer laws plus stale rejection; 750 ordinal cases agree. Two normal
generator runs match all 440 source hashes. Its 102.180s attempt reaches a new
initEngine Project lifetime/global-store error. Trace real Project ownership and
borrowed compiled payloads next. These packet controls do not qualify full engine
transport. No compiler C/header/executable or executed-Wasm result yet.
Keep 120/300s stage/overall caps and 3s first-error grace. A cap is incomplete;
do not repeat unchanged inputs or report it as success.

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
`0c235f038e1b40a7ff59abd140b666abef2b6b33d98b18753b33172f6dcef653`.
The tracked recipe reconstructs all 108 selected source files byte-exactly; its
accepted changes and independent controls are pinned in the receipt above.
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

407 passes Project headers by value through the retaining factory chain and
returns updated worker requests on all 16 decoder exits, before caller cleanup.
Both checkers pass 280 fault-prefix/cleanup cases; local payload escapes still
reject. No new authority, payload allocation or copy. Its 101.946s run clears
Project retention and reaches executeProjectJob with a nullable Engine field.
Use the existing local borrow/assert narrowing pattern next; no C output yet.

408 narrows the worker Engine field through the existing local borrow/assert
pattern; exact source review passes. Its 120.308s capped run captures one new
recursive-cycle lifetime error at inputCallbackRecipe (check.goose2003), with
no C/header/executable. Subtract the borrowed Recipe carrier if source proof
permits; no unchanged retry or cap growth.

409 extracts the callback recipe/derive/instantiate prefix to an acyclic helper
returning a scalar; branch casts, errors and recursive tail stay ordered. Both
checkers pass 42 controls and two local-borrow escape negatives. The whole run
caps at 120.281s with zero diagnostics and no C output; no qualification or
completed speed claim. Measurement 410 (same 120s cap) reads five valid ABI2 snapshots and reaps in
119.671s. At 115s, 1.302 billion raw visits are 99.98431% identity skips; positive
ClassAt work is small, while 7.934 billion TypeEq calls remain. Both sampled
stacks are waiting main-thread frames, so provide no hotspot attribution.
Next: indexed live raw-event selection at its 3 write sites, preserving event
order, current-field checks and classread normalization. No new IR or cap growth.

The selected index candidate 411 passes 201 frontend / 8 runtime / 7 focused / 12 emitted-C controls plus
eight store controls, 24,576 state/order and 49,152 query comparisons and
ASan/UBSan. Same 409 authored inputs reach a new scalarArgumentPossible AST
child-loop borrow in 107.649s; no compiler C/header/executable. All-relevant
projected replay regresses 2.15x; preserve that limit. Exact 108 source recipe
reconstruction passes without another build. No completed speed comparison.

412 reloads scalar AST child IDs in scalarArgumentPossible while preserving
full initial validation, iteration order, depth and false/error exits. Exact
source review passes. Its 107.049s run reaches operationValue readonly Option
overload mismatch; no C/header/executable.
