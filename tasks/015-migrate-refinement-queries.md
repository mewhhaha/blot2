# 015 — Migrate refinement queries

## Status, dependencies, and originating requirements

- **Status:** Complete — bounded common ownership/transaction/index primitives
  and the refinement adapter qualify at `bfcb464`.
- **Dependencies:** [014](014-specify-unified-query-table.md)
- **Originating requirements:** PLAN: Hill 12 / refinement-first migration.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Move refinement receipts and their indexes into the common query model.

## Starting point

[refinement_receipt.zig](../zig-native/src/refinement_receipt.zig),
[completed_specialization_query.zig](../zig-native/src/completed_specialization_query.zig)
and [shared_query_gate.zig](../zig-native/src/shared_query_gate.zig) hold
current refinement lookups;
[source_value_template_tests.zig](../zig-native/src/source_value_template_tests.zig)
exercises dynamic facts and publication.

## Implementation checklist

- [x] Implement the task 014 query primitives and migrate refinement keys,
      dependencies, results and first-match indexing.
- [x] Preserve dynamic scalar/plain-data facts, imported evidence, expected
      shapes, seeds and exact source admission.
- [x] Check collisions with full equality and publish only complete owned
      results; retire replaced refinement indexes after parity.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run refinement/source-template laws covering multiple matching candidates,
  collision buckets, changed catalogs and source-ID remapping.
- Compare fresh/retained output, repeated revisions, failed edits,
  dependency/checkpoint round trips and allocation-failure publication.
- Measure lookup work and retained storage to ensure the common table does not
  add unbounded indexing overhead.

## Acceptance criteria

- [x] Refinement results flow through the common table with the same first-match
      and validity behavior.
- [x] Superseded refinement indexes are removed after parity, and no dynamic
      fact or imported evidence check is lost.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `bfcb464` — local compiler milestone; no push.
- Validation: Zig 0.17.0; full LLVM native suite and **622 guest/client tests**
  via `deno task test:compiler`; `deno task lint:zig` checks **298 files / zero
  findings**; `deno task package:check` passes. Focused production batch runs
  **50 actual query/refinement/source-template laws**, including allocation
  failures, collision order, token ownership and exact capacity ceilings.
- Comparison: **626 cases / 3,756 six-policy invocations**, exact ordered
  diagnostics/Wasm and zero tracked teardown; corpus execution **192 guests /
  10,362 calls**. Broad retained qualification **2,106 revision samples / 648
  guests / 41,208 calls**, plus three refinement widths **234 samples / 72
  guests / 12,312 calls**, cover dependency edits, failures/recovery and
  restart.
- Measurements: **86 workloads × 15 alternating pairs / 2,580 fresh processes**;
  geometric CPU/wall ratios 1.0056/1.0033 versus task 013. **11 workloads ×
  seven pairs / 12,936 native phases**, plus **462 fresh/cache/restart CLI
  samples**, preserve bytes, plateau retained storage and teardown to zero. All
  sorted distributions, source/driver/library pins and query snapshots are
  tracked.
- Remaining limitations: only refinement migrates. Other adapters and portable
  representation remain tasks 016–020. Storage/CPU overhead is measured and
  bounded, with no speedup or global allocation reduction claim. The initial
  full gate's new TS law omitted two null unit arguments; corrected v2 passes
  with the identical native binary. Private gdev/original boxed artifacts remain
  absent, keeping tasks 002/084 open.
- Durable record:
  [representation, limits and qualification](../zig-native/REFINEMENT_QUERIES.md),
  [pins](../zig-native/qualification/refinement-queries-pins.json),
  [fresh distributions](../zig-native/qualification/refinement-queries-fresh.csv),
  [retained distributions](../zig-native/qualification/refinement-queries-retained.csv).
