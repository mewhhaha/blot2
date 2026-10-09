# 079 — Relocate fixtures through a test module

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [078](078-split-backend-state-and-emission.md)
- **Originating requirements:** PLAN: Hills 15 and 20 / fixtures and test
  discovery. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Expose fixtures through a dedicated Zig module rooted outside production sources
and relocate embedded fixture data.

## Starting point

[zig-native/build.zig](../zig-native/build.zig) roots tests at
`src/production_suite.zig`;
[production_suite.zig](../zig-native/src/production_suite.zig) imports the full
test suite. Many `@embedFile` paths still point inside production `src/`.

## Implementation checklist

- [ ] Create a dedicated fixture module rooted at `zig-native/fixtures/` and
      expose needed embedded data through it.
- [ ] Move top-level `.blot` and fixture directories out of production sources,
      updating test consumers and build wiring.
- [ ] Preserve complete comptime test import/discovery and correct module-root
      restrictions; do not make production depend on test data.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run the full native suite and several known filtered tests, including a
  relocated fixture consumer; assert nonzero matching counts.
- Check all embedded paths, fresh builds, packaging and analyzer coverage after
  relocation.
- Verify fixture bytes stay unchanged and dependency/execution fixtures still
  run.

## Acceptance criteria

- [ ] Fixtures live outside production sources behind a dedicated module with no
      invalid embed paths.
- [ ] All tests remain discoverable, including filtered runs; no test is
      silently dropped.
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
