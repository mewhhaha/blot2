# Compiler direction

Blot uses the handwritten Zig 0.17 compiler in `zig-native/` and its retained
project API. The gdev targets are about 500 ms cold compilation and under 100 ms
incremental compilation, with language, effects, staging and guest behavior
preserved. No optimization may recognize prelude declaration names. The previous
version of this file, with every earlier program's measurements, is
`git show be33230:PLAN.md`.

## Twenty-hill program

Approved on 2026-10-08 after a review of checkpoint `be33230`. Paused the same
day. This section records what landed, what waits on a branch, and how to finish
the rest. Each milestone lands as a local commit on `main` after
`deno task test:compiler` and `deno task lint:zig` pass. Nothing is pushed.

| Hill                                  | State                                       |
| ------------------------------------- | ------------------------------------------- |
| 1. Infer generic callees once         | Frontend half on a branch; backend open     |
| 2. Split the `sandbox` region         | Open; depends on 1 and 3                    |
| 3. Remove the call-depth cliff        | Open; same mechanism as 1's backend half    |
| 4. Canonical specialization keys      | Open                                        |
| 5. Solver hot paths                   | Open; counters landed                       |
| 6. Cheap literal and body edits       | Open                                        |
| 7. Region arenas                      | Open                                        |
| 8. Default restart cache              | Open                                        |
| 9. Parallel region inference          | Open; after 1–3                             |
| 10. Benchmarks, profile, budgets      | Done (`ae14677`)                            |
| 11. One production policy             | Done on a branch, gate unfinished           |
| 12. One reuse/query model             | Open; after 11                              |
| 13. Delete or promote prototypes      | Done on a branch, gate unfinished           |
| 14. Split god structs and switches    | Open                                        |
| 15. Source layout and test filter     | Test filter on the policy branch; rest open |
| 16. Shared equality/hash, diagnostics | Done (`4dd0a0e`)                            |
| 17. Zero analyzer warnings in CI      | Done (`4dd0a0e`); first GitHub run pending  |
| 18. Reclaim disk                      | Done locally; `build/` 37 → 4.5 GB          |
| 19. Docs state current numbers        | Open                                        |
| 20. Remove stale leftovers            | Done except the `.blot` fixtures in `src`   |

### Measuring

- Frozen gdev workload: `build/bench/gdev-snapshot` (gitignored). gdev is a
  private repository and blot2 is public, so never commit its sources. Verify
  the snapshot against `scripts/bench/gdev-manifest.json`.
- Paired comparison:
  `deno task bench:compile -- --baseline OLD_BLOTC --candidate NEW_BLOTC`. It
  reports child CPU (not wall time) for fresh processes and retained phases. It
  fails on any Wasm difference.
- Attribution: `blotc build ... --profile` prints phase timings and the slowest
  inference regions. Every build prints deterministic `work_counters`.
- Regression budgets: `zig-native/tests/compile_budget.test.ts` asserts counters
  for the chain, generic chain, diamond and fan-out probes. Its two ignored
  probes (`chain_mono` N=300 and diamond N=16) document the cliffs that hills 1
  and 3 remove. Un-ignore them and tighten the `today` tables whenever a hill
  lowers counters.
- On this machine ananicy demotes `deno` and its children to SCHED_IDLE. Compare
  CPU, never wall time, and use alternating pairs.

Starting point (be33230, cold CLI on the gdev snapshot):

- About 0.85–1.0 s CPU. Phases: check 137 ms, lower 31 ms, emit 672 ms.
- Inference is about 720 ms of emit.
- One principal region (`const sandbox = game …` in `src/main.blot`) has 13,863
  scopes and takes about 420 ms.
- Counters: 1,758 regions; 66,509 scopes; 5,673 closed and 10,897 unresolved
  callee collections; 7,436 memo hits; 3,113 solver passes; 35,725 constraint
  visits; 213,964 occurs steps; 555,661 type nodes; 426 MB requested in 1.4 M
  allocations.
- A literal edit (`floor_half_extent` 60.0 → 61.0 in `src/robots.blot`) takes
  about 228 ms. It re-specializes 210 named functions and 72 closures, and every
  edit reports `rebuilt_seed: true`.

### Next: land the two branches

