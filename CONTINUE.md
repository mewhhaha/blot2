# Continue the owned-storage rewrite

## Current frontier

**Shared-kernel runtime and Gdev Wasm size are current priorities**, with short
iterations and the subsecond compilation goal retained; the next latency gate is
below five seconds. The throughput target is a fresh, reachable 50k source lines
in 0.5 seconds (100k lines/second), then one million lines/second. Use
`deno run -A scripts/bench/compiler_throughput.ts --compiler PATH --lines 50000`;
it reports exact lines, bytes, estimated tokens, emitted work, Wasm size and
executed checks. Generation and cold compilation remain visible; `--profile` is
a separate diagnostic run. The million-lines/second target remains unmet. Game
diagnostics default to five seconds and have a hard 30-second iteration cap.
Never repeat the recorded 36-minute build or an unchanged five-minute
diagnostic.

The current
[primitive-alias checkpoint](scripts/bench/goose/results/2026-11-03-primitive-aliases.md)
replaces 30 terminal numeric wrappers with ordinary scalar primitive aliases.
The owned backend supports their partial applications/callbacks and shares
scalar opcode/result semantics with constant evaluation. Exact runtime folds
retain separate source-literal authority; ordinary const evaluation preserves
NaNs. ABI 8 and session protocol 2 remain unchanged.

Five fresh-process Blot before/after pairs show Mandelbrot F32 **96.04 →
73.18ms** (24% less time), CRC32 2.5% slower and the other three kernels flat.
The final seven-case Goose survey retains two explicit recursive sort failures;
Goose gaps are CRC32 8.29x, custom hash 6.98x, Sieve 3.07x, F32 Mandelbrot 1.86x
and Fannkuch 0.97x. Original F64 and the other 43 catalog tasks remain
uncovered. The README charts use the final compiler.

Three fresh Gdev compile pairs are effectively flat, **5.860 → 5.814s**. Main
Wasm grows **12,476,667 → 12,490,827B** (0.11%), with 8,257,498B of local/global
instructions. Five-second, subsecond and 1–2MB targets remain unmet. The
installed LLVM compiler is
`88709e2adf6f29ff41a2eaf475851964c05f7d48854dc6f3c78031c87d14daa4`. It was built
once; noLLVM development compiler rebuilds take about 5s. A single noLLVM Gdev
debug probe stopped at its 30s cap and was not repeated. Fresh before/after
builds use their matching preludes; the preserved old Main SHA matches exactly.
Runner `--std-root` supports this comparison.

All 2,945 native laws compile. The affected 214-law/196-guest development family
passes in 52.42s; nine focused laws pass full-fault mode, and the final LLVM
compiler passes the same 196 guests. Zig lint is clean; Astra found no remaining
blocker. Full compiler qualification remains pending; the bounded full-gate
attempt passes 49 smoke and 57 harness checks, then stops at its 180s budget:
110 completed native laws, 83 full sweeps, zero failures/leaks/logged errors.
This is incomplete; the linked JSON pins the logs and records.

World/editor, hand and seven renderer streams pass unchanged; the two small
control binaries shrink. The final Main passes a headless NVIDIA frame; its
inspected PNG and guest trace are byte-identical to the preceding checkpoint.
See
[current frame evidence](tasks/storage-handoff-evidence/2026-11-03-primitive-aliases-frame.json).
Broader gameplay and software-adapter coverage remain pending. Ink/Gdev/Pen
sources and assets are preserved and clean.

Next replace fresh fixed-array return expansion with an explicit owner-transfer
contract for reusable calls. **2,009 completed-plan rollbacks** remain, now
184,212 discarded expressions. The 512-word selector already uses a buffered
ABI; do not widen limits. CRC32's conditional shift/XOR recurrence remains the
largest kernel gap. Preserve the
[fixed-span evidence](scripts/bench/goose/results/2026-11-03-fixed-spans.md) and
[expanded survey controls](scripts/bench/goose/results/2026-11-03-expanded.md).

