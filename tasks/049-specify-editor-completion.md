# 049 — Specify editor completion

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [048](048-explain-dispatch-and-evidence.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / editor
  completion. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify completion requests, overlays, expected-type use, ranking, cancellation
and integration with the existing editor setup.

## Starting point

[compiler/zig_project_client.ts](../compiler/zig_project_client.ts),
[zig_project_server.zig](../zig-native/src/zig_project_server.zig),
[zig_project_frames.zig](../zig-native/src/zig_project_frames.zig) and
[source_overlays.zig](../zig-native/src/source_overlays.zig) provide retained
protocol/overlays. [editor/helix/languages.toml](../editor/helix/languages.toml)
and tree-sitter integration currently provide editor syntax support.

## Implementation checklist

- [ ] Define protocol request/response schemas, source positions,
      revision/overlay identities and ownership of completion results.
- [ ] Specify expected types, lexical shadowing/import visibility, ranking,
      incomplete syntax behavior and bounded work/results.
- [ ] Define cancellation, stale-response handling and malformed-message
      diagnostics, plus the concrete Helix integration path.
- [ ] Save durable API documentation and acceptance transcripts for compiler,
      client and editor.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review incomplete call/member/hole examples, shadowed identifiers, imported
  candidates and generic obligations.
- Trace rapid overlay changes, canceled requests, closed sessions and malformed
  protocol data.

## Acceptance criteria

- [ ] The completion API, ranking, limits, diagnostics and editor integration
      are unambiguous and documented.
- [ ] Task 050 has end-to-end acceptance examples without assuming an editor
      feature already exists.
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
