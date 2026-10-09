# 048 — Explain dispatch and evidence

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [004](004-summarize-predicate-bearing-callees.md),
  [005](005-summarize-higher-order-callees.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / explainable
  inference. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Expose bounded explanations of candidate selection, failed obligations and
selected evidence in native diagnostics and the client schema.

## Starting point

[hole_diagnostics.zig](../zig-native/src/hole_diagnostics.zig),
[type_display.zig](../zig-native/src/type_display.zig) and
[compiler/type_diagnostics.ts](../compiler/type_diagnostics.ts) already expose
owned bounded type graphs and lexical requirements. Dispatch/member evidence is
selected in [check.zig](../zig-native/src/check.zig) and specialization.

## Implementation checklist

- [ ] Record candidate origins, admission/rejection reasons and selected
      evidence without rerunning unbounded inference.
- [ ] Preserve left-before-right associated dispatch, receiver-only lookup and
      authoritative diagnostic ordering.
- [ ] Extend owned native and client data with depth/size limits, truncation and
      defensive decoding; keep diagnostic identities local.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Explain valid selection, missing/incompatible/ambiguous evidence, generic
  callbacks, imports and compiled dependencies.
- Check left candidate wins even when its result conflicts with an annotation;
  verify receiver lookup does not search argument types.
- Test huge/cyclic evidence graphs, malformed client payloads, OOM snapshot
  cleanup and correction after failure.

## Acceptance criteria

- [ ] Users can see which candidates were considered and why evidence succeeded
      or failed.
- [ ] Explanations are bounded, owned and consistent across native/client paths
      without changing dispatch semantics.
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