1. `hills/11-13-policy-prototypes`. This is hills 11 and 13. It is rebased onto
   `ae14677` and ends with a one-line `wip test filter` commit for hill 15.
   - It deletes `scalar_live_patch`, `resolved_scalar_ssa` and
     `transport_source_templates`, plus the 40-odd reuse and project knobs and
     their off paths.
   - `Policy` keeps `codegen_tier`, `share_machine_code`, `codegen_workers`,
     `semantic_workers` and `split_closed_calls`.
   - The diff is −1,781/+370 lines over 39 files.
   - The gate was still running when work stopped.
   - **To finish:**
     - Rebase onto `main` and run `deno task test:compiler` and
       `deno task lint:zig`.
     - Run `bench:compile` against `main`. Wasm must be byte-identical, cold CLI
       CPU must not regress, and retained edits must not regress.
     - Check how fresh/retained differential tests were rewritten. They now
       compare sessions, not knobs.
     - Keep the test-filter commit (it adds `-Dtest-filter` to `build.zig`) and
       document it in AGENTS.md.
     - Merge.
2. `hills/1-frontend-scheme-sharing`. This is the frontend half of hill 1, built
   on `5da0014`.
   - Commit `8696d7e` makes callee schemes shareable by reference in
     `check.zig`. It adds about 580 lines and `check_shared_scheme_tests.zig`.
   - The WIP commit after it sets a temporary differential switch,
     `pub var callee_sharing_threshold`, to 0 and fixes an addition overflow in
     `shareScheme`.
   - **To finish:**
     - Rebase onto `main`. `check.zig` conflicts with the analyzer renames and
       the `work_counters` additions.
     - Run the differential comparison: threshold `maxInt(u32)` against 0 over
       native tests, guest tests, guide examples and the gdev snapshot.
       Diagnostics (code, span, order), Wasm bytes, `constant_steps` and
       `code_instances` must all match.
     - Then delete the mutable global. Sharing is unconditional whenever
       `summary.shareable` holds, because ARCHITECTURE.md forbids mutable global
       switches.
     - Acceptance: diamond N=24 checks in under 20 ms, a generic chain's check
       cost is linear, and budgets are tightened.

### Hills 1 (backend) and 3: summaries instead of unfolding

Root cause: `ClosureRegion.collectCall` (`core_eval.zig`, about line 4432)
creates a scope for every global call. It freshens every callee type and, when
the instantiated call type is not closed at collection time, calls
`collect(scope, body_root)`. Collection precedes solving, so in principal
analysis this is the common case. The only guard is `unresolved_calls`, which
stops active recursion. The call DAG becomes a tree.

The depth cliff is `collect`'s `collect_depth >= options.max_depth` (256). It
raises `error.TypeLimit`, which is reported as `constant_fuel`. Even annotated
callees are collected inside the caller's region: a 255-deep chain of
`fn (x: U32) -> U32` functions fails, and so does an operator-free generic chain
at 300.

1. **Depth-free closed-call partition.**
   - In `partitionCall`/`closedCall` (about lines 4531–4580), replace the nested
     `child.closedCall` with a Session-level queue of (target, expected
     evidence) jobs drained iteratively by the top-level caller.
   - Remove the 32-job `split_active` limit and the inherited `collect_depth`.
   - Admit only callee schemes without obligations or free variables. The parent
     accepts the call by signature and does not collect the body.
   - Make this unconditional once parity holds, and delete `split_closed_calls`.
   - The earlier opt-in prototype accepted 963 gdev boundaries, cut the largest
     region from 13,863 to 10,335 scopes, and kept Wasm identical.
2. **`call_summary` constraint for functional callees.**
   - A callee is functional when its result and effect row are determined by its
     parameter types. Decline for `result_dispatch`, open effect-row
     dependencies, lexical closures that share outer variables (`shareLexical`,
     `definition == null`), closure or callable evidence (use
     `firstOrderArrow`), and SCC members.
   - `collectCall` appends (target, argument types, result) instead of
     collecting the body.
   - `solveMode` (about line 5091) resolves it once the parameter prefix is
     closed, using a Session memo
     `call_summaries[(target, closed input
     evidence)]`.
   - On a miss, push a job onto an explicit heap stack. The job runs the callee
     as its own closed region and publishes through `validated_calls`. Then
     retry. There is no native recursion.
   - Never use the order-sensitive `fallback` pass for summaries.
   - A failed job, or an input that never closes, falls back to inline
     collection, so the authoritative diagnostics stay unchanged.
