# Owned-storage rewrite: active task index

> **30 October handoff:** work is frozen for the requested main-branch commits
> and pushes across Blot, Gdev, Ink and Pen. Read `CONTINUE.md` first. The final
> Boxing source batch is written but unbuilt. No Gdev main Wasm or Pen frame has
> succeeded. The required full compiler gate ran and stopped at the protocol
> smoke span assertion (3 passed, 1 failed); see `storage-handoff-evidence/`.
> Tracked continuation runners are now in `scripts/storage_handoff/`.

## Immediate milestone: one real Gdev frame in Pen

The user's current direction is to integrate one real Gdev frame before broader
migration or qualification. Storage and callback interfaces needed by that frame
are frozen. Preserve existing edits, but pause unrelated fixture, generator and
legacy-retirement work unless an actual frame blocker requires it.

The frozen frame boundary is the current ABI 8 data-stack runtime and version-2
numeric session protocol. `world_storage.with_owners` retains session pools;
`host.with_frame` owns frame buffers; `application.bind_frame base bindings`
returns invocation-local aliases that are never stored in the persistent base.
`program.run` retains the named `ResizeArray F32` incoming/outgoing buffers and
calls `host: Array F32 -> Array F32 ! { Foreign }` with copied packets.
`execute access operation payload outgoing` writes the response after the
operation lane, and `acknowledge access published` repairs presentation caches.
Keep schema 26, operation numbers, wire order and these lifetime rules fixed.
The current Pen configuration reserves 2 MiB temporary, 256 KiB persistent,
2 MiB transport storage and 4096 owner slots. Change a boundary only for a
reproduced application blocker, with the required caller/callee changes together.

The prepared runner is `build/storage-integration/gdev-one-frame/run.py --launch`.
It runs the real Gdev `main` through Pen headlessly with SwiftShader, and requires
successful process exit, exactly one frame trace, a completed render marker and
a 640×480 screenshot. Each attempt keeps separate evidence. It has not yet run.
Compiler attempts now retain unique directories under `build/gdev-first-frame/`.

The source-proof integration now retains exact public callee arguments, grounds
private field receivers, solves physical fields before shared hypotheses, and
preserves mapped `Foreign` effect labels. Ordinary source schemes support 256
public type variables and 128 rows; portable and explicit-rank limits remain
unchanged. The effect-row substitution regression now passes. Earlier
correlation and lint passes are historical evidence, not qualification of the
current diagnostic compiler build identity `29bc25d3f516f7de` (configured Gdev
hello identity `71db1abcb18e7df70`; binary SHA-256 starts `d372edd3`). Its temporary
failure traces do not change proof semantics and still need cleanup.

The real-library scene decoder compiles and executes its empty-scene case.
Pen's generated flat encoder has schema-derived header, projection and count
contracts; its ten generator tests and reproducibility check pass. The ABI 8 Pen
runtime binary is unchanged. Main-stage Gdev owner contracts were made explicit
in a finite UI/platform/player/gameplay batch, followed by output's borrowed
snapshot contract and Ink editor-camera/brush-face contracts. These changes keep
existing nominal types, borrowed fields, update order and behavior.

Salt simulation now shares canonical Catch/State/Brick/Stack/Stash definitions
through `world/salt_state.blot`, with Salt's public type aliases retained.
Production constructors use the shared module explicitly: transparent type
aliases do not introduce constructors. Simulator state/row owners and affected
catch arithmetic helpers have concrete contracts. Source compile checking passes
this extraction; fixture constructor migrations remain paused until the frame.

The policy-row blocker is fixed. Checked source instances now retain lexical
ownership of exact generic row-tail witnesses after successful instantiation and
all prerequisites. This admits legitimate latent parameters without adding pure,
closed or Foreign facts; rollback and ambient checks remain intact. Sol A's
focused review found no blocker. The correlation runtime law passes on this
candidate.

