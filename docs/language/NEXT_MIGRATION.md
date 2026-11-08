# Type-directed language migration

Target: [RFC #46](https://github.com/mewhhaha/blot2/issues/46), including its
8 November 2026 collection and automatic-copy decisions. The owner chose the
working Zig compiler first, followed by the Goose implementation. This document
tracks the migration; [guide.md](guide.md) remains the executable reference.

## Required behavior

- Keep indentation, currying, ordinary function values, explicit returns,
  effects, `:=`/`self`, scalar semantics, operators and Wasm ABI 8/session 2.
- Add named `func` declarations, static overloads and parameter patterns.
  Function values remain values, without implicit overload groups.
- Add parameterized type namespaces, `::` lookup, compile-time type values and
  `#type_of`. Type inspection must not execute the inspected expression.
- Extend `#run` to statements/scopes and explicitly supplied build capabilities;
  track build inputs. An effect requirement does not grant authority.
- Collections become logically immutable values. Last uses move; independently
  retained versions use an admitted, pure, type-directed copy or reject if the
  type cannot copy. Physical reuse must preserve every observable version.
- Keep `List` non-indexable and distinguish `Array`, `GrowArray`, `ResizeArray`,
  borrowed views and stable pool links. No GC, hidden refcounts or shared writes.
- Replace public contract/implementation boilerplate only after inferred member
  requirements, associated types and portable evidence have equivalent coverage.
- Runtime `TypeInfo` is an explicitly later stage of the RFC.

## Implementation sequence

| Stage | Zig | Goose |
| --- | --- | --- |
| Named module declarations, entries, tags, imports | Affected checks pass | Parser checked; checker mirrored |
| Local declaration policy, overload resolution and parameter clauses | Pending | Pending |
| Parameterized namespaces and member lookup | Pending | Pending |
| Type values, `#type_of` and symbolic validation | Pending | Pending |
| Staged statements, capabilities and tracked build inputs | Pending | Pending |
| Immutable collections, moves and automatic copy admission | Pending | Pending |
| Library/application migration and superseded surface removal | Pending | Pending |
| Optional runtime type descriptors | Later | Later |

The existing Goose port remains an experiment: it has no whole compiler
executable. Its partial checks do not qualify these new language semantics.
Preserve the original pinned Zig oracle for old-language comparisons; use a new
checked Zig candidate when testing migrated Goose behavior.

## Qualification

Use semantic Zig laws and executed Wasm, including rejected programs. Named
functions must cover curried calls, recursion, entries, imports, tags, ambiguity,
shadowing and capture initialization. Local hoisting requires coherent recursive
inference and closure conversion; parsing a declaration is not that behavior.

Collection checks must retain both old and new values, exercise moves and custom
copies, reject noncopyable duplication and escaping borrows, and preserve trap
and effect order. Measure inserted copies and physical reuse separately.

Validate coherent families once per source batch, then run the full compiler
gate before compiler checkpoints. Preserve exact source/toolchain identities.
Recheck real Ink/Gdev/Pen integration after semantic changes; do not overwrite
sibling source or assets as a substitute for migration.
