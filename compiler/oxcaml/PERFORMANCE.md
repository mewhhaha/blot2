# OxCaml performance work

## First native allocation pass — 2026-09-28

Baseline: `b70958e8ed1444c36645c385f6eaba310500ab77`, including the standalone
installer, package entrypoints, and separate native backend executables. The
measurement-plan commit `b24d4d187f17314829277348a6df4a84f55482f6` changes no
compiler code. Both local executables were built from this source with the same
actual OxCaml 5.2.0+ox compiler, default flags, and domain backend.

This pass removes two artifacts of the Bend migration, not language features:

- Name equality returns a boolean directly, short-circuits on shared immutable
  tails, and checks module identity before nominal name identity. It no longer
  allocates an ownership-carrying `NameComparison`. OxCaml checks these hot
  functions with `[@zero_alloc strict]`; no unchecked allocation assumption is
  used. The old owning helper remains available as a regression-test oracle.
- `char32 = Chr of int32 [@@unboxed]` retains exact 32-bit values and the typed
  constructor but removes its redundant wrapper. It does not normalize Unicode,
  change strings to UTF-8, or alter the native protocol or Wasm representation.

No mutable interning table, worker scheduler, public host interface, installer,
Bend source, or generated Bend C/JavaScript was changed.

## Allocation measurements

On this 64-bit build, `bench_names.ml` measures **32 -> 0 allocated bytes per
name comparison**. The result includes physical sharing, separately allocated
equal strings, early mismatches, and shared suffixes. Building 100,000 text
characters measures **64 -> 48 allocated bytes per character**. The latter is
25% less allocation for that construction operation, not 25% less compiler RSS.

The new native unit suite has 6,614 checks: comparison against the old helper,
Unicode and embedded NUL, distinct normalization spellings, nominal ownership,
raw character bits, shared tails, 200,000-character names, randomized inputs,
and allocation guards. Running it against the baseline fails the per-comparison
allocation guard, as intended. Default OxCaml compilation also checks the strict
no-allocation annotations.

## Paired source measurements

The experiment uses the repository's **12 existing synthetic compiler
workloads**, with **1 and 4 requested workers**, **7 alternating baseline /
candidate pairs** per workload/worker combination and 2 warmups. Every pair
checks complete artifacts/analyses, Wasm execution, incremental histories, and
non-timing cache counters. All checks passed. Neither timed side runs Bend or
the synchronous JavaScript mirror adapter.

Environment: Linux x86-64, AMD EPYC 9V74 virtual CPU, 5 visible logical CPUs
with a 4-CPU quota, Deno 2.9.7, OxCaml 5.2.0+ox (Flambda 2). This is a shared
virtualized development machine, not the user's machine. No other local build or
test suite ran during the paired experiment. Flags are unchanged:
`-g -w -8-11-26-27 -I +threads -I +unix`.

Ratios below are geometric means of the **24 per-case median ratios** (baseline
/ candidate). Greater than 1 is faster. The time change is
`100 * (1 / ratio - 1)`; it is not a pooled application wall-time measurement.

| Phase                                   |  Ratio | Time change |
| --------------------------------------- | -----: | ----------: |
| First compile in a fresh native process | 1.033x |       -3.2% |
| Repeated source-to-Wasm                 | 1.009x |       -0.9% |
| Pre-encoded native request              | 1.118x |      -10.6% |
| Source analysis                         | 1.037x |       -3.6% |
| Incremental body edit                   | 1.050x |       -4.7% |
| Unchanged incremental request           | 1.027x |       -2.7% |
| Compiler/frontend startup               | 1.005x |       -0.5% |

The clearest result is lower native-request time and deterministic allocation
removal. **Repeated end-to-end compilation is effectively flat in this run**; it
includes frontend and transport work unaffected by this patch. Results are
mixed: several four-worker cases regress, including `reader_64` edits and
`lexical_256` full builds. These are retained below, not discarded. Seven
samples on shared hardware do not establish a statistical confidence bound or
guarantee a speedup for every program.

A native request here includes native decoding, compilation, response encoding,
and pipe transport, with a common pre-encoded frontend payload; it excludes
source parsing and host response decoding. A fresh-process compile excludes
startup and is not a cold OS page-cache run or fresh Deno runtime. Unchanged
requests mostly measure the existing host cache.

