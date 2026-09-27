# OxCaml compiler rebuild

An opt-in native semantic port of Blot's production compiler. The Bend compiler
remains the default and compatibility oracle until differential source, ABI,
and incremental-session checks establish the replacement's boundary.

The initial migration covers the complete 70-module native dependency graph:
3,386 functions and 436 algebraic types, including inference, effect rows,
constant evaluation, source lowering, specialization, Wasm emission, and the
transactional incremental session. These counts describe translated code, not a
claim that every language feature has passed differential tests yet.

## Build

Install OxCaml following <https://oxcaml.org/get-oxcaml/>:

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
eval $(opam env --switch 5.2.0+ox)
make -C compiler/oxcaml test
```

During the initial migration, before `core/` has been materialized, first run
`make -C compiler/oxcaml bootstrap`. Once committed, those `.ml` files can be
built and edited directly. Normal native builds require neither Bend nor the
Python migration script. Tests use Python 3 for subprocess framing checks.

The executable is `compiler/oxcaml/_build/blotc`. Select it using the existing
host option, without replacing the default compiler:

```ts
import { createNativeCompiler } from "../native.ts";
const compiler = await createNativeCompiler({
  executable: new URL("./_build/blotc", import.meta.url),
});
try {
  const artifact = await compiler.compile("entry const answer = fn () => 42\n");
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  console.log((instance.exports.answer as () => number)());
} finally {
  await compiler.dispose();
}
```

The example paths assume a file inside `compiler/oxcaml/`. The normal Deno/Baba
source frontend is retained; it does not perform typing or code generation.
The executable itself has no Bend/JavaScript interpreter, subprocess fallback,
`Obj.magic`, or third-party OCaml dependency.

## Implementation

`core/` contains typed OCaml algebraic data and functions. `bootstrap/` records
the fail-closed source migration from commit
`832e92be7ef227be202771d582d4cdd16967561f`, with source line comments and SHA-256
provenance. Do not regenerate it over hand-edited native optimizations without
reviewing the differences. No Bend-generated C or JavaScript is patched.

`base.ml` provides Unicode code-point strings, 32-bit scalars, Patricia maps,
and the small set of Base operations used by the compiler. `ox_native_transport.ml`
implements bounded version-13 frames. Complete malformed requests return the
normal diagnostic; truncated or oversized frames terminate the process.

The first native port is serial: `--threads` is accepted for host compatibility
but does not yet start workers. It inherits process scheduling priority. These
are explicitly remaining runtime differences, not language-feature removals.

## Current checks

Local OCaml 4.13.1: complete executable builds; 10 Wasm byte checks, 3,724 runtime
checks (including exact decimal midpoints and randomized Patricia lookups), and
6 subprocess framing checks pass. CI additionally builds with actual OxCaml.
Source-level differential results will be recorded separately, rather than
being inferred from these unit checks.

The default must not switch until syntax/imports/prelude, inference/effects,
constant diagnostics, Wasm/host ABI, and incremental cache invalidation all
have executable parity coverage. Compiler build time and compilation throughput
must be measured separately on identical programs and hardware.
