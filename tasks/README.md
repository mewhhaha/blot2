# Finish the compiler, runtime and language program

This directory turns the approved scope into 84 implementation, design and
qualification tasks, followed by the conditional cleanup task 999. Creating
these planning files does not execute or complete their work.
[PLAN.md](../PLAN.md) remains available until task [999]. The full scope
includes the unfinished twenty hills, earlier semantic compilation and runtime
ownership programs, collections,
[language evolution](../zig-native/LANGUAGE_EVOLUTION.md), and
[demand evaluation](../zig-native/DEMANDS.md).

## Starting revision and qualified baseline

The starting revision is `632b461` (`632b461000d93dbc1bdf8f9cae520f54e1419011`)
on local `main`. The tracked worktree was clean when this task directory was
prepared; the List span work described below remains in ignored paths.

The already qualified baseline is the native suite, **589 guest/client tests**
and **zero analyzer findings**. These are prior qualification results recorded
in [STATUS.md](../zig-native/STATUS.md) and [PLAN.md](../PLAN.md), not new test
runs performed for this documentation change.

| Measurement                              |            Qualified starting value |
| ---------------------------------------- | ----------------------------------: |
| Fresh gdev CPU                           |                Approximately 647 ms |
| Retained population CPU                  |                Approximately 740 ms |
| First retained literal edit CPU          |                Approximately 150 ms |
| Subsequent edit/revert CPU               |                Approximately 140 ms |
| No-op CPU                                | Below process-accounting resolution |
| Cumulative requested compiler allocation |                            321.2 MB |
| Peak requested live compiler memory      |                             78.9 MB |
| Live requested memory after teardown     |                                   0 |
| Inference regions                        |                               2,036 |
| Largest region by scope count            |                        8,041 scopes |
| Solver constraint visits                 |                              35,215 |
| Occurs-check visits                      |                              42,410 |
| Wasm size                                |                       629,339 bytes |

These measurements use seven alternating pairs on the frozen private
394,294-byte gdev workload. CPU is child user plus system time, fresh
compilation disables persistence, and machine load/filesystem caches were
uncontrolled. Against the previous variable-cache compiler, fresh CPU was
644/647 ms, population 740/740 ms, first edit 160/150 ms and subsequent edit
140/140 ms. Wasm, allocation and deterministic work counters matched; no compile
speedup was claimed. Raw samples and binary hashes are in ignored
`build/bench/demand-forwarding-qualified`.

## Completed foundations to preserve

These are regression baselines, not new implementation tasks. Historical
measurement batches are not interchangeable with the qualified starting batch.

| Existing milestone                                                               | Evidence or continuing obligation                                                                                                   |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Hill 1 first-order/predicate-free schemes and hill 2 predicate-free callbacks    | Iterative summary queue and checked scheme admission; general cases remain in [003]–[007].                                          |
| Hill 3 inference call-depth cliff removed                                        | Annotated chains at 300/1,000, generic chain at 300 and diamond N=16; executed evaluation limits remain separate.                   |
| Hill 4 frozen capture proofs                                                     | Complete fixed-point capture proofs already reuse; canonical keys remain [008].                                                     |
| Hill 5 occurs DAG, immutable row views and variable certificates                 | Chronological windows, rollback, physical edits and saturation remain regression laws; composite caching/worklists are [009]–[010]. |
| Hill 7 pooled region arenas                                                      | Separate nested leases, durable publication and 64 MiB retained raw-storage cap; cumulative allocation target remains open.         |
| Hill 8 automatic restart cache                                                   | Identity-checked bounded candidates, atomic persistence, corrupt/unavailable fallback and explicit checkpoints.                     |
| Hill 10 measurement/profile/budget harness (`ae14677`)                           | Preserve phase separation, work counters and deep/fan-out regression budgets.                                                       |
| Hills 11 and 13 one production policy and prototype cleanup                      | Preserve session-owned policy; do not revive discarded experiments solely because journals mention them.                            |
| Hill 15 complete test-filter discovery                                           | Keep full comptime test imports; layout and fixture work remains [079]–[080].                                                       |
| Hill 16 shared equality/hash and diagnostics; local hill 17 analyzer (`4dd0a0e`) | Exact equality follows hash selection; zero local findings remains mandatory; remote qualification remains [082].                   |
| Hill 18 approved disk cleanup                                                    | Already reduced build artifacts from roughly 37 to 4.5 GB; only the remaining inventory is [083].                                   |
| Hill 19 current docs and most hill 20 leftovers                                  | Update durable docs as work lands; remaining fixtures and artifacts have explicit tasks.                                            |
| Typed holes, aliases and named contracts                                         | Owned bounded diagnostics, imported polymorphic rows and predicate bundles stay valid.                                              |
| Language direction 6 extensible records and typed paths                          | Stable layouts, merge/type-changing updates, callback captures, effect order, dependencies and checkpoints already pass.            |
| Language direction 11 external assets                                            | Typed host parser boundary, JSON/shader adapters, immutable snapshots, tracked reads and recovery already pass.                     |
| Demand spelling, bounded lowering and local forwarding                           | Both `@demand`/`@force`, the 96-node proof budget, per-creation sharing and pinned completion semantics remain compatible.          |

