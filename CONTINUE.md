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
- Task 018 (executable fragment and optimizer queries) is complete at `a604cc1`.
  Full LLVM native execution, 623 guest/client tests, six-policy parity,
  executed same-signature callee edits and zero analyzer findings pass. Real
  incomplete-prefix saturation declines reuse and preserves fresh output. Fresh
  CPU is near neutral and allocation unchanged; retained tables add measured
  memory/allocation costs. Seventeen retained workloads plateau and tear down to
  zero. See [the qualification](zig-native/EXECUTABLE_QUERIES.md).
- Task 019 (portable query serialization) is complete at `ea4a7f3`. Typed
  versioned sections carry complete principal proofs and sealed optimizer
  records; decoding validates every ordinal, evidence edge, body operand,
  control frame and record/input correspondence before rebuilding native
  indexes. Full LLVM native execution, 624 guest/client tests and zero analyzer
  findings pass; six validator mutants are killed. Example checkpoints grow
  9.6–19.6% and decode CPU rises 1.156× (below 0.25% of restart CPU). A first
  design wrongly bounded builtin nominal units (`maxInt(u32)`) by the source
  image; a public-example restart law now guards it. See
  [the record](zig-native/PORTABLE_QUERIES.md).
- Task 020 (persisted semantic artifacts) is complete at `8803452`. Checkpoints
  (key v3) may carry the previous revision's selected-specialization owner:
  exact Core with certificate bytes, namespace, evaluator snapshot, slots, field
  locations and receipts, validated at decode and replayed by the ordinary Gate,
  Importer and Plan. Seven examples replay 1–3 receipts after restart at a
  measured 14–26% restart CPU cost; owner-free workloads allocate less thanks to
  exact-size encoding. Monadic libraries now pack into dependency artifacts. See
  [the record](zig-native/SEMANTIC_ARTIFACTS.md).
- Task 021 (transactional revision deltas) is complete at `696051e`. Plain
  artifact pool slices are refcounted leases; captures retain equal fields from
  the previous revision and copy only changed ones; unread body pins are gone.
  Steady edits request 1.4–6.1% less, peak 25–98 KB less, CPU geomean 0.967. See
  [the record](zig-native/REVISION_DELTAS.md).
- Task 022 (retained aggregate constants) is complete at `62241e2`. Retained
  fragments replay graph-equal aggregate constant children by re-serializing
  them in the current owner and relocating the caller's root operands; output
  stays identical to fresh. See [the record](zig-native/RETAINED_CONSTANTS.md).
- Task 023 (literal edit invalidation) is complete at `fbe28c8`. Edited
  effectful modules keep the reuse gate when their operation catalog is
  unchanged, and certificates share unchanged module images. Effectful edits at
  example size are CPU-neutral to 14% slower; the gdev target stays open. See
  [the record](zig-native/LITERAL_EDITS.md).
- Task 024 (body interface cutoff) is in progress at `a686304`. Refinement
  receipts in edited modules replay per declaration; loop names are numbered per
  declaration. Remaining: per-body frontend rechecking and stable Core node/type
  IDs and symbol order for size-changing edits. See
  [the record](zig-native/BODY_CUTOFF.md).
- gdev findings from a separate session (current gdev checkout, `fbe28c8`
  compiler): a retained literal edit costs about 1.1 s CPU, about 60% of it in
  re-evaluating entry constants (task 086); `099e700` doubled it versus
  `632b461` through principal-graph sharing (task 085). Per-commit binaries and
  `meas.sh` are in `/var/tmp/bisect-bins/` on the owner's machine.
- Task 085 (principal-graph payoff) is complete at `7d64435`: open principal
  edges are retained only where call paths multiply; gdev retained edits match
  the sharing-off cost and the diamond keeps its benefit. The gdev harness
  (frozen copy in `/var/tmp/gdev-bench`, local harness in ignored
  `build/bench/principal-graphs/meas.ts`) is local-only.
- Task 087 (trivia-only edits) is complete at `eaf02d7`: comment and spacing
  edits that keep tokens and adjacency reuse the last output (gdev comment edits
  ~0.94 s → <10 ms). See [the record](zig-native/TRIVIA_EDITS.md).