The user explicitly added standard-library syntax migration. A Sol agent updated
all 13 `std/*.blot` files with `$` constructors and equivalent immediate curried
stages, plus `std/README.md` and `std/PERFORMANCE.md`. Prior dirty work and
algorithms are preserved. The affected batch passed 25 checks and failed one
stdlib scalar-export law. The exact fixture fails identically against the
pre-agent std snapshot: scoped backend rejects exported nonfunction bodies at
`scoped_backend.zig`'s entry check. Do not replace the fixture with `#run` to hide
that requirement. Evidence: `std-runtime-candidate-a94f12ff.log` and
`std-syntax-baseline-comparison-a94f12ff.log` in the attempt directory. This is
pending backend global-export support, not a new std syntax regression.
The subsequent `std/array` concat/push count and reader contracts passed ten
focused prelude/stdlib checks with that same scalar-export failure unchanged
(`std-array-contracts-runtime.log`). Collection input capabilities remain generic.

Reservation preparation now accepts canonical borrowed Stack/Brick views,
removing the unresolved nested generic-reader path without payload copies.
Finite ECS, nested owner, UI geometry, Salt snapshot and Tutorial contracts now
preserve canonical owners and borrowed views at application boundaries. Tutorial
reconstructs a Story when changing its generic supplies payload to a borrowed
view, rather than changing the existing value's type through an update.

Hand's scratch callback uses a structural record merge over existing owner
aliases. Source proof retains the exact merge obligation for generic records;
instantiated concrete records receive strict field checks. The scoped emitter
preserves field roots, epochs and callback captures, evaluating each operand
once with right-hand replacement precedence. Apply-result checking now follows
callee/argument proof so generic callback rows have their checked witnesses.
Both executed-Wasm merge laws pass: generic replacement/callback/owner behavior
and rejection of a scratch view escaping its scope. Evidence is
`consumer-merge-apply-runtime.log` under
`build/gdev-first-frame/attempt-XRdVWB`.

Canonical read helpers now expose their actual resource result types in Salt,
Buildings, Robots, Build Bar, God Hand and Hover. This supplies type-preserving
update contracts at the declaration boundary while keeping outer access records
generic. Robot presentation and finite frame-geometry helpers now declare their
known numeric/pose/draw contracts; integer geometry indices use explicit
`U32.to_f32` conversions. Formulas, ordering and collection capabilities remain
unchanged.

The diagnostic trace located the generic prelude `add` failure in Ink's
`render.on_screen`: canonical matrix locals preserve its structural frame input.
Salt picture-cache Stack/Picture readers and pile-render numeric contracts then
cleared the next source blockers. Subsequent batches cover HUD borrowed words,
Station state, placement, robot timing/movement/wake rows and remaining known
geometry conversions. Ink's generic `ecs.read` now declares its `Maybe a` result
and U32 reader without evaluating payload access on an out-of-range request.

Further source batches cover material-batch rows, nearest-pile/stash queries,
minors movement/assignment and the Salt simulation callback group. Two concrete
compiler row defects are fixed: generalized source row parameters retain their
exact witnesses before body closure views, and two aliases of the same immutable
unknown row compare equal without acquiring purity or closure authority. Each
fix has a passing focused native law; the complete native inventory compiles.
This is not full native execution qualification.

