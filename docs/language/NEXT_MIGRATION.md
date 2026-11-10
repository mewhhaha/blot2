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
- Contracts become the only abstraction mechanism, as decided on 11 November 2026
  (see below). Remove string-named dispatch only after contract dispatch covers
  every existing operator, conversion, receiver and update use.
- Type declarations name their kind after `is`: `data`, `effect`, `contract` and
  `opaque` (`type Token is opaque = U32`). The `opaque type` prefix is retired.
- Runtime `TypeInfo` is an explicitly later stage of the RFC.

## Implementation sequence

| Stage | Zig | Goose |
| --- | --- | --- |
| Named module declarations, qualified names, predicates, entries, tags, imports | Affected checks pass | Parser checked; checker mirrored |
| Local declaration policy, overload resolution and parameter clauses | Pending | Pending |
| Parameterized namespaces and member lookup | Pending | Pending |
| Type values, `#type_of` and symbolic validation | Pending | Pending |
| Staged statements, capabilities and tracked build inputs | Pending | Pending |
| Immutable collections, moves and automatic copy admission | Pending | Pending |
| Standard library, Ink and Gdev named-function source migration | Source migrated; qualification recorded in CONTINUE.md | Uses Zig candidate |
| `type X is opaque` spelling | Done | Parser mirrored and law-checked |
| Contract-only abstraction (below) | Pending; follows namespaces | Pending |
| Remaining RFC library/application migration and surface removal | Pending | Pending |
| Optional runtime type descriptors | Later | Later |

The existing Goose port remains an experiment: it has no whole compiler
executable. Its partial checks do not qualify these new language semantics.
Preserve the original pinned Zig oracle for old-language comparisons; use a new
checked Zig candidate when testing migrated Goose behavior.

## Contracts and implementations

Decided 11 November 2026. Today there are two disjoint systems:

- **Associated functions** (`func Vec3.add`), selected by string-named dispatch
  (`@type.call "add"`, `where { associated "add" a a a }`). Only the type's own
  module can define them.
- **Contracts with `impl`.** Other modules can extend these, but their members
  are reached only as `Contract.member` and never feed operators or receivers.

They become one system:

```blot
type Add [left, right] is contract = { type Output, func add: left -> right -> Add.Output [left, right] }
type Eq a is contract = {
  func equal: a -> a -> Bool,
  func different left right => return not (equal left right),
}
type Ord a is contract = { Eq a, func compare: a -> a -> Ordering }

impl Add [Vec2, Vec2] = { type Output = Vec2, func add left right => return ... }
impl Eq (List a) where { Eq a } = { func equal left right => ... }
const twice: a -> a where { Add [a, a], type_eq (Add.Output [a, a]) a } =
  func value => return value + value
```

- **Contracts are the only abstraction.**
  - Operators and conversions are std contracts. `+` means `Add.add`; `from`
    conversions are a contract selected by the output type.
  - `where { Add [a, a] }` replaces `associated "add" a a a`. The `associated`,
    `result`, `receiver` and `update` predicates and `@type.call` are removed.
  - `field` remains a structural record predicate.
- **Heterogeneous operators.** `Add` takes both operand types, and its result is
  the associated `Output`. Selection is by the exact `[left, right]` head, so
  there is no left-then-right fallback. Either operand type's module may own the
  impl.
- **Composition.**
  - Contracts include contracts (as today).
  - Contracts may define default function members in terms of their other
    members. A new member with a default extends a contract without breaking
    existing impls. An impl may override a default; defined type equations
    still cannot be overridden.
- **Extension.**
  - An impl lives in the contract's module or in the module of its head's anchor
    nominal type (today's rule), and heads stay disjoint across the module graph.
  - Conditional impls use `where` prerequisites over the head's variables.
  - A third module that owns neither side wraps the type in `type X is opaque`.
    Opaque wrappers are erased at runtime, so this costs nothing.
- **Impls are anonymous.** `impl Contract Head = { ... }` is identified by its
  contract and head. Free lowercase head variables are inferred, as in
  annotations. Members use `func` and `type`, matching contract members.
- **Access through namespaces.**
  - `Contract.member` always works.
  - Receiver syntax `value.member` and `(Head)::member` also find a member of a
    contract implemented for the receiver's type, with any contract in scope
    considered. When several contracts supply that name, the use must be
    qualified.
  - Inherent members (`func Vec2.length`) remain plain namespace functions,
    owned by the type's module. A field and a member with the same name stay
    ambiguous.
- **Conformance is explicit.** A type does not satisfy a contract just by having
  matching namespace members. Associated types need a definition site, defaults
  need an opt-in, disjointness must be checkable, and errors say which contract
  a type lacks.
- **Validators are separate.** Compile-time assertions over type values check
  invariants a contract cannot express; they never replace contract
  requirements in generic checking.
- **No runtime dictionaries.** Selection stays compile-time and monomorphizing.

Qualification needs semantic laws and executed Wasm for each of these:

- operator and conversion dispatch through contracts, including heterogeneous
  heads and missing-impl explanations;
- default members, overrides and composition;
- conditional and foreign-owner impls, and opaque-wrapper extension;
- receiver/namespace lookup and its ambiguity errors;
- disjointness across imports;
- removal of every string predicate.

Migrate std, Ink, Gdev and Pen sources in the same batch that removes the old
surface.

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
