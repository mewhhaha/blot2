# Compiler direction

Blot uses the handwritten Zig 0.17 compiler and its asynchronous
retained-project API. The targets for gdev are about 500 ms cold compilation and
under 100 ms incremental compilation, with language, effects, staging and guest
behavior preserved. Exact Bend API shapes and evaluation step counts are retired
by the owner's decision on 2026-10-05.

The current work and measurements are in
[zig-native/STATUS.md](zig-native/STATUS.md). Continue improving invalidation
precision, scratch ownership and artifact reuse only where measurements show a
benefit. Dependency bundles and retained modules must account for compiler
settings, nominal identities, provider/evidence selection and executed
compile-time code.

Use language fixtures, negative diagnostics, allocation-failure tests, executed
Wasm and fresh-versus-retained output comparisons as correctness gates. Keep
cold process timing, dependency population, first edit, subsequent edit, no-op
and failed-edit recovery separate. Parallelize only after measuring a useful
independent workload and including coordination costs.
