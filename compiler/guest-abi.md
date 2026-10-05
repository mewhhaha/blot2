# Guest ABI 2: numeric arrays and explicit host capabilities

This is the implemented host boundary. See
[the executable host example](../examples/host_io.blot).

```blot
entry const main = fn (advance: U32 -> U32 ! {Foreign}) => do:
  use next <- advance 41
  return next
```

```ts
import { instantiateGuest } from "./compiler/guest.ts";

const guest = await instantiateGuest(artifact.bytes);
try {
  const advance = guest.capability({
    parameter: "U32",
    result: "U32",
    call: (value) => value + 1,
  });
  console.log(guest.call("main", advance)); // 42
} finally {
  guest.dispose();
}
```

`main` and `advance` are ordinary names; `entry` makes `main` a host entrypoint.
The entry module's `entry const` and `entry let` declarations are exactly the
module's exports. The host selects one and supplies its callable argument; there
is no implicit entrypoint, ambient registry, operation-name dispatcher, or
game-specific import. Declaring a source effect does not create host authority.
Providers can forward source operations into a supplied callback; their inferred
residual row still contains `Foreign`.

`Foreign` is one sealed compiler effect label, identified internally by the pair
`("blot:compiler", "Foreign")`. It is not a callable operation and cannot be
declared or discharged by a source provider. `! {Foreign}` annotates a
function's latent effect; acquiring the function value is pure. Calling it
requires `use` in a binding and is forbidden in const evaluation. Reflection is
inert: `@effect.descriptor Foreign` and `@effect.has (@effect.of main) Foreign`
expose requirements, never a callable or handle.

Closed row annotations also accept declared operation names, for example
`Unit -> U32 ! {Reader.ask}`. A suffix annotates the outermost arrow;
`U32 -> (U32 -> U32 ! {Foreign})` instead describes a pure function returning an
effectful function. Open rows are inferred in higher-order source code, not
written in this first annotation syntax.

## Values and Wasm signatures

Every export is an entry declaration and takes exactly one argument and returns
one value; an entry whose final type does not fit is a compile error
(`entry_type`, or `entry_let_type` for a runtime-initialized value). Arguments
are scalars, `Array U32`, `Array F32`, or a single scalar/numeric-array callback
with exactly the closed `Foreign` row. Results are scalars or numeric arrays;
exported constants remain scalars. Callback arguments/results use the same
scalar and numeric-array types. Pure callbacks, unknown/open rows, callback
results, algebraic values and bundles are not host ABI values.

| Blot type     | Adapter value                        | Wasm boundary representation  |
| ------------- | ------------------------------------ | ----------------------------- |
| Unit          | `null`                               | `i32`, canonical zero         |
| U32           | integer from 0 through 2³²−1         | `i32`, same 32 bits           |
| Bool          | `boolean`                            | `i32`, canonical 0 or 1       |
| F32           | `number`, rounded with `Math.fround` | `f32`; NaN/infinities allowed |
| Array U32     | copied `Uint32Array`                 | `i32` array pointer           |
| Array F32     | copied `Float32Array`                | `i32` array pointer           |
| Host callback | opaque capability token              | `externref`                   |

Arguments and callback results are validated, not JS-coerced. U32 values
returned by Wasm are converted from signed i32 representation back to unsigned
numbers. Unit callbacks return `null`, not `undefined`. `guest.read(name)` reads
a scalar constant. The adapter does not expose the instance, arena or raw
callable refs.

Capability modules import only signature-specific adapters from `blot:host/1`:
`call_<parameter>_<result>`, with lowercase `unit`, `u32`, `bool`, `f32`,
`array_u32`, or `array_f32`. Each import takes `(externref, value)` and returns
a value; array values are i32 pointers into the guest arena. For example,
`call_u32_f32` has Wasm signature `(externref, i32) -> f32`. Signatures are
deduplicated in first-export occurrence order. Scalar-only modules remain
import-free.