The preceding
[copy-coalescing checkpoint](zig-native/measurements/copy-coalesce-2026-11-03.json)
reduced Main from 13,594,002 to 12,932,581B with a measured 66ms median paired
compile penalty. Its exact source, qualification and rejected timing controls
remain pinned there; do not compare absolute times across shared-host rounds.

Multi-use aggregate copies now coalesce before outline banking. A complete
adjacent numeric copy disappears only when every destination read can use the
same unchanged source version within one control segment. The unique-callsite
outline tree is traversed iteratively; no computation or effects move. Published
aliases stop at retained snapshots. Cached helper entry reads translate through
accepted aliases and keep only actual reads; bank sharing and writes are
recomputed from staged IR. All 411 changed helpers pass an independent fresh
entry-read audit. Default-zero reads, source mutation, control crossings, loops,
hidden identities and symbolic operands retain their required snapshots.
Ordinary completed bodies use the same proof before slot reuse, pruning only
eliminated destinations. Empty candidate inventories skip the second scan.

At that checkpoint, Main removed 110,067 pre-bank copy pairs and forwarded
39,299 surviving reads. Its outline bank shrank **64,876 → 55,754 globals**;
reset bytes fell 373,246 → 318,514. These are work counts, not additive byte
savings. The nine small scalar/branch/loop source controls retain identical
sizes and pass 270 executed checks per compiler. Wide chains, retained
intermediate snapshots, parallel writes, nested helpers and full allocation
faults have dedicated native laws. The earlier scalar stackification and flat
scalar loop-field sharing remain installed; stop scalar widening and target
larger aggregate boundaries and live outlined interfaces next.

Real-game backend iterations can now replay a checked private IR snapshot. Use
`deno run -A scripts/bench/capture_outline.ts --output DIR` once with the pinned
installed compiler, then
`(cd zig-native && zig build bench-outline -Doptimize=fast -Dllvm=false --prefix zig-out-native-dev)`
and `zig-native/zig-out-native-dev/bin/blot-outline-replay DIR [verify]`. The
native replay tool builds in ~0.5s and replays finalization in ~3s; the
independent 411-helper input audit adds work. It verifies capture
format/bytes/SHA. The tracked capture command was exercised end to end with
before/after source pins and the exact baseline Main hash. This is private
compiler-engine evidence, not an authority for caller-supplied IR or
whole-runtime qualification. No noLLVM whole-game probe was run for this batch.

Checked graph helpers now reuse bodies that mutate input owners and return
input-owned records or borrows. Complete result/event retention, actual caller
lifetimes, alias topology and ordered reads/writes remain checked. Fresh results
and stored borrow escapes retain fallback/rejection; input freeze, reserve, pop
and truncate retain their barriers. Only compiled child input roots precede all
cleanup ranges and keep immutable token locals. Local/export owners, loop
carriers and demand caches retain their separate mutable marking. Direct results
whose every word aliases an input skip caller result-slot allocation and rewind;
partial results and packed packets keep their allocation paths.

The first gate-only experiment sped up the small cases but grew one output 30.5
→ 118.5kB. Preserving input tokens and removing unread direct result slots fixed
that regression. Final matched LLVM width-32 controls shrink 22–24%; the
width-128 shared/distinct cases take 38 → 25ms and 48 → 21ms respectively. The
widest distinct-owner control still grows 620B (2.03%). These ratios do not
predict whole-game savings: Main gains only 99 completed helpers, removes 98
rollbacks and skips 288 result slots. Classify its remaining 2,009 rollbacks and
large transfers before choosing another admission change.

Completed direct-input demand remains installed. Main omits 12,694 helper input
words and 75,414 physical call arguments while still evaluating all semantic
arguments and replaying owner events. Private entry copies preserve logical
local IDs/types. Hidden operands, table/provider identities and instruction
position catalogs retain ordinary inputs. See
[the preceding direct-input evidence](zig-native/measurements/direct-input-2026-11-03.json).

