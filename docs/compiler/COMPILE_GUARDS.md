# Compile-cost regression guards

CT92–CT94 add deterministic reuse budgets and an explicit paired CPU gate.
Output and diagnostic parity remain independent requirements.

## Deterministic work

`tests/compile_budget.test.ts` runs the seven public edit scenarios and their
reverts against fresh builds. It requires at least the recorded named-instance
reuse and bounds fresh instances, validated modules, rechecked bodies, body
elaborations and body lowerings. Trivia must publish the previous output.
Dependency Core/interface checks and entry-switch relocation have separate
budgets. Missing, noninteger or negative counters fail.

The 19 October 2026 measurements pin population at 150 elaborations/lowerings;
literal/body edits at five; type edits at eight; imported-body edits at five;
and unused-export edit/revert at 16/15. Literal-constant edits reuse at least
eight named instances, body edits seven and imported-body edits six. Lower work
or greater reuse is reported so the budgets can be tightened.

## Paired CPU

`bench:compile --guard-cpu` requires the game workload and at least three
alternating baseline/candidate pairs. It takes the median of the per-round
candidate/baseline child CPU ratios and fails above 1.05. Failed, incomplete,
duplicate and nonpositive/nonfinite samples fail. Retained phases and wall time
do not enter the gate. Every ratio is retained in `cpu_guard`.
`--allow-wasm-diff` cannot waive a timing failure or let it rewrite hashes.

Timing is opt-in so single-run profiles and synthetic-only measurements remain
available. Qualification commands must explicitly include `--guard-cpu`.
`--codegen-workers` pins both compilers equally and records the value in the
result; its default remains four. For this cloud machine, reduce scheduling
noise with an allowed CPU and one codegen worker:

```sh
BLOT_BENCH_CPU=$(python3 -c 'import os; print(min(os.sched_getaffinity(0)))')
taskset --cpu-list "$BLOT_BENCH_CPU" deno task bench:compile \
  --baseline OLD_BLOTC --candidate NEW_BLOTC --workload game \
  --runs 7 --no-retained --codegen-workers 1 --guard-cpu
```

Use the environment's shared memory/serialization wrapper for heavy commands.
Keep worker count, affinity and persistence equal. Preserve all samples and
investigate failed controls rather than retrying until the timing gate passes.

## Qualification on 19 October 2026

The 11 compiler-budget cases and nine benchmark-verification cases pass; the
complete harness passes 37 tests. Type/format checks pass. The preceding full
compiler gate is recorded in
`build/bench/ct90-cloud-qualification/qualified-pins.json`; these guard-only
checks do not claim another full native/guest run.

An initial unpinned four-worker identity control failed: identical binaries
produced paired median 1.106, with CPU samples from 4.2 to 7.7 seconds. This is
environment noise. After selecting CPU 0 from the allowed affinity and one
codegen worker, seven identity pairs pass with median 1.000. The same fixed
settings compare pre-CT90 with current in seven pairs: median 0.930, guard
passed, Wasm identical to each other and the recorded references. Spreads remain
large; these campaigns establish no new speedup and do not replace the separate
four-worker production baseline.

Current SHA-256:
`807d3f05f1a884290014d6b698f2263faa938e072df3cdbf4feca1b53f60584e`. Pre-CT90
SHA-256: `d487e1c49ab725e0f2716f1344073e63eed4370ab111e653683c8e5a2cfd0460`.
Complete raw results remain in ignored `build/bench/ct93-identity/`,
`build/bench/ct93-pinned-identity/` and `build/bench/ct93-ct90/`.