## Completion rules

Execute ready tasks in numeric order by default. **Ready** means no unfinished
dependencies; **Pending** means dependency completion is still required. Track
**In progress** when work starts and **Complete** only after every acceptance
criterion passes. An external gate may be recorded as **Awaiting external
evidence**, with the missing evidence stated explicitly. Update both the task
and index together. All tasks begin open; prior results in a starting-point
section are not task completion.

Design tasks settle syntax/APIs, semantics, representations, diagnostics,
compatibility and acceptance examples in durable documentation under
`zig-native/` and the relevant public guides. Finishing a design does not finish
its implementation tasks. A prototype, restricted admission rule or successful
subset cannot close a broader requirement. A rejected prototype in [001] may
close that experiment's decision while [002] remains responsible for the full
traversal regression.

Each task owns one bounded reviewable result. If new required work is
discovered, add a numbered task before 999, update this index, coverage and
dependency graph, and link it from the originating task. Do not silently reduce
scope. Task [075] follows all 001–074; task [999] follows every required task,
including additions. External evidence in [082] and the owner decision in [083]
must actually exist before those tasks or final cleanup are complete.

Keep local milestone commits on `main`; **nothing is pushed without
authorization**. Stage only the intended changes and preserve unrelated or
ignored work. File or comment on upstream issues only with explicit approval, as
required by [AGENTS.md](../AGENTS.md). This plan does not authorize a push to
obtain a remote workflow run. The owner review for unapproved artifact deletions
comes directly from [PLAN.md](../PLAN.md), hill 20 remainder.

Fill completion evidence with the local commit, exact commands/results,
baseline/candidate identities, paired measurements and remaining limitations.
Put essential decisions and qualification evidence outside this directory before
[999]; local raw logs alone do not preserve the public reasoning.

## Shared validation

Read [the language guide](../compiler/guide.md) and
[ownership contract](../zig-native/CONTRACT.md), plus applicable instructions,
before implementation. Blot has one handwritten compiler; Deno hosts its client,
formatter and Wasm guest API. No optimization may recognize prelude, library,
JSON, shader, ECS or framework declaration names.

Check `zig version` before **each** build batch and use **Zig 0.17.0**. Select
the documented development or release build as appropriate:

```sh
zig version
deno task build:compiler:dev
```

```sh
zig version
deno task build:compiler
```

Use focused native tests during development from `zig-native/`:

```sh
zig build test -Doptimize=safe -Dtest-filter="test name"
```

Verify that the selected filter actually ran matching tests. Focused guest tests
can use the existing harness, replacing FILE with the relevant suite:

```sh
deno test --allow-read --allow-write --allow-run --allow-env=BLOT_CLIENT_TEST_AMBIENT zig-native/tests/FILE.test.ts -- zig-native/zig-out/bin/blotc
```

Before committing compiler changes, run from the repository root:

```sh
zig version
deno task test:compiler
deno task lint:zig
```

The full compiler gate includes native semantic laws and executed-Wasm/client
coverage. The analyzer must report zero findings in the production source tree;
use `$ZIG_ANALYZER` or `../zig-analyzer/zig-out/bin/zig-analyzer`. Preserve that
coverage after source relocation.

- Ownership/publication changes require allocation-failure sweeps and immutable
  input checks. Scratch variables and borrows must not escape their owners;
  publication is atomic and failed work releases every candidate allocation.
- Reuse changes require fresh/retained comparisons, dependency/checkpoint round
  trips, repeated revisions, failed edits followed by correction, and restart
  checks where applicable. Preserve the last successful revision.
