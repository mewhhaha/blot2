# CT115: big frontend levers, parallelism and SIMD

The strongest new lead is repeated generic-requirement work in the application's
builder composition. Parallel module checking is useful, but its dependency
chain prevents it from reaching a sub-second fresh frontend by itself. SIMD
lexing has a small ceiling on this workload.

This is a diagnostic investigation of qualified CT114, not a new optimized
compiler. The production source and local installation are unchanged. No syntax
change is made or required for the first proposed experiments.

## New measurements

Three instrumented LLVM ReleaseFast fresh builds cover the same frozen gdev
snapshot: 189 checked modules and 1,604 distinct import/prelude edges. CPU
clocks cover each module, with separate header and body checking intervals. The
table sums per-module medians, so it is not a single build's elapsed clock.

| Checker work                                             | Coordinating-thread CPU |
| -------------------------------------------------------- | ----------------------: |
| All module checks                                        |              1,296.4 ms |
| Header checking, including scheme import                 |                325.1 ms |
| Body checking                                            |                818.3 ms |
| Other module work, including capture/publication/cleanup |                153.0 ms |

The largest module is particularly revealing:

| `src/game.blot`                                       |                       Observation |
| ----------------------------------------------------- | --------------------------------: |
| Source syntax nodes                                   |                             1,781 |
| Checker CPU                                           |          447.3 ms, 34.5% of total |
| Header CPU                                            |                           17.5 ms |
| Body CPU                                              |                          427.6 ms |
| Type nodes in its completed solver, including imports |                           592,006 |
| Selected generic-requirement candidates               |   587,596, 91.5% of project total |
| Free-type graph visits                                | 4,093,077, 74.1% of project total |
| Free-row graph visits                                 | 5,335,455, 75.6% of project total |

This small source module composes plugins through 78 sequential `application :=`
updates. The compiler's `rebindStatement` calls `local`; for a non-scalar value,
`local` computes the free environment and constructs a generalized scheme.
`schemeInto` collects candidate requirements and runs fixed-point closures over
type/row sets. The source and counters identify a strong candidate for repeated
work. They do not yet attribute every candidate to `game_using`, prove a
quadratic complexity curve, or prove that generalization can safely be omitted.

The next largest module checks are `robots.blot` at 62.7 ms, `main.blot` at 54.8
ms and `station.blot` at 47.5 ms. Module size alone is a poor scheduling weight:
`robots.blot` has 15,060 syntax nodes, over eight times `game.blot`, but takes
much less checker CPU.

## What module parallelism can achieve in the model

The longest dependency chain contains 24 modules and 797.4 ms of checker CPU. It
runs through the prelude, engine libraries, gameplay modules, `game.blot`, and
the final entry. The independent fresh runs put this chain at 796.9–802.6 ms.
Four workers nearly saturate the available module-level parallelism under a
critical-path-priority list scheduler.

| Workers | Modeled checking | Modeled whole frontend |
| ------- | ---------------: | ---------------------: |
| 1       |         1,296 ms |               1,736 ms |
| 2       |           896 ms |               1,336 ms |
| 4       |           798 ms |               1,238 ms |
| 8       |           797 ms |               1,237 ms |

The frontend column adds 438.4 ms of other measured frontend phases and 1.0 ms
of residual check-phase work. These are optimistic scheduling models, **not
measured parallel compiler times**. They preserve current per-module costs and
ignore scheduler overhead, cache contention, extra copies, symbol isolation,
ordered budget accounting and publication. Import/prelude dependencies define
the modeled graph; shared mutable compiler state still prevents its execution.
The CPU-weighted model also excludes time lost to descheduling within a module.

The conclusion is narrower than “parallelism cannot get below a second”:
parallelizing the current whole-module jobs alone cannot do so under this cost
model. Smaller jobs, less work on the critical chain, or faster later frontend
phases can change that limit.

Ordinary edits need a different lever. The literal and body edits each check
only `robots.blot`: checking takes 70/73 ms, and the complete frontend takes
133/139 ms. There is no useful module-level parallelism in those observations;
the multi-second edit latency remains mostly downstream.

