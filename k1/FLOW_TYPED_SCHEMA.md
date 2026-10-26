# Private typed flow-to-Wasm experiment

The whole-source fixture accepts one declaration of the shape
`let NAME: Bool -> U32 = fn PARAM => do: ...`. The body subset has explicit
U32-literal returns, `if`/`else`, sequential statements, and Bool expressions
formed from the single parameter, `#True`, `#False`, grouping, `&&`, and `||`.
Nested conditionals and explicit early returns are supported. Every source
node, including one in a literal-pruned branch, is checked for name and type
validity. Functions with potentially reachable fallthrough are rejected.

The candidate owns the whole source. An independent checker re-lexes the header,
matches both names and the exact body bytes, then independently re-recognizes the
source-owned body and recomputes every type and decimal literal. Emission rejects
any mismatch, and requires an exact-byte match against the independently retained,
immutable source supplied by its caller. The declaration checker by itself
establishes internal consistency, not origin or source authority. This is a private
checked fixture; it is not a completed portable
artifact, source-less import protocol, public compiler command, ABI certificate,
or representation of the full K1 language. The declaration checker is unmetered
and does not establish required-work receipts, cache provenance, diagnostics,
effects or resource guarantees.

Calls, declarations within the body, Unit/tuple values, value blocks, loops,
arithmetic, user types, arrays, generics, captures, module imports, public
declarations, multiple declarations and signatures other than Bool to U32 are
rejected. Unsupported syntax and unimplemented semantic forms may share a
fixture error; those errors are not qualified K1 diagnostics. The flow parser's
local 2,048-node and 64-frame limits and the emitter's 16,384-step and 65,536-byte
limits are private engineering bounds, not semantic policy limits.

The fixture module exports one function with raw Wasm `(i32, i32) -> i32`,
where the first argument is the unused environment and the second is the Bool
parameter. The fixture caller supplies a canonical Bool encoded as 0 or 1. There
is no checked host adapter and no claim that this is the K1 host ABI. The module
has no imports and uses the existing fixed-memory test wrapper. Lowering uses
structured Wasm `if` to short-circuit `&&` and `||` and an explicit return for
each source return. The emitter appends an unreachable Wasm instruction after
the source control flow for stack polymorphism; completion is independently
checked before this point and the appended instruction is not evidence of it.
Test-only probe modules inject a trap in a selected right operand to witness
short-circuit behavior; those probe modules are never emitted by the ordinary
entry.
