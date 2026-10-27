# First complete migration

The historical input is [an array identity](../migration/legacy/copy.blot) and
its [generic helper](../migration/legacy/helpers.blot). The K1 equivalents are
[copy.blot](../examples/migration/copy.blot) and
[helpers.blot](../examples/migration/helpers.blot). The host uses the same
copy-only boundary as other K1 programs:

```sh
build/blot migrate migration/legacy/copy.blot
build/blot build examples/migration/copy.blot -o build/migrated.wasm \
  --bridge-config=examples/migration/copy.json
deno run --allow-read migration/run.ts
```

The migration was reviewed manually. `const` becomes an immutable `let`, the
helper receives an explicit rank-1 boundary, calls use parentheses and type
arguments, and both functions return explicitly. Effects and conservative
resource contracts are visible in the public interfaces.

The managed Array becomes a borrowed View with an explicit Region, length and
Domain. The generic copy bridge supplies a destination and owns cleanup. This
identity does not write into that destination, so it consumes it with
`dest.discard`, packages the input View, and lets the bridge copy the result
before releasing its backing. No implicit allocation or retained host pointer
is introduced. The host handles `OutputTooSmall`, `InvalidInput`, reservation
and frame failures through the documented status protocol.

The migration command reports exact token spans for bindings, callable
return/resource/capture review, managed arrays, checked arithmetic, index
bounds, rebinding and unavailable constructs. It skips comments and quoted
import paths. It makes no automatic semantic changes. Its findings are review
prompts, not a legacy type checker: it cannot infer an application's desired
overflow, out-of-bounds or reservation-failure policy. This example performs no
arithmetic or indexing and captures no authority; other migrations must resolve
those findings explicitly.

`tests/migration_test.ts` executes the imported helper through the host bridge
at zero, singleton, maximum configured length and maximum U32 values, and checks
copy independence and failure statuses. The editor gate uses the real
TextMate/Oniguruma engine and checks every example's formatter round trip.
