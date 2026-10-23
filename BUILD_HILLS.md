# Compiler build and iteration hills

These hills concern developing the Zig compiler. The separate
[compile-time hills](COMPILE_HILLS.md) concern compiling Blot programs. Use
[current measurements](COMPILE_MEASUREMENTS.md) rather than the historical cloud
timings in [development turnaround](DEVELOPMENT_TURNAROUND.md).

Always use Zig 0.17.0 Safe/noLLVM for development and native tests. LLVM belongs
to the actual release candidate. Keep compiler construction, test compilation,
test execution, analysis and wrapper overhead as separate measurements.

Current status: BT1's warm cache-hit target and BT3's observed development-cycle
targets are met; BT2's incremental-mode experiment remains negative. The final
[CT97/reuse/scratch candidate](zig-native/CT97_QUALIFICATION.md) passes affected
static-sharing/type-effects checks in 16.10 / 3.94 s. Those are individual
observations, not p95 claims. BT4's temporary scratch removes real allocations:
33 exhaustive sweeps now require 37,930 scenario runs instead of 44,074. Its
halved-law and paired whole-gate timing targets remain open. Complete native
execution takes 584.26 s and the whole gate 634.83 s in this interval; these are
not paired reductions from the previous 665.13 / 761.75 s gate.

| Hill                                                       | Evidence and next action                                                                                                                                                                                                                                                                | Acceptance target                                                                                                                                                                                                                |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BT1: preserve build-system caches                          | An empty-cache `zig build --help` takes about 56 s; the repeated invocation takes about 10 ms. The initial compiler artifact itself takes about 5 s. Keep a stable writable global/local cache across ordinary development cycles. Diagnose initial configuration/bootstrap separately. | No repeated bootstrap on unchanged inputs; unchanged compiler/native build commands below 0.1 s on this host. Cache hits must still depend on source/toolchain/configuration bytes.                                              |
| BT2: choose incremental mode from measured edits           | Compare ordinary artifact caching with explicit `-fincremental` on three distinct leaf edits, checker edits, test-only edits and exact source reverts. The default already preserves cheap unchanged/test-only compiler builds.                                                         | Change a default only after at least seven alternating real-edit pairs improve the complete edit/check cycle by 15%, with no more than 10% regression for unchanged/test-only/revert cycles. Until then keep incremental opt-in. |
| BT3: shorten the affected development cycle                | Compile the complete native inventory once and select laws at runtime; retain the explicit family, sampled fault policy and guest checks. Measure compiler build, native compile/run, identity scans, types and lint separately before removing work.                                   | Warm affected checks below 30 s and edited checks below 60 s on this host, while preserving complete inventory compilation and required laws. Collect 20 real cycles before making a p95 claim.                                  |
| BT4: reduce exhaustive test cost without reducing coverage | Stack scratch reduces allocation scenarios by 13.9%; all fault positions in the resulting compiler still execute. Current native phase 584.26 s. The one-pair top-three screen is in the qualification record. Stop further scratch-size tuning after two bounded trials.               | Still open: halve combined top-three cost and show at least 5% paired whole-gate gain; then reprofile toward 480 s native. No sampled substitute for qualification.                                                              |
| BT5: lower actual release construction cost                | Final LLVM release takes 196.47 s; the later gate uses that cached release. Release construction remains a separate cost. Collect a detailed Zig time report on the next necessary release.                                                                                             | First milestone below 150 s on this host/configuration, with identical behavior and no application CPU regression. Native unit tests remain Safe/noLLVM.                                                                         |

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
