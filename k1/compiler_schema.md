# Private tagged source-to-Wasm compiler experiment

This is a single source entry for two checked alternatives, not a general K1
compiler or a unified expression/loop IR. It first tries the existing unified
U32/Bool scalar frontend. If that does not accept the source, it can instead
recognize a bounded finite-loop declaration of the form
`let NAME: U32 -> U32 = fn PARAM => do: ...`. The iteration alternative reuses
the existing iteration parser, independent source recognizer and completion
checker on the exact original suffix beginning at `fn`; it never rewrites the
source to create that suffix. The checker independently re-lexes the full
header and requires exact caller-retained source bytes and exact suffix bytes.
Iteration byte offsets, binding IDs and targets are local to that suffix; they
are not comparable with unified-body IDs or portable source identities.

The loop alternative supports U32 parameters, literals and lexical names,
nested finite `for` loops, explicit `return`, Bool-literal `if`/`else`, and
either no carries or exactly one U32 carry. No-carry loops use `break` or
`continue`; single-carry loops use `next(value)` or `stop(value)` and bind the
loop's U32 result with `let`. Bounds and initial carry are evaluated once; zero
iterations preserve the initial carry. `stop` returns its supplied carry and
does not increment. The independent checker establishes `lo <= hi` only for
literal zero as the lower bound or two literal bounds in ascending order.
The emitted loop compares the current unsigned index against its saved upper
bound before executing the body, making the in-range increment safe in this
restricted representation. Other ranges are conservatively rejected.

The scalar and iteration variants cannot yet be mixed inside one body: loop
expressions currently accept names and literals, while general unified scalar
expressions have their own tree. A common typed expression/binding arena,
source-owned identities and shared proof traversal are needed to compose them.
Invariants, multiple carries, tuple/Bool loop results, general Bool conditions,
generic functions, imports, effects, resource checking, array/storage and
ownership/loan operations remain unsupported in this path. No explicit portable
proof artifact, complete work receipt or independent Wasm target certificate is
produced. Private statuses are not qualified K1 diagnostics.

The scalar alternative retains the unified path's 16 MiB input limit; the loop
alternative has a local 65,536-byte source limit and at most 128 bindings and
128 loops. Output uses the existing test wrapper `(environment: i32, U32: i32)
and has no imports. This is not the K1 host bridge or a release artifact.
The emitted structured code may contain `unreachable` after source paths whose
explicit completion has already been checked; it is not used as proof.
