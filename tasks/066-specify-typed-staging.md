# 066 — Specify typed staging

## Status, dependencies, and originating requirements

- **Status:** Complete design — implementation and dependency qualification
  remain separate; no executable feature completion is claimed.
- **Dependencies:** [053](053-qualify-module-cutoffs-and-wrapper-erasure.md),
  [065](065-implement-existential-packages.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 8 / typed staging.
  Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify typed Blot code values, descriptors, stage boundaries, hygiene,
generation and exact dependencies.

## Starting point

[compiler/assets.ts](../compiler/assets.ts) already accepts typed host asset
modules, and ordinary const evaluation builds values.
[compiler/guide.md](../compiler/guide.md) explicitly lacks general type-valued
computation; typed code must use the ordinary frontend.

## Implementation checklist

- [x] Settle syntax and APIs for typed code/descriptors, construction,
      composition, evaluation and stage crossing.
- [x] Define binding hygiene, abstract/package identities, effects and resource
      restrictions at each stage.
- [x] Specify exact tracked inputs, artifact representation, invalidation,
      failure publication and diagnostics.
- [x] Document examples using the existing parser/checker/Core pipeline;
      prohibit a separate string-based compiler frontend.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review generated bindings with shadowing, imported abstractions, code shape
  mismatches and forbidden cross-stage values.
- Trace an asset/staged-input change through generation, retained reuse and
  failed-revision recovery.

## Acceptance criteria

- [x] Durable staging syntax, semantics, representation, diagnostics and
      compatibility are defined.
- [x] Tasks 067–068 can implement typed hygienic generation through the ordinary
      compiler stages.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Source milestone: isolated design checkpoint based on `ef57ec5`; no compiler
  source or executable fixtures changed in this specification checkpoint.
- Durable record: [Typed Staging](../zig-native/TYPED_STAGING.md).
- Validation: `deno fmt --no-config --check` on the four specifications and task
  records, plus local path/heading validation; results recorded in
  [design qualification](../zig-native/LANGUAGE_DESIGN_QUALIFICATION.md).
- Comparison: documentation only; no runtime or compiler performance claim.
- Remaining limitations: dependent implementation tasks remain open. The design
  fixes syntax, ownership/identity, portable evidence and rejection boundaries;
  it does not claim those mechanisms are executable or qualified yet.