- Effect/suspension changes require both synchronous and JSPI scenarios,
  including request cancellation, resumption, traps and host exceptions.
- Preserve diagnostic order, chronological substitutions, staging,
  nominal/provider identity, capture snapshots and once-per-creation demand
  sharing. Keep unused source checked even when its evaluation is skipped.
- Record intentional generated-code changes. Preserve byte equality between
  fresh and retained builds of the same compiler. For old/new compilers, retain
  byte equality where expected and explain legitimate code-generation changes
  with execution/structural evidence. Do not disable existing differential
  checks to obtain a pass, and do not patch generated output to fix behavior.
- Language/tooling changes also run `deno task check:editor`,
  `deno task test:editor`, affected formatter/client tests and
  `deno task package:check` where relevant. Packaging is a dry run, not a
  request to publish.
- Documentation-only tasks use `deno fmt --check` on changed Markdown plus link,
  dependency and consistency checks. Do not rerun compiler suites solely for
  reversible documentation edits. Write tests for meaningful semantic laws, not
  tests that merely mirror a low-impact edit. Once applicable checks pass,
  repeat them only after a relevant change or unresolved concern.

## Shared benchmarking

Pin executable and library revisions/hashes, workload manifests, compiler
options and machine conditions. Keep private gdev source out of commits. Verify
`build/bench/gdev-snapshot` against
[the manifest](../scripts/bench/gdev-manifest.json). Missing private data means
the gdev gate is unmeasured, even if synthetic probes pass.

```sh
deno task bench:compile --baseline OLD_BLOTC --candidate NEW_BLOTC --runs 7
```

Use `--restart-cache` for isolated cache population/restart measurements; the
ordinary harness disables persistence. Use `blotc build ... --profile` to
inspect phase and slowest-region timings, and preserve/tighten
[compile budgets](../zig-native/tests/compile_budget.test.ts) when work falls.

Measure fresh compilation, dependency population, first edit, subsequent edit,
no-op, restart where applicable, and failed-edit recovery separately. Do not
average them together. Use alternating paired samples and report distributions,
CPU, wall time and deterministic work; ananicy can demote Deno/children to
SCHED_IDLE, so wall time alone cannot establish a compiler win. Parallel default
qualification specifically needs an idle machine and improvement in both CPU and
wall time.

Compiler cumulative requested allocation, peak live requested memory, process
RSS, guest allocation and committed guest memory are different measurements.
Report guest runtime/memory separately. Compiler-identity-dependent dependency
files must be generated separately for each compiler.

Use [bench_packed_rows.ts](../scripts/bench_packed_rows.ts),
[bench_iterators.ts](../scripts/bench_iterators.ts),
[bench_stdlib.ts](../scripts/bench_stdlib.ts) and
[bench_runtime_costs.ts](../scripts/bench_runtime_costs.ts) for relevant runtime
work, with their documented arguments and matching libraries. Preserve the
pre-packed boxed baseline as well as the current packed baseline. A fixture win
does not demonstrate an application-wide gain.

## List span continuation

The ignored prototype checkout is `build/experiments/list-span-source/`. Its
tracked-source differences from the starting revision are in
`zig-native/src/core_backend.zig` and `zig-native/src/collection_tests.zig`; it
also adds `zig-native/tests/list_span_execution.test.ts`.

- `Emitter.readListRow` receives an optional `span_end`; direct loops pass the
  resolved leaf end and can use a row-end comparison. Other paths retain their
  ordinary cache checks. Cross-leaf fallback remains necessary.
- The native test is named
  `packed List span emission preserves immutable Core
  under allocation failure`.
  Its corrected source uses explicit `@u32.add` intrinsics rather than depending
  on an implicit prelude. It runs the emission allocation-failure sweep and
  compares the Core stamp.
- The execution test covers widths 1–16, counts around `248 / width`, nested
  traversal, slices, prepend/append and saved versions. It is present, but its
  presence is not a passing execution result.
- The supplied continuation records a **successful experimental release** and
  the **corrected native allocation-failure test** as prior work. Task [001]
  must capture their provenance and remaining gate results; this documentation
  change does not rerun or independently certify them.
- The observed candidate executable is
  `build/experiments/list-span-source/zig-native/zig-out/bin/blotc`, SHA-256
  `fb34ef7acf8575feeeb60d03e5b99f5cab3dc5cfb4a3de203c1b583ad0113cf1`. The saved
  comparison executable is `build/bench/list-span-baseline/blotc`, SHA-256
  `4abce406794c6ce6f6a9cad5e206bc981677205ade5a4b2d8111128d8ac0f1e3`, with
  `compiler-identity.bin` beside it. Verify source/build provenance before using
  either as a qualified measurement baseline.
