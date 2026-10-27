# Sol review: runtime and workload costs

Three GPT-6.1 Sol reviewers inspected runtime lowering, required validation,
and canonicalization/retained reuse. Four focused changes are implemented and
qualified. Paired runs against the original K1 release show **2.0–3.5× faster
compilation** across the nine largest accepted corpus points and **5.5× faster
retained body edits**. The chain runtime workload improved **38%**. Several small
runtime cases changed little or regressed slightly; this is not a universal
runtime speedup or a migrated `gdev` result.

## Implemented changes and safeguards

| Reviewed cost | Change | Regression evidence |
| --- | --- | --- |
| Every zero-byte source call and callable adapter loaded, checked, advanced and restored the frame frontier. | Omit that frame protocol when `own_frame == 0`. Public invocation preflight remains; instrumented calls read the incoming frontier for correct high-water attribution. | `wasm_runtime_test.ts`: zero/framed/zero call chain, captured values, early preflight trap, exact telemetry, repeated restoration and a generic Unit adapter with no frontier loads/stores. |
| Every block allocated program-sized ownership scratch, copied it per edge and scanned all Values on exits. | Allocate indexed scratch once per validation attempt; copy/scan/clear only affine values defined in the current block. Each sibling edge starts from the parent's state. | `test_validator_affine_scratch`: duplicate/drop rejection, independent siblings and impossible-block cleanup. `test_validator_unrelated_value_work`: adding 4,096 unrelated Share values does not inflate the function's ownership work. |
| Every canonical key zeroed two 131,072-entry U32 hash tables: 1 MiB before traversal. | Start with two 32-entry tables and grow with the reached graph, retaining the original capacity bound and exact byte/binder equality. | `test_canonical_growth`: forced growth, collision paths and Domain distinctions. A private original implementation also produced identical canonical bytes on the growth fixture. |
| Reusing one declaration initialized dozens of whole-source remap arrays and scanned entire tables to reserve/copy rows. | Use a bounded sparse `(table, id)` map and copy the reached queue sorted by table and source ID. Prepare/freeze the map before destination mutation; exact dependency projections remain. | `test_relocation_sparse_growth`: 128-op graph with 8,192 unrelated types. Existing malformed-cache, collision, forged-receipt, body-rebinding and rollback laws also pass. |

These are physical-work changes. Syntax, ABI and budget limits are unchanged.
Validation still charges the work it performs, including sparse copy/cleanup;
its visit counts decrease where global scans disappear. Canonical hash probes
use the existing private visit cap. Optional relocation may decline before
mutation; optional reuse never authorizes skipping source admission.

## Qualified candidate and measurement method

Full release gate: **95 native entries, 81 Deno integration tests, editor scopes
and 29 formatter round trips**. The Linux arena sweeps covered all 283 observed
construction boundaries, 271 decoder boundaries and 169 subsequent retained
revision boundaries for their respective fixtures. Every injected retained
failure preserved the previous output.

Current input manifest: `91d402345ffe5509f93f61642889c8422a3cfe65baac8f18836849250919b25f`.
Current release binary: `b54c172a659c9346604fb7dae5b8b76eb9852a96e9f962ce4ab858e5ab013292`.
Original K1 binary: `7b61cff1941de683e99269dc2a3c30cc137201d9bca8f98e90a8d0bbc02366b2`,
from `102963640f603cdcaf197c977357860b57f03c57` (compiler implementation `4d5fe603`).
The candidate was measured as changes atop that commit; the input manifest and
archived source contents identify it exactly.

[Qualification](results/sol-review/qualification.json),
[evidence manifest](results/sol-review/manifest.json) and
[raw sources/logs/samples](results/sol-review/raw-evidence.tar.gz) preserve all
runs and all 180 qualified inputs. [Initial K1 results](RESULTS.md) remain
historical and unchanged.

Host: AMD Ryzen 7 7800X3D, Linux 7.2.9-2-cachyos, Goose `a108677d`, Clang 23.1.1,
Deno 2.9.7 / V8 15.0.245.2-rusty. Host identity comes from the retained-run metadata;
Deno's paired CPU field reports unavailable. Jobs ran sequentially, with one
compiler worker. CPU affinity, frequency and filesystem caches were uncontrolled.
Both compilers receive identical K1 programs (only imported filenames differ),
`--opt=off`, and the same measurement harness. Each point has five pairs with
alternating order. Separate instrumented builds collect phase clocks. This
measures the four changes together; it does not isolate each change's speedup.

