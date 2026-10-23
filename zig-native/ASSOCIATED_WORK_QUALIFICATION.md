# Associated work budget qualification, 23 October 2026

The unchanged frozen gdev game reached an internal one-million-step
associated-type limit despite configuring `inferenceBudget: 200000000`. The
diagnostic named the configured inference allowance instead of the associated
allowance that actually ran out. This was a compiler defect; no gdev source
migration is required for this failure.

## Changes

Commit `58e00c3` preserves the preceding derive work: exact output-buffer
framing and explicit single-word scalar codec operations, with strict decoding.
It also routes project and evaluator associated allowances through the
configured inference budget. See [codec generation](../compiler/derive.md).

The follow-up skips associated normalization during ordinary constraint
unification when the solver has no associated projections, even if unrelated
implementations are in scope. It removes the additional one-million-step cap
inside module checking. A module's `associated_limit` diagnostic reports the
allowance available to that module, including any smaller remainder after
checking dependencies. Actual associated projections remain bounded and checked.
The production default remains one million steps; changing the configured budget
continues to change compiler identity.

See [project configuration](PROJECT_CLIENT.md) for the accounting rules.

## Verification

Three native laws cover ordinary wide effect rows with unrelated
implementations, accurate remaining-budget diagnostics, and successful real
projection work above one million steps. All three fail on the preceding
compiler sources and pass with the follow-up. They are included in
`check:dev --area type-effects`. The executed-Wasm regression covers real
associated members across multiple modules, low-budget rejection, successful
higher-budget compilation and recovery after rejection.

First commit: 2,536 native tests with exhaustive allocation-failure sweeps in
four shards, 1,647 guest/client tests, 48 smoke checks, 54 harness checks and 8
preflight checks. The full gate completed in 668.58 seconds.

Combined follow-up: 2,539 native tests with exhaustive allocation-failure sweeps
in four shards, 1,647 guest/client tests, 48 smoke checks, 54 harness checks and
2 preflight checks. The full gate completed in 669.83 seconds. Zig analyzer
reports zero findings across 518 source files plus the fixture module.
TypeScript and formatting checks pass.

Native compilation uses Zig 0.17.0 Safe/noLLVM. Release builds use Fast/LLVM.
Both full gates use the same frozen adjacent application parser corpus so
concurrent edits in the live gdev checkout cannot change the native inventory.
No incomplete or sampled run is counted as full qualification.

## Application measurement

Five fresh release builds per entry:

| Entry    | Median build wall |           Range | Median process CPU | Wasm bytes |
| -------- | ----------------: | --------------: | -----------------: | ---------: |
| game     |          16.192 s | 16.160–16.467 s |           16.350 s |  5,230,712 |
| devtools |           0.918 s |   0.905–0.926 s |            0.960 s |  1,107,529 |

Process CPU uses `/proc/PID/stat` totals (10 ms resolution on this host). The
timed runs begin after the full native and guest gate finishes.

The inputs are the previously frozen gdev, Ink and standard-library snapshot,
including the configured native text assets. Every timed build starts a fresh
compiler process with persistent caching disabled, optimized code generation,
four codegen workers and the application's existing 200-million-step budget.
Opening the project session is reported separately from build time. All fresh
outputs agree within each entry; the subsequent no-op build returns identical
Wasm. Input hashes are checked before and after the measurement. These are
compilation results, not a claim that the game's complete runtime has been
exercised.

## Evidence and installation

The raw gate logs, JUnit results, per-test timings, input and binary hashes,
regression controls, application samples and installation receipts are archived:

- [budget-base-2026-10-23.tar.gz](measurements/budget-base-2026-10-23.tar.gz),
  SHA-256 `e474e0ba9ec04ed0831ff18539bdb7e473c0191969c30c8f89f295efc1c2f57b`.
- [associated-work-2026-10-23.tar.gz](measurements/associated-work-2026-10-23.tar.gz),
  SHA-256 `bd124fcd5e1160191570e198763f8db1a58cb6f16493e78af4de77724dda77e5`.
- [associated-work-application-2026-10-23.tar.gz](measurements/associated-work-application-2026-10-23.tar.gz),
  SHA-256 `cb5987f7c4cba61fc83bef597af0b186d5f3662998a71b6b7ad3deb1aa5d8199`.

The qualified native compiler and bundled CLI are installed as
`~/.local/bin/blotc` and `~/.local/bin/blot`. Their hashes match the tested
candidates. Installation checks exercise the embedded guide, formatter, standard
library and README task example in synchronous and JSPI execution. The preceding
installation is preserved in `build/budget-fix/install/previous`; older
installation backups and the two existing Git stashes are untouched.

Release compiler SHA-256:
`fec30aece1dccd18f4709a06a96d70f42e9cd0682f843bc53fa8e3f99fa0ab31`.

The broader [completion plan](../FINISH_PLAN.md), including the remaining
structured-task and performance work, stays open.
