# Compiler iteration costs

`deno task build:compiler:dev` uses Safe, the non-LLVM backend and incremental
compilation. Safe retains runtime safety checks while using the compiler's
production allocator; Debug uses the validating allocator. Native tests retain
their validating allocator. Release builds and the full compiler gate are
unchanged.

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
