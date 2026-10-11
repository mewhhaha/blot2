# 050 — Implement editor completion

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified local implementation `2226d50`.
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

- [x] Implement bounded completion queries against revision-aware source
      overlays and expected-type/evidence information.
- [x] Apply specified visibility, ranking and incomplete-syntax behavior with
      owned results and precise source positions.
- [x] Wire client/editor requests, cancellation and stale-response rejection;
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

- [x] Completion works through the supported editor with the specified ranking
      and revision semantics.
- [x] Malformed/canceled/stale requests remain safe and last-good compilation
      survives incomplete edits.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2226d50` (joint 043/050 implementation); this record is separate.
- Validation: Zig 0.17.0; full native and 807 guest/client laws pass, all eight
  allocation budgets unchanged; analyzer zero across 336 Zig files. Focused
  native/OOM and executed-Wasm checks pass. Editor
  corpus/installer/protocol/client/LSP and actual Helix checks pass.
- Comparison: Actual Helix value/member/import/hole/Unicode/race sessions pass.
  Six-fixture wire latency, native CPU/allocation probes and seven public
  release pairs are pinned in the durable record. Main repeated medians are
  2.967–3.445 ms, large scope 33.672 ms.
- Remaining limitations: No retained query cache or auto-imports. Generic
  fitting can exhaust its shared budget and return unknown/truncated. Visibility
  follows the current language; task 052 adds privacy.
- Durable record: [qualification](../zig-native/EDITOR_COMPLETION.md); exact
  release pins, distributions and ignored evidence paths are recorded there.
