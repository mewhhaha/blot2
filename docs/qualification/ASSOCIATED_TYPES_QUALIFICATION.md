# Task 055 associated type members

The implementation covers defined type equations, abstract type members and
complete abstract function signatures. Defined projections normalize and
execute; abstract applications can remain symbolic in principal schemes.
Implementation declarations and member execution belong to task 056. Residual
projections never supply a backend layout.

Task 055 is complete at `46bf8b9`. The combined compiler gate passes the native
suite, 914 guest/client laws and eight unchanged allocation budgets; the
analyzer checks 348 files with zero findings. Exact combined inputs and
preserved failed attempts are in
[FRONTEND_OWNERSHIP_QUALIFICATION](FRONTEND_OWNERSHIP_QUALIFICATION.md).

## Scope and boundaries

- Named, shaped, curried and zero-argument projections; forward equations,
  nested records/products/sequences and generic alias recipes.
- Type and row substitution, including operation arguments inside exact latent
  rows. Signature checks run after defined projection normalization.
- Symmetric/transitive scoped `type_eq`, congruent projections, exact abstract
  contract coverage and preserved public binders. Associated outputs cannot
  determine their inputs. Exact reflexivity does not require a layout guess.
- Original contract/member identities across namespace imports, selective
  forwarding, opaque types and private interfaces. Public signatures cannot hide
  a private projection by reducing its equation.
- Required flat owned interface/Core member tables and complete recipes,
  including declared row names/positions. Admission rejects escaped binders,
  missing/duplicate records, forged equations, cycles, shifted rows and false
  origin claims. No AST or caller solver storage survives publication.
- Dependency wire version 3; changed backend checkpoint, principal, semantic and
  optimizer interpretation keys. Cycle/depth/work failure and OOM discard the
  entire unpublished candidate.

The new work shares the checked project budget, capped at 1,000,000 steps;
normalization/prerequisite depth is capped at 256. Memoization preserves active
cycle checks. Direct, mutual and growing equations reject after alias expansion.

## Immutable checkpoints

The first review checkpoint is based on production `dd6a66a`:

| Item                    | Pin                                                                |
| ----------------------- | ------------------------------------------------------------------ |
| Source tree             | `6c8b9d1a473271dc693b8a71233ce94d816546e3`                         |
| Source patch SHA256     | `0005bbf03b0386c1380a1822771ed90b793d8f96b95dacb36cc75422d2daad6b` |
| Release SHA256          | `dafafe35a96360e2edc153143462778987368fdfdd01df99b6221371e7160f5c` |
| Compiler identity       | `3539a85566441bc47c93e5cd1cb30f8f1396c73e70803649da3cdf63ff9962da` |
| Baseline release SHA256 | `c0959e9a375b2ba8d2a2263278417fb917b434e733c9a13f80af1d372e80b060` |

The measured release and its source remain unchanged. Separate review fixes
retain and compare declared row recipes, preserve distinct abstract application
binders, derive congruent equality chains, and normalize complete signatures.
Their implementation tree is `58411759f3aa36c1554a34e632e1d8c692d0e2b7`. A
diagnostic-only follow-up (`ff20fb63d1a960408af4dede845c7d39963638fa`) reports
`missing_implementation` for known abstract storage applications while retaining
`missing_predicate` for open generic payloads.

The first combined gate against `39e84f9d7fee4208f0845365260f7a07061c862a`
failed at native compilation: a generic test snapshot hashed Task 024 body-cache
lease/map pointers. The full unfiltered Task 055 native suite compiled
separately. A combined-tree trace identified `module_frontend_tests.zig` hashing
`partial_dependency.Prepared.body_caches`; integration replaced that test stamp
with immutable cache content/ownership checks, preserving the structural hash's
pointer refusal. The failed log and full trace remain in the artifact directory.

The final measured combined source tree is
`fe338f7062dccfa7214e20fe9687646a53526adc`, native source tree
`d96b286cbaa67afa5dc2bc24cc0469776e6fbd6a`, including all separate Task 055
scope and storage-diagnostic fixes. Its immutable release SHA256 is
`47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`, compiler
identity `ddaac9d20cb2f2e18dd530e5d6c08cb1240496f02c3124e4076c449446d9e4a3`. The
combined compiler gate subsequently passes against qualification tree
`cfdd18a616412e3416a5169ea18dec38cf67ec28`; analyzer reports 348 files/zero
findings. No compiler rebuild or redundant full gate was used for the final
performance screens.

## Validation

Zig 0.17.0 was checked before each build batch. Development used
`deno task build:compiler:dev`; the frozen checkpoint received one standard
`deno task build:compiler` release build on CPU 5.

Focused native safe/noLLVM `associated` and `contract` filters pass. They
include exhaustive allocation-failure walks for checking, symbolic/type/row
projection copying, wire decode/admission/relocation and declared-row forgery
rejection. The binder control first reproduced an unwanted reduction from two
quantifiers to one; exact coverage preserves both after the correction.

