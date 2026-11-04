# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
The next latency gate is below five seconds; subsecond compilation and 1–2MB
Wasm remain goals. Reachable throughput targets are 50k source lines in 0.5s,
then one million lines/second. None of these Main goals is complete.

The
[array-loop checkpoint](scripts/bench/goose/results/2026-11-04-sort-hills.md)
removes dominated fixed-array readiness guards, specializes scalar strides and
adds guarded bulk copy/fill loops after ordinary source/owner checks. Unsafe
ranges retain the exact scalar loop, including valid-prefix writes before a
later bounds trap. See `zig-native/CONTRACT.md`.

Five fresh release pairs improve unchanged merge sort **1.64x**, quicksort
**1.35x**, and Sieve **2.43x**. Custom hash regresses **4–5%**; CRC32, Fannkuch
and F32 Mandelbrot have no material runtime gain. Goose advanced independently
to `0d1715ce`; a fresh comparison leaves merge **2.00x**, quick **1.11x**, Sieve
**2.31x**, CRC **1.32x** and custom hash **7.37x** behind it. All seven adapted
pairs pass. Original F64 and the other 43 catalog tasks remain outside paired
coverage. Direct Blot wins use its frozen preceding release, not old Goose gaps.

Main shrinks **10,097,652 → 10,049,963B (-0.47%)**, with declared locals
**336,753 → 335,682** and 9,440 functions unchanged. Three fresh uncached pairs
measure **5.555 → 5.545s**, with changes **+2 / -93 / -10ms**: no compile-speed
win. Local/global instructions still occupy **6.51MB**. Main admits ten bulk
copies and three fills; representation work remains the large hill.

A separate exact-artifact profile records backend **4.430s**, checking
**0.500s**, lowering **0.124s**, validation **0.102s**, cumulative backend
allocation requests **5.324GB**, and process RSS **1,110,332KiB**. Requested
bytes are not peak memory; overlapping timing families do not add. Scoped
backend engine subtimers remain unavailable.

All **3,001 native laws compile without LLVM**. All **438 affected laws** pass
sampled faults on the final native binary; five focused full-fault laws include
three exhaustive sweeps. The development family passes **271 native / 250 guests
in 76.3s**. All **330 affected release guests** pass, including same-array reads
after bulk loops, skipped reads, exact float bits, aliases and prefix traps.
Formatting, types and Zig lint pass. The full gate passes smoke/harness and 282
native laws without failures, then reaches its 180s budget. **Full qualification
remains pending.**

Release compiler SHA256:
`dbb034d016d09d6b8a634ff97fbfac705915692848694658ec340f6175b169a7`. Main SHA256:
`8a5bc671b85bba52b8989abe4c2165e26d1e379c659e3db9666dd60ad7e5127b`. A fresh
inspected NVIDIA frame passes original budgets and matches the preceding
PNG/trace byte for byte; see
[frame evidence](tasks/storage-handoff-evidence/2026-11-04-sort-hills-frame.json).
Broader gameplay/software-adapter qualification remains pending. Pen's normal
source bridge still omits inferenceBudget; the bounded Deno runner builds Main
and Pen loads that reviewed artifact. Sibling source/assets remain unchanged:
Gdev `38af070`, Ink `ccaf08f`, Pen `d159492`.

The
[preceding shared hills](scripts/bench/goose/results/2026-11-04-shared-hills.md)
retain CRC composition, zero-allocation fold probes, copy proofs and rejected
scalar inlining.
[Direct recursion](scripts/bench/goose/results/2026-11-04-recursive-calls.md)
retains fixed Array U32/U32/Unit headers and finite invariant owner access;
broader recursion stays excluded.
[Addressed inputs](scripts/bench/goose/results/2026-11-04-addressed-inputs.md)
retain the rejected per-call snapshot rollout. Current runtime changes do not
complete the owned-storage rewrite.

## Next Main lever

Attribute materialization by record shape and operation: construction, call,
result, join, loop and row load. Measure distinct creations, repeated
expansions, actual demanded fields and final encoded bytes before redesigning
representation. The preceding checkpoint’s argument counts suggest repeated
shape work but do not establish its exclusive CPU cost.

With Astra, compare two bounded pilots: creation-backed immutable
`world_storage.FrameAccess` with borrowed private pointers/lazy field loads,
versus shared semantic shapes and transitive field demand. Keep a backing from
creation through helpers/branches/loops, rather than serializing a new packet at
each call. Keep small math records inline. A representative pilot should remove
about 20% of Main bytes or 10% of compile time while preserving snapshots,
owner/callback evidence, lifetimes and current budgets. A pointer hiding the
full eager Value tree would leave much compiler cost intact. Reject the approach
if eligible records account for little output or stores/loads replace the same
work.

The nearer sub-five-second lever needs scoped backend allocation/CPU
attribution; the current broad profile does not split generation, outlining and
assembly. Hash lane batching and dominated bounds/load elimination remain
separate runtime hills. Preserve valid-iteration effects before an eventual
bounds trap.

Use the private checked-IR capture/replay for short backend iterations:

```sh
deno run -A scripts/bench/capture_outline.ts --output build/bench/outline-capture
(cd zig-native && zig build bench-outline -Doptimize=fast -Dllvm=false --prefix zig-out-native-dev)
zig-native/zig-out-native-dev/bin/blot-outline-replay build/bench/outline-capture verify
```

Capture a fresh pinned artifact. Replay builds in about 0.5s and finalizes in
about 3s; it is engine evidence, not arbitrary-IR or whole-runtime authority.
Use `scripts/bench/capture_scaling.ts`, `aggregate_scaling.ts` and
`compiler_throughput.ts` for bounded controls. Small controls do not predict
Main.

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

The
[preceding checkpoint](https://github.com/mewhhaha/blot2/blob/b69ecfe38fc056bf5648e2dcb152f49ea2a0eeed/CONTINUE.md)
preserves earlier contracts, historical 2.08MB recovery, measurements, held
experiments and remaining requirements. Documentation cleanup is not completion.

## Iteration and delivery

Use Zig 0.17.0 and `-Dllvm=false` for development/native tests. Recent native
compiler/inventory rebuilds take about 7–13s / 16–20s; the final development
family takes 76s. This batch used one five-minute LLVM release candidate. Do not
repeat unchanged long diagnostics or the old 36-minute build; LLVM is reserved
for meaningful final release measurements.

Use `deno task check:dev --area scoped-storage` for the current regression
family and `deno task test:compiler` before compiler commits. Full qualification
is separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing sibling checkouts; no new worktrees. Commit/push
coherent checked batches to main and verify the remote. Environment publication
and upstream comments require explicit requests.
