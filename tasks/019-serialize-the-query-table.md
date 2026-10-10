# 019 — Serialize the query table

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `ea4a7f3`.
- **Dependencies:** [018](018-migrate-executable-reuse-queries.md)
- **Originating requirements:** PLAN: Hill 12 / query archives. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Serialize complete query records through the dependency format and backend
checkpoints.

## Starting point

[dependency_format.zig](../zig-native/src/dependency_format.zig),
[backend_checkpoint.zig](../zig-native/src/backend_checkpoint.zig),
[principal_archive.zig](../zig-native/src/principal_archive.zig) and
[optimized_archive.zig](../zig-native/src/optimized_archive.zig) already encode
bounded portable candidates, with compiler identity and checksums.

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
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

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
- Implementation: [portable_query.zig](../zig-native/src/portable_query.zig)
  defines typed sections (`version`, kind, schema, claim). Principal archives
  move to key v3 and optimizer captures to v2; backend checkpoints move to v2.
  Only complete principal proofs with observations and sealed optimizer tables
  are encoded. Decoding validates every structural ordinal, evidence edge, body
  operand, control frame and record/input correspondence before exposing an
  owner, then rebuilds native indexes; fingerprints are recomputed. Refinement,
  specialization, local templates, source validation and executable fragments
  are declined kinds that recompute after restart.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 624 guest/client tests, including a new
  law that restarts every public example from its own checkpoint.
  `deno task lint:zig` reports zero findings across 303 files with the analyzer
  at CI pin `756bfd5`; `deno task package:check` passes its dry run. 31 focused
  `portable` native tests pass, covering truncation, corrupt lengths and bytes,
  unknown envelope/section versions, kind/claim/schema mismatch, compiler and
  settings identity, duplicate records, missing dependencies, forged ordinals,
  builtin identities, unsealed/saturated tables and exact rebuilt indexes.
  Existing allocation-failure sweeps cover decoding, index construction, import
  and publication. Six validator-weakening mutants are all killed. The
  process-boundary checkpoint test round-trips both kinds and falls back on an
  unknown envelope version and corrupt bytes.
- Comparison: baseline `e018d8d` rebuilt locally (`8a758ae2…`), candidate
  `69e8692e…`. 31 alternating rounds over 13 public examples and five generated
  principal workloads (3,348 CLI builds) give identical Wasm in every
  fresh/population/restart phase, equal principal hits and optimizer reuse, and
  deterministic allocation. Checkpoints grow 9.6–19.6% on examples (optimizer
  records repeat call/lifetime facts) and 37 bytes on principal-only workloads.
  Requested allocation rises at most 0.90% (population) and 1.15% (restart);
  peak memory is unchanged. In-process decode CPU rises by a 1.156× geomean (−6
  to +47 µs), below 0.25% of each median restart. CLI CPU on this loaded
  interactive host cannot resolve the change (code-identical fresh ratios
  0.640–1.336); no speedup or slowdown is claimed. The synthetic `bench:compile`
  restart-cache run verifies cross-compiler and fresh/retained/restart Wasm
  parity.
- Remaining limitations: task 020 owns broader persisted semantic graphs.
  Decoded machine bodies are checked for ordinals and control but not
  re-typechecked; checksum, compiler identity and host Wasm validation remain
  the final checks. Cross-space type/row cycles are bounded by importer limits.
  The unchanged principal input gate still reuses at most one call-publishing
  record per fresh session. The private gdev snapshot does not match the local
  `../gdev` checkout and the cloud task-018 pins are absent, so tasks 002 and
  084 stay open.
- Durable record: [portable query records](../zig-native/PORTABLE_QUERIES.md),
  [restart distributions](../zig-native/qualification/portable-queries-restart.csv),
  [decode distributions](../zig-native/qualification/portable-queries-decode.csv),
  [pins](../zig-native/qualification/portable-queries-pins.json),
  [restart driver](../zig-native/qualification/portable_queries_restart.ts),
  [decode driver](../zig-native/qualification/portable_queries_decode.ts) and
  [decode probe](../zig-native/qualification/portable_queries_decode_probe.zig).
