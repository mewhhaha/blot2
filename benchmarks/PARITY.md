# K1 performance parity investigation

The rewrite is approaching the legacy compiler on this synthetic corpus, but
has **not reached parity across compilation and runtime**. This work keeps the
K1 plan: explicit interfaces, one ordinary generic body, independent validation,
fixed storage and bounded optional optimization. No syntax or ABI change was
needed.

## Implementation

Three Sol agents implemented and cross-reviewed these changes; root integrated
the shared work and qualification:

- Index CFG incoming edges, operation positions and exact dominance queries per
  validation pass. Incoming-edge authority still includes unused hostile edges;
  successful cached answers cannot cross function budget accounts.
- Index every function's ABI plans and every operation's adapters. Validation
  checks all matching rows, including a malformed duplicate after a valid row.
- Reuse layout scratch with fresh root epochs. Root-specific traversal, budget
  accounting and cycle detection stay intact; geometry is not reused across
  independently charged roots.
- Index values and dictionary contexts by function in both realization and the
  independent coverage checker. Concrete substitutions still compare exactly.
- Use one bounded SCC traversal for strict proof cycles and indexed complement
  edges. Materialize derived Fact/Evidence rows only for successful proof paths.
  Private recipes never replace ordinary independently checked evidence.
- Share frontend interning scratch across modules in one candidate, seed newly
  finalized suffixes, and clear it after failure. Module budgets, evidence and
  revision ownership remain separate.
- Borrow immutable indirect parameter slots, lower small unmerged return trees
  into structured control, and compact unused emitted Wasm locals. Parameter
  slots, local types and default zero initialization are preserved. The emitted
  bytecode and certificates are still independently validated.

The earlier [Sol review](SOL_REVIEW.md) already removed zero-frame pointer
traffic, global affine-value scans, oversized canonical indexes and dense
relocation maps. Its results and input snapshot remain unchanged.

New laws cover epoch-isolated layout work, dictionary scaling, forged producer
order, unused CFG edges, dominance collisions/exhaustion, duplicate layout rows,
lazy evidence and proof exhaustion, cross-module interning/rebinding/failure,
compound generic slots, local zero initialization and exact F32 bit behavior.
The dictionary fixture's 16 → 64 caller growth takes 357 → 1,413 charged visits.

## Method and preserved evidence

Linux, Ryzen 7 7800X3D, pinned Goose
`a108677d300cb0e8bbb842c35a353abe67a20c6c`, Clang 23.1.1, Deno 2.9.7 / V8
15.0.245.2-rusty. Native candidates use Goose's release build, without custom
CPU flags. Legacy is the installed Zig release at
`1e39b5d8a4268b9edf769c2813d5231abe1c963b`, executable SHA-256
`fd2119f5528cb164131e1156d35ba97c434393647f1b326ae5aa154db137d923`.

Each matrix uses five counterbalanced pairs, sequential compiler processes,
scales 8/32/128 and explicit one-worker legacy compilation. Chains stop at 127:
the 128-depth control was already rejected by the specified limit. K1 uses
`--opt=off`; legacy uses its default pipeline. Equivalent source spellings are
generated for each edition. Every artifact executes and checks its answers.
Runtime uses pre-resolved exports, one million checksum-checked warmup calls and
approximately 500,000 timed calls, including the JS/Wasm boundary. Compiler
phase clocks are collected in additional instrumented processes, separately
from wall/CPU/RSS timing samples.

CPU placement, frequency and filesystem cache are uncontrolled. Later paired-K1
and release-tier runs encountered substantial contention: a subsequent load
observation was 21.16 on the 16 logical CPU host. All samples remain recorded.
Use paired ratios and ranges; do not compare absolute times from different
batches as if the environment were fixed. These are synthetic workloads, not a
migrated `gdev` measurement. Compiler rebuild times were not rerun.

