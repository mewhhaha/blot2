# Local callback demand elimination

A bounded complete use proof admits immutable lexical closures and their local
aliases inside an admitted demand body. It checks every invocation and capture;
returning, storing or passing a callback through an unproved route declines the
whole local proof. Captured demands keep the creation's existing ready/result
locals. Several callbacks and loop iterations share those locals, while a new
creation resets them. No callback descriptor, environment or demand cell is
materialized for an admitted callback.

The proof uses the existing limits: 96 visited nodes, 64 local bindings/alias
steps and 16 parameters. It can follow bounded ordinary local named helpers,
including helpers without demand parameters. Recursive, exhausted, computed,
foreign or parameter-carried callback routes retain ordinary shared cells.
Provider/request bodies and unsupported metadata also retain that route.

Application preparation records the exact lexical closure and resolved arrow.
Emission maps its type and effect-row binders from that arrow, then uses the
caller's immutable binding versions, cleanup chain, provider and shared memo
slots. Generic U32/F32 callbacks keep their actual machine types. The new
application locator fits existing padding; no Emitter field or map is added.
Managed memo values keep the caller-frame owner established by task 032.

Two focused native/OOM laws preserve immutable Core while exercising callback
admission and type/row specialization. Nine executed laws cover zero iterations,
aliases and loops, once-per-creation sync/JSPI effects, immutable snapshots,
polymorphism, strong Array retirement under allocation pressure, returned/stored
fallback callbacks, source/compiled imports, stable-type edits, checkpoints and
failed-edit recovery. The isolated Fast candidate passes all eight unchanged
allocation budgets; the analyzer checks 339 files with zero findings. Root owns
the required full gate on the final integrated batch; this focused evidence is
not that gate.

## Isolated measurements

Incoming source is qualified implementation `2798ff9`, staged tree
`6064c8e2d114bfb39ab3c78d5c0b295f51f1be15`. Its Fast executable SHA-256 is
`b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`. The Zig
0.17.0 Fast / LLVM candidate is
`fd817bfd8396a6118a5b6be9bbc01a6fdd3f599927cc20f8729645cca83316c7` (40,352,168
bytes), compiler identity
`53cdd4871851e5d0c2b12f2d88f2d6ff90668bc67825db447d1c1fdb6d1bef54`. It was built
with `deno task build:compiler`.

Run
`deno run -A scripts/bench_local_memos.ts BASELINE CANDIDATE OUTPUT
--callbacks`.
The scalar fixture invokes two known callbacks sharing one captured demand.
Fifteen runtime samples per variant use original guest bytes; a separate
export-only telemetry copy reports allocation. CPU 5 was pinned; host load was
2.08 → 2.15. At 16,384 iterations:

| Creation     | Baseline → candidate CPU per invocation | Allocation traffic baseline → candidate |
| ------------ | --------------------------------------- | --------------------------------------- |
| Outside loop | 907.06 → 5.50 µs                        | 192 → 0 bytes                           |
| Inside loop  | 8,514.25 → 34.50 µs                     | 4,194,304 → 0 bytes                     |

The fixture's Wasm shrinks from 5,506 to 521 bytes. Candidate has no memory or
function table section; this is a scalar fixture result, not a claim about all
captured demands. Zero and one-iteration cases also execute the expected values.
All sixteen corresponding development/release guest artifacts are byte equal,
which validates screening runtime changes before rebuilding the native release.
Compiler allocation/elapsed comparisons use release against release.

Seven alternating compiler pairs preserve executed results through fresh,
retained, edited, no-op, failed and recovered builds. Median native fresh
elapsed time is 880 → 705 µs; requested allocation is 296,006 → 162,052 bytes
and peak requested memory 114,050 → 60,959 bytes, with zero live bytes after
teardown. The short fixture does not establish a whole-program compiler speedup.
Raw source/binary/guest/harness hashes and distributions remain ignored under
`build/bench/known-callback-memos/`.
