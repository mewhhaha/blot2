# Runtime representation boundaries

These public kernels reproduce the numeric-row and ownership costs reported in
issues #29–#36. `rows.blot` keeps the wide constructor behind an import, so the
construction case exercises the module boundary too. The two-field nominal and
flat structural cases are controls. Optional values exercise tagged numeric
rows; record/map/flatten pipelines exercise one-destination construction.
`acyclic-updates.blot` forces retained copies of nested plain data, reproducing
the missing acyclic marks found in gdev.

Run with two LLVM release compiler executables:

```sh
deno run -A scripts/bench/runtime_boundaries.ts \
  --baseline /path/to/before/blotc --candidate /path/to/after/blotc \
  --baseline-std /path/to/before/std \
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

For the same binaries in Wasmtime and Firefox, run the completed output
directory through the separate engine runners. The Python environment needs
`wasmtime`; its exact installed version is recorded. Firefox uses a temporary
profile with timer rounding disabled and deletes it on exit.

```sh
python scripts/bench/runtime_boundaries_wasmtime.py build/bench/runtime-boundaries
deno run -A scripts/bench/runtime_boundaries_browser.ts build/bench/runtime-boundaries
```

Both validate Wasm hashes, checksums and every production counter against the
Deno run, and alternate baseline/candidate samples. Python/Wasmtime invocation
overhead is included in that runner; Firefox measures its JavaScript host
boundary. Do not compare their absolute numbers as engine-only costs. Firefox
calibrates a shared batch per case to target at least 10 ms on the faster side
(capped at 100,000 calls), avoiding zero-duration samples from browser clock
quantization. Every row records that batch; it still uses 31 alternating
samples.

The baseline std directory matters: compilers predating `@array.flatten` must
use their original library. The current wrapper preserves eager flatten behavior
and allows the bounded pipeline proof to connect its stages. The candidate
retirement budgets require one Array for both optional generation/scalar reads
and the fixed rectangular pipeline. Saved intermediates, ragged lengths,
observable unused fields and unproved callbacks retain ordinary eager storage.

See the language guide for executed memory profiling and the checked
collector-free mode. Diagnostic profiles reserve their own memory; raw
uninstrumented timings, traffic and peak live bytes are separate measurements.
