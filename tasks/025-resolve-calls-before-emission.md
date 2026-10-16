# 025 — Resolve calls before emission

## Status, dependencies, and originating requirements

- **Status:** Complete at `29aaa98`.
- **Dependencies:** [008](008-canonicalize-specialization-keys.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  backend boundary. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent selected direct and indirect calls completely before Wasm instruction
emission.

## Starting point

[specialization.zig](../zig-native/src/eval/specialization.zig) already
separates some semantic selection, but
[core_backend.zig](../zig-native/src/backend/core_backend.zig) still resolves
calls while emitting. [known_call.zig](../zig-native/src/backend/known_call.zig)
and [layout_bridge.zig](../zig-native/src/backend/layout_bridge.zig) carry
current call/layout knowledge.

## Implementation checklist

- [x] Add a resolved call representation with target/body identity, direct or
      indirect signature, complete evidence, captures, effects and source
      origins.
- [x] Resolve semantic obligations during preparation with explicit owned
      results, retaining conservative staged/open-row handling.
- [x] Give unresolved calls authoritative diagnostics before emission and
      preserve evaluation order and argument witness sites.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare direct, indirect, partially applied, generic, captured and effectful
  calls with existing execution and diagnostics.
- Test unresolved evidence, incompatible signatures, nested forwarding and
  imported/portable calls.
- Exercise OOM during call preparation and ensure immutable Core and previous
  artifacts survive.

## Acceptance criteria

- [x] Prepared calls contain everything emission needs for call selection and
      signature checking.
- [x] No call semantics are guessed from machine types or selected anew by
      instruction emission.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commits: `b0c9168` ("Prepare named, operator, resolver and closure calls
  before emission") and `29aaa98` ("Prepare static closure applications and
  count prepared calls").
- Change: [resolved_call.zig](../zig-native/src/backend/resolved_call.zig) plans
  carry each call's specialization key or callable wrapper, consumed arguments
  and the semantic arrows of closures applied afterwards; static closure plans
  carry closure identity, captured values and specialized mappings. Every source
  call is prepared before its first instruction, and indirect signatures come
  from the callee's arrow. Function creation stays where emission reaches it.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 641 guest/client tests; `deno task lint:zig` reports zero findings across
  311 files; a process law executes each call shape and checks prepared-call
  counters. The existing allocation-failure sweeps of backend emission
  (`request_backend_tests.zig`, `core_operation_evidence_tests.zig`) run
  preparation wherever their programs reach it; no sweep was added for plans.
- Comparison: every public example, the synthetic corpus in every phase and gdev
  emit byte-identical Wasm before and after; no performance change was intended
  or measured.
- Remaining limitations: plans are transient per call (stored resolved bodies
  are tasks 026–028); named over-application is prepared but unreachable from
  current lowering; partial and recovered known calls are prepared only for
  inlining.
- Durable record: [resolved calls](../zig-native/RESOLVED_CALLS.md).
