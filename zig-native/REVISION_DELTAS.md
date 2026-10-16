# Transactional revision deltas

Task 021 stops rebuilding every artifact pool field on each successful revision.
Fields whose captured content equals the previous revision's share that
revision's immutable allocation through a refcounted lease; only changed fields
are copied. This record follows [the ownership contract](CONTRACT.md). The
compiler milestone is `696051e6db35a5464636131706e559092c9f37e6`; qualification
is recorded below.

## Leased pool fields

[pool_leases.zig](src/eval/pool_leases.zig) defines a `Lease`: one allocation,
its owning allocator, alignment and a reference count. `Pools.leases` holds an
optional lease for each of 41 plain slices: the identity namespace (bytes,
symbols, owners), layout graphs and rows, every evaluator snapshot array
including its evidence graph and rows, captured templates, field locations,
functions, serialized data, runtime globals and order, binding and node offsets,
slots, visited nodes, provider frames and cells, request cells and handlers,
break values and operation relocations.

`code_artifacts.capture` builds each of these through a lease `Builder`. With a
previous revision as the query predecessor, the builder compares the field's
source content with the previous leased slice: element bytes for types with a
unique representation, structural field equality otherwise. Equal content
retains the previous lease; anything else is copied into a new lease. Fields
sourced from hash maps are first ordered in a private temporary. A predecessor
without leases, such as a [persisted semantic owner](SEMANTIC_ARTIFACTS.md), is
never shared from. `Pools.deinit` releases leased fields and frees owned ones,
so manually constructed pools keep their ordinary ownership.

Module pins (per-revision canonical paths and Core pointers), substitution
tables, the representation bridge, runtime operation keys, array and discard
proofs and the dependency certificate stay per-revision owners. They are small
or hold nested owned slices.

`Pools.bodies` is removed. Its body pins copied every `core.Body` and hashed
each one against its module stamp on every revision, yet only a debug dump and
one test read them.

## Publication and failure

Leases are taken while preparing a candidate, never at commit. Commit still
moves the candidate's `Current` without allocation; releasing the old revision
drops its references, freeing blocks no live revision names. A rejected,
discarded or failed candidate releases every lease it took (`Builder.abort` on
error, `Pools.deinit` on discard), leaving the published revision's counts,
content and exported checkpoint unchanged. Captured slices are immutable after
publication; only reference counts change, on the owning Session's thread.

A lease names a single allocation, never a revision, so a chain of edits keeps
exactly the blocks still referenced by live pools. Steady edit/revert cycles
plateau in retained memory.

`WorkCounters` reports `metadata_shared_fields/bytes` and
`metadata_copied_fields/bytes` per compile. `snapshot_copy_bytes` and
`snapshot_copy_allocations` now count only evaluator fields actually copied.

## Qualification on 10 October 2026

The baseline is the task-020 compiler sources (`8803452`); the candidate release
compiler is SHA-256
`75ad482640273a9268479580f0457349cd7b07d8743dee29edcc69f97c764096`, 424-file
input map `9141a3311973ad2b4b96ab5e40fd3badfc9a26612f1c9ad9ad9398cacaeaeabc`.
[The pins](qualification/revision-deltas-pins.json) retain probes, drivers,
loads, conditions and per-phase summaries.

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 626 guest/client tests; `deno task lint:zig` reports
  zero findings across 307 files at analyzer pin `756bfd5`.
- [Lease laws](src/reuse/pool_lease_tests.zig): every nonempty leased field is
  shared exactly when its content equals the previous revision's, for identical
  and edited sources whose output matches fresh compilation; the earlier
  revision can be torn down first; an allocation-failure sweep of leased
  captures leaves every previous lease at one reference; twelve alternating
  edits plateau and tear down to zero. [Unit laws](src/eval/pool_leases.zig)
  cover sharing, copying, release order and refusal to share unleased owners.
- [A retained Session law](src/reuse/retained_candidate_tests.zig) sweeps every
  allocation failure while preparing a leased entry edit: the published
  revision's leases stay at one reference and its exported checkpoint bytes are
  unchanged; the same Session then commits the edit.
- Existing retained preparation, discard, unchanged-output and allocation
  failure laws pass with the new capture.

### Measurements

[The probe](qualification/revision_deltas_probe.zig), built with LLVM
`-OReleaseFast` against each tree, drives one retained Session per run: a
population, then nine rounds of edit, revert, rejected edit and no-op
correction. [The driver](qualification/revision_deltas.ts) ran 21 alternating
repetitions over eight workloads (literal, body, constant and import edits in
seven public examples), separating each run's first round. Both compilers emit
identical Wasm in every phase, and every phase's retained live bytes plateau.
Allocation counters are deterministic. Raw per-phase distributions:
[CSV](qualification/revision-deltas.csv).

| Phase (per revision)       | Requested allocation            | Peak requested | Retained live | CPU geomean   |
| -------------------------- | ------------------------------- | -------------- | ------------- | ------------- |
| Population                 | −45 to −112 KB                  | Unchanged      | −21 to −26 KB | 0.995         |
| Steady edit and revert     | −62 to −158 KB (−1.4% to −6.1%) | −25 to −98 KB  | −21 to −26 KB | 0.967 / 0.958 |
| Rejected edit (control)    | Unchanged                       | −21 to −26 KB  | −21 to −26 KB | 1.009         |
| No-op correction (control) | +656 bytes                      | −21 to −26 KB  | −21 to −26 KB | 0.992         |

Steady edits lease 1.8–43.4 KB of pool fields and copy 0–18.9 KB; the import
edit, which adds a unit, copies the most. The retained reduction comes mostly
from removing body pins. The no-op path, which captures nothing, requests 656
more bytes; that difference was not investigated. One-minute load was 6.6–8.8 on
an unpinned interactive host.

## Remaining scope

- Module pins, substitutions, the bridge, operation keys, array/discard proofs
  and certificates are still rebuilt each revision.
- Sharing is whole-field: one changed value copies its entire field. Finer
  segmentation (per unit or per value range) is not implemented.
- Comparison costs CPU comparable to a copy; the measured win is allocation,
  peak and retained memory, with a small edit CPU gain on these workloads.
- Gdev-scale retained edits are unmeasured without the private snapshot.
