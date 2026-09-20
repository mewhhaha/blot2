# Compiler core

Bend owns language semantics; Deno supplies layout, Baba's field-labelled CST,
native process transport, workers, and execution tests. The compiler
deliberately has no ECS, game, window, rendering, asset, or input vocabulary.

## Run it

```sh
just build
just demo
just demo-host
just compile examples/generic_effects.blot build/effects.wasm
just compile examples/arrays.blot build/arrays.wasm
just check
just bench-native
```

Builds require Bend 2.0.21, Deno, and clang 14+ on POSIX. Every compiler build
runs `bend PROOF.bend`. Source-only iterations reuse the compiled executable.
`build:compiler:js` builds the JavaScript reference; `build:compiler:all` builds
both backends for parity checks. The JS build also requires Bun. Its first build
downloads four matching upstream loader files into
`generated/compiler/bend-2.0.21/`; subsequent builds reuse them offline. Both
downloaded and cached files are verified against pinned SHA-256 hashes.

The native build uses stock Bend 2.0.21. Its runtime passes the ownership
regression that required an isolated emitter patch on 2.0.5, so that obsolete
patch has been removed. The build still compiles and runs
[the regression](native_backend_regression.bend) at 1 and 4 threads before
publishing the binary. The native transport uses the new runtime's
constructor-sealing interface; the installed Bend is never modified.

## APIs and incremental compilation

```ts
import { createNativeCompiler } from "./compiler/native.ts";
import { createNativeIncrementalCompiler } from "./compiler/native_incremental.ts";

const compiler = await createNativeCompiler({ threads: 1 });
const session = await createNativeIncrementalCompiler({ threads: 1 });
try {
  const analysis = await compiler.analyze(source);
  const artifact = await compiler.compile(source);
  const edited = await session.compile(changedSource); // artifact + cache stats
} finally {
  await Promise.all([session.dispose(), compiler.dispose()]);
}
```

The stateless API is a clean oracle. Incremental sessions retain declarations,
dependency groups, inferred interfaces, evaluated constants, and relocatable
Wasm function bodies. Only changed declarations cross the pipe; retained source
identities keep unchanged lambdas/local names stable. Cache keys encode complete
structure, including nominal operation identities and latent effect rows.
Reflection references are inference/const dependencies, not runtime calls.

Both clean builds and native sessions infer dependency-ready groups in balanced
Bend batches. A recursive component stays together, and only completed, closed
interfaces become visible to its dependents. Wasm emission batches independent
cache misses. Small batches use sequential loops; worker completion order never
chooses diagnostic or output order. Const evaluation remains sequential because
its fuel budget is shared.

Clean source lowering also splits declarations into balanced fork trees with at
most four declarations per leaf. Name collection completes first, and joins
preserve the serial lowerer's tail-first semantic diagnostics and source-order
output. Malformed declaration wrappers are validated before those forks.
Lowering, inference and codegen expose up to eight branches together while
keeping their existing leaf cutoffs; this spreads work across Bend 2.0.21's
coarse CPU task lanes. Native request scanning and word counting use flat tail
loops with single-owner scan cursors; diagnostic formatting stays outside the
loops so Bend can optimize them.

`just bench-native` compares JS with native 1/2/4/8-thread full builds, edits,
and cache hits. It verifies complete artifacts and executes the emitted Wasm,
then reports speedups against both JS and one native thread. `just bench-grains`
isolates inference and codegen at those thread counts, with matching JS jobs and
a sequential reference at every cutoff. The phase timings exclude parsing,
transport and linking; they must not be substituted for full-build speedups. See
[the measurements](PERFORMANCE.md) for the current limits.

Changed source still undergoes complete lexing and layout validation. Unchanged
declaration token sequences reuse Baba CST islands and their stable identities;
ambiguous boundaries fall back to the full parser. Exact successful revisions
also reuse a privately retained artifact without IPC. Returned artifacts are
independent copies, and changing the operation or const budget prevents that
shortcut. Stats distinguish parsed/reused islands, full-parser fallbacks and
result reuse. `parsed_ms` includes the complete incremental frontend, including
normalization and source-origin remapping.

