# Zig compiler rebuild

This branch rebuilds Blot's compiler in Zig. The existing Bend compiler and Deno
APIs remain the reference and default until differential tests establish parity.
This is not a language redesign: syntax, accepted and rejected programs, effect
handling, const evaluation, Wasm behavior and the guest ABI must be preserved.

## Compatibility gates

- Parse and lower the current language, including imports, tags and source prelude.
- Preserve rank-1 type/effect inference and diagnostics for invalid programs.
- Preserve const evaluation, nominal types, associated dispatch and specialization.
- Preserve closures, algebraic data, tuples, records, immutable arrays and loops.
- Preserve source-declared effects, providers and explicit host capabilities.
- Emit valid Wasm with compatible entry roots and `blot:abi` metadata.
- Preserve stateless and incremental compiler APIs; no silent reference fallback.
- Run the existing regression suite and differential execution tests before
  switching the default compiler. A passing subset is not full feature parity.

## Migration approach

Keep the reference implementation unchanged. Add independently testable native
stages, exercise them against the existing implementation, and extend the same
pull request with fixes. Test the compiler itself in Debug and ReleaseSafe and
execute emitted modules in a separate Wasm runtime. Reject unsupported inputs
explicitly until their implementation and compatibility tests land.

The implementation and checked coverage are recorded here as the rebuild proceeds.
