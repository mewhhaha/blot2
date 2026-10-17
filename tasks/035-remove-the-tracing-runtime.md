# 035 — Remove the tracing runtime

## Status, dependencies, and originating requirements

- **Status:** In progress — the CPU comparison against tracing is no longer a
  gate (owner decision, 15 October 2026); bounded-memory stress and a passing
  full gate on current source remain.
- **Dependencies:** [034](034-reclaim-cyclic-ownership.md)
- **Originating requirements:** PLAN: Earlier programs / qualified tracing
  replacement. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Remove tracing only after the replacement ownership system passes cycle,
suspension and memory gates: programs must run on the development machine
without crashing or exhausting memory.

**Owner decision, 15 October 2026:** the performance bar is "runs on this
computer without crashing". The historical tracing CPU baseline (about 4.9x on
the cycle workload) and the 1.05 overhead screen no longer gate completion; CPU
and memory figures are recorded for information only.

## Starting point

[arena_runtime.zig](../zig-native/src/runtime/arena_runtime.zig) and runtime
layout/cleanup code still support tracing during tasks 031–034. Local allocation
optimizations and public guest behavior must remain valid.

## Implementation checklist

- [ ] Audit every heap allocation, field role, root and exit for replacement
      coverage before deleting tracing code.
- [ ] Remove obsolete tracing metadata, scanning and collection triggers only
      after all dynamic graphs have valid ownership.
- [ ] Retain the behavioral cycle, suspension and persistent-root
      counterexamples as permanent regressions and update durable ownership
      documentation.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run full compiler, sync/JSPI, guest ABI, cycle and ownership suites with
  tracing absent.
- Stress long-running collections, escaping closures, repeated guest calls,
  canceled requests and discarded cycles.
- Include nested collecting loops whose successive activation floors retain
  earlier dead temporaries. Task 002 found identical baseline/candidate growth
  from 43,515,904 to 942,211,072 committed bytes when a 90-row outer traversal
  increased each inner loop from 8 to 200 discarded 8,192-word arrays. Preserve
  live outer rows while bounding dead storage within one guest invocation.
- Record runtime CPU, allocation, peak/live memory and compiler overhead against
  the tracing baseline for information; no ratio is a pass/fail gate.

## Acceptance criteria

- [ ] No production path relies on tracing, and all reachable values/cycles
      remain correct.
- [ ] The long-running stress scenarios above complete on the development
      machine without traps, crashes or out-of-memory failures, and committed
      memory stays bounded after warmup. CPU ratios are recorded, not gated.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Latest qualified checkpoint: `cb3ebec` adds the direct named reference
  environment with scalar-only local replacement. Full native/OOM suite, 965
  guest/client laws, eight unchanged budgets and 351 analyzer files with zero
  findings pass (Zig 0.17.0). Merged cycle CPU improves about 13.7% with flat
  128 KiB storage; ordinary controls stay within roughly 1.5%.
- Milestones: `850793f` qualified capture-free static descriptors, checked
  direct result forwarding and paired guest State frames (936 guest/client laws,
  analyzer 350/zero; cycle CPU about 35.5% below `2689ad5`); `4013b10` qualified
  conditional activation, static nullary constructors, explicit Array-copy
  publication, single-use private storage and same-unit immutable acyclic proofs
  (961 guest/client laws, analyzer 351/zero; joint sync/JSPI cycle CPU about 13%
  below `850793f`). Late immutable flags, eight-byte journals, checked results,
  frame-demand identity and scalar stores remain qualified. The nested
  discarded-Array memory law preserves outer rows and roots/leases at 8/40/200
  inner iterations.
- Informational CPU (not gating since the 15 October owner decision): the
  compact-marker cycle workload is about 4.89–4.96× the old tracing baseline.
  The 15 October current-source screen of a private union/guard candidate
  exceeded the former 1.05 overhead limit (guard/control fresh 1.114286, edit
  1.010309, geometric mean 1.061025; union 1.066424) in one balanced campaign
  without retries; it was not promoted.
- Remaining work: conservative partial paths still use tracing; physical
  removal, complete layout/scope coverage, the bounded-memory stress scenarios
  and a passing full gate on current source remain. No completion is claimed.
- Durable record: [TRACING_REPLACEMENT](../zig-native/TRACING_REPLACEMENT.md),
  [combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md),
  [the integrated record](../zig-native/ITERATOR_STATE.md) and
  [merged qualification](../zig-native/CONTINUATION_QUALIFICATION.md).
