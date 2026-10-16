# 036 — Summarize demand control flow

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** [007](007-infer-recursive-components-jointly.md),
  [014](014-specify-unified-query-table.md)
- **Originating requirements:** DEMANDS: Compiler plan and retained
  dependencies. Sources: [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Publish versioned demand-use summaries covering dynamic counts, aliases, escape,
loops and control/provider boundaries.

## Starting point

[demand_inline.zig](../zig-native/src/backend/demand_inline.zig) uses a bounded
96-node `Plan` for known acyclic expression forwarding.
[core.zig](../zig-native/src/check/core.zig) retains `suspend_`/`force`; broader
retained-body analysis is not implemented.

## Implementation checklist

- [x] Classify never/once/repeated/unknown/escaping demand uses by dynamic
      control flow rather than textual occurrence count.
- [x] Track aliases, creation scopes, loops, captures and request/provider
      boundaries; use bounded recursive-component fixed points.
- [x] Record checked-body identity, summary version, captures, latent effects
      and every consumed dependency in the query model. Keep Core immutable and
      principal facts distinct.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Analyze demands read in branches/loops, forwarded through aliases, stored in
  closures and recursive callbacks.
- Test bounded exhaustion and unknown control flow, imported bodies, changed
  callee bodies with stable types and failed revisions.
- Check summary ownership, OOM publication and work proportional to analyzed
  retained bodies.

## Acceptance criteria

- [x] Each summary conservatively represents dynamic use and scope with exact
      versioned dependencies.
- [x] No unknown use is misclassified as local/once, and repeated lookup can
      reuse summaries safely.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `b068dc9` (joint compiler boundary for 028/036/094/098).
- Validation: Zig 0.17.0, Deno 2.9.7; `deno task test:compiler` passes the
  complete native gate and 763 guest/client laws. `deno task lint:zig` with
  `ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer`: 323 files,
  zero findings. All eight unchanged compile-allocation laws pass.
- Comparison: seven alternating release pairs preserve successful Wasm, constant
  steps, code instances and old prepared-shape counters across 13 public
  examples, synthetic fresh/retained/restart phases and native-asset
  edit/revert/rejection/recovery. Nine CLI diagnostic cases match after optional
  `related`/`details` null-versus-absent normalization. Current captured gdev:
  55 modules, 482 fixture cases, 1,460 assertions; split hauling: 12 exports, 25
  assertions. CPU is mixed; no overall compiler speedup is claimed.
- Remaining limitations: Graph-wide read sets conservatively invalidate extra
  consumers; forwarded memo counts can overestimate; portable checkpoints
  reanalyze summaries. Unknown and escaping uses preserve fallback.
- Durable record: [DEMAND_SUMMARIES.md](../zig-native/DEMAND_SUMMARIES.md) and
  the shared
  [qualification](../zig-native/RESOLVED_BODIES.md#qualification-11-october-2026),
  including exact compiler/input/harness hashes and median distributions.