Checked aggregate joins now preserve immutable physical words and materialize
only differing or non-dominating lanes. Mutable owner tokens, loop carriers,
demand caches and normal fallthrough retain capture storage. Tagged, host,
demand and unowned-reference subtrees keep ordinary transport while eligible
siblings share. Completed buffered helpers may return unchanged input words
without result stores or caller loads. Statement completions and static callable
placeholders share one unwritten default-zero local per function. Complete type,
owner, read, effect and variant checks remain. Main shares 44,426 join words,
avoids 3,657 result stores and 29,642 result loads, and shares 139,130 zero
values. Counts describe compiler work, not additive byte savings.

Use `scripts/bench/aggregate_scaling.ts` for short iterations: 45 cases × three
fresh compilations take roughly two seconds with executed checksums. Its Unit,
read-only, shared-owner and distinct-owner controls isolate argument/result
transport from helper admission. Keep native Fast and final LLVM timings
separate. The earlier wider checked-source validation-budget failures remain
pinned in
[the scaling evidence](zig-native/measurements/aggregate-scaling-2026-11-03.json);
no full-game build is required for each microbenchmark iteration.

The first pilot shrank the output but regressed compilation to 10.470s. A
bounded stack sample attributed 46.3% of sampled emission CPU to rebuilding all
historical mutable-local sets at every join. The final implementation indexes
mutable origins once per function. Full Main and World Wasm hashes remain
identical after that bookkeeping fix; the final matched pair restores baseline
latency. The rejected candidate and diagnostic evidence remain pinned.

The preceding final transport cleanup still removes same-local get/set pairs and
folds set/get to tee after local compaction. Original module bodies and
semantic/table coordinates remain immutable; neutral reservation nops disappear
only during final assembly. Hidden ownership/resource markers and flagged table
operands retain conservative handling. See
[the preceding evidence](zig-native/measurements/transport-cleanup-2026-11-03.json)
for its exact baseline and byte accounting.

Packed helper inputs now reserve logical input locals in the existing Value
layout. After complete body checking, result serialization and cleanup, the
backend loads only words read by the finished IR and omits their unused caller
stores. The preceding packed-input batch avoided 7,392 loads and 11,088 stores,
with a 10% World witness reduction. Semantic arguments, owner/read/effect
admission, evaluation order, full packet offsets and output serialization remain
intact. Direct-word calls retain their ABI. This uses the existing value tree
rather than adding another representation or source-footprint cache.

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

At the preceding copy-coalescing checkpoint, all 2,929 native laws compiled. Its
integrated 165-law family had 162 passes and three unchanged completed-plan
assertions with 63 full allocation-failure sweeps, no leaks or logged errors.
The affected 34-law family passes full faults again after the output-preserving
no-candidate fast exit. The exact baseline assertion reproductions remain pinned
in the preceding evidence. Final LLVM guests have 119 passes/two unchanged
unsupported legacy memory-profile cases. Zig lint is clean. The full gate still
stops at 48 passes/one baseline List/chunk failure: full qualification remains
pending. Final LLVM passes seven world/editor, 160 hand and seven identical
renderer streams. World shrinks 507,288 → 495,494B; hand 205,425 → 203,340B;
renderer 97,891 → 94,648B. Installed Pen still rejects ABI 8 before rendering;
no new frame/PNG is qualified. The configured launcher selects the exact
measured release.

The current artifact has 413,749 declared locals and 56,176 mutable globals, up
by 4,857 and 54. Local/global instructions occupy 8,357,058B: 6,658,593B local
and 1,698,465B global, down 184,899B. Call bytes drop another 85,192B and
constants 111,981B; payload loads, stores and arithmetic retain identical byte
counts. Static encoding counts do not establish runtime cost or prove removable
work. Larger aggregate boundaries and outlining representation remain size
hills.

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

The preceding separate release profile took 6.13s: backend 5.12s, checking
0.53s, validation 0.11s. Borrow/owner-graph traversal and metadata copying
remain the latency follow-up from a bounded weighted stack sample; size
inspection does not establish CPU cost.

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
