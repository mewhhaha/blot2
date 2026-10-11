# Partial collection layouts

Task 097 preserves array/cursor representation facts without defaulting language
variables. Empty arrays and nominal data with unused type parameters can pass
through generic iteration. Generalized helpers remain reusable at U32 and F32.

Named and closure inference regions copy unresolved physical shapes through the
existing synchronous `CodeProjection` boundary. Layouts own the copied heads; no
solver ID, mutable region or semantic proof escapes. Erased positions and
unknown callback rows stay open. `layout.mergePartial` combines compatible facts
while rejecting different scalar heads, nominal identities, physical record
slots and known effect rows. Queries that require physical projections publish
no semantic receipt; they rebuild their shapes on the next query.

The abandoned checker default changed type-witness results and narrowed staged
builders. Its experiments remain ignored under `build/wip/`; the checker has no
new defaulting rule.

## Qualification, 11 October 2026

Implementation revision: `f2b41b4`. Baseline: `c226967`.

- Zig 0.17.0. Full native suite and 651 guest/client tests pass
  (`deno task test:compiler`). Analyzer: 315 files, zero findings.
- Native laws cover empty and phantom-element cursors, generic reuse and failed
  allocations. Layout laws cover nested holes, known-row conflicts and scalar
  conflicts. Four executed-Wasm laws also cover staged builders and
  fresh/retained edits through empty, U32, F32 and empty again.
- gdev regular suite: 472 passed, zero failed, 54 modules (375 checks, 91 traps,
  six expected rejections). Blocked app/sandbox copies: ten checks passed.
- All 13 public examples and all four synthetic workloads emit byte-identical
  Wasm. Synthetic fresh and retained phases agree across three paired runs.
- Frozen gdev: 840,534 bytes, SHA-256
  `3158216b0b7cb072245d9aa149887a39bbadbc305430569ae3e033818e3edef0`. Edited
  fresh and retained output also agrees; rejected edits recover unchanged.

Three alternating runs measured compiler process CPU in milliseconds (10 ms
resolution). LLVM native-test compilation ran concurrently; these short samples
establish no speedup. Full samples and binary pins are in
[qualification/partial-collections-gdev.csv](qualification/partial-collections-gdev.csv)
and
[qualification/partial-collections-pins.json](qualification/partial-collections-pins.json).

| Phase                 | Baseline min / median / max | Candidate min / median / max |
| --------------------- | --------------------------- | ---------------------------- |
| Fresh                 | 1410 / 1460 / 1460          | 1370 / 1440 / 1620           |
| Edit                  | 580 / 600 / 640             | 600 / 600 / 670              |
| Revert                | 510 / 520 / 600             | 520 / 530 / 540              |
| Rejected              | 270 / 280 / 280             | 270 / 280 / 290              |
| No-op after rejection | 0 / 10 / 10                 | 0 / 10 / 10                  |

At this representation milestone, the separate task 099 split-hauling fixture
still exited with signal 11, before emission. Task 099's `5340ef2` fixes export
handling of empty catalogs after inference budget exhaustion. The fixture now
reports `inference_budget` and remains uncompiled; task 097 retains that open
compilation qualification.

## Completed fixture gate

The remaining fixture gate is completed by `881c6ab`. Pending selections sleep
on unknown receivers instead of retrying while unrelated stages settle. The
current regular suite passes 472 cases across 54 modules, and the remaining
blocked module compiles and passes all 12 exports/25 assertions.
[PENDING_SELECTIONS.md](PENDING_SELECTIONS.md) records the public step-bound
law, byte/diagnostic identity, complete compiler qualification and remaining
quadratic type growth. No semantic default or budget increase was added.