The wrapper creates an ordinary internal closure pointing to a signature stub.
Calls through source functions, closures, and providers use the usual internal
application ABI. No special foreign expression or domain operation enters the
IR. Direct function relocations account for imports; cached table slots and
symbolic function bodies do not acquire hard-coded import indices.

## Copied numeric arrays

```blot
const advance = fn (positions: Array F32) => @array.set positions 0 42.0
const packet = fn (count: U32) => @array.fill count 0.0
```

```ts
const positions = new Float32Array([1, 2, 3]);
const next = guest.call("advance", positions); // Float32Array([42, 2, 3])
// positions stays [1, 2, 3]; next owns separate storage.
```

The adapter copies numeric inputs into guest memory and copies results back into
fresh typed arrays before resetting the arena. Empty arrays are supported.
Pointers never escape through `Guest`; inputs, results, later calls and
replacement instances cannot alias each other's storage. A host can retain a
returned packet and supply it to a replacement guest after reload. Its schema
and compatibility are application responsibilities.

Only modules with array arguments/results (including callback signatures) export
`blot:memory`, `blot:allocate` and `blot:reset` for the adapter. Allocation
takes an i32 byte count and returns an aligned i32 pointer. Reset takes an
ignored i32 and returns the first dynamic arena byte. Arrays use a little-endian
U32 length followed by contiguous 32-bit words, with F32 values stored as
IEEE-754 bits. Memory grows on demand through the Wasm32 address space, subject
to the engine's available memory. Allocation overflow and failed growth trap.
The adapter checks typed-array kinds, lengths, aligned pointers and ranges; it
acquires fresh memory views after allocation and guest execution because either
can grow memory. It resets before preparing inputs and in `finally` after output
copying, including traps. Raw Wasm callers must implement the same lifetime.

## Versioned manifest

Exactly one custom section named `blot:abi` is required by the adapter. Its
payload is, in order:

1. Version: canonical unsigned LEB128 U32, currently `2`.
2. Function count: unsigned LEB128 U32. For each exported function: name,
   parameter type, result value type.
3. Constant count: unsigned LEB128 U32. For each exported constant: name, scalar
   type.

Names are a canonical unsigned LEB128 byte length followed by UTF-8 bytes,
without normalization or BOM stripping. Scalar type tags are one byte:
`0 = Unit`, `1 = U32`, `2 = Bool`, `3 = F32`. A callback parameter is tag `4`
followed by its value parameter tag and value result tag. Numeric array value
tags are `5 = Array U32` and `6 = Array F32`. Counts preserve export declaration
order within functions and constants. Duplicate names, unknown tags/versions,
invalid UTF-8, truncated or trailing bytes, and imports or exports inconsistent
with the manifest are errors.

Test vectors (payload only): an empty module is `02 00 00`; a single export
`main: (U32 -> U32 ! {Foreign}) -> U32` is
`02 01 04 6d 61 69 6e 04 01 01 01 00`.

