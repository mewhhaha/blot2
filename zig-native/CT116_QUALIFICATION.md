# CT116 frontend qualification and benchmarks

Fresh profiled frontend time falls from 1.600 to 1.036 s; checking from 1.214 to
0.649 s. Checker allocation requests fall 51.1% and requested allocation bytes
fall 15.7%. These are instrumented phase measurements, distinct from the
unprofiled build timings below. See
[the work record](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILER_CT116_WORK.md).

## Implementation

Pending-requirement dependency watches avoid repeating unchanged type/row walks.
Rollback, physical writes, future IDs and slot reuse invalidate answers;
projection-bearing queries retain their original transition charges. Ordered
inference lists use sparse membership indexes for larger sets and the standard
library's vectorizable scalar search for smaller sets. No independent SIMD
speedup is claimed, and the lexer has not been rewritten.

Completed live interfaces share immutable analysis metadata; consumer IDs remain
fresh and private. Frozen or unpublished metadata takes the original path.
Canonical imported graphs are still copied. Full direct-from-producer
instantiation is not implemented by this change.

Fresh independent modules run in joined dependency-ready batches, with private
solvers, diagnostics and budgets. Symbols and completed interfaces are immutable
until join. Missing generated names, diagnostics or combined budget exhaustion
release speculation and replay the original serial order. Four workers are the
default; `frontendWorkers: 1` / `--frontend-workers 1` selects serial checking.
Retained edits, source validation, editor queries and small projects retain
their existing paths. This policy is separate from evaluator semantic workers.

## Release measurements

Three alternating profiled rounds use the same 554-file frozen gdev input, 189
modules, optimized output, four codegen workers, ordinary evaluator semantics, a
200-million inference allowance and no disk cache. Every output matches the
strict CT103 Wasm pin. All input and compiler hashes agree before and after.

| Phase, milliseconds |  CT114 | CT116 serial | CT116 four workers |
| ------------------- | -----: | -----------: | -----------------: |
| frontend            | 1599.6 |       1331.3 |             1036.0 |
| check               | 1214.0 |        941.7 |              648.7 |
| lex                 |   22.2 |         23.2 |               27.2 |
| parse               |   12.9 |         13.3 |               15.8 |
| lower               |  134.1 |        132.3 |              129.7 |
| freeze              |   82.9 |         78.6 |               79.5 |
| validation          |  121.9 |        111.5 |              111.1 |
| backend             | 5688.4 |       5533.9 |             5679.5 |

The frontend is the sum of all exclusive phases except backend. Worker clocks
are not added to coordinator elapsed time. Allocation traffic is not live heap
size or RSS. Profiling and allocation accounting affect the measured clocks.

A separate three-pair unprofiled screen covers fresh builds, literal/body edits,
reverts and independent fresh controls. Strict outputs and the fresh CPU guard
pass. No local build/test runs overlap these measurements. This is a shared-host
screen, not a seven-pair performance qualification.

| Scenario                    | CT114 wall seconds | CT116 wall seconds | Paired CPU change |
| --------------------------- | -----------------: | -----------------: | ----------------: |
| game fresh                  |              7.594 |              7.050 |            -1.81% |
| game edit:literal_in_body   |              3.285 |              3.234 |            -0.87% |
| game revert:literal_in_body |              2.954 |              2.977 |            -0.35% |
| game edit:body_change       |              5.615 |              5.556 |            -1.41% |
| game revert:body_change     |              5.460 |              5.545 |            +2.28% |
| devtools fresh              |              0.783 |              0.672 |            +1.23% |

The whole frontend remains just above one second. Literal/body edit timings
remain around 3.23/5.56 s; this screen does not establish a meaningful ordinary-
edit speedup. Fresh peak RSS rises from 483.5 to 491.8 MiB, so lower allocation
traffic is not a demonstrated retained-memory saving. Backend work still takes
about 5.68 s in the profiled builds and dominates the whole compilation.

The public eighteen-program Blot/Rust comparison measures fresh compilation and
same-engine Wasm execution, with independent output witnesses. See the
[README table](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/README.md#idiomatic-blot-and-rust-benchmarks),
[methodology](../benchmarks/idiomatic/README.md) and
[raw report](../benchmarks/results/ct116-2026-10-25.json). Do not generalize the
small-program compile times to gdev or other whole applications.

Blot compiles the small public programs in about 6–10 ms, versus Rust's 42–83
ms. Rust's runtime median is lower in every case, from a near tie for GCD to
roughly 139× for decimal formatting. The list pipeline is about 133× slower in
Blot and CSV numbers about 90×. These results include collection, text and
ownership representation differences; they do not isolate a backend instruction-
selection cost. Runtime profiling is the next step before attributing the gaps.

## Qualification and reproducibility

The final LLVM ReleaseFast compiler SHA-256 is
`ea9d15eaac5479c0697c1dc40834475f4a713801b085ecd43692892609c4fe82`; its identity
file SHA-256 is
`164d3a27766d302c851481fd70ad6c98ecb6cd0b45bdb67b5a197490c21a690f`. The source
manifest pins 1,221 files, including native fixtures and public benchmark
sources, against HEAD `e56375d18f32b0aef300fb4b80b9a3c0f2c1632d`.

The full gate passes 2,596 native laws compiled with Safe/noLLVM, with 1,692
full allocation sweeps and zero sampled sweeps. Raw native inventory and 17
journal artifacts are verified. Full gate time is 687.33 s. 1,660 release
guests, 48 client smoke tests and 57 build-harness checks pass; final Zig lint
has zero findings. The final candidate's exact counts and commands are retained
in the gate logs.

An initial isolated run lacked checked-in native fixtures and failed
compilation; they were restored from the qualified baseline. A mistakenly
started combined- checkout run was cancelled. Neither incomplete run is a pass.
The final gate uses the complete frozen candidate and a separate journal.

The candidate is qualified CT114 plus CT116. Concurrent `owned_arrays.zig`,
`owned_arrays_tests.zig` and `owned_array_execution.test.ts` changes remain
preserved and excluded. This qualifies the frozen candidate, not the combined
working tree. No syntax change, commit, push or installation is included; CT110
remains installed. Raw evidence is under `build/bench/ct116`.

Portable evidence:
[archive](measurements/ct116-frontend-and-language-benchmarks-2026-10-25.tar.gz),
148 files / 1,352,151 bytes, SHA-256
`96b246fd34793e193ebeb0abe77fe5c98490735bd7920db0e04eea4ef0355abb`. All archived
manifest entries are verified. It includes the exact CT116 source patch,
source/compiler pins, full qualification and development records, policy
screens, raw language samples and incomplete earlier attempts. Compiler binaries
and private workload sources are excluded.