The [first package](results/parity/manifest.json) pins 185 qualified inputs,
104 native tests, 84 Deno tests, editor checks and 1,429 records spanning the
before/intermediate/final compiler matrices, retained sessions and diagnostic
controls. Its qualified compiler is
`96ad70d96ecc03847508fcf4f49fcd3885fdbccd647e9d96cb3aeca25fbdd420`.
The intermediate `38a407…` candidate and its full input/gate snapshot are also
archived. The local-compaction probe used a debug native compiler and is
**runtime-only evidence**, never a release compile-time comparison.

## Latest release after fixing publication

Fresh-build medians now meet or beat legacy in **six of nine families at the
largest measured scale**. They remain behind for modules, guarded arithmetic
and static domains. This does not establish statistical significance for small
differences or parity for other programs. The current qualified compiler is
`f84aa746934c4b9ef5cc818bf7402f19f07beffb63b558000d30c0cccdbdb14a`,
input manifest `d42b6dc43bd0acd831f0316921995e12536d5b465d8524933a3902a53fed6012`.
Its full gate passed **104 native tests, 85 Deno tests, editor scopes and 29
formatter round trips**. The [publication package](results/publication/manifest.json)
adds 693 fresh/retained records to the preceding immutable evidence.

Final default-engine medians, scale 128 except chains 127:

| Family | Compile legacy / K1 (ms) | Runtime legacy / K1 (ns) |
| --- | ---: | ---: |
| Independent functions | 5.28 / 4.97 | 24.32 / 24.48 |
| Shared callee | 5.63 / 5.23 | 23.28 / 27.21 |
| Chain, 127 | 9.10 / 5.71 | 27.54 / 44.12 |
| Diamonds | 19.77 / 18.03 | 23.37 / 50.59 |
| Generic identity | 5.61 / 5.40 | 16.40 / 37.52 |
| Captured closures | 11.77 / 9.15 | 49.85 / 34.99 |
| Imported modules | 11.04 / 13.23 | 23.19 / 31.11 |
| Guarded arithmetic | 23.90 / 31.34 | 29.52 / 26.19 |
| Static domains | 7.40 / 15.81 | 43.55 / 30.87 |

[Full ranges and paired ratios](results/publication/final.json),
[chain results](results/publication/chains.json) and CPU/RSS samples are archived.
Guarded-arithmetic runtime is again sensitive to variation: the median paired
ratio is 1.071 despite the favorable ratio of aggregate medians. Independent
runtime is near equal (paired ratio 1.006). Diamonds, generics and chains remain
slower by paired ratios of 2.17×, 2.07× and 1.60×. Captured closures and static
domains are faster by paired ratios of 0.719 and 0.723. The post-run host load
observation was 4.99; this is not per-sample control of contention or frequency.

The final additional change is ordinary Wasm publication. The pinned Goose
`os.write_file_atomic` synchronizes both the staged file and its parent directory;
legacy's CLI uses ordinary file writes. A preload diagnostic timed the real
`fsync` calls without skipping them: over five workspace/tmpfs pairs, workspace
sync waits had median 2.095 ms within a 5.074 ms CLI total. The same program on
`/tmp` took 3.006 ms total with 0.00155 ms in synchronization. A preceding single
workspace sample took 12.29 ms in sync waits. These are filesystem attribution
samples, not end-to-end speedup estimates.

