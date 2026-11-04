# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
The next latency gate is below five seconds; subsecond compilation and 1–2MB
Wasm remain goals. Reachable throughput targets are 50k source lines in 0.5s,
then one million lines/second. None of these Main goals is complete.

The
[shared-hill checkpoint](scripts/bench/goose/results/2026-11-04-shared-hills.md)
composes checked fixed1..8-round U32 bit loops, preserves dominating machine
snapshots through structured scopes, and removes curried allocations from
selected saturated scalar primitive aliases. Normal type/owner/effect checks,
exact loop shells, coordinate guards, original-read accounting and transactional
publication remain. See `zig-native/CONTRACT.md`.

CRC32 is **6.2x faster** in five fresh release-Wasm pairs: **110.33 → 17.78ms**.
Its output grows **5,033 → 5,098B**; the fresh Goose gap is **1.33x**, down from
8.10x. All seven unchanged adapted pairs pass. Original F64 and the other 43
catalog tasks remain outside paired coverage. Custom hash remains roughly 7x
slower; Goose batches its periodic eight-lane state with SIMD.

Main shrinks **10,253,029 → 10,097,652B (-1.52%)**, but three fresh uncached
pairs regress **5.283 → 5.414s (+2.49%)**, with changes +112/+144/+105ms. This
is no Main compile-speed win. Declared locals fall 355,179 → 336,753. The
private checked-IR replay removes 14,477 more copies and 315 bank globals, with
the independent input audit passing. Remaining local/global instructions occupy
6.54MB; adjacent transfers account for only 1.50MB. Copy deletion alone cannot
reach 1–2MB.

A separate exact-artifact profile records backend **4.439s**, checking
**0.518s**, lowering **0.124s**, validation **0.102s**, cumulative backend
allocation requests **5.315GB**, and process RSS **1,107,548KiB**. Requested
bytes are not peak memory; overlapping timing families do not add. Main admits
zero bit recurrences. Tiny scalar-wrapper inlining showed no runtime gain and
was removed; its patch/artifacts/measurements remain pinned as a rejected
experiment. Extra branch-free scope promotion also added no savings and was
removed.

Evaluated range/map/filter/take probes now allocate **zero bytes per call**;
previous 100-call traffic reached 78.6–137.6MB. The source partial-application
expectation now matches the guide. The principal recorder fixture excludes
unrelated ECS runtime exports and strengthens persisted replay assertions; that
does not qualify ECS request-handler execution.

All **2,996 native laws compile without LLVM**; **433 affected laws** pass
sampled faults. Twenty-six focused laws pass full-fault mode with 33 exhaustive
sweeps. The development family passes **266 native laws / 248 guests in 67.9s**,
plus formatting, types and zero Zig lint findings. **All 328 affected release
guests pass**, including the three previously reported failures. The full gate
passes smoke/harness and 410 native laws with no failures, then reaches its 180s
budget. **Full qualification remains pending.**

Release compiler SHA256:
`4f0120a091870fd45722f4d878a9699f97843e4e40dd830e6583e06af07b09dd`. Main SHA256:
`fcaf7e05e434d6647f1b53b56bf1c39d95fe02e92a1933b8b6fdca3bbc0faa3f`. A fresh
NVIDIA frame passes the original budgets; its inspected PNG and guest trace
match the baseline exactly. See
[frame evidence](tasks/storage-handoff-evidence/2026-11-04-shared-hills-frame.json).
Broader gameplay/software-adapter coverage remains pending. Pen's normal source
bridge still omits inferenceBudget; the bounded Deno runner builds Main and Pen
loads that reviewed artifact. Sibling source/assets remain unchanged: Gdev
`38af070`, Ink `ccaf08f`, Pen `d159492`.

The
[recursion checkpoint](scripts/bench/goose/results/2026-11-04-recursive-calls.md)
preserves direct self-recursion over fixed Array U32 inputs/U32 bounds returning
Unit, with frozen full headers and finite invariant owner access. Broader
recursion remains excluded. The
[addressed-input evidence](scripts/bench/goose/results/2026-11-04-addressed-inputs.md)
retains capture wins and the rejected broad per-call snapshot rollout. Main
already had zero packed helper calls.

## Next Main lever

Attribute materialization by record shape and operation: construction, call,
result, join, loop and row load. Measure distinct creations, repeated
expansions, actual demanded fields and final encoded bytes before redesigning
representation. Main prepares 116,590 argument lists and omits 4,014,808 words;
these counts suggest repeated shape work but do not establish its exclusive CPU
cost.

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
assembly. Hash lane batching and dominated fixed-array check elimination are
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
family takes 68s. This batch used one five-minute LLVM release candidate. Do not
repeat unchanged long diagnostics or the old 36-minute build; LLVM is reserved
for meaningful final release measurements.

Use `deno task check:dev --area scoped-storage` for the current regression
family and `deno task test:compiler` before compiler commits. Full qualification
is separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing sibling checkouts; no new worktrees. Commit/push
coherent checked batches to main and verify the remote. Environment publication
and upstream comments require explicit requests.
