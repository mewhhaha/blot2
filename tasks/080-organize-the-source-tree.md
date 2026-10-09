# 080 — Organize the source tree

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [079](079-relocate-fixtures-through-a-test-module.md)
- **Originating requirements:** PLAN: Hill 15 / source layout. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Move compiler sources into parse/check/eval/backend/reuse/runtime areas with
nearby tests.

## Starting point

The baseline
[zig-native/src/production_suite.zig](../zig-native/src/production_suite.zig)
imports a flat source tree; [zig-native/build.zig](../zig-native/build.zig),
[zig-native/compiler_fingerprint.zig](../zig-native/compiler_fingerprint.zig)
and packaging/analyzer scripts depend on paths.

## Implementation checklist

- [ ] Organize files by responsibility and keep tests near their production
      areas while retaining the fixture module.
- [ ] Update every import, build root, test aggregator, compiler fingerprint
      input and packaging path.
- [ ] Update analyzer traversal, scripts, documentation links and any
      generated-input lists; preserve intended compiler identity changes.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run fresh dev/release builds, full native/guest and filtered-test discovery,
  zero analyzer findings and packaging dry run.
- Run editor/client checks where paths change and validate all
  documentation/import references.
- Verify fingerprints include every production source and change when
  moved/edited inputs change.

## Acceptance criteria

- [ ] The planned source areas exist with correct imports, nearby tests and
      external fixtures.
- [ ] Builds, tests, fingerprints, analyzer, packaging and links all use the new
      layout.
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
