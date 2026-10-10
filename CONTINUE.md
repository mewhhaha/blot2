# Continue here

Work follows [tasks/README.md](tasks/README.md): pick the lowest-numbered ready
or in-progress task. Use Zig 0.17.0, `deno task test:compiler` and
`deno task lint:zig` before each compiler commit.

## State on 10 October 2026

- Task 010 (variable-indexed solver worklists) is complete: `352b3ff`, closed in
  `6a4271c`.
- Task 002 (packed List F32 fold regression) is in progress. Commit `65dccda`
  hoists the crossing-row buffer and assembles two-leaf rows with two
  constant-size copies. F32 folds are now within 0.6–1.7% of boxed at widths
  14–16 and at or below 1.006 elsewhere; the all-width gate stays open.
- Task 004 (general principal/residual call summaries) is in progress. Commit
  `099e700` adds owned inferred first-order graphs and bounded export of
  all-unknown residual callee edges. Staged diamond factories share distinct
  bodies instead of unfolding paths. The native suite, 601 guest/client tests,
  393 public comparisons and zero-findings analyzer pass. General admission,
  including result-directed callee edges, remains unfinished; see
  [the qualification record](zig-native/CALL_SUMMARIES.md#owned-inferred-principal-graphs-9-october-2026).
- The structured/result-directed milestone admits source-owned physical and
  nominal residual relationships, preserves seeded operation rows, and keys
  complete result expectations. The full native suite, 603 guest/client tests,
  450 public comparisons and zero-findings analyzer pass. Task 004 stays open:
  representation headers still repeat work, and general type-head, comparison
  and handler admission is unfinished. See
  [the new qualification record](zig-native/CALL_SUMMARIES.md#structured-and-result-directed-graphs-10-october-2026).
- Cloud follow-up: a loop counter in storage words passed the native suite, 599
  guest/client tests and the pinned analyzer, but repeated release batches did
  not establish an F32 improvement and regressed a U32 tuple shape. It is
  unlanded; List lowering was restored to `65dccda`. See
  [the measurement record](zig-native/LIST_TRAVERSAL.md#word-positions-at-leaf-boundaries-9-october-2026).

## Next steps for task 002

The owner confirmed the original benchmark artifacts were probably local and
uncommitted. The cloud checkout lacks them and the frozen private gdev snapshot.
`build/bench/cloud-list/` contains a rebuilt pre-packed compiler, the unchanged
production baseline, the rejected probe and raw results. The rebuilt boxed
binary is a separate comparison, not the original pinned executable. Restore the
historical artifacts and verify the gdev snapshot against
`scripts/bench/gdev-manifest.json` before final qualification. The all-width
fold gate remains open.

1. Run the gdev compile comparison for the latest commit, allowing the intended
   Wasm difference:
   `deno task bench:compile --baseline build/bench/indexed-solver-lazy-release/blotc --candidate build/bench/list-two-block-crossing/blotc --runs 7 --workload gdev --allow-wasm-diff`.
2. Repeat the F32 record/tuple batches on a quieter host
   (`scripts/bench_list_traversal.ts BOXED NEW std OUT record|tuple 16 f32`,
   boxed compiler `build/compiler-hills/final/blotc`). If widths 14–16 stay
   above 1.0, investigate the remaining per-crossing cost (tree walk and the two
   64-byte copies feeding 4-byte loads).
3. Analysis tools from the original machine lived in
   `build/bench/f32-fold-analysis/` and are absent from this cloud checkout:
   `multi.ts` (hand-edited Wasm comparisons), `dump_seq.py` (TurboFan
   register-allocated sequences; trace with
   `--v8-flags=--trace-turbo,--trace-turbo-path=.,--trace-turbo-filter=wasm-function#N`
   and call the function before exiting).

## Next steps for task 004

Extend the owned graph representation in
[CALL_SUMMARIES.md](zig-native/CALL_SUMMARIES.md). Current open-edge admission
now retains source-owned physical structure and result-directed callee
relationships. Complete result/arrow inputs receive independent fresh jobs;
unknown destinations and witness-dependent failures retain ordinary checking.
Next, replace allocation-based open header keys with exact region-local keys
over only the public slots consumed by mandatory requirements. Equivalent live
inputs currently get different wrapper product IDs, and the depth-12
representation diamond still needs 24,616 constraint visits. Preserve private
binder independence, effect identities/cursors, original witness order and
rollback revocation. Then finish general type-head, type-comparison and handler
coverage before closing task 004. `build/bench/cloud-principal-graphs/` contains
the final `candidate-guarded/` pin, 393-case comparison, fifteen paired factory
measurements and seven-pair fresh/retained/restart comparisons. Factory depth 12
drops from 198.730 to 5.371 ms CPU and 19,420,315 to 4,783,635 requested bytes.
Ordinary typed workloads keep their counters; no general compiler or private
gdev speedup is claimed. Preserve the earlier selected-scheme pins as separate
baselines. The latest pin is `candidate-structured-result-v2/`; its depth-12
result diamond drops from 489.525 to 6.156 ms CPU and from 120,471,388 to
5,327,642 requested bytes. Small operation wrappers instead cost about 11% more.
Keep the rejected v1 pin and its failure logs separate from the passing v2
qualification.

## Notes

- Compare allocation release-to-release: debug `blotc` reports roughly 10% less
  requested allocation than release.
- `../zig-analyzer` currently has an uncommitted `double-release` rule that
  flags guarded `defer if (alive)` patterns (10 false positives). The CI pin
  `756bfd5` reports zero findings; run with
  `ZIG_ANALYZER=/tmp/blot-qualified-analyzer-756bfd5/zig-out/bin/zig-analyzer`.
  Those paths refer to the original machine. In the cloud checkout, use
  `ZIG_ANALYZER=/workspace/tooling/zig-analyzer/zig-out/bin/zig-analyzer`; its
  source is at the CI pin and it reports zero findings across 291 Zig files.
- The cloud Deno 2.9.6 standalone runtime is cached from the official GitHub
  release with its published SHA-256 verified. The initial full gate failed only
  on the blocked `dl.deno.land` download; after caching, the complete
  `deno task test:compiler` command passed. Keep the cache setup in the saved
  environment installation instructions.
- Corpus differential and budget scripts:
  `build/bench/indexed-solver-lazy-release/tools/`.
