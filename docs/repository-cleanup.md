# Repository cleanup — 2026-11-04

Zig is the only compiler implementation. The dependency audit found no orphan
native implementation module or second TypeScript compiler. Deno source tools,
its generated Baba parser and Tree-sitter highlighting are active dependencies.

The native compiler still selects two live Wasm backends. Counted emission can
produce ABI 2–7 depending on features; owned data-stack emission uses ABI 8.
Scalar language-task programs can still reach counted task emission and its host
bridge. Those files remain relevant until task 120 makes owned storage
unconditional. This cleanup does not claim that retirement is complete.

## Removed or condensed

- Replaced the cumulative `PLAN.md` and `DESIGN.md` with current requirements
  and design intent. The original contents remain available through pinned Git
  links in [the documentation map](README.md).
- Removed `FINISH_PLAN.md`, `ISSUE_TRIAGE.md` and `DEVELOPMENT_TURNAROUND.md`
  from the working tree. Their superseded counted/task programmes, dated issue
  state and timing diaries remain at the same pinned revision. References in
  historical qualification reports now point there.
- Removed three unused files under
  `zig-native/fixtures/retained-state-fixtures`: `plain-annotation-scope.blot`,
  `template-local-state-identity.blot` and `template-local-state-scopes.blot`.
  Their exact sources remain exercised inline in
  `zig-native/tests/retained_state_execution.test.ts` at lines 614/632, 421 and
  3/31 respectively. No semantic witness was removed.
- Stopped generating unused Baba highlighting/rainbow queries. Tree-sitter owns
  the editor queries; Baba's `applyBundle` removed its two manifest-owned query
  files. Every active parser/plan/schema file remains byte-identical.
- Corrected stale first-frame/backend/setup descriptions, a removed-runtime
  reference and three broken local benchmark-evidence links.
- Replaced one stale numeric diagnostic-span snapshot with its source-token
  location. The missing-associated rejection and its exact span remain checked.
- Repacked the local ignored compiler payload from the current Zig release. The
  old payload failed to parse today's prelude; packaged API and standalone host
  execution now pass.

- Added explicit return types to the public memory-profile API. The package dry
  run now passes its fast-type checks; runtime behavior is unchanged.

## Retained

All native implementation modules are reachable from current build/test roots;
standalone native benchmark probes retain their documented qualification use.
Host files remain public entrypoints, transitive dependencies or executed tests.
Examples, generated parser assets and benchmark ports are active inputs.

Tasks 110–121 and the original task inventory keep their requirements. The
remaining compiler latency, retained-edit, memory, package, gameplay, recovery
and browser qualification work remains open. Copied-packet workers and
Foreign/JSPI stay supported. Dedicated measurement archives, rejected
experiments and current integration evidence are preserved.

## Ignored outputs

Removed 37 unreferenced experimental Zig installation prefixes and two obsolete
`budget-fixture` executables, reclaiming **8,014,917,632 bytes (7.46GiB)** from
`zig-native/`. The current build registry rejects the retired fixture target.
The [exact inventory](repository-cleanup.json) records each path, reference
checks, allocated bytes and preserved binary hashes.

All tracked text and private benchmark text references were checked, along with
active executable/working-directory paths and source-file exclusions. Forty-two
additional prefixes named by private evidence were retained. Current
compiler/test installations, documented baselines, `build/bench` and the Zig
cache remain available to keep iteration fast.

## Validation

The 75 affected parser, formatter, derive, CLI, public/packaged API, standalone
host and retained-State checks pass. Six editor checks pass. All 3,001 native
laws still compile with the same cached Safe/noLLVM artifact; Zig lint has zero
findings. A fresh Gdev compile is byte-identical to the preceding reviewed
10,049,963B artifact. The compressed package expands to the exact current
release binary, and active generated parser bytes are unchanged.

The full guest-only gate stops after 158 passes on the existing
`acyclic_updates_execution.test.ts` owned-storage admission gap
(`storage_unsupported`). Both the frozen preceding release and current release
reproduce it with unchanged benchmark source. The memory-profile suite also has
two existing nested-array layout rejections, reproduced by the preceding release
before the host profile reader runs; its two supported scalar/JSPI checks pass.
These semantic laws remain in place. Tasks 110–121 and full qualification remain
unfinished. The package dry run, formatting, types and local-link checks pass.
No Zig compiler implementation or runtime semantics changed in this cleanup.
