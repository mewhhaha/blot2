---
name: blot-diagnostics
description: Interpret and fix Blot compiler diagnostics ([CODE]) quickly using exact blame spans, ownership rules, and minimal before/after fixes.
---

# Blot Diagnostic Handbook

Every Blot CLI diagnostic has the same structure:

```text
[CODE] <one-sentence explanation>
from <input> via <generator> (stage0 <phase>)   # when emitted from a Stage-0 pipeline
in <file> › <enclosing declaration>
at <file>:<line>:<col>
  <line> | <related source line>
         | ---- <secondary blame label (move / borrow / parameter)>
  <line> | <failing source line>
         | ^^^^ <primary label>
fix: <minimal concrete fix>
doc: blot explain <CODE> (skills/blot-diagnostics/SKILL.md#<CODE>)
```

Run `deno task blot explain <CODE>` for the built-in CLI lookup or jump straight to the matching `#CODE` section below. Every `## <CODE>` heading in this handbook matches `DIAGNOSTIC_CATALOG` in `host/diagnostics.ts` 1-to-1.

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
const xs: #[U32] = #[1, 2, 3

// After
const xs: #[U32] = #[1, 2, 3]
```

---

## LEXICAL_ERROR

**Cause:** Invalid UTF-8, unexpected source character, unterminated string literal or invalid escape, out-of-range `U32`/`F32` literal, tab indentation, or misaligned layout dedent.

- Use spaces (never tabs) for indentation and start top-level declarations at column 1.
- Close string literals on one line and use only `\"`, `\\`, `\n`, `\r`, `\t` escapes.
- Keep integer literals in `0..4294967295` (`U32`) and float literals within finite `F32`.

```blot
// Before
const big: U32 = 999999999999

// After
const big: U32 = 4294967295
```

---

## UNSUPPORTED_EXPRESSION

**Cause:** Bare `[...]` list literal or retired expression syntax.

```blot
// Before
io main (): #[U32] => return [1, 2, 3]

// After
io main (): #[U32] => return #[1, 2, 3]
```

---

## UNKNOWN_VALUE

**Cause:** Identifier is not bound in scope.

