# Runtime representation boundaries

These public kernels reproduce the numeric-row and ownership costs reported in
issues #29–#34. `rows.blot` keeps the wide constructor behind an import, so the
construction case exercises the module boundary too. The two-field nominal and
flat structural cases are controls. Optional values and record/map/flatten
pipelines remain separate, unresolved representation cases.

Run with two LLVM release compiler executables:

```sh
deno run -A scripts/bench/runtime_boundaries.ts \
  --baseline /path/to/before/blotc --candidate /path/to/after/blotc \
  --output build/bench/runtime-boundaries
```

The runner checks 28 independent checksums, zero roots and leases at each host
exit, and the repaired allocation/ownership budgets. It alternates the two
compilers for three fresh builds, then alternates the resulting Wasm modules for
31 warmed runtime samples per case (five invocations per sample). It records all
samples, exact executable and Wasm hashes, source/standard-library/client pins,
output sizes and production counter deltas. Results are written before work
starts and marked complete only after the final input checks.

Runtime measurements include the host ownership boundary and checksum check.
They use the same Deno/V8 engine for both modules and Blot's optimized codegen
tier, without an external `wasm-opt` pass. They are distinct from the reporter's
Node/external-O3 samples. No Wasm bodies are patched or instrumented.
Retirements and retain/release operations measure traffic, not peak live memory
or bytes. Compile timings include process startup and project opening. Three
builds are a local regression screen; application build cost is measured
separately with `bench:compile` and a frozen workload.

The optimized tier can share an identity-generated immutable array, load an
indexed scalar field directly, and remove temporary boxes through bounded
producer and selected-reader paths. Unknown callbacks and escaping values keep
owned materialization. No public ABI, language syntax or collection semantics
change. Development-tier semantic tests cover the same inputs.
