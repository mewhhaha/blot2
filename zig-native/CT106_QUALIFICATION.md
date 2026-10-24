# CT106: exact frontend reuse and bounded inference work

CT106 fixes the demonstrated first-edit graph correspondence boundary, removes
repeated type/effect and lexical work, and adds measurements for query stages,
allocator capacity, hardware counters and compiler construction. The complete
[86-suggestion ledger](../COMPILER_CT106_WORK.md) distinguishes implemented work,
rejected trials, conditional alternatives and unfinished work. It does not claim
that every proposed architecture has been implemented.

## Seven alternating release pairs

Baseline native SHA-256:
`0eadf4bb1a0cc7448f59156091a7287e2456aedfd4b31452197a0a3437a1da78`.
The frozen 554-file gdev/Ink/stdlib manifest is
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`:
189 game modules, optimized codegen, four backend workers, a 200-million
inference budget, profiling off and persistent restart cache disabled.
Every fresh/edit/revert result matches the previous strict Wasm pins and the
independent fresh controls. All seven pairs are retained.

| Workload / phase | Baseline wall | CT106 wall | Baseline CPU | CT106 CPU | Paired CPU change |
| --- | ---: | ---: | ---: | ---: | ---: |
| game / fresh | 7.509 s | 7.292 s | 7.640 s | 7.470 s | -2.4% |
| game / edit:literal_in_body | 3.620 s | 2.907 s | 3.850 s | 3.150 s | -19.1% |
| game / revert:literal_in_body | 2.657 s | 2.811 s | 2.900 s | 3.080 s | +3.5% |
| game / edit:body_change | 4.942 s | 4.900 s | 5.170 s | 5.150 s | -0.2% |
| game / revert:body_change | 4.927 s | 4.872 s | 5.170 s | 5.020 s | -1.7% |
| devtools / fresh | 0.674 s | 0.683 s | 0.710 s | 0.710 s | +1.3% |

CPU changes are medians of ratios within each pair, not ratios of independent
medians. Process CPU includes workers at 10 ms resolution; no-op percentages
are not useful. Wall time excludes project/process opening. Host load changes
from 8.52 to 5.54 on 16 logical CPUs, with unrelated applications active. Raw
ranges, order and inputs are retained; these are not quiet-host latency bounds.

Fresh-game and devtools regression guards pass. The first-edit improvement is
substantial; the proposed 10% fresh/body and 10% later-literal targets are not
met. Body CPU is effectively unchanged and later-literal CPU regresses 3.5%.
Neither two-second nor sub-second ordinary edits are reached. Work-counter
reductions must not be presented as a larger end-to-end improvement.

Median lifetime peak RSS is 483.44 → 482.04 MiB fresh, 707.82 → 688.28 MiB after
the first literal, and 755.50 → 752.61 MiB after the body edit. Retained peaks
include preceding requests; they are not per-edit live memory.

## Implementation and correctness boundaries

- Frontend graph correspondence now permits different sharing of equal immutable
  constructors. Type and row variables still require injective correspondence.
  Exact catalogs, content, depth and work limits remain authoritative. The first
  literal edit checks one module and reuses 188, instead of checking 22.
- Operation interning uses bounded structural shapes to select an oldest-first
  candidate chain, followed by exact equality. Closed operation certificates
  reuse argument heights within physical-owner and solver-generation guards;
  mutation, rollback and saturation retain conservative paths. Fresh candidate
  inspections fall from 90.45 million to 0.74 million, and actual argument-height
  checks from roughly 76 million to 1.79 million. Those work reductions are not
  equivalent to CPU speedups.
- Wide record/effect comparisons use temporary indexes while preserving field
  lookup and duplicate-label semantics. Certified closed DAG comparisons avoid
  repeated pairs; open and cyclic graphs retain bounded validation. Historical
  replacement queries have first-write and after-last-write shortcuts.
- Watch traversal deduplicates bounded exact IDs and retains links for exactly
  unchanged ordered frontiers. Row-variable sharing follows lexical-scope links.
  Dense unit lookup retains the original sparse/duplicate fallback.
- Query keys include additional owner-valid discriminators. Optional canonical
  admission precedes replay-array copying. Small traversal/import temporaries
  use stack-first storage and exact local reservations; durable ownership stays
  unchanged. Selected-query candidate counts did not improve on this workload.
- Bounded declaration-containment indexes cover nested closures and suspensions.
  Ambiguous or incomplete indexes fall back to whole-module observations. Two
  narrowing attempts reach each remaining principal's own changed source
  position. All four body-principal declines remain: 16 of 20 results are reused.
  A stable declaration-origin proof is still required.
- Compiler identity recomputes Zig build configuration after a retained-cache
  experiment exposed a stale digest across source edits. Compiled artifacts and
  generated files remain cacheable. Retained and fresh configuration identities
  now agree; production/test/target edit-and-revert controls pass.

Finer arena bins were rejected: they lowered one peak but increased requested
and provided capacity. Write-notification coalescing observed no duplicates and
was removed. Both prototypes remain in the evidence. Neither rejected trial
changes the final allocator/worklist policy.

## Profiled residual work

Three same-binary profiling-off/on pairs preserve exact output. Paired CPU
ratios for substantive phases range from 0.946 to 1.027, except population
which is separately recorded. Changing host load prevents interpreting faster
profiled samples as an optimization or proving that instrumentation is free.
These are attribution screens, not the primary seven-pair release comparison.

| Profiled game phase | Checking | Inference | Total minus inference |
| --- | ---: | ---: | ---: |
| fresh | 1266.6 ms | 4630.5 ms | 2577.9 ms |
| edit:literal_in_body | 63.8 ms | 1475.8 ms | 1654.5 ms |
| revert:literal_in_body | 66.8 ms | 1476.5 ms | 1547.7 ms |
| edit:body_change | 65.7 ms | 4158.3 ms | 1568.6 ms |
| revert:body_change | 65.0 ms | 3930.1 ms | 1495.1 ms |

Literal-revert exclusive query stages (median ms): prepare 0.253, scan 0.581, source 1.095, import 16.066, match 9.316, validate 77.020, publish 1.117.
Remaining lookup is 406.0 ms, constants 107.2 ms and replay 62.4 ms.
These work categories are exclusive: entering a query stage pauses lookup.
They are nested within the backend clock and must not be added to that clock
again. The 0.8-second
non-inference milestone is not met. Query validation/import remain useful
measurement targets; a larger cross-owner cache requires exact observations
and is not implemented by this pass.

## CT106 policy screen, 24 October 2026

Three alternating pairs per policy compare the same final CT106 release with
semantic workers disabled versus two or four workers. All frozen fresh, retained
and independent fresh-control outputs match the strict Wasm pins. These are
shared-host screening runs, not seven-pair optimization qualifications.

| Candidate policy | Fresh game CPU | First literal CPU | Literal revert CPU | Body edit CPU | Fresh devtools CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 workers | -0.5% | +1.4% | +2.9% | +2.4% | +3.7% |
| 4 workers | +2.6% | +2.0% | +2.7% | +0.7% | +5.4% |

Percentages are medians of within-pair process-CPU ratios. Neither policy
establishes an ordinary-edit improvement. Four workers also exceed the 5%
devtools guard. The serial default remains unchanged.

Both policies admit 281 component jobs in 14 fresh-game batches. The two-worker
run records 14,372 attempts: 9,863 decline during proof recording and 4,405 lack
worker I/O in their private context. Default-policy attempts are all disabled.
Independent selected-query parallel jobs remain zero. The maximum worker count
reports admitted batch capacity, not simultaneous useful execution. Parallel
proof recording needs a deterministic ownership/publication design; increasing
worker count does not remove that prerequisite.

## CPU target and hardware screens

A three-pair same-source screen compares portable baseline targeting with
`-Dcpu=native`. It uses the earlier isolated CT106 source, before the later
identity/heap-observation additions, so it must not be confused with the final
seven-pair compiler comparison. Portable SHA-256 is
`de3bf00c804d665bb5142a030eb3aa18e46c454a79880564ec12f15dae7c5bac`;
host-native SHA-256 is
`e82fba76e94cd84f2a86f97705e0f37943008f77199fdd75f6731747365f0648`.
Strict outputs pass. Paired CPU changes are fresh -1.8%, first literal +7.1%,
literal revert +6.2%, body edit +3.2% and devtools +1.4%. The target change fails
the ordinary-edit screen. The portable baseline target remains the default and
installation candidate.

Two opposite-order PMU comparisons use CT105 and the final CT106 binary. They
cover user-space whole build requests on all existing and inherited future
compiler threads. All nonzero counters report full scheduling: enabled time
equals running time, so these samples require no multiplex scaling. Idle root
threads can have zero enabled/running time and zero counts. Internal phases and
model-specific cache/TLB events are not isolated.

| Build | CT105 instructions | CT106 instructions | Instruction change | Cycle change |
| --- | ---: | ---: | ---: | ---: |
| fresh | 92.54 billion | 86.30 billion | -6.8% | -3.8% |
| literal_in_body | 48.95 billion | 37.89 billion | -22.6% | -23.1% |
| literal_revert | 37.22 billion | 36.71 billion | -1.4% | -0.3% |
| body_change | 64.01 billion | 61.20 billion | -4.4% | -4.6% |
| body_revert | 63.97 billion | 61.18 billion | -4.4% | -2.5% |

These two-pair screens support reduced instruction work, but do not replace the
seven-pair CPU result, particularly its unchanged body-edit CPU and slower
literal revert. Fresh IPC changes from 2.55 to 2.47; generic cache-miss fraction
is 7.40% versus 7.44%. This does not establish a cache-level, TLB or bandwidth
bottleneck. The raw branch/cache events and scheduling times remain available.

A separate opposite-order placement screen compares five distinct cores
(`0-4`) with five logical CPUs on three cores (`0,1,2,8,9`). It constrains the
whole compiler CPU set, not each worker's placement. Instruction counts are
unchanged. The SMT-packed set increases first-literal, later-literal and body
CPU by roughly 3.3%, 3.5% and 3.7%; fresh CPU is effectively unchanged. Shared
host activity and two samples per set limit this to a screen. No affinity or
false-sharing policy is inferred from it.

## Held-out programs

Three-pair screens pass the historical five-program synthetic suite and the
explicit nine-case review matrix: records of width 32/128, effect rows of width
16/64 with explicit providers, closures of depth 16/64, a shared diamond, a small
program and 32 producer modules plus an entry. Fresh, retained and independent
fresh edit controls agree between CT105 and CT106. All **36** original/edited
executions across both compilers return independent expected results and match
the measured Wasm hashes.

Most cases take only a few milliseconds, below useful resolution for 10 ms
process-CPU ticks; no fine CPU percentage or 5% guard is claimed for them.
The depth-64 closure case is about 52 ms fresh and 56 ms edited in the candidate.
These are coarse regression controls, not a substitute for the main workload.
The first effect fixture attempted to export an unhandled custom effect row
and correctly failed `entry_type` in both compilers. Explicit providers repair
the fixture; only the completed rerun is counted as a pass.

## Memory and attribution

An unprofiled session executes 200 distinct literal edits, no-ops, errors,
recovery and restoration: **232 requests** with **12 sampled fresh controls**.
All sampled outputs and recovery/restoration controls pass. Other revisions do
not have independent fresh controls. RSS is about 482 MiB after edit 10, 489 MiB
after edit 40 and 523 MiB after edit 200; restored/idle RSS is about 524 MiB.
Lifetime peak is 794.65 MiB, with no major faults or swap reported. This run
partly overlapped other qualification/build work and is memory evidence, not a
latency comparison or proof of an indefinite bound.

Separate 50-edit and 40-edit profiled runs use the final release. From edits 10
through 40, small-block slab capacity stays at 187.8125 MiB, with 51.663 MiB
free, 0.430 MiB unused and 135.719 MiB rounded allocated capacity. Class counts
are unchanged. In the virtual-memory run, VmSize stays at 1,620,396 KiB, VmData
at 1,609,796 KiB and thread count at five while RSS rises from 491,396 to
498,752 KiB. This supports increased residency within stable mappings during
that window; it does not establish a leak or growing small-slab pool.

`sessionHeap` is collected only with profiling, before revision publication,
when old and pending owners can overlap. It excludes direct large mappings.
Requested bytes, arena backing capacity, rounded allocated capacity, current RSS
and lifetime peak are distinct quantities. No speculative idle trimming, huge
page policy or allocator-lock redesign was installed.

CPU-weighted literal edit/revert stacks account for 99.555% of sampled CPU over
522 complete intervals. Exclusive nearest-directory ownership is check 31.15%,
eval 25.62%, reuse 20.36% and backend 19.28%. Self samples include memcpy 3.00%,
projection-cache lookup 2.85%, implementation-use context 2.15%, operation
argument resolution 1.90% and closed-height lookup 1.88%. Debugger stops perturb
execution; these are attribution observations, not latency measurements.

The new tools and their scopes are documented in
[scripts/bench/README.md](../scripts/bench/README.md). The PMU collector verifies
future-thread inheritance with a one-versus-two-worker instruction ratio of
2.00001. Generic cache counters do not identify a particular cache/TLB level.
The Zig timing collector passes raw-frame replay and rejects premature closure
and a missing step report.

## Compiler construction and development cycles

Twenty complete `check:dev --area static-sharing` edit/check cycles pass in a
disposable checkout: seven leaf-source edits, seven checker diagnostic edits and
six test-only fixture edits. Every cycle compiles the complete 2,564-law native
inventory and executes the same 78-law family with sampled allocation faults,
55 selected guest checks and local format/type/Zig analysis. Source restoration,
production-versus-test compiler identity and exact native inventory checks pass.
The test-only fixture is compiled as part of the full inventory; the selected
runtime family remains static-sharing. These cycles do not qualify every law
or the experimental source edits as releases.

Observed complete-cycle median is **25.35 s**, sample
p95 **27.64 s**, maximum **27.78 s**.
Initial checkout setup/check and three group-restoration checks are recorded
separately. The first attempted sequence failed a cache-directory teardown race
and is not included as a successful cycle. The completed sequence starts again
from its own initial check. Host global caches are retained, local checkout
caches start fresh, and OS caches are not flushed. Unrelated host work continues.
This is a 20-sample observation, not a universal latency bound or a paired
compiler-build speedup claim.

| Edit class | Complete cycle median | Compiler construction | Full native compilation | Sampled native execution | Guest smoke |
| --- | ---: | ---: | ---: | ---: | ---: |
| leaf | 25.39 s | 4.29 s | 7.62 s | 1.00 s | 9.75 s |
| checker | 26.25 s | 4.87 s | 8.03 s | 1.04 s | 9.87 s |
| test | 20.50 s | 0.35 s | 7.20 s | 1.02 s | 9.73 s |

All cycles use Zig 0.17.0 Safe/noLLVM and zero Zig lint findings. The cached
production build on test-only edits is preserved. Native compilation and the
selected guest suite are the next development-cycle costs; the deep principal
law deliberately crosses a 128-level import boundary at depth 130, so shrinking
it below that boundary would remove its coverage.

The actual release timing trace records **227.759 s total**, including
**220.884 s LLVM emission** (about 97%), 0.678 s file work, 5.912 s declarations
and 0.239 s link flush. It reports 855 reachable files, 436 imported files,
12,851 generic instances, 7,699 inline calls and 13,963 declaration timing rows.
CPU categories can overlap and are not an additional wall-time sum. Generic
interface erasure is not justified by this trace. The 150-second release and
480-second exhaustive-native targets remain open. Timing-server shutdown after
successful capture is not a failed compiler build.

## Qualification

The final full gate passes with **2,564 native laws**, exhaustive allocation
failures, **1,655 guest checks**, **48 smoke checks** and **57 tooling checks**.
The final full `deno task lint:zig` check reports zero findings.
Native compilation uses Zig 0.17.0 Safe/noLLVM; the release uses LLVM and the
portable x86-64 baseline CPU target. Four native shards take 599.42, 622.13,
648.68 and 637.12 seconds; complete native execution takes 648.72 seconds.
The roughly 49-second spread does not justify replacing weighted scheduling.

The final guest pass resumes the exact verified native evidence and takes
51.84 seconds including smoke/tooling/release-cache/pack phases. This is **not**
a 52-second full-suite runtime. Three guest-only fixes wait for detached restart
writers through the documented same-key reopen handshake before deleting their
temporary directories. The failed cleanup attempts, including the first development-cycle run, are retained.

An earlier gate passed native execution but was invalidated by concurrent edits
in the sibling gdev checkout. Qualification moved to an isolated checkout with
frozen sibling fixtures. A later attempt stopped at a Zig smoke-build panic
while `/tmp` was full; temporary work moved to the workspace disk. Neither
interrupted attempt is counted as a pass. The source and exact native evidence
of the successful resumed gate remain pinned.

Final native SHA-256:
`7d7ea08313e865a633ec9be2acc0347bc1560490ce8caca82e96df1c5b2dba69`.
Compiler-identity-file SHA-256:
`c6f01a199871b66d90fb24354c1d165bfff7bdc10323ea83c7c92cc8964a004f`.

The matching CLI and native compiler are installed at `~/.local/bin/blot` and
`~/.local/bin/blotc`, with rollback copies. Staged and installed checks run from
outside the repository: format, format-check, source-check, build, matching
CLI/native Wasm, no-import instantiation and list-example result **29** all pass.
The bundled guide matches its source. Installed CLI SHA-256:
`0fc44a8d4be387868f9cf95df10300039b8e9bb8a472567e73909d2cd3ce6410`.

The [evidence archive](measurements/ct106-2026-10-24.tar.gz) and
[SHA-256 sidecar](measurements/ct106-2026-10-24.tar.gz.sha256) preserve raw pairs,
hardware counters, memory sequences, timing frames, all qualification attempts,
20-cycle results, source/binary/manifest pins, the source patch, new source/tool
files and installation records. Internal `SHA256SUMS` is verified after writing.
Private workload sources, binaries, generated Wasm and caches are excluded;
public generated synthetic fixtures are included. Reproducing gdev requires the
matching frozen source manifest. See the [ledger](../COMPILER_CT106_WORK.md) for
all 86 dispositions, including partial and remaining work.
