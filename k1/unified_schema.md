# Private unified U32 and control-flow fixture

This experimental whole-source path accepts a single declaration of the form
`let NAME: U32 -> U32 = fn PARAM => do: ...`. It supports nested `if`/`else`,
sequential statements, and explicitly returning U32 values. Local `let`
initializers have U32 type, run before the name enters scope, and may occur in
function or branch suites. A branch-local name cannot be used by its sibling or
after the branch. The same name may be used in distinct, non-overlapping
branches; rebinding an active name is rejected by this subset.

U32 expressions support local/parameter names, U32 literals, parentheses,
ordinary `+`, total bitwise `&`, and `U32.wrapping_add`, `wrapping_sub` and
`wrapping_mul`. Conditions support `#True`, `#False`, U32 `<`, parentheses,
and short-circuit `&&`/`||`. Precedence follows K1-LANG for these forms.
For ordinary addition, the private checker establishes safety only when one
operand is a direct zero literal or both are direct literals whose sum fits.
It conservatively rejects other additions, including `x + (0)`; wrapping
operations produce no arithmetic facts. Every branch is syntax/name/type/proof
checked even when its condition is a literal. Completion accounts for literal
conditions and explicit transfers; it does not implement general finite facts.

The candidate owns the complete source. A separate recognizer re-lexes the
caller-retained immutable expected source, rebuilds lexical scope and every
typed node, rechecks each addition, and independently recomputes completion.
Emission first requires exact byte equality and this revalidation. The local
2,048-node, 128-binding, 64-frame, 32,768 lowering-step and 65,536-byte output
limits are fixture bounds, not K1 semantic budgets or work receipts.

F32, Unit and tuple values, Bool locals/parameters, other scalar operators,
calls except the three wrapping intrinsics, value blocks, loops, arbitrary
patterns, public or multiple declarations, imports, resources, effects,
storage and the remaining K1 grammar are unsupported. The private statuses are
not qualified K1 diagnostics. This is not a portable checked artifact, public
compiler command, copy-only host bridge or ABI certificate. The test module
exports a raw `(environment: i32, U32: i32) -> i32` function with fixed test
memory and no imports. An `unreachable` after completed source control provides
Wasm stack polymorphism; it is not used to establish source completion. The
separate test-only probe injects a trap into a Bool right operand to witness
short-circuit execution.
