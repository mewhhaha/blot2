# Shared call contexts — 2026-11-03

Named helpers can now access initialized source globals through checked owner
roles, so their bodies remain shared instead of expanding into callers. A cached
dependency graph limits each helper's context to conservative transitive global
dependencies, including associated candidates and actual callbacks. Global
descriptors load behind invocation-local readiness guards. Mixed/inactive
arguments cannot substitute for a named global, and initialization never
replays.

Private calls also share exact immutable input words before nested planning and
choose direct parameters from completed physical demand. The 512-parameter limit
stays fixed. Scalar results return exact bits through either transport. Ordinary
concrete bound callbacks retain their qualifiers and closed-row certificates;
nonzero qualifier IDs no longer force expansion. Polymorphic/obligated closures
keep fallback. Guest ABI 8/session protocol 2 and saved framing schema 26 remain
unchanged. Gdev Hooks now captures one environment in a closed operation
dispatcher, with typed associated methods preserving calls. Ink/Pen sources
remain unchanged.

[Machine-readable evidence](2026-11-03-call-contexts.json) pins commands,
compiler and source hashes, samples, controls, failures and qualification. Final
compiler: `4ea42109bf2d13afacb04e226a1182a5372f110f83e70042f04603c7ff29431d`.
Before compiler:
`1ccf0e50b158971a3fa3d7943be3f6393db4212e61714cfc7ca0835c8b57068a`.

## Gdev Main

Three uncached paired sessions include startup and use seeded side order with
the frozen compiler/original source versus the final compiler/landed source.
Only world_storage changes; its source hashes are pinned. No other deliberate
benchmark work ran concurrently.

| Metric                         |     Before |      After |
| ------------------------------ | ---------: | ---------: |
| Compile median                 |     5.634s |     5.278s |
| Median absolute deviation      |     0.015s |     0.005s |
| Wasm bytes                     | 12,113,691 | 10,241,074 |
| Emitted expressions            |    853,678 |    645,290 |
| Failed plan constructions      |      1,464 |        577 |
| Discarded expressions          |    108,775 |     75,786 |
| Declared locals                |    399,240 |    352,383 |
| Wasm functions                 |      8,627 |      9,437 |
| Local/global instruction bytes |  8,017,336 |  6,694,005 |

Main is **1,872,617B smaller (15.5%)**. Each pair improves: 312, 334 and 376ms;
the median paired reduction is 334ms. The difference of overall medians is a
different statistic. Five-second, subsecond and 1–2MB targets remain unmet.

The compiler publishes 199 definitions that directly access source globals and
859 guarded global-reference sites. Main shares 820 logical input bindings and
needs no packet-to-direct promotions; those promotions matter in the smaller
wide-capture controls. These are compiler work counts, not runtime call counts.

A separate profile emits the exact same artifact. Exclusive backend time is
4.404s, checking 0.492s, lowering 0.129s and validation 0.103s. Backend
allocation requests total 5.21GB cumulatively; whole-process peak RSS is
1.05GiB. Do not add overlapping timing families or treat requested bytes as peak
memory.

## Controls and rejected experiments

The new `scripts/bench/capture_scaling.ts` covers width 32/128, one/four
captures, one/eight calls, shared/distinct owner bundles and one/all-field
reads. Three fresh repetitions of all 32 shapes execute 384 U32 checks per
compiler.

| Capture control                                           | Before bytes | After bytes |
| --------------------------------------------------------- | -----------: | ----------: |
| Shared width128, four captures, eight calls, all fields   |       86,413 |      50,307 |
| Shared width32, four captures, eight calls, all fields    |       20,108 |      12,616 |
| Distinct width128, four captures, eight calls, all fields |      134,653 |     263,521 |

Shared captures shrink up to **41.8%**. Distinct wide captures regress
**95.7%**: their packet stores/loads can cost more than the expanded forwarding
wrapper. This remains a representation hill; these results do not establish a
blanket capture improvement.

The first global-import prototype carried every source global into every helper.
It reached 10.24MB but took 16.6s, requested 24.1GB and published 806,909 owner
roles. Dependency footprints reduce that to 44,446 roles and retain the size
win. This slow prototype is excluded from the final timing samples.

The source-only hook change has its own three-pair same-compiler control:
**5.672 → 5.397s**, with per-pair reductions 244/312/195ms and a 2,961B size
increase. It is landed in Gdev `38af070`. A separate compiler-only round on the
original source records **6.546 → 5.965s**, Main **12,113,691 → 10,238,113B**.
These are different shared-host rounds; do not add their timing effects or mix
controls. The final combined round is the table above.

Four numeric Blot kernels are byte-identical to the preceding checkpoint.
Mandelbrot F32 grows by 10B; five fresh before/after pairs have overlapping
timings (76.32/75.91ms medians), so no numeric runtime gain is claimed. README
charts rerun all seven adapted Goose cases: five matched pairs and two
explicitly unsupported recursive Blot sorts. Original F64 remains unsupported.

World/editor results and seven renderer lane streams match. World shrinks
479,110 → 477,380B; hand grows 198,598 → 198,743B and renderer grows 92,016 →
93,468B. These regressions remain visible. The final Main passes the original
memory budgets in one headless NVIDIA frame. Its inspected PNG and guest trace
match the baseline byte for byte; see
[frame evidence](../../../../tasks/storage-handoff-evidence/2026-11-03-call-contexts-frame.json).
Broader gameplay/software-adapter coverage remains pending. The matching Pen
passes `codegen --check`; normal `pen check` and `pen test-blot` stop before
compilation because the host omits `inferenceBudget` from compiler settings. The
bounded Deno runner executes the affected source, including seven world/editor
and 160 hand assertions; the native frame uses the exact precompiled artifact.

## Qualification and next lever

All 2,969 native laws compile without LLVM. Affected families pass 405 unique
native laws; the scoped development family passes 238 native/202 guests. Eleven
focused laws pass full-fault mode. Zig lint has zero findings; formatting and
type checks pass. Final release guests pass 284/286. Both failures reproduce on
the frozen compiler: unsupported ECS summary-job export and legacy optimized
`iter.take(0)` allocation.

The full gate passes 49 smoke and 57 harness checks, then stops at its 180s
total budget after 100 native laws, with zero failures, leaks or logged errors.
It is incomplete, not a pass. Full native execution and broader integration
remain pending. Development compiler builds take 5–7s and inventory compilation
10–13s; the two interim/final LLVM builds took about five/six minutes. A new
noLLVM Main diagnostic stopped at 30s and is excluded.

The next large lever is immutable aggregate transport across calls. Local/global
instructions still occupy 6.69MB, and 282 bodies above 10KB contain 7.68MB. The
distinct-capture regression specifically exposes repeated private packet
serialization. Measure addressed bundles that persist across calls, preserving
complete owner/effect facts, snapshot semantics and invocation lifetimes.