World storage now declares the existing 166-field frame record as `FrameAccess`.
All ten game stage callbacks use this structural contract. Its four storage callback
fields have explicit pure effects, and the two higher-order building callbacks
use typed forwarding functions. No owner layout or packet protocol changes are
introduced. These boundaries cleared the nested callback-row rejection. Actual
main `main-fa38c3d606f02d0b` (`root-building-callback-contracts-main.log`) reached
an unresolved private `access.rock` receiver in Hand's copy callback. Hand now
ties its input, merged working record and consumer input to the same generic
type; all ten replacement fields preserve their original types while changing
owner identities. Its effect row remains polymorphic. This cleared the private
receiver failure. The next attempt, `main-d8e317b261cfce65`
(`root-hand-shared-access-main.log`), fails in strict callback-row comparison
while validating that record merge. Solver initialization now retains already
checked source-instance ownership as rigid facts; its positive/negative native
law passes and all 2,669 native tests compile. This independently valid transfer
fix did not clear the application failure. Failure-only diagnostics then showed
the merge selecting exactly the same function type ID on both sides, including
a nested latent row that was not a direct mapped row witness. Merge equality now
accepts that exact type identity without granting any row authority; distinct
types retain the strict comparison. A whole-proof native law rejects unowned
callback rows and forged result fields, and both executed-Wasm merge laws pass.
All 2,670 native tests compile. Actual main `main-b9473c0944a82c6d`
(`root-merge-identity-main.log`) cleared Hand and now reaches an unresolved
numeric conversion in Boxing's update; its finite source contract batch is next.
No main Wasm or Pen frame has succeeded yet. World-storage's last measured proof
consumption was about 9.694 million of its 32 million steps.

One inference limitation remains explicit: the temporary source solver rigidifies
all original caller-side variables. A known `F32 * F32` can therefore fail when
its intermediate result remains a caller rigid. Do not thaw all such variables:
a future fix must distinguish exact fresh instance variables from genuine
universal binders and preserve rollback and correlation. Solvers currently
discard inferred equalities when each inquiry ends, so merely making checked
instances flexible would permit conflicting answers in later inquiries. A safe
fix also needs retained lexical equalities, replay, atomic publication and
conflict rejection. Diagnostic builds classify failed rigids before
choosing that change. Canonical application contracts remain the bounded current
workaround.
The classification showed one failing conversion witness in the active scheme,
but that alone does not establish public universality: a full scheme also holds
private prerequisite witnesses. A future fix must distinguish public/captured
binders from private qualifiers and solve the whole correlated dictionary.
The two concrete callback-row fixes do not implement that broader solver change.

One compiler inference defect remains tracked separately: in output `bounds`,
an inner `do` owner was projected as `Never` despite a reachable nominal `Rect`
break (`main-4ee9932fa66243d6`, `consumer-jump-owner-defect.json`). The standalone
reduction does not reproduce it. Equivalent function-return guards cleared the
application boundary. Strict proof checks remain unchanged; fix the general
inference defect after the frame candidate.

Root owns actual-main builds and Pen execution. Sol C takes concrete compiler
blockers; Sol A/B supply bounded reviews or source reductions when needed. Check affected laws after a coherent fix; broader qualification waits for
a working application candidate. No performance improvement is claimed yet.

Prepared 29 October 2026 from three Sol source reviews. The
[decision record](../zig-native/STORAGE_REWRITE_REVIEW.md) contains the
findings, feature cuts and target contracts. Tasks 110–119 are **in progress**.
The most recent passing shared development check took 12.54 seconds: the
complete 2,652-test native inventory compiles, all 43 selected native laws and
81 executed-Wasm checks pass, and formatting, TypeScript and Zig lint pass
(`build/bench/check-dev/run-793ee36e99b39c55/results.json`). This is a
development family, not full qualification. Closed pure inline-data helpers now
admit acyclic direct callees. Selected call cycles reject explicitly; concrete
checked types and static callback choices distinguish finite nested generic
calls. General callback ABI remains pending. Source proof work has a separate
inventory-sized allowance per immutable module, shared across that module's
roots: `min(32_000_000, max(1_000_000, 256 * inventoryWords))`, where inventory
counts Core nodes/extra words, type nodes/extra words and obligations. Imported
bodies consume their own module's allowance; cache hits cannot reset it. The
emitter/dispatch allowance remains separate and unchanged. Explicit caller
budgets retain their previous semantics. This adjustment has passed the actual
large-module boundary but has not received broad qualification.

