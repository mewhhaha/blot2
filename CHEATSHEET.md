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
| `let t = Clock.now ()` | `use t <- Clock.now ()` | Effects require `use <-` and `with` / `do` handling |
| Mutating a borrowed param | `func f (xs: own #[U32]): #[U32] =>` | Mark parameter `own` or copy via `let local = xs.copy` |

## 2. Scalars & Built-in Types

- `Unit` (`()`), `Bool` (`true`, `false`), `U32` (`42`, `0xFF`, `4_096`), `F32` (`1.0`, `1e-5`).
- Negative arguments need parens: `F32.abs (-2.0)`.
- Arrays: `#[T]` (equivalent to `Array T`), fixed-length `#[N; T]`, borrowed read-only view `&[T]`, frozen shared handle `*T` (via `freeze x`).
- No built-in `String` type; byte strings are `#[U8]` / `Array U8`.

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
entry func main (): U32 =>
  let sum = 0
  for i in 0 .. 10:
    sum := self + i
  return sum
```

- Application is curried and left-associative: `add 1 2` means `(add 1) 2`.
- Tuples use parens: `let (x, y) = pair`.
- Indented `do:` blocks yield via `break value`.
- Pattern matching must be exhaustive:

```blot
type Event is data = $Tick U32 | $Reset

func step (ev: Event) -> (acc: U32): U32 => case ev of
  $Tick n => acc + n
  $Reset => 0

func unwrap_or_zero (opt: Option U32): U32 =>
  let $Some v = opt else:
    return 0
  return v
```

## 4. Ownership, Borrowing & In-Place Mutation

- Locals owning an array (`let a = #[1, 2, 3]`) mutate **in place with zero copies** via `a[i] := val`, `@storage.push a val`, `@storage.truncate a n`.
- `let b = a` **borrows** `a` until `b`'s last read; mutating `a` while `b` is still live fails with `[ALIASED_UPDATE]`.
  - Fix: `let b = a.copy` (explicit snapshot) or finish reading `b` before mutating `a`.
- Passing `a` to an `own` parameter **moves** `a`; reading `a` afterward fails with `[SPENT_VALUE]`.
  - Fix: pass `a.copy` or use the returned value (`let a = append_one a 9`).
- Non-entry functions returning storage must return a fresh value, `.copy`, or an `own` parameter (`[RESULT_NOT_OWNED]`).
- Module `const` arrays are deeply immutable; copy (`pool.copy`) before mutating.

## 5. Fast SIMD (`spark`) & Multi-Core (`entry kernel` / `entry process`)

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

entry func run (): F32 =>
  with Clock = { delta: func () => return 0.01666667 }:
    use next <- step 10.0 6.0
    return next
```

## 7. CLI Commands

```sh
deno task blot check app.blot                  # type-check with agent diagnostics
deno task blot build app.blot build/app.wasm   # compile to Wasm ABI 8
deno task blot build app.blot build/app.wasm --wasm3  # opt-in Wasm 3.0 (FMA + return_call)
deno task blot fmt app.blot                    # format source
deno task blot explain SPENT_VALUE             # explain any diagnostic code
deno task blot explain --list                  # list all diagnostic codes
deno task blot guide --cheatsheet              # print this cheatsheet
```
