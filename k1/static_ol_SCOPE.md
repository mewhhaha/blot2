# Private static metadata/layout metering

This scratch path extends `static_om_pipeline`: it charges the shared ordered
meter before each of five selected shape-validation expressions, before reading
the row and width fields, and before each of seven image metadata comparison
expressions. It preserves short-circuit behavior and charges only an expression
that is reached. Its fixture event policy is not the complete C09 cost table.
Failures return no Wasm from the pipeline.

At O0/O2, tests cover each expression's exhaustion cutoff, each early mismatch,
whole-pipeline cutoffs, 120 baseline target comparisons and Wasm execution.
The multi-page control exercises only the inherited target emitter/checker.

Runtime vector growth and allocations, implicit source/value copying, Goose's
`bytes_of`/`from_bytes` and their generated verifier/allocator internals remain
outside the meter. `bytes_of` itself provides a view; `from_bytes` generates a
verified owned array. The meter cannot observe their internal work from Goose
source. The parser and target emitter have other metadata/layout operations,
and generic types, proofs, resources, packages, manifests and ordered C09
coverage are still incomplete. Metering those internal runtime operations
requires changes to the Goose runtime/compiler or replacement with explicitly
metered primitives. No public ABI, K1 Domain or complete C09 receipt is claimed.
