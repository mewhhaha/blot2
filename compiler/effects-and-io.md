# Effects, descriptors, and controlled IO

## Compiler boundary

Compiler primitives are general language/machine operations: numeric operations,
panic, generic effect installation/reflection, and typed foreign calls through
explicit callbacks; checked memory operations remain future work. There are no
`@ecs.*`, `@window.*`, `@render.*`, `@input.*`, or `@asset.*` primitives.

ECS registration, storage, entity lifecycle, queries, scheduling, and render
packet formats belong in Blot libraries. Source wrappers around compiler domain
hooks would not satisfy this boundary.

## Generic effects

```blot
effect Reader.ask: Unit -> U32

fn read_twice () => do:
  use left <- Reader.ask ()
  use right <- Reader.ask ()
  return left + right

const reader = @effect.provider Reader.ask (fn () => 21)

export fn answer () => do reader:
  use value <- read_twice ()
  return value

const accesses = @effect.of read_twice
const reads_reader = @effect.has accesses Reader.ask
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

This is direct, result-returning handling. It supports Reader-style operations,
not pure mutable State or continuation/resumption semantics.

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

Host functions are passed explicitly to ordinary exported functions. The first
implemented boundary accepts one scalar callback and returns a scalar:

```blot
export fn main (advance: U32 -> U32 ! {Foreign}) => do:
  use next <- advance 41
  return next
```

Run `just demo-host`; [the executable example](../examples/host_io.blot) also
forwards a source operation through that callback. [Guest ABI 1](guest-abi.md)
defines the manifest, scalar codecs, opaque references, lifetime and failure
rules. The compiler does not recognize `main`, `advance`, or any service name.

`Foreign` is a sealed, generic effect label, not an operation or authority
token. Source providers cannot remove it. Its descriptors are inspectable at
const time, but calling a foreign function is not. Closed function annotations
can also name source operations, as in `Unit -> U32 ! {Reader.ask}`.

[The concrete host API proposal](host-api-proposal.md) and
[Blot specimen](../examples/host_capabilities.blot) show ordinary records of
typed callbacks, an explicit entrypoint, source effect adapters and the reload
boundary. Their record bundles, Text/buffers and persistent world values still
need implementation; they must not be confused with the implemented scalar ABI.

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

Tuples, record construction/patterns, immutable arrays and file imports now
execute inside the guest, but do not cross the scalar host boundary. Before
reconnecting the sandbox: implement record field access and state resolvers,
stabilize the composite capability/state ABI, implement the ECS in source, then
restore render packets and transactional live reload. Do not restore the retired
domain backend.
