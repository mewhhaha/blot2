# CT103/CT104: principal dependencies and operation-row normalization

Qualified 24 October 2026. All four selected changes are implemented. Seven
alternating pairs against exact `5412320` reduce literal-edit CPU by **24.8%**,
body-edit CPU by **4.2%**, and fresh-game CPU by **6.1%**, with exact Wasm.
Devtools is effectively unchanged. The literal 20% target is met; the body 20%
and sub-second targets remain open. The final installed release includes the
concurrent `faf3f78` changes and receives separate combined qualification.

## Changes

1. Projected principal queries import nonempty type and effect-row results into
   the current owner. The existing type, depth and work bounds remain in force.
2. Principal keys record consumed positive and negative call proofs. Completed
   recursive summaries have separate argument/result observations and optional
   publications; they never become ordinary global call certificates. This lets
   the frozen game's literal edit reuse all 20 principal results instead of 18.
3. A complete declaration observation can admit a query or its memo outputs when
   an unrelated body changes. The root and every consumed declaration must
   match; the entire ordered semantic catalog and producer namespace must still
   match. Unknown foreign lexical sources require the complete input image. The
   measured body edit reuses one extra result, reducing fresh principal regions
   from five to four; the large body-edit jobs remain.
4. Operation-row normalization retains at most 64 answers per solver, keyed by
   resolved row, cursor, depth, depth limit and both mutation epochs. Writes and
   rollback invalidate the entries; saturated epochs disable reuse. Immutable
   operation arguments can also receive the existing positive certificate beside
   an open tail, which is resolved before lookup.

All result and memo graphs are translated before publication. Unsupported
optional memo outputs are omitted and their next use checks normally. Source
certificates grant no evaluated-value or executable-body reuse. The portable
principal archive key advances to version six; portable lookup still requires
the complete source image. See [the ownership contract](CONTRACT.md) and
[client statistics](PROJECT_CLIENT.md).

## Validation

The measured candidate passes **2,548 native laws with exhaustive allocation
failures**, 48 smoke checks and 57 tooling checks. Its full gate fails at the
existing summary-job restart guest test after 1,364 guest passes: an unsupported
optional summary output discards an otherwise admitted portable principal
result. Native execution takes 650.62 s. The complete failed gate evidence is
preserved; it is not a release pass.

The final fix omits only unsupported optional summary publications. Required
summary reads still must translate and match before any publication. The
existing restart law now runs in the static-sharing development family and
passes, including lost-reuse detection, fresh byte parity, errors and recovery.
The original integration run was cancelled after discovering this regression;
its incomplete evidence is also preserved. Native tests compile with Zig 0.17.0
Safe/noLLVM. The complete inventory is checked across four isolated shards; no
incomplete, skipped or sampled run substitutes for qualification.

Main advanced from `5412320` to `faf3f78` during measurement. The combined
source includes that commit and the portable-output fix. This final candidate is
frozen separately and passes **2,551 exhaustive native laws**, **1,654 guest
checks**, 48 smoke checks and 57 tooling checks, with zero Zig lint. Its native
phase takes 576.32 s and full gate 623.68 s. A separate strict frozen-workload
screen checks fresh builds, literal/body edits, reverts and checkpoint restarts
against the measured candidate. It allows no output differences. This is
integration correctness evidence, not a new performance measurement of the later
changes. The seven-pair figures belong to the pinned measured candidate; the
portable fix changes only restart summary-output admission, not fresh or
retained principal inference.

New regression laws cover nonempty translated rows, consumed-source edits,
positive/negative call reads, exact completed-summary inputs/results, atomic
publication, malformed archive observations, and normalization through historic
writes, physical changes, depth limits, rollback and saturated clocks. The
consumed-callee rejection fixture preserves producer order and explicitly
asserts a source-image decline, so a namespace mismatch cannot make it pass.
Executed-Wasm cases cover local row mappings, recursive calls, edits, errors,
recovery and checkpoint restart with a changed output policy in both codegen
tiers. The changed policy prevents cached output from hiding failed proof
replay.

