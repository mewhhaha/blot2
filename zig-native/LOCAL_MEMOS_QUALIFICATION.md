# Local memo qualification (037)

037 extends the existing local-demand emitter to bounded structured callee
bodies. It adds no second memo runtime. Creation-time lexical binding versions
stay in the caller; first execution of a demand computes and commits its result.
Ready/result locals belong to the call site, outside callee loops, and reset on
each dynamic call. Reference-only aliases share those locals.

The preparation proof still bounds work to 96 shared nodes, 64 ordinary
bindings, 16 parameters and 64 alias steps. It admits structured branches,
range/List/Array and forever loops, early returns/breaks, and primitive
collection operations that do not invoke callbacks. Loop reads saturate at
repeated. Owned task 036 summaries supply dynamic never/once/repeated counts;
unknown falls back to the bounded proof, and escaping declines. No solver IDs or
scratch pointers enter durable plans.

Cancellation borrows an owned, flattened snapshot of the force-site cleanup
actions while evaluating through the lexical emitter. This includes callee List
scratch and avoids a cyclic parent link. Managed cached results join typed
forever-loop collection roots, including enclosing admitted calls. Uninitialized
managed result slots are zero; scalar reads require the ready bit. Normal
completion precedes the ready-bit store.

## Frozen inputs

- Incoming revision: `b9cbdd2b7ad7780fd27c1775d05bc76d57e2d8ca`. This includes
  qualified 031; it precedes the independent 043/050 implementation.
- Zig: `0.17.0`; both binaries use the standard LLVM fast release task.
- Ordinary binary:
  `1ea2d0594b5dcbd183d807844867f07a02af6172a9c0ffff8dfb604414201a19` (37,716,512
  bytes).
- Local-memo binary:
  `e6a1cd2129b7ee8fc492ed86f2e071e751b4170804c4dcb60942a1cc2d11ca85` (37,738,168
  bytes).
- Reproduction: [bench_local_memos.ts](../scripts/bench_local_memos.ts). Run
  `taskset -c 6 deno run -A scripts/bench_local_memos.ts BASELINE CANDIDATE OUTPUT`.

Raw inputs, all distributions, source/binary/script SHA-256 pins and logs are
retained in `build/bench/local-memos/` in the integration workspace. The
original worktree artifacts are
`/var/tmp/blot2-local-memos/build/bench/qualified/`. Telemetry adds exports
only; timed Wasm uses the original bytes. Allocation traffic counts arena block
bytes, and arena extent includes reserved free blocks.

## Focused verification

- `zig build test -Dllvm=false -Doptimize=safe -Dtest-filter="local memo"`: 19
  tests pass, including four new admission/fallback/exhaustion/ownership laws.
  Full allocation-failure sweeps cover scalar aliases, List cleanup snapshots,
  managed forever-loop roots and frozen Core.
- 41 focused executed-Wasm laws pass across local memos, existing demand
  inlining, forwarding, summaries, completion, persistent demands and recursion.
- The eight new laws pass with the final release binary. They cover no arena or
  thunk table, inside/outside nested creation, aliases, conditional first reads,
  zero iterations, breaks, sync/JSPI suspension, repeated cancellation, provider
  fallback, managed collection pressure, traps, F32 results, stable-type
  imported body edits and failed-revision recovery.
- Semantic laws also pass against the ordinary-cell baseline; the new no-arena
  assertion intentionally describes only the candidate.
- Removing memo roots makes the pressure law return a corrupted Array; restoring
  roots passes. This negative control proves the law reaches the new root path.
- Zig analyzer: 327 files, zero findings. Deno checks, formatting and diff
  checks pass.
- Parent owns the mandatory combined full compiler/analyzer gate before
  committing; no separate full gate was run for this handoff.

## Runtime measurements

AMD Ryzen 7 3800X, CPU 6 affinity, 15 alternating pairs per case after warmup.
Host load was 27.62 → 29.05 while other compiler work ran. These are loaded-host
measurements, not an isolated performance floor. Raw samples retain the tails.
The combined scalar module shrinks from 3,573 to 466 bytes and has no
arena/table. The single outside-loop example shrinks from 3,345 to 209 bytes.

