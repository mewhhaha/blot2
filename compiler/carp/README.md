# Carp compiler experiment

A native, standalone Blot-to-Wasm compiler written in Carp. This branch is an
**additive rewrite, not a feature-complete replacement**. Existing compiler
commands continue to use Bend; no original compiler, source library, host API,
or test has been removed. Unsupported Carp inputs fail explicitly. The Carp
binary never invokes Bend, Deno, Node, an assembler, or a fallback compiler.

## Build and run

Use Carp 0.6.0, pinned to `56d7115e289896d16bbb753c39383dac12811339`,
with its source checkout in `CARP_DIR`, `carp` on PATH, and a C compiler.
The current native host supports 64-bit POSIX targets. Node 22.16+ runs tests
against the existing TypeScript guest adapter; it is not a compiler dependency.

```sh
bash compiler/carp/build.sh debug
# Or: bash compiler/carp/build.sh release

generated/carp/blotc-carp build examples/carp_scalar.blot build/answer.wasm
generated/carp/blotc-carp check examples/carp_scalar.blot
node --experimental-transform-types compiler/carp/test.mjs
```

The output directory must exist. A failed compile preserves any existing output.
`--const-steps N` bounds constant evaluation (default 100000; maximum 10000000).
These implementation limits are not yet the same as the reference compiler's.

## Implemented milestone

- Byte-oriented layout lexer and Pratt parser; comments, CRLF, explicit scalar
  annotations, default numeric precedence and direct unary-argument calls.
- Unit, Bool, U32 and F32, monomorphic scalar inference, forward declarations,
  direct recursion and mutual recursion. No implicit numeric conversions.
- `do`, lexical `let`, rebinding/`self`, `if`/`else`, nearest-block returns,
  range loops and `for ever`, with loop-carried values and scoped shadowing.
- Bounded const evaluation, cycle detection and entry-root reachability.
- Direct binary Wasm emission and the scalar portion of `blot:abi` version 2.
  Tests instantiate results through the unchanged `compiler/guest.ts` adapter.
- Wrapping U32 arithmetic; F32 rounding, signed zero, NaN/infinity and saturating
  conversions; deterministic output; atomic output publication.

The default numeric operations are temporarily recognized directly. Source
operator declarations, associated dispatch and replacing prelude definitions
are **not** implemented. This is not yet a general implementation of the source
prelude or rank-1 polymorphism.

## Architecture

`lexer.carp` -> `parser.carp` -> `check.carp` -> `eval.carp` / `wasm.carp`.

Nodes occupy an owned arena of structs linked by integer IDs. Scalar type
variables use union-find with path compression. The compiler uses Carp ownership
and ordinary arrays, not a tracing collector. `host.h` contains file IO, byte
access and representation conversions only; language rules remain in Carp.
Generated C is never patched.

File-scope parser/checker functions deliberately accommodate Carp 0.6.0's
mutually recursive name resolution. The small module wrappers are public entry
points, not separate implementations.

## Tests and compatibility gates

`test.mjs` compiles independent sources, validates Wasm, executes guest reads and
calls, checks diagnostics, recompiles for determinism, and checks that failures
produce no artifact or preserve an old artifact. Rejected tests include both
invalid programs and deliberately unsupported features; they do not claim that
all those programs are invalid in full Blot.

`reference_test.mjs` runs the accepted corpus against both the unchanged Bend
JavaScript reference and the native Carp executable. It compares results, not
Wasm bytes, because independent backends need not emit identical modules.
Run it after `deno task build:compiler:js`:

```sh
deno run --allow-read --allow-write --allow-run=generated/carp/blotc-carp --allow-env compiler/carp/reference_test.mjs
```

The baseline is `832e92be7ef227be202771d582d4cdd16967561f`. Before the Carp
compiler can replace the default, port and test all of these remaining areas:

| Area | Status |
| --- | --- |
| Rank-1 polymorphism, local generalization, constraints and evidence | Not ported |
| First-class functions, captured closures and higher-order calls | Not ported |
| ADTs, exhaustive/multi-value/value patterns, tuples and named records | Not ported |
| Immutable arrays, alias-safe updates and array iteration | Not ported |
| Effects/providers, typed state, descriptors and callback effects | Not ported |
| Imports, source prelude, custom operators, methods and expression tags | Not ported |
| Numeric-array/callback ABI and long-lived guest execution | Not ported |
| Incremental sessions, cache invalidation and request recovery | Not ported |
| Existing host-facing APIs, diagnostic parity and complete regression suite | Not ported |

Keep this as a draft until those gates pass. Benchmark compiler rebuild time
separately from source-to-Wasm throughput, with identical corpora and specified
optimization settings. Scalar milestone timings do not predict full-language
performance.
