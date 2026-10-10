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
- Task 004 (first-order principal/residual call summaries) is complete at
  `3a8b6ee`. Exact live header keys and owned source-normalized graphs remove
  transitive diamond work while preserving original witnesses, rows and source
  dependencies. The full native suite, 607 guest/client tests, 509 public
  differential cases and zero-findings analyzer pass. Fifteen-pair measurements
  and seven-pair fresh/retained/restart comparisons qualify the artifact. Small
  wrappers can cost more; no private gdev or general speedup is claimed. See
  [the durable qualification](zig-native/CALL_SUMMARIES.md#live-headers-and-source-normalized-graphs-10-october-2026).
- Task 005 (parametric callback obligations) is in progress. Callback/capture/
  joint-component/canonical-key work remains tasks 005–008.
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

## Next steps for task 005

Implement the callback-obligation form in
[CALL_SUMMARIES.md](zig-native/CALL_SUMMARIES.md#higher-order-obligations-and-effects).
Keep dedicated higher-order summary shape/evidence checks separate from the
first-order data predicates used by dispatch and representation proof. Record
each formal callback slot, curried invocation stage, original argument/result
witness and latent row relationship in the owned graph. Complete callback
interfaces can key independent jobs; executable identity, captures and provider
observations retain their own caller checks. Unknown facts use bounded ordinary
fallback. Do not grant closed proof status to an exported callback obligation.

The task 004 pin is `candidate-live-headers/` under
`build/bench/cloud-principal-graphs/`. Keep it and earlier pins immutable. The
latest record includes source edges revealed only after normalization, an
allocation-failure cycle publication law, active effect handlers, 509
diagnostic/ Wasm comparisons and all paired samples. For task 007, retain the
direct source `Seed.build -> parent.read -> Box.read -> parent` probe: it
exposed frontend lowering work that did not finish even with written arrows. The
kernel cycle law qualifies optional publication, not ordinary recursive
inference.

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