| Workload                   | Workers | Full baseline ms | Full candidate ms | Native request ratio | Body edit ratio |
| -------------------------- | ------: | ---------------: | ----------------: | -------------------: | --------------: |
| lexical_256                |       1 |          181.319 |           165.170 |               1.031x |          1.029x |
| lexical_256                |       4 |           97.996 |           113.176 |               1.050x |          1.103x |
| nominal_256                |       1 |           42.257 |            38.134 |               1.167x |          1.274x |
| nominal_256                |       4 |           39.936 |            40.646 |               1.105x |          1.106x |
| shared_frontier_diamonds_8 |       1 |          138.999 |           130.813 |               1.052x |          1.076x |
| shared_frontier_diamonds_8 |       4 |          101.772 |            93.317 |               1.169x |          1.101x |
| reader_8                   |       1 |            4.441 |             4.166 |               1.210x |          1.216x |
| reader_8                   |       4 |            4.857 |             4.724 |               1.095x |          0.927x |
| reader_64                  |       1 |           31.053 |            30.278 |               1.159x |          0.956x |
| reader_64                  |       4 |           30.685 |            30.667 |               0.897x |          0.871x |
| balanced_64                |       1 |          329.039 |           330.316 |               1.098x |          0.969x |
| balanced_64                |       4 |          175.449 |           178.081 |               0.969x |          1.098x |
| uneven_64                  |       1 |           69.781 |            74.188 |               1.128x |          1.107x |
| uneven_64                  |       4 |           50.623 |            53.369 |               1.201x |          1.046x |
| clustered_64               |       1 |           73.267 |            72.088 |               1.113x |          1.010x |
| clustered_64               |       4 |           55.941 |            54.144 |               1.028x |          1.001x |
| chain_64                   |       1 |            8.620 |             8.122 |               1.176x |          1.059x |
| chain_64                   |       4 |            8.473 |             8.612 |               1.158x |          0.965x |
| diamonds_8                 |       1 |          134.868 |           134.735 |               1.130x |          1.041x |
| diamonds_8                 |       4 |           95.420 |           100.658 |               1.340x |          1.019x |
| shared_root_diamonds_8     |       1 |          140.821 |           134.349 |               1.153x |          1.032x |
| shared_root_diamonds_8     |       4 |           88.791 |            93.631 |               1.124x |          1.122x |
| staggered_64               |       1 |           56.287 |            56.765 |               1.083x |          1.142x |
| staggered_64               |       4 |           52.337 |            50.569 |               1.294x |          1.009x |

All raw timing samples, including startup and analysis, are committed in
[the CSV](measurements/2026-09-28-names.csv). Rows preserve paired sample order;
within each row the order alternates baseline-first and candidate-first. Timing
values are milliseconds rounded to six decimal places. The full JSON produced by
the harness additionally records per-workload source and Wasm hashes, cache
counters, runtime identity, and completion state.

Executable SHA-256 values from this experiment:

```text
baseline  a70ac4cd0de69d4bee72d10a16f5ab86b48ad7c0211b1f777350803faed1a151
candidate 4013555dc41ee8bb3ba6c74f10799bfdcc77ea256d39280fc1e484596733a424
harness   55331528b42c1e7cceac5a1b910de8b1d7767e08653b961a14df4ae59eec7ee7
workloads e744ec7c5f9b37f51f83aee9395153cba0a6a7615cdcab70b50a5d73d7618f81
```

These hashes identify the local binaries, not future rebuilds on other paths or
machines. The measurement began at 2026-09-28T16:39:15.772Z. Compiler build time
was not compared in this pass; no compiler-build speedup, Bend-native speedup,
application speedup, or peak-memory reduction is claimed.

## Follow-up on noisy cases

A separate run retested the two prominent four-worker regressions (`lexical_256`
full builds and `reader_64` edits) plus `nominal_256` as a positive comparison,
with 9 pairs each and otherwise identical settings. These cases were selected
after the primary run, so this is **not** a second unbiased full-suite
aggregate. The first run remains unchanged above.

| Workload (4 workers) | Full ratio | Native request ratio | Body edit ratio |
| -------------------- | ---------: | -------------------: | --------------: |
| lexical_256          |     1.080x |               1.097x |          0.939x |
| reader_64            |     1.109x |               1.089x |          1.173x |
| nominal_256          |     1.134x |               1.184x |          1.175x |

The previously observed full-build/edit regressions did not repeat, but the
lexical body-edit result changed from an improvement to a regression. This
supports treating these short end-to-end timings as variable, not claiming a
universal speedup.
[Follow-up raw samples](measurements/2026-09-28-names-confirmation.csv) retain
all nine pairs for each of the three reported phases.

## Local correctness gates

On the exact candidate executable hashed above: **934 regression tests passed, 0
failed, 2 privileged scheduling checks ignored** across 158 unchanged
compiler/script files. The mirror recorded 862 source operations (838 reached
the native core), 524 successful results, 338 matching diagnostics, and **0
mismatches**. Low-level IR tests still exercise the reference and are not
counted as native source comparisons. The additional four-worker corpus passed
630 comparisons (346 artifacts and 284 diagnostics), and all 25 standalone
source/Wasm/incremental smoke checks passed.

Native unit, concurrency, framing, and eight incremental-build checks also
passed with actual OxCaml. The new paired benchmark is exercised by CI with
identical executables; CI timing is not treated as a performance threshold.

## Reproduce

Build the baseline in a separate checkout at the commit above and retain its
`compiler/oxcaml/_build/blotc`; build this candidate with the same toolchain and
flags. Do not run the two builds concurrently with the timed experiment.

```sh
make -C compiler/oxcaml test test-build
make -C compiler/oxcaml bench-names
deno run -A compiler/oxcaml/bench_compare.ts \
  /path/to/baseline/blotc compiler/oxcaml/_build/blotc \
  build/oxcaml-paired.json 7 1,4
```

The benchmark uses no reference compiler. It accepts an optional workload-name
substring after worker counts. CI exercises it with the same executable on both
sides and does not fail on noisy timing thresholds. The ordinary native,
differential, and standalone gates remain required; low-level IR-only tests
still exercise the unchanged reference and are not native parity evidence.

## Next profiling targets

Keep optimizing measured allocation and traversal rather than mechanically
adding language extensions. Candidate areas are compact/interned immutable
identifiers and dense indexes, followed by transient IR construction. A future
stack-allocation or unboxed-product change needs its own escape/lifetime review,
allocation measurements, and source/incremental parity checks. Large real
projects and repeated measurements on dedicated hardware are needed before
making an application-performance claim.