The focused call/record/capacity Wasm batch passes 31 laws, with a subsequent
nested-variant law included in the shared check. The real Ink batch passes all
23 test entrypoints in nine ready modules (8.6 seconds), including editor
copies/codecs, changes and retained rendering. Physics is being rewritten in a
separate source batch and is not counted as passing. Owner-table retirement now
scans only its live extent, and owner-free blocks omit rewind scans. The
unchanged interpolation fixture completes in about 275 ms after previously
timing out at 45 seconds; this is a development fixture observation, not a Gdev
benchmark. Generic imported field spellings, initialized variant payloads,
empty-owner joins and loop read-shape stability now execute. Fixed global
literal pools reserve their actual extent without enlarging explicit limits;
twelve one-word state pools use under 4 MiB including scratch and transport.
Retained physics geometry now uses six explicit resizeable payload owners and
structural refresh in source. Gdev production sources and legacy fixtures are
being migrated by the Sol lanes; the migrated fixture runner currently includes
146 files and 988 entrypoints, still awaiting execution. No complete Gdev
execution, full compiler qualification or new application performance result is
claimed. Task 120 has started with explicit ABI 8 data-stack identity and host
admission: five host laws, three Pen reader tests and the 23-entrypoint Ink
batch pass on the rebuilt compiler/Pen pair. Unconditional dispatch and legacy
retirement remain pending, as does task 121; ordinary programs can still reach
the old backend until 120.

This is the active memory migration program. Earlier counted-runtime and
language-task plans are historical, not prerequisites. Keep prior work and
evidence; do not restart the 109-task backlog. No commit, push, upstream posting
or task-directory cleanup is part of this review.

## Tasks and handoffs

| Task                                                    | Result                                                                 | Implementation dependency                                                      |
| ------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [110](110-plan-owned-storage-and-specialized-calls.md)  | Storage plan, lifetime summaries and reusable destination calls        | First publish the plan/value/exit/call interfaces with 111/112                 |
| [111](111-pack-regions-and-widen-owner-identity.md)     | Packed regions, grower lanes and wide owner identities                 | 110 interface; may implement in parallel                                       |
| [112](112-admit-flat-data-and-control.md)               | ADTs, patterns, exits, loops and flat List operations                  | 110 interface and 111 runtime contract                                         |
| [113](113-initialize-pools-and-copy-host-packets.md)    | Computed persistent pools, copied packets and host suspension          | 110–112 interfaces                                                             |
| [114](114-replace-ink-storage-and-ecs.md)               | Owned collection/ECS APIs and explicit checkpoints                     | Shared target contract; write before compiler completion, accept after 110–113 |
| [115](115-migrate-ink-simulation.md)                    | Scene, physics, simulation and spatial ownership                       | 114 API handoff                                                                |
| [116](116-migrate-ink-render-and-ui.md)                 | Render/UI/input storage and known policies                             | 114 API handoff                                                                |
| [117](117-migrate-ink-application-lifetime.md)          | Live application, saves, history and native/browser protocol           | 114 API; coordinate 113 host ownership                                         |
| [118](118-migrate-gdev-systems.md)                      | Game systems using explicit pool access                                | 114/115/116 APIs and 119 owner schema                                          |
| [119](119-compose-gdev-owned-world.md)                  | Concrete world, static stages, devtools and integration                | 114/117 APIs; co-design with 118                                               |
| [120](120-retire-counted-storage-and-language-tasks.md) | Unconditional new backend; old runtime/task removal                    | Inventory early; cut over after 110–119 application execution                  |
| [121](121-qualify-and-measure-owned-applications.md)    | Final behavior qualification and separate compile/runtime measurements | 120; preserve baseline artifacts early                                         |

Dependencies mean a stable interface is needed to write code, not that every
upstream test must pass first. Acceptance waits for executable integration. Hand
off concrete type/function declarations and one representative call site; do not
create another design-only phase before implementing modules.

## Three Sol lanes, one integrator

