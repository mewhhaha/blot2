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
- Task 012 (private semantic component jobs) is complete at `eb66151`. Joined
  private solver/scratch/import owners publish whole components
  deterministically through a staged evidence owner. The full LLVM native suite,
  620 guest/client tests, 626 six-policy comparisons and zero-findings analyzer
  pass. Fresh and repeated retained edits/failures/restarts preserve diagnostics
  and Wasm, with zero fresh teardown bytes and executed original/edited outputs.
  See [the semantic job qualification](zig-native/SEMANTIC_JOBS.md).
- Task 014 (typed query design) is complete at `8219cf3`, with final review
  corrections at `beeae7f`. The shared table and migrations remain tasks
  015–020. [The durable design](zig-native/QUERY_TABLE.md) keeps open principal
  templates, completed semantic proofs, source validation, executable behavior
  and evaluated values distinct, with exact dependency equality and atomic
  publication.
- Task 013 (semantic worker qualification) is complete at `4c61f25`. The full
  LLVM native suite, 621 guest/client tests and zero-findings analyzer pass.
  Alternating fresh/retained/restart measurements show worker CPU/wall and
  allocation overhead; no stable threshold qualifies default enablement. Serial
  remains the default and workers stay opt-in. See
  [the policy distributions and pins](zig-native/SEMANTIC_WORKERS.md).
- Task 015 (owned refinement queries) is complete at `bfcb464`. Bounded common
  records, atomic publication and ordered position indexes preserve local and
  retained validity/priority. Full LLVM native tests, 622 guest/client tests and
  zero-findings analyzer pass. Six-policy byte/diagnostic parity, executed
  edits, fifteen-pair fresh and seven-pair retained/restart qualification show
  bounded storage overhead and roughly neutral overall CPU. See
  [the refinement qualification](zig-native/REFINEMENT_QUERIES.md).
- Task 016 (specialization and principal query owners) is complete at `913a59f`.
  Selected, principal, canonical and local source-template tables preserve their
  distinct proofs; the portable Reader keeps its v2 wire projection and uses a
  transactional ordered index. Full LLVM native tests, 623 guest/client tests,
  626 six-policy comparisons and the zero-findings analyzer pass.
  Fresh/retained/checkpoint measurements qualify near-neutral overall CPU and
  bounded storage, with recorded small-control overhead. See
  [the durable qualification](zig-native/SPECIALIZATION_PRINCIPAL_QUERIES.md).
- Task 017 (source and revision validation records) is complete at `089efb0`.
  Successful input buffers move without copying; checked-Core records retain
  exact namespaces/graphs and foreign bounds. Full LLVM native execution, 623
  guest/client tests, six-policy parity and zero analyzer findings pass. Fresh
  allocation is unchanged and CPU near neutral; exact certificates add measured
  retained memory/allocation and about 14% CPU in positive entry-only edit
  controls. See [the qualification](zig-native/SOURCE_VALIDATION.md).
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

## Next steps for task 018

Migrate
[executable reuse queries](tasks/018-migrate-executable-reuse-queries.md) under
[the typed query contract](zig-native/QUERY_TABLE.md). Retained artifact
fragments and optimizer body relocation are separate adapters. Preserve full
request/evidence/capture/staging dependencies, inlined callee and static reads,
exact instructions/signatures/policy and transitive lifetime summaries. Keep
existing admission/reconstruction gates and candidate order; an unchanged
interface cannot certify an edited executable body. Portable serialization
remains task 019.

The final task-017 baseline is `candidate-source-validation/`, source revision
`089efb0b9b29504513bc0808fb20992b09c53f89`, binary
`5058f69f10640780061bb7a8cd093a9164dc789ff806ce1bc48b1ce0a9921356`, identity
`23035481dc651f09728b2636b90d5eb1c8a78939b11896947cc396592f7c904c`, and 414-file
source/test map
`d2c208558cd097650d65e93710b73fa29cc2ded3496f98459588b1a7267159ae`. Keep earlier
qualified pins immutable, including task 016's
`candidate-specialization-principal/` and task 015's
`candidate-refinement-query-v2/`. Task 002 and the private application gate in
084 remain open on absent owner-local artifacts. No push is authorized.

## Notes

- Compare allocation release-to-release: debug `blotc` reports roughly 10% less
  requested allocation than release.
- `../zig-analyzer` currently has an uncommitted `double-release` rule that
  flags guarded `defer if (alive)` patterns (10 false positives). The CI pin
  `756bfd5` reports zero findings; run with
  `ZIG_ANALYZER=/tmp/blot-qualified-analyzer-756bfd5/zig-out/bin/zig-analyzer`.
  Those paths refer to the original machine. In the cloud checkout, use
  `ZIG_ANALYZER=/workspace/tooling/zig-analyzer/zig-out/bin/zig-analyzer`; its
  source is at the CI pin and it reports zero findings across 301 Zig files.
- The cloud Deno 2.9.6 standalone runtime is cached from the official GitHub
  release with its published SHA-256 verified. The initial full gate failed only
  on the blocked `dl.deno.land` download; after caching, the complete
  `deno task test:compiler` command passed. Keep the cache setup in the saved
  environment installation instructions.
- Corpus differential and budget scripts:
  `build/bench/indexed-solver-lazy-release/tools/`.
