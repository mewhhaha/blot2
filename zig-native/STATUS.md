# Zig compiler status

Blot's production compiler is handwritten Zig 0.17. Deno hosts the public
compiler API, formatter and Wasm guest API. The latest full-qualified source
freeze passes 2,223 native laws, 1,404 guest/client tests and all 455 Zig
analyzer files with zero findings. It includes 1,366 complete allocation-failure
sweeps. Exact source/executable pins and logs are in
`build/bench/complete-program-20261015/final-proof-repaired-gate/qualified-pins.json`.
Later uncommitted continuation changes await their combined final gate;
[language qualification](LANGUAGE_QUALIFICATION.md) maps the qualified language
contracts and their separate costs. Language behavior remains defined by
[the guide](../compiler/guide.md), with ownership rules in
[CONTRACT.md](CONTRACT.md).

The default path shares frontend callee schemes, infers closed first-order
callees through an iterative queue, and reuses complete semantic queries and
executable fragments under separate dependency checks. Inference collection no
longer consumes the executed-code depth budget: annotated chains at 300 and
1,000, a generic chain at 300 and diamond N=16 compile and execute.
Predicate-free source schemes and qualified parametric callback obligations
admit independent higher-order jobs without unfolding complete transitive
bodies. Recursive components use bounded joint inference. Incomplete callback or
capture evidence retains ordinary checking; the captured-project region and
latency targets remain open. [Call summaries](CALL_SUMMARIES.md) records the
qualified boundaries and measurements.

`std/path` provides pure getters/setters, identity and composition,
type-changing writes, and modification with an effectful transform. Staged
accessors retain unused polymorphic fields. Bounded inlining and private
functions preserve callback effect labels without treating a partial layout as a
closed semantic proof.

Known local demand-forwarding chains can use control flow and local memo state
within a shared 96-node proof budget. Indirect, recursive and escaping demands
retain runtime cells. Provider cancellation permits a later force to retry;
recursive force fails, and traps or host exceptions leave persistent demand
cells terminal. Sync and JSPI execution share this contract.

Region solvers and checker scratch use independent resettable arenas, retaining
at most 64 MiB per pool. Published results keep durable owners. Automatic CLI
and project-server restart caches contain validated checkpoint candidates;
missing, unavailable, incompatible and corrupt caches fall back to compilation.
Explicit checkpoints remain supported. No evaluated values are trusted merely
because a checkpoint file exists.

The qualified [List span change](LIST_TRAVERSAL.md) removes redundant leaf
validation from direct packed-row loops. Its three-field fold fixture uses about
24% less CPU against the preceding packed compiler, with unchanged guest memory.
Full traversal and cursor regression closure remain open.

## Historical demand-forwarding measurements

These are the earlier qualified demand-forwarding measurements on the frozen,
private 394,294-byte gdev workload, from seven alternating pairs. CPU is child
user plus system time; filesystem caches and machine load are uncontrolled.
Fresh compilation has persistence disabled. Retained population is measured
separately from edits. Earlier batches and different workloads are not
comparable timings. They do not describe the later 415-input captured project or
establish its current cold/edit targets.

| Measurement                          |                           Current value |
| ------------------------------------ | --------------------------------------: |
| Fresh CLI CPU                        |                                  647 ms |
| Retained population CPU              |                                  740 ms |
| First retained literal edit CPU      |                                  150 ms |
| Subsequent edit/revert CPU           |                                  140 ms |
| No-op CPU                            | Below the process-accounting resolution |
| Fresh requested allocation           |                                321.2 MB |
| Peak requested live memory           |                                 78.9 MB |
| Live requested memory after teardown |                                       0 |
| Inference regions                    |                                   2,036 |
| Largest region, scopes               |                                   8,041 |
| Solver constraint visits             |                                  35,215 |
| Occurs-check visits                  |                                  42,410 |
| Wasm bytes                           |                                 629,339 |

Wasm matched between compilers and between fresh and retained phases. Against
the preceding variable-cache compiler, fresh CPU was 644 / 647 ms, population
was unchanged at 740 ms, first edit was 160 / 150 ms and subsequent edit was
unchanged at 140 ms. Allocation and work counters are unchanged. No
compile-speed gain is claimed. Raw samples and binary hashes are in ignored
`build/bench/demand-forwarding-qualified`. Requested allocation is cumulative
allocator traffic, not process RSS or guest memory. The 500 ms cold, under-100
ms retained-edit and under-100 MB cumulative allocation targets remain open; the
stricter literal-edit target is 30 ms.

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

The shared semantic query table and its portable archives are implemented.
Selected, principal, refinement, constant and executable records retain separate
proof obligations. Higher-order and recursive jobs retain bounded ordinary
fallbacks when their inputs are incomplete. The captured-project latency and
allocation targets remain open. Semantic workers stay opt-in until paired CPU
and wall measurements justify a default change. A remote CI run for the final
local source has not occurred; the continuation remains uncommitted.

The current continuation replaces ordinary tracing with counted strong edges,
journal/invocation leases and nonmoving trial deletion for real cycles. Its
latest result-slot transfer and iterator changes still require the final common
release and performance qualification. General iterator allocation, broader
fusion/SIMD and complete retained-body/constant coverage also remain open. See
[standard-library guidance](../std/PERFORMANCE.md),
[language evolution](LANGUAGE_EVOLUTION.md), [demand evaluation](DEMANDS.md) and
[the architecture](ARCHITECTURE.md) for current contracts and limits.