| Wave | Sol A                      | Sol B                                  | Sol C                                             | Shared checkpoint                                              |
| ---- | -------------------------- | -------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------- |
| A    | 110 planning/calls         | 111 runtime                            | 114 storage/ECS                                   | Early API handoff; write code, no build per edit               |
| B    | 112 data/control           | 113 globals/transport                  | Finish 114                                        | **1:** compiled backend + one owned-pool/ECS slice             |
| C    | 115 simulation             | 116 render/UI                          | 117 application/save/host                         | **2:** all Ink and compact behavior witnesses                  |
| D    | 118 Gdev systems           | 119 composition/devtools               | 120 removal inventory and isolated task deletions | **3:** game/devtools and bounded browser/Pen scene/save/replay |
| E    | 120 final cutover/deletion | Fix only concrete integration failures | 121 measurements/evidence                         | One final compiler/consumer qualification batch                |

Root integrates and resolves interface changes. Each lane can be assigned to
`gpt-6.1-sol`; at most three child agents are active concurrently. Split 118 by
its explicit directory groups if a lane becomes free, after transferring file
ownership. Do not let two agents edit one source file simultaneously.

Task 110 initially owns `scoped_backend.zig`; after its extraction, root owns
that integration file, `core_backend.zig`, `backend/wasm.zig`, checker dispatch,
ABI registration, test roots, development-area registration and build scripts.
Agents own their new modules and focused fixtures. Task 113 owns `guest.ts` and
the ordinary Pen guest bridge until handed to 120; 117 owns the application
session protocol outside that bridge. Root coordinates shared consumer test
fixtures, codec state registration, generator templates and configuration.

Preserve all existing uncommitted edits. Sibling source trees are readable;
request tool filesystem permissions for the named sibling paths when writing
them. That environment requirement is not a new product-design approval step.

## Verification budget

1. Write a complete slice and its few semantic witnesses, then compile once.
   Failed compilation is repaired as a batch. No build/test invocation per small
   edit, no exhaustive OOM sweep per agent and no long generation soak.
2. Integrator checks `zig version` before each build batch: Zig 0.17.0.
   Development and native test compilation use `-Dllvm=false`, safe optimization
   and `--prefix zig-out-native-dev`. Use
   `deno task check:dev --area static-sharing` as the starting family and
   register only the affected new laws. It remains a development pass, not full
   qualification.
3. Reuse the installed native test inventory for exact laws. Group
   executed-Wasm, copied-host and worker witnesses. Consumer gates use the same
   compiler artifact; do not accidentally test the old `zig-out/bin/blotc`
   binary.
4. After coherent consumer batches, run the required Ink generation/format and
   tests, Gdev check/codegen/tests, and relevant Pen native/browser checks. Run
   GPU work sequentially and headlessly. Record baseline failures separately.
5. Final only: release compiler build for release guest/performance evidence,
   `deno task test:compiler` and `deno task lint:zig`. The full gate's native
   compilation still uses the native backend. No repeats after a pass without a
   changed candidate, concrete failure or unresolved concern.

Acceptance bullets identify distinct behavior, not a demand for separate test
programs or separate builds. Reuse existing fixtures where they cover the new
contract; replace obsolete COW/task expectations intentionally. Never mark an
incomplete run or compiled-but-unexecuted inventory as a pass.

## Completion and performance

Update each task and this index when code lands in the workspace, distinguishing
implemented, development-checked and qualified. Keep the durable decision and
final evidence under `zig-native/`. Task 999 cannot run while any task here is
unfinished and does not itself authorize a cleanup now.

Keep baseline source/binary identities before retirement. Measure fresh compile,
retained edits, precompiled warmed simulation, packet/presentation cost, Wasm
size and memory separately. Preserve meaningful gameplay/save witnesses; do not
infer frame time from the test-suite duration. Report results even if the hoped
for improvement fails to appear. Do not introduce a benchmark-optimization loop
until an actual regression or missed goal points to specific code.

### Primitive words and integration, 2026-10-29

- `true`/`false` are now bare primitive Bool literals and patterns; reserved
  `and`/`or` have fixed precedence25/20 and short-circuit Core lowering. Prelude
  lazy-function aliases removed; formatter/editor regenerated from sources.
