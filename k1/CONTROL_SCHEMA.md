# Private Boolean control-flow fixture

This is an experimental, closed subset of K1-LANG for one private declaration.
It is not public admission, a portable CheckedFunction, a full resource or
proof judgment, or K1-01 completion. The caller supplies a canonical Bool
argument (0 or 1) under the internal K1 callable convention.

```
let name: Bool -> U32 = fn parameter => do:
  if condition:
    return decimal_u32
  else:
    return decimal_u32
condition := atom | atom && atom | atom || atom
atom := parameter | #True | #False
```

One declaration, one if, no other statements, no expressions beyond the
specified atoms, and no implicit return are admitted. Each physical suite is
checked by the K1 lexer. Branches return U32 literals in range. The source
parser emits owned numeric tags, half-open byte spans, and the explicit
function target of each return; it keeps no borrowed pointers. An independent source recognizer and Core validator recheck
the full source, operand bindings, exact spans, integer values, op, complete
branch returns and absence of extra statements before any encoding. All other
constructs are rejected. Literal-condition control paths do not grant any
numeric or ownership facts in this subset.

Wasm uses the canonical `(environment:i32, Bool:i32)->i32` callable. The
conditional and each short-circuit expression use Wasm `if (result i32)`,
with a constant in the unexecuted alternative. No eager `i32.and` or `i32.or`
substitutes for `&&`/`||`. The fixture exposes its private callable for tests;
it is not a public host API, ABI manifest, or M13 certificate. Test-only probe
modules may place `unreachable` in the right-hand side to demonstrate that it
is skipped. No admitted source constructs a trap.