- `build/bench/list-span-v1-runtime/retained_array_rows.blot` exists as a probe;
  it does not establish completed runtime measurements. Remaining work includes
  execution, analyzer, differential comparison and paired runtime/compiler
  measurements, then a merge-or-reject decision.
- The prototype `.zig-cache` is a symlink to
  `build/experiments/arenas-zig-cache`. Preserve it and the checkout while
  qualifying the work. Keep the older boxed traversal baseline separate; the
  saved packed comparison alone cannot close the 1.9× regression.

## Task index

Dependency numbers below link to their task files. All tasks are initially open.

| Task                                                    | Status      | Dependencies                           |
| ------------------------------------------------------- | ----------- | -------------------------------------- |
| [001] — Qualify list span prototype                     | Complete    | None                                   |
| [002] — Close packed list traversal regression          | In progress | [001]                                  |
| [003] — Specify general call summaries                  | Complete    | None                                   |
| [004] — Summarize predicate bearing callees             | Ready       | [003]                                  |
| [005] — Summarize higher order callees                  | Pending     | [004]                                  |
| [006] — Summarize lexical closures                      | Pending     | [005]                                  |
| [007] — Infer recursive components jointly              | Pending     | [006]                                  |
| [008] — Canonicalize specialization keys                | Pending     | [007]                                  |
| [009] — Cache composite type resolutions                | Ready       | None                                   |
| [010] — Schedule constraints by variable                | Pending     | [009]                                  |
| [011] — Reduce semantic allocation traffic              | Pending     | [007], [008], [010]                    |
| [012] — Schedule independent semantic jobs              | Pending     | [007], [008], [010]                    |
| [013] — Qualify parallel inference                      | Pending     | [011], [012]                           |
| [014] — Specify unified query table                     | Pending     | [008]                                  |
| [015] — Migrate refinement queries                      | Pending     | [014]                                  |
| [016] — Migrate specialization and principal queries    | Pending     | [015]                                  |
| [017] — Unify source and revision validation            | Pending     | [016]                                  |
| [018] — Migrate executable reuse queries                | Pending     | [017]                                  |
| [019] — Serialize the query table                       | Pending     | [018]                                  |
| [020] — Persist complete semantic artifacts             | Pending     | [019]                                  |
| [021] — Publish transactional revision deltas           | Pending     | [017], [020]                           |
| [022] — Retain constants and relocatable data           | Pending     | [020], [021]                           |
| [023] — Narrow literal edit invalidation                | Pending     | [022]                                  |
| [024] — Apply general body interface cutoff             | Pending     | [023]                                  |
| [025] — Resolve calls before emission                   | Pending     | [008], [020]                           |
| [026] — Resolve structured control flow                 | Pending     | [025]                                  |
| [027] — Represent ownership in resolved ir              | Pending     | [026]                                  |
| [028] — Make emission consume resolved bodies           | Pending     | [027]                                  |
| [029] — Remove function indices from reuse keys         | Pending     | [018], [028]                           |
| [030] — Specify shared and cyclic ownership             | Pending     | [027]                                  |
| [031] — Implement shared reference counting             | Pending     | [030]                                  |
| [032] — Own escaping values and persistent roots        | Pending     | [031]                                  |
| [033] — Own suspended effects and cancellation          | Pending     | [032]                                  |
| [034] — Reclaim cyclic ownership                        | Pending     | [033]                                  |
| [035] — Remove the tracing runtime                      | Pending     | [034]                                  |
| [036] — Summarize demand control flow                   | Pending     | [007], [014]                           |
| [037] — Lower loop aware local memos                    | Pending     | [036]                                  |
| [038] — Eliminate demands through known callbacks       | Pending     | [037], [032]                           |
| [039] — Guarantee and explain demand lowering           | Pending     | [038], [033]                           |
| [040] — Fuse packed row producers and consumers         | Pending     | [002], [027]                           |
| [041] — Broaden numeric simd                            | Pending     | [040]                                  |
| [042] — Specify ragged builders                         | Pending     | [011], [027]                           |
| [043] — Implement ragged builders                       | Pending     | [042]                                  |
| [044] — Specify rolling and summary operations          | Pending     | [040]                                  |
| [045] — Implement rolling reductions                    | Pending     | [044]                                  |
| [046] — Implement composable summary trees              | Pending     | [045]                                  |
| [047] — Eliminate generic iterator state                | Pending     | [040], [027]                           |
| [048] — Explain dispatch and evidence                   | Pending     | [004], [005]                           |
| [049] — Specify editor completion                       | Pending     | [048]                                  |
| [050] — Implement editor completion                     | Pending     | [049]                                  |
| [051] — Specify module abstraction                      | Pending     | [020]                                  |
| [052] — Implement opaque types and privacy              | Pending     | [051]                                  |
| [053] — Qualify module cutoffs and wrapper erasure      | Pending     | [052], [024]                           |
| [054] — Specify associated types and implementations    | Pending     | [052]                                  |
| [055] — Implement associated type members               | Pending     | [054]                                  |
| [056] — Implement declarations and evidence diagnostics | Pending     | [055]                                  |
| [057] — Specify scoped effect identities                | Pending     | [052]                                  |
| [058] — Implement effect instances and subtraction      | Pending     | [057]                                  |
| [059] — Reject escaping capabilities                    | Pending     | [058]                                  |
| [060] — Specify usage and lifetime contracts            | Pending     | [059], [030]                           |
| [061] — Check usage and call multiplicity               | Pending     | [060]                                  |
| [062] — Implement resource cleanup contracts            | Pending     | [061], [033], [020]                    |
| [063] — Specify polymorphic packages                    | Pending     | [056], [059]                           |
| [064] — Check higher rank types and skolems             | Pending     | [063]                                  |
| [065] — Implement existential packages                  | Pending     | [064], [020]                           |
| [066] — Specify typed staging                           | Pending     | [053], [065]                           |
| [067] — Implement typed code and descriptors            | Pending     | [066]                                  |
| [068] — Implement hygienic generation and reuse         | Pending     | [067], [024]                           |
| [069] — Specify bounded erased proofs                   | Pending     | [056]                                  |
| [070] — Implement numeric and index witnesses           | Pending     | [069]                                  |
| [071] — Eliminate checks from proved branch facts       | Pending     | [070], [026]                           |
| [072] — Specify structured concurrency                  | Pending     | [059], [062]                           |
| [073] — Implement scoped tasks and cancellation         | Pending     | [072], [035]                           |
| [074] — Implement disjoint access and host execution    | Pending     | [073], [071]                           |
| [075] — Split evaluator state and dispatch              | Pending     | All [001]–[074]                        |
| [076] — Split core module and builder                   | Pending     | [075]                                  |
| [077] — Split checker responsibilities                  | Pending     | [076]                                  |
| [078] — Split backend state and emission                | Pending     | [077]                                  |
| [079] — Relocate fixtures through a test module         | Pending     | [078]                                  |
| [080] — Organize the source tree                        | Pending     | [079]                                  |
| [081] — Finalize durable documentation                  | Pending     | [080]                                  |
| [082] — Qualify the remote analyzer workflow            | Pending     | [081]                                  |
| [083] — Review and clean old build artifacts            | Pending     | [081]                                  |
| [084] — Qualify the complete program                    | Pending     | [082], [083]                           |
| [999] — Remove tasks and plan                           | Pending     | All [001]–[084], plus every added task |

