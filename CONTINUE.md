# Continue the Goose compiler completion

## Current frontier

Current user priority: repair Goose lifetimes in coherent families, build the
actual native compiler, then qualify recoverable OOM/retention and differential
behavior against Zig. Verify at family boundaries, keeping repair stages at 120s and whole builds at 300s. Final emission may
use a 180s stage after engine-family checks. Source-only progress and native component tests are not executable
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

Goose mirrors the new parser/checker rules, but **no whole compiler executable
exists yet**. Keep the original Zig oracle for old-language comparisons.
The current user scope is lifetime repair, actual native compilation, then
CLI/server, retained state and recoverable request OOM qualification. Use
coherent source batches and bounded checks; source presence is not completion.

Sixteen executed production families pass together. They cover diagnostic and
body ownership, live/frozen readers, imports, SourceValidation, frames, native
assets, completion snapshots, loader scheduling and editor budgets. These laws
check real helpers in seconds; they do not qualify a whole compiler executable.

Project checker engines and worker headers are now invocation-local. Synchronous
callback contexts borrow the local engine, so caller-owned compiled modules,
reuse masks, execution observers and editor budgets need no global retention.
The engine registry and temporary editor-prefix copy/writeback machinery are
removed. Worker requests own their engine value and clean it before source and
packet ownership. Nonempty compiled/mask views and callback/worker lifetimes
have executed controls; the full entry remains pending.

Live Source/Patterns keep existing lease/generation checks and all 49/2 alias
guards. Frozen readers carry fixed descriptors and value proof headers without
copying graphs. Import dictionaries hold scalar indices into an invocation-owned
arena; append-only caller tables use grow-only storage. SourceValidation publishes
19 registered views without extra allocation. Loader and scheduling scratch use
fixed pooled headers; diagnostic/item moves use checked whole-run observations.
NativeAssets sorts scalar indices and owns generated error codes after producer
cleanup. Its final Source ownership scan can still be quadratic; optimization
requires a measured workload.

Source and semantic diagnostics now publish through checked owning views, and
worker clones preserve their payload ownership. All seven CheckedProject outer
runs escape the local engine through validated typed views. One tagged-union
portable flag now mutates its owning payload; the next batched entry check is
pending. Executor and metadata checks have passed their previous boundaries.
There is still no emitted whole C program, header or executable. Actual
CLI/server, request OOM/retry and differential qualification remain pending.

Private checker tooling is checkpointed separately. Its holder index reaches the
same diagnostic in 82.445s versus 104.824s on identical inputs in one pair; this
is not a complete compilation ratio. The frame guard passes 147 laws in each
debug/release mode, 24 semantic controls and six C parity cases. Full emission
reaches concrete CLI/server errors in 130–135s; installed Goose remains unchanged.
See the [tool evidence](benchmarks/evidence/qualification/2026-11-09-goose-used-after-frames.json).

Native request supervisor/transport/cache/observer components pass normal and
sanitizer controls using the real runtime with a fake compiler entry. Candidate
heaps and cache writes remain staged until reply adoption. A token-bound
stage-worker capability covers allocation refusal during initialization,
execution and cleanup. Integrated compiler coverage is pending. Active payload,
retained capacity and scratch counts are unavailable; operation totals and
virtual reservations are not liveness. See [worker OOM evidence](benchmarks/evidence/qualification/2026-11-09-goose-worker-oom.json).

The qualification runner has eight oracle baseline passes plus an unsupported
ABI 8 recursion witness. No ABI 2 fallback or invented zero memory counts.
Repair checks cap at 120s; final emission may use 180s after entry checks, within
a shared 300s build limit. Builds stop 3s after the first diagnostic. Selected
roots pin input/compiler identities and reject source drift. The required Zig
gate passed smoke/harness and compiled all 2,974 laws without LLVM; its LLVM
phase hit 120s and cancelled execution after 94 laws/65 full sweeps. Full
qualification remains incomplete. Zig lint has zero findings. Astra reviews
specific architectural snags; never Terra.

Current identities, source repairs, raw qualification receipts and unqualified
scope are pinned in [the completion frontier](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).
Earlier exact-candidate evidence remains in
[batched validation](benchmarks/evidence/qualification/2026-11-08-goose-batched-validation.json)
and the [pinned handoff](https://github.com/mewhhaha/blot2/blob/22003c1b937c63e8dfdea723c6807e834060b1f7/CONTINUE.md).

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
completed speed claim. Measurement 410 (same 120s cap) reads five valid ABI 2 snapshots and reaps in
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
