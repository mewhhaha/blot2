# 096 — Compile typed asset imports natively

## Status, dependencies, and originating requirements

- **Status:** Ready — protocol dependency qualified; no completion is claimed.
- **Dependencies:** [095](095-specify-and-version-the-project-protocol.md)
- **Originating requirements:** the owner's decision of 11 October 2026, relayed
  by the gdev session and recorded in gdev's `PEN_MIGRATION.md` ("Decisions",
  phase 1): typed asset imports move into `blotc` so every host gets them alike;
  gdev's `asset_parsers.ts` is the specification.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

`blotc` reads and types asset imports itself, so a host sends only sources and
options, never parsed assets.

## Starting point

Typed asset imports run in TypeScript:
[compiler/assets.ts](../compiler/assets.ts) `withAssetImports` wraps a build
with host-supplied parsers, and gdev's `asset_parsers.ts` (318 lines) defines
the kinds: the catalog (`meshes`, `sounds` and `materials` as ID records), JSON
records, `text.json` (words as code points, each checked against the font's
glyphs), `tunables.json`, and WGSL reflection (`struct Parameters` and module
constants, through `wgsl_reflect`).

## Implementation checklist

- [ ] Specify each asset kind's Blot interface and errors from
      `asset_parsers.ts`, including asset handles, content snapshots and
      dependency reporting.
- [ ] Implement the readers natively, with bounded, positioned diagnostics, and
      track asset files as build inputs so retained builds invalidate exactly.
- [ ] Extend the protocol specification (task 095) for asset roots, snapshots
      and dependencies; keep the TypeScript path working until hosts move.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Every asset kind, malformed inputs, missing glyphs, edits and deletions in
  retained builds, and parity with the TypeScript parsers on gdev's assets.
- gdev builds to identical Wasm and asset snapshots through native imports.

## Acceptance criteria

- [ ] gdev's typed asset imports compile through `blotc` with no host parsers,
      matching the TypeScript results.
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
