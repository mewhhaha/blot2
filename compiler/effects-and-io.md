# Effects, descriptors, and controlled IO

## Compiler boundary

Compiler primitives are general language/machine operations: numeric operations,
panic, generic effect installation/reflection, scoped state, and typed foreign
calls through explicit callbacks; checked memory operations remain future work.
There are no `@ecs.*`, `@window.*`, `@render.*`, `@input.*`, or `@asset.*`
primitives.

ECS registration, storage, entity lifecycle, queries, scheduling, and render
packet formats belong in Blot libraries. Source wrappers around compiler domain
hooks would not satisfy this boundary.

## Generic effects

```blot
type Reader a is effect = { ask: Unit -> a }

const read_twice = fn () => do:
  use left <- Reader.ask U32 ()
  use right <- Reader.ask U32 ()
  return left + right

const reader = @effect.provider (Reader.ask U32) (fn () => 21)

const answer = fn () => do reader:
  use value <- read_twice ()
  return value

const accesses = @effect.of read_twice
const reads_reader = @effect.has accesses (Reader.ask U32)
const effect_count = @effect.count accesses
```

An operation has a nominal module/declaration identity and a closed unary
signature. This is not a string-keyed runtime registry. Function types carry
latent effect rows, including inferred row variables in higher-order code.
Constructing an effectful function value is pure; calling it contributes the
latent effects.

A provider is an ordinary value tied to one operation. `do provider:` evaluates
it once, runs the suite in that scope, and removes only that operation's
requirement. Implementation effects propagate outward. Invoking a matching
provider runs its implementation in the outer scope, so forwarding to an older
provider does not recurse into itself. Escaping functions retain their effects
and do not capture the provider chain.

Monadic resolvers are also supported: `do (monad Maybe):` uses `Maybe.bind` for
`use`, `Maybe.pure` for `return`, and forwards an existing wrapper with
`return $`. A failed bind skips the remaining block, including later effects and
loop iterations. The adapter is an ordinary prelude function backed by a generic
resolver protocol; user-defined data types can provide their own `pure` and
`bind`. It preserves unrelated effect requirements. Nested plain `do:` blocks
retain direct sequencing and return rules.

Ordinary providers return each operation result directly. A source-declared
effect family gives each concrete state type its own read/write operations:

```blot
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}

const advance = fn initial => do:
  let (next, previous) = do (@effect.state (State.get U32) (State.set U32) initial):
    use value <- State.get U32 ()
    use State.set U32 (value + 1)
    return value
  return (next, previous)
```

`State U32` names the concrete family instance; type application uses spaces
throughout the language. Generic libraries infer the same source-declared
operations from ordinary argument and result types, without naming the type
argument in each function body. A typed getter can connect a constructor or
function witness's result type to the operation's result type.

`@effect.state read write initial` checks that the distinct operations have
signatures `Unit -> S` and `S -> Unit`. Installing it creates fresh scoped state
and returns `(successor_state, body_result)`. Writes do not mutate the initial
value or earlier snapshots. Reusing a provider starts from its original value;
nested providers shadow the same operations and forward unrelated effects.
Closures use providers at their call site and never capture a state cell. State
resolvers work during bounded const evaluation and in the guest. This does not
add continuation/resumption semantics.

Generic libraries can let monomorphization select a family instance:

```blot
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Counter is data = #Counter U32
const get = fn (witness: p -> a) -> a => State.get ()
const set = fn value => State.set value

const advance = fn () => do:
  use counter <- get #Counter
  let #Counter value = counter
  return set (#Counter (value + 1))

const answer = fn () => do:
  let (#Counter next, _) = @effect.run State.get State.set (#Counter 41) advance
  return next
```

`State.get ()` and `State.set value` are ordinary effect calls. The compiler
infers their family arguments from the value argument and expected result type;
there are no get/set selector intrinsics. The `get` wrapper annotates its
witness as `p -> a` and its result as `a`, connecting a constructor's result to
the operation's result without invoking the constructor. An unused witness
without that annotation establishes no type relationship.

The same inference supports arbitrary operation signatures, composite arguments,
and curried families. Explicit arguments remain available, including shared free
annotation variables. Operations specialize to closed nominal identities before
const evaluation and Wasm emission, with no runtime type lookup.

