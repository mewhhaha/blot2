# Five-minute development feedback

Run `deno task check:dev --area static-sharing` from the repository root. In the
cloud environment, activate the pinned tools and avoid waiting behind a heavy
job:

```sh
. /workspace/.tools/activate.sh
python3 /workspace/.tools/run-heavy.py --no-wait deno task check:dev --area static-sharing
```

The command enforces a 300-second total budget. A timeout, missing selected
test, failed check or changed input is incomplete or failed, never a pass. The
repository lease returns busy immediately when another compiler check owns its
artifacts.

## Scope

- Compile the complete native inventory with Zig's backend, then select existing
  laws at runtime. LLVM is reserved for the actual release compiler.
- The published static-sharing family runs 16 native laws: aggregate parity and
  rejection, physical sharing, descriptor relocation, the positive static
  closure replay contract, all eight operation-admission laws, and two
  fault-policy laws.
- Run 45 protocol, budget-recovery and selected client edit/error/recovery
  tests. JUnit validation requires every selected file/name to actually execute
  and pass.
- Run formatting, type checks and local Zig analysis. Broad lint changes batch
  pending files into directory scans; cache reuse still checks
  tool/configuration and transitive contents.
- Record actual names, per-test durations, fault coverage, input/executable
  hashes, identity-check timings, other overhead, and pending qualification in
  `build/bench/check-dev/results.json` and a separate directory for each run.

Development fault checks execute the successful scenario and inject faults at
its first, middle and last discovered allocation positions. The default full
mode retains exhaustive sweeps, including the original standard-library
semantics. The native policy laws exercise both modes. Manual fault loops remain
exhaustive.

This published selection uses existing compiler behavior. Pending compiler
repairs can extend the manifest with their additional native and guest laws;
those extensions must be qualified alongside the repair. They are not
prerequisites for using the published command.

## Improvements and measurements

The first implementation measured 244.92 s with compiler/native rebuilds and
88.57 s cached on the pending compiler candidate's expanded 21-native/48-guest
selection. Its sampled timing census executed all 2,510 native tests in 176.55
s. These are historical development measurements, not release qualification or a
p95 guarantee for the published compiler.

The isolated published selection passes in **154.74 s**: compiler rebuild 29.35
s, all 2,499 native tests compiled in 43.25 s, 16 selected native laws in 1.38
s, 45 guests in 25.44 s, and Zig analysis in 44.77 s. Initial/final identity
checks take 7.56 s; other overhead is 0.11 s. Formatting and type checks also
pass. The raw report is `build/bench/turnaround-publish/results.json` (input
digest `3d491fd3d6067f605a9834d5dea40067a5bf02ce6ba24a0986b3a10b66887dcf`).

The final cached command, including the smoke-lease correction, passes in
**28.66 s**, executing the same 16 native/45 guest selection and static checks.
Its report is `build/bench/turnaround-publish-final/results.json` (input digest
`601bd377b08ca581a7547d9c5d222c781805629c14bd5bc2a51d9e48ca6f5a6b`). Identity
checks take 12.89 s and other overhead 0.11 s. These single-run numbers show
substantial I/O/runtime variation; they do not establish a p95 or a speedup
against the pending candidate's different test selection.

One pending ownership law spent 76.73 s in two direct exhaustive
standard-library fault sweeps. The new wrapper lets development explicitly
sample those sweeps while preserving the original full-mode behavior. Broad lint
edits previously launched hundreds of processes; directory batching checked 513
files with zero findings in 62.18 s. The 256-local requirement law now reuses
its already prepared baseline, preserving the budget boundary, rejection and
exact byte comparison.

Native tests reserve the same 1 GiB evaluation stack as the compiler, with pages
committed on demand. This fixes Zig-only failures caused by the host's 8 MiB
main stack. The runner harness includes a 16 MiB stack regression.

Executable hashing uses a reusable 1 MiB buffer instead of many small stream
reads. An initial same-machine comparison of the 291 MB compiler and 509 MB
native executable measured 3.56 s before and 1.30 s after, with identical
SHA-256 values. Source hashing shares a 64 KiB buffer. All bytes are still read
before and after a check; equal sizes/timestamps do not bypass verification.
Boundary and same-size edit tests guard these identities. Timed identity checks
now expose previously unattributed wall time without caching test execution.

