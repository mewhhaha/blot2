# Compilation repair frontier

The user explicitly requested fixing and recompiling the port. Verification is
active; there is no remaining approval or source-writing barrier. Keep the Zig
compiler, normal toolchain, saved oracle and siblings unchanged.

Checkpoint `ec5f0a96e201262f95bf44686c996ace437fa538` is pushed to main. It preserves
the engine dependency cuts and pooled-view repairs; it is not a full compiler build.
Upstream Goose parses roughly 35,700 declarations across 435 files in about
1.1 seconds. Whole-program type checking has not completed successfully.

Use `python3 compiler-goose/tools/check_source.py --phase check --log NAME`.
The runner caps and kills the process group and saves full diagnostics under
`build/goose-port/verification/`. Check mode uses streaming text diagnostics;
JSON diagnostics buffer until completion and hid errors in capped runs.
Check mode stops the process group after the first error; recent failed
iterations take four to eight seconds. One coordinator runs whole-program
checks at a time; backend currently owns this loop while errors remain in its files.

The actual build entry remains `compiler-goose/build.py`, with explicit Goose
binary, standard-library directory and 30-second stage caps. Do not claim a
working compiler until C emission, linking and execution have succeeded.

The official repair loop has advanced through semantic worker packet handling
and capability validation into scoped-backend type shapes (check60). Optimizer growing instruction views pass
through helpers rather than being stored in analysis records; module
copy-coalescing inputs use numeric tape ranges. Whole-program parsing passes
after recursive-checker repairs (35,798 declarations, 436 files, 1.002 seconds).
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

Astra's private toolchain experiment is isolated under
`build/goose-port/fast-goose/`. The first candidate hash is
`b493cdeac83a1833d645503cf5eeb7d5d5f1c32ffa64ee9634719480fa7502b3`.
Readiness hash traversal plus successful-graph descendant caching passes 12
actual-header laws, 37 differential frontend fixtures and eight runtime laws.
Neither this candidate nor a second private global-narrowing experiment
demonstrated a whole-Blot timing win within matched 30-second caps. A newer
frozen-prefix comparison reaches an official diagnostic in 7.296 seconds while
the second private candidate hits its 12.244-second cap without a diagnostic;
this also supplies no performance or acceptance result. Neither
experiment is accepted into the toolchain. Keep the installed compiler and
upstream checkout intact.

Runtime recoverable physical OOM and retention parity remain separate known
production requirements; null/unavailable metrics do not close them.
