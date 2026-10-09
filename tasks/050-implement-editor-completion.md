# 050 — Implement editor completion

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [049](049-specify-editor-completion.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / editor
  completion. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Deliver the specified completion flow through the native compiler, client and
editor.

## Starting point

Task 049 defines the API.
[compiler/zig_project_client.ts](../compiler/zig_project_client.ts),
[zig_project_server.zig](../zig-native/src/zig_project_server.zig),
[source_overlays.zig](../zig-native/src/source_overlays.zig) and
[scripts/helix_languages.ts](../scripts/helix_languages.ts) are the existing
integration boundaries.

## Implementation checklist

- [ ] Implement bounded completion queries against revision-aware source
      overlays and expected-type/evidence information.
- [ ] Apply specified visibility, ranking and incomplete-syntax behavior with
      owned results and precise source positions.
- [ ] Wire client/editor requests, cancellation and stale-response rejection;
      keep failed overlays from replacing the last successful build.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Exercise incomplete calls, member access, shadowing, named/namespace imports
  and generic suggestions end to end.
- Test rapid edits, cancellation, stale responses, malformed frames, UTF-8
  positions and bounded large scopes.
- Run `deno task check:editor`, `deno task test:editor`, protocol/client tests
  and relevant compiler/OOM gates; record an actual editor-session acceptance
  trace.

## Acceptance criteria

- [ ] Completion works through the supported editor with the specified ranking
      and revision semantics.
- [ ] Malformed/canceled/stale requests remain safe and last-good compilation
      survives incomplete edits.
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
