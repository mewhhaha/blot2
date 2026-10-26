# Private tagged source-to-Wasm compiler experiment

This is a single source entry for three checked alternatives, not a general K1
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

If both original alternatives reject, a third checked alternative admits a
bounded mixture of scalar expressions and loop control in one source-owned
node and binding arena. It supports scalar U32 locals, grouping, less-than,
explicit `U32.wrapping_add`, and checked `+` with independently checked
literal/zero proofs or a source-bound proof for a successor `value + 1`.
For the latter, a dominating U32 less-than guard establishes that its left
operand is below the maximum, and the false edge establishes a non-strict
relation in the reverse direction. Bounded paths through those source guard
edges can connect an exact binding or immutable alias to the dominating fact.
The independent consumer re-recognizes the source, binding identities, edge
polarities and proof path before emission. Facts and aliases start fresh for
each loop body; branch-derived facts do not escape a join, and no proof is
carried across a backedge. Each expression is limited to depth 128.
Existing alternatives run first, preserving their accepted sources and
diagnostic statuses; a still-rejected source retains its original status.
The mixed alternative is not yet the same IR as the original scalar variant,
and the formatter does not yet support it. A common typed expression/binding
arena across all paths and shared proof traversal are still needed.
Invariants, multiple carries, tuple/Bool loop results, Bool conditions beyond
the supported literals and U32 less-than,
generic functions, imports, effects, resource checking, array/storage and
ownership/loan operations remain unsupported in this path. No explicit portable
proof artifact, complete work receipt or independent Wasm target certificate is
produced. In particular, fact construction and replay have bounded local
limits but no complete C09 work accounting. Private statuses are not qualified
K1 diagnostics.

The scalar alternative retains the unified path's 16 MiB input limit; the loop
alternative has a local 65,536-byte source limit and at most 128 bindings and
128 loops. Output uses the existing test wrapper `(environment: i32, U32: i32)
and has no imports. This is not the K1 host bridge or a release artifact.
The emitted structured code may contain `unreachable` after source paths whose
explicit completion has already been checked; it is not used as proof.
