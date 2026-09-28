# OxCaml performance work

The starting point for the first native optimization pass is
`b70958e8ed1444c36645c385f6eaba310500ab77`. Preserve its standalone installer,
package entrypoints, separate backend executables, and source/host contracts.

Measure compiler build time separately from source-to-Wasm throughput. Compare
baseline and candidate executables with the same OxCaml toolchain, flags,
programs, prelude, worker counts, and const budget. Alternate their execution
order and retain raw samples and executable hashes. Separate startup, full
compilation, incremental edits, and no-op reuse; do not use the synchronous
parity adapter as a throughput benchmark.

Prefer measured reductions in allocation and repeated traversal over mechanical
syntax changes. Keep compiler state immutable across workers and acknowledged
incremental revisions. Native representation changes must retain exact scalar
bits, Unicode identities, diagnostic ordering, Wasm bytes, and cache rollback.

Every accepted optimization needs focused regression tests and the existing
native/differential/standalone gates. Microbenchmarks explain a mechanism; only
source-to-Wasm measurements establish an end-to-end speedup. No performance gain
has been established for this pass yet.