The manifest describes types, not permissions. It is independent of compiler
analysis/protocol metadata. This is a Blot ABI using Wasm reference types, not a
claim of WIT/Canonical ABI compatibility. The
[WebAssembly JS interface](https://www.w3.org/TR/wasm-js-api-2/) specifies
`externref`, imports, and custom-section access used by the adapter.

## Lifetime, failure, and reload

Tokens are owned by one guest instance and checked against private identity
metadata. Numbers, copied token properties, another instance's token, or a
disposed token cannot authorize a call. Definitions are snapshotted when bound;
mutating the caller's descriptor does not change the installed signature.

Every invocation creates a fresh opaque reference. Only its active adapter call
can use it; `finally` expires it on success, trap, bad result, or host
exception. Wrappers clear their reference global on normal return. On a trap it
may retain an inert reference until the next call, never a live callback. Tests
also cover a Wasm module deliberately retaining and retrying a previous call's
reference.

`guest.call` and `guest.capability` are synchronous. Unexpected
Promises/thenables produce `async_host_call`; rejected Promises are observed to
avoid a second unhandled rejection. Host exceptions produce `host_exception`
with the original cause. These failures do not poison the next invocation. The
adapter rejects same-instance reentry (including disposal during a call),
because calls share the invocation arena. Calling a different guest is allowed.
All host bindings are released on disposal.

The host is trusted: this does not isolate mutually untrusted libraries inside
one guest, validate arbitrary binaries as compiler-produced programs, cancel
already-started asynchronous host work, or roll back IO already performed.
Engine callbacks must implement their own command staging before speculative
frames can be transactional.

Reload creates a new instance and rebinds callbacks explicitly. Persistent state
can be represented by copied numeric packets owned by the host. Closures,
records, Text, nested arrays and multiple capabilities per call remain outside
this ABI. Do not copy arena pointers or old tokens into a replacement instance.

## Suspended program entrypoints

Create a guest with `{ asynchronous: true }`, bind a `capabilityAsync` and start
its entrypoint with `callAsync`. This requires WebAssembly JS Promise
Integration (`WebAssembly.Suspending` and `WebAssembly.promising`); missing
support reports `unsupported_async`. Imports are bound when instantiating, so
the asynchronous mode is selected once. An asynchronous guest rejects
synchronous `call`.

```ts
const guest = await instantiateGuest(bytes, { asynchronous: true });
const host = guest.capabilityAsync({
  parameter: "Array F32",
  result: "Array F32",
  call: async (packet) => await nextInput(packet),
});
await guest.callAsync("main", host);
guest.dispose();
```

A callback can return a value immediately or resolve a Promise/thenable later.
Suspension preserves the Wasm stack, locals, capability and guest allocations.
The adapter does **not** reset the arena between host callbacks: it resets only
before entering the program and after that invocation completes or fails.
Callback packets are still copied on both crossings. Keeping a world in a
program local does not transfer it to the host unless the program includes it in
a callback packet.

Only one invocation may be active per instance, including while suspended.
Reentry, constant reads, new capability binding and disposal remain rejected
until the invocation settles. Shutdown is cooperative: reject or resolve the
pending host callback so the invocation can unwind, then dispose. A rejected
host callback produces `host_exception` with the original rejection as its
cause. A new invocation remains possible after cleanup.

Suspension alone does not reclaim allocations. Every fourth backedge of an
eligible `for ever:` loop, the runtime traces the carry's object graph and
reuses unreachable allocation blocks. Each loop activation has its own counter,
so nested loops cannot consume an outer loop's collection turns. Collection
amortizes tracing work while adding latency to the iterations that collect.
Carries may contain tuples, records, variants, closures, and nested arrays; no
numeric-buffer packing or annotation is required. Objects do not move, so
sharing, immutable aliases, and rollback versions retain their addresses.
Pre-loop objects remain pinned and their outgoing references are traced as well.

Collection requires a checked, closed function effect row containing only
`Foreign` or no effects, including curried functions with that checked type.
Loops inside lexical effect handlers remain excluded. The collector recognizes
exact allocated object starts conservatively: a scalar with the same bits as a
pointer can retain an extra object, but its bits are never changed. Foreign
packets remain copied values, not roots or borrowed heap views.

Allocation blocks carry private headers and use size classes for reuse. Dynamic
blocks start at or above 64 KiB so common small integer IDs cannot be mistaken
for dynamic pointers; static data can still occupy the first page. The
exact-start bitmap is reused while block boundaries remain unchanged, and
invalidated by fresh bump allocation, including the first such allocation after
an arena reset. The arena's high-water mark can therefore exceed the live
payload size. Memory must fit the live graph, up to four iterations of temporary
allocations, and temporary collection metadata. `blot:allocate(0)` observes that
high-water cursor; cursor differences are not cumulative allocation counts once
blocks are reused. The host must not reset memory while a suspended invocation
still holds pointers.