| Creation | Iterations | Ordinary CPU µs median / p90 | Memo CPU µs median / p90 | Ordinary allocation traffic | Memo traffic |
| -------- | ---------: | ---------------------------: | -----------------------: | --------------------------: | -----------: |
| outside  |          0 |                0.049 / 0.186 |            0.020 / 0.058 |                        64 B |          0 B |
| outside  |          1 |                0.062 / 0.095 |            0.019 / 0.020 |                        64 B |          0 B |
| outside  |        128 |                0.634 / 0.692 |            0.166 / 0.176 |                        64 B |          0 B |
| outside  |     16,384 |              60.797 / 64.242 |          11.336 / 11.820 |                        64 B |          0 B |
| inside   |          0 |                0.018 / 0.047 |            0.013 / 0.058 |                         0 B |          0 B |
| inside   |          1 |                0.056 / 0.057 |            0.014 / 0.014 |                       128 B |          0 B |
| inside   |        128 |                5.115 / 6.380 |            0.392 / 0.431 |                    16,384 B |          0 B |
| inside   |     16,384 |            634.188 / 712.250 |          47.219 / 58.625 |                 2,097,152 B |          0 B |

Outside creation uses constant ordinary traffic as iterations grow; the
candidate removes that cell entirely. Inside creation resets its memo each
iteration and removes ordinary traffic proportional to creation count. At 16,384
creations, ordinary arena extent is 2,162,432 bytes; the candidate requires no
linear memory. Scalar result slots and initialization are static Wasm locals,
not allocations.

## Compiler costs

Seven alternating pairs measure fresh process builds and retained project first,
body edit, no-op, rejection and recovery separately. Edits keep public types
stable and move ordinary arithmetic in the imported callee.

| Phase    | Ordinary wall ms median / maximum | Memo wall ms median / maximum |
| -------- | --------------------------------: | ----------------------------: |
| fresh    |                     2.257 / 2.459 |                 2.034 / 2.298 |
| first    |                     1.675 / 3.177 |                 1.347 / 1.712 |
| edit     |                     1.369 / 1.711 |                 0.894 / 1.385 |
| no_op    |                     0.500 / 1.092 |                 0.487 / 9.342 |
| failure  |                     0.509 / 0.697 |                 0.455 / 2.433 |
| recovery |                     1.362 / 1.560 |                 0.828 / 1.569 |

Fresh native total time is 907 → 739 µs; requested peak is 76,016 → 38,377
bytes, traffic 193,960 → 117,651 bytes, and allocation calls 814 → 574. Retained
edit output has two runtime functions instead of 19 and retains 2,517 rather
than 19,275 bytes of optimized bodies. Both paths build one demand summary,
visit 38 summary nodes, and validate one dependency on this edit. Retained
allocation traffic is not exposed by this client API; its table reports wall
time only. The candidate no-op maximum of 9.342 ms is preserved rather than
hidden by the 0.487 ms median. Small timings and tails are sensitive to the
loaded host.

## Conservative limits

Returned/captured pending demands still use ordinary cells. Demand-valued branch
merges and loop carries, provider/handler boundaries inside the callee,
arbitrary callbacks, source-dispatched scalar operations and recursive/exhausted
inline proofs decline. Primitive generation callbacks also decline. This task
does not eliminate returned-demand factories or recognize declaration names. The
ordinary runtime cell remains the semantic fallback, including cancellation
retries and terminal failures of persistent demands.

The qualification establishes structured local lowering and the measured hill;
it does not claim universal cell elimination or universal timing improvements.

## Integrated qualification (12 October 2026)

The final compiler/client gate and source/binary pins are in
[the persistent-root qualification](PERSISTENT_ROOTS.md#integrated-qualification-12-october-2026).
Reference memos reserve a caller-frame owner before entering a callee loop and
publish their first result into it before readiness. Iteration retirement can
then remove the original owner while later forces share the cached value.
Forwarding uses the existing caller link; no extra parent pointer is stored on
Emitters. The allocation-pressure law proves actual object retirement and exact
Array contents, then verifies zero roots/leases after reset. The earlier cost
tables retain their isolated binary pins and are not substituted for final
integration measurements.
