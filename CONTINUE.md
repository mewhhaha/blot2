# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**, with
the next gate below five seconds. The throughput target is a fresh, reachable
50k source lines in 0.5 seconds (100k lines/second), then one million
lines/second. Use
`deno run -A scripts/bench/compiler_throughput.ts --compiler PATH --lines 50000`;
it reports exact lines, bytes, estimated tokens, emitted work, Wasm size and
executed checks. Generation and cold compilation remain visible; `--profile` is
a separate diagnostic run. The million-lines/second target remains unmet. Game
diagnostics default to five seconds and have a hard 30-second iteration cap.
Never repeat the recorded 36-minute build or an unchanged five-minute
diagnostic.

The latest release produces **16,220,693 bytes of Wasm**, down from 16,392,014
(171,321B / 1.05% smaller). A matched fresh pair takes **6.204s → 6.177s**; the
configured launcher takes **6.100s** with identical compiler identity and full
Wasm hash. These individual cache-disabled completions under shared-host load
show no meaningful latency gain. The five-second and subsecond targets remain
unmet. Exact pins and qualification are in
[the current evidence](zig-native/measurements/lazy-packed-inputs-2026-11-03.json).
Release source is `b0be28fb` plus source snapshot `6e4e71f237cf`; the complete
patch and per-file hashes are pinned separately. The installed LLVM binary is
`638f0b453da644a2d5cb7acc6239463e4e77c9172564e38309febe29d9ff1c22`.

Packed helper inputs now reserve logical input locals in the existing Value
layout. After complete body checking, result serialization and cleanup, the
backend loads only words read by the finished IR and omits their unused caller
stores. Main avoids 7,392 input-word loads and 11,088 argument-word stores; the
World witness shrinks 10%. Semantic arguments, owner/read/effect admission,
evaluation order, full packet offsets and output serialization remain intact.
Direct-word calls retain their ABI. This uses the existing value tree rather
than adding another representation or source-footprint cache.

Statement-match arms with a single pattern row now retain immutable Binding
metadata instead of copying every introduced value into a carrier. Only a sole
continuing arm publishes it. Explicit SSA merges, multi-row arms and scalar
addresses keep their existing paths. Main avoids 3,488 binding copies, including
copies from arms whose bindings would later be discarded. No new value graph,
instruction relocation or semantic proof cache was added.

One completed named-function plan replaces the scalar/inline/Reader/writer probe
cascade. Full source/type witnesses precede physical projection; plans retain
the ABI, result layout and ordered actual owner events. Unused arguments no
longer invent reads. Input-owner array/view aliases retain their real roots;
fresh owners fall back. Export roots keep outlining, oversized helpers roll
back, and trapping helpers retain declared result layouts. Closures still use
their separate path. This is a function-contract boundary, not a completed
monomorphic expression IR.

All 2,878 native laws compile; all 72 affected laws pass full allocation faults
(33 sweeps), 96 guest tests pass with the final LLVM compiler, and Zig lint is
clean. New witnesses cover wide forwarding beyond the 512-word direct ABI,
variant/descriptor results, reads after nested packed calls, repeated plan hits
and observable unused-argument effects. The broader family retains 187 passes
and the same 15 failure names with its required runtime fixtures. The required
full gate retains 48 passes/one baseline List/chunk failure. Final LLVM passes
seven world/editor, 160 hand and seven identical renderer checks. Installed Pen
still rejects ABI 8; no new frame/PNG is qualified. The configured launcher
selects `zig-native/zig-out/bin/blotc` with the exact measured identity and
Wasm.

The preceding size census found 16.31MB (75.6% of the module) in local/global
instruction traffic. A tiny real-menu conditional copied roughly 10k unchanged
captured words: the backend rejected callback-bearing aggregates even when both
branches proved the exact same dominating value. Removing that redundant shape
restriction saves 4.90MB in the full game. Scalar-address fallback and all
owner, read, type and variant checks remain. Mutable spill globals fall from
110,266 to 68,879 and declared locals from 778,621 to 455,933. An older
full-game capture is 2,076,028B (1.98MiB), with different source/config/memory
model. Exact duplicate bodies account for only 427kB. See
[size diagnosis](zig-native/measurements/gdev-code-size-diagnosis-2026-11-02.json).
The current artifact still has 11.32MB of local/global instructions (69.8% of
the module), 68,201 mutable spill globals and 462,178 declared locals. Private
field masks remain held after neutral real-menu results; explicit callback
capture narrowing saved only 116kB. The direct-tail-return pilot saves 969B in
World and 110B in menu, and remains held. Ordinary statement returns can sit
inside a synthetic completion operand, beyond that narrow tail marker.

