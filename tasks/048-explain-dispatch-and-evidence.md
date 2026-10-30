# 048 — Explain dispatch and evidence

## Status, dependencies, and originating requirements

- **Status:** Complete at `67e7912`.
- **Dependencies:** [004](004-summarize-predicate-bearing-callees.md),
  [005](005-summarize-higher-order-callees.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / explainable
  inference. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Expose bounded explanations of candidate selection, failed obligations and
selected evidence in native diagnostics and the client schema.

## Starting point

[hole_diagnostics.zig](../zig-native/src/reuse/hole_diagnostics.zig),
[type_display.zig](../zig-native/src/reuse/type_display.zig) and
[compiler/type_diagnostics.ts](../compiler/type_diagnostics.ts) already expose
owned bounded type graphs and lexical requirements. Dispatch/member evidence is
selected in [check.zig](../zig-native/src/check/check.zig) and specialization.

## Implementation checklist

- [x] Record candidate origins, admission/rejection reasons and selected
      evidence without rerunning unbounded inference.
- [x] Preserve left-before-right associated dispatch, receiver-only lookup and
      authoritative diagnostic ordering.
- [x] Extend owned native and client data with depth/size limits, truncation and
      defensive decoding; keep diagnostic identities local.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Explain valid selection, missing/incompatible/ambiguous evidence, generic
  callbacks, imports and compiled dependencies.
- Check left candidate wins even when its result conflicts with an annotation;
  verify receiver lookup does not search argument types.
- Test huge/cyclic evidence graphs, malformed client payloads, OOM snapshot
  cleanup and correction after failure.

## Acceptance criteria

- [x] Users can see which candidates were considered and why evidence succeeded
      or failed.
- [x] Explanations are bounded, owned and consistent across native/client paths
      without changing dispatch semantics.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `67e7912` ("Explain failed dispatch candidates in diagnostics").
- Change:
  [dispatch_explanation.zig](../zig-native/src/reuse/dispatch_explanation.zig)
  defines an owned explanation (operator, member, up to four candidates with
  side, spelled type and outcome). The checker attaches it to operator,
  associated, result-dispatch and receiver failures and to a selected member's
  result conflict, from member tables and resolved types only. The evaluator
  records a plain candidate record in its diagnostic, which the backend spells
  into `Result.explanation`. The CLI, dependency consumers, partial builds and
  project server publish it as `details.explanation`; the client decodes it into
  `diagnostic.explanation` and rejects malformed payloads.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 645 guest/client tests; `deno task lint:zig` reports zero findings across
  313 files. Native laws cover each candidate order, receiver-only lookup,
  result dispatch, a left member that wins although its result conflicts, a
  generic callback, cut spellings, and allocation failure in the checker and
  backend; a mutant that lists an identical right owner fails. A process law
  covers the CLI with the standard prelude, an imported type through the project
  server with recovery to the original Wasm, and a compiled dependency bundle;
  client tests reject malformed explanations.
- Comparison: every public example and gdev emit byte-identical Wasm (gdev
  SHA-256 `3158216b…def0`, 840,534 bytes). Successful compilation only records
  which side a dispatch selected, so no timing was measured.
- Remaining limitations: explanations accompany diagnostics only (no editor
  query for successful selection); specialization failures are still located in
  the callee, often `std/prelude` (task
  [094](094-locate-specialization-failures-at-their-use.md)); a user-written
  `@type.call` whose result conflicts later carries no explanation; the
  evaluator's own `result_mismatch` record is reached by no known source program
  because the checker reports first; emit-stage spellings are module-qualified
  and omit unnamed shapes such as records.
- Durable record:
  [dispatch explanations](../zig-native/DISPATCH_EXPLANATIONS.md).
