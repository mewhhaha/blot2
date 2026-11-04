# Safe local sinking qualification

Issue #24 adds a bounded, single-use scalar plan. A producer using stable local
or parameter inputs, with no effects, traps, divergence, allocation, or unknown
behavior, can run at its sole read. The planner rejects captures, carried and
merged bindings, repeated loops, unsupported control flow, and bindings already
owned by another backend plan. A scalar consumed directly by the next `if`
condition or `return` is inlined at the same eager evaluation point, even when
its producer can trap or is an opaque call.

The executed-Wasm regression checks both codegen tiers, taken and skipped
branches, lexical rebinding, aliases, loop reads, eager traps and effects, and
an opaque named call. The native planner law checks a function-exit wrapper,
loop rejection, trap rejection, prepared-binding exclusion, and direct eager
consumption. The full gate passed 2,502 native tests and 1,615 guest tests;
`deno task lint:zig` reported zero findings.

Generated code for the small `heavy` fixture in
`safe_local_sinking_execution.test.ts` places `i32.mul` after the conditional
branch. The candidate's internal function declares zero temporary locals; the
pre-change version stored the producer before the branch. Both versions have
two Wasm functions (body and export wrapper), so the sink adds no thunk.

The paired benchmark is reproducible with
`scripts/bench_safe_local_sinking.ts BASELINE_BLOTC CANDIDATE_BLOTC` under
`deno run --allow-read --allow-write --allow-run`. Both compilers were LLVM
release builds from the same toolchain; the baseline source is `9cae6f7` and
the candidate is this change. The fixture has 48 scalar operations and skips
their result on 90% of calls. It uses nine alternating fresh build pairs and
31 alternating runtime pairs of 500,000 guest calls each, after warmup.

| Metric (median) | Baseline | Candidate |
| --- | ---: | ---: |
| Guest-call wall time per 500,000 calls | 23.04 ms | 20.48 ms |
| Paired candidate/baseline runtime ratio | — | 0.890 |
| Compiler-reported build time | 1.621 ms | 1.452 ms |
| Generated Wasm bytes | 441 | 435 |
| Compiler allocation requests | 537 | 539 |

Compiler time is short enough that these samples do not establish a compile
speedup. Allocation requests here are compiler-side, not guest heap traffic.
The runtime result applies to this branch-heavy fixture, including the guest
call ABI and harness overhead; it is not a general application speed claim.