## Coverage matrix

All open requirements are mapped below. Completed language directions 6 and 11
and completed hill portions stay in the baseline table; their regression
obligations remain part of applicable tasks and final qualification.

| Originating requirement                                                                                       | Tasks                                                  |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| PLAN hill 1: general predicate-bearing checked summaries and fallback diagnostics                             | [003], [004]                                           |
| PLAN hill 2: parametric callback obligations, lexical captures and joint recursive regions                    | [003], [005], [006], [007]                             |
| PLAN hill 4: canonical body/evidence keys including captures and value-dependent inputs                       | [008]                                                  |
| PLAN hill 5: composite resolution across unrelated writes, history, rollback and physical edits               | [009]                                                  |
| PLAN hill 5: variable-indexed constraints and alias fixed-point worklists                                     | [010]                                                  |
| PLAN hill 6: changed-only metadata, retained constants, literal invalidation and body/interface cutoff        | [020], [021], [022], [023], [024]                      |
| PLAN hill 7: semantic graph sharing and under-100-MB cumulative requested allocation                          | [011], [084]                                           |
| PLAN hill 9: isolated workers, deterministic publication and CPU/wall-qualified default                       | [012], [013]                                           |
| PLAN hill 12: typed query design, dependency recording and exact fingerprints/early cutoff                    | [014]                                                  |
| PLAN hill 12: refinement, specialization and principal migration                                              | [015], [016]                                           |
| PLAN hill 12: shared source/revision validation, executable reuse and archive serialization                   | [017], [018], [019]                                    |
| PLAN hill 14: evaluator, Core, checker and backend responsibilities; approximately 120-line functions         | [075], [076], [077], [078]                             |
| PLAN hill 15 and hill 20 fixtures: dedicated test module, full filtered discovery, source layout              | [079], [080]                                           |
| PLAN hill 17: successful authorized remote analyzer workflow on relevant code                                 | [082]                                                  |
| PLAN hill 19: current durable guide, architecture, contracts, status and library guidance                     | [081]                                                  |
| PLAN hill 20: owner decision and cleanup of unapproved old artifacts                                          | [083]                                                  |
| Earlier semantic compilation: portable complete semantic artifacts and their dependencies                     | [019], [020]                                           |
| Earlier semantic compilation: transactional revision deltas without metadata rebuilds                         | [021]                                                  |
| Earlier semantic compilation: resolved calls, control flow, ownership and emission boundary                   | [025], [026], [027], [028]                             |
| Earlier semantic compilation: optimized-body reuse independent of incidental function indices                 | [029]                                                  |
| Earlier runtime ownership: shared RC, destruction and explicit root ownership                                 | [030], [031], [032]                                    |
| Earlier runtime ownership: escaping values, persistent roots and suspended effects                            | [032], [033]                                           |
| Earlier runtime ownership: legal State → closure → cached-demand cycles with strong memo results              | [030], [034]                                           |
| Earlier runtime ownership: qualified tracing removal and long-running memory/performance                      | [035], [084]                                           |
| Collections: unfinished List span qualification and boxed-baseline fold/cursor regression                     | [001], [002]                                           |
| Collections: broader typed row fusion and numeric SIMD                                                        | [040], [041]                                           |
| Collections: legal ragged sizing/counting and direct construction                                             | [042], [043]                                           |
| Collections: rolling API/algebra and bounded reductions                                                       | [044], [045]                                           |
| Collections: composable summaries, queries and persistent updates                                             | [044], [046]                                           |
| Collections: generic iterator step/cursor elimination and effect/pull-order preservation                      | [047]                                                  |
| Collections: distinct List/Array types, no public List indexing, snapshots and fallback representations       | [001], [002], [040], [041], [043], [045], [046], [047] |
| Language 1: dispatch/selected evidence explanations beyond existing typed holes                               | [048]                                                  |
| Language 1: editor completion API, overlays, cancellation, ranking and actual integration                     | [049], [050]                                           |
| Language 2: opaque types, construction access, exports/re-exports and representation privacy                  | [051], [052]                                           |
| Language 2: nominal identity, separate compilation, private cutoff and zero-cost wrappers                     | [051], [052], [053]                                    |
| Language 3: associated member design, checking, substitution and projection                                   | [054], [055]                                           |
| Language 3: implementation declarations, coherence and richer evidence diagnostics                            | [054], [056]                                           |
| Language 4: symbolic operation arguments, same-typed instances, generativity and handler subtraction          | [057], [058]                                           |
| Language 4: capability capture/identity transport and escaping-capability rejection                           | [057], [058], [059]                                    |
| Language 5: unique/shared, borrowed, once/many syntax and usage/multiplicity checking                         | [060], [061]                                           |
| Language 5: resource cleanup and sound contracts across separate compilation                                  | [060], [062]                                           |
| Language 7: higher-rank annotations, bounded checking and skolem-escape rejection                             | [063], [064]                                           |
| Language 7: existential evidence, specialization and heterogeneous portable packages                          | [063], [065]                                           |
| Language 8: typed code values/descriptors and stage boundaries through one frontend                           | [066], [067]                                           |
| Language 8: hygienic generation, exact staged dependencies and retained/recovery behavior                     | [066], [068]                                           |
| Language 9: bounded numeric/index witnesses, proof scope and conservative fallback                            | [069], [070]                                           |
| Language 9: branch facts, check elimination, erasure and required traps                                       | [069], [071]                                           |
| Language 10: scoped task design, joining, defined cancellation and ownership/capability transfer              | [072], [073]                                           |
| Language 10: disjoint-access proofs, host execution, failures and permitted nondeterminism                    | [072], [074]                                           |
| Demand plan: retained versioned summaries, dynamic counts, aliases, escapes and bounded recursive analysis    | [036]                                                  |
| Demand plan: creation-scoped branch/loop memos, zero iterations and cancellation                              | [037]                                                  |
| Demand plan: known callbacks and provably local captured demands; escaping/unknown shared storage             | [032], [038]                                           |
| Demand guarantee: Boolean-shaped lowering via aliases/custom fixities/imports/bundles in debug/release        | [039]                                                  |
| Demand tooling/cost: bounded source-span reasons, structural counters, long chains and retained edits         | [036], [039]                                           |
| Demand acceptance: skipped/taken branches, custom equivalents and unused ill-typed arguments                  | [036], [039]                                           |
| Demand acceptance: repeated/conditional reads, outside/inside loops and per-creation sharing                  | [037], [038], [039]                                    |
| Demand acceptance: rebinding/collection snapshots, aliases and first-demand providers                         | [032], [037], [038], [039]                             |
| Demand acceptance: persistent arrays/closures and roots across guest calls                                    | [032], [033], [038], [039]                             |
| Demand acceptance: request yield/return/break, cancellation retry, trap/host exception and recursive force    | [033], [037], [039]                                    |
| Demand reuse: body changes with unchanged types, exact captures/effects, failed revisions and recovery        | [018], [024], [036], [039]                             |
| Shared gates: no name recognition; chronological semantics, diagnostic order and immutable atomic publication | [084]                                                  |
| Final performance: cold ~500 ms; literal <30 ms; body <100 ms; largest region <50 ms; allocation <100 MB      | [084]                                                  |
| Final qualification: every semantic/runtime/language/tooling and external gate, follow-ups before cleanup     | [082], [083], [084]                                    |
| Final cleanup: durable evidence, all required tasks complete, remove tasks and PLAN, local commit             | [999]                                                  |

