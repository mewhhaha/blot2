# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**, with
the next gate below five seconds. The throughput target is a fresh, reachable
50k source lines in 0.5 seconds (100k lines/second), then one million lines/second.
Use `deno run -A scripts/bench/compiler_throughput.ts --compiler PATH --lines 50000`;
it reports exact lines, bytes, estimated tokens, emitted work, Wasm size and
executed checks. Generation and cold compilation remain visible; `--profile`
is a separate diagnostic run. The million-lines/second target remains unmet.
Game diagnostics default to five seconds and have a hard 30-second iteration cap. Never repeat the recorded 36-minute build
or an unchanged five-minute diagnostic.

The latest fresh actual main takes **5.91 seconds**, versus a matched **7.33s**
baseline (19.3% faster), producing **21,576,480 bytes of Wasm**. The configured
launcher path takes 6.06s with the identical compiler identity and complete Wasm
hash. These are individual completions, cache disabled. The five-second and
subsecond Gdev targets remain unmet. Exact source/toolchain/binary/workload pins
are in [the current evidence](zig-native/measurements/unified-function-plans-2026-11-02.json).
Release source is `cd02242b` plus patch `5c477c1e6f69`.

One completed named-function plan replaces the scalar/inline/Reader/writer probe
cascade. Full source/type witnesses precede physical projection; plans retain
the ABI, result layout and ordered actual owner events. Unused arguments no
longer invent reads. Input-owner array/view aliases retain their real roots;
fresh owners fall back. Export roots keep outlining, oversized helpers roll
back, and trapping helpers retain declared result layouts. Closures still use
their separate path. This is a function-contract boundary, not a completed
monomorphic expression IR.

All 2,866 native laws compile; all 58 affected laws pass full allocation faults
(28 sweeps), 86 type/effect guests pass, and Zig lint is clean. The broader
storage/static family has 185 passes and 15 failures reproduced with the old
compiler. The required full gate retains 48 passes/one baseline List/chunk
failure. The final LLVM compiler passes seven original world/editor checks,
160 hand checks in sync/JSPI and all seven identical renderer streams. Installed
Pen still rejects ABI 8 before rendering the new artifact; no new frame/PNG is
qualified. The launcher selects the final release at `zig-native/zig-out/bin/blotc`.

A separate profile takes 6.08s: backend 5.10s, checking 0.52s, validation 0.10s.
Backend traffic is 5.26GB/3.42M allocations. Plans emit 138,596 calls with zero
post-plan type queries, but preparation/key construction still costs work.
2,107 rolled-back trials discard 188,790 of 1,017,503 counted expressions; this
is a work ratio, not a measured CPU share. The next structural slice should
resolve operations/layouts/callees and symbolic owner obligations before physical
emission, replacing the corresponding Generator walks.

The reachable primitive benchmark compiles 50,025 lines in 16 modules in
0.480–0.491s, plus 0.026s generation, producing 973,511B Wasm with all three
checks passing. The old compiler already takes 0.470s on the same workload;
this is a throughput control, not a general speedup. A single-module 50k control
hits the existing 100k-node pool-discovery cap; the benchmark preserves that
failure. Gdev's rich backend work remains the main latency lever.

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
`deno task test:compiler` before compiler commits. Development/native test builds
use Zig 0.17.0 without LLVM. Reserve `deno task build:compiler` for a meaningful
release candidate, then run the tracked `scripts/storage_handoff/build_gdev.ts`
and `run_pen.py` runners. Game builds retain their 30-second cap; profile in a
separate run. Frozen candidates use plain archives, exact source/binary hashes
and the existing sibling workloads, never extra worktrees.