The expanded development cycle passes in **26.05 s** with sampled faults: 3.59 s
compiler build, 6.90 s complete native compilation, 0.87 s selected native
execution, 10.76 s guest smoke, 1.09 s selected guests, 0.84 s type checks and
0.97 s lint. These individual observations do not establish a paired
compiler-build gain or p95. The measured actual LLVM release takes 234.85 s; the
final combined release takes 191.29 s. No build hill closes.

## Measurement protocol and pins

The performance baseline is exact committed
`541232090b3941ec0c433de54d04c43c1eeb0276`; the measured candidate is that
commit plus the recorded optimization. Both are actual Zig 0.17.0
ReleaseFast/LLVM compilers. Production sources stay fixed across the accepted
comparisons. A later test-only strengthening does not affect the release
identity or bytes. The final combined installation is based on
`faf3f78f864e5bcbb6d0e11a1c2ce8d824841ca6` plus this change. Source hashes,
commands, compiler identities and release hashes are archived separately.

| Release                   | SHA-256                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| Performance baseline      | `88a94a4e77244d3f7f809e728eafa82a2fb7092604a88a3c68c99bc9b9c34ba5` |
| Measured candidate        | `7ae8081bdb0b55337d48571ffedae9b86a4e3699bec232d13d1eca846e193bee` |
| Combined installed native | `0185500e446d59d6e813de8cecb3318bcc5983632043eb0129b8a64bad45ee9f` |

