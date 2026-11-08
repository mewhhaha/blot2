# Continue the owned-storage rewrite

## Current frontier

The active experiment ports the compiler to idiomatic Goose in
[`compiler-goose/`](compiler-goose/README.md). The user requests fixing and
recompiling the written port.
Whole-program parsing passes; type/lifetime repairs and full compilation are
still pending. Source-only checkpoints are unverified;
follow `compiler-goose/source-correspondence.json` and its port notes for exact
writing status and runtime gaps. Keep `compiler/` and the default toolchain
unchanged as the oracle. The remote tag `goose-port-oracle-156f84b` pins source
`156f84b4810f630dff7e5efb7014b2194e3160f7`; its saved compiler is
`build/goose-port/oracle/bin/blotc` with the release SHA256 below. Use bounded
upstream Goose acceptance checks and differential comparisons. The
[compilation frontier](compiler-goose/port-notes/compilation.md) records the
current repair loop. The whole port establishes no compiler performance or parity
result. Parser checkpoint `21df1327` is pushed: its import closure falls from
436 to 14 files, and 63 controls match oracle counts and complete diagnostics;
tracked AST/fixity/recovery/depth laws pass. Four isolated engine suites pass.
The current package repairs keep recursive state scalar, construct borrowed
views through explicit boundaries, and share nested admission using local
workspace copies. Whole-program C emission and linking are still pending.
The selected private checker filters impossible stable global candidates while
retaining live reference/local provenance checks. Two frozen220 pairs measure
99.138 ->42.461s to the identical source diagnostic (57.17% reduction), with
sampled process memory essentially unchanged. These are failing-prefix gains,
not completed compiler timings. The new candidate is pinned in the
[global-filter receipt](benchmarks/evidence/qualification/2026-11-08-goose-global-filter.json),
including its source delta and byte-exact tracked recipe reconstruction. Private
checker678b88 retains the ce317 unused-overload-text optimization and checks
exported roots first, retaining final export validation and every fixup. Its
201frontend/8runtime/27focused controls pass; one error order changes while the
complete multiset remains equal. The preceding
global-bound correctness fix preserves all provenance alternatives and exactness;
10 positive cases execute and 26 strict negatives reject. The formatting candidate
matches 201 frontend cases, 8 executed runtimes, 20 focused cases and 15 emitted-C
comparisons. Same-CPU synthetic overload checks improve 24–32% at 512–2048 heads;
direct-call controls stay within 2%. This is not whole-port performance evidence.
The tracked recipe reconstructs all 108 checker source files byte-exactly with no
fuzz or offsets. Installed tools, upstream checkout and Zig oracle are unchanged.

Frozen324 replaces Session's Generator backpointer with the existing scalar
Frame token. Lookup retains live generation, current-frame, registry bounds and
exact Session/Generator/Workspace identity checks. Three source files change;
normal writers leave all generated adapters unchanged. Fourteen reduced Frame
controls pass, and independent inversion preserves the surrounding source.
The static declaration graph falls 939→506; this is not an instantiated-type or
time measurement. Six readonly Plan parameters also pass the small view by value
through the actual forwarding chain; local-reference escapes still reject.

Actual321 reaches a new active-seed-borrow diagnostic after 74.174s, compared with
320's 115.636s at the preceding Plan binding error. Frozen322 returns the same
live anchor prefix through its named pool; concrete clone-path analysis excludes
anchor invalidation. Its74.494s run reached another readonly Plan forwarding
path. Frozen324 passes that path by value and indexes live mapping/row buffer
item views; the74.640s actual run reaches an importer call API mismatch. Source and frontier differ,
so this is shorter repair iteration, not a paired full-compile speed result.
Whole parsing passes 440 files. No program C/header/executable, executed-Wasm
comparison or Gdev result exists for the port. Caps remain 120/300s with a 3s
first-error window. The optional-global index showed no gain beyond controls and
remains unselected; a query-specific array-cache gate passed correctness but regressed
its measured stresses and remains unselected. Preserve the exact source/carrier limits in the linked evidence.

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
Sub-five-second Main, subsecond compilation and 1–2MB Wasm remain unmet.
Reachable throughput targets are 50k source lines in 0.5s, then one million
lines/second.

The
[array engines checkpoint](benchmarks/goose/results/2026-11-04-array-engines.md)
improves unchanged merge/custom hash/Sieve another **1.19/7.00/1.16x** across
five release-Wasm pairs. Creation-proven descriptors retain private validation
receipts; exact independent U32 lanes use scalar registers or SIMD; Sieve's
strided count/index scan uses a branchless loop. Guards retain the original
checked fallbacks and trap prefixes. All seven Goose pairs and both README
charts are freshly measured.

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