- Task 086 investigation: on gdev, constant evaluation is one constant
  (`sandbox`, ~700 ms per edit); 98% of it is inference nested in its
  evaluation, and its value never reads the edited literal. Reusing it means
  publishing a constant slot and its fuel from a receipt, which crosses the
  documented value-template boundary ("does not publish constant slots ... or
  skip source fuel"); that design needs the owner's agreement first. Agent
  scratch data is in ignored `build/bench/consttime/`. That profile predates
  task 088 and must be measured again.
- Task 088 (summary-job cost) is complete at `86db5b1`: summary jobs drained
  under a principal recorder, foreign graph sources and memo facts decided by
  detached graph descriptions no longer drop `sandbox`'s input key, and lexical
  capture selection projects only reachable scopes. gdev retained edits 780 →
  570 ms CPU (inference 448 → 240 ms); `f7be6e7` is still 400 ms, now task 093.
  See
  [the record](zig-native/CALL_SUMMARIES.md#summary-job-cost-11-october-2026).
  Bisect worktrees and binaries are in ignored `build/bench/summary-growth/`;
  candidate scripts, pins and logs in `build/bench/summary-fix/`.
- A gdev session reported four issues, filed as tasks 089–092: inference budget
  exhaustion reported without a position, checker pending checks rescanned every
  pass, compile-time evaluation depth counted per nested expression, and the
  formatter rejecting current syntax (confirmed on `examples/ecs.blot` and
  `examples/syntax.blot`).
- Task 089 (budget diagnostics) is complete at `c5cb9ac`: exhausting a module's
  inference budget reports one positioned `inference_budget` diagnostic naming
  the declaration. A public shape for task 090 (N closures in a global record, N
  helpers) checks in 3.8 s at N = 300.
- Task 091 (evaluation depth) is complete at `915b7e1`: compile-time recursion
  is bounded by 4,096 nested calls on a 1 GiB reserved compile thread, with a
  `constant_recursion` diagnostic at the outermost call.
- A separate session (bun-desktop) offered an unapplied wasm name-section patch
  at `/var/tmp/blot2-names.patch` (14 files, always on, +5% Wasm, gate green on
  `a488ba2`); applying it is the owner's decision.
- Cloud follow-up: a loop counter in storage words passed the native suite, 599
  guest/client tests and the pinned analyzer, but repeated release batches did
  not establish an F32 improvement and regressed a U32 tuple shape. It is
  unlanded; List lowering was restored to `65dccda`. See
  [the measurement record](zig-native/LIST_TRAVERSAL.md#word-positions-at-leaf-boundaries-9-october-2026).

## Next steps for task 002

The owner confirmed the original benchmark artifacts were probably local and
uncommitted. The cloud checkout lacks them and the frozen private gdev snapshot.
The owner's machine (`~/src/blot2`) also has an empty `build/`. Its `../gdev`
checkout does not match `scripts/bench/gdev-manifest.json` at any commit (at
most 27 of 51 files), so task 002 stays blocked there as well.
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

## Next steps

Task [024](tasks/024-apply-general-body-interface-cutoff.md) stays in progress:
the remaining work is per-body frontend rechecking and stable Core IDs, which
needs its own design before implementation. Ready tasks in numeric order are
[025](tasks/025-resolve-calls-before-emission.md), 036, 048,
[086](tasks/086-retain-constant-evaluation-across-revisions.md) 090, 092 and
093; 086 needs a fresh gdev profile and then a design decision (see above), and
[093](tasks/093-close-the-gdev-edit-gap.md) carries the remaining measured gdev
edit gap. The retained probe
`zig-native/qualification/revision_deltas_probe.zig` and its driver measure
edit/revert/rejected/no-op phases against an earlier tree; task-024 binaries are
in ignored `build/bench/body-cutoff/`, and the pinned analyzer is built in
ignored `build/tools/zig-analyzer` (CI pin `756bfd5`). Tasks 002, 040–047 and
075 onward stay blocked on owner-local artifacts (task 002), and 084 on private
gdev.

## Notes

- Compare allocation release-to-release: debug `blotc` reports roughly 10% less
  requested allocation than release.
- `../zig-analyzer` currently has an uncommitted `double-release` rule that
  flags guarded `defer if (alive)` patterns (10 false positives). The CI pin
  `756bfd5` reports zero findings; run with
  `ZIG_ANALYZER=/tmp/blot-qualified-analyzer-756bfd5/zig-out/bin/zig-analyzer`.
  Those paths refer to the original machine. In the cloud checkout, use
  `ZIG_ANALYZER=/workspace/tooling/zig-analyzer/zig-out/bin/zig-analyzer`; its
  source is at the CI pin and it reports zero findings across 302 Zig files. On
  the owner's machine `../zig-analyzer` is absent: clone
  `https://github.com/mewhhaha/zig-analyzer` at `756bfd5`, run
  `zig build -Doptimize=fast && zig build backend`, and point `ZIG_ANALYZER` at
  it. It reports zero findings across 303 Zig files at `ea4a7f3`.
- The cloud Deno 2.9.6 standalone runtime is cached from the official GitHub
  release with its published SHA-256 verified. The initial full gate failed only
  on the blocked `dl.deno.land` download; after caching, the complete
  `deno task test:compiler` command passed. Keep the cache setup in the saved
  environment installation instructions.
- Corpus differential and budget scripts:
  `build/bench/indexed-solver-lazy-release/tools/`.