The new OS adapter completely writes and closes a sibling temporary file before
atomic rename. It preserves existing permissions/new-file umask and prior bytes
on reported errors, removes temporary files, and rejects symlink/nonregular
outputs. It omits file/directory sync: success promises complete visible output,
not durable media acknowledgement or detection of every delayed writeback error.
This matches the [publication contract](../docs/CONTRACT.md#transport-publication-and-observations).
Explicit Core output, paired Core/Wasm transactions and source-formatting output
retain their existing synchronization paths. Retained revision commit still
follows successful publication. Syntax, checking and emitted Wasm are unchanged.

The [publication-only K1 pair](results/publication/k1.json) verifies identical
Wasm bytes for every timed case. Fresh compile medians before → after include
independent functions 7.56 → 5.24 ms, shared calls 7.66 → 5.22 ms and generic
calls 8.05 → 5.70 ms. No runtime gain is attributed to this patch. Runtime
variation with identical bytes is another reason not to overread tiny samples.

The [retained publication pair](results/publication/sessions.json) compares the
preceding qualified K1 with the final release, at 128 callers:

| Request | Before ms | After ms |
| --- | ---: | ---: |
| Fresh session | 7.96 | 6.16 |
| Unchanged | 9.51 | 7.61 |
| Body edit | 8.65 | 7.06 |
| Interface edit | 8.35 | 6.49 |
| Static edit | 8.24 | 6.48 |
| Rejected edit | 1.83 | 1.81 |
| Valid revert | 8.86 | 7.07 |
| Source origins | 9.01 | 7.04 |
| Bridge first request | 3.74 | 2.35 |
| ABI edit | 2.18 | 0.64 |

These are not retained-protocol comparisons against legacy. All failure/recovery
responses, runtime checksums and particle storage counters pass. CLI clocks now
separate setup, required pipeline, artifact encoding and publication. In the
final independent-function attribution sample those costs were 0.164, 2.554,
0 and 0.102 ms, respectively, inside 2.822 ms of CLI time. Process startup and
teardown are outside that clock, included in the separate wall-time sample.

## Before the publication fix

The first qualified candidate produced these scale-128 medians (chains 127),
with both compilers measured together. Units are ms for compilation and ns per
exported call for runtime. Ranges and per-pair ratios are in
[the matrix](results/parity/final.json) and
[chain control](results/parity/final-chains.json).

| Family | Compile legacy / K1 | Runtime legacy / K1 |
| --- | ---: | ---: |
| Independent functions | 4.82 / 9.35 | 22.62 / 23.93 |
| Shared callee | 5.44 / 9.17 | 23.23 / 26.78 |
| Chain, 127 | 8.06 / 7.10 | 23.10 / 39.65 |
| Diamonds | 17.86 / 20.07 | 22.53 / 59.75 |
| Generic identity | 5.56 / 7.44 | 15.76 / 30.25 |
| Captured closures | 10.24 / 10.74 | 46.61 / 33.29 |
| Imported modules | 10.42 / 14.36 | 21.91 / 27.94 |
| Guarded arithmetic | 20.64 / 30.21 | 27.40 / 22.75 |
| Static domains | 7.20 / 16.78 | 38.73 / 27.09 |

The guarded-arithmetic runtime distributions vary: its median **paired** K1 /
legacy ratio is 1.025 despite the favorable ratio of aggregate medians. Treat
that case as near parity in this run. The clear default-engine runtime gaps are
diamonds (2.67×), generic identity (1.91×) and chains (1.70×).

A separate [prior-K1 comparison](results/parity/final-k1.json) uses identical
source, flags and runtime loops on both binaries. Paired median runtime ratios
for independent/shared/diamond/generic calls were 0.704/0.729/0.649/0.703.
Proof completion visits fell from 2,226,560 to 534,912; required validation
visits from 3,361,606 to 558,150. Static-domain validation visits fell from
1,828,192 to 395,938. These deterministic work reductions support the timing
results without depending on host load.

The [retained matrix](results/parity/sessions.json) compares the preceding K1
release (`b54c172…`) with this candidate, not the different legacy protocol.
At 128 callers, body-edit medians were 8.87 → 8.12 ms and unchanged requests
9.47 → 8.86 ms. Publication was still using the synchronized writer here.

## Where compiler time remains

Final release phase samples, scale 128, milliseconds:

| Family | Load | Complete | Plan | Validate | Lower |
| --- | ---: | ---: | ---: | ---: | ---: |
| Independent | 0.21 | 0.44 | 0.46 | 1.02 | 0.43 |
| Diamonds | 0.94 | 4.08 | 4.36 | 4.00 | 4.47 |
| Modules | 2.01 | 3.37 | 2.17 | 4.31 | 1.06 |
| Guarded arithmetic | 1.04 | 10.18 | 1.43 | 11.44 | 3.63 |
| Static domains | 0.37 | 2.14 | 3.34 | 5.54 | 2.16 |

These samples are attribution, not medians or subtraction from unrelated wall
samples. Native `gprof` attribution of the earlier `38a407…` candidate assigned
61.8% of static-domain sampled self CPU to `validate_layout_premises`, motivating
the ABI-plan/adapter indexes. Its instrumented profiles and exact commands are
in the first package. Short independent-function processes accumulated no CPU
samples; their call counts alone cannot establish a CPU bottleneck.

## Runtime engine and optimizer controls

The [optimizing-engine control](results/parity/final-optimized-engine.json) runs
the same generated Wasm with Deno `--v8-flags=--no-liftoff`. Median runtime ns:

| Family | Legacy | K1 |
| --- | ---: | ---: |
| Independent | 14.75 | 14.76 |
| Shared callee | 14.73 | 14.14 |
| Diamonds | 14.88 | 13.43 |
| Generic identity | 14.91 | 20.50 |
| Guarded arithmetic | 17.70 | 18.84 |
| Static domains | 31.04 | 18.06 |

This control helps isolate engine behavior; it does not replace default-engine
results. Generic overhead persists even under the optimizing engine. The
existing `--opt=release` tier produced byte-for-byte identical Wasm to `off` for
shared calls, diamonds and generic identity. Its timing run encountered high
host load and supplies no useful tier speedup claim. Adding the flag alone does
not remove these costs.

## Remaining work in the plan

1. Apply the already specified bounded release inlining policy to small call
   graphs. Preserve argument evaluation, effects, captures, evidence and
   resource preflight; revalidate every candidate. Keep the baseline independent
   of optional success. Limits remain 32-operation callees, depth 2, 16 sites,
   and growth at most 25% of the caller capped at 256 operations.
2. Reduce generic slot/adapter work within the single-body ABI, and separately
   evaluate legal identity forwarding. Do not reintroduce representation-based
   specialization. Measure both default and optimizing Wasm engines.
3. Profile the remaining proof-evidence traversal and static-domain planning.
   Any cache must respect exact context and independently charged accounts;
   required admission cannot become a trusted producer marker.
4. Measure startup/arena construction and retained transport separately from
   output publication. Build iteration remains a separate Goose/C-driver task;
   the historical 37.36 s debug / 57.67 s release figures are not updated claims.

The plan supports these next steps without further syntax changes. Performance
parity is a measured target, not a completed specification law.

## Reproduction

Run `scripts/check.sh --release` with the pinned Goose before measuring. For the
final paired matrix:

```sh
deno run --allow-read --allow-write --allow-run scripts/benchmark.ts \
  --families=independent,calls,diamonds,generics,closures,modules,proofs,domains \
  --scales=8,32,128 --rounds=5 --baseline=/path/to/legacy/blotc \
  --baseline-kind=legacy --runtime-warmup=1000000 --runtime-calls=500000 \
  --build-label=publication-final-release --out=build/bench-publication-final
```

Run chains separately with `--families=chains --scales=8,32,127`. The K1
publication comparison uses `--baseline=build/parity-before-publication/blot
--baseline-kind=k1 --scales=128`. The retained pair's complete runner and all
per-process commands are archived at `build/bench-publication-sessions/run.py`.
The optimizing-engine command adds `--v8-flags=--no-liftoff` immediately after
`deno run`; it is a separate diagnostic, not a default-runtime result.

`benchmarks/package_parity.py` freezes the earlier investigation;
`benchmarks/package_publication.py` freezes the final follow-up and verifies
its relationship to that prior package. Both validate qualification/input/binary
hashes and all expected samples/checksums, archive raw source/log/evidence, and
refuse to overwrite a published directory. The follow-up additionally verifies
that publication did not change any paired K1 Wasm bytes or guest storage
counters. Generated compiler executables, generated C and Wasm/Core files are
excluded from archives; hashes remain in the records.
