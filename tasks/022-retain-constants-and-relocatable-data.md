# 022 — Retain constants and relocatable data

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `62241e2`.
- **Dependencies:** [020](020-persist-complete-semantic-artifacts.md),
  [021](021-publish-transactional-revision-deltas.md)
- **Originating requirements:** PLAN: Hill 6 / constants; earlier semantic
  compilation. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Reuse eligible evaluated aggregates and serialized data under exact staging
dependencies.

## Starting point

[core_eval.zig](../zig-native/src/eval/core_eval.zig) owns evaluated values;
[core_backend.zig](../zig-native/src/backend/core_backend.zig) serializes them.
Scalar constant admission already exists, while
[source_value_template.zig](../zig-native/src/reuse/source_value_template.zig)
records complete captured graphs and aggregate data remains separate.

## Implementation checklist

- [x] Retain supported aggregate values with alias topology, nominal/generative
      identities and exact observed staged inputs.
- [x] Separate relocatable data descriptions from final memory/function offsets;
      reconstruct output in current owners.
- [x] Preserve evaluation order, constant jobs, failure semantics and demand
      creation identity; never merge runtime memo results by a code key.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test shared/nested aggregates, closures, demands, literal bits, changed
  captures and changed staged dependencies.
- Verify relocation after data/function movement, dependency/checkpoint import,
  traps during evaluation and failed-edit recovery.
- Measure re-evaluation counts, data reuse, allocation and fresh/retained byte
  equality.

## Acceptance criteria

- [x] Eligible aggregates and data reuse only when complete staging inputs and
      identities match.
- [x] Relocation and evaluation behavior remain correct; unsupported/generative
      cases conservatively rebuild.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `62241e2f2d315b46c6b32a1785dfe1942ba44720` (compiler milestone).
- Implementation: retained fragment replay admits aggregate constant children
  whose current value is already evaluated and graph-equal (scalar bits, nominal
  identities, closures, alias topology) to the old one, with an old serialized
  root and an importable layout. Reconstruction re-serializes the current value
  in the current owner through the ordinary constant path and relocates only the
  caller's exact root-address operands, so data, function indices and memo hits
  follow the current revision and output stays byte-identical to fresh. Demand
  cells, computations, request decisions, providers, resolvers and interior
  addresses still rebuild.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 627 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 308 files. Native laws
  cover replay under an allocation-failure sweep and exact rebuilds after
  element, nominal payload or combined edits. A process-level law covers moved
  functions/data, imported and aliased aggregates, a trapping constant and
  recovery against fresh servers, including executed results and native work
  steps.
- Comparison: 21 alternating repetitions of the retained probe over nine
  workloads emit identical Wasm in every phase. A generated aggregate program
  replays 4 functions and 4 aggregate constants per edit (baseline 0) with 4.9
  KB less requested allocation; public examples are unchanged within noise (+8
  bytes to +3.3 KB requested). Steady CPU geomeans are 0.999 (edit) and 1.001
  (revert).
- Remaining limitations: aggregate data is re-serialized (old bytes are not
  replayed); constants are still evaluated every revision; no public example
  replays an aggregate in these workloads, for reasons not investigated.
- Durable record: [retained constants](../zig-native/RETAINED_CONSTANTS.md),
  [distributions](../zig-native/qualification/aggregate-constants.csv) and
  [pins](../zig-native/qualification/aggregate-constants-pins.json).
