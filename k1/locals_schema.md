# Private U32 local-variable fixture

This private source-to-Wasm experiment accepts one whole declaration of the form
`let NAME: U32 -> U32 = fn PARAM => do: ...`. The body contains zero or more
immutable top-level `let` bindings, optionally annotated `: U32`, followed by
an explicit return or a single `if LEFT < RIGHT:` whose true and false paths
each explicitly return. The false return may appear in `else:` or after the
`if`. Each initializer is evaluated before its binder becomes visible, and
duplicate names (including the parameter) are rejected by this subset. No
branch-local binding or nested conditional is admitted.

U32 expressions comprise parameter and prior local names, decimal U32 literals,
parentheses, bitwise `&`, ordinary checked `+`, and the explicitly wrapping
`U32.wrapping_add`, `U32.wrapping_sub`, and `U32.wrapping_mul` intrinsics. `+`
binds more tightly than `&`; operands and initializers are evaluated left to
right. Every expression in this subset has U32 type. Ordinary addition is
accepted only when either operand is a **direct** zero literal, or both operands
are direct literals whose sum fits U32. Thus `x + 0` is admitted, `x + 1` is
rejected without evidence, and even the safe `x + (0)` is conservatively not
proved by this fixture. Wrapping results do not generate arithmetic facts.

The candidate owns source bytes and postorder records. An independent source
recognizer reparses the caller's separately retained, immutable expected source,
rebuilds name resolution and each checked-add proof, and verifies every record
before emission. Exact source equality is required; a digest is not authority.
Unsupported syntax or proof failures return no program or output bytes. This
does not admit source-less artifacts, certify a K1 Core, or establish full K1
typing, diagnostics, completion, work accounting, scopes, or proof policy.

Calls other than the three fixed intrinsics, arithmetic other than `+`, U32
comparison forms other than `<` in the final condition, Bool/F32 values,
general control flow, loop syntax, nested functions, multiple declarations,
public exports, storage, and resource/effect contracts are unsupported. The
private local engineering limits are 2,048 value nodes, 128 bindings, 64 parser
frames, and a 65,536-byte lowering output; these are not K1 semantic budgets.

The Wasm test wrapper exports `(environment: i32, U32: i32) -> i32`, has no
imports, and is not a public K1 host bridge or ABI certificate. Arithmetic uses
Wasm i32 bit patterns; the checker has already established ordinary `+` safety,
while wrapping intrinsics intentionally use modulo arithmetic. An `unreachable`
after all source paths return supplies Wasm stack polymorphism; it does not
establish source completion.
