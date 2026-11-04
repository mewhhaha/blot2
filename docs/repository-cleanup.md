# Repository cleanup record

This records the 2026-11-04 cleanup at the layout in use then. Its validation
figures and candidate-specific results are historical; they do not qualify the
current source tree. See the [repository map](README.md) for today's paths.

## Changes recorded

- Replaced cumulative `PLAN.md` and `DESIGN.md` with current requirements and
  design intent. Removed `FINISH_PLAN.md`, `ISSUE_TRIAGE.md` and
  `DEVELOPMENT_TURNAROUND.md`; their prior contents remain at the pinned
  revisions linked from the documentation map.
- Removed three unused retained-state fixtures. Their exact cases remain inline
  in
  [the retained-state guest tests](../tests/guest/retained_state_execution.test.ts).
- Stopped generating unused Baba highlighting queries; Tree-sitter owns editor
  queries. Active generated parser assets were retained.
- Corrected stale setup descriptions and benchmark links, updated one numeric
  diagnostic-span snapshot, and repacked the ignored local compiler payload.
- Added explicit return types to the public memory-profile API.

The native compiler still has both counted-storage and ABI 8 data-stack
backends. Task 120 tracks the unfinished cutover. No compiler implementation or
runtime semantics changed in that cleanup.

## Preserved outputs and evidence

Removed 37 unreferenced experimental Zig installation prefixes and two obsolete
`budget-fixture` executables, reclaiming 8,014,917,632 bytes (7.46 GiB). The
[cleanup inventory](repository-cleanup.json) records paths, checks, byte counts
and preserved binary hashes. Forty-two other prefixes named by private evidence
were retained, along with current compiler/test outputs, `build/bench`, and the
Zig cache.

Pinned measurements, qualification reports, rejected experiments and integration
artifacts remain under [benchmarks/evidence](../benchmarks/evidence). Their raw
records and hashes identify the candidate they measured; moving a record does
not refresh its qualification.

## Historical validation snapshot

At the time, 75 affected host/parser/CLI/API checks and six editor checks
passed; 3,001 native laws compiled with the cached Safe/noLLVM artifact and Zig
lint had zero findings. The full guest gate stopped after 158 passes at the
known `acyclic_updates_execution.test.ts` owned-storage admission gap. Two
nested-array memory-profile cases also remained unsupported. These were recorded
as open issues, not passes. The source-path references and test totals in this
snapshot refer to that earlier layout and run.

## Repository layout follow-up

The
[layout evidence](../benchmarks/evidence/integration/2026-11-04-repository-layout.json)
records the subsequent physical reorganization and caller updates. Zig now owns
`compiler/`; Deno tools live in `host/`; tests, benchmarks and reference
material have separate roots. There are no compatibility directories. Historical
raw records and all Blot programs remain byte-identical, and the README retains
both benchmark charts.

The checked batch passes 57 tooling, six editor, 55 host/migration and 68 guest
path checks, plus three native path laws. The normal syntax development check
passes 12 native laws and 20 guests in 9.64s, including complete native
compilation, formatting, types and Zig lint. Package and standalone API checks,
publication dry-run and a paired Goose quicksort smoke pass. Gdev compiles in
5.66s to the unchanged 10,049,963-byte Wasm; a fresh inspected NVIDIA frame
matches the preceding PNG and trace byte for byte. This is a layout check, not a
compile-speed improvement.

The full gate stops at its 180s cap after smoke/harness and 77 native passes
without test failures. Full qualification and the existing storage-admission
gaps remain pending. Pen's stale generated structured host bundle was rebuilt
through its generator; missing web-service and example-build artifacts still
limit sibling coverage. An existing diagnostic-span snapshot was corrected using
the unchanged compiler and original fixture as a control.

A Btrfs atomic-replacement error blocked the final development build despite
reported free space. Removing 151 older rebuildable cache directories reclaimed
5.02GiB and restored writes. Installed binaries, recent cache entries, source,
assets and measurement artifacts were preserved; the successful retry includes a
0.55s cached native test build.
