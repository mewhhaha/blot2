# Compiler iteration costs

`deno task build:compiler:dev` uses Safe, the non-LLVM backend and incremental
compilation. Safe retains runtime safety checks while using the compiler's
production allocator; Debug uses the validating allocator. Native tests retain
their validating allocator. The production compiler and full native gate retain
their LLVM builds.

The 12 October comparison used Zig 0.17.0, CPU 8 and identical source tree
`8cd045d49d5610912ec49b2a63438a6686d636bf` in an isolated checkout. Each mode
had a separate output/cache configuration. Global caches and filesystem caches
were warm; the initial measurements are not cold-machine build claims.

| Wall seconds                     | Debug/noLLVM | Safe/noLLVM |
| -------------------------------- | -----------: | ----------: |
| Initial invocation               |       10.878 |       7.883 |
| Unchanged invocation             |        8.108 |       7.549 |
| Retained source comment edit     |        8.171 |       7.627 |
| Eight unchanged compiler budgets |        8.259 |       2.014 |

The eight budget laws pass in both modes. All 28 merged constant/member, cursor,
iterator, suspension and budget test groups pass in Safe: 11.768 seconds wall,
11.552 seconds child CPU. The earlier Debug run took about 41 seconds; that
broader comparison was not a controlled paired timing experiment.

Ignored `build/bench/dev-iteration-cost/` retains commands, binary/source
hashes, logs and separate build, edit and guest samples. Its original build
report calls the unchanged invocation `retained`; `pins.json` records the
corrected meaning. Only `edit-costs.json` measures an actual source edit.

The first combined 047/086 full gate took 928.947 seconds before its one failing
native law: build 181.270 seconds, native phase 747.666 seconds. These are wall
spans on CPUs 0–3, including scheduling. The failure and pin remain in
`build/bench/joint-047-086/`; the repaired gate has its own directory. These
measurements explain the dominant iteration cost and do not justify weakening
OOM or ownership coverage. Use focused development checks, then one full gate
per frozen batch.

The repaired compiler first ran a full native phase in743.310 seconds, then
972/973 guests in274.516 seconds. After the counter-schema test correction,
unchanged compiler source reused the build and successful native cache:
0.056/0.025 seconds for those task spans,276.872 seconds for all973 guests. The
complete final gate took276.964 seconds and passed. This is retained-cache
reuse, not a fresh native execution or faster changed-source build. Pins/logs
are in `build/bench/joint-047-086-qualified/`.

## Budget-test iteration fix

The earlier profiled gate in `build/bench/iteration/qualified-gate/` took 1,155
seconds: release build 176, native compilation 247, native execution 493, and
guests 227. Two stage-chain tests spent about 214 seconds repeatedly exhausting
the production million-step inference budget.

Routine rejection and recovery now use the ordinary CLI/server compiled with a
build-local 256-step budget. The fixture has a distinct compiler identity; the
production compiler must accept and execute the input it rejects. The tests
still require one positioned diagnostic, no published output, zero reported live
allocations, fresh/retained agreement, and unchanged Wasm and execution after
recovery. The adversarial production-limit case remains in
`deno task test:compiler:stress`.

The first focused run passed both laws in 115 ms (1.12 seconds including Deno
startup/checking), compared with the earlier rounded 214-second test durations.
The fixture build took 4.71 seconds with warm global/filesystem caches. This is
not a cold-machine build measurement. The production stress case passed in 51
seconds. Commands and logs are in `build/bench/iteration/budget-fix/`.

The full profiled gate passed all 1,508 native laws, 973 guests and 884
allocation-failure sweeps. Its guest phase fell from 226.56 to 17.47 seconds.
Native compilation and execution remained about 250 and 498 seconds. The
expanded development smoke check passed all 48 tests in 8.19 seconds, including
its build; keeping the unchanged budget fixture in Zig's artifact cache avoided
a three-second regression in the quick loop. Full-gate logs are in
`build/bench/iteration/budget-qualified/`, and the final quick-loop logs are in
`build/bench/iteration/budget-dev-cached-fixture/`.

