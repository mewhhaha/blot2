# Compiler build and iteration hills

These hills concern developing the Zig compiler. The separate
[compile-time hills](COMPILE_HILLS.md) concern compiling Blot programs. Use
[current measurements](COMPILE_MEASUREMENTS.md) rather than the historical cloud
timings in [development turnaround](DEVELOPMENT_TURNAROUND.md).

Always use Zig 0.17.0 Safe/noLLVM for development and native tests. LLVM belongs
to the actual release candidate. Keep compiler construction, test compilation,
test execution, analysis and wrapper overhead as separate measurements.

[CT109](zig-native/CT109_QUALIFICATION.md) expands the static-sharing family
to 95 native laws. Its last complete selected cycle passes in 25.73 s; this is
one shared-host observation, not a paired construction speedup. Final exhaustive
qualification compiles all 2,573 native laws with Safe/noLLVM in 8.63 s and
executes them in 651.07 s (four shards, 630–651 s). The full gate takes 711.82 s
and includes 1,656 guests; its already built LLVM release is reused. Development
selection and complete release qualification remain separate.

The CT106 distribution below retains its original 78-law selection and source
pins; it is historical evidence, not the current selection count.

[CT106](zig-native/CT106_QUALIFICATION.md) measures 20 complete Safe/noLLVM
static-sharing edit/check cycles: **25.35 s median**,
**27.64 s observed p95**, **27.78 s maximum**.
Leaf/checker compiler construction medians are 4.29/4.88 s; the test-only cached
compiler build is 0.36 s. Complete native compilation takes 7.20–8.03 s by edit
class, and guest smoke about 9.7–9.9 s. Every cycle compiles all 2,564 native
laws, runs the same 78-law sampled family and 55 guests, and passes local checks.
The first failed teardown sequence is excluded and preserved; the completed
sequence verifies every source restoration, compiler identity and inventory.
These are observed distributions on a shared host, not paired build speedups or
universal latency bounds. Full release qualification remains separate.

The actual LLVM release trace spends 220.88 of 227.76 s in emission. Keep
Safe/noLLVM for development and the complete native inventory; focus next on
native compilation, the measured guest cost and LLVM emission. The deep guest
fixture is already just above its required 128-level boundary. Correct build
identity recomputation preserves compiled-artifact caches and fixes the observed
stale digest. [Experiment tools](scripts/bench/README.md) document reproduction.

BT3's current-host latency thresholds are observed across the 20-cycle sample;
this is evidence for the selected family, not whole-subsystem qualification.
BT1's sub-0.1-second command target, BT4's paired exhaustive-gate improvement and
BT5's sub-150-second release target remain open. Four native shards span about
599–649 s, so rebalancing alone has limited headroom. No generic-interface or
incremental-mode policy is changed on this evidence.

Historical follow-up: [CT103/CT104](zig-native/CT103_QUALIFICATION.md) keeps
Safe/noLLVM development and native tests. Its expanded static-sharing cycle
passes in 26.05 s: compiler build 3.59 s, complete native compilation 6.90 s,
sampled native execution 0.87 s. The measured actual LLVM release takes 234.85
s; the final combined-main release takes 191.29 s. The measured native gate
takes 650.62 s, and the combined native gate takes 576.32 s (623.68 s complete).
These separate intervals are not paired build/gate improvements; no build hill
closes. BT2 remains negative and BT4's scratch-size trials remain complete. The
historical CT97 allocation reduction (44,074 → 37,930 exhaustive scenario runs)
and its halving/whole-gate targets remain unchanged.

| Hill                                                       | Evidence and next action                                                                                                                                                                                                                                                                                                         | Acceptance target                                                                                                                                                                                                                |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BT1: preserve build-system caches                          | An empty-cache `zig build --help` takes about 56 s; the repeated invocation takes about 10 ms. The initial compiler artifact itself takes about 5 s. Keep a stable writable global/local cache across ordinary development cycles. Diagnose initial configuration/bootstrap separately.                                          | No repeated bootstrap on unchanged inputs; unchanged compiler/native build commands below 0.1 s on this host. Cache hits must still depend on source/toolchain/configuration bytes.                                              |
| BT2: choose incremental mode from measured edits           | Compare ordinary artifact caching with explicit `-fincremental` on three distinct leaf edits, checker edits, test-only edits and exact source reverts. The default already preserves cheap unchanged/test-only compiler builds.                                                                                                  | Change a default only after at least seven alternating real-edit pairs improve the complete edit/check cycle by 15%, with no more than 10% regression for unchanged/test-only/revert cycles. Until then keep incremental opt-in. |
| BT3: shorten the affected development cycle                | Compile the complete native inventory once and select laws at runtime; retain the explicit family, sampled fault policy and guest checks. Measure compiler build, native compile/run, identity scans, types and lint separately before removing work.                                                                            | Warm affected checks below 30 s and edited checks below 60 s on this host, while preserving complete inventory compilation and required laws. CT106 observes 25.35 s median and 27.64 s sample p95 over 20 complete cycles; retain scope and shared-host limitations.                                  |
| BT4: reduce exhaustive test cost without reducing coverage | Stack scratch reduces allocation scenarios by 13.9%; all fault positions in the resulting compiler still execute. CT97 native phase was 584.26 s; CT102 observes 768.23 s in a different interval. The one-pair top-three screen is in the CT97 qualification record. Stop further scratch-size tuning after two bounded trials. | Still open: halve combined top-three cost and show at least 5% paired whole-gate gain; then reprofile toward 480 s native. No sampled substitute for qualification.                                                              |
| BT5: lower actual release construction cost                | CT103 measured LLVM release takes 234.85 s; final combined-main release takes 191.29 s (different intervals); the later gate uses that cached release. Release construction remains a separate cost. CT106 records 227.76 s total with 220.88 s in LLVM emission; target emission cost rather than assuming generic analysis dominates.                                                           | First milestone below 150 s on this host/configuration, with identical behavior and no application CPU regression. Native unit tests remain Safe/noLLVM.                                                                         |

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
