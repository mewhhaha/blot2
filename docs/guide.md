# Blot K1 language guide

The normative [language contract](spec/LANG.md), [Core contract](spec/CORE.md)
and [memory/ABI contract](spec/MEM.md) take precedence over this introduction.
The implementation remains under qualification; examples and tests show the
currently executed paths.

## Values, functions and control flow

Bindings are immutable. A function takes one value, which may be a tuple or
record. Calls do not discover an argument convention or infer a new generic
body. Public and higher-order interfaces state effects and finite resources.

```blot
pub let offset: U32 -> U32 ! {} resources {depth: 1, frame: 0} =
  fn value => return U32.wrapping_add(value, 7)
```

Every continuing function path returns explicitly. A `do:` expression completes
with `break value`. `if` and `case` join only facts and authorities valid on every
continuing predecessor. `Result` must be handled even if its payload is copyable.
There is no implicit tail return, mutable rebinding, named recursion or general
proof search.

Finite range loops use explicit carries and invariants. See
[counted_loop.blot](../examples/counted_loop.blot): `next` establishes the
successor invariant; `stop` establishes it at the current iteration. Only a
naturally exhausted range grants its final index equality.

## Numbers and collections

U32 operators require evidence against overflow, zero division and invalid
shift counts. Explicit wrapping and checked-result operations have distinct
semantics. F32 operations round separately, preserve signed zero and follow
Wasm's NaN rules. Required-static arithmetic chooses positive canonical NaN.

Capacity describes reserved storage; length describes initialized elements.
Indexing needs evidence against length. A checked `Index[d,n]` also belongs to
one exact immutable collection identity. Equal lengths do not identify domains.

A destination grants exclusive initialization authority. Append/Resize builders
consume and return that authority as their initialized prefix changes. Freezing
consumes the builder and publishes an immutable view. Arrays do not allocate a
hidden heap: array literals require a static initializer or an explicit
`array.in` destination. The particle example demonstrates destination building
with an explicit loop invariant.

## Lifetimes, callbacks and ownership

A scoped region has one owner and explicit space/capability transitions. Views
and callbacks cannot outlive their backing storage or lexical environments.
Closures capture Share values; affine state is passed as arguments/results.
`Once` callbacks are consumed by invocation or an explicit discard.

`Owned[P]` transfers one entire backing region containing a closed Share payload.
Opening it lends a fresh lexical view of that payload; closing it consumes the
owner and releases its backing. It cannot contain another owner, external loan
or affine callback. See the region, Owned and closure examples for complete
error handling and cleanup paths.

## Generics, static work and artifacts

Generic binders explicitly state kind and constraints. An unconstrained type is
affine: generic identity can move it, but cannot silently copy or drop it. Each
declared generic body is checked once; every use supplies explicit arguments
with `@[...]`. A declaration can appear at module scope or inside a function.

```blot
pub let run: U32 -> U32 ! {} resources {depth: 3, frame: 1024} =
  fn input => do:
    let identity: forall [T: Type] =>
      T -> T ! {} resources {depth: 1, frame: 256}
    = fn value => return value
    return identity@[U32](input)
```

Ordinary locals remain monomorphic. `let identity = fn x => return x` lacks a
usable parameter type and is rejected; it is not implicitly generalized. A
bare generic name such as `let callback = identity` is also rejected. Instantiate
it first, for example `let callback = identity@[U32]`. Higher-rank parameters and
results, polymorphic recursion, and escaping a local generic binder are
unsupported. An unused local generic body is still checked. Compiler admission budgets belong
to the enclosing module declaration: nested functions and local generics share
its operation, block, type, proof, and semantic-work limits. Introducing another
local function does not reset those limits.

A local generic may capture Share values from its enclosing scope. Its complete
callable type uses `Fn[local, ...]` when those captures require the current
activation. Its own `forall` binders remain call parameters; ambient Type and
Nat witnesses belong to the captured environment. Instantiating a captured
generic inside a nested lambda preserves that same captured value. See
[local_generic_capture.blot](../examples/local_generic_capture.blot),
[local_generic_ambient.blot](../examples/local_generic_ambient.blot), and
[local_generic_nat.blot](../examples/local_generic_nat.blot).

One checked generic body uses compiler-owned layout dictionaries and bounded ABI
adapters. Domains remain semantic authorities, never arbitrary source integers.

Transparent aliases can be generic and may also be declared locally:

```blot
type Pair[T: Type] = (T, T)
let first: Pair[U32] -> U32 = fn pair => do:
  type Number = U32
  let result: Number = pair.0
  return result
```

Module aliases are completed in dependency order, so long acyclic forward
chains do not require recursive compiler calls. Function and static-value
dependencies use the same iterative completion order. Named recursive components
are rejected even when a reference occurs in a later-proved dead branch. Cycles such as `type A = B` and
`type B = A` are rejected with `k1_recursive_call`. A local alias is visible from
its declaration until the end of that lexical scope. Generic aliases require
explicit arguments: `Pair[U32]` is a type; bare `Pair` is rejected with
`k1_kind_mismatch`.

`static let` evaluates even when no export uses it. Required evaluation allows
closed constants, immutable arrays and captured callbacks, pure scalar/product/
sum work, finite loops, and compatible calls. Local static bindings may depend
on earlier static values, but may not depend on runtime parameters:

```blot
static let seed: U32 = 19
static let answer: U32 = seed + 23

// Rejected with k1_static_limit: input is a runtime value.
let bad: U32 -> U32 = fn input => do:
  static let cached = input
  return cached
```

Static evaluation has per-declaration limits of 100,000 primitive steps, source
call depth 128, and 4 MiB of immutable output; semantic traversal limits also
apply. A synthetic initializer does not consume a source call-depth level.
Runtime reservation, mutable state, host I/O, and future runtime identities are
excluded. See [static_loop.blot](../examples/static_loop.blot),
[static_pattern.blot](../examples/static_pattern.blot), and
[static_closure.blot](../examples/static_closure.blot) for executed examples.

Completed Core owns types, evidence, selected operations and origins. Independent
validation establishes its structural and semantic invariants before lowering.
Optional optimization cannot repair a missing source proof or change whether a
program is admitted. External serialized objects remain untrusted regardless of
hashes or purported work receipts.


## Parenthesized arguments and suites

Newlines inside parentheses, brackets and braces are whitespace under the
current grammar. An indentation suite therefore cannot start inside an open
parenthesized argument. Bind a suite's result before passing it to a function.
The checker still tracks already evaluated affine arguments while checking
later arguments; this restriction does not grant permission to discard them.
