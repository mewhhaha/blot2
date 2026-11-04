# Continue the owned-storage rewrite

## Current frontier

Shared-kernel runtime, Gdev Wasm size and short iterations remain priorities.
Sub-five-second Main, subsecond compilation and 1–2MB Wasm remain unmet.
Reachable throughput targets are 50k source lines in 0.5s, then one million
lines/second.

Memoized `~` parameters/types and `@demand`/`@force` are removed throughout the
compiler, evaluator, runtime, std and source tools. `and`/`or` remain primitive
short-circuit operators. Other deferred work uses ordinary Unit callbacks;
explicit local bindings share computed values. `Maybe.unwrap_or_else` and
`Result.unwrap_or_else` take callbacks. Typed Code retains its latent effects
through an ordinary Unit-to-Unit function carrier. Declaration reachability,
field-demand analysis and resource journal demand events are different concepts
and remain. See [deferred work](docs/compiler/DEFERRED_WORK.md) and
[the evidence](benchmarks/evidence/integration/2026-11-04-demand-retirement.json).

Three fresh uncached LLVM-release pairs measure **5.409 → 5.474s**, with paired
changes **-12 / +302 / +101ms**: no compile-speed gain. Gdev remains
byte-identical at **10,049,963B**. The frozen before compiler uses its frozen
std; the candidate uses the migrated std with the same application source,
settings and runner. Main still contains 9,440 functions and 6.51MB of
local/global instructions. Removing this language feature simplifies the
implementation; it does not solve the representation hill.

`List T` and `[]` remain. The
[packed-sequence pilot](docs/compiler/PACKED_SEQUENCES.md) keeps immutable
construction, concatenation and sequential cursors separate from indexable
mutable Arrays. A standalone native witness packs 100,000 mixed enum elements
into **260,000 bytes**, against **1,200,000 modeled fixed-union bytes**; it
reserves **900,000 bytes**. Five representation tests pass. This is not yet the
production List emitter, nor a measured Blot runtime/Wasm/compile-time win.
Contiguous concatenation copies O(total bytes); repeated concat needs a builder
path or a separately qualified chunk representation.

The final native inventory has **2,949 laws**, all compiled without LLVM. The
migrated engine family has **231 passes and four failures**, each reproduced on
the frozen preceding native binary. The 39-file migrated guest batch has **276
passes and 19 classified baseline failures**. Five new executed laws cover
Boolean short-circuiting, selected callbacks, repeated work and explicit
sharing. Code archive portability and generated Unit-thunk parameter flags have
focused regressions. A migrated native receipt fixture now expects ordinary
callback reuse: both compilers show 0/1/0 reuse for
initial/unrelated/captured-base edits. The final function-syntax development
check passes **8 native / 26 guests** in **28.41s**, including complete native
compilation. Full qualification remains pending; consult the evidence for the
bounded full gate and baseline failures. Types, formatting, Zig lint,
parser/editor, package API and publication dry-run checks pass. Publication was
not performed.

Release compiler SHA256:
`4a2be13d0e1b09816c51cc6aa3ae1059fc3aaf4b8554ceeee323e345b2bdf60c`. Main SHA256:
`8a5bc671b85bba52b8989abe4c2165e26d1e379c659e3db9666dd60ad7e5127b`. A fresh
inspected NVIDIA frame passes the original budgets and matches the preceding
PNG/trace byte for byte. Broader gameplay/software-adapter qualification remains
pending. Pen's normal source bridge still omits inferenceBudget; the bounded
Deno runner builds Main and Pen loads that reviewed artifact. Only Gdev's
language compatibility test source changes in the siblings; Ink/Pen and
application assets remain unchanged. Its broad collection fixture retains the
same fixed-inline-layout admission failure on both compilers.

The
[preceding array-loop measurements](benchmarks/goose/results/2026-11-04-sort-hills.md)
retain merge/quick/Sieve gains, the hash regression, fresh Goose controls and
limited coverage. The
[pinned preceding handoff](https://github.com/mewhhaha/blot2/blob/742f1cae8c76c8380716e17d78ff6ec5f11da681/CONTINUE.md)
retains exact prior qualification and profiling identities. Earlier results do
not qualify this candidate.

## Next representation levers

Integrate one bounded packed List element plan into the owned backend: dense tag
plus active payload, append/freeze, byte-position/count cursors and one terminal
nested scalar tail. Preserve owner lifetime evidence, complete append checks,
exact scalar bits and original budgets. Measure scalar controls, live versus
reserved bytes, bytes copied, construction/traversal time and emitted Wasm. Keep
production status explicit until executed Blot witnesses pass.

For Main, attribute materialization by record shape and operation before
changing representation: construction, call, result, join, loop and row load.
Compare creation-backed immutable `world_storage.FrameAccess` with borrowed
private pointers/lazy field loads against shared semantic shapes and transitive
field demand. Keep backing through helpers/branches/loops and small math records
inline. Target roughly 20% fewer Main bytes or 10% less compile time while
retaining snapshots, checked authority and budgets; reject designs that replace
stores and loads with equivalent work.

The preceding exact-artifact profile records backend 4.430s, checking 0.500s,
lowering 0.124s, validation 0.102s, cumulative backend allocation requests
5.324GB and process RSS 1,110,332KiB. Requested bytes are not peak memory;
overlapping timing families do not add. Scoped backend engine subtimers remain
unavailable.

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

Use Zig 0.17.0 and `-Dllvm=false` for development/native tests. This feature
removal rebuilt the development compiler in 17s and native inventory in 54s; the
final test-only inventory rebuild is recorded in the development check. The
final LLVM release build took about five minutes. Two premature LLVM builds were
stopped; freeze production source before the final release build and keep
ordinary iterations on the native backend.

Use `deno task check:dev --area function-syntax` for this regression family and
`deno task test:compiler` before compiler commits. Full qualification is
separate. Recheck real integration after semantic changes with the tracked
`build_gdev.ts` and `run_pen.py` runners, and inspect the actual PNG. Preserve
unrelated work and existing siblings; no new worktrees. Commit/push coherent
checked batches to main and verify the remote. Environment publication and
upstream comments require explicit requests.
