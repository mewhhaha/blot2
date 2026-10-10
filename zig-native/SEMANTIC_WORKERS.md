# Semantic worker policy

Task 013 is qualified at source milestone `4c61f25`. The default continues to
use serial inference; explicit `semanticWorkers` or `--semantic-workers` selects
the private path, including explicit one-worker mode. This record keeps
performance policy separate from the
[semantic ownership rules](SEMANTIC_JOBS.md).

## Measurements and owners

Fresh native CLI measurements use child user plus system CPU from Linux
`getrusage(RUSAGE_CHILDREN)`. Wall time covers process creation through captured
process completion, before the harness writes or parses its output. Persistence
is disabled. Fifteen rounds alternate the order of six policies: task 011,
candidate serial default, and candidate workers 1, 2, 4 and 8. Every round
compares exact Wasm and verifies zero live requested bytes. The first
exploratory run included harness output processing in its wall timer; only the
corrected second run qualifies performance.

Retained measurements use separate LLVM native drivers built from the pinned
task-011 and candidate sources, with `-fllvm -flld -Ofast`, x86-64 baseline CPU
target and Zig 0.17.0. Linux `getrusage(RUSAGE_SELF)` includes CPU used by all
process threads. Each phase starts before prepare and ends after commit, Wasm
digest calculation and candidate destruction. Fixture setup, initial Session
construction and JSON reporting are outside the phase. The driver uses the
production retained Session and allocation tracker, with the same worker policy.
Seven alternating rounds each run 21 population/edit/revert/no-op cycles.
Separate production CLI invocations check fresh compilation, cache population
and restart against those native bytes.

Backing requested bytes include private worker Sessions and arenas, results,
coordinator staging and the retained old/new revision overlap. Positive
resize/remap growth contributes traffic; allocation-call counts describe new
allocations. Retained live bytes are measured after commit and candidate
cleanup; peak live bytes include coexistence during prepare. Solver and scratch
counters describe logical arena clients and overlap backing bytes. Import
counters are subsets of those clients; their peaks are per owner, rather than
the concurrent total. Process RSS, executor/thread stacks and allocations
outside the compiler tracker are separate. Every driver checks zero tracked
bytes after Session destruction and checks a stable retained plateau for each
repeated phase.

## Optional profiling

Profiling adds exclusive coordinator wall clocks: `semantic_coordination_us`
covers ready-set preparation and coordinator work outside dispatch/publication;
`semantic_dispatch_us` covers dispatch, joined execution and worker-arena
reset/destruction; `semantic_publication_us` covers staged evidence cloning,
import, reservation and installation. These clocks nest inside existing work
phases and replace their attribution for the same interval. They do not
partition process CPU.

`semantic_job_sum_us` sums private callback wall times, including private
Session teardown, for returned completed or declined component results. It
overlaps dispatch and can exceed its wall time. Throwing allocation failures and
cancelled slots have no returned job time. Generic worker-arena
reset/destruction after a callback contributes to dispatch, not the job sum. No
worker mutates the coordinator clock; returned times merge after join. Profiling
never supplies a semantic decision, budget or artifact validity judgment.

`max_semantic_component_workers` reports admitted batch capacity, including the
coordinator. It does not report simultaneous execution, physical CPU count or
CPU utilization. Component job counts include submitted slots. Unprofiled
records omit the detailed `work` timing object. A dedicated execution law checks
that profiling leaves Wasm and deterministic work counters unchanged.

Reused-output no-op phases do not open backend work clocks; their detailed
timing object is absent even in the profiled driver. The profiling CSV
represents these absent clocks as zero. The separate profiled batch compares
every Wasm, work-counter and retained-live result against the unprofiled batch:
**10,080 retained phases and 120 fresh CLI builds**, with zero teardown bytes.

## Immutable pins and conditions

The candidate is `build/bench/cloud-principal-graphs/candidate-worker-policy/`:
compiler SHA-256
`2c511afb7d3fa257f9538b534d93b175ec623e6e3656e1150ddb5ad3964679ee`,
identity-file SHA-256
`07583dbd69b791c698a0f877f1a3b4ae98918fca92a8c76654e997ed98c48f07`, and
four-file source-input map SHA-256
`e09007e7d2001e7ec4d6b3959f379adefebbc066aaaeb4f3ca16b8f2dc1e6584`. Task 011's
unchanged `candidate-allocation/` baseline compiler is
`571c1ccab004a8659553a20b10d5eb2e4b1ad9e680999a59156bc7b66af92c36`. Task 012's
unchanged `candidate-semantic-jobs/` compiler is the equivalence baseline,
`c96e7679ac6173b9d3b9bb3a76d78c1904f4be6735f9419406b2390d93554466`.