## Final qualification gates

Task [084] must establish every condition below. These are requirements, not
forecast measurements. A missed target remains unfinished and requires bounded
follow-up work before [999].

| Requirement                   | Completion condition                                                                                 |
| ----------------------------- | ---------------------------------------------------------------------------------------------------- |
| Cold compilation              | Approximately 500 ms gdev CPU, supported by paired measurements                                      |
| Literal edits                 | Under 30 ms                                                                                          |
| General body edits            | Under 100 ms                                                                                         |
| Largest inference region      | Under 50 ms                                                                                          |
| Requested compiler allocation | Under 100 MB cumulative requested allocation, distinct from live memory/RSS                          |
| Specialization sharing        | No duplicate regions for the same complete canonical key                                             |
| Runtime ownership             | Legal cycles and suspended values remain correct; replacement of tracing is qualified                |
| Collections                   | Traversal regression closed; new operations/optimizations pass behavioral and measurement gates      |
| Language and demands          | Every mapped completion gate passes, including separate compilation and recovery                     |
| Tooling and structure         | Analyzer, editor, packaging, source layout, fixture relocation and remote workflow evidence complete |

## Planning-directory validation

For this documentation change, verify exactly 001–084 plus 999, unique numbered
filenames, all seven required sections, concrete unchecked acceptance criteria,
existing relative links/anchors, and exact manifest dependencies forming an
acyclic graph. Check that every task is indexed and every open source
requirement has a coverage row. Format with `deno fmt tasks`, then use
`deno fmt --check tasks` and `git diff --check`. Compiler tests are not required
when only these planning files change. Preserve PLAN and all ignored
experiments.

