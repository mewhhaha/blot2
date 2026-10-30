# 019 — Serialize the query table

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `ea4a7f3`.
- **Dependencies:** [018](018-migrate-executable-reuse-queries.md)
- **Originating requirements:** PLAN: Hill 12 / query archives. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Serialize complete query records through the dependency format and backend
checkpoints.

## Starting point

[dependency_format.zig](../zig-native/src/reuse/dependency_format.zig),
[backend_checkpoint.zig](../zig-native/src/backend/backend_checkpoint.zig),
[principal_archive.zig](../zig-native/src/reuse/principal_archive.zig) and
[optimized_archive.zig](../zig-native/src/reuse/optimized_archive.zig) already
encode bounded portable candidates, with compiler identity and checksums.

## Implementation checklist

- [x] Version typed query keys, dependency records and supported values in both
      archive paths.
- [x] Encode owned portable data only; reject native pointers, capacities,
      unresolved solver IDs and incomplete records.
- [x] Validate sizes, counts, indexes, exact identities and checksums before
      atomic import; preserve optional-cache fallback and explicit-import error
      behavior.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Round-trip each supported query kind across processes and compare behavior
  with fresh work.
- Exercise truncation, corrupt lengths, unknown versions, identity mismatch,
  duplicate records and missing dependencies.
- Sweep allocation failure in decoding/import/publication and verify no
  half-published query survives.

## Acceptance criteria

- [x] Complete supported query records survive both serialization paths with
      reconstructed ownership.
- [x] Corrupt, incompatible or incomplete inputs decline safely under the
      documented cache/import contract.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `ea4a7f3ef23ebf8506fe85eefa24f51ee65c3024` (compiler milestone).
- Implementation:
  [portable_query.zig](../zig-native/src/reuse/portable_query.zig) defines typed
  sections (`version`, kind, schema, claim). Principal archives move to key v3,
  optimizer captures and backend checkpoints to v2. Only complete principal
  proofs with observations and sealed optimizer tables are encoded. Decoding
  validates every structural ordinal, evidence edge, body operand, control frame
  and record/input correspondence before exposing an owner, then rebuilds native
  indexes and recomputes fingerprints. Refinement, specialization, local
  templates, source validation and executable fragments are declined kinds that
  recompute after restart.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 624 guest/client tests, including a law
  that restarts every public example from its own checkpoint;
  `deno task lint:zig` reports zero findings across 303 files (analyzer CI pin
  `756bfd5`); `deno task package:check` passes its dry run. 31 focused
  `portable` native tests cover corrupt, incompatible, forged and incomplete
  inputs, existing allocation-failure sweeps cover decode through publication,
  and six validator-weakening mutants are all killed.
- Comparison: baseline `e018d8d` (`8a758ae2…`) versus candidate `69e8692e…`, 31
  alternating rounds over 18 workloads (3,348 CLI builds): identical Wasm in
  every fresh/population/restart phase with equal reuse. Example checkpoints
  grow 9.6–19.6%; requested allocation rises at most 0.90% (population) and
  1.15% (restart); in-process decode CPU rises by a 1.156× geomean, below 0.25%
  of each median restart. No speedup or slowdown is claimed.
- Remaining limitations: task 020 owns broader persisted semantic graphs.
  Decoded machine bodies are checked for ordinals and control but not
  re-typechecked; checksum, compiler identity and host Wasm validation remain
  the final checks. Cross-space type/row cycles are bounded by importer limits.
  The unchanged principal input gate still reuses at most one call-publishing
  record per fresh session. At this milestone the private gdev snapshot did not
  match the local `../gdev` checkout and the cloud task-018 pins were absent, so
  large-program measurement was left to task 084.
- Durable record: [portable query records](../zig-native/PORTABLE_QUERIES.md),
  [restart distributions](../zig-native/qualification/portable-queries-restart.csv),
  [decode distributions](../zig-native/qualification/portable-queries-decode.csv),
  [pins](../zig-native/qualification/portable-queries-pins.json),
  [restart driver](../zig-native/qualification/portable_queries_restart.ts),
  [decode driver](../zig-native/qualification/portable_queries_decode.ts) and
  [decode probe](../zig-native/qualification/portable_queries_decode_probe.zig).
