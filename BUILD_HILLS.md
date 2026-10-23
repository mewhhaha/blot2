# Compiler build and iteration hills

These hills concern developing the Zig compiler. The separate
[compile-time hills](COMPILE_HILLS.md) concern compiling Blot programs. Use
[current measurements](COMPILE_MEASUREMENTS.md) rather than the historical cloud
timings in [development turnaround](DEVELOPMENT_TURNAROUND.md).

Always use Zig 0.17.0 Safe/noLLVM for development and native tests. LLVM belongs
to the actual release candidate. Keep compiler construction, test compilation,
test execution, analysis and wrapper overhead as separate measurements.

Current status: BT1's warm cache-hit target is met (15–16 ms). BT2's three-cycle
screen finds no useful real-edit gain from incremental mode and substantial
cache-hit regressions, so keep ordinary caching. BT3's warm target is met by
4.71 / 4.64 s `type-effects` checks. CT96's edited `tasks` cycle passes in 14.54
s, including complete native compilation, 17 selected laws and 27 guest checks;
this meets the edited target for one observed cycle, not a p95 claim. BT4 and
BT5 remain open. The [post-CT96 review](PERFORMANCE_REVIEW.md) profiles 33 full
sweeps in the three slowest laws: 44,074 scenario runs, all passing. The two
deep-path emission fixtures dominate the path law; their frontend setup is
already outside the emission sweeps.

| Hill                                                           | Evidence and next action                                                                                                                                                                                                                                                                | Acceptance target                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| BT1: preserve build-system caches                              | An empty-cache `zig build --help` takes about 56 s; the repeated invocation takes about 10 ms. The initial compiler artifact itself takes about 5 s. Keep a stable writable global/local cache across ordinary development cycles. Diagnose initial configuration/bootstrap separately. | No repeated bootstrap on unchanged inputs; unchanged compiler/native build commands below 0.1 s on this host. Cache hits must still depend on source/toolchain/configuration bytes.                                                                                |
| BT2: choose incremental mode from measured edits               | Compare ordinary artifact caching with explicit `-fincremental` on three distinct leaf edits, checker edits, test-only edits and exact source reverts. The default already preserves cheap unchanged/test-only compiler builds.                                                         | Change a default only after at least seven alternating real-edit pairs improve the complete edit/check cycle by 15%, with no more than 10% regression for unchanged/test-only/revert cycles. Until then keep incremental opt-in.                                   |
| BT3: shorten the affected development cycle                    | Compile the complete native inventory once and select laws at runtime; retain the explicit family, sampled fault policy and guest checks. Measure compiler build, native compile/run, identity scans, types and lint separately before removing work.                                   | Warm affected checks below 30 s and edited checks below 60 s on this host, while preserving complete inventory compilation and required laws. Collect 20 real cycles before making a p95 claim.                                                                    |
| BT4: reduce exhaustive test cost without reducing its coverage | The qualified native phase costs 665 s; its three slowest laws cost 87.35, 80.51 and 73.92 s. Perfect rebalancing has only 3.18% native headroom at fixed costs. Profile real backend allocations in the deep-path sweeps; setup is already hoisted.                                    | Halve combined top-three cost, preserving every required fault position and boundary case; measure at least 5% whole-gate gain. Reprofile before the 480 s native target, which requires broader reductions. Never replace full sweeps with sampled qualification. |
| BT5: lower actual release construction cost                    | CT96's LLVM release takes 204 s and overlaps the much longer native execution. It is not the critical path of that gate. Record Zig's detailed time report on the next necessary release, then inspect generic instantiation and repeated IR.                                           | First milestone: release build below 150 s on the same machine/configuration, with identical compiler behavior and no application CPU regression. Do not build LLVM unit tests or claim Safe/noLLVM timings as a release speedup.                                  |

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
