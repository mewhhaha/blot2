# Memory and concurrency experiments

Starting point: `e18ad178d9aea326dad4d8d626b688f25805a191`.

This pass investigates compact scalar/text representation, transient allocation,
request transport, and structured fork/join scheduling. It does not change the
language, host ABI, package installer, or incremental rollback contract.

Each retained change needs executable correctness checks and a native-to-native
comparison with identical inputs/toolchain. Allocation, resident memory, compiler
build time, native-request time, and source-to-Wasm latency are different metrics.
Failed and inconclusive experiments belong in this report too. No performance
claim follows from the use of a language extension alone.

The source and toolchain snapshot produced by this commit is the reproducible
starting point. Results and implementation decisions are pending experiments.
