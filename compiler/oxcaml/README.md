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
just build
blot check examples/generic_effects.blot
blot build examples/arrays.blot build/arrays.wasm
```

`just build` builds the checked-in `.ml` files, installs
`generated/compiler/blotc` for repository APIs, keeps a release copy at
`generated/compiler/blotc-oxcaml`, and installs a standalone `blot` executable
in `~/.local/bin`. Set `BLOT_INSTALL_DIR` to choose another directory. The
executable bundles the native compiler, parser, standard library, and guide, so
it works without this checkout, Deno, or opam. The build requires OxCaml, GNU
Make 4.3+, a C toolchain, and Deno 2. Neither Bend, Bun, the Python migration
script, nor generated JavaScript compiler artifacts are needed.
`deno task build:compiler:oxcaml` builds only the repository backend;
`deno task build:compiler` remains available to select the Bend backend.

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
regenerate this code. The migration refuses to overwrite differing native files,
before writing any output. Reproduce into a new directory with
`python3 compiler/oxcaml/bootstrap/port.py --output /tmp/blot-port` and review
the differences. No Bend-generated C or JavaScript is patched.

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

## Memory representation

The 64-bit native runtime stores character words as immediate integers. Exact
U32 bits, code-point order, Unicode validation, and the version-13 wire format
are unchanged; F32 values still retain their Int32 bits. U32 comparisons use
non-allocating machine-integer arithmetic, checked with `[@zero_alloc strict]`.

Requests stay in their packed byte buffer instead of expanding to boxed word
arrays. String decoding validates forward before constructing the result
backward, preserving diagnostic precedence without per-character cursors. No
request buffer is retained by the published syntax or incremental session.
Responses validate their complete output plan before emitting any frame prefix,
then write through a private buffer capped at 64 KiB.

OxCaml uses tail-modulo-constructor recursion for string append and the native
list append, allocating one result spine. OCaml 4 retains a stack-safe fallback.
String joins are right-associated; map and set traversals avoid temporary
key/value-pair lists. These are internal changes, not changes to source values,
Wasm, host APIs, or the installer.

See [the experiment report](MEMORY_CONCURRENCY.md) for measurements and rejected
scheduler experiments. The original FIFO worker pool is retained; adding more
concurrency machinery did not establish a repeatable speedup.

## Validation

```sh
deno task test:compiler:oxcaml
# Differential tests additionally require the unchanged Bend reference:
python3 compiler/oxcaml/build_reference.py
deno task test:compiler:oxcaml:parity
```

The native unit gate includes 10 byte-encoding checks, 3,726 Base/runtime
checks, 6,614 native name/allocation checks, 177 fork/join checks, a
concurrent-domain rendezvous and exception-join check, 39,283 memory/scalar
checks, 1,174 response-stream checks, 564 scheduler stress checks, 3 migration
overwrite checks, 6 subprocess framing checks, and 8 incremental-build checks.
Python 3 is needed for the test drivers, not for ordinary builds.

`test_existing.py` discovers the existing compiler test files and script suites
and runs them in an isolated checkout. Native tests select the OxCaml
executable. An exact-URL import map routes synchronous source tests through the
test-only `source_mirror.ts`: each operation must match the unchanged Bend
JavaScript reference, including full Wasm bytes, analyses, and diagnostic
fields. The unchanged tests receive the native result. A mismatch remains a gate
failure even when a negative test catches its exception. Low-level IR-only tests
still exercise the reference; mirrored operation counts are recorded separately.

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

[Performance work](PERFORMANCE.md) records the first native allocation pass,
paired samples, and its limitations. Name equality is checked allocation-free by
OxCaml; the redundant character wrapper is unboxed. The executable still builds
with stock OCaml, where the OxCaml-specific check attribute is ignored.

For native-to-native comparisons without a JavaScript reference:

```sh
make -C compiler/oxcaml bench-names
deno run -A compiler/oxcaml/bench_compare.ts \
  /path/to/baseline/blotc compiler/oxcaml/_build/blotc \
  build/oxcaml-paired.json 7 1,4
```

This alternates baseline and candidate runs, validates outputs and cache
behavior, and separates startup, source-to-Wasm, pre-encoded native requests,
analysis, body edits, and unchanged reuse. It records raw samples and hashes;
synthetic workloads are not a substitute for application measurements.

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
