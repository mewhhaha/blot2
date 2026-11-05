# Compilation repair frontier

The user explicitly requested fixing and recompiling the port. Verification is
active; there is no remaining approval or source-writing barrier. Keep the Zig
compiler, normal toolchain, saved oracle and siblings unchanged.

Checkpoint `25a8da6b6f32d48bf2a11f096d2e5e9f334614a7` is pushed to main. It preserves
unification scratch and mutable rank-state repairs; no successful whole compiler
executable exists yet.
Upstream Goose parses roughly 35,700 declarations across 435 files in about
1.1 seconds. Whole-program type checking has not completed successfully.

Use `python3 compiler-goose/tools/check_source.py --phase check --log NAME`.
The runner caps and kills the process group and saves full diagnostics under
`build/goose-port/verification/`. Check mode uses streaming text diagnostics;
JSON diagnostics buffer until completion and hid errors in capped runs.
Check mode stops the process group after the first error. The later source
frontier now takes about 60–65 seconds to reach; current checks use a bounded
90-second cap. A no-error timeout is not a pass. Exactly one coordinator runs
whole-program checks. Checker currently owns package admission's owner-ID cache
frontier after staging variable ranges and row frames (check128).

The actual build entry remains `compiler-goose/build.py`, with explicit Goose
binary, standard-library directory and 30-second stage caps. Do not claim a
working compiler until C emission, linking and execution have succeeded.

The official repair loop has advanced through solver, projection and staging
validation. Public Principal retains its existing layout/API; fresh recursive
proofs use scalar state with borrowed roots passed directly. Static resolver
policies preserve real projection behavior. Staging variables use their original
same-module graph ranges; scalar row/scope frames preserve parent lifetimes,
charges and cleanup. Astra's static comparisons found no introduced regression;
these are not runtime qualification. Whole-program parsing passes in about one
second. The new scalar admission representation remains under implementation.
Scoped tests pass for lexer, interning, graph
SCCs, arena ownership, byte/hash/JSON helpers, maps and buffers, wire/IR emission,
native JSON and WGSL fixtures. A fresh exact C-host startup probe passes with
the unchanged native shim and official runtime.
Saved probe sources/commands/logs are under
ignored `build/goose-port/`; these do not qualify the whole compiler.

Recursive capability analysis now keeps scalar Builder state and passes its
borrowed module/store/owner inputs directly. Nested readers own separate pooled
callable buffers. Astra's source comparison found preserved module selection,
owner identity, traversal counters and cleanup. The input-body path restores
the native 1 MiB logical scratch limit. Integrated runtime parity remains
pending; reaching a later type error is not execution evidence.

Focused iteration no longer loads the entire compiler for two engine laws.
Copy coalescing accepts its actual type/tape inputs: the import closure falls
from 431 files to nine and official C emission, native compilation and executed
forwarding/ownership/invalidation/reuse laws finish below 0.2 seconds. The
import-free type-evidence schema preserves the exact original namespace and
declarations, cutting interning laws from 431 files to seven: checking takes
0.064 seconds and native growth/interning/quantifier/reuse laws pass. A separate
global Store.view execution passes in 0.047 seconds. Evidence is in
`coalesce-leaf-*-03.log` and `expectation-schema-check/` under the ignored build
directory. Tracked laws and the bounded native runner are now in `tests/` and
`tools/test_engines.py`; a fresh root run with clang-23 passes both below one
second total. These are measured leaf improvements, not whole-build timings.

Canonical ownership repairs include explicit typed empty slices, finite lazy
JSON/packet adapters, enum aliases qualified to original definitions, safe
pool free/reallocation receipts, numeric process-local owner slots, pooled
planning/query buffers and ordered bootstrap globals. Copied packets omit the
new process-local Chunk/Loops/Auxiliary slot fields.

The installed upstream compiler remains selected and unchanged. Three private
checker experiments passed their small differential fixtures but did not meet
the frozen-prefix acceptance/time target. The private O0 and official O3 builds
also prevent attributing timing differences to the algorithm changes alone.
No experiment is accepted into the toolchain. Latest rejected-run evidence:
`build/goose-port/fast-goose-positive/decision.json`; prior source/checkpoint
history retains the other measurements. Do not rebuild these candidates without
a new measured lever.

The official C build attempts emitted the runtime but did not reach C program
output: 60-second caps were incomplete. Build125 used a longer window and stopped
immediately on the next source diagnostic at 61.464 seconds. The late profile
(`official-profile-123`) identified RootCandidates/CanContain under recursive
solver-summary application, before IR/emission. A private matched-O3 compiler
build itself hit its 75-second cap and produced no candidate; see
`fast-goose-o3/decision.json`. No upstream or installed binaries changed.

The hot composite cache now accesses its canonical generation-checked state
directly. Baseline/candidate focused execution laws match, including snapshots,
aliases and reuse; both take about 0.15 seconds. This has no demonstrated whole
compile-time win (both whole attempts hit their caps). Keep that distinction.

Runtime recoverable physical OOM and retention parity remain separate known
production requirements; null/unavailable metrics do not close them.
