# Continue the Goose compiler completion

## Current frontier

Current user priority: repair Goose lifetimes in coherent families, build the
actual native compiler, then qualify recoverable OOM/retention and differential
behavior against Zig. Verify at family boundaries, keeping stage/whole limits
at 120/300s. Source-only progress and native component tests are not executable
or whole-runtime qualification. Keep the Zig oracle and sibling state intact.

The remaining language [RFC #46](https://github.com/mewhhaha/blot2/issues/46)
stages remain in [the migration index](docs/language/NEXT_MIGRATION.md).
Immutable collections, automatic admitted copies, overloads, parameterized
namespaces and staged scopes are pending; named-owner writes remain current.

The named-function source migration is complete across **782 Blot files**:
**353 std / 3,506 Ink / 5,105 Gdev module functions** now use named declarations.
No module `const name = func` definitions remain in those trees. Genuine
function aliases, local closures and implementation value members remain.
Qualified declarations reuse existing member identities; declaration `where`
clauses preserve complete written parameter/result signatures. Tags, entries,
privacy, recursion and currying keep their checked behavior. Updated emitters
regenerate Pen bindings, codecs, behavior/dataflow and text/font/rock helpers.
Codec helper names are lowercase snake_case, including their callers. Assets,
numeric tables, packet order, ABI 8/session 2 and saved schema 26 are unchanged.

All **2,974 native laws compile without LLVM**. The development family passes
**17 native / 32 guest-host checks in 17.62s**; all 17 selected laws also pass
exhaustive allocation failures in **9.25s**. Host/tooling checks pass 39 laws
with one optional compiler-fixture skip; editor/generator/freshness checks pass.
Six named-function and eight stdlib executed-Wasm laws pass, as do both original
Gdev restoration tests across tiers and sync/JSPI. Existing stdlib and full Ink
codec emission gaps reproduce identically with original source overlays.

The complete frontend/API inventory covers **776 passes + six exact expected
rejections**, with zero unexpected failures. Standard-library coverage is 13
files; Ink is 322 + three; Gdev is 441 + three. Gdev's first 288 files use the
safe native compiler, its remaining 156 the fast native build. Both identities
and the unchanged source digest are pinned; this is not single-binary runtime
qualification. Batched imports reduce repeated auditing; failures bisect to
singletons, and interrupted batches remain unqualified.

The final full gate is **incomplete**: LLVM release compilation hit its 120s
phase cap and cancelled native execution. Actual Main hits its 30s cap with the
fast native-backend compiler; no fresh Wasm or PNG exists. Do not repeat long
release builds per edit. The pre-existing default release executable is an older
candidate; use the explicitly identified development compiler for these checks.
Full original-export, release and Main/frame qualification remain pending.
See [the exact batch evidence and compressed raw reports](benchmarks/evidence/qualification/2026-11-08-named-source-migration.json).

Goose mirrors the new parser/checker rules. Its parser engine passes, but no
whole compiler executable or semantic qualification exists. Preserve the
original pinned Zig oracle for old-language comparisons. The current repair
removes mixed-root importer callbacks, separates resolver/context/counter inputs,
and uses scalar owner/lease/generation keys for recursive proof storage. Both
store acquisitions retain all 9/21 header-identity guards. Error-only work records
keep borrowed inputs separate. A review audits 210 affected calls and 46 bodies.
The actual checker path has cleared the proof/resolver, sort-context and
diagnostic-transfer failures. Its latest selected-root diagnostic is the
source-validator AST traversal, then a scratch index at
`parse/source_operators.goose:100`; that
traversal/indexing family is now repaired. The combined five-root check hit
its 120.301s cap with no emitted error; that is incomplete. Split runtime,
semantic, lower and independent roots pass in 2.103/66.086/3.605/67.102s. The
checker root then exposed a pre-existing scratch wrapper index; it is fixed
and its family audited. A whole build, rather than another selected check,
hit120.262s with warnings only and no C/header. Measure this whole-entry cost
before repeating emission attempts. All 12 sort helpers and 11 comparator/swap contexts
now take fixed views by value, preserving charged comparison/swap order. The current source batch also
converts 100 immutable AST loops, removes 32 retained AST span aliases and copies
111 scalar metadata lookups rather than retaining optional map-entry references.
Readonly leased views pass by value; owning mutation/deinit references remain.
The adjacent source/global-reference family replaces another 21 AST loops
and 14 span aliases, preserving forward/reverse and prefix traversal order.
Six isolated production law families execute, including borrowed sort payloads
and shared counters, repeated store release/reuse, owner/generation rejection
and direct reified-view reads. Diagnostic transfer now canonicalizes owned
payloads and validates pool membership before deriving scalar run indices. These source
repairs remain under validation, not a completed checker or compiler pass.

The actual whole C/header build compiles all seven runtime/native objects in
about one second, then reaches its **120.323s emission cap without an error**.
No C program, header or executable was produced. Normal Goose checks unreached
nongeneric functions across the universal generated-adapter import closure;
separate worker entry files alone would not isolate that work. Measure the
checker before raising limits or making a broad process split. Private profiling identifies the real exported entry, rather than parsing or
global initialization, as the current cost. A 30-second stack sample observes
array reachability, TypeEq/reference root queries and branch flow snapshots.
The optional stable-closure candidate is `fdc59ab9...`; an array-specific gate
is qualified on controls, with no macro compilation win yet. Installed Goose
remains unchanged.
Current static source fixes still need whole executable qualification.

The native request transaction components pass normal and sanitizer batches:
forked candidates preserve the previous heap on explicit marked OOM, stage
bounded immutable replies, validate before adoption, detach inherited workers,
and wait for post-adoption cache publication. Cache staging mutates no external
files; publication runs through an allocation-free native hook after adoption.
The production server loop and C entry now integrate these APIs, but no compiler
runtime has executed them yet. A dedicated capability now carries token-bound allocation-failure markers
from copied stage processes. Native/sanitizer controls cover initialization,
execution and post-reply cleanup refusal, malformed markers, ordinary failures,
retained state/cache and retry in 7.5s. These tests use the real Goose allocator
with a fake C compiler entry; whole compiler integration remains unqualified. Scoped runtime observations report actual pool operation totals
and virtual region reservations; active payload, retained capacity and scratch
remain unavailable. Never substitute operation balance or RSS for liveness.
See [observer evidence](benchmarks/evidence/qualification/2026-11-08-goose-runtime-observer.json),
[supervisor/transport evidence](benchmarks/evidence/qualification/2026-11-09-goose-request-supervisor.json)
and [cache evidence](benchmarks/evidence/qualification/2026-11-09-goose-request-cache.json) and
[worker OOM evidence](benchmarks/evidence/qualification/2026-11-09-goose-worker-oom.json).

Whole builds cache native/runtime objects first, retain stage logs/timings,
stop three seconds after the first emission diagnostic, and share a 300s cap.
Do not repeat whole builds per small edit. Partial entry checks are diagnostic
coverage only. Astra is for a specific snag; never Terra.

Prior qualified controls, source repairs and rejected checker experiments remain
in [batched validation](benchmarks/evidence/qualification/2026-11-08-goose-batched-validation.json)
and [the pinned handoff](https://github.com/mewhhaha/blot2/blob/22003c1b937c63e8dfdea723c6807e834060b1f7/CONTINUE.md).
Those receipts qualify their exact earlier source/tool identities.
Current source repair scope and pending runtime work are pinned in
[the completion frontier](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).

Main shrinks **10,038,987 → 9,203,613B** (8.3%). Three fresh paired compilations
measure **5.768 → 5.523s**; paired deltas are **-1277ms, +38ms, +94ms**. There
is **no reliable compilation gain**. Final local-index ordering preserves
instruction order/count and local types, placing frequent operands below ULEB
width thresholds. The creation-backed wide-record prototype grew Main 357,722B
and was removed after a bounded rescue. The 20%-size/10%-compilation target was
not met.

Release compiler SHA256:
`7c8027242749ccc1027c6d855a7bd91f7cba72f27a39df307e36ea29aace3ac8`. All **2,965
native laws compile without LLVM**. The affected family passes **20 native /60
guests in 29.86s**, including a separate full allocation-failure run of all 20
selected native laws. Affected final release guests and four packaged/public API
laws pass. A fresh inspected NVIDIA Pen frame passes under original budgets and
matches the prior PNG. The full gate hit its 180s cap after 103 native passes
and 73 completed full sweeps, without an emitted failing law. **Full
qualification remains pending.**

Memoized `~` parameters/types and `@demand`/`@force` remain removed. `and`/`or`
short-circuit as primitives; other deferred work uses ordinary Unit callbacks
and explicit local sharing. Typed Code retains its effects through an ordinary
Unit-to-Unit carrier. Declaration/field-demand analysis and resource journal
demand events remain separate concepts. See
[deferred work](docs/compiler/DEFERRED_WORK.md).

`List T` and `[]` remain. The
[packed-sequence pilot](docs/compiler/PACKED_SEQUENCES.md) keeps immutable
construction/concat/cursors separate from indexable mutable Arrays. Its
standalone witness encodes 260,000 bytes against 1,200,000 modeled fixed-union
bytes, reserving 900,000 bytes; five tests pass. It is not production List
emission or a measured Blot runtime/Wasm/compile-time gain. Contiguous concat
copies O(total bytes); repeated concat needs linear builder construction or
separately qualified chunks.

The
[pinned preceding handoff](https://github.com/mewhhaha/blot2/blob/aa8a1268501b092c2ad52a68ddf6a1fbdf884128/CONTINUE.md)
retains feature-retirement qualification, known baseline failures, earlier
array-loop gains/regressions and exact profiling identities. They qualify their
named candidates, not this release. Broader gameplay/software-adapter checks and
Pen's source bridge inferenceBudget remain open. Sibling source/assets are
unchanged by this checkpoint.

## Next representation levers

Keep measuring the remaining sort costs against the unchanged Goose kernels.
Creation receipts and guarded lanes now remove substantial repeated validation
and loop overhead. Preserve aliases, exact primitive selection and trap-prefix
behavior rather than weakening authority checks.

Integrate one bounded packed List element plan into the owned backend: dense tag
plus active payload, append/freeze, byte-position/count cursors and one terminal
nested scalar tail. Preserve owner lifetime evidence, complete append checks,
exact scalar bits and original budgets. Measure scalar controls, live versus
reserved bytes, bytes copied, construction/traversal time and emitted Wasm. Keep
production status explicit until executed Blot witnesses pass.

For Main, avoid emitting unnecessary transport while preserving canonical leaf
identity, field demand and result-alias proofs. The rejected all-leaves-lazy
record prototype added 41,582 loads and lost descriptor SSA reuse. Do not revive
it as a broad heap-record default. Local ordering removes encoded index bytes;
it does not remove the underlying operations. Final Main still has 3,795,220
instructions, including 2,100,876 local operations occupying 4,721,802B. Even a
one-byte opcode floor exceeds 3.79MB; reaching 1–2MB requires fewer operations.
Static zero-only-local cleanup has about 108kB potential in the old artifact and
remains unimplemented/unmeasured. The broader aggregate representation still
needs operation/shape attribution.

An older exact-artifact profile, before this candidate, records backend 4.430s,
checking 0.500s, lowering 0.124s, validation 0.102s, cumulative backend
allocation requests 5.324GB and process RSS 1,110,332KiB. Requested bytes are
not peak memory; overlapping timing families do not add. Scoped backend engine
subtimers remain unavailable.

Use the private checked-IR capture/replay for short backend iterations:

```sh
deno run -A benchmarks/tools/capture_outline.ts --output build/bench/outline-capture
(cd compiler && zig build bench-outline -Doptimize=fast -Dllvm=false --prefix zig-out-native-dev)
compiler/zig-out-native-dev/bin/blot-outline-replay build/bench/outline-capture verify
```

Capture a fresh pinned artifact. Replay builds in about 0.5s and finalizes in
about 3s; it is engine evidence, not arbitrary-IR or whole-runtime authority.
Small controls do not predict Main. Hash lane batching and dominated bounds/load
elimination remain separate runtime hills; preserve prefix effects before traps.

## Contracts and remaining qualification

Preserve guest ABI 8, session protocol 2, saved schema 26 and packet ordering.
Named persistent pools, invocation-local owners, borrow lifetimes, explicit
copies and the original 2MiB temporary/256KiB persistent/2MiB
transport/4096-slot budgets remain. FrameAccess uses complete-source payload
slicing. Hand transactions retain isolation, resource scopes and ordered
updates. Snapshot restore is explicit; retries must not advance twice. Language
tasks remain retired; copied-packet host workers remain.

The owned-storage rewrite and ordinary legacy-backend retirement are unfinished;
[tasks 110–121](tasks/STORAGE_REWRITE.md) retain their requirements. Original
exports, nonfunction/global export support, block-break inference, broader
library/game/save/recovery/browser qualification and `#run` build effects remain
pending. A successful first frame or source inventory does not complete them.
The [repository map](docs/README.md) records the current layout. Historical
2.08MB recovery, held experiments and earlier requirements remain in pinned
history; documentation cleanup is not completion.

## Iteration and delivery

Use Zig 0.17.0 and `-Dllvm=false` for development/native tests. The current
development family takes 29.86s including complete native compilation; one final
LLVM release takes about five minutes. Compiler-only native rebuilds take 8–11s.
Use `deno task build:compiler:dev --fixtures= --jobs=2` for a compiler-only
iteration, then the affected regression family. Keep source frozen before the
final LLVM build.

Use `deno task check:dev --area array-engines` for the current regression family
and `deno task test:compiler` before compiler commits. Full qualification is
separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing siblings; no new worktrees. Commit/push coherent
checked batches to main and verify the remote. Environment publication and
upstream comments require explicit requests.

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

Index 411 passes the 201 frontend / 8 runtime / 7 focused / 12 emitted-C controls and eight store controls,
24,576 event-state/order and 49,152 query comparisons plus ASan/UBSan. Its
107.649s run reaches scalarArgumentPossible immutable child-loop borrowing
where 409 capped with no diagnostic. All-relevant synthetic replay costs 2.15x;
retain that limitation and measure future dense cases. No completed compiler
speed or whole-runtime result. Recipe reconstructs all 108 source files exactly.

412 reloads scalar AST child IDs in scalarArgumentPossible while preserving
full initial validation, iteration order, depth and false/error exits. Exact
source review passes. Its 107.049s run reaches operationValue readonly Option
overload mismatch; no C/header/executable.