## Recommended experiments, in order

### 1. Stop repeatedly rebuilding generic state along the builder chain

Measure scheme construction by declaration and rebinding, with distinct
requirements, rescans, variable-set lengths and graph nodes created. Use the
real `game.blot` composition plus a public small/medium/large builder-chain
fixture to establish scaling before selecting an algorithm.

Then keep each pending requirement and its dependency frontier once, indexed by
owner/scope, and update it when its actual dependencies change. The current
reconstruction of candidate variable sets is the first target. Where a pure
intermediate has one use, investigate delayed scheme construction or a direct
constraint connection to that use. This must preserve independent polymorphic
uses, escaping values, higher-rank expectations, effect rows, chronological
substitution views and error order. Do not make all rebindings monomorphic.

The first experiment can preserve existing syntax and inference behavior. If a
restricted builder interface or new annotation becomes necessary, consult the
user before changing language syntax or the rules accepted by existing code.

### 2. Make module jobs independent, then schedule roughly four workers

The existing checker already owns private solver state for each module. Move the
remaining coordination out of those jobs:

- Discover qualified names and fixed descriptor field names before concurrent
  checking, then give workers a frozen symbol dictionary. There are four direct
  `pool.intern` sites in `check.zig`: two form qualified names and two intern
  `result`/`effects`. Audit transitive helpers as well. If complete discovery
  cannot be proved, retain a private overlay and deterministic relocation.
- Return owned diagnostics, counters and immutable checked interfaces. Publish
  in the existing dependency/source order, regardless of completion order.
- Preserve project-wide resolution and associated-inference budgets. Private
  charging plus ordered accounting and a serial exhaustion fallback is one
  design to test; giving each worker an independent full project budget is not.
- Use private allocator arenas and explicit immutable producer leases. Avoid
  holding a shared solver or symbol lock around the hot checking operation.

A ready-task queue can begin a consumer when its actual dependencies finish;
level-wide barriers can unnecessarily wait for an unrelated slow sibling. The
new model uses ready tasks. The older CT44 study already identified these
shared-state barriers; the new costs update that study for today's program.

