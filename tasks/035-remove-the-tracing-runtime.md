# 035 — Remove the tracing runtime

## Status, dependencies, and originating requirements

- **Status:** In progress — no completion is claimed.
- **Dependencies:** [034](034-reclaim-cyclic-ownership.md)
- **Originating requirements:** PLAN: Earlier programs / qualified tracing
  replacement. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Remove tracing only after the replacement ownership system passes cycle,
suspension, memory and performance gates.

## Starting point

[arena_runtime.zig](../zig-native/src/arena_runtime.zig) and runtime
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
- Compare runtime CPU, allocation, peak/live memory and compiler overhead with
  the pinned tracing baseline.

## Acceptance criteria

- [ ] No production path relies on tracing, and all reachable values/cycles
      remain correct.
- [ ] Long-running memory and performance qualification passes; a failing
      replacement gate keeps this task open.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Partial implementation: `2689ad5` additionally qualifies late immutable flag
  lowering and one-marker eight-byte ownership journals. Checked results,
  admission, frame-demand cache identity and scalar stores remain qualified.
- Full compiler gate: complete native suite,925 guest/client laws, eight
  unchanged budgets; analyzer349/zero; Zig0.17.0. Nested discarded-Array memory
  law preserves outer rows and roots/leases at 8/40/200 inner iterations.
- Open gates: conservative partial paths still use tracing. Physical removal,
  complete layout/scope coverage and CPU acceptance remain unfinished. The prior
  compact-marker cycle workload is about4.89–4.96× the old tracing baseline,
  about14.1% faster than the isolated flag-only control. Those exact isolated
  pins are separate from merged public compiler costs. The later static
  closure-descriptor subtraction remains isolated; no completion is claimed.
- Durable record: [TRACING_REPLACEMENT](../zig-native/TRACING_REPLACEMENT.md)
  and
  [combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).
