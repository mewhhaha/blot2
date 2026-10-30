# 049 — Specify editor completion

## Status, dependencies, and originating requirements

- **Status:** Complete.
- **Dependencies:** [048](048-explain-dispatch-and-evidence.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / editor
  completion. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify completion requests, overlays, expected-type use, ranking, cancellation
and integration with the existing editor setup.

## Starting point

[compiler/zig_project_client.ts](../compiler/zig_project_client.ts),
[zig_project_server.zig](../zig-native/src/reuse/zig_project_server.zig),
[zig_project_frames.zig](../zig-native/src/reuse/zig_project_frames.zig) and
[source_overlays.zig](../zig-native/src/reuse/source_overlays.zig) provide
retained protocol/overlays.
[editor/helix/languages.toml](../editor/helix/languages.toml) and tree-sitter
integration currently provide editor syntax support.

## Implementation checklist

- [x] Define protocol request/response schemas, source positions,
      revision/overlay identities and ownership of completion results.
- [x] Specify expected types, lexical shadowing/import visibility, ranking,
      incomplete syntax behavior and bounded work/results.
- [x] Define cancellation, stale-response handling and malformed-message
      diagnostics, plus the concrete Helix integration path.
- [x] Save durable API documentation and acceptance transcripts for compiler,
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

- [x] The completion API, ranking, limits, diagnostics and editor integration
      are unambiguous and documented.
- [x] Task 050 has end-to-end acceptance examples without assuming an editor
      feature already exists.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `d7e2b89`; durable API and acceptance transcripts.
- Validation: Deno formatting and seven local links/anchors pass; JSON/TOML
  examples and incomplete calls/members/holes, imports, shadowing, generic
  obligations, cancellation and stale replies were reviewed against the guide,
  ownership contract, project protocol and current Helix setup.
- Comparison: documentation only; performance measurement does not apply.
- Remaining limitations: task 050 implements and qualifies the query, client,
  bounded recovery/ranking and actual Helix bridge. The proposed 250 ms deadline
  is editor policy, not measured latency.
- Durable record: [editor completion](../zig-native/EDITOR_COMPLETION.md).
