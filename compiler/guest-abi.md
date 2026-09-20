# Guest ABI 1: explicit scalar capabilities

This is the implemented boundary, not the broader
[record/buffer/persistent-state proposal](host-api-proposal.md). Run
`just demo-host` for [the executable example](../examples/host_io.blot).

```blot
export fn main (advance: U32 -> U32 ! {Foreign}) => do:
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

`main` and `advance` are ordinary names. The host selects an export and supplies
its callable argument; there is no implicit entrypoint, ambient registry,
operation-name dispatcher, or game-specific import. Declaring a source effect
does not create host authority. Providers can forward source operations into a
supplied callback; their inferred residual row still contains `Foreign`.

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

Every export takes exactly one argument and returns one value. Arguments are
scalars or a single scalar-to-scalar callback with exactly the closed `Foreign`
row. Results and exported constants are scalars. Pure callbacks, unknown/open
rows, callback results, algebraic values and bundles are not host ABI values.

| Blot type       | Adapter value                        | Wasm boundary representation  |
| --------------- | ------------------------------------ | ----------------------------- |
| Unit            | `null`                               | `i32`, canonical zero         |
| U32             | integer from 0 through 2³²−1         | `i32`, same 32 bits           |
| Bool            | `boolean`                            | `i32`, canonical 0 or 1       |
| F32             | `number`, rounded with `Math.fround` | `f32`; NaN/infinities allowed |
| Scalar callback | opaque `guest.capability(...)` token | `externref`                   |

Arguments and callback results are validated, not JS-coerced. U32 values
returned by Wasm are converted from signed i32 representation back to unsigned
numbers. Unit callbacks return `null`, not `undefined`. `guest.read(name)` reads
a scalar constant. The adapter does not expose the instance, arena or raw
callable refs.

Capability modules import only signature-specific adapters from `blot:host/1`:
`call_<parameter>_<result>`, with lowercase `unit`, `u32`, `bool`, or `f32`.
Each import takes `(externref, scalar)` and returns a scalar. For example,
`call_u32_f32` has Wasm signature `(externref, i32) -> f32`. Signatures are
deduplicated in first-export occurrence order. Scalar-only modules remain
import-free.

The wrapper creates an ordinary internal closure pointing to a signature stub.
Calls through source functions, closures, and providers use the usual internal
application ABI. No special foreign expression or domain operation enters the
IR. Direct function relocations account for imports; cached table slots and
symbolic function bodies do not acquire hard-coded import indices.

## Versioned manifest

Exactly one custom section named `blot:abi` is required by the adapter. Its
payload is, in order:

1. Version: canonical unsigned LEB128 U32, currently `1`.
2. Function count: unsigned LEB128 U32. For each exported function: name,
   parameter type, result scalar type.
3. Constant count: unsigned LEB128 U32. For each exported constant: name, scalar
   type.

Names are a canonical unsigned LEB128 byte length followed by UTF-8 bytes,
without normalization or BOM stripping. Scalar type tags are one byte:
`0 = Unit`, `1 = U32`, `2 = Bool`, `3 = F32`. A callback parameter is tag `4`
followed by its scalar parameter tag and scalar result tag. Counts preserve
export declaration order within functions and constants. Duplicate names,
unknown tags/versions, invalid UTF-8, truncated or trailing bytes, and imports
or exports inconsistent with the manifest are errors.

Test vectors (payload only): an empty module is `01 00 00`; a single export
`main: (U32 -> U32 ! {Foreign}) -> U32` is
`01 01 04 6d 61 69 6e 04 01 01 01 00`.

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

Calls are synchronous. Promises/thenables produce `async_host_call`; rejected
Promises are observed to avoid a second unhandled rejection. Host exceptions
produce `host_exception` with the original cause. These failures do not poison
the next invocation. The adapter rejects same-instance reentry (including
disposal during a call), because each export resets its private arena. Calling a
different guest is allowed. All host bindings are released on disposal.

The host is trusted: this does not isolate mutually untrusted libraries inside
one guest, validate arbitrary binaries as compiler-produced programs, cancel
already-started asynchronous host work, or roll back IO already performed.
Engine callbacks must implement their own command staging before speculative
frames can be transactional.

Reload creates a new instance and rebinds callbacks explicitly. ABI 1 carries no
persistent guest state; closures, records, Text, arrays/buffers, multiple
capabilities per call, asynchronous IO and world-state migration remain future
ABI work. Do not copy arena pointers or old tokens into a replacement instance.
