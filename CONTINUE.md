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
- Task 005 (parametric callback obligations) is complete at `652f4d6`. Exact
  formal callback slots/stages/rows and conditional graph actions preserve
  caller checks. The full native suite, 609 guest/client tests, 563 public
  comparisons and zero-findings analyzer pass. Fifteen-pair fresh measurements
  and seven-pair fresh/retained/restart batches qualify the immutable v2 pin.
  Deep predicate cases have bounded work; small controls add overhead. See
  [the durable callback qualification](zig-native/CALL_SUMMARIES.md#parametric-callback-obligations-10-october-2026).
- Task 006 (owned lexical capture inputs) is complete at `71c0f2a`. Complete
  ordered captures, actual aliases, values, nested bodies and provider/demand
  identities key private jobs without global principal publication. The full
  native suite, 610 guest/client tests, 587 public comparisons and zero-findings
  analyzer pass. Initial/edited guest outputs, fifteen-pair measurements and
  seven-pair retained/restart batches qualify the immutable artifact. Shared Box
  output shrinks by 12 static bytes per closure; small and demand/provider
  controls can add overhead. See
  [the lexical qualification](zig-native/CALL_SUMMARIES.md#owned-lexical-inputs-10-october-2026).
- Task 007 (joint recursive components) is complete at `4f898b0`. Exact body
  edges, component-atomic publication and heap scheduling bound both frontend
  and ordinary Core inference. The full native suite, 615 guest/client tests,
  608 public comparisons and zero-findings analyzer pass. Initial/edited guest
  execution, fifteen-pair fresh and seven-pair retained/restart batches qualify
  the final immutable pin. Five formerly limited deep cases now compile; some
  controls add overhead and diamond32 CPU rises 10.872→19.634 ms. See
  [the component qualification](zig-native/CALL_SUMMARIES.md#joint-recursive-inference-10-october-2026).
- Task 008 (canonical specialization keys) is complete at `daf9d70`. Complete
  Session-owned proofs reconstruct results against current captures with atomic
  replay. The full native suite, 617 guest/client tests, 617 strict comparisons
  and zero-findings analyzer pass. Initial/edited execution and
  fresh/retained/restart measurements qualify the immutable pin. Scalar/Box
  repeated-capture regions fall; incomplete interfaces remain conservative. See
  [the canonical qualification](zig-native/CALL_SUMMARIES.md#session-local-canonical-specialization-10-october-2026).
- Task 011 (semantic allocation traffic) is complete at `3a51bcd`. Stable owner
  meters and single-copy capture publication pass the full native suite, 618
  guest/client tests, 620 strict comparisons and the zero-findings analyzer.
  Fresh/retained/restart qualification removes measured wide-capture allocation
  with neutral overall CPU; repeated public revisions plateau and teardown to
  zero. Small controls can add traffic. See
  [the allocation qualification](zig-native/SEMANTIC_ALLOCATION.md).
- Task 014 (typed query design) is complete at `8219cf3`, with final review
  corrections at `beeae7f`. The shared table and migrations remain tasks
  015–020. [The durable design](zig-native/QUERY_TABLE.md) keeps open principal
  templates, completed semantic proofs, source validation, executable behavior
  and evaluated values distinct, with exact dependency equality and atomic
  publication.
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

## Next steps for task 012

Implement
[general private semantic jobs](tasks/012-schedule-independent-semantic-jobs.md).
Keep `build/bench/cloud-principal-graphs/candidate-allocation/` immutable as the
baseline. Its compiler SHA-256 is
`571c1ccab004a8659553a20b10d5eb2e4b1ad9e680999a59156bc7b66af92c36`, identity
`3be94f26e4252ad0a710459aaa87ac25628bdba41ad034781cc13e56a808185d`, and
seven-file source manifest
`ba3728c7d06708969c7a8ed1a015a908c045ee127331daa3b2449f1d33f5bef7`. Older pins
remain unchanged. Task 011 qualifies 80 fresh workloads and 76 retained/restart
workloads, plus direct requested-memory evidence on four repeated public graphs.
The private application gate remains task 084.

Generalize the existing closed-call proof batch to actual independent semantic
components with immutable input snapshots, private solver/scratch/import maps
and diagnostics. The coordinator owns SCC discovery, exact complete keys and
atomic deterministic publication. Exported-source-interface fan-out alone does
not complete the task. Newly discovered shared edges need conservative serial
fallback or component restart before publication. Preserve completed independent
proofs across other worker failures, stop dispatch on cancellation and join
started jobs before any borrowed source or allocator is released. Worker-local
semantic IDs require explicit remapping before parent publication. Test mixed
results, one-versus-many equivalence, recursive components, cancellation and
allocation failure. Default parallel enablement belongs to task 013 and needs
both CPU and wall-time improvement. Task 014's design is complete; task 015 is
also dependency-ready after the lower-numbered in-progress work.

## Notes

- Compare allocation release-to-release: debug `blotc` reports roughly 10% less
  requested allocation than release.
- `../zig-analyzer` currently has an uncommitted `double-release` rule that
  flags guarded `defer if (alive)` patterns (10 false positives). The CI pin
  `756bfd5` reports zero findings; run with
  `ZIG_ANALYZER=/tmp/blot-qualified-analyzer-756bfd5/zig-out/bin/zig-analyzer`.
  Those paths refer to the original machine. In the cloud checkout, use
  `ZIG_ANALYZER=/workspace/tooling/zig-analyzer/zig-out/bin/zig-analyzer`; its
  source is at the CI pin and it reports zero findings across 295 Zig files.
- The cloud Deno 2.9.6 standalone runtime is cached from the official GitHub
  release with its published SHA-256 verified. The initial full gate failed only
  on the blocked `dl.deno.land` download; after caching, the complete
  `deno task test:compiler` command passed. Keep the cache setup in the saved
  environment installation instructions.
- Corpus differential and budget scripts:
  `build/bench/indexed-solver-lazy-release/tools/`.
