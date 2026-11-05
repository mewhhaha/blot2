# Compilation repair frontier

The user explicitly requested fixing and recompiling the port. Verification is
active; there is no remaining approval or source-writing barrier. Keep the Zig
compiler, normal toolchain, saved oracle and siblings unchanged.

Checkpoint `36c733f3b5ae4ea23fa93166c37ca38b43faf6e9` is pushed to main. It preserves
recursive checker repairs and executable engine laws; it is not a full compiler build.
Upstream Goose parses roughly 35,700 declarations across 435 files in about
1.1 seconds. Whole-program type checking has not completed successfully.

Use `python3 compiler-goose/tools/check_source.py --phase check --log NAME`.
The runner caps and kills the process group and saves full diagnostics under
`build/goose-port/verification/`. Check mode uses streaming text diagnostics;
JSON diagnostics buffer until completion and hid errors in capped runs.
Check mode stops the process group after the first error; recent failed
iterations take roughly eight to sixteen seconds. One coordinator runs
whole-program checks at a time; backend currently owns the substitution-family
frontier in `check/types.goose`.

The actual build entry remains `compiler-goose/build.py`, with explicit Goose
binary, standard-library directory and 30-second stage caps. Do not claim a
working compiler until C emission, linking and execution have succeeded.

The official repair loop has advanced through capability, usage and task
validation into substitution scratch ownership (check99). Opaque inference
frames hold numeric ranges, while borrowed instruction/type inputs pass directly
down helpers. Usage exit/staging frames use numeric indices; direct child
visitors avoid storing recursive borrows. Named scope frames contain only scalar
identity/view/parent data in a reusable pool. Astra reviewed identity, scope,
16-view ordering, work charging, depth bounds and all cleanup paths without
finding an introduced regression. This is static review, not runtime parity.
Whole-program parsing continues to pass at about one second.
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

Runtime recoverable physical OOM and retention parity remain separate known
production requirements; null/unavailable metrics do not close them.
