# 066 — Specify typed staging

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Settle syntax and APIs for typed code/descriptors, construction,
      composition, evaluation and stage crossing.
- [ ] Define binding hygiene, abstract/package identities, effects and resource
      restrictions at each stage.
- [ ] Specify exact tracked inputs, artifact representation, invalidation,
      failure publication and diagnostics.
- [ ] Document examples using the existing parser/checker/Core pipeline;
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

- [ ] Durable staging syntax, semantics, representation, diagnostics and
      compatibility are defined.
- [ ] Tasks 067–068 can implement typed hygienic generation through the ordinary
      compiler stages.
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
