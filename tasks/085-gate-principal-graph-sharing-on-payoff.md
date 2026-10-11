# 085 — Gate principal-graph sharing on payoff

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** none.
- **Originating requirements:** discovered while qualifying task
  [024](024-apply-general-body-interface-cutoff.md); PLAN: Hill 6 / cheap edits
  and Hill 7 / semantic graph sharing. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Keep the open-diamond benefit of shared principal graphs without taxing ordinary
generic programs: inquire about and import principal graphs only where sharing
pays.

## Starting point

A separate session bisected a 2.3× retained-edit slowdown on the current gdev
checkout (`632b461` 850–910 ms CPU, `fbe28c8` 2000–2140 ms) to `099e700` "Share
owned inferred principal graphs without unfolding open diamonds". Its parent
`f7be6e7` edits in 770–900 ms with inference 388–553k µs; `099e700` takes
1560–1860 ms with inference 1.14–1.33M µs; fresh functions are equal. With
`Session.reuse_principal_graphs = false`
([core_eval.zig](../zig-native/src/core_eval.zig)) `099e700` returns to 790–880
ms. `ClosureRegion.collect` builds a principal graph for every admitted
first-order global body with unresolved parameters or result (`principalGraph`,
`describePrincipal` and `importPrincipal`), and `retainOpenPrincipal` walks
every reachable callee; keeping an open edge invalidates call reads and marks
the tape unknown. The commit's own benchmark is a synthetic factory diamond.

## Implementation checklist

- [ ] Count principal-graph builds, imports, deferrals and open retentions in
      the work counters.
- [ ] Build or import a graph only when it can be reused (for example the same
      target imported twice in a revision, or a detected diamond), keeping exact
      results and diagnostics.
- [ ] Avoid call-read invalidation and unknown tapes where the retained graph
      does not need them, so retained reuse is not defeated.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Pair the factory-diamond benchmark from `099e700` and generic workloads,
  including a large generic program, against the current compiler and `f7be6e7`.
- Record gdev cold and retained-edit CPU and inference when gdev is available.

## Acceptance criteria

- [ ] The diamond workload keeps its measured benefit.
- [ ] Ordinary generic workloads are no slower than with sharing disabled, with
      paired evidence.
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