Three executed guest laws pass: nested defined outputs and callback rows;
concrete equality prerequisites, equality chains and missing implementations;
imported recursive failed edits preserving revision/output, restoration and both
automatic restart and explicit checkpoint parity. The 128-helper lifecycle below
also executes fresh, edited, restored and restarted Wasm in optimized and
development tiers.

Fourteen focused host formatter/parser/diagnostic tests pass, including
formatted public examples/std modules compiling to identical Wasm. The host
parser was regenerated from `grammar.baba`. TreeSitter 0.27.1 regenerated with
ABI 14/native JS runtime; its corpus/highlights and
syntax/ecs/host-capability/host-I/O example parses pass. The CLI was acquired
through `pnpm dlx tree-sitter-cli` without a project dependency change. Focused
analysis checks 345 Zig files with zero findings; the root combined tree
subsequently reports 348/zero.

## Costs

Raw artifacts and harnesses are retained under
`/var/tmp/blot2-associated-055-qualified/build/bench/associated055/`.
`no-feature-schedstat/{results.json,samples.jsonl}` contains seven alternating
baseline/candidate pairs for each synthetic workload. Fresh/restart CPU uses
child user+system time; retained CPU sums live thread scheduler runtime in the
serial compiler. The original `/proc/stat` measurements remain in `no-feature/`
for comparison. Process affinity is CPU 7. Private gdev inputs were unavailable
in this isolated tree; no private checkout was changed or benchmarked.

| No-feature workload   | Fresh allocations, both | Candidate requested-byte increase | Fresh median CPU ratio | Retained first-edit CPU ratio |
| --------------------- | ----------------------: | --------------------------------: | ---------------------: | ----------------------------: |
| Monomorphic chain 128 |                  22,976 |        6,514 / 8,021,155 (0.081%) |                  1.000 |                         1.033 |
| Generic chain 64      |                  27,164 |        6,562 / 8,314,153 (0.079%) |                  1.000 |                         1.056 |
| Diamond 8             |                  13,031 |        1,186 / 4,117,091 (0.029%) |                  1.000 |                         1.067 |
| Fanout 128            |                  53,919 |      25,090 / 15,654,475 (0.160%) |                  1.000 |                         1.022 |

Type-node counts and fresh allocation counts match the baseline exactly. Wasm is
identical between compilers, fresh/retained edits and restarts. The retained CPU
results show a small observed overhead; this record does not claim zero cost.
Fresh/restart CPU samples are only millisecond resolution. Seven pairs, small
workloads and a shared host limit precision; the combined final release needs
its own screen.

`projections-qualified/results.json` records seven child-CPU samples per depth,
requested allocations and checker counters for a doubling projection DAG:

| Levels | Result         | Median CPU us | Owned type nodes | Associated steps | Exact memo hits | Requested bytes / allocations |
| ------ | -------------- | ------------: | ---------------: | ---------------: | --------------: | ----------------------------: |
| 8      | accepted       |           708 |              463 |            1,593 |              80 |               201,555 / 1,690 |
| 16     | accepted       |           983 |            1,543 |            5,709 |             288 |               543,350 / 5,287 |
| 32     | accepted       |         1,992 |            5,623 |           25,909 |           1,088 |            1,778,360 / 18,670 |
| 64     | accepted       |         5,809 |           21,463 |          142,853 |           4,224 |            6,001,839 / 70,164 |
| 128    | depth rejected |        21,857 |           83,998 |          912,600 |          16,639 |          22,024,822 / 271,838 |

Work tracks distinct generated graphs/subproblems rather than the exponentially
expanded tuple tree. Checking each generic declaration produces different binder
applications, so this whole-catalog benchmark is not a claim of linear source
size cost. The 128-level case reaches the active depth limit and reports
`associated_limit`; every run releases all owners. A separate 32-level callback
DAG law checks shared rows within one instantiation and fresh rows between uses.

`lifecycle-schedstat/results.json` contains seven repetitions in each codegen
tier, with a 128-helper imported projection workload:

| Phase                 | Optimized median CPU ms | Development median CPU ms | Solver / scratch allocations |
| --------------------- | ----------------------: | ------------------------: | ---------------------------: |
| Fresh                 |                   5.033 |                     5.153 |                2,703 / 2,061 |
| Recipe edit           |                   3.940 |                     3.963 |                2,703 / 2,061 |
| Failed recursive edit |                   2.017 |                     2.032 |      No backend solver phase |
| Restore               |                   3.743 |                     3.756 |                2,703 / 2,061 |
| Noop                  |                   0.081 |                     0.084 |                        0 / 0 |
| Restart               |                   5.347 |                     5.434 |                2,703 / 2,061 |

