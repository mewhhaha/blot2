# 079 — Relocate fixtures through a test module

## Status, dependencies, and originating requirements

- **Status:** In progress — fixtures and consumers are relocated; final combined
  compiler/analyzer qualification remains pending.
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

- [x] Create a dedicated fixture module rooted at `zig-native/fixtures/` and
      expose needed embedded data through it.
- [x] Move top-level `.blot` and fixture directories out of production sources,
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
- Implementation: the `fixtures` native test module owns 126 Blot inputs and two
  frozen oracle files, all byte identical to their prior locations. Thirty Zig
  consumers and four guest helper/fixture readers use the new location;
  test-only module wiring gives production imports no fixture access.
- Validation: an exact-name focused run executes three relocated consumers
  (request graph/OOM, purity oracle and dynamically selected closure source); a
  broader filter selected 56 staging/usage controls but no fixture consumer. All
  seven local analyzer dependency/cache laws pass, including fixture additions
  and deletions. No full-gate result is claimed.
- Comparison: byte manifests show every relocated file unchanged; no performance
  comparison is recorded. Manifests, original sources and logs:
  `build/bench/finish-rest-20261015/fixture-relocation/`.
- Remaining limitations: complete comptime test import/discovery under the
  module-root restrictions and the final combined compiler/analyzer gate.
- Durable record: the fixture module is described in
  [zig-native/README.md](../zig-native/README.md); a final qualification record
  is pending.