## Remaining hills

Measure the next 20 real development cycles before claiming a five-minute p95.
Keep cold and cached observations separate. Extend the explicit regression
families when changes reach beyond their documented scope.

Profile the next necessary LLVM release build with Zig's time report; do not
rebuild LLVM native unit tests. Further scheduling work can use the recorded
per-test durations to measure shard imbalance before changing the partition.

Keep genuine boundary tests in extended validation. Examples include the
evidence limit, a 2^19-visit projection DAG and a million-instruction relocation
budget. Shrinking them would stop testing their intended limits.

A quick pass never replaces the full native exhaustive-OOM gate, full guests/CI,
or release exact-output, CPU, runtime and allocation qualification. Frozen
evidence remains tied to its original inputs.

Validation before publication: all 44 tooling tests pass. The final full-gate
smoke-lease correction passes all 19 affected launcher/journal tests, including
a new busy-before-build regression. The 256-local boundary law also executes and
passes in default full mode with zero skips, failures, leaks or logged errors.

## Explicit shard scheduling and additional areas

The full gate now executes the installed native binary directly in one to four
bounded concurrent shards, default two. It inventories the binary first, checks
every shard against its exact partition, rejects missing/repeated/skipped tests,
and requires the requested allocation-failure mode and complete shard records.
Full qualification always requests `full`; standalone sampled runs remain
explicit development measurements. No test cases or exhaustive sweeps were
removed.

Each shard has its own logs and measured monotonic execution interval. The
coordinator reports peak active shards and retains partial evidence on failure.
A failed shard cancels its siblings, including descendant process groups. Native
journal reuse pins the inventory, raw shard logs, report, executable and
aggregate phase logs; altered or incomplete evidence cannot become a resumed
pass.

The earlier small Zig probes already overlapped forced runs with and without an
explicit working directory. They did not explain historical production
serialization. Direct scheduling removes dependence on that build scheduler for
full-gate execution; it does not claim a diagnosis of Zig itself or a release
speedup. Synthetic barrier tests prove one/two/four-worker execution and
failure, cancellation and resume behavior. Real inventory measurements are
recorded below.

Use `deno task check:dev --list-areas` for the supported selections:

| Area             | Native laws | Guest coverage                                                                 |
| ---------------- | ----------: | ------------------------------------------------------------------------------ |
| `syntax`         |           9 | CST structure and annotation success/rejection                                 |
| `type-effects`   |           9 | Nominal identity, symbolic rows, retained/archive specialization and rejection |
| `body-checking`  |           8 | Seven fresh/retained revisions including edits, rejection, recovery and revert |
| `static-sharing` |          16 | Protocol, budget and selected client recovery                                  |

These are focused families, not whole-subsystem substitutes. Their native laws
include positive behavior, rejection/recovery and ownership/OOM checks. Every
command still compiles the complete native inventory and enforces its
five-minute budget. Selected-only guest areas avoid an empty Deno file list
(which would otherwise discover unrelated tests), and requested guest fixtures
are derived from the manifest. Unknown areas fail before any build starts.

The three new commands pass on the isolated published compiler baseline, with
all 2,499 native tests compiled: `syntax` **25.25 s** (9 native/13 guests),
`type-effects` **25.98 s** (9 native/7 guests), and `body-checking` **17.65 s**
(8 native/1 guest). Reports are `build/bench/shards-areas-AREA/results.json`.
The existing `static-sharing` family also passes in **28.51 s**, executing all
16 native laws and 45 guests through the updated workflow.
All 51 compiler-tooling tests pass, including the integrated full-gate
failure/repair/resume/native-edit sequence. These are measured development runs,
not a cold-build or p95 guarantee.

The real complete-inventory execution passes all **2,499 native tests in
172.81 s**, split into 1,250 and 1,249 tests with a measured peak of two active
shards. This census uses sampled allocation failures and does not qualify a
release. Source and executable digests stayed unchanged during the measurement.
Raw per-shard logs and intervals are retained under
`build/bench/shards-areas-census`; `results.json` records exact inventory coverage
and `pins.json` records the before/after identity checks. Full exhaustive-OOM
timing remains to be measured in the next necessary release qualification.
