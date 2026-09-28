# OxCaml compiler

A native Blot compiler with the same source frontend, Wasm ABI, diagnostics, and
incremental-session protocol as the Bend implementation. Typing, effects,
constant evaluation, specialization, and code generation run in OxCaml. Deno and
Baba retain source parsing and the host API; they do not compile Blot.

## Build and use

Install [OxCaml](https://oxcaml.org/get-oxcaml/) and select its opam
environment:

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
eval $(opam env --switch 5.2.0+ox)
deno task build:compiler:oxcaml
deno task blot check examples/generic_effects.blot
deno task blot build examples/arrays.blot build/arrays.wasm
```

`build:compiler:oxcaml` builds the checked-in `.ml` files and atomically
installs `generated/compiler/blotc`. Existing native APIs, CLI commands, and
applications then use OxCaml without an executable override. It requires OxCaml,
GNU Make 4.3+, and a C toolchain; source tooling needs Deno 2. Neither Bend,
Bun, the Python migration script, nor generated JavaScript compiler artifacts
are needed. The original `build:compiler` task remains available to select the
Bend backend.

To keep both executables, use the isolated build instead:

```sh
make -C compiler/oxcaml
deno task blot:oxcaml build examples/prelude.blot build/prelude.wasm
```

The isolated executable is `compiler/oxcaml/_build/blotc`. Existing
`createNativeCompiler`, `createNativeIncrementalCompiler`, and project APIs
accept it through their `executable` option:

```ts
// Example located in compiler/oxcaml/.
import { createNativeCompiler } from "../native.ts";
const compiler = await createNativeCompiler({
  executable: new URL("./_build/blotc", import.meta.url),
  threads: 4,
});
try {
  const artifact = await compiler.compile("entry const answer = fn () => 42\n");
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  console.log((instance.exports.answer as () => number)());
} finally {
  await compiler.dispose();
}
```

## Development

The Makefile extracts module dependencies and recompiles changed modules and
their dependents, rather than rebuilding the entire compiler for every edit.
Compiler identity, flags, and worker-backend changes invalidate cached objects.
An unchanged invocation does not recompile or relink. `make -j2` can compile
independent modules concurrently; keep memory available for the larger modules.

`core/` contains 70 native modules, initially migrated from 3,386 functions and
436 algebraic types. `bootstrap/` records the fail-closed migration and SHA-256
provenance from `832e92be7ef227be202771d582d4cdd16967561f`. Normal builds never
regenerate this code. Review differences before running `make bootstrap` over
hand-edited native changes. No Bend-generated C or JavaScript is patched.

`base.ml` supplies Unicode code-point strings, 32-bit scalars, Patricia maps,
and the Base operations used by the compiler. Native transport implements
bounded version-13 frames: complete malformed requests produce diagnostics;
truncated or oversized frames terminate the process. The executable contains no
Bend/JavaScript interpreter, subprocess fallback, or `Obj.magic`.

OxCaml uses persistent, bounded fork/join workers at the compiler's 16 existing
fork points. `--threads 1..64` is capped by available CPUs. Nested joins help
execute queued work; errors wait for outstanding children and preserve source
error order. The pool is an explicit synchronized legacy-Domain boundary, not a
claim of mode-checked race freedom. OCaml 4.13 builds use a serial portability
backend. Linux priority restoration is best-effort; `--inherit-priority` keeps
the launcher's scheduling policy.

## Validation

```sh
deno task test:compiler:oxcaml
# Differential tests additionally require the unchanged Bend reference:
python3 compiler/oxcaml/build_reference.py
deno task test:compiler:oxcaml:parity
```

The native unit gate includes 10 byte-encoding checks, 3,726 Base/runtime
checks, 177 fork/join checks, a concurrent-domain rendezvous and exception-join
check, 6 subprocess framing checks, and 8 incremental-build checks. Python 3 is
needed for the test drivers, not for ordinary builds.

`test_existing.py` runs the existing 156 compiler test files and two script
suites in an isolated checkout. Native tests select the OxCaml executable. An
exact-URL import map routes synchronous source tests through the test-only
`source_mirror.ts`: each operation must match the unchanged Bend JavaScript
reference, including full Wasm bytes, analyses, and diagnostic fields. The
unchanged tests receive the native result. A mismatch remains a gate failure
even when a negative test catches its exception. Low-level IR-only tests still
exercise the reference; mirrored operation counts are recorded separately.

Coverage includes imports/prelude, rank-1 types and effects, closures, data and
patterns, arrays/records, tags/operators, bounded constant evaluation, float
rounding, source error locations, guest callbacks, and incremental rollback,
cache invalidation, and multithreaded compilation. CI uploads a manifest with
executable/test hashes, mirrored operation counts, failures, and ignored tests.
The paused graphical ECS sandbox and historical prototypes are listed separately
in that manifest; they are not part of the repository's `deno task test` gate.
Scheduling tests requiring privileges may be reported as ignored, not passed.

CI builds with both actual OxCaml and stock OCaml. A separate read-only clean
checkout gate builds, tests source compilation without reference artifacts, and
verifies installation through the existing CLI. It does not regenerate source
files or commit to the branch.

The executable language boundary remains the one in `compiler/guide.md`. Planned
language features do not become supported merely through migration. This is a
feature-preserving native backend, not a new language design.

## Measurements

Measure compiler build time separately from the compiler's own throughput. For
source-to-Wasm timings, after selecting the OxCaml executable and building the
reference, the existing benchmark runs unchanged:

```sh
deno run --allow-all compiler/native_bench.ts 7 build/oxcaml-bench.json 1,2,4 2
```

It records executable hashes, startup separately, repeated full builds,
analysis, body edits, and warm reuse. Its comparison is against the JavaScript
reference, **not** a Bend-native speedup. The synchronous mirror adapter starts
one subprocess per operation for compatibility with existing tests; its timings
are deliberately not used as compiler throughput measurements.
