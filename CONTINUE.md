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

The latest release produces **14,332,601 bytes of Wasm**, down from 15,535,572
(1,202,971B / 7.74% smaller). A matched fresh pair takes **5.773s → 5.778s**;
the configured launcher takes **5.660s** with identical compiler identity and
full Wasm hash. No meaningful latency change is established. The five-second,
subsecond and 1–2MB targets remain unmet. Exact pins and qualification are in
[the current evidence](zig-native/measurements/aggregate-identity-2026-11-03.json).
Release source is `35aa2fde` plus complete patch `bc908f3c32fc`; the 15 frozen
implementation, test and contract files match the candidate. The installed LLVM
binary is `47a7c70efd802bd0ab9d24b21c2078d14854154d5aacc0fad433429fa4e860ad`.

Checked aggregate joins now preserve immutable physical words and materialize
only differing or non-dominating lanes. Mutable owner tokens, loop carriers,
demand caches and normal fallthrough retain capture storage. Tagged, host,
demand and unowned-reference subtrees keep ordinary transport while eligible
siblings share. Completed buffered helpers may return unchanged input words
without result stores or caller loads. Statement completions and static callable
placeholders share one unwritten default-zero local per function. Complete type,
owner, read, effect and variant checks remain. Main shares 48,699 join words,
avoids 3,060 result stores and 24,284 result loads, and shares 145,227 zero values.
Counts describe compiler work, not additive byte savings.

The first pilot shrank the output but regressed compilation to 10.470s.
A bounded stack sample attributed 46.3% of sampled emission CPU to rebuilding
all historical mutable-local sets at every join. The final implementation indexes
mutable origins once per function. Full Main and World Wasm hashes remain
identical after that bookkeeping fix; the final matched pair restores baseline
latency. The rejected candidate and diagnostic evidence remain pinned.

The preceding final transport cleanup still removes same-local get/set pairs
and folds set/get to tee after local compaction. Original module bodies and
semantic/table coordinates remain immutable; neutral reservation nops disappear
only during final assembly. Hidden ownership/resource markers and flagged table
operands retain conservative handling. See
[the preceding evidence](zig-native/measurements/transport-cleanup-2026-11-03.json)
for its exact baseline and byte accounting.

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

All 2,899 native laws compile; 131 selected laws pass full allocation faults
(52 sweeps), including deferred joins, helper result aliases, zero-source
rollback and demand caches. The final LLVM guest family has 108 passes and the
two unchanged unsupported legacy memory-profile cases; both reproduce with the
preceding frozen LLVM compiler. Zig lint is clean. The required full gate still
stops at 48 passes/one baseline List/chunk failure, so full qualification remains
pending. Final LLVM passes seven world/editor, 160 hand and seven identical
renderer checks. World shrinks 563,087 → 529,248B; hand 221,408 → 210,126B;
renderer 106,804 → 100,146B. Installed Pen still rejects ABI 8 before rendering;
no new frame/PNG is qualified. The configured launcher selects the exact release.

The current artifact has 424,255 declared locals and 64,963 mutable globals.
Local/global instructions still occupy 9,829,600B (68.58%). The outliner banks
64,595 globals, with a 371,560B root reset run. Only four functions with 59 total
body bytes are unreachable. Local self-copies and adjacent same-local set/get
readbacks remain absent. Byte counts describe static encodings, not runtime
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
Current closure admission remains its own path. The current selective
merge/result pilot uses the existing Value/Core model. The remaining aggregate
transport and global banking are the next size hills; retain complete type,
owner, read, variant, loop/backedge and invocation-zero checks.

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

The preceding separate release profile took 6.13s: backend 5.12s, checking 0.53s,
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