3. **Limit `max_depth` to executed code.** After 1 and 2, `max_depth` limits
   only executed compile-time evaluation (`expressionInner`), not region
   collection.

Laws:

- Executed-Wasm parity on all tests and on gdev.
- Diagnostic parity, including an ill-typed leaf at depth 300 and a missing
  `add` deep in a summarized callee.
- Fresh/retained parity.
- `.blotdep` and checkpoint round trips.
- Allocation-failure sweeps over the job queue.

Acceptance:

- `chain_mono` at 300 and 1,000 compiles, and so does `gen300`.
- Diamond N=16 emits in milliseconds.
- On gdev, unresolved collections and the maximum region scopes fall.

### Hill 2: the `sandbox` region

`principalEvidence` (about line 1374) uses `include_callables` to pull the
transitive callee graph into one region. After hill 1's backend work, profile
gdev with `--profile`. The remaining scopes come from higher-order combinators
(plugins, ECS queries, iterators).

- Extend summaries to function-typed parameters. A summary stays parametric in
  the obligations of its argument functions.
- Extend summaries to lexical closures by treating captured variables as extra
  public variables.
- Give each SCC one joint region.

Acceptance: no gdev region takes more than 50 ms.

### Hill 4: canonical specialization keys

The same `packages/ecs.blot` body (binding 234, body 80) is inferred in four
regions. `specialized_closures` is keyed by `ViewKey{value, evidence}`, where
`value` is a closure value ID that includes its captures. The refinement memo
and refinement receipts in `core_backend.zig` are keyed per seed.

- Key both by (body, complete evidence including capture evidence).
- Prove that the capture values cannot change the inferred result before
  sharing.

Acceptance: `--profile` shows no duplicate (body, evidence) regions.

### Hill 5: solver hot paths

Measure first with `solver_passes`, `solver_constraint_visits` and
`occurs_steps`.

- `types.zig` `occurs` walks resolved types without a visited set.
- Each `mutation_epoch` bump wipes the whole resolve cache
  (`epoch_resolution_cache.zig`). Rollback also drops `closed_generation`.
- `solveMode` rescans every constraint until nothing changes. `solveDataAliases`
  rescans aliases.

Fixes: a visited bitmap or a cached "variable-free" flag for `occurs`, per-type
resolve caches that survive unrelated writes, and a worklist of constraints
indexed by the variables they watch. Chronological substitution semantics must
hold, so keep diagnostic parity tests next to each change.

### Hill 6: cheap edits

Use the retained profile with `deno task bench:compile` to find which
invalidation forces `rebuilt_seed` on a literal edit.

- Literal-only edits re-evaluate the affected constants and re-emit only data
  segments, functions whose instructions changed, and their callers'
  relocations.
- Body edits recheck one body behind an exact interface cutoff. Its callers
  rebuild only when the summary or scheme changes. This builds on refinement
  receipts and early cutoff.

Targets: a literal edit under 30 ms, and a body edit under 100 ms on gdev.

### Hill 7: region arenas

Cold gdev requests 426 MB in 1.4 M allocations for 394 KB of source. Give each
ClosureRegion's solver, scratch and constraint lists one arena that is reset
when the region ends. Publish results by copying them out, following CONTRACT.md
ownership rules. Use the same arenas for checker pending lists and the scheme
copier. Target: under 100 MB requested, with allocation-failure laws intact.

### Hill 8: default restart cache

Backend checkpoints (`backend_checkpoint.zig`) already reduce gdev restart CPU
by about 30%, but only when the client supplies them. The project server and the
CLI should read and write a cache by default under the platform cache directory,
keyed by compiler identity and the entry. Write it atomically, and on corruption
or an identity mismatch, ignore and replace it. Measure restart CPU with
`bench:compile`.

### Hill 9: parallel region inference

After hills 1–3, regions are independent closed jobs. Run them on
`semantic_workers` threads with solver state owned by each job. Publish results
in a deterministic order. Gate record collection in `independent_call_proof.zig`
on more than one worker. Enable by default only if paired CPU and wall time win
on an idle machine. Thread counts measured as no help while one region
dominated.

