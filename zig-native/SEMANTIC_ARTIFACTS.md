# Persisted semantic artifacts

Task 020 extends backend checkpoints from individual query records to a complete
previous-revision semantic owner. A restarted process can replay completed
selected specialization receipts through the same Gate, Importer and graph Plan
that admit an in-process previous revision. This record follows
[portable query records](PORTABLE_QUERIES.md) and
[the typed query contract](QUERY_TABLE.md). Qualification is recorded below.

## The persisted owner

[semantic_archive.zig](src/semantic_archive.zig) encodes, under settings key
`blot-semantic-archive-v1`, a section of claim `selected_complete_proof` (kind
`specialization`, schema 1) together with the graphs those receipts name:

| Part                      | Contents                                                                                                                                                          |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Units                     | Unit ordinal, canonical producer path, module stamp and the exact checked Core, including type-node certificate bytes                                             |
| Namespace                 | The identity metadata: symbol spellings and owner paths                                                                                                           |
| Evaluator snapshot        | Values, children, closures, value evidence, type/row mappings, the evidence graph, value records, record layouts, field names, demands                            |
| Slots and field locations | One slot per binding in unit order; exact physical field positions required before any import                                                                     |
| Selected receipts         | Key (input, expected, options, depth), dependencies (storage counts, sources, scalar/call reads, call publications, typed views, plain facts) and selected result |

Structural equality and module stamps cover the solver certificate bytes in type
nodes. The dependency format deliberately drops those bytes from `types.Node`,
so each unit carries them as a separate word array (empty when all are zero) and
decoding restores them before any check. Binding offsets are recomputed from
Core rather than trusted.

The backend checkpoint key moves to v3 and its wire gains a `semantic` byte
section. Encoding omits the section when the capture has no complete project
namespace, when it holds no completed selected receipt (nothing could be
replayed), and when the owner exceeds the artifact element limit; restart then
recomputes. A decoded checkpoint owns a `semantic_archive.Archive`: the decoded
Core array plus a Capture whose pools pin it.

## Validation before exposure

Decoding checks, in order:

- the section header (version, kind, schema, claim);
- the namespace: owners equal the unit count, every symbol and owner spelling
  resolves, owner paths are nonempty UTF-8 without NUL, unique and equal to each
  unit's canonical path;
- each unit's ordinal and Core unit, certificate length and width, then full
  [frozen Core validation](src/frozen_core_validation.zig) against its sibling
  units and the namespace's symbol bound. Stamps are accelerators: every Gate
  recomputes them from the decoded Core and disables itself on a mismatch before
  its exact graph comparison;
- the evaluator snapshot: the shared evidence graph check, one evidence entry
  and one record entry per value, child spans and child ordinals, closure
  ordinals, mapping spans, mapping evidence and rows, record layouts within the
  field-name table, and demand values;
- one slot per binding with in-range values, and field locations whose family
  unit is a source unit or the builtin unit and whose name is a namespace
  symbol;
- each receipt: a closure input, a function-typed expected evidence, an in-range
  selected value, storage counts within the snapshot, and source, scalar-read
  and call bindings inside their decoded unit.

Only then does decoding move the owned arrays into a Capture and rebuild the
selected index in wire order through `selected_query.remember`; the table's own
completion and limits still apply. Allocation failure at any point leaves the
decoded snapshot as the sole owner and releases everything.

The persisted owner is supplied only as `query_previous` when the compile has no
in-process previous revision. Its emission recorder is unsealed and it has no
optimizer capture, so executable fragment reuse and the retained principal
evidence path never see it. The Gate still requires the identical namespace,
compares every persisted Core with current Core exactly (`moduleEqual`, never
the stamp alone), validates dependencies, propagates dirty declarations and
admits each receipt's sources. The Importer still requires exact field locations
and imports evidence/rows into the current owner; the graph Plan still matches
every captured value and publishes atomically.

## Represented and declined

| Result                                                                                                                            | Across processes | Reason                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Completed selected specialization receipts                                                                                        | Yes              | Complete owner above; ordinary admission against current source                                                                            |
| Principal complete proofs                                                                                                         | Yes (task 019)   | Their importer now also admits builtin State/Computation nominals (unit `maxInt(u32)`, declarations 1–6), matching the in-process importer |
| Optimizer outputs                                                                                                                 | Yes (task 019)   | Exact machine inputs and outputs                                                                                                           |
| Executable fragments and emission                                                                                                 | No               | Need emission pools, jobs and relocations; recomputed                                                                                      |
| Retained principal evidence through a previous capture                                                                            | No               | Requires a sealed emission; the principal archive covers restart                                                                           |
| Layouts, captured templates, substitutions, static values, operations, provider/request state, break values, array/discard proofs | No               | Not read by selected replay; never partially encoded                                                                                       |
| Checked-Core dependency certificate                                                                                               | No               | A native image; the Gate revalidates                                                                                                       |
| Refinement, canonical specialization, local principal templates, independent call proofs                                          | No               | Session-local or parallel-only                                                                                                             |
| Builtin effect operations in imported graphs                                                                                      | Declined         | Both in-process and portable importers decline them                                                                                        |

