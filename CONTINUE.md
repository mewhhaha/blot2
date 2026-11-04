# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
Sub-five-second Main, subsecond compilation and 1–2MB Wasm remain unmet.
Reachable throughput targets are 50k source lines in 0.5s, then one million
lines/second.

The
[guarded merge checkpoint](benchmarks/goose/results/2026-11-04-merge-ranges.md)
improves unchanged merge another **156.70 → 137.19ms (1.145x)** across five
release pairs. The fresh Goose gap is **1.19x**. Complete-range guards admit
private pointer iteration for longer merges; declined guards retain the exact
checked loop. Fresh loads preserve aliases/ties, and actual scalar cursor values
are restored at exit. A bounded independent scalar replacement proof also omits
unused destination loads, retaining address/owner/bounds checks and live
borrows. Merge Wasm grows **6,810 → 7,196B**. All seven benchmark pairs are
freshly measured; quicksort is effectively unchanged, custom hash improves about
5%, and Mandelbrot is effectively unchanged with a slightly higher median.

Current release compiler SHA256:
`a18ced7646f5237d49f508ffdee850a0eed8490ee04944e3ec8c8f6e39da8745`. All **2,954
native laws compile without LLVM**. The affected development family passes **10
native / 32 guests in 37.56s**; four focused native laws pass full fault mode,
all 32 affected release guests and four public-package API laws pass. The full
gate reaches its 180s budget during native execution after 90 passes / 63
complete full allocation sweeps, without an emitted failing law. **Full
qualification remains pending.** Main has zero merge matches and 1,425 static
old-load omissions; those counters are not exact encoded-instruction counts.
Main saves **10,976B** to **10,038,987B**. Three fresh uncached pairs measure
**5.362 → 5.306s**, changes **+14/-107/-33ms**: no material compilation gain. A
fresh inspected NVIDIA frame matches the preceding PNG under original budgets.
See the checkpoint for exact pins, diagnostic controls and limits.

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

For merge, measure per-call owner validation and recursive descriptor/call
setup. The range/pointer path narrows the gap; remaining exclusive costs are
unmeasured. Consider validated internal borrowed descriptors only where the
existing recursive source proof establishes stable owners, no callbacks and no
invalidating effects. Keep checks at authority boundaries, valid-prefix effects,
aliases and exact fallback behavior.

Integrate one bounded packed List element plan into the owned backend: dense tag
plus active payload, append/freeze, byte-position/count cursors and one terminal
nested scalar tail. Preserve owner lifetime evidence, complete append checks,
exact scalar bits and original budgets. Measure scalar controls, live versus
reserved bytes, bytes copied, construction/traversal time and emitted Wasm. Keep
production status explicit until executed Blot witnesses pass.

For Main, attribute materialization by record shape and operation before
changing representation: construction, call, result, join, loop and row load.
Compare creation-backed immutable `world_storage.FrameAccess` with borrowed
private pointers/lazy field loads against shared semantic shapes and transitive
field demand. Keep backing through helpers/branches/loops and small math records
inline. Target roughly 20% fewer Main bytes or 10% less compile time while
retaining snapshots, checked authority and budgets; reject designs that replace
stores and loads with equivalent work.

The preceding exact-artifact profile records backend 4.430s, checking 0.500s,
lowering 0.124s, validation 0.102s, cumulative backend allocation requests
5.324GB and process RSS 1,110,332KiB. Requested bytes are not peak memory;
overlapping timing families do not add. Scoped backend engine subtimers remain
unavailable.

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
development family takes 37.56s including complete native compilation; one final
LLVM release takes about six minutes. Compiler-only native rebuilds take 8–11s.
Use `deno task build:compiler:dev --fixtures= --jobs=2` for a compiler-only
iteration, then the affected regression family. Keep source frozen before the
final LLVM build.

Use `deno task check:dev --area merge-loops` for the current regression family
and `deno task test:compiler` before compiler commits. Full qualification is
separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing siblings; no new worktrees. Commit/push coherent
checked batches to main and verify the remote. Environment publication and
upstream comments require explicit requests.
