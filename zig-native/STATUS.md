# Zig compiler status

Blot's production compiler is handwritten Zig 0.17. Deno hosts the public
compiler API, formatter and Wasm guest API. The current compiler passes the
native suite, all 565 guest/client tests and the zero-finding Zig analyzer gate.
Language behavior remains defined by [the guide](../compiler/guide.md), with
ownership rules in [CONTRACT.md](CONTRACT.md).

The default path shares frontend callee schemes, infers closed first-order
callees through an iterative queue, and reuses complete semantic queries and
executable fragments under separate dependency checks. Inference collection no
longer consumes the executed-code depth budget: annotated chains at 300 and
1,000, a generic chain at 300 and diamond N=16 compile and execute. Higher-order
and recursive-component summaries remain incomplete.

Region solvers and checker scratch use independent resettable arenas, retaining
at most 64 MiB per pool. Published results keep durable owners. Automatic CLI
and project-server restart caches contain validated checkpoint candidates;
missing, unavailable, incompatible and corrupt caches fall back to compilation.
Explicit checkpoints remain supported. No evaluated values are trusted merely
because a checkpoint file exists.

## Current measurements

These are the latest qualified arena measurements on the frozen, private
394,294-byte gdev workload, from five alternating pairs. CPU is child user plus
system time; filesystem caches and machine load are uncontrolled. Fresh
compilation has persistence disabled. Retained population is measured separately
from edits. Earlier batches and different workloads are not comparable timings.

| Measurement                          |                           Current value |
| ------------------------------------ | --------------------------------------: |
| Fresh CLI CPU                        |                                  847 ms |
| Retained population CPU              |                                  960 ms |
| First retained literal edit CPU      |                                  180 ms |
| Subsequent edit/revert CPU           |                                  170 ms |
| No-op CPU                            | Below the process-accounting resolution |
| Fresh requested allocation           |                                344.0 MB |
| Peak requested live memory           |                                 88.6 MB |
| Live requested memory after teardown |                                       0 |
| Inference regions                    |                                   2,597 |
| Largest region, scopes               |                                   7,369 |
| Solver constraint visits             |                                  53,915 |
| Occurs-check visits                  |                                  52,251 |
| Wasm bytes                           |                                 629,339 |

Wasm matched between compilers and between fresh and retained phases. Against
the preceding scratch-buffer implementation, requested allocation fell 13%, peak
live memory rose from 59.2 MB, and cold CPU was essentially unchanged. Raw
samples and binary hashes are in ignored `build/bench/region-pooled-arenas`.
Requested allocation is cumulative allocator traffic, not process RSS or guest
memory. The 500 ms cold, under-100 ms retained-edit and under-100 MB cumulative
allocation targets remain open; the stricter literal-edit target is 30 ms.

## Building and verification

Check `zig version` before a build batch. Use `deno task build:compiler` for
release builds and `deno task build:compiler:dev` during incremental
development. `deno task test:compiler` runs native semantic/ownership laws and
executed-Wasm, client, dependency, checkpoint and retained-revision tests.
`deno task lint:zig` requires zero findings. Native filtering uses
`zig build test -Dtest-filter=TEXT` from `zig-native/` and imports the complete
suite before applying the filter.

`deno task bench:compile --baseline OLD_BLOTC --candidate NEW_BLOTC --runs 5`
checks output equality and measures fresh, population, first edit, subsequent
edit and no-op phases. Add `--restart-cache` to measure isolated cold cache
population and process restart. The harness verifies the private gdev snapshot
against `scripts/bench/gdev-manifest.json`; never commit that snapshot. Without
it, the synthetic corpus still runs. `blotc build ... --profile` reports phase
and region timings; deterministic work counters accompany compilation records.

## Remaining boundaries

Canonical specialization queries, general higher-order/SCC summaries,
variable-indexed solver worklists, changed-only revision metadata and the
unified reuse table remain open. Semantic workers stay opt-in until paired CPU
and wall measurements justify a default change. The first remote run containing
the new analyzer workflow has not occurred; local milestone commits have not
been pushed.

Runtime ownership still uses tracing for dynamic graphs, including real cycles
formed by State, closures and cached demands. Shared RC and ownership of
escaping or suspended values must preserve those cycles before tracing can be
removed. Packed List traversal, generic iterator allocation, broader
fusion/SIMD, ragged builders and rolling/summary reductions still need work. See
[standard-library guidance](../std/PERFORMANCE.md),
[language evolution](LANGUAGE_EVOLUTION.md), [demand evaluation](DEMANDS.md) and
[the architecture](ARCHITECTURE.md) for their current contracts and limits.
