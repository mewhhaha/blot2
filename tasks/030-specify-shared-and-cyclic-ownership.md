# 030 — Specify shared and cyclic ownership

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / runtime ownership;
  DEMANDS: Effects and lifetime. Sources: [PLAN.md](../PLAN.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify shared reference counting, roots, suspension, destruction and a complete
cycle-reclamation strategy.

## Starting point

[zig-native/CONTRACT.md](../zig-native/CONTRACT.md) describes tracing, local
lifetime groups and the State → closure → cached-demand cycle.
[runtime_layout.zig](../zig-native/src/runtime_layout.zig),
[arena_runtime.zig](../zig-native/src/arena_runtime.zig) and
[tests/arena_gc_execution.test.ts](../zig-native/tests/arena_gc_execution.test.ts)
are the current layout, allocator and counterexample boundaries.

## Implementation checklist

- [ ] Define strong/borrowed references, root ownership, typed retain/release,
      destruction order, reentrancy and host-call boundaries.
- [ ] Choose and specify a cycle strategy covering reachable and discarded
      cycles, including suspended frames and long-lived memo results.
- [ ] Preserve strong demand memo fields: clearing State must not erase a
      completed result or weaken a live edge.
- [ ] Document the transition with tracing retained until replacement
      qualification, including failure cleanup and observable acceptance
      examples.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Trace reference graphs for shared collections, returned closures, State-demand
  cycles and suspension/cancellation.
- Review counterexamples for naive RC, weak memo fields, recursive destruction,
  double release and abandoned host calls.

## Acceptance criteria

- [ ] Durable ownership documentation settles representations, APIs, lifecycle,
      cycle algorithm and compatibility.
- [ ] Tasks 031–035 have measurable memory and behavioral gates that preserve
      the existing cycle counterexample.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
