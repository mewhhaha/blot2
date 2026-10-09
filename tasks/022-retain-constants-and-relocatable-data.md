# 022 — Retain constants and relocatable data

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

[core_eval.zig](../zig-native/src/core_eval.zig) owns evaluated values;
[core_backend.zig](../zig-native/src/core_backend.zig) serializes them. Scalar
constant admission already exists, while
[source_value_template.zig](../zig-native/src/source_value_template.zig) records
complete captured graphs and aggregate data remains separate.

## Implementation checklist

- [ ] Retain supported aggregate values with alias topology, nominal/generative
      identities and exact observed staged inputs.
- [ ] Separate relocatable data descriptions from final memory/function offsets;
      reconstruct output in current owners.
- [ ] Preserve evaluation order, constant jobs, failure semantics and demand
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

- [ ] Eligible aggregates and data reuse only when complete staging inputs and
      identities match.
- [ ] Relocation and evaluation behavior remain correct; unsupported/generative
      cases conservatively rebuild.
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
