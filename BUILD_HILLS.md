# Compiler build and iteration hills

These hills concern developing the Zig compiler. The separate
[compile-time hills](COMPILE_HILLS.md) concern compiling Blot programs. Use
[current measurements](COMPILE_MEASUREMENTS.md) rather than the historical cloud
timings in [development turnaround](DEVELOPMENT_TURNAROUND.md).

Always use Zig 0.17.0 Safe/noLLVM for development and native tests. LLVM belongs
to the actual release candidate. Keep compiler construction, test compilation,
test execution, analysis and wrapper overhead as separate measurements.

Current follow-up: [CT102](zig-native/CT102_QUALIFICATION.md) keeps ordinary
Safe/noLLVM development builds. Its expanded static-sharing cycle passes in
35.36 s: compiler build 2.57 s, complete native compilation 15.50 s, sampled
native execution 0.91 s, with the additional retained-proof and executed-Wasm
laws. Actual LLVM release construction takes 254.61 s. Full native execution
takes 768.23 s and the complete gate 819.00 s. These individual intervals
are not paired compiler-build or whole-gate improvements; no build hill closes
from this batch. BT2 remains negative and BT4's previous scratch-size trials
remain complete. The historical CT97 scratch reduction (44,074 → 37,930 exhaustive
scenario runs) and its unresolved halving/whole-gate targets remain unchanged.

| Hill                                                       | Evidence and next action                                                                                                                                                                                                                                                                | Acceptance target                                                                                                                                                                                                                |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BT1: preserve build-system caches                          | An empty-cache `zig build --help` takes about 56 s; the repeated invocation takes about 10 ms. The initial compiler artifact itself takes about 5 s. Keep a stable writable global/local cache across ordinary development cycles. Diagnose initial configuration/bootstrap separately. | No repeated bootstrap on unchanged inputs; unchanged compiler/native build commands below 0.1 s on this host. Cache hits must still depend on source/toolchain/configuration bytes.                                              |
| BT2: choose incremental mode from measured edits           | Compare ordinary artifact caching with explicit `-fincremental` on three distinct leaf edits, checker edits, test-only edits and exact source reverts. The default already preserves cheap unchanged/test-only compiler builds.                                                         | Change a default only after at least seven alternating real-edit pairs improve the complete edit/check cycle by 15%, with no more than 10% regression for unchanged/test-only/revert cycles. Until then keep incremental opt-in. |
| BT3: shorten the affected development cycle                | Compile the complete native inventory once and select laws at runtime; retain the explicit family, sampled fault policy and guest checks. Measure compiler build, native compile/run, identity scans, types and lint separately before removing work.                                   | Warm affected checks below 30 s and edited checks below 60 s on this host, while preserving complete inventory compilation and required laws. Collect 20 real cycles before making a p95 claim.                                  |
| BT4: reduce exhaustive test cost without reducing coverage | Stack scratch reduces allocation scenarios by 13.9%; all fault positions in the resulting compiler still execute. CT97 native phase was 584.26 s; CT102 observes 768.23 s in a different interval. The one-pair top-three screen is in the CT97 qualification record. Stop further scratch-size tuning after two bounded trials. | Still open: halve combined top-three cost and show at least 5% paired whole-gate gain; then reprofile toward 480 s native. No sampled substitute for qualification. |
| BT5: lower actual release construction cost                | Latest actual LLVM release takes 254.61 s (CT97 observed 196.47 s in a different interval); the later gate uses that cached release. Release construction remains a separate cost. Collect a detailed Zig time report on the next necessary release.                                                                                             | First milestone below 150 s on this host/configuration, with identical behavior and no application CPU regression. Native unit tests remain Safe/noLLVM.                                                                         |

Run the isolated build measurement on Linux with Python 3.11+ and Zig 0.17.0:

```sh
deno task bench:compiler-build \
  --out build/bench/compiler-iteration-next --runs 3
```

It copies the compiler inputs, uses separate task caches, checks Zig's version
before each build, records wall/CPU/RSS and raw Zig summaries, makes distinct
edits, and restores the exact source bytes. It never edits the working compiler
or installed tools. Compiler identity and native test inventory are checked;
unstripped executable hashes are retained separately because a rebuilt native
test binary need not return to the same byte hash. The three restored budget
laws execute at the end of each mode. This is build-cost evidence, not a full
compiler qualification.

For ordinary work use `deno task check:dev --area NAME`; choose a documented
family with `--list-areas`. A successful development run still leaves full
exhaustive native execution, the complete guest suite and release performance
qualification pending. No timing hill may change that distinction.

CT96's first full qualification reached the default 600 s native-phase limit
with 2,366 laws passed and the rest cancelled. That run is incomplete. On this
host, allow headroom before starting the expensive full gate:

```sh
deno task test:compiler --native-shards 4 --phase-seconds 900 --budget-seconds 1200
```

This avoids repeating an otherwise healthy run because the earlier 596 s native
baseline barely fit the default phase limit. It changes the time allowance, not
the inventory or exhaustive fault policy. BT4 still targets reducing the actual
execution cost. CT96's complete rerun takes 665.13 s for native execution; the
different intervals are not a paired compiler-build performance comparison.
