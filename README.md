# Blot 2

A native compiler written in Bend 2.0.21, with Deno tooling and Baba 9.0.1
lexing/parsing. The executable core targets Wasm and includes a source prelude,
rank-1 type/effect inference, closures, algebraic data, multi-value matching,
tuples, named record constructors, immutable arrays, file imports, bounded const
evaluation, and source-defined operators.

The compiler has no ECS, game, window, input, or rendering primitives. Effects
are source-declared operations; providers supply implementations. Host functions
are explicit callable capabilities passed into ordinary exports, not ambient
services. See [effects and controlled IO](compiler/effects-and-io.md).

## Work with the compiler

Requires Deno 2, Bend **2.0.21**, and clang 14+ on a POSIX system. Building the
JavaScript reference additionally needs Bun and network access on its first
build to fetch integrity-pinned upstream loader sources.

```sh
just build       # native generated/compiler/blotc
just demo        # execute the generic-prelude Wasm example
just demo-host   # execute an explicit host callback and source effect adapter
just compile     # reuse the native compiler; no Bend rebuild
just check       # formatting, types, proofs, compiler/editor tests
just bench       # JavaScript reference timings
just bench-native # native full builds, declaration edits, and cache reuse
just install     # install Blot highlighting in Helix
deno task blot check examples/generic_effects.blot
```

Deno supplies parsing and a persistent subprocess transport; Bend owns lowering,
inference, const evaluation, and Wasm generation. Native failures never silently
fall back to JavaScript. The reference JavaScript compiler exists for parity
checks. Builds run `bend PROOF.bend`; important rules live in `LAWS.bend`. Stock
Bend 2.0.21 passes the retained native ownership regression without an emitter
patch; see [compiler details](compiler/README.md).

Start with [the executable prelude example](examples/prelude.blot),
[generic effects and descriptors](examples/generic_effects.blot), and
[explicit host callbacks](examples/host_io.blot). The
[array example](examples/arrays.blot) imports an ordinary source library and
executes through `just compile examples/arrays.blot`. See also
[record construction and destructuring](examples/records.blot) and
[the source prelude](std/README.md). The [syntax showcase](examples/syntax.blot)
and [ECS example](examples/ecs.blot) also compile and execute on the current
language. The ECS uses immutable component columns, explicit queries, and
source-defined system scheduling; `just study` runs it headlessly.

[The host-capability example](examples/host_capabilities.blot) constructs
guest-side records from a scalar host callback, with no game intrinsics. See
[the source/host contract](compiler/host-api-proposal.md) for ABI, effects and
reload boundaries. Scalar callbacks are executable through
[guest ABI 1](compiler/guest-abi.md); record bundles and persistent worlds in
the broader proposal are not implemented yet.

## Current boundary

`effect Reader.ask: Unit -> U32`, `@effect.provider Reader.ask implementation`,
and `do provider:` form the generic effect core. Function values retain latent
effect requirements; creating one is pure, invoking it need not be.
`@effect.of`, `@effect.descriptor`, `@effect.has`, `@effect.count`, and
`@effect.same` support closed compile-time descriptors. Closed annotations such
as `U32 -> U32 ! {Foreign}` describe callback effects. `Foreign` cannot be
declared or handled as a source operation. Runtime descriptors, unhandled source
operations at executable exports, and implicit host access are rejected.

Matching uses `case a, b, c of` with comma-separated pattern rows. Single-value
matches use `case value of` too. The inputs evaluate once, left to right.

File imports, tuple values/patterns, named record construction/patterns, and
homogeneous immutable arrays now compile to Wasm. Array updates currently copy;
composite values remain private to a guest invocation. Project-wide incremental
compilation is not connected yet.

Record field access/update syntax, SIMD, parameterized effect identities,
type-valued const programming, resumptions, capability bundles, and persistent
state transfer remain future work. Host exports currently accept a scalar or one
scalar callback and return a scalar.

## Helix highlighting

Run `just install` to regenerate, check, and install the `blot` language
override and its highlighting queries. The editor grammar deliberately covers
the wider language proposals; highlighting does not imply the compiler
implements every form.

## Sandbox status

The [3D sandbox/editor](case-study/ecs/README.md) is paused. Its
compiler-coupled ECS/render backend and `compileEcs`/`compileApp` APIs have been
removed; `just study` now runs the separate headless ECS example, not the
graphical sandbox. Prior host/runtime experiments are preserved in
[the prototype archive](case-study/ecs/prototype/README.md).

The next sandbox must build storage, queries, system scheduling, and render
descriptions in Blot source. JavaScript will supply capability-scoped platform
services, assets/GPU submission, and code/resource reloading. The
[case-study plan](case-study/ecs/PLAN.md) records that migration; old ECS
timings are historical measurements, not results for the new generic core.
