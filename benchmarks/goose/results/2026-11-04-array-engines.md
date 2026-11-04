# Array engines and local encoding — 2026-11-04

All four selected hills were tested against frozen
`294768442bdf3fcb7be394751a54692a3e0db58f`. Creation receipts, independent lanes
and strided reduction remain. Wide-record backing was rejected; local-index
ordering supplies the measured Main size win.
[Machine-readable evidence](2026-11-04-array-engines.json) pins sources,
binaries, individual samples, rejected candidates and qualification. Final
compiler SHA256:
`7c8027242749ccc1027c6d855a7bd91f7cba72f27a39df307e36ea29aace3ac8`.

## Runtime

Five fresh release-Wasm pairs after one excluded process warmup, with unchanged
sources, algorithms, input sizes, kernel warmups and checksums. Ratios are
medians of matched observations. Merge clocks cover four 400k-element sorts.

| Workload       | Before ms | After ms | Paired speedup |    Wasm bytes |
| -------------- | --------: | -------: | -------------: | ------------: |
| fannkuch       |     14.08 |    14.13 |         0.997x | 5,984 → 5,984 |
| crc32          |     18.93 |    18.75 |         1.015x | 5,182 → 5,155 |
| custom_hash    |    104.32 |    14.74 |         7.004x | 5,925 → 6,512 |
| sieve          |     25.54 |    22.02 |         1.160x | 5,098 → 5,225 |
| sort_merge     |    143.67 |   120.11 |         1.188x | 7,196 → 7,128 |
| sort_quick     |    124.19 |   121.44 |         1.012x | 6,118 → 6,067 |
| mandelbrot_f32 |     76.94 |    75.43 |         1.021x | 6,143 → 6,066 |

All seven Goose pairs and cold-build observations are freshly measured too; both
README charts use this survey. Cold builds include process startup and are not
controlled before/after compiler-latency evidence. Blot uses U32 payloads where
Goose uses U8 for hash, flags and pixels; both sorts use four-byte elements.
Mandelbrot is an explicitly labelled F32 control. Original F64 remains
unsupported.

Goose's installed binary remains `8c09c1a6…`. Reference scripts/catalog/ports
come from Git revision `dccd2a2e81035f84a6e6eef24723e24770b42e85`, matching the
preceding comparison. The live checkout advanced independently: one run detected
an input edit, and another rejected the old binary through its newer driver.
Both runs are excluded. The final survey executes frozen reference inputs; a
regression test rejects edits during the initial copy and preserves snapshots
through later edits. No sibling checkout was modified.

## Decisions

1. Successful fixed scalar Array creation grants a private exact descriptor
   receipt through normal and recursive helpers. Unknown/mixed descriptors and
   scalar-address programs decline. First actual use can load header length
   directly; per-access bounds, lazy access order and other owner validation
   remain. There are no additional public ABI words or runtime validation cache.
2. A bounded source proof recognizes eight independent cyclic U32 recurrences.
   Exact selected primitives qualify, including prelude forwarding wrappers;
   overloaded implementations and curried applications decline. Complete bounds,
   nonwrap and disjointness guards license resident scalar lanes or two i32x4
   states. The exact original loop handles aliases, tails and unsafe guards.
3. Sieve's exact strided predicate/count/last-index loop gets one load, Boolean
   count add, index select and conditional backedge. Ordinary source/owner
   checks, complete inclusive bounds and nonwrap proofs remain. Three earlier
   marking rewrites regressed roughly 5–15% and were removed. Their measured
   Wasm samples remain; some archived early emitter sources are reconstructed,
   not exact pins.
4. The first wide-record backing candidate grew Main **357,722B (+3.56%)**. It
   added 41,582 loads and 52,295 local operations while losing existing
   descriptor sharing and field-demand savings. The bounded rescue and final
   removal decision are recorded in the JSON. The replacement is a simple final
   local-index permutation: parameters stay fixed, local types/zero
   initialization and all packed flags remain, and instruction order is
   unchanged. Hot locals receive shorter ULEB indices. Exact declaration costs
   are charged before publication; hidden local identities and no-gain cases
   decline. This removes encoded bytes, not source operations or semantic
   checks.

## Main

Main changes **10,038,987 → 9,203,613B** (8.3% smaller). Three fresh uncached,
counterbalanced release pairs measure **5.768 → 5.523s** with paired deltas
**-1277ms, +38ms, +94ms**. The median paired change is **+37.79ms**; there is
**no reliable compilation gain**. The 20%-size/10%-compilation target is **not
met**. Raw paired deltas retain dispersion. Subsecond compilation and 1–2MB
output remain open. Final decoded Main still contains **3,795,220
instructions**, including **2,100,876 local operations** occupying
**4,721,802B**. This is an encoding win, not an operation-count win. Even one
byte per instruction exceeds 3.79MB; reaching 1–2MB requires removing
substantial emitted transport. Exact static census reports remain in the raw
evidence; static transfer counts do not prove dead work or runtime cost.

Main records 111 creation-proven validation omissions and no lane or strided
reduction matches. The hash/Sieve build witnesses exercise their respective new
engines. These counters count static emission work, not dynamic executions.

A fresh inspected real NVIDIA Pen frame passes the tracked runner. Its PNG
matches the preceding frame. ABI 8, session 2, schema 26 and original 2MiB
temporary /256KiB persistent / 2MiB transport /4096-owner budgets remain.
Broader gameplay/save/recovery and software-adapter qualification remain
pending.

## Checks

All **2,965 native laws compile without LLVM**. The explicit development family
passes **20 native / 60 guest laws in 29.86s**. The affected native family also
passes full allocation-failure mode. Final release guests, four
packaged/standalone/public API laws, types, format and zero-finding Zig lint
pass. Full-fault laws retain immutable inputs and leak-free rollback.

The full gate reaches its 180s budget in 180.25s: 103 native passes, 73
completed full sweeps and no emitted failing law. Budget cancellation terminates
the native shards; this is an incomplete run. Raw shard logs are archived.
**Full qualification remains pending.**

Development uses the native backend; compiler-only rebuilds take about 7–8s. The
final LLVM build is separately recorded. Btrfs metadata reservations caused
ENOSPC despite free data; bounded old binary/archive cache cleanup restored
installation. Compiled-but-uninstalled test runs were recorded separately and
never labelled complete development checks. No privileged filesystem operation
was performed.