`@effect.run` requires both operations to belong to one family, installs fresh
state, calls `action ()`, and returns `(successor, result)`. `@effect.reader`
and `@effect.writer` install custom implementations through ordinary provider
rules. These runner shortcuts require one plain family binder. Explicit
providers can handle composite and curried families. Explicit polymorphic
effect-row annotations such as `! {State a}` remain unsupported. Unhandled
effects remain visible in function types; pure annotations and const evaluation
reject unhandled calls.

In the sibling gdev checkout, `src/ecs.blot` implements the source ECS using
these operations. `insert_resource initial` and `register_component exemplar`
compose nested state and access closures in a const builder. Duplicate types,
including resource/component conflicts, fail during const evaluation.
`ecs.build` removes the registration schema and returns a simulation containing
initial state, scope and checkpoint closures. Component columns and their
snapshots are runtime values whose types come from registration; there is no
handwritten application World record or runtime type registry.

The gdev library's `get`, `previous`, `components`, `previous_components`,
column replacement and query functions require a unary constructor/function
witness; use `(fn () => Idle)` for a nullary constructor. Component access
requires `at entity action` or a query scope. Missing current components trap;
individual `previous` falls back to the current component when no snapshot
exists. Bulk `previous_components` preserves missing entries as `Nothing`, and
bulk access masks removed entities. Queries are explicit library calls; system
registration does not infer queries from a callback's effects.

## Compile-time descriptors

- `@effect.of named_function` returns an opaque EffectSet for a checked, closed
  function effect row. Open row variables are rejected.
- `@effect.descriptor Reader.ask` returns its nominal EffectDescriptor.
- `@effect.has effects Reader.ask` is convenient named-operation syntax;
  descriptor values can also be passed to generic const helpers.
- `@effect.count effects` counts distinct operations.
- `@effect.same left right` compares descriptors by nominal identity.

These values are usable in ordinary source functions during bounded const
evaluation. Only resulting runtime values, such as Bool/U32, cross into Wasm.
Descriptors do not expose table indices, addresses, or host authority.
Reflection dependencies invalidate inference/const caches when the reflected
interface changes. Runtime-reachable descriptor operations are a diagnostic.

## Controlled host IO

Host functions are passed explicitly to entry functions (`entry const`), the
module's only exports. The boundary accepts one scalar or numeric-array callback
and returns a scalar or numeric array. For example:

```blot
entry const main = fn (advance: U32 -> U32 ! {Foreign}) => do:
  use next <- advance 41
  return next
```

Run `just demo-host`; [the executable example](../examples/host_io.blot) also
forwards a source operation through that callback. [Guest ABI 2](guest-abi.md)
defines the manifest, value codecs, opaque references, lifetime and failure
rules. The compiler does not recognize `main`, `advance`, or any service name.

`Foreign` is a sealed, generic effect label, not an operation or authority
token. Source providers cannot remove it. Its descriptors are inspectable at
const time, but calling a foreign function is not. Closed function annotations
can also name source operations, as in `Unit -> U32 ! {Reader.ask}`.

[The concrete host API proposal](host-api-proposal.md) describes cross-boundary
record bundles, Text/buffers and persistent world values; these still need
implementation. The executable
[Blot example](../examples/host_capabilities.blot) uses the current scalar ABI
instead, constructing ordinary records of typed callbacks inside the guest.

Effect rows describe requirements. Capabilities grant authority. A source
declaration alone never opens a window, acquires a file handle, or creates a
Wasm import. A host-backed provider must originate from a capability supplied by
the trusted caller.

The host supplies a typed bundle of permitted services. Source can install a
provider from that bundle or pass a narrower capability to a subsystem. Host
handles/foreign closures must be unforgeable; ordinary integer values must not
turn into authority. There is no ambient global IO object or fallback for
unhandled effects. Pure providers remain constructible in source for tests.

Window, rendering, input, and filesystem effects will be declared by source
libraries and implemented through this generic foreign/capability boundary. The
compiler must not recognize those operation names. Reload must keep persistent
source state separate from transient host handles and reinstall explicit
capabilities for the replacement program.

Tuples, nominal data, immutable arrays, file imports, scoped state and generic
source libraries execute inside the guest. Numeric arrays cross the host
boundary as copied typed arrays, which gdev uses for transactional state and
render packets. The ECS itself is source code; the compiler implements general
state, effects, loops and specialization rather than domain operations.
