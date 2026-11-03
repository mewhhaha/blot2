# Continue the owned-storage rewrite

## Current frontier

**Gdev Wasm size is the current priority**, with short iterations and the
subsecond compilation goal retained; the next latency gate is below five
seconds. The throughput target is a fresh, reachable 50k source lines in 0.5
seconds (100k lines/second), then one million lines/second. Use
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

Fresh
[binary inspection](zig-native/measurements/gdev-size-forensics-2026-11-03.json)
accounts for the complete current artifact: 15.81MB is code, 341kB global
declarations and 50kB data. Local/global instructions alone occupy 11.32MB
(69.8%). There are 462,178 locals and 68,201 mutable globals. Only four
functions with 59 total body bytes are unreachable; byte-identical bodies
account for at most 406kB before index rewriting. Assets, debug names and dead
functions do not explain the size.

The output contains 43,468 exact local self-copy pairs using 254,472B. Final
local compaction reuses slots without deleting instructions, and no cleanup runs
after it. Another 325,398 zero/local-set pairs occupy 1.58MB, but physical slots
are reused: most cannot be called dead Unit values from this census. The
outliner creates 462 helpers and 67,833 bank globals. Main resets those bank
slots in one 390,988B run, preserving function-entry zero semantics on repeated
calls. The bank amplifies eager value/carrier materialization; it is not the
whole cause.

A bounded Binaryen 133 diagnostic (`simplify-locals`, `vacuum`, `dce`) shrinks
the same Wasm to 13,544,604B in 2.84s. It removes 2.35MB of local instruction
traffic while retaining all function/local/global declaration counts and
unchanged load/store bytes. The existing World witness also shrinks and passes
all seven checks in sync/async modes. Main is engine-validated only. These are
private optimizer outputs; the installed compiler still emits 16,220,693B.
Adding that postprocessing cost to the edit loop is not the intended fix.

Astra's review favors a bounded data-stack cleanup after final local compaction:
delete exact self-copy pairs and fold adjacent set/get pairs to tee, respecting
hidden ownership/resource coordinates. Then measure residual transport before
choosing a larger Value/phi IR or aggregate ABI rewrite. Preserve semantic
arguments, effects, owners, variants, loops and default-zero behavior. Use
`scripts/bench/wasm_size.py` and the SHA-matched `wasm_transfers.py` companion
to compare the complete emitted result; pattern byte totals overlap and are not
removable-byte promises. There is no measured path to 1–2MB yet.

Earlier identity-join and immutable-survivor fixes remain installed. Neutral
field masks, narrow direct-tail markers and unused-local pruning remain held;
requirements, controls and raw evidence are retained in the
[preceding frontier](https://github.com/mewhhaha/blot2/blob/8ed0781c4c623c1d8d47b47fff1f2edaebd9a9a0/CONTINUE.md)
and linked measurements. Remaining-use counts are not a dead-binding proof.

The separate release profile takes 6.13s: backend 5.12s, checking 0.53s,
validation 0.11s. Borrow/owner-graph traversal and metadata copying remain the
latency follow-up from a bounded weighted stack sample; size inspection does not
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
