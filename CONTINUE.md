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

The latest release produces **16,392,014 bytes of Wasm**, down from 16,677,822
(285,808B / 1.7% smaller). A matched fresh pair takes **6.13s → 5.97s**; the
configured launcher takes **5.64s** with identical compiler identity and full
Wasm hash. These are individual cache-disabled completions under shared-host
load, not a timing distribution. The five-second and subsecond targets remain
unmet. Exact pins and qualification are in
[the current evidence](zig-native/measurements/immutable-survivors-2026-11-03.json).
Release source is `6d853b51` plus patch `e108f3d4ccef`.

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

All 2,872 native laws compile; all 67 affected laws pass full allocation faults
(31 sweeps), 94 guest tests pass with the final LLVM compiler, and Zig lint is
clean. A strengthened fallback rerun executes 120 assertions, combining an
otherwise eligible match with active scalar-address code. The broader family
retains 187 passes and the same 15 failure names after generating two missing
private runtime fixtures. The required full gate retains 48 passes/one baseline
List/chunk failure. Final LLVM passes seven world/editor, 160 hand and seven
identical renderer checks. Installed Pen still rejects ABI 8; no new frame/PNG
is qualified. The configured launcher selects `zig-native/zig-out/bin/blotc`.

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
The current artifact still has 11.41MB of local/global instructions, 68,686
mutable spill globals and 454,492 declared locals. Private field masks remain
held after neutral real-menu results; explicit callback capture narrowing saved
only 116kB. The direct-tail-return pilot saves 969B in World and 110B in menu,
and remains held. Ordinary statement returns can sit inside a synthetic
completion operand, beyond that narrow tail marker.

A bounded copy-site diagnostic counts actual emitted transfer operations, with
argument pushes separate from copies and buffer traffic. World completes with
identical baseline Wasm. Main prefixes stop at 30 seconds and include discarded
planning trials; they are not full-output or CPU attribution. The exact coarse
407,440-instruction prefix has 91,254 callee packed argument-load instructions,
56,446 continuation assignments and 23,780 Control.result assignments. The
per-source table saturates; the coarse call-site totals do not. Raw pins and
limits are preserved in the current evidence. Do not repeat unchanged capped
runs.

The next private pilot makes packed function inputs lazy at the completed-plan
boundary. Reserve logical input locals using the existing Value layout; inspect
the fully checked helper IR after result serialization/cleanup; load only
demanded input words at entry and omit their unused caller stores. Keep complete
semantic arguments, owner/read/effect checks, evaluation order, packet offsets
and result serialization. Direct-word calls remain unchanged. This composes
physical demand through calls without another source-footprint cache. It is not
implemented in the installed release. Remaining-use counts are not a
dead-binding proof: the current traversal misses alternative-row multiplicity
and some pattern/fallback reads.

A separate new profile takes 5.68s: backend 4.71s, checking 0.51s, validation
0.10s. Backend type/key preparation remains a major unresolved latency cost;
static traffic proportions and rolled-back expression counts are not CPU shares.

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