Failed edits do not publish partial state or advance the acknowledged revision.
Const caches include entering fuel and transitive source dependencies. Link-time
relocation is repeated against the current catalog; cached code contains no live
table indices or runtime pointers. The JS worker-pool implementation remains a
separate reference with the same compiler semantics.

The binary native protocol is version **6**. Its bounded little-endian frames
contain at most 16M words (64 MiB), Unicode scalar strings, and 48-bit Nats.
Stdout is reserved for frames; stderr carries process diagnostics. Framing or
process failures are fatal; checked language diagnostics leave a session usable.
No native error triggers a silent JS fallback.

## Source modules

The CLI loads relative file imports and the explicit `std/` directory mapping.
Imports precede declarations; `.blot` may be omitted. Both namespace and named
imports work, including aliases:

```blot
import * as array from "std/array"
import { Point as Position, coordinate } from "./geometry"
export fn answer () => array.fold_left U32.add 0 [10, 20, 12]
```

Programmatic callers use `loadSourceProject(entry, { imports })` from
[source_project.ts](source_project.ts), then pass that project to either
compiler's `analyze` or `compile` method. The loader reads each dependency once,
diagnoses cycles, and retains per-file diagnostic locations. Bend resolves
exports, private module scopes, nominal type/effect identities, and qualified
type annotations. Only entry-module exports become Wasm exports. Importing a
type does not implicitly import constructors with different names. Imported
operator functions need a local fixity declaration; prelude fixities are
available in every module.

This first project API performs clean compilation; declaration-incremental
sessions still accept single-file source only. Passing imports to a raw string
compiler is an error, not an implicit filesystem read or ignored declaration.

## Executable language

- Nominal `data` types with nullary/unary constructors, generic parameters,
  constructor functions, and nested patterns.
- Named record constructors, such as `data Vec2 = Vec2 { x: F32, y: F32 }`.
  Construction requires every field exactly once; shorthand `{ x, y }` uses
  lexical bindings. Fields evaluate once in written order, even when reordered
  relative to the declaration. Named patterns can reorder or omit fields, with
  omitted fields acting as wildcards. Zero/one/many fields lower to ordinary
  nullary/unary/tuple constructor payloads, not a separate runtime record kind.
- Heterogeneous tuples `(42, True)` with annotations `(U32, Bool)` and static
  `@product.get value 0` projection. Parenthesized single values stay ordinary
  values; Unit stays `()`. Projection needs a known tuple shape, from a value or
  annotation. Tuple patterns infer the shape from their arity and nest inside
  records and algebraic constructors. Matching preserves correlations between
  tuple fields as well as between multiple scrutinees.
- Homogeneous immutable arrays, including empty/nested literals and `Array T`
  annotations. `@array.length`, `@array.get`, and `@array.set` are generic
  memory primitives; [std/array.blot](../std/array.blot) supplies checked
  access, folds, and short-circuit predicates in source.
- Curried named functions/lambdas, immutable lexical capture, rank-1 inference,
  pure/closed-effect annotations, and inferred higher-order effect rows.
- `case value of` and `case a, b, c of`; every row has the same arity. Inputs
  evaluate once left-to-right; coverage checks combinations, not columns
  independently. Duplicate bindings in one row are rejected.
- `if let pattern = value:`, irrefutable bindings, and
  `let pattern = value else:` with an exiting failure suite.
- `do:` expressions and nearest-block `return`. Falling through yields Unit.
  `let` requires a pure RHS; `use name <- expression` permits effects.
  `use expression` is a discard binding, not a handler or boxed action.
- Closed source operations, provider values, `do provider:`, and const effect
  descriptors. See [the full contract](effects-and-io.md).
- Unit, Bool, U32, and F32 scalar values. U32 arithmetic wraps at 32 bits.
  Decimal/hex separators work; overflowing literals fail. F32 literals round
  directly to binary32 ties-to-even, including subnormals. Arithmetic can yield
  infinity/NaN; no implicit U32/F32 conversion. Prefix `-` is F32 negation;
  parenthesize negative call arguments.
- Generic `@panic "message"` produces Never and traps in Wasm; const evaluation
  reports its message as a diagnostic. It supplies no IO authority.