The retained driver binaries are baseline
`d286cef0b2686626627804773c6a7e652a66f010c3f63a82471c65ced754d9f9` and candidate
`12f34d59087482b24e409bbeedc255441c229f8f8f17438a9b5eeea01c025a1f`. Their
identical driver source hashes to
`ca878bd5d9241e1bce4ee63f1e36a2259e8f906d9ba00aac54e313666619d917`. Both source
trees and individual files are pinned in
[the manifest](qualification/semantic-workers-pins.json). The sorted compact
path/hash maps for standard library and workloads hash to
`b43bb89d1e0c1ef37cc896e9546d8f7a5a751e3b93285b72f011c5ca0e6b9abc` and
`e7c95b42d48f33b94e31d256580b3a4972bcd893f159f1fee1347712402deb85`. The manifest
also records helper/report hashes and complete scheduler/cgroup snapshots.
Source inputs and compiler binaries stayed fixed during qualification.

No builds or test workloads ran concurrently with the measurements. Scheduler
policy was **SCHED_OTHER**, nice **0**, affinity CPUs **0–4**, with a cgroup
quota of **400,000 µs per 100,000 µs**: four CPUs of capacity. Workers 1, 2 and
4 are feasible counts; 8 is an oversubscription control. Fresh one-minute host
load started/ended at **0.676/1.093**; retained load at **1.093/1.131**. Neither
primary batch added cgroup throttling. Filesystem caches and shared-host
activity remain uncontrolled; small overlapping timing ranges are not gains.

## Fresh CPU and wall qualification

The corrected helper `measure-semantic-jobs.py` covers **83 workloads, 15
alternating rounds and 7,470 fresh invocations**. All six policies produce
identical bytes, deterministic per-policy work counters and zero tracked
teardown bytes. Complete sorted CPU, wall, backing-request and peak
distributions for every workload and policy are retained in
[the fresh CSV](qualification/semantic-workers-fresh.csv). Geometric means of
per-workload median ratios against candidate serial default:

| Policy        | CPU ratio | Wall ratio |
| ------------- | --------: | ---------: |
| One worker    |    1.0692 |     1.0674 |
| Two workers   |    1.1292 |     1.1014 |
| Four workers  |    1.1517 |     1.1175 |
| Eight workers |    1.1740 |     1.1362 |

Independent-call graphs expose scheduling overhead directly. CPU / wall median
µs for 8, 32 and 128 leaves:

| Policy         |      8 leaves |     32 leaves |    128 leaves |
| -------------- | ------------: | ------------: | ------------: |
| Task 011       | 1,048 / 1,248 | 1,774 / 1,973 | 4,072 / 4,333 |
| Serial default |   869 / 1,054 | 1,519 / 1,744 | 3,912 / 4,182 |
| One worker     |   907 / 1,114 | 1,513 / 1,818 | 4,223 / 4,545 |
| Two workers    | 1,153 / 1,357 | 1,852 / 2,053 | 4,756 / 4,776 |
| Four workers   | 1,599 / 1,784 | 2,356 / 2,424 | 5,143 / 4,815 |
| Eight workers  | 2,275 / 2,406 | 3,482 / 3,313 | 6,008 / 5,554 |

For 128 leaves, serial CPU/wall ranges are **3,317–4,769 / 3,531–4,982 µs**;
four-worker ranges are **4,746–6,129 / 4,583–5,780 µs**. Faster individual
observations against task 011 do not attribute a gain to parallelism: the
candidate serial path is the relevant policy control. The private path pays for
Session cloning, evidence import, snapshots and coordinator staging.

## Retained CPU, allocation and restart

`measure-worker-policy-memory.py` covers eight workloads: capture-factory widths
8/32/128, actual dependency widths 32/128 and independent-call widths 8/32/128.
Its **336 native driver processes / 28,224 revision phases** plus **1,008 CLI
fresh/cache-population/restart builds** match exact Wasm across all six
policies. Every per-phase retained plateau is stable and every owner tears down
to zero. The [retained CSV](qualification/semantic-workers-retained.csv)
preserves all CPU/wall distributions, backing-byte/peak distributions and median
owner totals.

Independent 128-leaf population / edit CPU and wall median µs:

| Policy         | Population CPU / wall | Edit CPU / wall | Restart CPU / wall |
| -------------- | --------------------: | --------------: | -----------------: |
| Task 011       |         3,936 / 3,931 | 3,250.5 / 3,254 |      4,279 / 5,097 |
| Serial default |         3,653 / 3,646 | 3,166 / 3,165.5 |      4,575 / 5,239 |
| One worker     |         4,172 / 4,166 | 3,786 / 3,786.5 |      4,901 / 5,716 |
| Two workers    |         4,372 / 4,091 |   3,767 / 3,539 |      5,006 / 5,640 |
| Four workers   |         5,167 / 4,512 | 4,010 / 3,522.5 |      5,907 / 6,413 |
| Eight workers  |         6,073 / 5,320 | 4,367 / 3,661.5 |      7,392 / 7,352 |

At width 8, one-worker population is **644/638 µs** versus serial **708/701**,
but its edit is **302/302.5** versus **285/285** and fresh CPU also rises. This
does not establish a phase-independent enablement threshold. Width-128 no-op
medians remain **28–30 CPU / 28–30 wall µs** with **28,930** candidate requested
bytes and **341,976** retained live bytes, independent of policy.

Population backing requested bytes / new allocation calls / peak live bytes:

| Workload        |                      Task 011 |                Serial default |                    One worker |                   Two workers |                  Four workers |                 Eight workers |
| --------------- | ----------------------------: | ----------------------------: | ----------------------------: | ----------------------------: | ----------------------------: | ----------------------------: |
| Independent 8   |        248,048 / 752 / 62,316 |        248,104 / 752 / 62,316 |        283,772 / 879 / 62,316 |        321,648 / 886 / 74,223 |       397,400 / 900 / 111,451 |        283,772 / 879 / 62,316 |
| Independent 128 |   3,447,309 / 6,034 / 885,215 |   3,447,365 / 6,034 / 885,215 |   3,540,845 / 7,963 / 885,215 |   3,592,173 / 7,968 / 885,215 |   3,694,829 / 7,978 / 885,215 |   3,694,829 / 7,978 / 885,215 |
| Capture 128     | 3,562,243 / 3,469 / 1,206,811 | 3,562,299 / 3,469 / 1,206,811 | 3,669,159 / 3,506 / 1,206,587 | 3,783,563 / 3,512 / 1,206,587 | 3,783,563 / 3,512 / 1,206,587 | 3,783,563 / 3,512 / 1,206,587 |
| Dependency 128  |   2,380,074 / 2,213 / 741,662 |   2,380,130 / 2,213 / 741,662 |   2,465,390 / 2,235 / 741,662 |   2,579,690 / 2,241 / 741,662 |   2,579,690 / 2,241 / 741,662 |   2,579,690 / 2,241 / 741,662 |

These are medians, not promises of identical worker-arena allocation.
Eight-worker independent-8 requests range **283,772–473,152**, and
independent-128 requests range **3,592,173–3,900,141**. Dispatch order changes
which workers actually need arenas even when admitted capacity is eight. Logical
counters and bytes remain deterministic. Retained population bytes are identical
across policies: **26,886 / 341,928 / 655,940 / 354,332** for the four rows
respectively. Width-128 independent edit retains **341,976** with peak
**1,227,039** for every policy, while four-worker requested traffic grows to
**4,053,660** from task 011's **3,806,140**. Capture edits retain **655,936**,
with serial peak **1,865,679**, explicitly including old/new revision
coexistence. Instrumentation adds **56** native phase bytes versus task 011 even
on unchanged no-op paths.

## Coordination and job costs

The separate `profile-worker-policy.py` batch reports wall attribution rather
than qualifying CPU. Complete distributions for all eight workloads, five
policies and fresh/population/edit/revert/no-op are in
[the profiling CSV](qualification/semantic-workers-profile.csv). Median
coordination / dispatch / publication / overlapping job sum µs:

| Workload and phase         |                One worker |         Two workers |          Four workers |           Eight workers |
| -------------------------- | ------------------------: | ------------------: | --------------------: | ----------------------: |
| Independent 8 population   |           3 / 50 / 6 / 39 |    3 / 202 / 7 / 80 |     3 / 458 / 7 / 232 |       4 / 977 / 8 / 113 |
| Independent 8 edit         |           2 / 31 / 6 / 27 |   2 / 44 / 6 / 34.5 |   2 / 75.5 / 6 / 70.5 |     2 / 96.5 / 8 / 99.5 |
| Independent 128 population |       50 / 445 / 86 / 421 | 54 / 408 / 83 / 494 |   56 / 697 / 94 / 816 | 58 / 1,217 / 89 / 1,073 |
| Independent 128 edit       | 45.5 / 431.5 / 85 / 410.5 | 50 / 289 / 83 / 467 | 50 / 260.5 / 89 / 714 | 51 / 277 / 86 / 1,310.5 |

Some large retained dispatch phases shrink with multiple workers. Total CPU and
wall against the serial default still rise; this phase improvement does not
justify enabling the whole path. Fresh startup, allocations and private evidence
ownership remain substantial. Profiling overhead is excluded from the primary
policy comparison.

## Validation and decision

Zig **0.17.0**, the full LLVM native suite and **621 guest/client tests** pass
(`worker-policy-full-gate-v1.log`); `deno task lint:zig` reports zero findings
across **297 files** (`worker-policy-analyzer-v1.log`). The focused ownership
batch passes **25 tests**; package/API/publish dry run and affected formatting
pass. Against task 012, **626 cases / 3,756 invocations** preserve ordered
diagnostics and Wasm, including unsuccessful cases and zero-live teardown.
Original execution passes **192 guests / 10,362 calls**. Six-policy retained
edits, failures, recovery and checkpoint restart pass **2,106 successful
samples** and **648 guests / 41,208 original and edited calls**.

Keep the **serial default** and the qualified **opt-in** path. No tested size
threshold consistently improves both total CPU and wall across fresh and
retained phases. Private worker memory and dispatch costs can exceed the small
jobs they parallelize, and eight workers are unsuitable as a default under this
quota. Users may measure their own sufficiently expensive independent
components. Unsupported lexical origins or source contexts still fall back to
serial; running cancellation waits for the bounded current job. No gain, RSS
target or private-application allocation target is claimed. The historical boxed
compiler and private gdev application remain unavailable, so their external
gates remain open. These observations qualify policy for the represented public
domain, not all hosts or application graphs.
