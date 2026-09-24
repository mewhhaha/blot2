# Compiler allocation and checking improvements

This implements the measured candidates from
[the larger compilation study](LARGE_LEVER_STUDY.md), plus its incremental
pending-constraint scan. It preserves the existing type system and uses Bend
2.0.27. The JavaScript backend remains a reference for the native kernels; the
checking and pending-constraint changes apply to both.

## Final gdev measurement

Five alternating pairs on the complete 16-module project, with a fresh native
process per sample at one worker, measured these medians after the final source
rebuild and tests:

| Measurement                 | Saved compiler |  Final compiler |
| --------------------------- | -------------: | --------------: |
| Compile call                |    1,487.35 ms | **1,181.87 ms** |
| Native CPU during compile   |       1,450 ms |        1,140 ms |
| Startup + loading + compile |    1,569.04 ms | **1,259.71 ms** |
| Native peak resident memory |     50,080 KiB |      49,276 KiB |

The compile-call median improved **20.5%**. Every pair improved; candidate times
ranged from 1,167.86 to 1,185.86 ms. No build or test jobs ran during this
measurement. These results remain far above the 100–200 ms target.

All ten samples emitted exactly the same 192,168-byte Wasm, SHA-256
`3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. The saved
native executable has SHA-256
`7207b96597f57b55930717c203d84d47c8901c6f7234bacbbac670937da643e9`; the
installed final executable has SHA-256
`7d479e0f4507772a42a8affba04df5d4472a38ab75bf669de2849e005e14cb93`. Raw samples
and logs are in `build/type-system-production/`.

An earlier isolated comparison measured the bounded active resolver's additional
contribution over the other combined changes: 1,204.67 to 1,174.45 ms
(**2.51%**) across five alternating pairs, all faster. Native CPU fell from
1,170 to 1,140 ms and peak memory remained essentially unchanged. This is a
separate measurement window; its percentage is not added to the final combined
improvement.

## Implemented paths

- `check_scheduler.bend` checks one representative of equivalent generated
  singleton functions within a dependency frontier. The complete input must
  match: source origin, body, annotations, nominal declarations, and imported
  interfaces. Lambda/block/return labels may share one uniform offset, compared
  with directional differences to avoid overflowing native label IDs. Operation
  declarations come from the same immutable catalog. Failed checks are repeated
  for each follower so diagnostics retain their original names and order.
- `monomorph.bend` retains the ordered unresolved requirements and scans only
  newly prepended definitions after selection. Raw requirements are resolved
  against the current substitutions each time. The cache relies on the existing
  append-only definition history and monotone choice map; an invalid prefix
  count falls back to a full scan.
- `scripts/native_kernels/index.c.inc` walks a String Patricia index in a native
  loop, consumes the selected path with the runtime's ownership operations, and
  releases the unselected branches.
- `scripts/native_kernels/free.c.inc` borrows type trees and constructs only the
  final free-variable list. It preserves the original ordered unions.
- `scripts/native_kernels/closed.c.inc` certifies that substitutions cannot
  change a type and transfers the original owned tree into the result.
- The bounded active resolver plans nested types in temporary storage addressed
  by small node IDs. It follows the same chronological substitution cursor, then
  constructs changed types once. It retains unchanged subtrees and leaves the
  original inputs untouched when preflight cannot certify the result.

The borrowed scans have fixed depth, node, fuel, and variable limits. A miss
uses the original Bend algorithm. There is no cross-request cache, disabled
reclamation, or change to the chronological substitution rules.

The active resolver handles single types with up to 256 plan nodes, depth 64,
and 16 children per product/application. It rejects open row tails and uses the
existing resolver for unsupported forms, large histories, or exhausted limits.
Native instrumentation on the full 16-module gdev compile recorded 102,638
attempts after the closed-type shortcut: 63,647 successes, including 15,853
changed types. The other successes transferred an unchanged type. These are
actual native counts; the instrumented executable is separate from timing runs.

This remains a bounded resolver improvement. Full compact type storage,
substitution-state regions, and general generic-body constraint reuse require
further implementation.

## Build contracts and regression coverage

`scripts/native_compiler_kernels.ts` and `scripts/native_owned_resolver.ts`
check the Bend version, relevant source definitions, constructor set, generated
field projections and dispatch shapes, and runtime ownership helpers before
applying the native transforms. Tests deliberately corrupt those inputs and
require the transform to reject them. Upgrading Bend requires reviewing these
contracts. The active resolver also pins the Nat integer domain, version
construction, and numeric-index layouts.

`frontier_reuse_regression.bend` covers successful equivalent checks, label and
annotation mismatches, imported and nominal types, source offsets, operation
catalog isolation, comparison limits, ordered failures, and certificate names.
`pending_cache_regression.bend` covers insertion order, resolved choices, prefix
shrinkage, and requirements whose variables acquire later substitutions. Both
run in the native build's regression executable at one and four workers. Eight
corresponding laws are recorded in `LAWS.bend` and proved in `PROOF.bend`.

The native API oracle compares repeated analyze/compile results, diagnostics,
and error recovery with the saved compiler. Separate differential probes cover
index snapshots, Unicode/prefix handling, free-variable order, fuel limits, and
closed/open row resolution.

Final validation passed:

- `bend PROOF.bend` and the combined native ownership/compiler regression at one
  and four workers.
- **696 compiler and transformer tests**, plus **24 gdev tests**.
- **104 native API operations** matching the saved compiler at one and four
  workers, including exact diagnostics and recovery after errors.
- Fresh differential C probes for all four kernels. The active resolver probe
  confirms that changed-type calls actually enter its optimized path.
- Near-limit label regressions for positive and negative shifts and a mismatch.
  The earlier cross-addition formula was separately confirmed to overflow on
  these valid labels; directional subtraction passes at one and four workers.
- Typechecking, formatting, and `git diff --check` for the changed tooling.

The final validation build staged proof, ownership, native, and JS work in
parallel and published after every gate succeeded. The ordinary build script now
emits its three independent JS reference modules concurrently as well.

## Reproduction

```sh
deno task build:compiler:all
deno test --allow-read scripts/native_string_compare.test.ts scripts/native_compiler_kernels.test.ts scripts/native_owned_resolver.test.ts
deno task test:native-kernels
deno run --allow-read --allow-run scripts/native_compiler_kernels_oracle.ts BEFORE AFTER
deno run --allow-all compiler/gdev_cold_bench.ts BEFORE AFTER 5 1 1
```

The benchmark creates a fresh compiler process and reloads the complete gdev
project for every sample, alternates binary order, verifies exact Wasm hashes,
and reports startup, project loading, compile-call time, native CPU time, and
Linux peak resident memory separately. Filesystem caches remain warm and the
Deno driver is shared; these are not cold-disk or Deno-launch timings.
