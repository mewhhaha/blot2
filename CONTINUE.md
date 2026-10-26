# Continue the Goose K1 rewrite

Worktree: `/home/mewhhaha/.codex/worktrees/0409/blot2`, branch `rewrite/goose-k1`.
Main and the installed legacy compiler remain separate. The latest task was to
implement the next predictable performance steps: structural validator/proof
work, then bounded release inlining. Three Sol agents implemented and reviewed
the changes; root integrated counters, session invalidation, workloads and evidence.
The qualified implementation is frozen and is being published as a draft PR.
The user next requested a bounded runtime performance pass with Sol review;
stop if measurements do not justify further changes.

Read [current results](benchmarks/STRUCTURAL.md), [ledger](IMPLEMENTATION.md),
[contracts](docs/CONTRACT.md) and [normative snapshots](docs/spec/INDEX.md).
The earlier [parity report](benchmarks/PARITY.md) remains historical evidence.

The current release gate passed **115 native entries, 88 Deno tests, editor
scopes and 29 formatter round trips**. Input manifest:
`32c050991a86eec699074c07a52add676ebef9f795685c3f6490743ab054b928`.
Executable SHA-256:
`ca49141eea94f5f3e1cb3d87930bb41b5409e5dedc777b991c6ed6b2eebcf527`.
[Current evidence](benchmarks/results/structural/manifest.json) pins all 191
qualified inputs and 1,177 records, including isolated release ablations,
previous/new K1, legacy, retained edits, fast/release and engine controls.
All samples, hashes, raw logs, source overlays and profiling reports are archived.
Historical evidence packages are immutable. Do not rerun snapshot-specific
packagers against a different candidate.

## Completed mechanisms

Validator Context borrows its immutable Core view, avoiding repeated copies of
the table inventory. Attempt budgets/scratch remain private. Fifty-four frozen
before/after admissions preserve exact outcomes, diagnostics, work counts and
canonical digests. Iterative Tarjan proof SCCs remove reverse adjacency and a
second graph traversal, while keeping the first strict edge, certificate BFS,
evidence order and direct contradiction shortcut. Guard-heavy proof visits fall
about 15%; the isolated Tarjan wall-time ratio is 0.999, so no separate timing win
is established. The Core-borrow ablation helps several larger workloads.

The release tier adds direct monomorphic single-block U32/Bool/F32 inlining.
It excludes captures, generic substitutions, effects and proof-bearing interfaces
or pinned producers. Templates are immutable; arguments evaluate once; SSA,
source order and separate F32 rounding are preserved. Policy limits are unchanged:
32 callee nodes, depth 2, 16 sites/caller, floor(caller nodes/4) growth capped at 256,
global output N+64, visits 8N+1024 and rewrites N+256. Preflight and reserved cleanup
visits retain a valid prefix on optional refusal. Internal mapping failures still
fail; every candidate is independently validated. Nine native laws and two guest
laws cover boundaries, a 256-limit multi-block sweep, F32 and effectful arguments.
A retained release test checks callee edits while reusing caller judgments.

The CLI exposes inline_sites/growth/declines/max_callee/max_depth separately.
These count attempted work; whole-candidate rewrite_declines can still cause
baseline emission. Semantic receipts contain preoptimization bodies, so each
revision redoes optional transport from current completed callees.

## Results and limits

At scale 128 (chains 127), paired whole-compile ratios against previous K1 are
0.851–0.932, roughly 7–15% less time. Off-tier Wasm is byte-identical throughout.
Body edits: 6.96 → 6.29 ms; unchanged: 7.31 → 6.34 ms. These are synthetic inputs, not gdev.
Against legacy, modules are near parity (10.71 vs 10.61 ms); proofs (22.56 vs 25.40 ms) and
domains (7.35 vs 13.23 ms) remain slower. Old/new absolute times across separate batches
are not comparable; host load/frequency/cache are uncontrolled.

Inlining has no established general runtime win. The 128-diamond corpus retains
25 sites/+8 operations within 12,288 visits, no whole-candidate decline. Only 9 of 128
export call graphs change; 119 are byte-identical. Original mixed-family runtime
ratio 1.228 regressed, fresh-engine control 0.796 reversed direction, and optimizing
engine control 0.989 was near parity. All are retained. Integer/F32 loop kernel
ratios 1.010/0.980 also do not resolve a win. Do not tune source or policy to these
fixtures or claim that more inlining alone closes the runtime gap.

Next useful compiler work is completion/evidence traversal, remaining validator
/type traversal and static-domain planning. For runtime, examine shared generic
slot/adapter overhead with engine-stable whole kernels before more rewrite rules.
Retained transport and Goose/C build iteration remain separate targets. Compiler
rebuild-time was not remeasured. No syntax or ABI change was made.

## Reproduction

Pinned Goose: `/tmp/blot-k1-goose/build/goose`, commit
`a108677d300cb0e8bbb842c35a353abe67a20c6c`,
`GOOSE_HOME=/tmp/blot-k1-goose-home`. The same pinned toolchain was rebuilt this
turn after its temporary executable disappeared. Bootstrap can recreate it.
Compiler changes require the complete `scripts/check.sh --release` gate.

Previous qualified compiler: `build/structural-baseline/blot` (`f84aa746…`), with
its input snapshot. Earlier preserved executables: `build/review-baseline/blot`,
`build/parity-baseline/blot`, `build/parity-first-candidate/blot`,
`build/parity-before-publication/blot`. Full hashes are in their evidence packages.
Final orchestration and control scripts are archived from `build/run_structural.py`
and `build/run_inline_control.py`; public workload harness is
`scripts/benchmark_workloads.ts`. No required checks remain pending.

The user authorized committing and pushing this branch for a draft PR.
The next runtime pass should preserve the qualified baseline and report measured
results, including unsuccessful experiments. Do not replace the installed
compiler, merge the draft or close #37 without the user's instruction.
