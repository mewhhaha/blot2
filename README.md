# Blot 2

A native compiler written in Bend, with Deno tooling and Baba 9.0.1
lexing/parsing. The executable core targets Wasm and includes a source prelude,
rank-1 type/effect inference, closures, algebraic data, multi-value matching,
tuples, named record constructors, immutable arrays, file imports, bounded const
evaluation, and source-defined operators.

The compiler has no ECS, game, window, input, or rendering primitives. Effects
are source-declared operations, including type-applied families such as
`State U32`; providers supply implementations. Host functions are explicit
callable capabilities passed into entrypoints, not ambient services. A module's
host entrypoints are its `entry const` and `entry let` declarations: they are
its only Wasm exports and the roots from which compilation keeps code. See
[effects and controlled IO](compiler/effects-and-io.md).

## Work with the compiler

Requires Deno 2, Bend, and clang 14+ on a POSIX system. Builds use the installed
Bend without a version restriction. Building the JavaScript reference
additionally needs Bun and network access on the first build for each Bend
version to fetch loader sources from its matching upstream release tag.

```sh
just build       # native generated/compiler/blotc
just guide       # compact language reference for people and LLMs
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
checks. Builds run `bend PROOF.bend`; important rules live in `LAWS.bend`. The
build uses Bend's generated C and JavaScript without rewriting either output.
See [compiler details](compiler/README.md). Suspected upstream problems are
tracked in [BUGS.md](BUGS.md); posting them requires the owner's approval.

Read [the CLI guide](compiler/guide.md) for the executable syntax and language
rules in one pass, or print it with `deno task blot guide` without rebuilding.
Start with [the executable prelude example](examples/prelude.blot),
[generic effects and descriptors](examples/generic_effects.blot), and
[explicit host callbacks](examples/host_io.blot). The
[array example](examples/arrays.blot) imports an ordinary source library and
executes through `just compile examples/arrays.blot`. See also
[record construction and destructuring](examples/records.blot) and
[the source prelude](std/README.md). The [syntax showcase](examples/syntax.blot)
and [ECS example](examples/ecs.blot) also compile and execute on the current
language. The ECS composes component columns at const time and accesses them
through scoped state effects; `just study` runs it headlessly.

[The host-capability example](examples/host_capabilities.blot) constructs
guest-side records from a scalar host callback, with no game intrinsics. See
[the source/host contract](compiler/host-api-proposal.md) for ABI, effects and
reload boundaries. Scalar and numeric-array callbacks are executable through the
[guest ABI](compiler/guest-abi.md). Long-lived `main(host)` invocations can
retain guest state; record capability bundles remain outside the ABI.

[Expression tags](examples/tags.blot) apply ordinary functions to top-level
`const` and `let` values with `#[expression]`. Tags may stack, use arguments or
imports, and precede an `entry` declaration.

## Current boundary

Data constructors require `#` in declarations, values, and patterns. Type names
stay unmarked:

```blot
type Maybe x is data = #Some x | #Nothing
const value: Maybe U32 = #Some 42
```

Qualified constructors put the marker first: `#time.Clock`. Boolean constructors
are `#True` and `#False`.

`type Reader a is effect = { ask: Unit -> a }`,
`@effect.provider (Reader.ask U32) implementation`, and `do provider:` form the
generic effect core. Function values retain latent effect requirements; creating
one is pure, invoking it need not be. `@effect.of`, `@effect.descriptor`,
`@effect.has`, `@effect.count`, and `@effect.same` support closed compile-time
descriptors. Closed annotations such as `U32 -> U32 ! {Foreign}` describe
callback effects. `Foreign` cannot be declared or handled as a source operation.
Runtime descriptors, unhandled source operations at entrypoints, and implicit
host access are rejected.

Matching uses `case a, b, c of` with comma-separated pattern rows. Single-value
matches use `case value of` too. The inputs evaluate once, left to right. A
plain name in a pattern binds a value; `^name` compares against an existing
constant, parameter, or `let` binding. Qualified references work too:

```blot
const tab = 0x110104
const key_action = fn code => case code of
  ^tab => #True
  _ => #False

const matches = fn (expected: U32) => fn actual => case actual of
  ^expected => #True
  _ => #False
```

Value patterns currently support `U32` and `Bool`, including nested patterns
such as `#Some ^expected` and imported names such as `^keys.tab`. The referenced
binding comes from the surrounding scope, never a sibling pattern. Its type must
match the scrutinee. Value patterns are refutable even when naming a constant,
so other arms must cover the remaining values. They also work in `if let` and
`let … else`. Arbitrary expressions, floats, and structural equality are not
supported in value patterns. Annotate parameters whose scalar type is otherwise
unconstrained.

File imports, tuple values/patterns, named record construction/patterns, and
homogeneous immutable arrays compile to Wasm. Records support field reads and
updates; arrays support `.length`, checked `.get(index)`, `a[index]`, and
`a[index] := value`. Updates preserve aliases and reuse locally owned array
storage when safe. Receiver methods such as `tail.contains(witness)` select
ordinary associated functions. Numeric arrays cross the host boundary as copied
`Uint32Array`/`Float32Array` values; records and other composite values remain
private to a guest invocation. Project-wide incremental compilation is not
connected yet.

`for let value in values:` iterates an array, `for let index in 0..5:` binds a
range index, and `for 0..5:` discards it. `for ever:` repeats until a return or
failure; it does not suspend by itself. A long-lived `main(host)` can suspend
through an asynchronous host callback. See the
[guest ABI](compiler/guest-abi.md) for callback setup and bounded numeric-array
loop state.

SIMD, explicit polymorphic effect-row annotations such as `! {State a}`, general
type-valued const programming, resumptions, capability bundles, and persistent
guest handles remain future work. Entry functions accept scalars, numeric
arrays, or one scalar/numeric-array callback and return a scalar or numeric
array. Source libraries can serialize application state into numeric arrays for
save/load and reload.

## Helix highlighting

Run `just install` to regenerate, check, and install the `blot` language
override and its highlighting queries. The editor grammar deliberately covers
the wider language proposals; highlighting does not imply the compiler
implements every form.

## Sandbox status

The sibling [gdev application](../gdev/README.md) runs on this compiler with a
source-defined ECS, a Deno Desktop/WebGPU host, editor controls, save/load and
state-preserving source reload. Run `cd ../gdev && just run`. Its source derives
typed component columns at const time and selects source-declared state effects
for generic ECS access. Its numeric state/render codec is an application
protocol, not a compiler primitive.

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

## Local package development

`@mewhhaha/blot` provides the compiler API, guest API, and CLI in one package.
The adjacent `gdev` checkout links this package through its Deno `links`
setting. Run `deno task package:build` after changing Bend compiler sources to
rebuild both backends and the bundled native executable. Standard library and
TypeScript changes are read directly from the linked checkout.

The bundled native executable targets Linux x86-64. Other platforms can supply
their own executable to `createNativeCompiler({ executable })` or use
`createSourceCompiler()` for the JavaScript reference backend.

`just build` rebuilds and repacks the native compiler used by gdev. Use
`deno task package:build` when the JavaScript reference backend also needs to be
regenerated.

`deno task package:check` prepares the package and performs a release dry run.
Publishing remains a separate `deno publish` step.