Successful non-noop phases request 422,164 solver bytes and 339,448 scratch
bytes. These are named backend allocation scopes, not total retained-owner
allocations. Failed edits preserve the last-good revision/output. Both tiers
execute to the same result; recipe edits, restored source and restart preserve
Wasm bytes. Earlier quantized lifecycle samples remain in `lifecycle/`.

## Final combined release screen

The exact harnesses were rerun on CPU 5 against the final immutable combined
release and incoming `c0959e9a` baseline, with seven alternating pairs. Raw
samples, result digests, source/release/identity pins and harness SHA256 values
are in `final/pins.json` and
`final/{no-feature-schedstat,projections,lifecycle-schedstat}/`. The final
binary SHA256 was checked again after all screens. These measurements cover
combined Tasks 024/035/039/055; they do not attribute every CPU difference to
Task 055.

| No-feature workload   | Fresh allocations, both | Candidate requested-byte increase | Fresh median CPU ratio | First-edit CPU ratio | Subsequent-edit CPU ratio |
| --------------------- | ----------------------: | --------------------------------: | ---------------------: | -------------------: | ------------------------: |
| Monomorphic chain 128 |                  22,976 |        6,516 / 8,021,212 (0.081%) |                  1.000 |                1.044 |                     1.021 |
| Generic chain 64      |                  27,164 |        6,564 / 8,314,210 (0.079%) |                  1.000 |                1.042 |                     1.024 |
| Diamond 8             |                  13,031 |        1,188 / 4,117,148 (0.029%) |                  1.000 |                1.063 |                     1.031 |
| Fanout 128            |                  53,919 |      25,092 / 15,654,532 (0.160%) |                  1.050 |                1.018 |                     1.027 |

Type nodes remain exactly 10,411/9,397/6,430/18,504 respectively in both
compilers. All fresh/retained/restart Wasm hashes match. Restart median ratios
are 1.000 for all workloads; retained population ratios are
1.017/1.020/1.032/1.011 and noop ratios are 0.921/0.958/1.002/1.018. The
millisecond fresh/restart resolution and small workloads limit precision;
retained scheduler-runtime measurements show measurable edit overhead.

The final doubling-DAG screen preserves every node, work and allocation counter
in the earlier table. Median child CPU is 817/1,086/2,093/5,953/22,495 us at
levels 8/16/32/64/128. Levels through 64 pass; 128 reports `associated_limit`.
All 35 samples end with zero live allocated bytes. This demonstrates bounded
sharing over distinct graphs, not linear whole-catalog growth.

The final lifecycle screen contains 84 samples, seven repetitions of all six
phases in both tiers. Positive phases execute `answer(42) = 42`, retain
identical Wasm bytes within each tier and reload the automatic restart cache.
Every failed recursive edit retains revision 2. The focused guest law separately
checks last-good output access and explicit checkpoint parity.

| Phase                 | Optimized median CPU ms | Development median CPU ms | Solver / scratch allocations |
| --------------------- | ----------------------: | ------------------------: | ---------------------------: |
| Fresh                 |                   5.267 |                     5.310 |                2,703 / 2,061 |
| Recipe edit           |                   3.986 |                     3.863 |                2,703 / 2,061 |
| Failed recursive edit |                   2.057 |                     2.041 |      No backend solver phase |
| Restore               |                   3.740 |                     3.782 |                2,703 / 2,061 |
| Noop                  |                   0.080 |                     0.083 |                        0 / 0 |
| Restart               |                   5.690 |                     5.562 |                2,703 / 2,061 |

Successful non-noop solver/scratch requests remain 422,164/339,448 bytes.
Allocation counts and requested bytes are deterministic in all seven samples;
these named backend scopes exclude other retained owners. All earlier pins, raw
samples and failed attempts remain preserved.

## Preserved failures and remaining scope

The first 32-level DAG exposed exponential covariance traversal and was stopped;
sharing/cutoff laws now bound it. An early symbolic-field retry duplicated
pending work; its structural evidence law now passes. An early budget-cleanup
defer used released inference state; the defer now spends the budget before
cleanup. The first equality-prerequisite guest exposed public binder narrowing;
written principal headers now remain intact. These failed attempts and the
original source patch are preserved, not presented as passing evidence.

No implementation selection or method execution is claimed; those belong to
Task 056. Final combined release screens and compiler/analyzer/budget
qualification pass at `46bf8b9`; Task 055 is complete.

The required storage diagnostic is included in the final combined source:
`Source.Item U32` in an unqualified data payload reports
`missing_implementation`, while generic `Source.Item a` reports
`missing_predicate`. The separately preserved patch is
`admission-followup/storage-diagnostic.patch`, SHA256
`34e7e73d49a85c0220febac650f60bb00508d7ed20ef844a43bb4a764be144bb`. Its
safe/noLLVM negative control and final full qualification pass.
