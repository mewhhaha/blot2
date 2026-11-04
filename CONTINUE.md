# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
The next latency gate is below five seconds; subsecond compilation and 1–2MB
Wasm remain goals. Reachable throughput targets are 50k source lines in 0.5s,
then one million lines/second. None of these Main goals is complete.

The
[addressed-input checkpoint](scripts/bench/goose/results/2026-11-04-addressed-inputs.md)
adds immutable private bundles with exact range forwarding, separate outputs,
transitive demand and bounded snapshot reuse. Complete semantic Values, owner
roles, callbacks and access replay remain checked. Structural borrowed-input
preference separates private cache alternatives without runtime addresses/local
IDs. Sparse calls rebuild with the ordinary ABI; a bounded optional rejection
memo survives executable rollback. See `zig-native/CONTRACT.md` for admission,
read-only proofs, snapshot barriers and cleanup.

The largest repeated distinct-capture control shrinks **263,521 → 97,002B
(63.2%)**; shared captures shrink **50,307 → 36,141B**. Two single-call width32
controls grow 7.1%; keep that regression visible. Three repetitions of 32 shapes
execute 384 checks per compiler. The benchmark retains actual Wasm.

Gdev is effectively flat: three uncached pairs record **6.334 → 6.235s**, Main
**10,241,074 → 10,253,029B (+0.12%)**. Per-pair changes are -115/+8/-300ms, not
a robust latency win. Earlier 5.28s belongs to another shared-host round. Final
LLVM compiler SHA256:
`2de96d223cced8d71bbf4a5ebf2d875ed92a2445a7ef7abb556c8ec7e81c8d19`. Final Main
SHA256: `148bf08353aa302e2462e15488728a18a036fa71dfc7d7aedd192a235ee05833`. A
separate exact-artifact profile has backend 4.645s, checking 0.516s, lowering
0.131s and validation 0.107s. Backend requests 5.29GB cumulatively; maximum
process RSS is 1,104,988KiB. Overlapping timing families do not add.

**Main already had zero packed helper calls.** Packet serialization explained
the capture regression, not the game's remaining 6.70MB of local/global
instructions. The broad rollout grew Main by 134KB and is rejected. Adaptive
admission reduces snapshot stores 13,965 → 1,079, but Main still has zero cache
hits. Do not extrapolate capture savings to Main.

All 2,976 native laws compile without LLVM. The affected union passes 412 laws
with sampled faults; eight focused laws pass full-fault mode, including three
exhaustive allocation sweeps. The final development family passes 245 native
laws, its guest suite, formatting, types and zero Zig lint findings. Release
guests pass 300/302; the summary-job ECS export and optimized iter.take(0)
allocation failures also reproduce on the frozen compiler. Full qualification
remains pending. The full gate passes 49 smoke checks and the harness, then
stops at 180s after 101 native passes, zero failures/leaks/logged errors.

World/editor, hand and renderer binaries remain byte-identical. Seven editor
assertions, 160 hand assertions and seven renderer streams match. The exact Main
passes the original memory budgets in one headless NVIDIA frame; its inspected
PNG and guest trace match the baseline byte for byte. See
[frame evidence](tasks/storage-handoff-evidence/2026-11-04-addressed-inputs-frame.json).
Broader gameplay/software-adapter coverage remains pending. The normal Pen
source bridge still omits inferenceBudget; bounded Deno runners compile and
execute affected sources, and the frame reuses the reviewed artifact. This batch
changes no sibling source/assets. Gdev remains `38af070`, Ink `ccaf08f`, Pen
`d159492`.

Five numeric binaries remain byte-identical. README charts rerun Goose's pinned
cases and V8 checksums; no numeric runtime improvement is claimed. Two recursive
Blot sorts and original F64 remain unsupported.

## Next Main lever

Measure copy candidates rejected solely for crossing structured control in
`wasm_copy_coalesce.zig`. Its segment counter currently discards all aliases at
block/if/else/end as well as loops/jumps. A small structured-scope stack could
retain dominating immutable aliases across branches, discard arm-local aliases
at else/end, and preserve conservative source-version and loop/jump barriers.
Keep default-zero reads and the complete-all-reads proof. Do this before
memory-backed banks: individual memory loads/stores cost more and the existing
frequency-sorted bank layout disrupts contiguous bulk copies.

Use the private checked-IR capture/replay for short backend iterations:

```sh
deno run -A scripts/bench/capture_outline.ts --output build/bench/outline-capture
(cd zig-native && zig build bench-outline -Doptimize=fast -Dllvm=false --prefix zig-out-native-dev)
zig-native/zig-out-native-dev/bin/blot-outline-replay build/bench/outline-capture verify
```

Capture a fresh pinned artifact; older captures qualify their exact source and
compiler. Replay builds in about 0.5s and finalizes in about 3s. It is compiler
engine evidence, not authority for arbitrary IR or whole-runtime qualification.

Use `scripts/bench/capture_scaling.ts` for capture boundaries and
`scripts/bench/aggregate_scaling.ts` for joins, results and distinct-owner
controls. `scripts/bench/compiler_throughput.ts` measures reachable primitive
throughput with source/work/Wasm pins. Small controls do not predict Main.

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

Use Zig 0.17.0 and `-Dllvm=false` for development/native tests. The latest
compiler builds take 7s; inventory compilation takes 12s. Development family
checks stay below five minutes. Native Safe and Fast Main probes each stopped at
30s, and the frozen Fast baseline also stopped at 30s; none is a release latency
measurement. Do not repeat unchanged long diagnostics or the old 36-minute
build. LLVM is reserved for meaningful final release candidates; this batch's
two release builds took about five/six minutes.

Use `deno task check:dev --area scoped-storage` for the current regression
family and `deno task test:compiler` before compiler commits. Full qualification
is separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing sibling checkouts; no new worktrees. Commit/push
coherent checked batches to main and verify the remote. Environment publication
and upstream comments require explicit requests.
