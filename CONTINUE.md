# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
The next latency gate is below five seconds; subsecond compilation and 1–2MB
Wasm remain goals. Reachable throughput targets are 50k source lines in 0.5s,
then one million lines/second. None of these Main goals is complete.

The
[recursive-call checkpoint](scripts/bench/goose/results/2026-11-04-recursive-calls.md)
implements the first slice of the
[Astra-reviewed plan](tasks/RECURSIVE_CALLS.md): closed named direct
self-recursion over U32 bounds and fixed Array U32 inputs, returning Unit.
Complete direct headers retain semantic owner aliases and never narrow
parameters or use addressed/packed transport. Finite invariant access is
separate from ordered events; possible writes never establish initialization or
nonempty storage, including through ordinary wrappers. Publication is atomic.
Machine SCCs allow ordinary recursion disjoint from outline-bank members while
still rejecting bank reentry and reachable unknown indirect dispatch.

Both unchanged Goose sorting ports now compile and execute at 100,000 and
400,000 elements. Five fresh cold-build medians are **51.00 / 52.74ms**; Wasm is
**6,741 / 6,244B**. Each has one recursive definition and two runtime self-call
sites, with full ten/six-word inputs. Five bounded runtime pairs show **2.54x
merge / 1.51x quicksort** gaps against Goose. Six original-numeric pairs plus
the explicit Mandelbrot F32 control now pass; original F64 and the other 43
catalog tasks remain outside paired coverage. Five preceding numeric binaries
remain byte-identical. README charts show all seven pairs.

Gdev Main is byte-identical at **10,253,029B**. Three fresh pairs record **5.615
→ 5.732s (+2.1%)**, with changes +117/-21/+234ms. This is no compile-speed win;
do not compare these shared-host times with earlier unpaired rounds. A separate
exact-artifact profile records backend **4.769s**, checking **0.513s**, lowering
**0.131s**, validation **0.108s**, cumulative backend allocation requests
**5.30GB**, and process RSS **1,102,832KiB**. Overlapping timing families do not
add. Discovery examines 4,029 source bodies / 169,617 nodes; Main admits no
recursive component.

Final LLVM compiler SHA256:
`f90931ef17ec2b143f880db68253d54392ec4f19a44e9eb58ff09b587d6d967b`. Main SHA256:
`148bf08353aa302e2462e15488728a18a036fa71dfc7d7aedd192a235ee05833`. A fresh
headless NVIDIA frame passes unchanged memory budgets; its inspected PNG and
guest trace match the baseline exactly. See
[frame evidence](tasks/storage-handoff-evidence/2026-11-04-recursive-calls-frame.json).
Broader gameplay/software-adapter coverage remains pending. The normal Pen
source bridge still omits inferenceBudget; the bounded Deno runner builds Main
and Pen executes that reviewed artifact. Sibling source/assets remain unchanged:
Gdev `38af070`, Ink `ccaf08f`, Pen `d159492`.

All **2,983 native laws compile without LLVM**. The affected union passes **419
laws** with sampled faults. Seven new laws pass full-fault mode, including three
exhaustive allocation sweeps. The development family passes **252 native laws /
242 guest tests in 53.1s**, plus formatting, types and zero Zig lint findings.
All 24 recursive guests pass in both codegen tiers, including depth512, owner
aliases, trap recovery, repeated exports and forced outlining. Actual native
development rebuilds take about 7s for the compiler / 16s for inventory; LLVM is
reserved for the one release measurement candidate.

Full qualification remains **pending**. Release affected guests pass 324/326;
the summary-job ECS export and optimized iter.take(0) allocation failures both
reproduce on frozen compiler `2de96d…`. The full gate passes smoke/harness and
200 native laws, then stops at 133.4s on the pre-existing source-input primitive
arity diagnostic mismatch (`call_arity` versus `module_loader_required`). That
failure reproduces on the frozen source snapshot; all 294 frontend files match.
The remaining full suite has not passed.

The preceding
[addressed-input evidence](scripts/bench/goose/results/2026-11-04-addressed-inputs.md)
retains capture savings, rejected broad rollout and earlier qualification. Main
already had zero packed helper calls: its remaining local/global copying needs a
separate lever. Recursive components still exclude allocation, resize, freeze,
owner transfer, globals, host suspension, indirect calls and mutual recursion.
The broader owned-storage rewrite remains unfinished.

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
