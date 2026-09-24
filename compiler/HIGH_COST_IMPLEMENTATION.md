# Reducing repeated compiler work

2026-09-24. Implements the borrowed String traversals and common nominal catalog
from [the preceding experiments](HIGH_COST_EXPERIMENTS.md).

## Implemented

- Native `Map.bit` and `String.cmp` retain their owning String roots, borrow
  immutable nodes, and return the original roots. This avoids reconstructing
  traversed prefixes. Maintained guards check Bend 2.0.27, installed Base
  definitions, generated cases and continuation relationships, helper bodies,
  term layout, atomic reads and runtime polling. Unexpected changes stop the
  build. Direct probes cover shared roots, arbitrary U32 characters, prefix
  comparisons, Nat48 positions and overflow diagnostics.
- Planning computes the transitive nominal requirements of operation signatures
  once. Individual jobs retain their additional requirements and reuse the
  common sorted catalog when possible. The Planning cache key includes the new
  shared requirements. The earlier gdev census found 664 shared-list reuses in
  844 jobs and reduced per-declaration nominal seeds from 10,570 to 707.
- Added cache invalidation, unused-operation/recursive-group, native drift and
  ownership regressions, plus the shared-catalog law in
  `LAWS.bend`/`PROOF.bend`.

These changes preserve gdev's complete 3,360,009-byte analysis, including its
821 checked functions and 23 constants. Analysis SHA-256:
`dae40eb1448855bc156f9c9bb043a68329a33c8782adeef71ca1520d71015c32`. The
192,168-byte Wasm remains byte-identical:
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`.

## Integrated native measurements

Five alternating fresh-process pairs per worker count; fresh project loading,
warm filesystem. Compile time includes request preparation, encoding, IPC,
native compilation and decoding. Startup and project loading are separate.

| Median                      | 1 worker: baseline → integrated | 4 workers: baseline → integrated |
| --------------------------- | ------------------------------: | -------------------------------: |
| Compile call                |                1,230 → 1,019 ms |               **1,033 → 784 ms** |
| Native CPU                  |                  1,170 → 970 ms |             **1,410 → 1,130 ms** |
| Peak RSS                    |             49,912 → 44,760 KiB |              69,052 → 63,688 KiB |
| Startup + loading + compile |                1,321 → 1,138 ms |                   1,131 → 894 ms |

Median compile reductions are 17.2% and 24.1%; CPU reductions are 17.1% and
19.9%. Four of five one-worker pairs and all five four-worker pairs improve both
wall time and CPU. Other CPU-heavy work continued on the machine; our builds and
tests were stopped for timing. The two worker rows are separate windows and do
not measure the causal effect of adding workers. Medians of individual stages do
not necessarily add to the median total.

Baseline executable SHA-256:
`925a2442cd872cf52d772eb3d59189039b8a291316d65cabd3883ffba39bd7c0`. Integrated
executable SHA-256:
`0ff3102bea067b66a8cfd3f267a3a7557966de0f4eeb57ce8d45091a924f1376`. Raw pairs
and summaries: `build/high-cost-integration/root/pairs-integrated-{1,4}.*`.

## Validation

- `BEND_NO_TELEMETRY=1 bend PROOF.bend`: all terms check.
- Native ownership regression: one and four workers.
- **727 compiler/transformer tests**, **24 gdev tests**, and **176 native API
  differential operations** at one/four workers.
- Direct borrowed String probes: generated-C parity, actual kernel execution,
  shared inputs, Nat48 overflow diagnostics, ASan and UBSan at one/four workers.
- Complete gdev analysis equality and exact Wasm in every timed request.

Builds and gate logs are in `build/high-cost-integration/`. During emission the
coordinator strengthened continuation-identity guards, triggering the staged
build's source fingerprint check. A fresh run of every current production
transform reproduced byte-identical guarded C before installation; only the
reviewed transformer and its test changed. `validated/guard-recheck.json` and
`validated/validated.json` record this check and installed artifact hashes.

## Further experiments

### Singleton dependency graphs: native benefit not established

The final check invokes SCC analysis 456 times: two planner graphs and 454
single-declaration checking graphs. A private Bend wrapper returns the known
empty/singleton component directly and leaves the general algorithm unchanged.
Body scanning and validation still run. It passes the random graph tests,
complete gdev analysis equality, 176 native API operations and 17 native session
tests.

Native measurements were mixed: one-worker medians were 1,419 → 1,457 ms (CPU
1,280 → 1,350 ms); four-worker medians were 1,155 → 1,125 ms (CPU 1,550 → 1,520
ms). This does not establish a useful native improvement. It remains private.
The earlier JavaScript improvement is insufficient evidence for shipping it as a
native optimization.

Evidence: `build/high-cost-integration/planning-next/REPORT.md` and
`root/pairs-singleton-{1,4}.*` under the same integration directory.

### Shared String addresses: low hit count

A second private native variant checks whether different owning references point
to the same underlying immutable String node. It preserves gdev Wasm at one/four
workers. Only 19,471 of 22,342,800 name-equality node checks and 916 of
1,065,287 comparison checks hit the new branch (about 0.087%). This was
deprioritized; no native speed improvement is claimed and the extra branch is
not installed.

### Specialization remains the largest target

A refreshed coarse phase profile of the integrated compiler attributes about
**53.3% of native CPU to specialization**, **20.0% to final checking/planning/
exports**, 7.0% to initial checking, 5.6% to decode/lowering/planning, 4.2% to
constant evaluation, and 9.9% to Wasm/response work. These are means of three
one-worker instrumented requests. Heavy unrelated load changed CPU frequency and
wall time substantially; use this profile for approximate attribution, not as an
absolute latency comparison with the earlier profile. Raw phase events and
adjacent uninstrumented controls are in `build/high-cost-integration/root/`.

The next private experiment is a checked-source schema evaluator that avoids
generating helper clones. Review requires complete chain validation even after a
successful membership hit, exact nominal/source dependencies, ordinary
field/method diagnostics, receiver/witness evaluation, and transactional
fallback. Its production integration depends on full output/diagnostic parity
and a measured native benefit.

The **100–200 ms target has not been reached**.
