# 085 — Gate principal-graph sharing on payoff

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `7d64435`.
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

- [x] Count principal-graph builds, imports, deferrals and open retentions in
      the work counters.
- [x] Build or import a graph only when it can be reused (for example the same
      target imported twice in a revision, or a detected diamond), keeping exact
      results and diagnostics.
- [x] Avoid call-read invalidation and unknown tapes where the retained graph
      does not need them, so retained reuse is not defeated.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Pair the factory-diamond benchmark from `099e700` and generic workloads,
  including a large generic program, against the current compiler and `f7be6e7`.
- Record gdev cold and retained-edit CPU and inference when gdev is available.

## Acceptance criteria

- [x] The diamond workload keeps its measured benefit.
- [x] Ordinary generic workloads are no slower than with sharing disabled, with
      paired evidence.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `7d644355573b7f4934a9b41348275ca9fc21f79e` (compiler milestone).
- Implementation: new work counters report principal-graph builds, imports and
  retained open edges. Timers and a gdb sampling profile showed that describing
  and importing graphs cost a few milliseconds per gdev edit, while retained
  open edges left alias types open so `solveDataAliases` re-walked them (about
  70 ms per edit). Restricting imports had no measurable effect, so they stay;
  `retainOpenPrincipal` now keeps an edge open only when the callee's normalized
  call graph has at least twice as many call paths as distinct bodies. Trees
  collect ordinarily with equal judgments; diamonds keep the residual edge, so
  unknown tapes and call-read invalidation now occur only there.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 632 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 310 files. A native law
  compares judgments with and without sharing for callee chains and diamonds and
  checks retention and counters; it fails with the old unconditional retention.
- Comparison: six alternating triples on the frozen gdev copy at load 17.7–23.3:
  retained edits cost 1.11 × (1.02–1.12) with sharing as committed and 0.99 ×
  (0.94–1.00) with sharing off, relative to the candidate; inference 752k µs
  versus 870k (as committed) and 744k (off). The factory diamond keeps its
  benefit (13.5 ms at depth 12 versus 1630 ms with sharing off); public examples
  are unchanged within 1–3%.
- Remaining limitations: graph descriptions and imports still run where
  eligible; the open-type re-walk itself is not fixed, only avoided where
  retention does not pay. The summary-job inference growth since `f7be6e7` is
  task [088](088-restore-summary-job-inference-cost.md).
- Durable record:
  [open-principal payoff](../zig-native/CALL_SUMMARIES.md#open-principal-payoff-11-october-2026),
  [gdev distributions](../zig-native/qualification/principal-payoff-gdev.csv),
  [public results](../zig-native/qualification/principal-payoff-public.jsonl)
  and [pins](../zig-native/qualification/principal-payoff-pins.json).