The runtime harness now resolves exports before timing and performs approximately
1,000,000 checksum-checked warmup calls before 500,000 timed calls per sample
(rounded down to whole export sweeps). It includes JS/Wasm crossings and required
entry wrappers. Tiering and call-site specialization remain uncontrolled. These
numbers must **not** be compared directly with the original report's short,
unwarmed runtime samples. Every accepted paired artifact executes and checksums.

## Fresh compilation

Milliseconds, median [minimum–maximum]. All 324 builds, including separate
attribution builds, passed. All scales 8/32/128 are in
[paired summaries](results/sol-review/paired.json); chains use 8/32/127 in
[chain summaries](results/sol-review/chains.json). The known 128-chain depth limit
is unchanged; its prior rejection evidence is preserved in the initial report.

| Family | Scale | Original K1 ms | Reviewed K1 ms | Speedup |
| --- | ---: | ---: | ---: | ---: |
| independent | 128 | 20.05 [19.43–20.82] | 9.98 [9.79–10.49] | 2.01× |
| calls | 128 | 20.01 [19.76–20.78] | 7.66 [7.47–10.32] | 2.61× |
| chains | 127 | 22.03 [20.45–23.35] | 9.58 [8.44–10.82] | 2.30× |
| diamonds | 128 | 79.24 [78.48–81.53] | 27.45 [27.40–29.73] | 2.89× |
| generics | 128 | 20.60 [20.10–23.00] | 8.64 [8.03–9.87] | 2.38× |
| closures | 128 | 35.49 [34.62–38.77] | 13.47 [12.81–14.15] | 2.64× |
| modules | 128 | 41.63 [39.20–42.69] | 18.67 [17.46–18.97] | 2.23× |
| proofs | 128 | 302.33 [294.88–307.58] | 109.89 [107.87–123.50] | 2.75× |
| domains | 128 | 89.04 [87.28–89.95] | 25.14 [24.45–25.39] | 3.54× |

## Wasm execution

Nanoseconds per exported call, median [minimum–maximum], from the same five
pairs. The chain sample sweeps all 127 exports, with source depths 1–127; it is
not 127-deep on every call. Diamonds improve as well. Simple scalar, generic and
closure calls show no broad runtime win; all samples and small regressions remain.

| Family | Original K1 ns/call | Reviewed K1 ns/call |
| --- | ---: | ---: |
| independent | 34.8 [33.6–35.7] | 36.4 [35.9–36.9] |
| calls | 38.1 [37.3–40.7] | 39.9 [38.1–41.2] |
| chains | 75.2 [74.0–80.1] | 47.0 [44.2–49.8] |
| diamonds | 116.4 [47.1–118.6] | 91.4 [86.3–92.9] |
| generics | 37.3 [34.6–50.3] | 37.1 [33.2–47.6] |
| closures | 54.3 [24.8–56.0] | 56.0 [25.6–57.5] |
| modules | 51.1 [50.5–54.3] | 50.4 [47.5–53.1] |
| proofs | 47.1 [46.0–51.9] | 49.5 [45.6–53.2] |
| domains | 23.4 [19.7–39.7] | 22.8 [20.3–39.5] |

The separately instrumented particle runs at lengths 0, 1 and 1,024 have exactly
the same counters as the original K1 binary: one reserve/release, zero live backing
on exit, 24,576-byte backing high-water and 256-byte scratch high-water. Initialized,
copied and result bytes also match. The gate still checks the unoptimized particle
loop's four loads, two stores, two multiplies, two adds and absence of loop calls.
The zero-frame optimization does not remove real frame storage.

## Retained edits

Five paired sessions, alternating process order, scales 8/32/128. Each session
receives ten ordered requests, including rejection and valid revert: 300 requests
total. All expected statuses and rejected-output preservation checks passed.
Milliseconds below are request wall times at 128 callers, including optional
cache admission, encoding and publication. Bridge requests use a separate fixed
fixture. [All summaries](results/sol-review/sessions.json).

| Revision | Original K1 ms | Reviewed K1 ms |
| --- | ---: | ---: |
| fresh | 37.07 [35.92–40.82] | 9.16 [8.29–9.75] |
| unchanged | 57.16 [56.79–57.77] | 11.16 [10.06–21.16] |
| body-edit | 54.49 [53.06–55.90] | 9.98 [9.12–12.93] |
| interface-edit | 48.58 [48.17–50.26] | 9.98 [8.72–10.34] |
| static-edit | 54.33 [53.94–54.47] | 9.08 [8.72–9.24] |
| rejected-edit | 5.88 [5.73–6.20] | 2.39 [2.38–2.75] |
| valid-revert | 53.51 [52.48–56.60] | 10.19 [9.80–11.11] |
| source-origins | 53.87 [52.83–56.39] | 9.82 [9.64–10.07] |
| bridge-first | 10.38 [9.67–10.77] | 4.47 [4.18–5.07] |
| abi-edit | 4.94 [4.82–5.31] | 2.33 [2.24–2.69] |

