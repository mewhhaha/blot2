# Continue the owned-storage rewrite

## Current frontier

This is a greenfield project. Breaking changes are welcome; remove superseded
APIs and implementations. Preserve useful behavior, assertions, deterministic
math, original workloads and independent references. Read `AGENTS.md`,
`compiler/guide.md`, `zig-native/CONTRACT.md` and `tasks/STORAGE_REWRITE.md`.

One actual Gdev main frame passed native Pen with an inspected 640×480 startup
letter-board PNG. Its exact historical compiler, sources and result are in
[the first-frame record](tasks/storage-handoff-evidence/2026-10-31-first-frame.json)
and [screenshot](tasks/storage-handoff-evidence/2026-10-31-first-frame.png).
That frame used compiler SHA `e6ccd2d4…`; later fixes require a fresh real
frame. Broader gameplay, browser, recovery and release qualification remain
open.

The remaining source migration has reached the full Ink/Gdev inventories,
fixtures, generators and active documentation. Current language uses `func`,
explicit `return`, curried `->`, `$Constructor`, primitive booleans, `and`/`or`
and `#[...]` arrays. Grammar-rejection fixtures, foreign shader syntax and
historical captures intentionally retain their own text. Generated sources must
come from generator inputs, never manual output patches.

## Checked compiler fixes

The installed development compiler is the reviewed contract-method candidate, SHA
`9902355fc8b3735371e38495d741c84122e7eae9fa583d1fd650d343ded09929`. Older exact
candidates remain local build artifacts; portable evidence qualifies its named
candidate rather than every later revision.

- [Imported opaque layouts](tasks/storage-handoff-evidence/2026-10-31-opaque-layouts.json)
  use exact closed producer metadata while preserving public opacity.
- Loop refinements, literal SIMD forwarding, proven-empty nested rows and
  impossible pattern fallbacks have executed regression coverage in the linked
  records under `tasks/storage-handoff-evidence/`. Original hauling and full
  packet fixtures now run without dummy rows or altered algorithms.
- [Lexical schemes](tasks/storage-handoff-evidence/2026-10-31-lexical-schemes.json)
  use bounded immutable lists, avoiding sparse temporary-fact saturation.
- [Indexed mutation](tasks/storage-handoff-evidence/2026-10-31-indexed-fields.json)
  preserves original owner and selected-field equations, including two indices.
- [Callback values](tasks/storage-handoff-evidence/2026-10-31-callback-values.json)
  align source/Core recipe classification while keeping invocation and no-store
  checks strict. All six original Gdev restore tests and both rejection tests
  pass. The latest native inventory compiles 2,730 tests; 435/436 affected laws
  pass with the same independently reproduced associated-partial baseline
  failure. All 61 affected guest tests pass.

[Contract methods](tasks/storage-handoff-evidence/2026-10-31-contract-methods.json)
now select exact visible implementations with full signature/effect evidence
and context-sensitive reusable calls. Original Gdev language tests and Ink
custom-codec persistence, including all 260 truncated inputs, pass on the final
candidate. Actual main must be rechecked on this binary.

Astra xhigh reviewed the semantic fixes. The required full compiler gate was
attempted for each batch but stops before tests because the configured proxy
blocks locked Baba 9.0.1 from `npm.jsr.io`. No dependency, lockfile or TLS
workaround was applied. Changed files have no new analyzer findings; four
existing checker warnings and the broader 25-finding baseline remain visible.

## Remaining execution work

Source checks are distinct from emitting original exports and running
assertions. Ink's completed inventory reports 322 passes and three expected
invalid fixtures; rerun after source changes. Gdev's 441-file inventory had
three restore-family failures cleared by the callback fix and one icon-preview
API migration. Refresh the final inventory after that tool/generator batch.

Current execution frontiers include parser array-element layouts, actor
presentation-reference qualification and the full affordance
fixture. Original prepared-physics replay comparisons pass through the smaller
batch counts; the 2,048-body case traps and needs diagnosis with unchanged
limits. All nine original adapter entries now pass 71 cases per mode after
restoring their required request-bitset owner. Preserve original workloads and
assertions while resolving remaining issues.

Ordinary legacy backend retirement is still unfinished (task 120). Some pure
programs still emit ABI 3; do not fake ABI 8 with unused owners or claim that
the whole rewrite is complete. Task 121 covers final behavior and measurements.
Release/performance claims require the qualified release compiler.

## Integration and checks

Use the existing sibling checkouts. Build with Zig 0.17.0, checking
`zig version` first, and `-Dllvm=false` for development/native tests. Use
coherent affected batches and the required full gate as documented in
`AGENTS.md`.

Run actual Gdev main through native Pen, including its real imports and assets:

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

Require every runner check and inspect the PNG. For a compile-only diagnosis:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

The reusable frontend inventory checks unused declarations through overlays:

```sh
deno run --no-config --no-lock -A scripts/migration_audit.ts --project ../gdev --expectations ../gdev/tests/migration_expectations.json --report /tmp/gdev-audit.json
```

It does not emit original exports or execute their assertions. Its project
source digest excludes external library snapshots; rerun after dependencies
settle. Keep large outputs ignored and commit concise portable evidence.

## Frozen contracts

- ABI 8, session 2, Gdev saved framing 26 and packet order remain fixed.
- Gdev storage: 2 MiB temporary, 256 KiB persistent, 2 MiB transport, 4,096
  owners. Reply budget: 64 MiB including assets.
- Production expansion: 500,000 expressions per physical function; layout work:
  100,000. Engine bounds: 7,654,321 body bytes, 50,000 parameters/locals and
  1,000,000 globals. Do not raise these limits to pass fixtures.
- Named owners are independent. Access records alias live pools. Borrowed views
  remain invocation-local; copy retained history and host/worker packets.
  Preserve callback effects and explicit checkpoint/restore. Renderer rejection
  is not rollback. Language tasks are retired; copied-packet workers remain.
- Gdev FrameAccess has 165 fields and four explicitly pure storage callbacks.
  Preserve exact generic field types and real latent callback effects.

Continuously commit coherent checked batches to each `main` and verify remote
hashes. Preserve unrelated work. Environment publication requires a separate
explicit request. Older checkpoint narratives remain in pinned Git history and
portable evidence, rather than duplicate continuation documents.