## Related fixes

- Resolver continuations bind the checker's synthetic local payload, so Core
  closures can carry a `.local` parameter binding. Frozen Core validation
  required `.parameter`, so `blotc dependencies` failed with `InvalidArtifact`
  for any library containing a monadic `do`. Validation now admits `.local`
  parameter bindings; a dependency artifact with a monadic library packs, loads
  and executes.
- The backend built a fresh query Gate inside an optional's struct literal. An
  allocation failure in `Gate.initWithStamps` left the optional non-null with a
  partial Gate, and teardown crashed. The Gate is now initialized before the
  optional. Restart allocation-failure sweeps exposed this path.
- `dependency_format` encoding now sizes the payload in a counting pass and
  writes header and body into one exact allocation. Wire bytes are unchanged;
  every artifact encode avoids list growth and the final copy.

## Qualification on 10 October 2026

The baseline is the task-019 release compiler (`ea4a7f3` sources, SHA-256
`69e8692e88c0e49fa63e25fe3d42100dcec085ee048bb900acb2d2c2ac36f0d5`). The
candidate release compiler is SHA-256
`640c744df0e3eb10ef7f8e9189b899949bbd0baafb407c9b8cc248baa7e802f1`, 422-file
input map `052419dbb6c0c04e8b1c0d6d522719d0b8edec642a0eb46d897e3eb1eb22362f`.
[The pins](qualification/semantic-artifacts-pins.json) retain compilers, probes,
drivers, workloads, loads and machine conditions.

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and **626** guest/client tests; `deno task lint:zig` reports
  zero findings across 305 files at analyzer pin `756bfd5`.
- [Native laws](src/semantic_archive_tests.zig) cover restart replay with fresh
  output parity under an allocation-failure sweep of decode, Gate, import and
  publication; edited bodies, captured values and recursion plus a failing
  source; forged namespaces, Core graphs, certificates, values, closures, slots,
  receipts and field locations; a forged stamp that decodes but admits nothing;
  and omission without a namespace or a replayable receipt.
- [The example restart law](tests/portable_query_restart.test.ts) now requires
  selected reuse after restart for every example that records a complete
  receipt. [Process-boundary laws](tests/semantic_artifacts.test.ts) pack a
  monadic library into a dependency artifact, execute it, restart a
  dependency-loaded project from its checkpoint with selected replay, and
  compare edited, failing and corrected revisions with fresh servers.

### Measurements

[The restart driver](qualification/portable_queries_restart.ts) ran 31
alternating rounds over 13 public examples and five generated workloads (3,348
CLI builds); [the decode probe](qualification/portable_queries_decode_probe.zig)
decoded each compiler's own checkpoint 200 times per round for 11 rounds. All
phases of both compilers emit identical Wasm; every restart loads; principal and
optimizer reuse are equal. Raw data:
[restart](qualification/semantic-artifacts-restart.csv),
[decode](qualification/semantic-artifacts-decode.csv).

| Workloads                                                                                 | Checkpoint      | Restart requested allocation | Decode CPU            | Restart median CPU             | Selected receipts replayed |
| ----------------------------------------------------------------------------------------- | --------------- | ---------------------------- | --------------------- | ------------------------------ | -------------------------- |
| 7 with a persisted owner (ecs, generic_effects, host_io, prelude, requests, syntax, tags) | +177 to +338 KB | +1.12 to +1.86 MB            | 66–252 → 552–1,114 µs | +14% to +26% (+1.2 to +3.4 ms) | 1–3 each                   |
| 11 without a replayable receipt                                                           | +4 bytes        | −4 to −135 KB                | Unchanged             | Within noise                   | 0                          |

Population requested allocation falls for owner-free workloads (exact-size
encoding) and rises 289–355 KB where an owner is written. Peak requested memory
rises up to 821 KB (ecs restart) and is otherwise unchanged. The code-identical
fresh phase ranged 0.897–1.044, so the restart increases exceed this run's
noise. One-minute load was 22 at the start and about 7 for most rounds, on an
unpinned interactive host.

On these small programs the persisted owner costs more restart CPU than its one
to three replays save: decoding and validating every unit's Core, then the
Gate's exact comparison, outweigh the avoided specialization work. Larger
programs with expensive specializations may recover the cost, but the private
gdev workload remains unavailable, so no restart speedup is claimed.

## Remaining scope

- The decode-time frozen Core validation and the Gate's own dependency
  validation both run on restart; a decode-issued validation certificate could
  remove the second pass.
- Executable fragments, the retained principal path and the other declined
  owners above still recompute after restart.
- Builtin effect operations remain declined by both importers.
- Restart benefit on large programs is unmeasured until the private gdev
  snapshot is available (tasks 002 and 084).
