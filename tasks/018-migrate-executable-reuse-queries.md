# 018 — Migrate executable reuse queries

## Status, dependencies, and originating requirements

- **Status:** Complete — implementation and qualification passed on 10
  October 2026.
- **Dependencies:** [017](017-unify-source-and-revision-validation.md)
- **Originating requirements:** PLAN: Hill 12 / executable queries. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Integrate code fragments and optimizer dependencies into the query table without
confusing interface stability with executable stability.

## Starting point

[artifact_capture.zig](../zig-native/src/artifact_capture.zig),
[optimized_bodies.zig](../zig-native/src/optimized_bodies.zig),
[runtime_pipeline.zig](../zig-native/src/runtime_pipeline.zig) and
[runtime_body_relocation.zig](../zig-native/src/runtime_body_relocation.zig)
capture instructions, called bodies, signatures and lifetime facts. Demand
inlining also consumes body dependencies.

## Implementation checklist

- [x] Represent body, selected evidence, capture, staging, policy and optimizer
      dependencies as executable query inputs.
- [x] Preserve exact instruction/signature comparisons and deterministic
      preparation of callee lifetime summaries, including recursive call graphs.
- [x] Keep semantic early cutoff separate: a body edit with an unchanged type
      must still invalidate affected executable consumers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run optimized-body, general-cache, compilation-tier, static-capture and
  demand-forwarding reuse tests.
- Change an inlined callee or its escape behavior without changing its
  signature; compare fresh and retained code and execution.
- Cover recursive relocation, policy changes, OOM, failed assembly and recovery.

## Acceptance criteria

- [x] Executable queries share storage and dependency machinery while preserving
      every code/lifetime validity check.
- [x] Unchanged interfaces never suppress required body or optimizer rebuilds.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `a604cc1644d120430b0d853be9dcd9b8eab3e93f` (compiler milestone).
- Validation: Zig 0.17.0; full LLVM `deno task test:compiler` passes native
  execution and 623 guest/client tests. `deno task lint:zig` reports zero
  findings across 302 files; `deno task package:check` passes. Broad and final
  focused batches pass 160 and 26 tests. Real fragment/optimizer prefix
  saturation declines all reuse, matches fresh Wasm and tears down to zero.
  Exact capture/staging, recursive relocation, callee lifetime/escape changes,
  policy changes, OOM and failed-revision recovery remain covered.
- Comparison: immutable task-017 baseline versus candidate across 626 cases /
  3,756 six-policy invocations preserves diagnostics and Wasm; 192 guests /
  10,362 calls execute. Retained/checkpoint qualification covers 27 workloads,
  three additional refinement controls and two principal controls. Five-policy
  executable scenarios pass 80 samples / 75 guests / 225 calls, including an
  imported callee body edit with an unchanged signature and positive reuse on
  entry-only edits.
- Measurement: 86 fresh workloads × 15 alternating pairs give 2,580 samples, CPU
  ratio 1.00063, wall 1.00220 and unchanged requested allocation. Seventeen
  retained workloads × seven pairs give 238 native runs / 19,992 phases and 714
  CLI builds. Paired Wasm agrees, committed memory plateaus and all teardown is
  zero. Positive executable controls reuse one fragment and one optimizer body;
  their held memory grows by 6,000 bytes. Refinement128 adds 7.94% requested
  allocation, 4.29% CPU and 14.84% peak memory. No general speedup or allocation
  reduction is claimed.
- Remaining limitations: local graph ordinals belong to immutable captures;
  portable query representation and further archive validation remain task 019,
  broader persisted graphs task 020. Unsupported jobs and saturated tables
  conservatively rebuild. Private gdev/original boxed artifacts remain absent,
  so tasks 002/084 stay open. Later tasks remain pending.
- Durable record: [executable queries](../zig-native/EXECUTABLE_QUERIES.md),
  [fresh distributions](../zig-native/qualification/executable-queries-fresh.csv),
  [retained distributions](../zig-native/qualification/executable-queries-retained.csv),
  [pins](../zig-native/qualification/executable-queries-pins.json),
  [native probe](../zig-native/qualification/executable_queries_probe.zig),
  [prefix law](../zig-native/qualification/executable_queries_prefix.zig) and
  [executed body-edit scenario](../zig-native/qualification/executable_queries_behavior.ts).