The frozen 554-file gdev/Ink/std/asset corpus and original pen settings remain
unchanged: optimized codegen, four codegen workers and a 200,000,000 inference
budget. Input manifest SHA-256 is
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`. New output
pins require exact baseline/candidate equality in the initial
fresh/edit/revert/restart screen. CT102's older pins predate `5412320` fixes; no
Wasm-difference allowance is used.

Seven alternating unprofiled pairs measure fresh game/devtools and retained
edits separately. Each retained pair has fresh controls and isolated restart
caches. CPU is Linux process user+system ticks including exited workers; wall
time is the build request, excluding process start/open. OS caches are not
flushed. A separate profiled pair attributes work; clocks are not added to
overlapping parent/region clocks. The gain is the median of each pair's
candidate/baseline CPU ratio, not the ratio of independent medians below.

No own compiler build, native-test gate or diagnostic profile runs concurrently
with accepted throughput comparisons. Other shared-host work remains active;
wall distributions are noisy. Even some no-op requests consume 10–20 ms CPU
while waiting seconds. The predeclared target is at least 20% less retained CPU
and no more than 5% unaffected fresh regression, evaluated independently for
literal and body edits. No thresholds are relaxed after measurement.

## Seven-pair results

| Scenario       | Median paired CPU change | CPU medians, baseline → candidate | Wall medians, baseline → candidate |
| -------------- | -----------------------: | --------------------------------: | ---------------------------------: |
| Fresh game     |                   -6.06% |                   13.69 → 13.02 s |                  19.090 → 17.365 s |
| Fresh devtools |                   -0.94% |                     1.06 → 1.06 s |                    1.098 → 1.074 s |
| Literal edit   |                  -24.82% |                     8.34 → 6.27 s |                    8.529 → 7.599 s |
| Literal revert |                  -30.79% |                     6.86 → 4.75 s |                    6.850 → 4.898 s |
| Body edit      |                   -4.20% |                     9.93 → 9.28 s |                  10.864 → 12.461 s |
| Body revert    |                   -2.90% |                     9.64 → 9.11 s |                  10.174 → 13.269 s |

The literal target and unaffected-work guards pass. Body CPU improves 4.2%,
which misses its 20% target. Body wall median worsens; do not claim a body wall
speedup. Literal wall ranges are 5.30–49.68 s baseline and 4.42–28.21 s
candidate; body ranges are 6.36–74.58 s and 6.46–29.55 s. A quiet-host latency
distribution is still needed before closing either ordinary-edit wall target.

Literal-stage process peak RSS medians rise from 726,072 to 755,708 KiB (about
709 to 738 MiB); body-stage medians are 763,508 and 763,148 KiB. These are
cumulative server high-water marks including population and previous requests,
not isolated per-edit allocation measurements. Preserve this memory tradeoff
when considering larger memo capacities.

Literal principal hits rise from **18 to 20**, fresh regions fall from two to
zero, and 4,400 completed summaries are published, including replay of one
nonempty principal result. Body principal hits rise from **15 to 16**, with one
consumed-source hit, leaving four fresh regions. The remaining large body jobs
still need inference; the result does not justify wider source admission. The
three largest body principal regions collect 1,832,134 / 936,128 / 610,381 nodes
with complete input recordings. They still fail source admission. For the
literal edit, the largest recorded non-principal entry/closure queries still
collect roughly 77,000–100,000 nodes each despite all principal hits. These
overlapping region counters are diagnostic work, not additive CPU times.

The separate candidate phase sample spends 1.504 s in literal inference and
4.363 s in body inference. Host load changes sharply across that pair, so its
body wall ratio is not a causal speedup claim. Use the seven unprofiled CPU
pairs for throughput acceptance.

## Previously unseen edits

Three distinct literal values followed by three distinct body changes all match
both binaries and fresh controls; revert restores the original output. This is
one profiled sequence, not a latency distribution.

| Revision  | Candidate wall | Candidate CPU | Frontend check | Inference |
| --------- | -------------: | ------------: | -------------: | --------: |
| Literal 1 |        4.513 s |        4.64 s |        0.912 s |   1.578 s |
| Literal 2 |        2.964 s |        3.27 s |        0.063 s |   1.475 s |
| Literal 3 |        3.181 s |        3.50 s |        0.067 s |   1.514 s |
| Body 1    |        6.689 s |        6.98 s |        0.069 s |   5.063 s |
| Body 2    |        7.618 s |        7.85 s |        0.062 s |   6.466 s |
| Body 3    |        6.200 s |        6.52 s |        0.062 s |   4.566 s |

The original combined driver exited 143 after its first warm-sequence success
marker, before clean completion and before the gate. Cause is unknown. Completed
cold/retained/profile records are preserved. The warm sequence was rerun
separately to exit zero, then full qualification was launched separately. Both
interrupted and clean evidence are archived; a success marker alone is not
counted as a completed run.

## Diagnostic evidence and next hills

A separate Safe/noLLVM run first confirmed all 20 principal hits and the
completed-summary publications. A 64-slot exact-epoch simulation in 89 large
solvers covered 22,737,312 of 181,230,656 operation-label visits (12.55%). It
motivated the bounded cache but does not establish an isolated cache CPU gain;
the release comparison measures the combined four changes.

Next, attribute the exact consumed declarations invalidating the largest body
regions and repeated summary/body queries outside principal replay. Keep the
body 20% target and four/two/one-second ordinary-edit targets open. Investigate
first-edit frontend allocation separately from later revisions. Do not multiply
historical ratios from different intervals into a cumulative speedup claim. See
[the compile queue](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md), [build queue](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/BUILD_HILLS.md) and
[performance review](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/PERFORMANCE_REVIEW.md).

## Installation and evidence

The combined release is installed as `~/.local/bin/blotc`; the standalone CLI at
`~/.local/bin/blot` bundles that exact native binary, parser, updated guide and
standard library. Both resolve through PATH. Outside the repository,
format/check/build pass, native and CLI Wasm are byte-identical, and the
executed list example returns 29. The bundled guide equals the combined source
guide.

CLI SHA-256: `28f989af445ef716539b8afb3015cdfc2a98d458fd2a79d903b74836f2f64874`.
Previous installed binaries are preserved at
`build/install/ct103/previous-glbm9pgb`. Atomic replacement and rollback on
failed verification are recorded in `build/install/ct103/installed.json`.

The [evidence archive](measurements/ct103-inference-reuse-2026-10-24.tar.gz)
contains commands, hypotheses, source pins, diagnostic counters, all raw paired
samples, output hashes, exhaustive native/guest/gate logs, integration checks
and installation records. Every payload is covered by `SHA256SUMS`. Compiler
binaries, caches and private workload sources are excluded. Reproduction of gdev
requires the matching private snapshot; source/binary hashes distinguish the
measured candidate from the combined installed release.