## Six implemented improvements

Local implementation commit: `9080f6b`. The recorded source and binary hashes
were rechecked unchanged on 13 October before committing this checkpoint.

Measurements are local samples with warm global/filesystem caches, including
cache-miss compilations. Other compilation was active. They describe actual
iteration costs here, not cold-machine or repeatable benchmark guarantees.

| Improvement                            |                                              Before |                                                               Measured after | Coverage                                                                                                                                                                                                                                                 |
| -------------------------------------- | --------------------------------------------------: | ---------------------------------------------------------------------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Focused Safe/noLLVM native checks      |           78.47 s for the canonical constructor law |              5.04 s for separate compile/run phases; 12.46 s including smoke | Same 16 tests passed. Full production gate stays LLVM; `--native-llvm` is available for longer executions.                                                                                                                                               |
| Rolling/summary fault fixtures         |                                             174.1 s |                                                            23.75 s whole law | Original scalar/reference integration matrix remains, plus retained/nonretained byte equality. Two exhaustive representatives cover rolling state and retained reference trees: 6,694 failure indices. Artifact publication/replacement laws remain.     |
| Typed-path fault fixtures              |                                             56.25 s |                                                      18.59 s of fault sweeps | Full eight-entry matrix stays. Exhaustive frontend, evaluator, shallow, deep unobserved and deep Foreign emission coverage: 10,490 failure indices. Source types stay immutable.                                                                         |
| Prepared/retained revision fault setup |                                             31.51 s |                                                 7.68 s across all ten sweeps | 6,828 exhaustive failure indices. Fixture decode/validation is separate; immutable emission inputs are stamped per unrelated fault, then byte-checked without sources. Shared-owner candidate faults still verify old outputs and seed at every failure. |
| Native subsystem roots                 |               247 s / about 4 GiB for the full root | Syntax 20.12 s / 552 MiB; types 26.63 s / 603 MiB; runtime 47.75 s / 955 MiB | These are optional focused roots. The default complete `production_suite.zig` is unchanged, and the full gate refuses partial selectors. All three roots also pass noLLVM checks.                                                                        |
| Pinned prebuilt analyzer in CI         | Source build exceeded 60 s before backend bootstrap |                                              Install 1.088 s; doctor 0.009 s | Exact workflow shell bodies verified the pinned archive checksum, release tag/commit and compatible Zig backend. Workflow YAML parsed. Source timing is only a lower bound.                                                                              |

Choose a subsystem without narrowing the full production gate:

```sh
deno task test:compiler:dev --native-suite syntax
deno task test:compiler:dev --native-suite types
deno task test:compiler:dev --native-suite runtime --native-llvm
```

LLVM executes the complete types/runtime roots faster on unchanged artifacts;
noLLVM makes changed native code cheap to compile. The backend is recorded in
the timing report. Native root measurements include test execution. The isolated
syntax source-comment experiment passed all 34 tests in both runs: 18.97 seconds
for its initial artifact compilation and 18.56 seconds for the retained edit,
with 566 MiB peak compile memory. Those samples are separate in
`build/bench/iteration/all-hills/shard-edit/`.

Commands, logs, source pins and individual timings are under
`build/bench/iteration/all-hills/`. The pinned analyzer bundle is
[v0.17.0-1](https://github.com/mewhhaha/zig-analyzer/releases/tag/v0.17.0-1),
SHA-256 `398b48dfbf71cf7eba40cfff277db5b1680c701feffa2fdbe3178dcf525c94d3`.

The final complete profiled gate passed 1,508 native tests, 973 guests and 894
exhaustive allocation-failure sweeps, with zero findings across 360 Zig files.
It took 743.57 seconds (12.39 minutes), compared with 958.76 seconds before
these six changes. Native execution fell from 498.20 to 281.32 seconds; release
build/native compilation remained 176.14/250.33 seconds. Guest wall time was
23.34 seconds in this run. The increased sweep count reflects splitting large
products into independent exhaustive phases, rather than sampling faults. The CI
installer was validated locally; no remote Actions run was triggered.