- New executed-Wasm boolean laws pass, including skipped traps, mutations,
  precedence and rejection of non-Bool skipped operands. Main client typecheck
  and formatter batch pass; this does not qualify the memory rewrite.
- Source-body row indexes are now reused per immutable module, retaining local
  proof facts separately. The150-declaration witness passes without increasing
  work limits. Generic pool-cursor integration is still being repaired.
- Frozen Ink integration checkpoint: ECS5/5pass;
  app/input/persistence/editor/UI/ render-cache/physics modules still had
  compile failures. No complete Ink/Gdev runtime or new performance claim.
  Salt/Robots/navigation/devtools source migration remains active across the
  three Sol lanes.
- Complex resource decoders now target caller-owned pools. Editor direct stored
  encoding and decode_into/reset_storage added; source qualification pending.
- Automatic review rejected broad Salt changes in an already dirty file. Root
  reviewed exact patches, found owning temporary dirty-list records that needed
  borrowed views, and applied only plain metadata declarations using
  fingerprint, unique-anchor and duplicate-name checks. The agent resumed
  corrected operations.

### Compiler and consumer integration, 2026-10-30

- Associated operations now select real declarations from checked operands,
  retaining ordered left/right selection and destination-selected conversion.
  Reusable scalar results preserve their semantic type through generic callers.
  Four focused executed-Wasm call laws pass; a generic cursor law is still being
  repaired.
- Checked source instances admit only ordinary type leaves justified by an exact
  producer scheme. Failed candidates restore their facts. The native law also
  rejects an unrelated forged variable. Other source effect/goal proofs remain
  integration blockers; they have not been bypassed.
- Storage budgets are exposed through project-open policy, the Deno client and
  Pen settings forwarding. Retained output identity includes all budget fields;
  an executed project witness checks exhaustion, retry and reopening with a
  different budget. Per-owner reservations for the complete game remain open.
- Ink lookup building now writes independent caller destinations. Change
  normalization/composition and journal reads are being converted to caller
  arrays plus borrowed deltas. Persistence reads accept borrowed/growable input
  through associated `at`. These consumer source edits are not yet qualified.
- Brush/editor APIs are moving to destination-first face construction, borrowed
  logical brush faces and fixed stored drag origins. Editor stash/restore runs
  synchronously at the scene transition. The consumer Sol lane owns this batch.
- Source migration still includes Robots, transactional Salt operations,
  Cannon/construction, navigation and selected minor systems and debug panels.
  Do not mark 110–119 complete based only on these source handoffs.

### Latest integration batch, 2026-10-30

- Bare `true`/`false` and fixed `and`/`or` are implemented; Gdev actor-state
  equality was regenerated from the current generator.
- Source-body proofs now reuse completed claims within one immutable compiler
  context. Failed roots publish no claims; call effects and instantiated type
  checks remain independent. Operator/field catalog lookup also reuses exact
  immutable declaration selections.
- Captured type environments retain one active binding per parameter. Dependent
  reader fields and shared callback type variables are resolved before local
  output allocation. This removed the 90-second compilation timeouts in the
  changes/render-cache witnesses without increasing work limits.
- Reusable scalar, inline aggregate, and readonly descriptor leaf calls execute.
  Local optional owners retain their descriptors across branches; stored rows
  still cannot contain owning arrays. General call ABI/SCC work remains open.
- `@storage.reserve owner literalCount` gives each named Grow/Resize owner an
  explicit element request. Gdev history keeps 64 entries/1,048,576 F32 lanes;
  its payload, scratch and stash reserve their own capacity. No blanket grower
  budget increase or history-limit reduction was made.
- Current/previous persistence and full-width U32 framing execute (2 laws), as
  do prepared UI, ECS, application lifetime, and input paths. The latest Ink
  batch has 18 passing checks and 3 modules blocked during compilation.
