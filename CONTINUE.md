# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
Sub-five-second Main, subsecond compilation and 1–2MB Wasm remain unmet.
Reachable throughput targets are 50k source lines in 0.5s, then one million
lines/second.

The
[checked merge checkpoint](benchmarks/goose/results/2026-11-04-merge-select.md)
improves unchanged merge sort **230.88 → 157.72ms (1.466x)** across five release
pairs. The fresh Goose gap narrows **1.97x → 1.36x**. A bounded Core proof emits
two checked loads, select/store and Boolean cursor increments after ordinary
semantic/owner/backedge checking. All per-access bounds and lazy validation
remain. Aliases, ties, skipped accesses, wrapping and trap prefixes execute in
both tiers and sync/async modes. Merge Wasm shrinks **6,991 → 6,810B**; the
other six adapted benchmark Wasms are byte-identical. README runtime charts
refresh merge only; cold-compilation and other exact-artifact observations
retain their pinned preceding survey.

Current release compiler SHA256:
`105f0e18734b8eeb7fa53801087f069a8d4591d325f26eea6c4f0416538cecbf`. All **2,953
native laws compile without LLVM**. The affected development family passes **8
native / 28 guests in 9.36s**; four new laws pass full-fault mode, and all 28
affected release guests and four public-package API laws pass. The full gate
passes smoke/harness, runtime fixtures and native compilation, then the native
runner exits 130 after 83 passes/50 full allocation sweeps, without an emitted
failing law. Cancellation occurs before the 180s cap; its cause is not
established. **Full qualification remains pending.** Main has zero merge matches
and is byte-identical at 10,049,963B; three fresh uncached pairs measure **5.271
→ 5.279s**, changes -8/-73/+19ms, with no material compile-time gain. A fresh
inspected NVIDIA frame matches the preceding PNG/trace under original budgets.
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

For merge, measure complete-range bounds reuse and per-call owner validation.
The checked select change narrows the gap; their exclusive CPU costs remain
unmeasured. Keep source-source-destination order, valid-prefix effects, aliases
and all fallback behavior while testing those separate levers.

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
development family takes 9.36s after cache repair; one final LLVM release takes
about five minutes. Use `deno task build:compiler:dev --fixtures= --jobs=2` for
a compiler-only iteration, then the affected regression family. Keep source
frozen before the final LLVM build.

A Btrfs metadata stall inflated one rebuild to about two minutes with about 20
CPU seconds. Only older disposable compiler objects were pruned. Zig's stale
empty-input manifests then needed invalidation to regenerate removed options
normally; compiled-object manifests, installed binaries, source/assets and raw
evidence were preserved. See the checkpoint for the exact cache inventory.

Use `deno task check:dev --area merge-loops` for the current regression family
and `deno task test:compiler` before compiler commits. Full qualification is
separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing siblings; no new worktrees. Commit/push coherent
checked batches to main and verify the remote. Environment publication and
upstream comments require explicit requests.