**Most frequent fixes:**
- Missing `$` prefix on a data constructor: `Some 1` → `$Some 1`, `None` → `$Nothing`.
- Typo in local/global name (follow the compiler's `did you mean \`...\`?` hint).
- Non-Blot primitive names: use `U32`, `F32`, `Bool`, `Unit`, and `Text` (Unicode scalar strings `#[U32]` with `std/text`).

```blot
// Before
type Opt is data = $Some U32 | $Nothing
io main (): Opt => return Some 1

// After
type Opt is data = $Some U32 | $Nothing
io main (): Opt => return $Some 1
```

---

## MISSING_MEMBER

**Cause:** Receiver type has no associated member or field with that name.

**Most frequent fixes:**
- Arrays use `.length` (not `.len`).
- Append to an owned array with `arr := self.push item` (or `arr := @storage.push self item`).
- Match exact field names shown in the receiver record type.

```blot
// Before
io main (): U32 =>
  let xs = #[1, 2, 3]
  return xs.len

// After
io main (): U32 =>
  let xs = #[1, 2, 3]
  return xs.length
```

---

## UNKNOWN_RECORD_FIELD

**Cause:** A record literal, pattern, projection, or field update omitted a required field or named a field not declared on the record type.

- Check the declared field names on the record type and match them exactly.
- For nominal data records (`type Pt is data = $Pt { x: U32, y: U32 }`), construct with `$Pt { x: 1, y: 2 }`.

```blot
// Before
type Pt = { x: U32, y: U32 }
io main (): U32 =>
  let p: Pt = { x: 1, z: 2 }
  return p.x

// After
type Pt = { x: U32, y: U32 }
io main (): U32 =>
  let p: Pt = { x: 1, y: 2 }
  return p.x
```

---

## AMBIGUOUS_MEMBER

**Cause:** Member access, operator, state type, or associated result dispatch cannot be uniquely resolved without more concrete type information or non-colliding names.

- Add explicit type annotations on empty arrays (`let xs: #[U32] = #[]`) or polymorphic destinations.
- Avoid colliding record field and associated function names on the same type.

```blot
// Before
func empty_len (): U32 =>
  let xs = #[]
  return xs.length

// After
func empty_len (): U32 =>
  let xs: #[U32] = #[]
  return xs.length
```

---

## MISSING_IMPLEMENTATION

**Cause:** A required contract implementation is missing, orphan, overlapping, cyclic, or fails its prerequisites or associated type members.

- Provide an explicit contract implementation in the defining module, or operate on concrete fields directly.
- Break cyclic prerequisite or associated-type equations and supply every required associated type member.

```blot
// Before
type Box = { v: U32 }
func eq_box (a: Box) -> (b: Box): Bool => return a == b

// After
type Box = { v: U32 }
func eq_box (a: Box) -> (b: Box): Bool => return a.v == b.v
```

---

## UNKNOWN_CONSTRUCTOR

**Cause:** A `$Constructor` expression, pattern, or `is data` declaration used an unknown constructor name, invalid `$` marker, wrong arity, or unboxed recursive tag.

- Verify the constructor spelling matches a declared `type ... is data` variant in scope.
- Pass the exact payload arity declared by the variant, and use `#[Node]` indices rather than directly self-recursive tags.

```blot
// Before
type Opt is data = $Some U32 | $Nothing
io main (): Opt => return $Some 1 2

// After
type Opt is data = $Some U32 | $Nothing
io main (): Opt => return $Some 1
```

---

## TYPE_MISMATCH

**Cause:** Inferred expression type does not unify with the declared or expected type.

**Most frequent fixes:**
- No implicit `U32`/`F32` conversion: use `@u32.to_f32` / `@f32.to_u32` or match literal syntax (`1` vs `1.0`).
- Curried calls take space-separated args (`f a b`); `f (a, b)` passes a single tuple.

```blot
// Before
io main (): U32 => return 1.5

// After
io main (): F32 => return 1.5
```

---

## INFINITE_TYPE

**Cause:** A type annotation failed occurs-check, arity, kind, rank, concrete-representation, or supported-type validation (for example, writing `String` instead of `Text` or passing the wrong number of type arguments).

- Use `Text` (prelude alias for `#[U32]`) for Unicode strings, and `U32`/`F32`/`Bool`/`Unit`/`#[T]` for built-ins.
- Pass every required type argument (e.g. `Maybe U32`) and avoid cyclic `type` aliases.

```blot
// Before
io main (s: String): U32 => return s.length

// After
io main (s: Text): U32 => return s.length
```

---

## SPENT_VALUE

**Cause:** A local binding or record field projection was moved (secondary `-` label shows the exact move site: `own` call, `freeze`, or field move) and then read again.

```blot
// Before
func consume (xs: own #[U32]): U32 => return xs.length
io main (): U32 =>
  let a = #[1, 2, 3]
  let n = consume a
  return n + a.length

// After
func consume (xs: own #[U32]): U32 => return xs.length
io main (): U32 =>
  let a = #[1, 2, 3]
  let n = consume a.copy
  return n + a.length
```

For a moved field projection in call position (`fill row.xs`), parenthesize the copy: `fill (row.xs.copy)`. Or return the owned value from `consume` and thread it forward (`let a = transform a`).

---

## ALIASED_UPDATE

**Cause:** `:=` index write, `@storage.push`, or `@storage.truncate` mutates storage that another live binding borrows (secondary `-` label names the borrow holder), that arrived as a non-`own` parameter, or that is captured/aliased inside a `with` handler.

```blot
// Before
io main (): U32 =>
  let a = #[1, 2, 3]
  let b = a
  a[0] := 99
  return a[0] + b[0]

// After
io main (): U32 =>
  let a = #[1, 2, 3]
  let b = a.copy
  a[0] := 99
  return a[0] + b[0]
```

```blot
// Before
func set0 (a: #[U32]): #[U32] =>
  a[0] := 99
  return a

// After
func set0 (a: own #[U32]): #[U32] =>
  a[0] := 99
  return a
```

---

## OWN_ARGUMENT

**Cause:** An `own` parameter (or `freeze`) was given a borrowed, aliased, or outer-loop value instead of a uniquely owned value.

- Pass `x.copy` if the caller still needs `x`.
- Mark the caller's parameter `own` to forward ownership without copying.

```blot
// Before
func consume (xs: own #[U32]): #[U32] => return xs
func forward (xs: #[U32]): #[U32] => return consume xs

// After
func consume (xs: own #[U32]): #[U32] => return xs
func forward (xs: own #[U32]): #[U32] => return consume xs
```

---

## RESULT_NOT_OWNED

**Cause:** A non-entry function returned borrowed or aliased storage instead of a fresh or uniquely owned value.

- Return `x.copy`, or mark the source parameter `own`.

```blot
// Before
func pick (xs: #[U32]): #[U32] => return xs

// After
func pick (xs: #[U32]): #[U32] => return xs.copy
```

---

## ENTRY_TYPE

**Cause:** A declaration marked `io` leaves an algebraic effect unhandled (`(unhandled: Effect.op)`) or uses a parameter/result type outside raw ABI 8.

- Raw `io` entries accept ABI-8 boundary types (`Unit`, `Bool`, `U32`, `F32`, `#[U32]`, `#[F32]`, or one `! {Foreign}` host callback).
- `#kernel` and `#process` accept FlatNumeric / PersistentSafe structs and numeric arrays; fixed-size arrays `#[N; T]` and closures cannot cross raw `io`.

```blot
// Before
type Clock is effect = { now: Unit -> U32 }
io main (): U32 =>
  use t <- Clock.now ()
  return t

// After
type Clock is effect = { now: Unit -> U32 }
io main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t
```

---

## EFFECT_MISMATCH

**Cause:** An effectful call appears in a pure position (`let`, `const`, top-level initializer, or pure function signature) or two branches have mismatched effect rows.

- Use `use x <- Effect.op arg` instead of `let x = Effect.op arg`.
- Handle local effects with `with Effect = { ... }:` or `do provider:` before crossing a pure boundary.

```blot
// Before
type Clock is effect = { now: Unit -> U32 }
func read_time (): U32 =>
  let t = Clock.now ()
  return t

// After
type Clock is effect = { now: Unit -> U32 }
func read_time (): U32 =>
  use t <- Clock.now ()
  return t
```

---

## SEALED_EFFECT

**Cause:** An effect declaration, row annotation, handler operation signature, provider, or scoped capability failed effect validation.

- Match effect family names and operation signatures against `type Name is effect = { ... }`.
- Keep scoped capabilities and resolvers inside the `with` / `do` block that provides them.

```blot
// Before
type Clock is effect = { now: Unit -> U32 }
io main (): U32 =>
  with Clock = { wrong: func () => return 0 }:
    return 0

// After
type Clock is effect = { now: Unit -> U32 }
io main (): U32 =>
  with Clock = { now: func () => return 42 }:
    use t <- Clock.now ()
    return t
```

---

## KERNEL_EFFECTFUL

**Cause:** A `#kernel`, `#process`, or `spark` comprehension performs an algebraic effect or violates purity/generator constraints.

- `#kernel` and `#process` functions must be completely pure (`! {}`); move host I/O and effect handling to the caller/host boundary and pass read values in as parameters.
- Keep `spark #[expr | i <- 0 .. n]` pure with simple range generators and read-only outer inputs.

```blot
// Before
type Clock is effect = { now: Unit -> U32 }
#kernel func step (x: U32): U32 =>
  use t <- Clock.now ()
  return x + t

// After
#kernel func step (x: U32): U32 =>
  return x + 1
```

---

## KERNEL_TYPE

**Cause:** A `#kernel` or `#process` wire type fails FlatNumeric / PersistentSafe / stride requirements, or a SIMD intrinsic received a non-literal lane index.

- Use FlatNumeric scalars, flat structs, or numeric arrays for `#kernel` packets and PersistentSafe types for `#process`.
- Pass compile-time `U32` literals directly to SIMD shuffle/swizzle/broadcast intrinsics.

```blot
// Before
#kernel func bad (f: U32 -> U32): U32 => return f 1

// After
#kernel func good (x: U32): U32 => return x + 1
```

---

## NO_ENTRY

**Cause:** `blot build` was invoked on a module with no `io`, `#kernel`, or `#process` declaration (or `io` was placed in a non-entry imported module).

- Use `blot check` to check library modules without `io` entries.
- Add an `io`, `#kernel`, or `#process` declaration to the root entry module when building a Wasm artifact.

```blot
// Before
func helper (x: U32): U32 => return x + 1

// After
func helper (x: U32): U32 => return x + 1
io main (x: U32): U32 => return helper x
```

---

## NON_EXHAUSTIVE_MATCH

**Cause:** `case ... of` or refutable `let` does not cover all variants.

- Add missing `$Variant` arms or `_ => ...`.
- For refutable `let`, add `else:` with an exiting suite (`return` / `break`).

```blot
// Before
func unwrap (opt: Maybe U32): U32 =>
  let $Some value = opt
  return value

// After
func unwrap (opt: Maybe U32): U32 =>
  let $Some value = opt else:
    return 0
  return value
```

---

## FUNCTION_RETURN_REQUIRED

**Cause:** Indented function body falls off the end without an explicit `return`.

- Add `return <value>` on every branch, or write single-expression `func x => expr`.

```blot
// Before
func clamp (x: U32): U32 =>
  if x > 10:
    return 10
  x

// After
func clamp (x: U32): U32 =>
  if x > 10:
    return 10
  return x
```

---

## DUPLICATE_NAME

**Cause:** Two top-level declarations, import aliases, record fields, or pattern bindings share a name.

- Rename the duplicate declaration or field, or use `x := next` to update an existing local.

```blot
// Before
const x: U32 = 1
const x: U32 = 2

// After
const x: U32 = 1
const y: U32 = 2
```

---

## UNKNOWN_REBINDING

**Cause:** Left-hand side of `:=` is not a local `let` binding or parameter in scope.

- Declare local state with `let x = init` before `x := next`; module `const` values are immutable.

```blot
// Before
const count: U32 = 0
io main (): U32 =>
  count := 1
  return count

// After
io main (): U32 =>
  let count = 0
  count := 1
  return count
```

---

## PRIVATE_ACCESS

**Cause:** Code attempted to access a `private` declaration from another module, inspect an abstract type's internal representation, or call a `std`-only intrinsic.

- Remove `private` on declarations meant to be imported, use the module's public accessors, or call the public `std/` wrapper.

---

## CONTROL_FLOW_ERROR

**Cause:** Invalid `break`/`continue`/`return`/`else:` placement, unreachable statement, wrong call/intrinsic/pattern/tuple arity, or unknown intrinsic name.

- Keep `break` / `continue` inside loops or `do:` blocks, ensure `let ... else:` suites exit, and verify intrinsic names and arities.

```blot
// Before
io main (): U32 =>
  break 1

// After
io main (): U32 =>
  return do:
    break 1
```

---

## STORAGE_ERROR

**Cause:** The compiler could not prove safe collector-free ownership, scoped storage lifetimes, or usage multiplicity (for example, passing an `own` function as a first-class value or letting a borrow escape).

- Call `own`-parameter functions directly instead of storing them as function values.
- Return `.copy` or transfer ownership via `own` so borrowed storage never escapes its owner.

```blot
// Before
func take (xs: own #[U32]): U32 => return xs.length
io main (): U32 =>
  let f = take
  return f #[1, 2]

// After
func take (xs: own #[U32]): U32 => return xs.length
io main (): U32 =>
  return take #[1, 2]
```

---

## COMPTIME_ERROR

**Cause:** Compile-time evaluation of a `const` initializer or staged computation panicked, divided by zero, indexed out of bounds, hit a dependency cycle, read a top-level `let`, or exceeded its evaluation budget.

- Keep `const` initializers pure, acyclic, bounded, and independent of top-level `let` bindings.

```blot
// Before
const bad: U32 = 1 / 0

// After
const ok: U32 = 1 / 1
```

---

## IMPORT_ERROR

**Cause:** Module import path, alias, prelude path, exported symbol lookup, or declaration modifier/attribute failed.

- Use relative paths (`./foo`) or configured aliases (`std/...`, `blot.json` aliases), verify exported names, and break circular module imports.

---

## ASSET_IMPORT

**Cause:** A Stage-0 asset generator failed during `compile`, `execute` (runtime trap), `result` (`$Err`), or `generated_source` validation.

- Check the `from <input> via <generator> (stage0 <phase>)` provenance line to pinpoint whether the generator, input file, or generated Blot source failed.
- Run `blot check <generator.blot>` directly when `phase === "compile"`.

---

## IO_ERROR

**Cause:** File I/O failed or a deterministic compiler safety budget (source size, file count, nesting depth, inference steps, or 16 MiB bootstrap arena) was exceeded.

- Check file paths/permissions and split overly deep or complex expressions into annotated helper functions.

---

## TYPED_HOLE

**Cause:** An explicit `@hole` placeholder reported the expected type and matching in-scope bindings.

- Replace `@hole` with a concrete expression matching the reported expected type.

```blot
// Before
func inc (x: U32): U32 => return @hole

// After
func inc (x: U32): U32 => return x + 1
```

---

## UNSUPPORTED

**Cause:** Unsupported backend form, invalid custom operator/proof declaration, or retired language task/request construct.

- Rewrite using standard Blot vNext functions, algebraic effects, `#kernel`, or `#process` (`blot guide --cheatsheet`).
