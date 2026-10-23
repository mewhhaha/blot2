# Integrated numeric and ownership qualification, 23 October 2026

This comparison starts at released main `93bc8d4`. The candidate combines the
recovered closed-row certificates, evaluated-call/static-capture reuse and
iterator cursor work with recursive numeric collection storage. It also fixes
project-client shutdown and improves full native test scheduling and resume
identity.

## Pinned compilers and workload

- Baseline LLVM executable:
  `12dcb193d352feb50bf7ebbd8fdea91f7a4034fd1925b9a50dfb3ce3ebb16eb3`.
- Candidate LLVM executable:
  `6daefd5ffc0331dc9a7dcd559244657f0350ef019da42244c1c3c4c7bef7140e`.
- Frozen source manifest:
  `60e11cc0c22ba75b4c5bb892f02a3509d9835a710036874aad360fa09b19a030`, 583 files.

The earlier frozen source uses the old block-return syntax. Its source-only
migration replaced 4,510 `return` tokens with `break` in 218 files, checked with
the real lexer; strings and comments remain unchanged. The original snapshot is
preserved. All 78 recorded entry/edit outcomes were remeasured, including the
expected `non_exhaustive_match` rejection for `tests/protocol.blot`.

## Qualification

`deno task test:compiler --resume --native-shards 4 --phase-seconds 2400 --budget-seconds 3600`
passes in 1,113.76 s. All 2,525 native tests execute with exhaustive allocation
failures in 1,028.47 s; all 1,640 guest/client checks pass in 48.15 s. Smoke,
harness, packaging and the final 26.03 s numeric development check pass; Zig
analysis has zero findings. The release compiler and native executable are
reused from verified build caches. The
[sanitized gate record](measurements/numeric-gate-2026-10-23.json) contains
phase times and executable hashes; private environment values are omitted.

## Numeric runtime and storage

The public synthetic campaign runs seven alternating pairs in each codegen tier.
Runtime timings use eager fixed-tier V8 compilation and raw scalar Wasm calls
inside the ordinary ownership boundary. Public `guest.call` separately checks
the same values. Allocation probes and memory-instruction instrumentation are
not timed. Direct/imported calls, known and unknown callbacks, Array/List rows,
nested edits, saved snapshots, constants, field order and F32 bits have executed
witnesses.

For 512 generated sixteen-F32 rows:

| Shape             | Baseline capacity, KiB | Candidate capacity, KiB | Baseline allocation bytes/call | Candidate allocation bytes/call | Optimized paired median CPU ratio |
| ----------------- | ---------------------: | ----------------------: | -----------------------------: | ------------------------------: | --------------------------------: |
| structural nested |                    256 |                     192 |                         155648 |                          188416 |                             0.950 |
| structural flat   |                    192 |                     192 |                         126976 |                          122880 |                             0.928 |
| nominal nested    |                    320 |                     192 |                         299008 |                          311296 |                             0.912 |
| nominal flat      |                    192 |                     192 |                          94208 |                          139264 |                             0.829 |

Capacity is warmed guest arena capacity, not live payload or process RSS.
Cumulative allocation includes reused arena storage and can increase even when
capacity falls. Optimized direct numeric adapters in this fixture allocate zero
bytes; development calls, unknown callbacks and escaping values retain the
ordinary boxed ABI. See [the layout contract](NUMERIC_LAYOUTS.md) for exact
admission and fallback rules.

The separate instruction observer reports zero `memory.copy` bytes in all four
512-row cases. Nested structural scalar reads/writes change from 616,764/391,684
to 653,564/399,612 bytes per call; nested nominal reads/writes change from
1,331,636/740,124 to 1,247,484/747,772. These are executed Wasm instruction
widths, not hardware memory traffic, cache misses, or a claim of universally
reduced copying.

No new allocation-free annotation is introduced. A checked allocation-free call
boundary would need transitive proof covering every reachable callee and runtime
helper; unknown calls and unproved helpers must reject or stay unproved.
Allocation remarks alone do not supply that proof.

## Application compilation and runtime

The LLVM compiler comparison runs seven alternating pairs for the game, devtools
and retained edit suite, plus one pair for every captured test entry.
Independent fresh edited builds validate retained results. Restart, no-op and
revert equality pass. The sole expected bookkeeping failure was the old manifest
association; the new entry hashes come exclusively from this complete run.

| CPU phase, ms           | Baseline median | Candidate median | Ratio of medians |
| ----------------------- | --------------: | ---------------: | ---------------: |
| Game fresh              |          3518.2 |           3564.8 |            1.013 |
| Game literal edit       |          1519.5 |           1519.6 |            1.000 |
| Game body literal edit  |          1281.8 |           1360.4 |            1.061 |
| Game body change        |          1711.3 |           1768.0 |            1.033 |
| Game imported body edit |          1778.3 |           1908.7 |            1.073 |
| Devtools fresh          |           970.7 |           1035.6 |            1.067 |

The fresh-game **median of paired ratios is 1.013**, within the existing 1.050
guard. These profiled CPU measurements include telemetry. Smaller retained
phases and devtools show regressions; this change does not meet the separate 500
ms fresh / 30 ms literal / 100 ms body targets. Seven first-edit pairs also do
not resolve task 086, which requires later edits and unaffected-constant CPU
attribution.

Fourteen Pen runs execute 600 deterministic frames each, discard the first 100
from frame distributions, and preserve every trace and final snapshot hash.
Paired median ratios are 1.003 for p50, 0.942 for p95, 0.913 for p99, 0.987 for
whole-process CPU and 0.972 for peak process RSS. This supports this workload
comparison, not a universal speedup or a significance claim.

## Rejected experiments

- Broad numeric inlining (two or more leaves, 128-node body budget) passed
  functional checks but failed the fresh-game compiler CPU guard: median ratio
  1.067 over three LLVM pairs. It is not the release policy.
- Requiring four leaves but retaining the flat 128-node budget still failed the
  native-backend screen: median ratio 1.073 over three pairs.
- The chosen policy requires four leaves and scales the budget to eight nodes
  per leaf, capped at 128. It preserves the ordinary small-helper limits and
  original positive reuse-budget laws.
- Compacting the numeric layout cache did not materially reduce measured backend
  allocation (727.58 to 727.70 MiB requested); the experiment was reverted.
- Lower Wasmtime inlining budgets reduced compilation memory but regressed frame
  p50 by about 14%/9%. Production defaults remain unchanged.

## Evidence and remaining work

Compressed raw JSON reports under `measurements/` preserve all paired samples,
compiler/source/library/harness pins, host/load information, allocation
measurements, instruction traffic, and rejected inlining screens.
`numeric-release-manifest-2026-10-23.json` pins each uncompressed and compressed
report. The application sources and assets remain in the private frozen capture;
no raw source is included in the reports.

Whole-application cold/warm startup is measured separately in Pen for issue 27.
The frame comparison above includes native module compilation in process
CPU/RSS, but it does not establish asset-loading or GPU-upload costs. These
remain separate acceptance work.

Issue 25 and the remaining CONTINUE milestones remain open: generic task-region
inference, tuple collection/selection, streams, typed exits, purity evidence,
checked workers, remaining iterator cases, later-edit attribution and the
compiler latency/allocation targets. This milestone does not claim the full
program is finished.