- Reviewed Gdev source replacements retire old owning-resource factories and
  callable-returning codec migrations. Existing fixture assertions and workload
  bounds are being migrated to named owners, not deleted to obtain a pass.
- Full compiler/consumer qualification, unconditional backend cutover, browser/
  Pen execution and release performance measurements are still pending.

### Ongoing integration, ABI 8 and reusable captures

The rebuilt Pen executes 23 entrypoints in nine ready Ink modules with ABI 8
(8.9 seconds). Twenty focused call/host laws pass after preserving
output-directed associated conversion alongside the new function-result row
mapping. Readonly descriptor captures reuse helpers across owners, and syntax
nesting and active selected-call depth each retain their own bound of 128. The
complete native inventory now compiles 2,651 laws. Two focused initialization
laws pass, including independent module discovery bounds and cycle rejection.
The next complete shared family run remains pending; a temporary diagnostic
hypothesis and its fixture were removed after identifying Gdev's actual issue as
a missing concrete `Goals` row annotation, preserving the strict capture proof.

Gdev now reaches data-stack initialization planning. Discovery previously spent
one 100,000-node allowance across every imported module; it now tracks the same
allowance per immutable module, without renewing repeated visits. Application
compilation after this change is pending the protocol source batch. The protocol
is moving to caller-owned event decoding and borrowed packet state. Physics
source migration covers seven fixture modules, but execution is still blocked:
selected callback type provenance, remaining owning loop carries and expanded
expression work are concrete outstanding frontiers. No full application runtime
or performance result is claimed.

The subsequent shared development check above includes exact per-module target
indexes with atomic publication, the independent global discovery bound, and
captured composite type provenance. Nested active `Maybe.map` instances retain
their own immutable substitutions through record/nominal children; they no
longer overwrite the outer call's inferred result. All 22 focused call/host laws
pass. The actual physics module now advances to the existing 100,000-step
expression expansion bound. Gdev still reaches the separate source-proof work
bound in its progression text catalog; its generated metadata is being changed
to address the original flat text payload directly. Neither work bound was
increased.

The migrated app-hook fixture now passes its original pause/event order and
Foreign callback observation sequences, static name values, and scheduling
workloads at 0, 1, 256, 512 and 1,024 frames under executed Wasm. The primary
application stage API forces routing through an effectful bind and consumes
pause-transition events. The native Rust expectations remain unchanged; their
full native runner is still pending. Gdev progression names now address the
original generated text payload directly with 82 fixed spans. This removes the
duplicate catalog payload and advances compilation to repeated closed-layout
work in the generated asset catalog, rather than relaxing the source proof.

### Static callbacks and flat consumer metadata, 2026-10-30

The static readonly callback batch builds the complete 2,657-test native
inventory. All 48 selected native laws pass with sampled allocation failures.
The focused call/record/global/host Wasm family passes 47 laws (46 in the
combined run, then the corrected callback fixture passes separately). Captured
owner identities remain runtime parameters; callable targets and capture schemas
identify reusable code. This is focused evidence, not full qualification.

Gdev now passes the earlier asset catalog and repeated global-initializer
expansion failures. Both cannon metadata generators emit flat coordinate payloads
and range rows, preserving coordinates, tier ordering and lookup bounds. The
handmade cannon retains all 21 coordinates and six heights. Navigation endpoint
construction likewise uses one flat owner. Gdev now stops at source type-evidence
validation of its main body. Its four-module sample exposed concrete Array versus
ResizeArray/view annotations in fixture helpers; those are being corrected.

Speech, station feedback and completed-home source paths use direct mutation or
one named output owner. The ordinary Gdev fixture inventory is 146 files and
988 entrypoints, still awaiting executable integration. The separate historical
blocked-hauling fixture now retains all 11 entries and 24 checks with explicit
owners; execution remains pending. Physics, heightfield and algorithm-stress
still reach the unchanged 100,000-expression expansion bound. Returned aliases
and reusable writer calls remain compiler work; no application runtime or
performance improvement is claimed from these source conversions.
