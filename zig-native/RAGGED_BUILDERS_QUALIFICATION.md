# Ragged builder qualification

The implementation follows [the reviewed specification](RAGGED_BUILDERS.md).
Runtime and staged construction share a bounded proof; the existing final
List/Array allocator and ordinary evaluator own filling. The count pass borrows
immutable inputs and skips payload evaluation. It uses fixed scratch, no
decision tape and a 1,048,576-visit limit. Exhaustion starts ordinary execution.

Selected typed scalar operations qualify through at most eight capture-free
forwarding adapters. Every adapter body is an executable dependency. An edit
that preserves its function type still invalidates the primitive proof.

The initial implementation conservatively declines division/remainder, including
F32, numeric conversions that may trap, indexing, allocating payloads, effects,
unknown calls, generic iterators and regions beyond the proof bounds. The staged
scratch adapter accepts bind, wildcard and product patterns; unsupported pattern
execution keeps ordinary evaluation. These are optimization boundaries, not
additional language restrictions.

## Checks

Zig 0.17.0 was checked before every build batch. Focused native filtering ran 29
matching laws; ten focused executed-Wasm laws pass against development and LLVM
release binaries. Coverage includes dependent bounds, filters, qualifier order,
four dimensions, reversed/empty ranges, exhausted probing, complete checking of
unreachable payloads, packed List leaf crossings, immutable snapshots,
shared/cyclic children, closures and strong memo copies. Demanded bounds, guards
and payloads, plus runtime-selected demand callbacks and an opaque callback
retaining a memo, report zero runtime/staged admissions and preserve Foreign
first-use traces.

Native laws exhaust compiler/staged/retained-edit allocation failures and
compare every ordinary logical-fuel boundary, including selected source
adapters. Staged growth at 0, 1, 8, 32 and 128 preserves source steps and
publishes exactly K children. Frozen Core remains unchanged. Successful ordinary
child/value/depth budgets still succeed. Stable-type adapter edits, failed
revisions and recovery match fresh builds. A guest constrained to four memory
pages rejects a large output, preserves established input and subsequently
builds a small output.

A checked shared-product type exercises the real million-visit evidence limit.
Speculative fact preparation restores its prior diagnostic on a decline; zero
ranges and false guards preserve empty output and source fuel. One step below
ordinary completion preserves the original diagnostic and span. OOM still
propagates. Imported control globals whose numeric binding IDs equal local loop
IDs retain their qualified identity. A real checked collision preserves
admission, output and staged fuel; retained imported-value edits match fresh
executed-Wasm output.

The initial full default gate passed native laws and 770 guest laws, but found
one compiler allocation budget regression. Keeping the private count state in a
scoped stack borrow restored all eight compile budgets; it stores no pointer in
a durable plan or artifact. A corrected full default gate passed native laws and
all 772 guest laws. The final gate includes the evidence-limit and
qualified-reference safety fixes and passes native laws plus all 773 guest laws
(4m26s for the guest batch). The superseded no-LLVM full run was stopped, not
passed. Zig analyzer checked 327 files with zero findings. Deno type checks and
local Markdown target checks pass.

## Measurements

The ordinary LLVM release differs only in the private default
`CompileOptions.ragged_builders = false`; both binaries contain the same
implementation. Compiler SHA-256:

- Ordinary: `776a22e60570c4c638e7dce61114030bcfd15bf66d122c2783915808e9e91493`.
- Candidate: `9d52d6ec52a463fb1fb2e1b3b683f01e5cf8609f233650267f67da8cd6d9a6c3`.

[The harness](../scripts/bench_ragged_builders.ts) pins compiler,
standard-library and input bytes. The final batch contains 15 alternating warmed
pairs for each of 68 runtime cases and seven pairs for fresh, first retained,
edit, no-op, failure and recovery: 136 runtime rows and 84 compilation rows. It
runs on CPU 7; host load was 3.97→4.46 while correctness/build work used other
cores. Earlier 55-case and 68-case batches independently passed the same
measurement gates. Raw samples, pins, Wasm and metrics are retained under
`build/bench/ragged-builders/{qualification,list-qualified,final-qualified,safety-qualified}`.

Construction timing invokes unmodified Wasm directly, without host decoding or
input-copy cost; runtime globals initialize before measurement. List output is
consumed through intrinsic length. Separate telemetry adds only exports for
existing allocator globals; executable instructions and layouts stay unchanged.
Traffic counts rounded allocated block bytes, including fixed traversal buffers.
Arena high-water includes temporary storage and allocator rounding, excludes
pinned inputs and is an upper bound on peak live bytes. Active header counts are
physical blocks still present after a call, not allocation-event counts.

