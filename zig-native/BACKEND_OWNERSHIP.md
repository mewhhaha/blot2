# Backend owners

`core_backend.Generator` coordinates one compilation. It owns the evaluator,
Wasm module, diagnostics and borrowed admission callbacks. Four owners hold the
state used by its backend responsibilities:

| Owner                           | Owns                                                                                                                              | Borrows                                                                                    |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `backend_plan.State`            | Code identity maps, runtime operation symbols and slots, startup order/facts, per-unit optimization proofs, Task mover identities | Live Core, evaluator IDs, layouts and output module                                        |
| `backend_static_data.State`     | Serialized-value cache and published static closure identities                                                                    | Live values, layouts and the output module; cache entries retain IDs, never table pointers |
| `backend_representations.State` | Physical layouts, substitution/instance identities and the optional semantic representation bridge                                | The bridge borrows the evaluator's evidence store                                          |
| `backend_emission.Owner`        | One function's resolved body, instruction plan, locals, scopes, cleanup stack and proof scratch                                   | The Generator and immutable mapping slices                                                 |

The representation bridge binds lazily after its owner has a stable address.
Generator teardown retires planning maps and proofs, the output module and the
representation bridge/layouts before the evaluator. Static cache teardown only
frees ID tables. Function emitters release their resolved plans, locals and
cleanup storage before the borrowed Generator leaves scope.

`CompileRun` owns a compilation attempt's admission gates, Generator, journal,
metadata, candidate view and optimizer capture. Callback pointers bind during
`prepare`, after the caller places this owner. Teardown follows reverse lifetime
order. Publication transfers journal/metadata/optimizer ownership to the result;
replay explicitly destroys the Generator before materializing the journal.
Resolved-body preparation, optimization, relocation and cleanup remain separate
phases. These modules own storage and work; there are no Generator forwarding
methods for the extracted operations.

The matched control includes evaluator storage owners (075), CoreBuilder (076),
auxiliary body metadata (024) and the proof-guard operand preparation
correction. The refactor preserves complete Wasm and non-timing work counters
for ordinary Cost, persistent record/List/Array callbacks and constant
aggregate/demand serialization, each through fresh, unchanged, edited and
reverted revisions. All three cold CLI allocation records are exact:

| Input                | Allocated bytes | Allocations | Peak bytes | Live bytes |
| -------------------- | --------------: | ----------: | ---------: | ---------: |
| Ordinary Cost        |       4,734,253 |      12,619 |  1,163,072 |          0 |
| Persistent callbacks |       3,973,727 |      11,887 |  1,124,784 |          0 |
| Static serialization |       3,516,344 |      11,042 |  1,096,108 |          0 |

These totals use fixed private input/prelude paths and cache-disabled CLI
processes. Compare matched rows rather than absolute totals from a different
harness. Retained API records compare solver/scratch allocation counters; they
do not claim total process allocation measurement.

`core_backend.zig` falls from 13,374 to 3,127 lines and Generator from 59 to 30
fields. The five production files total 13,626 lines after the bounded-slice
amendment, versus 13,374 before. Largest routine changes, counted through
matching braces:

| Routine          | Before | After |
| ---------------- | -----: | ----: |
| `compileAttempt` |    382 |    13 |
| `loopStatement`  |    290 |   103 |
| `serialize`      |    275 |    53 |
| `prepareNode`    |    242 |   106 |
| `arrayLocals`    |    181 |   102 |

The extracted compilation phases span 14–68 lines, loop phases 61–72, and the
largest serializer 96. Residual exceptions are explicit: `callable` (165),
`suiteSkip` (165), `operationFunction` (151), `apply` (149), `function` (131),
`requestLoop` (130), `emitHostDataSchemas` (123) and `planRuntime` (122). Each
keeps one dispatch or ABI/admission sequence together; further splits need an
independent responsibility rather than forwarding helpers.

Root focused qualification covers eight native ownership/query-lifetime laws
with complete allocation-failure sweeps and 38 executed guest groups. Complete
Wasm, ordered diagnostics, work and archive payloads match through five retained
phases. Root's fixed-path ordinary Cost record is 4,731,000 allocated bytes,
12,609 allocations, 1,162,755 peak bytes and zero live bytes; its 12,902-byte
Wasm is unchanged. Compare each record only with its matched control.

The agent's initial statement that all 17 changed Zig files had zero findings
was premature: that run had one static-data range-endpoint finding. Root changed
the serializer to slice the remaining words before applying the bounded chunk
length. Its affected-closure rerun verifies all 429 files with zero findings.
The original failed output and the correction remain in the qualification
artifacts. Final combined CPU qualification, ownership performance gates and the
full compiler gate remain required before claiming the complete milestone.