- Explicit host callbacks with a sealed `Foreign` effect, scalar signatures,
  opaque invocation-scoped references, and a versioned generic adapter. See
  [guest ABI 1](guest-abi.md) and
  [the executable example](../examples/host_io.blot).

## Prelude and operators

[std/prelude.blot](../std/prelude.blot) is ordinary source, loaded once per
frontend session. `{ prelude: "none" }` selects a freestanding module. Prelude
exports become visible source names, but only root exports become Wasm exports.
Qualified functions such as `Maybe.map` are statically resolved names, not
implicit receivers or type-directed dispatch.

Symbolic operators have source fixity declarations; backticks use ordinary
functions, e.g. `a \`combine\` b`. No operator implies a game-specific
primitive. Higher-order prelude functions propagate callback effects. See
[the prelude reference](../std/README.md).

Low-precedence application is also source-defined: `infixr 0 ($) = apply`, where
`apply function value` calls `function value`. Thus `f $ g $ x` means `f (g x)`.
Infix RHSs can be lambdas, blocks or matches. `$` retains eager evaluation and
inferred effects; `return $ value` remains separate resolver forwarding syntax.
Plain `do:` functions already fall through to Unit without an explicit
`return ()`; expression-bodied functions return their expression.

## Evaluation and Wasm representation

Const evaluation has an explicit shared step budget. Handled operations use the
same scoped-provider rules as runtime; unhandled operations fail. Closed effect
descriptors are opaque const values, not numeric runtime IDs. Ordinary helper
functions may calculate with them during const evaluation. Runtime reachability
omits const-only helpers; a live descriptor value/operation reports
`backend_const_only`.

Internal functions take closure environment, argument, and provider chain.
Provider frames are immutable and lexical, so early returns cannot leak a
binding. Closures capture locals, not active providers: invoking an escaped
closure uses the caller's provider scope. A provider implementation sees the
outer chain, excluding the selected provider and younger frames.

Export wrappers accept Unit/Bool/U32/F32 or one scalar callback with exactly
`! {Foreign}`, and return scalars. Callback parameters use `externref` and
signature-specific `blot:host/1` imports. Scalar-only artifacts stay
import-free. Every module describes its exports in `blot:abi`; the adapter
validates this manifest and scopes supplied callbacks to the current invocation.
Ordinary unhandled source operations still fail instead of acquiring ambient IO.

Arrays have a length header and contiguous machine-word elements; tuples have
fixed-size contiguous fields. Nested values and closures occupy reference lanes,
not recursive list nodes. Elements evaluate once left-to-right. Indexes are
checked unsigned U32 values; invalid const accesses report `array_bounds`, and
runtime accesses trap. Updates allocate and copy the full array, preserving
existing aliases. Const updates charge one extra step per copied element. Array
size arithmetic is checked before allocation; the private arena is bounded to 16
MiB. Bulk builders and uniqueness-based in-place optimization remain future
work, so repeated per-element updates currently have quadratic copying cost.

Internal closures and data values stay inside the module. Multi-value matches
use locals rather than heap-allocated tuples. Each export resets its arena; the
adapter rejects same-instance reentry and callback/ADT return values cannot
escape as persistent handles.

Wasm uses binary format version 1, also used by newer Wasm standards; a
different binary header is not how Wasm 3.0 features are selected. The current
emitter does not yet require newer proposals, SIMD, or Wasm-GC.

## Deliberate limits

Record field access/update syntax, indexing/update sugar, array patterns,
destructuring function parameters, general Text/F64, SIMD, parameterized
operation identities, effect-group syntax, demand parameters, type-valued
consts, and resumptions are not implemented. `do monad Maybe:`/`return $` remain
design syntax, not implemented monad resolution. An unconstrained provider
parameter cannot infer an unknown operation identity in this first closed-label
slice.

[Controlled host IO](effects-and-io.md#controlled-host-io) now works for scalar
callbacks. Composite host values, persistent values and a Blot-source ECS come
next. The removed compiler-coupled sandbox is preserved only as a
[prototype reference](../case-study/ecs/prototype/README.md).