The index and matrix must stay consistent when statuses or dependencies change.
Task 999 must repeat the completion/evidence audit, include any added tasks and
check remaining references after deletion. It cannot run while any requirement,
external gate or durable-documentation obligation remains open.

[001]: 001-qualify-list-span-prototype.md
[002]: 002-close-packed-list-traversal-regression.md
[003]: 003-specify-general-call-summaries.md
[004]: 004-summarize-predicate-bearing-callees.md
[005]: 005-summarize-higher-order-callees.md
[006]: 006-summarize-lexical-closures.md
[007]: 007-infer-recursive-components-jointly.md
[008]: 008-canonicalize-specialization-keys.md
[009]: 009-cache-composite-type-resolutions.md
[010]: 010-schedule-constraints-by-variable.md
[011]: 011-reduce-semantic-allocation-traffic.md
[012]: 012-schedule-independent-semantic-jobs.md
[013]: 013-qualify-parallel-inference.md
[014]: 014-specify-unified-query-table.md
[015]: 015-migrate-refinement-queries.md
[016]: 016-migrate-specialization-and-principal-queries.md
[017]: 017-unify-source-and-revision-validation.md
[018]: 018-migrate-executable-reuse-queries.md
[019]: 019-serialize-the-query-table.md
[020]: 020-persist-complete-semantic-artifacts.md
[021]: 021-publish-transactional-revision-deltas.md
[022]: 022-retain-constants-and-relocatable-data.md
[023]: 023-narrow-literal-edit-invalidation.md
[024]: 024-apply-general-body-interface-cutoff.md
[025]: 025-resolve-calls-before-emission.md
[026]: 026-resolve-structured-control-flow.md
[027]: 027-represent-ownership-in-resolved-ir.md
[028]: 028-make-emission-consume-resolved-bodies.md
[029]: 029-remove-function-indices-from-reuse-keys.md
[030]: 030-specify-shared-and-cyclic-ownership.md
[031]: 031-implement-shared-reference-counting.md
[032]: 032-own-escaping-values-and-persistent-roots.md
[033]: 033-own-suspended-effects-and-cancellation.md
[034]: 034-reclaim-cyclic-ownership.md
[035]: 035-remove-the-tracing-runtime.md
[036]: 036-summarize-demand-control-flow.md
[037]: 037-lower-loop-aware-local-memos.md
[038]: 038-eliminate-demands-through-known-callbacks.md
[039]: 039-guarantee-and-explain-demand-lowering.md
[040]: 040-fuse-packed-row-producers-and-consumers.md
[041]: 041-broaden-numeric-simd.md
[042]: 042-specify-ragged-builders.md
[043]: 043-implement-ragged-builders.md
[044]: 044-specify-rolling-and-summary-operations.md
[045]: 045-implement-rolling-reductions.md
[046]: 046-implement-composable-summary-trees.md
[047]: 047-eliminate-generic-iterator-state.md
[048]: 048-explain-dispatch-and-evidence.md
[049]: 049-specify-editor-completion.md
[050]: 050-implement-editor-completion.md
[051]: 051-specify-module-abstraction.md
[052]: 052-implement-opaque-types-and-privacy.md
[053]: 053-qualify-module-cutoffs-and-wrapper-erasure.md
[054]: 054-specify-associated-types-and-implementations.md
[055]: 055-implement-associated-type-members.md
[056]: 056-implement-declarations-and-evidence-diagnostics.md
[057]: 057-specify-scoped-effect-identities.md
[058]: 058-implement-effect-instances-and-subtraction.md
[059]: 059-reject-escaping-capabilities.md
[060]: 060-specify-usage-and-lifetime-contracts.md
[061]: 061-check-usage-and-call-multiplicity.md
[062]: 062-implement-resource-cleanup-contracts.md
[063]: 063-specify-polymorphic-packages.md
[064]: 064-check-higher-rank-types-and-skolems.md
[065]: 065-implement-existential-packages.md
[066]: 066-specify-typed-staging.md
[067]: 067-implement-typed-code-and-descriptors.md
[068]: 068-implement-hygienic-generation-and-reuse.md
[069]: 069-specify-bounded-erased-proofs.md
[070]: 070-implement-numeric-and-index-witnesses.md
[071]: 071-eliminate-checks-from-proved-branch-facts.md
[072]: 072-specify-structured-concurrency.md
[073]: 073-implement-scoped-tasks-and-cancellation.md
[074]: 074-implement-disjoint-access-and-host-execution.md
[075]: 075-split-evaluator-state-and-dispatch.md
[076]: 076-split-core-module-and-builder.md
[077]: 077-split-checker-responsibilities.md
[078]: 078-split-backend-state-and-emission.md
[079]: 079-relocate-fixtures-through-a-test-module.md
[080]: 080-organize-the-source-tree.md
[081]: 081-finalize-durable-documentation.md
[082]: 082-qualify-the-remote-analyzer-workflow.md
[083]: 083-review-and-clean-old-build-artifacts.md
[084]: 084-qualify-the-complete-program.md
[999]: 999-remove-tasks-and-plan.md
