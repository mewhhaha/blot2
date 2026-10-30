# CT114 frontend checking and measurements

CT114 compacts generic-requirement storage, skips unused sharing summaries for
predicate-free schemes, and adds whole-project checker counters. The profiled
fresh frontend median is 1.872 → 1.784 s; checking is 1.421 → 1.344 s. Checker
allocation requests fall 27.0% and requested bytes 17.6%. Unprofiled whole-build
measurements do not establish a latency improvement. These are instrumented
clocks, separate from the unprofiled comparison below. The sub-second fresh
frontend target remains open.

## Implementation and scope

Each generalization now owns one candidate table and two variable buffers.
Candidates contain numeric spans rather than separately allocated slices.
Type-component scratch is reused between candidates. Predicate-free schemes
retain all their type/effect quantifiers and ordinary instantiation; only
sharing metadata that cannot be used is omitted. The whole-project counters
exclude checker invocations during backend inference. See
[the work record](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILER_CT114_WORK.md).

Zig was already the only compiler. TypeScript hosts its client, CLI, guest API,
formatter and derive source generator. README and API documentation now make
that boundary explicit. No language syntax changes are introduced.

The candidate is frozen qualified CT113 plus these changes. Concurrent changes
in `backend/owned_arrays.zig`, `backend/owned_arrays_tests.zig` and
`tests/owned_array_execution.test.ts` are excluded. This qualifies the frozen
candidate, not the combined working tree. CT110 remains installed; these changes
are uncommitted.

## Release comparison

The final LLVM ReleaseFast compiler SHA-256 is
`58d73ef3620dc6ba3c895b38865cb4a56b852441195ee9b5de833baa4e7c829f`; its identity
digest is `8d62e3ad75a0c701c53f1cc5186ae4ef16eac39a7bc06d6c2085e5fa516a2fdd`.
The source manifest pins 1,004 files against HEAD
`e56375d18f32b0aef300fb4b80b9a3c0f2c1632d`. The baseline is qualified CT113,
SHA-256 `7643273aebdf572fded1f0dc1c4b354e26d89cd8316c5249067dd675c4dc47e5`.

Three alternating instrumented pairs use the frozen 554-file gdev snapshot, 189
game modules, four codegen workers, ordinary serial semantics, optimized output,
a 200-million inference budget and no disk cache. Every fresh output matches its
strict CT103 Wasm pin; input pins agree before and after.

| Profiled phase | CT113 median | CT114 median |
| -------------- | -----------: | -----------: |
| frontend       |    1871.7 ms |    1783.9 ms |
| check          |    1420.7 ms |    1343.6 ms |
| lex            |      27.5 ms |      25.6 ms |
| parse          |      15.7 ms |      15.4 ms |
| lower          |     151.2 ms |     147.1 ms |
| freeze         |      92.5 ms |      91.4 ms |
| validation     |     127.4 ms |     127.1 ms |

The whole frontend sums every exclusive phase except backend. Profiling adds
overhead, including allocation accounting: fewer allocations can reduce that
overhead as well as compiler work. These clocks do not establish the same gain
in an unprofiled frontend.

Checking allocation requests are 7,636,643 → 5,573,343; requested bytes are
1,078,511,978 → 888,829,730. Requested bytes measure allocation traffic, not
retained memory or RSS.

A separate unprofiled three-pair screen records 60 samples with no overlapping
local build or test. Strict outputs, independent fresh controls, frozen inputs
and the CPU guard pass. Shared-host noise and the small sample count limit
generalization; this is a screen, not a seven-pair optimization qualification.

| Scenario            | CT113 wall median | CT114 wall median | Median paired CPU change |
| ------------------- | ----------------: | ----------------: | -----------------------: |
| game Fresh          |           7.356 s |           7.701 s |                   -1.18% |
| game Literal edit   |           3.228 s |           3.237 s |                   +0.00% |
| game Literal revert |           2.918 s |           2.873 s |                   -1.43% |
| game Body edit      |           5.616 s |           5.570 s |                   -1.29% |
| game Body revert    |           5.526 s |           5.574 s |                   +0.38% |
| devtools Fresh      |           0.776 s |           0.759 s |                   -2.56% |

Fresh wall time rises despite a small paired CPU reduction, and literal-edit CPU
is unchanged. No whole-build or ordinary-edit latency improvement is
established. Peak RSS medians are 485.8 → 484.6 MiB fresh, 704.7 → 701.5 MiB on
the literal edit and 761.0 → 760.3 MiB on the body edit; these small changes do
not demonstrate a large retained-memory reduction.

## Remaining architectural work

The checker still scans 3,421,572 pending positions across 9,281 scheme
constructions and imports 90,541 schemes across 189 modules. Only 7,089 imported
bindings are directly read, but other imports may support shared callees,
coherence and publication. Do not treat that difference as proven removable
work. The changes leave semantic type nodes at 2,665,378.

A trial query cache recorded 161,744 hits but saved only twelve graph visits
beyond compact storage. It is removed. Its sources, passing selected checks,
strict profile outputs and cancelled full-gate evidence are preserved
separately; the cancelled run is not qualification. An earlier compact-candidate
screen also precedes the final checked span conversions and is not the final
result.

The [frontend architecture review](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILER_FRONTEND_REVIEW.md) proposes
direct instantiation from immutable producer interfaces, requirement dependency
tracking, and fewer copies across checked/Core/frozen boundaries. Those changes
remain unimplemented. Lexing/parsing are already a small part of the frontend;
Baba's useful lesson is shared analysis and deferred copying.

## Verification and evidence

The compact-storage development cycle passes in 29.72 s: all 2,589 native laws
compile with Safe/noLLVM, 36 selected laws run with sampled allocation failures,
three executed guest tests pass, and formatting/types/lint pass. Final checked
span conversions are covered by the full gate. Final Zig lint checks 522 source
files plus the build file with zero findings.

The exact final candidate passes the full gate: 2,589 exhaustive native laws,
1,660 release guest tests, 48 smoke tests and 57 build-harness checks. The audit
verifies 17 native journal artifacts and 1,688 full allocation sweeps with zero
sampled sweeps. Full gate elapsed time is 767.04 s. It reuses unchanged build
artifacts and reruns native execution in full. This is not a fresh or isolated
compiler-build benchmark.

The first final-candidate run used two native shards and exhausted its
1,100-second native-phase budget after 2,135 passing laws, with no reported test
failures. It is recorded as incomplete. The successful run uses four shards and
a larger budget; no partial native sweep is accepted as a pass.

Raw measurements, source pins, exact patches and qualification journals are
under `build/bench/ct114`. The portable archive is listed below. Binaries and
private workload sources are excluded.

Evidence: [archive](measurements/ct114-frontend-checking-2026-10-25.tar.gz), 204
files / 2,314,753 bytes, SHA-256
`b93642ec504585ae87087e77c822b59ccd61ad97ce60816082ef38caf9639568`. Every
archived manifest entry is verified. It includes the final full gate, the
timed-out run, rejected query-trial sources, preliminary and final screens,
source pins and compiler patches.