The immutable-result boundary is consistent with the design described in
[Rust's parallel-query documentation](https://rustc-dev-guide.rust-lang.org/parallel-rustc.html#query-system).
That page warns that its implementation-status discussion is dated; the design
principle is the relevant comparison, not Rust's current default thread policy.

### 3. Shorten dependency chains with complete interfaces and smaller jobs

Whole-module jobs force consumers to wait for every producer body. Publish a
complete semantic interface separately from its body proof where the language
permits that distinction. Independent declaration bodies can then become jobs,
with recursive groups remaining together. Inferred interfaces still depend on
their producing bodies; a written return type alone does not necessarily close
effects, associated requirements or compile-time values.

This is also the boundary needed to avoid repeated backend inference and improve
ordinary edits. It is a larger architecture change than adding worker threads.
The existing optional interface/result requirements are building blocks, not
proof that every function is ready for separate compilation.

### 4. Instantiate from immutable imports without the intermediate copy

Header checking still costs 325 ms of CPU across modules. The existing
`SchemeInterface`, `Callees` and `F.Source` readers can support direct
producer-to-use instantiation instead of first copying a complete scheme into
each consumer solver. Publish portable public-slot membership once, then create
only each use's private quantified variables and required constraints.

This removes work and makes worker sharing cheaper. It is secondary to the
identified builder bottleneck for shortening the critical path: only 17.5 ms of
`game.blot`'s 447.3 ms is header checking. Imports that are not directly read
may still support coherence, shared callees and publication.

### 5. Make set operations cheaper before adding SIMD

The checker uses repeated linear `inList` membership checks during
generalization. For large accumulated variable sets, compare compact local ID
numbering plus generation-stamped membership or sparse bitsets. Batch
intersection/union over bitset words is a plausible SIMD target after that
representation exists. Preserve ordered lists where order affects diagnostics;
membership indexes need not replace the ordered result.

The averages warn against vectorizing every candidate: the final CT114 census
has only 0.166 type IDs and 0.897 row IDs per selected candidate. Distribution
tails and the large enclosing sets matter. Measure those lengths and the time in
membership before choosing a vector width or allocating bitsets per candidate.
The current type graph already uses dense 16-byte nodes; replacing “object
pointers” is not an accurate description of the remaining work.

Type resolution and effect-row discovery follow tags, substitution histories,
cursors and dependent graph edges. These irregular operations are poor first
targets for lane-wise execution. Removing a traversal can be much more useful
than comparing several IDs per instruction inside it.

### 6. Keep SIMD lexing and wider CPU targets as smaller experiments

CT114's paired profile has 25.6 ms lexing and 15.4 ms parsing. Even eliminating
lexing entirely saves only about 1.4% of its 1.784 s frontend; a hypothetical
fourfold lexer speedup saves about 19 ms. Loading is also already small.

SIMD byte classification, UTF-8 checks and structural scans are valid
techniques;
[simdjson's staged parser](https://simdjson.github.io/simdjson/md_doc_2parse__many.html)
illustrates separating structural indexing from later interpretation. That is a
design comparison, not a transferable Blot speedup. Bulk immutable-table
validation is another potential vector target, but semantic/capability
validation cannot be replaced with bounds checks alone.

The host reports a Ryzen 7 7800X3D, 16 logical CPUs, AVX2 and AVX-512 features;
the compiler build defaults to a baseline CPU target. A separate native-target
build is a reasonable later A/B experiment, with exact output controls and a
portable baseline retained. Instruction availability is not a measured gain. No
hardware counters were collected here, so no cache-miss or memory-bandwidth
bottleneck is claimed.

## What would make sub-second plausible

With four modeled workers, halving only `game.blot` body checking brings the
frontend estimate to 1.024 s. Quartering that body cost gives 0.917 s; halving
both that body cost and all header costs gives 0.967 s. These are hypothetical
cost reductions used to set targets, not predictions or completed improvements.
Their small margin also leaves room for real scheduling overhead to miss the
target. The useful combination is less inference work on the critical path and
parallel independent work.

## Evidence and limitations

The diagnostic compiler is frozen qualified CT114 plus three observational
source changes. It was built with Safe/noLLVM first and LLVM ReleaseFast for the
three fresh CPU traces and four edit/revert traces. All seven outputs match
strict CT103 Wasm pins, and workload and compiler hashes agree before and after.
No competing local build/test ran alongside those release traces.

Dependency freezing renumbers numeric module IDs before checking the entry. The
first trace therefore has two different files labeled unit 189. A separate
Safe/noLLVM topology probe records stable filename keys, with truncation and
collision checks. Analysis joins those edges to the release clocks by exact
filename, verifies all 189 names and topological order, and checks identical
per-module semantic work counters across both build modes. The Safe clocks are
not used as release costs. This probe also passes the strict Wasm/input checks.

The scheduling audit verifies complete job execution, dependency readiness,
worker capacity, the single-worker total and the unlimited-worker critical path
for all twelve CPU/wall schedules. The production compiler is unchanged, so the
CT114 qualification remains the applicable correctness result; this
investigation does not qualify a parallel implementation. CT110 remains
installed. Raw traces, source pins, patches and reproduction scripts are under
`build/bench/ct115`.

The
[portable evidence archive](zig-native/measurements/ct115-big-levers-2026-10-25.tar.gz)
contains 42 files (753,046 bytes), including release and topology source pins,
exact patches, raw profiles, workload/output hashes, build logs, the scheduling
analysis and its audit. SHA-256:
`692f68a3abb195d3a60cdf474e74feea046901a7bf92487cd7cd0e43d0aa8a8d`. It excludes
compiler binaries, build caches and the private workload sources. After
extraction, run `python3 ct115/analyze.py` to reproduce the model from the
preserved traces. Rebuilding or remeasuring also requires the pinned CT114
source and workload. Release and Safe topology source snapshots are separate;
their clocks must not be combined as if they were the same executable.
