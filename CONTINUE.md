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

The latest fresh actual main takes **5.56 seconds**, producing **16,677,822
bytes of Wasm**, down from 21,576,480 bytes (22.7% smaller). The configured
launcher takes **6.06s** with the identical compiler identity and whole-module
hash. The preceding release took 5.91s explicitly and 6.06s through the
launcher; these are individual completions, cache disabled, not a repeated
timing distribution. The five-second and subsecond targets remain unmet. Exact
source, toolchain, binary, workload and configured-launcher pins are in
[the current evidence](zig-native/measurements/identity-joins-2026-11-02.json).
Release source is `0d9ab244` plus patch `d14a168e9fb2`.

One completed named-function plan replaces the scalar/inline/Reader/writer probe
cascade. Full source/type witnesses precede physical projection; plans retain
the ABI, result layout and ordered actual owner events. Unused arguments no
longer invent reads. Input-owner array/view aliases retain their real roots;
fresh owners fall back. Export roots keep outlining, oversized helpers roll
back, and trapping helpers retain declared result layouts. Closures still use
their separate path. This is a function-contract boundary, not a completed
monomorphic expression IR.

All 2,870 native laws compile; all 62 affected laws pass full allocation faults
(29 sweeps), 86 type/effect guests and two new guests (96 assertions) pass, and
Zig lint is clean. The broader storage/static family has 187 passes and 15
failures reproduced with the old compiler. The required full gate retains 48
passes/one baseline List/chunk failure. The final LLVM compiler passes seven
original world/editor checks, 160 hand checks in sync/JSPI, seven real-menu
checks in both modes and all seven identical renderer streams. Installed Pen
still rejects ABI 8 before rendering the new artifact; no new frame/PNG is
qualified. The launcher selects the final release at
`zig-native/zig-out/bin/blotc`.

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
The new artifact still spends 11.70MB (70.1%) on local/global traffic. The next
size lever is field-wise control merges: retain unchanged aggregate fields and
materialize only changed paths. A private branch/loop mask prototype is pending;
copy cleanup and field/match probes remain held without material World CPU
gains.

A separate profile takes 5.65s: backend 4.71s, checking 0.48s, validation 0.10s.
Backend traffic is 4.96GB/3.41M allocations. Plans emit 138,596 calls with zero
post-plan type queries, but preparation/key construction still costs work. 2,107
rolled-back trials discard 188,790 of 1,017,503 counted expressions; this is a
work ratio, not a measured CPU share. The next structural slice should resolve
operations/layouts/callees and symbolic owner obligations before physical
emission, replacing the corresponding Generator walks.

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
