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
per stage. Frozen199 advances past the repaired native-array family and stops after
101.558 seconds at a missing slice mapping adapter and an integer-width mismatch
in static list emission. Those source errors remain open in this checkpoint. Individual
source laws cover exact roots, duplicate policies, bounds/fuel order and callback
cleanup with their reduced continuation leaves disclosed in the evidence.

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

The next syntax batch makes 202 local native-array constructions and 73 native
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
`46b54e2a387c53bef9bee3f2e457808280269f463e6ab93d350665263ee1ea0e`.
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