### Hill 12: one reuse/query model

Today's caching code spans 19 files, about 6.3k lines plus 7.3k of tests:
dependency certificates and closure, revision inputs, retained candidates, the
principal gate and evidence reuse, and refinement and specialization receipts.
Each has its own key, equality, hash and "did the inputs change" check.

Replace them with one query table: a key, recorded dependencies (from
`declaration_dependencies` and `dependency_closure`), a value fingerprint, and
an early-cutoff predicate. Archives become that table's serialization through
`dependency_format`. Migrate one mechanism at a time behind fresh/retained
parity, starting with refinement receipts.

### Hill 14: split god structs and switches

- **Structs:**
  - `core_eval.Session` has 75 fields; split into a value store, closure
    regions, specialization caches and retained-reuse state.
  - `core.Builder` has 73 fields.
  - `core_backend.Generator` has 53 fields; split into serialization, planning,
    array/layout and statement emission.
  - `core.Module` has 46 fields.
- **Functions:** split these per node kind:
  - `checkInternalExecution`, 383 lines
  - `expressionInner`, 335
  - `collect`, 279
  - `compileWithOptions`, 262
  - `serialize`, 251
- **Files:** split along the seams:
  - `check.zig` into schemes, expressions and statements, rows and fields, and
    validation
  - `core.zig` into module and builder
- **Target:** no function over about 120 lines.

Do this after hills 1–5, which edit the same functions.

### Hill 15: source layout and test filter

`zig-native/src` holds 285 `.zig` files flat, 139 of them tests, plus 32 fixture
directories and 18 `.blot` files.

- Move sources into `parse/`, `check/`, `eval/`, `backend/`, `reuse/` and
  `runtime/`, with tests next to their areas.
- Fixtures move to `zig-native/fixtures/`. `@embedFile` cannot leave a module's
  root, so either root the test module at `zig-native/` or expose the fixtures
  as a separate module in `build.zig`.
- Land `-Dtest-filter` from the policy branch.

Do this last, because it touches every import.

### Hill 17 follow-up

The first GitHub Actions run of the new workflow needs checking. It clones and
builds zig-analyzer at `756bfd5` with caching. An uncached analyzer backend
build took about 16 minutes on this loaded machine.

### Hill 19: docs

- Rewrite `zig-native/STATUS.md` as current state plus one table of current
  numbers.
- Cut `std/PERFORMANCE.md` (1,321 lines of dated journal) down to the current
  standard-library guidance.
- Leave the history in git.
- Update `zig-native/ARCHITECTURE.md` for policy, summaries and arenas as the
  hills land.

### Hill 20 remainder

The `.blot` fixtures at the top of `zig-native/src`, for example
`checker-positive_*` and `monad_*`, move with hill 15. `build/` still holds
about 4 GB of older qualification, profile and audit directories that were not
on the approved deletion list. Review them with the owner.

## Earlier programs still open

These items from the programs before 2026-10-08 are not covered above.

- **Semantic compilation program:**
  - Transactional revision deltas without rebuilding unchanged metadata. This
    overlaps hill 6.
  - Portable dependencies for complete semantic artifacts.
  - A resolved backend IR for calls, control flow and ownership.
  - Optimized-body reuse identities without incidental function indices.
- **Runtime ownership program:**
  - Shared RC, ownership of escaping and suspended effect values, and removal of
    the tracing collector after qualification.
  - Preserve the executed counterexample: State can return a closure that
    reaches the demand caching it.
- **Collections:**
  - Read-only List folds still use 1.9× the CPU of the pre-packed layout.
  - Broader row fusion and SIMD, ragged builders, rolling reductions and summary
    trees remain open.
  - Generic iterator step and cursor allocation remain open.
  - Keep List and Array as distinct types, with no public list indexing.
- **Language evolution:** see `zig-native/LANGUAGE_EVOLUTION.md` and the
  [demand evaluation design](zig-native/DEMANDS.md).

Gates for all of these: language fixtures, negative diagnostics, allocation
failure tests, executed Wasm, and fresh-versus-retained output comparisons.
Measure cold compiles, dependency population, first edit, subsequent edit, no-op
and failed-edit recovery separately.
