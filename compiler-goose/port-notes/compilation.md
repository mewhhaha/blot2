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

Frozen380 is the current source checkpoint. Selected private checker
`678b88bd…` checks exported roots before nonexports, retaining final export
validation and every fixup. Its 201 frontend/8 runtime controls match exactly;
27 focused controls retain acceptance and error multisets (one ordering change).
Two emitted-C/header host executions pass. The tracked builder reconstructs all
108 source files byte-exactly, without offsets or fuzz. Installed tools, upstream
checkout, siblings and the pinned Zig oracle remain unchanged.

The Session→Generator data edge uses the existing scalar Frame token. Lookup
checks generation, live/current-frame state and exact registered Session,
Generator and Workspace identities. Fourteen projected controls pass; the static
declaration graph drops939→506, which is neither an instantiated-type count nor
a completed compilation speed result. The retained importer stores destination
and memo maps only; invocation-local readers borrow real leased or unleased
source Views. Readonly Plan headers are forwarded explicitly. Invocation-owned
layout import ends before recursive proof work. Two evaluator region records
retain only their existing Frame IDs; full execution Frames travel separately.

Owned-pool transfers preserve actual live ranges and payload identities. A pool
range check or identity token alone never grants liveness. Pure constructors and
typed stores preserve original evaluation, nonce-mint and cleanup order. New
collector argument IDs are copied once into a dedicated invocation-owned run,
then freed after the call on success or error. Its exact-helper nested controls
pass on official/private Goose; the copying/allocation cost and physical OOM
behavior remain unmeasured. Fixed scratch default initialization also adds
unmeasured work relative to native undefined spare capacity.

Frozen377 shares the exact 31-field Constraint constructor between region-pool
reconstitution and principal-name copying. Both retain their distinct original
pools and copy/free order. Frozen378 reconstructs all 25 PrincipalGraph fields,
keeping its original entry mint, allocation/copy order and byte accounting.
StoreSnapshot is transferred through its existing live/generation lease and
exact pointer/length validation of all 22 leased ranges, with State unchanged.
The helper adds no allocation, clone, retain or ID mint. All 37 strict controls
pass on official and selected Goose, including stale/reused leases, all redirected
same-pool slices, foreign/stack slices and global publication/cleanup. Independent
allocation/deinit mapping and complete graph-field inverses pass. Its98.842s
actual run clears graph publication and reaches caller result retention.
Frozen379 fixes the actual binding error: plain tuple binding snapshots a
reference-returned graph; borrowed tuple binding keeps the pool header. Both
checkers execute the distinction. Frozen380 applies the same exact correction
to three audited mutable-reference results (cached unit Uses, importer and
layout bridge), then makes NormalizePrincipal borrow its description instead
of copying the whole carrier back. Only its final successful result mutates;
cleanup has no observer and both callbacks are synchronous. Independent source
reviews pass. Its98.034s run clears that boundary and reaches PrincipalVisit
buffer publication. Its three-field owned pointer transfer is next. No whole
compiler C, header or executable has been emitted; source acceptance is not
runtime qualification.

A single 15-second post-error collection experiment returns only one diagnostic
after110.572s. It is rejected; subsequent attempts restore three seconds within
the same120/300-second caps. Semantic-only entry probes remain inconclusive
(the revised probe hits20.071s with no diagnostic/C). The optional-global index
passes controls but gains match zero-global noise; it is unselected. The narrower
array-readiness gate passes correctness but regresses stresses4.2–4.5% versus
controls within0.4%; it is unselected. Cross-event root memoization was rejected
because store replay mutates provenance. Exact source/carrier limits and all
failed, cancelled and timed-out runs remain in qualification evidence.

The [preceding source checkpoint](https://github.com/mewhhaha/blot2/blob/a20bb37f4b1014bea338335e3802ebaaaad434af/compiler-goose/port-notes/compilation.md)
retains earlier repair narratives and their explicit limitations. They qualify
those exact sources and reduced carriers, not later revisions. The linked
qualification receipts preserve original requirements, rejected experiments,
source/toolchain hashes and incomplete runs. Source writing remains separate
from full compiler/runtime qualification.

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
`678b88bdf038dae9fdf1366cf59aca5dfeaf046fb29de0b2fadf85359b703c19`.
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