Unchanged builds still complete two staging bodies and reuse 129; body edits
complete three and reuse 128. The faster result did not come from declining reuse.
Unchanged still costs slightly more than fresh for these tiny bodies. Median
phase clocks are shown separately; medians of components need not sum to the
median request wall time.

| Unchanged phase | Original K1 ms | Reviewed K1 ms |
| --- | ---: | ---: |
| Old-cache decode/admission | 5.50 | 2.10 |
| Source completion/relocation | 17.05 | 1.69 |
| Planning/schema/keys | 13.93 | 0.94 |
| Candidate validation | 5.55 | 1.50 |
| Canonical encoding/copy | 11.59 | 1.28 |
| Publication | 2.29 | 2.22 |

## What remains expensive

Single separate attribution builds at scale 128; these are phase samples, not
paired wall-time medians. The large proof workload still spends about 72 ms in
required validation and 20 ms in source completion.

| Family | Plan ms, old → new | Validate ms, old → new | Validation visits, old → new |
| --- | ---: | ---: | ---: |
| independent | 6.86 → 0.65 | 5.48 → 1.32 | 208,438 → 159,158 |
| closures | 12.21 → 1.57 | 15.98 → 3.90 | 782,523 → 552,891 |
| proofs | 7.62 → 2.35 | 259.74 → 71.97 | 16,881,606 → 3,361,606 |
| domains | 30.60 → 5.20 | 47.41 → 10.55 | 3,549,408 → 1,828,192 |

The proof sample's source semantic visits remain 2,438,920, source proof visits
2,226,560, and validation proof visits 2,264,454. The removed work was repeated
ownership scanning, not removal of required proof reasoning. Next candidates
from the Sol review and integration inspection are **unimplemented**:

1. Index SSA operation positions and compute function CFG/dominance facts once.
   `use_value` scans preceding operations; `dominates` allocates program-sized
   state and searches the graph repeatedly. Preserve exact block/SSA/scope rules.
2. Index evidence by function, scope and obligation. Return checks currently scan
   all evidence; loan-conflict checks also retain global scans. Profile these
   helpers before assigning fractions of the remaining validation clock.
3. Index relocation metadata ownership once per revision. Sparse row remapping
   is implemented, but closure discovery still scans evidence, loops, interfaces,
   receipts and adapters; term interning still scans destination terms.
4. Retain immutable admitted Core directly. Unchanged requests still spend about
   2.1 ms decoding/admitting the private cache and 1.3 ms encoding it. Keep
   rollback and independent admission of external artifacts.
5. Reduce real frame materialization for register-flat aggregates and unnecessary
   edge scratch. Scalar generic adapters that cross the uniform ABI still need
   their spills. Removing them requires representation work, not just deleting
   the frame protocol.
6. Investigate Goose build iteration separately. The previous 37.36 s debug /
   57.67 s release measurements still identify a large development cost. This
   review did not change that driver or remeasure its full build matrix.

## Reproduce

Preserve/build the original K1 release as `build/review-baseline/blot`, build the
candidate with the pinned Goose, and run `scripts/check.sh --release` first.
Do not overwrite existing evidence directories when repeating measurements.

```sh
deno run --allow-read --allow-write --allow-run scripts/benchmark.ts \
  --families=independent,calls,diamonds,generics,closures,modules,proofs,domains \
  --scales=8,32,128 --rounds=5 --baseline=build/review-baseline/blot \
  --baseline-kind=k1 --runtime-warmup=1000000 --runtime-calls=500000 \
  --build-label=sol-review-release --out=build/bench-sol-paired
deno run --allow-read --allow-write --allow-run scripts/benchmark.ts \
  --families=chains --scales=8,32,127 --rounds=5 \
  --baseline=build/review-baseline/blot --baseline-kind=k1 \
  --runtime-warmup=1000000 --runtime-calls=500000 \
  --build-label=sol-review-release --out=build/bench-sol-chains
```

For retained sessions, use `scripts/benchmark_sessions.py --compiler=PATH` with
`--rounds=1 --scales=8,32,128`, alternating baseline/candidate order over five
outer rounds and separate output directories. The exact orchestrator and commands
are archived as `build/bench-sol-sessions/run.py`. Run telemetry with
`--output=build/sol-runtime-telemetry.json`, then
`python3 benchmarks/package_review.py` verifies and freezes the evidence.
Compiler iteration and operation-limit matrices remain in the initial report;
they were not repeated without a new implementation or measurement question.
