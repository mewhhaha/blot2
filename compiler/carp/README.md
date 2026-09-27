# Carp compiler experiment

This is an additive rewrite, not yet a replacement for the Bend compiler.
The existing compiler, public APIs, test suite, source language and Wasm ABI
remain the compatibility contract. Never silently delegate unsupported Carp
inputs to Bend or report partial coverage as feature parity.

## Toolchain

Carp 0.6.0 is pinned to `56d7115e289896d16bbb753c39383dac12811339`.
Set `CARP_DIR` to that checkout and put its `carp` executable on PATH.
The GitHub Actions job builds the toolchain, caches it, and publishes diagnostic
artifacts. No generated C or JavaScript is patched.

## Migration gates

1. Establish a reproducible native Carp build and ownership-safe compiler data.
2. Port a complete source-to-Wasm slice with execution and rejection tests.
3. Grow the slice against the existing parser/lowering/inference/const/Wasm tests.
4. Cover rank-1 types, inferred constraints, effects/providers, closures, ADTs,
   multi-value and value patterns, tuples, records, arrays, imports, tags,
   source operators, entry reachability and the host ABI.
5. Preserve bounded evaluation, diagnostics, deterministic output, incremental
   invalidation, failed-request recovery and the existing host-facing APIs.
6. Only replace the default compiler after the full compatibility suite passes.

Measure compiler rebuild time separately from source-to-Wasm throughput. Use
identical input corpora and release/development build settings in comparisons.
The baseline is commit `832e92be7ef227be202771d582d4cdd16967561f`.
