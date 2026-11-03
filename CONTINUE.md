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

The latest release produces **15,535,572 bytes of Wasm**, down from 16,220,693
(685,121B / 4.22% smaller). A matched fresh pair takes **5.652s → 5.636s**; the
configured launcher takes **5.702s** with identical compiler identity and full
Wasm hash. Individual cache-disabled completions under shared-host load show no
meaningful latency gain. The five-second, subsecond and 1–2MB targets remain
unmet. Exact pins and qualification are in
[the current evidence](zig-native/measurements/transport-cleanup-2026-11-03.json).
Release source is `4c6a253b` plus complete patch `3c99042261da`; all five
changed implementation/test files match the frozen candidate. The installed LLVM
binary is `05b05beef0cc7fc5c323296db7494fd665747aca2a1cb336440a259e9eae4249`.

Final data-stack bodies now remove same-local get/set pairs and fold set/get
pairs to tee after local compaction. The complete output has no local self-copy
or adjacent set/get readback pairs, down from 43,468 and 160,011 respectively.
It gains 153,111 tee instructions; overlapping pair counts are not additive.
Original module bodies and semantic/table coordinates stay immutable. Packed
flags and hidden ownership/resource markers retain conservative handling;
diagnostic origins do not select the optimization. Global banks, call
conventions, semantic/effect checks and default-zero behavior stay intact.

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

All 2,884 native laws compile; all 116 selected laws pass full allocation faults
(47 sweeps), including the new compaction/transport/metadata/typed-local laws.
The final LLVM guest family has 102 passes and two unsupported legacy
memory-profile cases; both failures reproduce with the preceding frozen LLVM
compiler. Zig lint is clean. The required full gate retains 48 passes/one
baseline List/chunk failure, so full qualification remains pending. Final LLVM
passes seven world/editor, 160 hand and seven identical renderer checks. World
shrinks 588,596 → 563,087B; hand 227,033 → 221,408B; renderer 110,675 →
106,804B. Installed Pen still rejects ABI 8 before rendering; no new frame/PNG
is qualified. The configured launcher selects the exact measured release.

The current artifact has 15.13MB of code, 341kB of global declarations and 50kB
of data. Local/global instructions occupy 10.63MB (68.45%). There are still
462,178 locals and 68,201 mutable globals. The outliner's 67,833 banked globals
and 390,988B root reset run stay unchanged. Only four functions with 59 total
body bytes are unreachable. Byte counts describe static encodings, not runtime
cost or removable work.

The **2,076,028B historical predecessor was recovered exactly**, with its
original SHA, using the preserved compiler and source in one 30-second-capped
replay (2.88s). All 578 input pins match before and after. Its local/global
instructions occupy 1,000,142B and it has 29 mutable globals. Against the
preceding 16.22MB artifact, local/global growth accounts for 73% of total byte
growth; embedded data shrank. Source bytes grew about 2×, but these snapshots
differ in source, APIs, configuration and memory model, so that category delta
is not a controlled compiler-only attribution.

Historical aggregate construction stored fields in a heap object and returned
one pointer. Current `temporary`/`assignTransport` recursively materialize and
copy Value leaves, including explicit owner/borrow metadata. Some resulting
instructions are necessary for the current representation; preserving ownership
does not require redundant or eager copies of every unchanged aggregate lane.
Current closure admission remains its own path. The next larger pilot should
preserve immutable word/immediate references and materialize only genuinely
differing merge/result lanes, within existing Value/Core semantics. Keep
complete type, owner, read, variant, loop/backedge and invocation-zero checks.

The earlier bounded Binaryen diagnostic shrank the preceding 16.22MB artifact to
13.54MB in 2.84s. Its broader simplification is not installed and its savings
cannot be added to this batch. Use `scripts/bench/wasm_size.py` and the
SHA-matched `wasm_transfers.py` companion to measure complete output; most of
the 1.58MB zero/local-set category is not trivially dead. Another full IR or
aggregate ABI rewrite needs evidence from the remaining large transfers.

Earlier identity-join, immutable-survivor and packed-input fixes remain
installed. Neutral field masks, narrow direct-tail markers and unused-local
pruning remain held; requirements, controls and raw evidence are retained in the
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