| Case                         |      K | Median CPU µs ordinary → candidate | Candidate wall median/p90 µs | Arena high-water bytes ordinary → candidate |
| ---------------------------- | -----: | ---------------------------------: | ---------------------------: | ------------------------------------------: |
| Triangle Array, N=256        | 32,640 |                 1,322.000 → 69.625 |              69.636 / 72.435 |                           401,408 → 131,072 |
| Triangle List, N=256         | 32,640 |                1,351.875 → 180.625 |            184.164 / 213.884 |                           270,336 → 143,616 |
| 50% filter, C=16,384         |  8,192 |                   185.500 → 39.734 |              39.914 / 44.084 |                            133,248 → 65,536 |
| Two-word rows                | 16,384 |                   924.750 → 42.812 |              42.883 / 44.612 |                           532,992 → 262,144 |
| Four-word rows               | 16,384 |                 2,108.625 → 59.250 |              59.310 / 80.801 |                         1,065,984 → 524,288 |
| Existing references          | 16,384 |                   418.125 → 27.594 |              27.667 / 27.865 |                           266,496 → 131,072 |
| Packed List input            | 16,384 |                   951.750 → 41.750 |              41.944 / 42.889 |                           533,504 → 262,688 |
| Nested List inputs, C=65,536 | 32,640 |                1,621.500 → 508.500 |            511.408 / 544.363 |                           402,432 → 132,096 |

All twelve large cases with K≥1,000 pass the 10% median CPU regression gate; CPU
ratios range from 0.028 to 0.458. Large-case CPU/storage improvements exceed
10%. Admitted Array cases retain one active final payload block. Range/Array
counting allocates no traversal heap. Packed List counting/filling needs 544
bytes of peak scratch beyond the rounded output: a fixed walk plus the existing
two-row buffer. Nested scalar Lists need 1,024 bytes at depth two. Scratch stays
bounded by active depth, but reactivation has real allocation traffic: the N=256
nested case requests 394,240 rounded block bytes, including 263,168 traversal
bytes across both passes. It still improves on ordinary 532,992 bytes. These
fixed per-activation buffers are permitted by the specification; they are not
per-payload row allocations or a decision tape.

The staged 32-row triangle reports 5,158 raw probe visits, K=496 selected and
496 published children, with identical 14,586 total ordinary source steps for
the complete compilation workload. Native growth laws check exact O(K) final
children and one publication copy independently of compiler frontend peak.

| Compilation phase | Median ms ordinary → candidate | Added ms |
| ----------------- | -----------------------------: | -------: |
| Fresh             |                10.015 → 10.723 |    0.708 |
| First retained    |                11.225 → 12.352 |    1.127 |
| Edit              |                  7.572 → 8.275 |    0.702 |
| No-op             |                  0.512 → 0.578 |    0.066 |
| Failed edit       |                  3.847 → 3.749 |   -0.097 |
| Recovery          |                  7.044 → 7.662 |    0.618 |

Fresh/edit phases pass the agreed 5% or 2 ms gate through the absolute
allowance. Final fresh/edit relative overhead is 7.1%/9.3%. The earlier batch
measured a retained-edit regression of 19.9% (+1.678 ms); relative compile
overhead is visible and is not claimed to disappear. Fresh compiler peak remains
1,200,085 requested bytes; allocation traffic grows from 5,774,767 to 6,173,838
bytes and allocation calls from 22,366 to 22,757. No reduction in whole-compiler
peak is claimed.

All-filtered C=16,384 costs 9.325→16.830 µs CPU with identical 32-byte storage.
The exhausted C=1,048,577, K=0 case costs 288.094→681.984 µs, a 2.37× regression
(earlier batches: 2.35× and 2.42×). Counting is bounded, but does extra work
before ordinary fallback. Broader admission or a different probe policy requires
further measured qualification.

## Main integration qualification (11 October 2026)

Implementation `2226d50` jointly includes tasks 043 and 050 over qualified 031.
Zig 0.17.0, Deno 2.9.7: `deno task test:compiler` passes the full native suite
and 807 guest/client laws (6m21s guest phase), with all eight allocation budgets
unchanged. `deno task lint:zig` with the pinned local analyzer checks 336 Zig
files with zero findings. The staged tree remained
`fccba545f83a668fc3c75bcfbd916c3fbebe20fe` through this gate. Release SHA-256:
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127`;
compiler-identity file SHA-256:
`15cc1fda4ca4969090b5876a2f181813e4b9ff889bc288851984d6bfe3371a96`. Ignored gate
logs and input patches are retained in `build/bench/joint-043-050/`.
