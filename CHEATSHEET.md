# Blot vNext Cheatsheet

Quick, version-matched reference for humans and coding agents. Run `deno task blot guide --cheatsheet` to print this file, or `deno task blot explain <CODE>` for any compiler error.

## 1. Top 10 Rules (Avoid Common Mistakes)

| Don't write | Write instead | Why |
|---|---|---|
| `fn add(a, b) -> U32 { ... }` | `func add (a: U32) -> (b: U32): U32 =>` | `func`, curried `->`, return after `:`, indented suite after `=>` |
| `[1, 2, 3]` | `#[1, 2, 3]` | Unified owned array literal uses `#[...]` |
| `type Opt = Some U32 \| Nothing` | `type Opt is data = $Some U32 \| $Nothing` | Data types need `is data` and `$` constructors |
| `Some 1`, `None` | `$Some 1`, `$Nothing` | Constructors always require `$`; prelude option is `$Some` / `$Nothing` |
| `a && b`, `a \|\| b`, `!a` | `a and b`, `a or b`, `not a` | Word boolean operators |
| `xs.len` | `xs.length` | Array length property is `.length` |
| `mut x = 1` / `var x = 1` | `let x = 1` then `x := 2` | Local rebinding uses `:=` (`x := self + 1`) |
| `1 + 2.0` | `@u32.to_f32 1 + 2.0` | No implicit `U32` / `F32` conversion |
| `let t = Clock.now ()` | `use t <- Clock.now ()` | Effects require `use <-` and `handler` + `.handle ... .run` / `@handle` |
| Mutating a borrowed param | `func f (xs: own #[U32]): #[U32] =>` | Mark parameter `own` or copy via `let local = xs.copy` |

## 2. Scalars & Built-in Types

- `Unit` (`()`), `Bool` (`true`, `false`), `U8`, `U32`, `I32`, `U64`, `I64`, `F32`, `F64`.
- Integer/float suffixes (optional `_`): `42u8`, `0xff_u8`, `100u32`, `-42i32`, `100u64`, `-9223372036854775808i64`, `1f32`, `1.5f64`. Unsuffixed integer defaults to `U32`, unsuffixed float defaults to `F32`.
- Char literals (`'a'`, `'\n'`, `'\x1b'`, `'é'`) type-check to `U8` (default if `<= 255`) or `U32` (any Unicode scalar), and work in `case` patterns.
- Byte-string literals (`b"hello\r\n\x00"`) have type `#[U8]` (see `std/bytes`).
- Negative arguments need parens: `F32.abs (-2.0)`.
- Arrays: `#[T]` (equivalent to `Array T`), fixed-length `#[N; T]`, borrowed read-only view `&[T]`, frozen shared handle `*T` (via `freeze x`). Pre-size with `Array.with_capacity`, `Array.reserve`, bulk append with `Array.extend` / `Array.extend_view`.
- Text: `Text` is a prelude alias for `#[U32]` Unicode scalar values; string literals (`"hi"`, `"é🙂"`) have type `Text` (see `std/text`).
- Standard modules: `std/prelude`, `std/text`, `std/bytes`, `std/map` (open-addressed hash map `Map K V`), `std/simd` (`F32x4`, `I32x4`, `F64x2`, `U64x2`, `U8x16`, `I16x8`).
- Wide 64×64->128 multiply: `U64.mul_wide a b` returns `(lo, hi)` as `(U64, U64)`.

## 3. Functions, Control Flow & Patterns

```blot
// Single-expression (implicit return)
func add (a: U32) -> (b: U32): U32 => a + b

// Block-bodied (explicit return on every path)
func clamp (x: U32) -> (hi: U32): U32 =>
  if x > hi:
    return hi
  return x

// Entry point exported to Wasm ABI 8 (must handle all effects)
io main (): U32 =>
  let sum = 0
  for i in 0 .. 10:
    sum := self + i
  return sum
```

- Application is curried and left-associative: `add 1 2` means `(add 1) 2`.
- Custom operators are ordinary functions named in parentheses (`func (++) a -> b => ...`, `import { (++) } from "./ops"`, `fold (+) 0 xs`) with lexical precedence (`|>`/`<|` 5, `or` 20, `and` 25, `= ! < >` 30, `|` 40, `^` 45, `&` 50, `<< >>` 55, `+ - ~ ?` 60, `* / %` 70, `**` 75). Standard operators live in `std/prelude.blot` using `@type.call` and `@pipe`.
- Tuples use parens: `let (x, y) = pair`.
- Indented `do:` blocks yield via `break value`.
- Pattern matching must be exhaustive:

```blot
type Event is data = $Tick U32 | $Reset

func step (ev: Event) -> (acc: U32): U32 => case ev of
  $Tick n => acc + n
  $Reset => 0

func unwrap_or_zero (opt: Maybe U32): U32 =>
  let $Some v = opt else:
    return 0
  return v
```

## 4. Ownership, Borrowing & In-Place Mutation

- Locals owning an array (`let a = #[1, 2, 3]`) mutate **in place with zero copies** via `a[i] := val`, `a := self.push val` (or `a := @storage.push self val`), `a := self.truncate n`.
- `let b = a` **borrows** `a` until `b`'s last read; mutating `a` while `b` is still live fails with `[ALIASED_UPDATE]`.
  - Fix: `let b = a.copy` (explicit snapshot) or finish reading `b` before mutating `a`.
- Passing `a` to an `own` parameter **moves** `a`; reading `a` afterward fails with `[SPENT_VALUE]`.
  - Fix: pass `a.copy` or use the returned value (`let a = append_one a 9`).
- Non-entry functions returning storage must return a fresh value, `.copy`, or an `own` parameter (`[RESULT_NOT_OWNED]`).
- Module `const` arrays are deeply immutable; copy (`pool.copy`) before mutating.

## 5. Fast SIMD (`spark`) & Multi-Core (`#kernel` / `#process`)

```blot
// Auto-vectorized 4-wide Wasm v128 SIMD (must be pure)
func saxpy (a: F32) -> (xs: #[F32]) -> (ys: #[F32]): #[F32] =>
  return spark #[a * xs[i] + ys[i] | i <- 0 .. xs.length]
```

## 6. Algebraic Effects

```blot
type Clock is effect = { delta: Unit -> F32 }

func step (pos: F32) -> (vel: F32): F32 =>
  use dt <- Clock.delta ()
  return pos + vel * dt

io run (): F32 =>
  handler clock: Clock =>
    delta () => 0.01666667
  return (step 10.0).handle clock
    .run 6.0
```

## 7. CLI Commands

```sh
deno task blot check app.blot                  # type-check with agent diagnostics
deno task blot build app.blot build/app.wasm   # compile to Wasm ABI 8
deno task blot build app.blot build/app.wasm --wasm3  # opt-in Wasm 3.0 (FMA + return_call)
deno task blot build app.blot build/app.wasm --stack-mb 256 --heap-mb 256 --transport-mb 16  # custom memory budgets
deno task blot fmt app.blot                    # format source
deno task blot explain SPENT_VALUE             # explain any diagnostic code
deno task blot explain --list                  # list all diagnostic codes
deno task blot guide --cheatsheet              # print this cheatsheet
```
