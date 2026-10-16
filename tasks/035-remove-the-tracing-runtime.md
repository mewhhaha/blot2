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

- Partial implementation: `850793f` additionally qualifies capture-free static
  descriptors, checked direct result forwarding and paired guest State frames.
  Late immutable flags, eight-byte journals, checked results, frame-demand
  identity and scalar stores remain qualified.
- Full compiler gate: complete native suite,936 guest/client laws, eight
  unchanged budgets; analyzer 350/zero; Zig 0.17.0. Nested discarded-Array
  memory law preserves outer rows and roots/leases at 8/40/200 inner iterations.
- Open gates: conservative partial paths still use tracing. Physical removal,
  complete layout/scope coverage and CPU acceptance remain unfinished. The prior
  compact-marker cycle workload is about 4.89–4.96× the old tracing baseline,
  about 14.1% faster than the isolated flag-only control. Those exact isolated
  pins are separate from merged public compiler costs. The merged descriptor/
  forwarding/State slices reduce cycle CPU about 35.5% versus 2689 ad 5, but
  still fail the historical tracing comparison. JSPI Array CPU is+1.7% on the
  merged screen. Conditional activation is later isolated work; no completion is
  claimed.
- Durable record: [TRACING_REPLACEMENT](../zig-native/TRACING_REPLACEMENT.md)
  and
  [combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).

### Qualified conditional and immutable storage —12 October 2026

`4013b10` additionally qualifies conditional activation, static nullary
constructors, explicit Array-copy publication, single-use private storage and
same-unit immutable acyclic proofs. Full native/OOM and 961 guest/client tests,
eight unchanged budgets and 351 analyzer files/zero pass. Original cancellation
and cyclic-summary fixtures regain strict ownership/flat storage; scalar trees
avoid repeated trials. Joint sync/JSPI cycle CPU is about 13% below 850793 f,
with mixed controls. Physical tracing, uncovered layouts and the historical CPU
gate remain open. See
[TRACING_REPLACEMENT](../zig-native/TRACING_REPLACEMENT.md).

The direct named reference environment is qualified at `cb3ebec` with
scalar-only local replacement: full native/OOM, 965 guest/client laws, eight
unchanged budgets and 351 analyzer files/zero. Merged cycle CPU improves about
13.7% with flat 128-KiB storage; ordinary controls remain within roughly 1.5%.
This is another measured checkpoint, not physical tracing removal or the final
task CPU gate. See [the integrated record](../zig-native/ITERATOR_STATE.md).

Current-source compiler screen,15 October: the private union/guard candidate
fails its1.05 overhead limit (guard/control fresh1.114286, edit1.010309,
geometric mean1.061025; union1.066424). One balanced campaign, no retries.
Timing stopped before runtime/release qualification; no candidate was promoted.
Exact pins and rejection:
`build/bench/complete-program-20261015/current035-screen/`. Under the 15 October
owner decision this CPU screen no longer gates task 035; it remains recorded for
information.
