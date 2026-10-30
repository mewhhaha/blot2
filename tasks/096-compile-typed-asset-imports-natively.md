# 096 — Compile typed asset imports natively

## Status, dependencies, and originating requirements

- **Status:** Complete — implementation `0c5be56` is qualified.
- **Dependencies:** [095](095-specify-and-version-the-project-protocol.md)
- **Originating requirements:** the owner's decision of 11 October 2026, relayed
  by the gdev session and recorded in gdev's `PEN_MIGRATION.md` ("Decisions",
  phase 1): typed asset imports move into `blotc` so every host gets them alike;
  gdev's `asset_parsers.ts` is the specification.
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

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

- [x] Specify each asset kind's Blot interface and errors from
      `asset_parsers.ts`, including asset handles, content snapshots and
      dependency reporting.
- [x] Implement the readers natively, with bounded, positioned diagnostics, and
      track asset files as build inputs so retained builds invalidate exactly.
- [x] Extend the protocol specification (task 095) for asset roots, snapshots
      and dependencies; keep the TypeScript path working until hosts move.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Every asset kind, malformed inputs, missing glyphs, edits and deletions in
  retained builds, and parity with the TypeScript parsers on gdev's assets.
- gdev builds to identical Wasm and asset snapshots through native imports.

## Acceptance criteria

- [x] gdev's typed asset imports compile through `blotc` with no host parsers,
      matching the TypeScript results.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `0c5be56`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 743 guest/client tests. Analyzer: 318 files, zero findings. All 37
  independent raw-wire cases pass. Reader/session laws sweep allocation
  failures; client laws validate ownership and malformed replies. Formatting,
  typechecking and the package publish dry run pass. Current gdev passes 472
  regular cases across 54 modules and 12 split-hauling exports/25 assertions
  through native imports.
- Comparison: exact generated-source parity for all 33 current private shaders,
  73 public WGSL probes and 16 JSON/catalog/text/tunable modules. Three paired
  frozen-game runs match Wasm, snapshots and dependency digests through source
  and asset edits, rejection and recovery. One asset edit reparses one module
  and reuses 33; unchanged inputs reuse all 34. Frozen Wasm remains 840,534
  bytes, SHA-256
  `3158216b0b7cb072245d9aa149887a39bbadbc305430569ae3e033818e3edef0`. All 13
  public examples, four synthetic workloads in every fresh/retained phase, and
  five ordered diagnostic probes preserve the preceding compiler's outputs. CPU
  distributions and exact pins are in the durable record.
- Remaining limitations: the frozen game has no resource handles or tunables
  input; public laws qualify those interfaces separately. Complex matrix,
  packing and struct-result WGSL constant builtins reject explicitly. The pinned
  reflector's observed scalar quirks are preserved and documented. Unchanged
  disk inputs are still acquired and hashed. Loaded-host timings do not
  establish a general compiler speedup. Private source/assets stay outside
  commits.
- Durable record: [native assets](../zig-native/NATIVE_ASSETS.md),
  [protocol](../zig-native/PROJECT_PROTOCOL.md),
  [distributions](../zig-native/qualification/native-assets.csv) and
  [pins](../zig-native/qualification/native-assets-pins.json).
