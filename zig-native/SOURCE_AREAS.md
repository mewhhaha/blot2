# Source areas

Compiler sources live under `src/` by responsibility. Tests stay beside the code
they exercise; root suite modules select execution shards without changing those
ownership boundaries.

| Area           | Responsibility                                                           |
| -------------- | ------------------------------------------------------------------------ |
| `src/parse/`   | Tokens, syntax, symbols and source diagnostics                           |
| `src/check/`   | Source checking, types, Core construction and frozen semantic validation |
| `src/eval/`    | Compile-time values, specialization and evaluation                       |
| `src/backend/` | Resolved plans, representations, static data and Wasm emission           |
| `src/reuse/`   | Retained projects, query owners, artifacts and project protocol          |
| `src/runtime/` | Generated guest runtime, ownership and collection operations             |

The source root retains the executable entry, suite aggregators, test runner and
shared allocation, work-counter and execution-policy helpers. External Source
fixtures remain in `fixtures/`, imported through the test-only fixture module.
There are no compatibility forwarding modules.

Build roots remain `src/main.zig` and the root suite modules. Compiler identity
walks actual production imports recursively, including relative imports across
areas. Analyzer traversal scans all areas and the fixture module; focused lint
follows the reverse import closure. Packaging exports the same public Deno API.

The 15 October move relocates 464 of 483 Zig source files. The matched dev
comparison preserves exact Wasm, ordered diagnostics and source work across
fresh, literal-edit, revert, failed-edit recovery and process restart.
Dependency archive wire version, settings/source/dependency keys, checksum and
serialized payload also agree. Schema and compiler identities intentionally
change: the schema hashes Zig type names, whose module qualifiers change with
the layout. Old archives therefore use the ordinary incompatible-cache fallback.

Dev build, all native test interfaces, selected test discovery, fingerprint laws
and seventeen tooling laws pass. Analyzer coverage is 483 source files plus the
fixture module, with zero findings. Sixty-one editor/client/protocol laws and
the grammar corpus plus seven example parses pass. The editor CLI is pinned
to0.27.1 in the tool record. Package publication dry run passes after including
the existing cleanup-data dependency in the public module graph. It checks the
existing bundle; the final release bundle is still pending. The full move map,
original before tree, source/binary pins and exact comparison are preserved in
`build/bench/finish-rest-20261015/source-areas/`. The release build and final
combined compiler gate remain pending; focused parity does not qualify later
semantic changes.

The pure moved tree is reconstructed from the original before files with the
final move map, rebased imports and Zig formatting. At that checkpoint all483
files agree with Root except the five explicitly pinned later rank/numeric
amendments. The manifest `qualified-layout-pins.json` has SHA-256
`9046a19381ca59959280dd6b74b6f9b529e2fab58788a95bf6f0533e40fed52d`. Initial
staged manifests are retained separately; their after hashes precede the
corrected root-helper imports and are not the qualified layout pins.

Native qualification resume keys include both recursive production source and
the external fixture module. Fixture edits, additions and deletions invalidate
completed native evidence; guest-only assertion repairs retain valid native
results. Six harness laws exercise the actual process/journal behavior,
including cancellation and failed-phase cleanup. Local documentation audit
checks199 pages,1,573 file/anchor references and finds no dangling targets.

All eight runtime fixture programs use one source-root entry selected by an
exact build option. This allows imports across source areas while preserving Zig
module boundaries and removes repeated build blocks. The complete seven-fixture
execution passes77 groups; the opt-in packed fixture also builds. Cohort
controls use actual transferred member leases and journal records, including a
real second-page spill and transactional premature-retirement rejection.
Production runtime behavior is unchanged.
