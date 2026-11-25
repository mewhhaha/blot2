---
name: blot-diagnostics
description: Interpret and fix Blot compiler diagnostics ([CODE]) quickly using exact blame spans, ownership rules, and minimal before/after fixes.
---

# Blot Diagnostic Handbook

Every Blot CLI diagnostic has the same structure:

```text
[CODE] <one-sentence explanation>
in <file> › <enclosing declaration>
at <file>:<line>:<col>
  <line> | <related source line>
         | ---- <secondary blame label (move / borrow / parameter)>
  <line> | <failing source line>
         | ^^^^ <primary label>
fix: <minimal concrete fix>
doc: blot explain <CODE> (skills/blot-diagnostics/SKILL.md#<CODE>)
```

Run `deno task blot explain <CODE>` for the built-in CLI lookup or jump straight to the matching `#CODE` section below.

---

## SYNTAX_ERROR

**Cause:** Token does not match Blot's indentation-sensitive grammar.

**Most frequent agent mistakes:**
- Using `fn` instead of `func`, or `-> Ret` instead of `: Ret =>`.
- Using `{ ... }` braces for function/if/loop bodies instead of indented suites after `=>` / `:`.
- Writing `type Opt = Some U32 | Nothing` instead of `type Opt is data = $Some U32 | $Nothing`.
- Writing `&&` / `||` / `!` instead of `and` / `or` / `not`, or `mut` / `var` instead of `let` + `:=`.

```blot
// Before
fn add (a: U32, b: U32) -> U32 { return a + b }

// After
func add (a: U32) -> (b: U32): U32 => return a + b
```

---

## UNMATCHED_DELIMITER

**Cause:** Unclosed or mismatched `(`, `[`, `#[`, or `{`.

```blot
// Before
let xs = #[1, 2, 3

// After
let xs = #[1, 2, 3]
```

---

## UNSUPPORTED_EXPRESSION

**Cause:** Bare `[...]` list literal or retired expression syntax.

```blot
// Before
#entry func main (): #[U32] => return [1, 2, 3]

// After
#entry func main (): #[U32] => return #[1, 2, 3]
```

---

## UNKNOWN_VALUE

**Cause:** Identifier is not bound in scope.

**Most frequent fixes:**
- Missing `$` prefix on a data constructor: `Some 1` → `$Some 1`, `None` → `$Nothing`.
- Typo in local/global name (follow the compiler's `did you mean \`...\`?` hint).
- Non-Blot primitive names: use `U32`, `F32`, `Bool`, `Unit`, `#[U8]`.

```blot
// Before
type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return Some 1

// After
type Opt is data = $Some U32 | $Nothing
#entry func main (): Opt => return $Some 1
```

---

## MISSING_MEMBER

**Cause:** Receiver type has no field or associated member with that name.

**Most frequent fixes:**
- Arrays use `.length` (not `.len`).
- Append with `@storage.push arr item`.
- Match exact field names shown in the receiver record type.

```blot
// Before
let n = arr.len

// After
let n = arr.length
```

---

## TYPE_MISMATCH

**Cause:** Inferred expression type does not unify with the declared or expected type.

**Most frequent fixes:**
- No implicit `U32`/`F32` conversion: use `@u32.to_f32` / `@f32.to_u32` or match literal syntax (`1` vs `1.0`).
- Curried calls take space-separated args (`f a b`); `f (a, b)` passes a single tuple.

```blot
// Before
#entry func main (): U32 => return 1.5

// After
#entry func main (): F32 => return 1.5
```

---

## SPENT_VALUE

**Cause:** A local binding was moved (secondary `-` label shows the exact move site: `own` call, `freeze`, or field move) and then read again.

```blot
// Before
let a = #[1, 2, 3]
let n = consume a
return n + a.length

// After (keep `a` live)
let a = #[1, 2, 3]
let n = consume a.copy
return n + a.length
```

Or return the owned value from `consume` and thread it forward (`let a = transform a`).

---

## ALIASED_UPDATE

**Cause:** `:=` index write, `@storage.push`, or `@storage.truncate` mutates storage that another live binding borrows (secondary `-` label names the borrow holder) or that arrived as a non-`own` parameter.

```blot
// Before (aliased local)
let a = #[1, 2, 3]
let b = a
a[0] := 99
return a[0] + b[0]

// After (snapshot before mutating)
let a = #[1, 2, 3]
let b = a.copy
a[0] := 99
return a[0] + b[0]
```

```blot
// Before (borrowed parameter)
func set0 (a: #[U32]): #[U32] =>
  a[0] := 99
  return a

// After (take ownership)
func set0 (a: own #[U32]): #[U32] =>
  a[0] := 99
  return a
```

---

## OWN_ARGUMENT

**Cause:** An `own` parameter (or `freeze`) was given a borrowed, aliased, or outer-loop value instead of a uniquely owned value.

- Pass `x.copy` if the caller still needs `x`.
- Mark the caller's parameter `own` to forward ownership without copying.

---

## RESULT_NOT_OWNED

**Cause:** A non-entry function returned borrowed or aliased storage instead of a fresh or uniquely owned value.

- Return `x.copy`, or mark the source parameter `own`.

---

## ENTRY_TYPE

**Cause:** A declaration marked `#entry`, `#kernel`, or `#process` leaves an algebraic effect unhandled (`(unhandled: Effect.op)`) or uses a type outside ABI 8, such as a closure.

```blot
// Before
type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  use t <- Clock.now ()
  return t

// After
type Clock is effect = { now: Unit -> U32 }
#entry func main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t
```

---

## EFFECT_MISMATCH

**Cause:** An effectful call appears in a pure position (`let`, `const`, `spark`, `#kernel`, or pure function signature).

- Use `use x <- Effect.op arg` instead of `let x = Effect.op arg`.
- Keep `spark #[...]` and `#kernel` pure.

---

## NON_EXHAUSTIVE_MATCH

**Cause:** `case ... of` or refutable `let` does not cover all variants.

- Add missing `$Variant` arms or `_ => ...`.
- For refutable `let`, add `else:` with an exiting suite (`return` / `break`).

---

## FUNCTION_RETURN_REQUIRED

**Cause:** Indented function body falls off the end without an explicit `return`.

- Add `return <value>` on every branch, or write single-expression `func x => expr`.

---

## DUPLICATE_NAME

**Cause:** Two top-level declarations, record fields, or pattern bindings share a name.

- Rename the duplicate declaration, or use `x := next` to update an existing local.

---

## UNKNOWN_REBINDING

**Cause:** Left-hand side of `:=` is not a local `let` binding or parameter in scope.

- Declare local state with `let x = init` before `x := next`; module `const` values are immutable.