A bounded copy-site diagnostic counts actual emitted transfer operations, with
argument pushes separate from copies and buffer traffic. World completes with
identical baseline Wasm. Main prefixes stop at 30 seconds and include discarded
planning trials; they are not full-output or CPU attribution. The exact coarse
407,440-instruction prefix has 91,254 callee packed argument-load instructions,
56,446 continuation assignments and 23,780 Control.result assignments. The
per-source table saturates; the coarse call-site totals do not. Raw pins and
limits are preserved in the
[preceding evidence](zig-native/measurements/immutable-survivors-2026-11-03.json).
Do not repeat unchanged capped runs.

A follow-up compactor prototype drops only locals with no get/set/tee mentions.
It passes 80 affected native laws with full faults and the packed guest witness,
but saves only 1,073B (0.18%) in World. It remains held; no additional LLVM
build was spent on it. Remaining-use counts are not a dead-binding proof: the
current traversal misses alternative-row multiplicity and some pattern/fallback
reads.

A separate release profile takes 6.13s: backend 5.12s, checking 0.53s,
validation 0.11s. One bounded 94-stop stack sample, weighted by per-thread CPU
deltas, points toward borrow/owner-graph traversal and metadata copying as the
next latency work. memcpy/memset appears in approximately 18.3% of that weighted
sample; allocator paths appear in 8.5%. These overlapping endpoint-stack
attributions are approximate, not a timing distribution or exact CPU shares.
Prefer reducing repeated value/type/owner traversal and copying before another
instruction-count pass. Static traffic and rolled-back expression counts do not
establish CPU cost.

The reachable primitive benchmark compiles 50,025 lines in 16 modules in
0.480–0.491s, plus 0.026s generation, producing 973,511B Wasm with all three
checks passing. The old compiler already takes 0.470s on the same workload; this
is a throughput control, not a general speedup. A single-module 50k control hits
the existing 100k-node pool-discovery cap; the benchmark preserves that failure.
Gdev's rich backend work remains the main latency lever.

The language simplification direction is one `#run` evaluator for ordinary
checked build functions with tracked `readFile`/`publishModule` effects and
normally parsed/checked generated modules. Current `#run` remains pure; this
build-stage capability is not implemented. It is separate from the measured
runtime backend bottleneck. Hot Gdev callbacks already have explicit interfaces;
this batch makes no library/game API changes or feature cuts.

## Contracts and remaining qualification

Preserve ABI 8, session protocol 2 and saved schema 26. Work in the existing
Ink/Gdev/Pen siblings; this batch leaves their source and assets unchanged.
FrameAccess remains fixed nominal data with complete-source payload slicing.
Hand transactions retain isolation, resource scopes and ordered updates.

Original `elements_game` still has the preceding emit-layout gap; the seven
world/editor checks do not replace those assertions or a full-game frame.
Installed Pen's config parser/generator are also older than the checkpointed
inputs. Preserve generated bindings. The latest reused-Wasm frame attempt is
pinned in the current evidence and fails before rendering on ABI 8.

The held canonical-store, query-ledger, outliner-preview, direct Salt/Rock,
constant/lambda and CPU-target experiments remain held. No neutral private patch
was copied into the compiler or siblings. Their exact requirements, controls,
raw references and decisions are retained in
[the preceding checkpoint](https://github.com/mewhhaha/blot2/blob/cd02242bed03c2507d78731d37887fe94044118e/CONTINUE.md)
and its linked measurements; do not reuse preliminary/censored figures.

Use `deno task check:dev --area type-effects` for affected development work and
`deno task test:compiler` before compiler commits. Development/native test
builds use Zig 0.17.0 without LLVM. Reserve `deno task build:compiler` for a
meaningful release candidate, then run the tracked
`scripts/storage_handoff/build_gdev.ts` and `run_pen.py` runners. Game builds
retain their 30-second cap; profile in a separate run. Frozen candidates use
plain archives, exact source/binary hashes and the existing sibling workloads,
never extra worktrees.
