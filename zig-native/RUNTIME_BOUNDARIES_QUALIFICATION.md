# Runtime boundary repairs

Historical qualification, 25 October 2026 (`fdfaa89`). The follow-up batch is
documented in
[Runtime representation, attribution and collection](RUNTIME_MEMORY_QUALIFICATION.md).
The unresolved controls and measurements below describe this earlier compiler.

Issues #29, #30, #31 and #34 are fixed and correctness-qualified. The complete
compiler gate, zero-finding Zig lint, public runtime benchmarks and application
compile-cost screen pass. Broader representation, cycle-collection and
attribution work remains tracked separately in
[the issue triage](../ISSUE_TRIAGE.md).

## Changes

- Indexed scalar projections follow checked nominal/nested physical paths to one
  packed field load, preserving the original bounds check. Existing scope
  elimination removes the now-empty per-item ownership frame.
- A bounded forwarding producer exposes imported constructor bodies to the
  existing scalar replacement pass. The 96-instruction, 64-byte allocation and
  local-count limits remain unchanged.
- Up to four known selected readers receive guarded direct-call paths. The
  original descriptor selects the actual target and environment; the ordinary
  owned indirect-call fallback remains. A shared bounded scalar-reader proof
  supports internal branches and initializes locals that may otherwise retain an
  earlier loop activation's value.
- Exact identity generation shares immutable array storage. The same structural
  proof denies fresh ownership of the result and exclusive mutation of its
  source. It follows checked forwarding wrappers and records their dependency
  bodies for retained compilation. It never trusts a function name.
- Previously pending owned-array changes admit exclusive consumers in disjoint
  branches and fresh outer Array slice/concat buffers. Their original regression
  laws are included in this candidate's complete qualification.

No public ABI, language syntax or observable collection semantics change.
Unknown/escaping callback values retain owned materialization. This does not
implement a universal unboxed callback ABI, inline multi-constructor sums,
record/map/flatten fusion, executed source attribution or a collector-free
language mode.

## Regression coverage

The permanent guest laws cover development and optimized tiers, imported
constructors, selected/captured/unknown callbacks, escaping results and copies,
immutable snapshots after edits to either alias, nested arrays, suspended
values, array/list boundaries, trap recovery and exact F32 bits. Native laws
cover forwarding rejection, local initialization, frozen Core and allocation
failures. Existing ownership, strong-cycle and cancellation laws remain in the
full gate.

The existing generator cost law now expects two retirements after its temporary
environment disappears. The SIMD worker fixture reads a runtime bias to keep it
outside pure-reader inlining; its vector-worker, spill and boxed-table
assertions remain intact. The first full-gate attempt stopped on the old
worker-count expectation. The updated law passes its exhaustive fault sweep
independently.

The public [28-case benchmark](../benchmarks/runtime-boundaries/README.md)
checks independent numeric witnesses and ownership budgets, records unmodified
Wasm and pins its inputs. It keeps optional variants and record pipelines as
unresolved controls. Diagnostic Safe/noLLVM timings from implementation are not
release performance results.

## Release runtime and code size

31 alternating warmed samples (five invocations each) use LLVM release
compilers, Blot's optimized Wasm tier, and Deno 2.9.7 / V8 15.0.245.2-rusty on
an AMD Ryzen 7 7800X3D, Linux. No external `wasm-opt` or body instrumentation is
used. These are local kernel measurements, distinct from whole-application
runtime and the issue reporter's Node/O3 numbers.

| Kernel                                            | CT116 milliseconds | Candidate milliseconds | Retired objects before → after |
| ------------------------------------------------- | -----------------: | ---------------------: | -----------------------------: |
| Selected nine-field reader, 2000 rows × 100 scans |            15.4794 |                 1.1187 |                    404,001 → 1 |
| Indexed scalar read, 2000 rows × 100 scans        |             2.0659 |                 0.1819 |                      4,001 → 1 |
| Imported nine-field construction, 2000 rows       |             0.1526 |                 0.0060 |                      4,001 → 1 |
| Reference scratch, 512 closures × 2000 iterations |            26.2337 |                 0.0486 |                    6,513 → 513 |

Reference scratch performs 512 retains and 1,025 releases independent of the
iteration count; CT116 performs 2,052,512/2,059,025 at 2,000 iterations. All 28
checksum cases and their ownership budgets pass. Optional numeric variants still
retire 6,001 objects; the record/map/flatten pipeline still retires 6,005.
Neither remaining case is claimed fixed.

The exact indexed inner loop now contains its bounds-length load and one scalar
field load. It has no root-open/root-close calls or other row-field loads. A
guarded cycle safe point remains; the optimization does not suppress collection.

The combined 28-kernel module grows from 21,561 to 22,912 bytes (+6.3%). Three
alternating fresh builds, including process startup/opening, have medians of
13.19/13.74 ms. These small-program compile timings are a screen, not a claim of
compiler latency improvement. All repeated outputs within each compiler match.

Raw samples and hashes:
[public result](../benchmarks/results/runtime-boundaries-2026-10-25.json).
Baseline compiler SHA-256:
`ea9d15eaac5479c0697c1dc40834475f4a713801b085ecd43692892609c4fe82`. Candidate
compiler SHA-256:
`b127325a76a2990b04aed39434c8a692483888af4c1b69dc07d62d645a9aeabf`.

## Application compile cost

Three alternating release pairs use the frozen 554-file, 189-module gdev
snapshot. The candidate intentionally emits different Wasm. Within-compiler
repeatability, retained/revert parity, fresh edited controls and unchanged input
pins all pass; the paired fresh CPU guard is 0.982 against a 1.050 limit.

| Scenario     | CT116 wall | Candidate wall | CT116 CPU | Candidate CPU |
| ------------ | ---------: | -------------: | --------: | ------------: |
| Fresh        |    7.011 s |        6.852 s |   7.670 s |       7.530 s |
| Literal edit |    3.135 s |        3.142 s |   3.360 s |       3.380 s |
| Body edit    |    5.401 s |        5.491 s |   5.540 s |       5.640 s |

The fresh gdev module grows from 5,230,730 to 5,300,353 bytes (+1.3%). These are
three-pair regression screens, not evidence of an ordinary-edit speedup. Fresh
peak RSS medians are 493.04/491.52 MiB. Literal-revert CPU rises 4.5%;
retained-population CPU rises 2.3%. The sub-second edit goal remains open.

## Correctness qualification

`deno task test:compiler --oom-profile --native-shards 4` passes all 2,601
native laws with 1,693 exhaustive allocation-failure sweeps, 1,668 release
guests, 48 smoke tests and 57 tooling tests. No guest tests are skipped. The
full gate takes 756.02 seconds. Native compilation uses Zig 0.17.0 Safe/noLLVM;
only the final release compiler uses LLVM. Whole-source Zig lint reports zero
findings.

The root compiler source and tests match the frozen candidate. Documentation
updates follow qualification; the guide's executable examples are unchanged. The
candidate includes the previously pending owned-array branch and fresh
slice/concat changes. The prior CT116 frontend work is committed separately as
`9ff812b`.

## Portable evidence

The [evidence archive](measurements/runtime-boundaries-2026-10-25.tar.gz)
contains SHA-256-verified gate/shard logs and inventory, source pins, lint,
compile samples/results, runtime samples, exact Wasm/disassembly, public
fixture, runner and host metadata. Its `manifest.json` verifies every payload.
The frozen application snapshot is private and is represented by input hashes
and measurements, not source. Documentation prose was finalized after
qualification; compiler code, executable tests, benchmark inputs and their
measurements remain pinned to the tested candidate.
