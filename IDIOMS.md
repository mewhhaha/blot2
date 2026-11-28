# Squid Idioms

Practical patterns for writing fast, zero-GC, ownership-checked Squid vNext code. Run `deno task squid guide --idioms` to print this document, `deno task squid guide --cheatsheet` for syntax tables, or `deno task squid guide --list` to browse focused topics.

## 1. Choosing the Right Collection

Squid puts memory layout in the type symbol so hot loops stay dense without changing high-level code:

| Type | Literal / Constructor | Layout & Complexity | Use When |
|---|---|---|---|
| `#[T]` (`Array T`) | `#[1, 2, 3]` | Contiguous mutable buffer; O(1) index, amortized O(1) push | Default collection, random access, `spark` SIMD, in-place indexing |
| `#[n; T]` | `#[4; F32]` | Equal-length-checked fixed array family | Matrices, small fixed vectors, zero-bounds-check hot inner loops |
| `&[T]` (`View T`) | `&xs[start..end]` | Zero-copy read-only borrowed slice | Passing read-only subranges without copying |
| `%[T]` (`Packed T`) | `%[1, 2, 3]` | Non-indexable dense sequential storage: SoA columns for records/tuples, dense U8 tag + payload streams for sums | Event/command logs, particle SoA sweeps, sum-type streams scanned with `for` + `case` |
| `~[T]` (`Seq T`) | `~[1, 2, 3]`, `Seq.ramp` | 16-way SIMD-RRB tree with focus gap & packed leaves; O(1) `.reverse`/`.copy`/`freeze`, O(log16 m) `.split`/`.concat`/`.slice`/`.insert`/`.remove` | Rope/undo buffers, reversible sequences, front+back queues, structural sharing |
| `*T` | `freeze x` | O(1) frozen shared handle | Immutable lookup tables, snapshots shared freely across scopes or closures |

Prefer `%[T]` when you only push and scan sequentially, especially for sum types (`for ev in events: case ev of ...` fuses tag scanning and skips runs in 16-byte SIMD) and wide records where loops only read a subset of fields (SoA). Prefer `~[T]` when you need cheap `.copy`, `.reverse`, `.split`, `.concat`, or front edits:

```squid
type Event is data = $Hit U32 | $Heal U32 | $Miss

func net_damage (raw: #[U32]): U32 =>
  let events: %[Event] = %[
    if x == 0 then $Miss else if (x & 1) == 0 then $Hit x else $Heal x
    | x <- raw
  ]
  let total: U32 = 0
  for ev in events:
    case ev of
      $Hit dmg =>
        total := self + dmg
      $Heal _ => ()
      $Miss => ()
  return total

func mirror_middle (n: U32): U32 =>
  let seq = Seq.ramp 0 1 n
  let reversed = seq.reverse_range 1 (n - 1)
  return reversed[1] + reversed[n - 2]

io main (): U32 => net_damage #[0, 4, 3, 6] + mirror_middle 8
```

## 2. Zero-Copy Ownership, `own`, and In-Place Mutation

- **Borrow by default.** An unannotated parameter (`func sum (xs: #[U32])`) borrows with zero copies and leaves ownership with the caller.
- **Take `own` to mutate and return in place.** Use `xs: own #[T]` (or `state: own State` for large records holding storage) and rebind with `:=` (`xs := self.push v`, `xs[i] := self * 2`, `state.field := ...`). The compiler reuses the buffer or boxed record block in place with zero GC and zero extra allocation.
- **Make timeline splits explicit.**
  - `x.copy` — O(n) independent mutable clone (O(1) for `~[T]`).
  - `freeze x` — O(1) immutable `*T` shared across scopes and closures.
  - `fork x:` — O(edits) speculative mutation block that rolls back `x` automatically on exit (pure only; no `Foreign` effects inside `fork`).

```squid
func scale_and_append (xs: own #[F32]) -> (factor: F32) -> (extra: F32): #[F32] =>
  for i in 0 .. xs.length:
    xs[i] := self * factor
  xs := self.push extra
  return xs

func preview_first (xs: own #[F32]): (F32, F32) =>
  let speculated: F32 = 0.0
  fork xs:
    xs[0] := self + 10.0
    speculated := xs[0]
  // `xs` is rolled back automatically after `fork` exits.
  return (speculated, xs[0])

io main (): F32 =>
  let values = scale_and_append #[2.0, 4.0] 3.0 9.0
  let (tried, kept) = preview_first values
  return tried + kept
```

## 3. Flat Control Flow & Exhaustive Patterns

- **Use `let <pattern> = expr else:` for early exits** instead of deeply nested `case` blocks. The `else:` branch must exit (`return`, `break`, `continue`, or `panic`).
- **Use `if let` when only the matching branch matters.**
- **Use `do:` + `break value`** to scope local setup inside an expression without introducing a helper function.
- **Match multiple values at once with `case a, b of`** instead of nested `case` or tuple allocations.
- **Use single-expression `func x => expr`** for one-liners and block-bodied `func x =>` with explicit `return` for multi-step logic.

```squid
type Mode is data = $Fast | $Safe

func pick_limit (mode: Mode) -> (opt: Maybe U32): U32 =>
  let $Some cap = opt else:
    return 0
  return case mode, cap > 100 of
    $Fast, true => 100
    $Fast, false => cap
    $Safe, _ => cap / 2

func bounded_step (xs: #[U32]) -> (idx: U32): U32 =>
  let found = do:
    if let $Some v = xs.get idx:
      break v + 1
    break 0
  return found

io main (): U32 => pick_limit $Fast ($Some 140) + bounded_step #[10, 20] 1
```

## 4. High-Throughput SIMD, Reductions & Pre-Sized Loops

- **Vectorize pure elementwise maps with `spark`.** `spark #[expr | i <- 0 .. n]` compiles to 4-wide Wasm `v128` SIMD (and reuses uniquely owned buffers in place when assigned back).
- **Write direct `for v in xs:` reductions.** `for v in xs: acc := self + v` automatically lowers to 16-wide `v128` SIMD for `U32`/`I32`, 8-wide `v128` for `U64`/`I64`, and exact IEEE-754 left-to-right 4× unrolled loops for `F32`/`F64` across `#[T]`, `%[T]`, and `~[T]`.
- **Pre-reserve or use counted range-push loops.** `for i in 0 .. n: out := self.push (a * i + b)` pre-reserves once and fills via SIMD without repeated growth checks; for conditional pushes, start with `Array.with_capacity n`.
- **Keep `#kernel` and `#process` pure.** Exported compute kernels and stateful processes cannot perform unhandled effects; pass flat arrays or scalars across the host boundary.

```squid
func saxpy (a: F32) -> (xs: #[F32]) -> (ys: #[F32]): #[F32] =>
  return spark #[a * xs[i] + ys[i] | i <- 0 .. xs.length]

func sum_f32 (xs: #[F32]): F32 =>
  let acc: F32 = 0.0
  for x in xs:
    acc := self + x
  return acc

func build_ramp (n: U32): #[U32] =>
  let out: #[U32] = Array.with_capacity n
  for i in 0 .. n:
    out := self.push (i * 3 + 1)
  return out

#kernel func checksum_row (n: U32): U32 =>
  let xs = build_ramp n
  let total: U32 = 0
  for x in xs:
    total := self + x
  return total

io main (): F32 => sum_f32 (saxpy 2.0 #[1.0, 2.0, 3.0, 4.0] #[0.5, 0.5, 0.5, 0.5])
```

## 5. Pipelines, Custom Operators & Backtick Infix

- **Chain left-to-right transformations with `|>`.** Application binds tighter than `|>`, so partial applications read cleanly without nested parentheses.
- **Name custom operators in parentheses** (`func (++) a -> b => ...`) and pass any operator as a first-class function (`(+)`, `(*)`).
- **Use backticks to apply any 2-argument function infix** (``x `F32.min` y``, ``xs `concat_u32` ys``). Backtick infix binds at precedence `80` (tighter than `**`, looser than function application) and is left-associative.

```squid
func (+*) (a: U32) -> (b: U32): U32 => a * b + 1

func clamp_hi (x: U32) -> (hi: U32): U32 => if x > hi then hi else x

func fold_u32 (combine: U32 -> U32 -> U32) -> (init: U32) -> (xs: #[U32]): U32 =>
  let acc = init
  for x in xs:
    acc := combine self x
  return acc

func transform (xs: #[U32]): U32 =>
  return xs
    |> fold_u32 (+) 0
    |> (func total => (total `clamp_hi` 50) +* 2)

io main (): U32 => transform #[10, 20, 30]
```

## 6. Composable Effects & Deterministic Testing

- **Keep effect interfaces small and capability-scoped.** Functions infer their effect row automatically (or annotate `!{ Clock, Log }`).
- **Invoke operations with `use r <- Eff.op arg`** (never `let`).
- **Compose handlers with `layer` and bind them locally** via `.handle env .run arg` (or `@handle`). Because handlers are ordinary values, swapping production I/O for a deterministic replay handler requires zero global state or mocks.

```squid
type Clock is effect = { now: Unit -> U32 }
type Log is effect = { record: U32 -> Unit }

func sample_twice (bias: U32): U32 !{ Clock, Log } =>
  use t0 <- Clock.now ()
  use t1 <- Clock.now ()
  let diff = t1 - t0 + bias
  use Log.record diff
  return diff

io main (): U32 =>
  let tick: U32 = 100
  let logged: U32 = 0
  handler clock: Clock =>
    now () =>
      tick := self + 16
      return tick
  handler log: Log =>
    record v => logged := self + v
  let env = layer clock log
  let result = sample_twice.handle env
    .run 4
  return result + logged
```

## 7. Comptime Reflection Without Macros

- **Attach typed `@[...]` tags to fields** and iterate `#fields T` or `#variants T` with `#for` / `#if`.
- **Read and update reflected fields with `val.(field)` and `val.(field) := expr`**; construct records in expression position with `#for field in #fields T: ... break value`.
- **Use `is opaque`** on data types whose layout must stay hidden outside their defining module—`#fields` and `#variants` automatically respect `is opaque` encapsulation.

```squid
type Skip is data = $Skip
type Weight is data = $Weight U32

type Stats is data = $Stats {
  @[$Weight 2] hp: U32 = 10,
  @[$Weight 3] mp: U32 = 5,
  @[$Skip] scratch: U32 = 99,
}

func weighted_sum (value: t): U32 =>
  let total: U32 = 0
  #for field in #fields t:
    #if not (field.has_tag $Skip):
      total := self + value.(field) * field.tag $Weight
  return total

io main (): U32 => weighted_sum ($Stats {})
```

## 8. Error Handling & Anti-Patterns

- **Use `Maybe a`** when absence is ordinary and needs no reason; **use `Result [a, e]`** when callers need a typed error reason; reserve `panic` for unrecoverable invariant bugs.
- **Chain fallible steps flatly** with `let $Ok v = ... else: return $Err ...`, `Result.map`, `Result.bind`, and `Result.unwrap_or`.

```squid
func checked_div (a: U32) -> (b: U32): Result [U32, U32] =>
  if b == 0:
    return $Err 1
  return $Ok (a / b)

func ratio_plus_one (a: U32) -> (b: U32): Result [U32, U32] =>
  let $Ok q = checked_div a b else:
    return $Err 1
  return $Ok (q + 1)

io main (): U32 =>
  let chained = Result.bind (checked_div 42 2) (func q => ratio_plus_one q 3)
  return Result.unwrap_or 0 chained
```

| Prefer | Avoid | Why |
|---|---|---|
| `let $Some v = opt else: return 0` | Nested `case` pyramids | Keeps the happy path flat |
| `xs := self.push v` / `xs[i] := self + 1` | Rebuilding arrays per iteration | Mutates uniquely owned storage in place with zero copies |
| `let snap = xs.copy` only when needed | Defensive `.copy` on every call | Unannotated parameters already borrow zero-copy |
| `%[Event]` for append-and-scan streams | `#[Event]` when random indexing is unused | Enables dense U8 tag streams, SoA columns, and SIMD tag-run skipping |
| `~[T]` for frequent reverse/split/front ops | Copying `#[T]` on every front edit | O(1) `.reverse`/`.copy` and O(log16 m) `.split`/`.concat` |
| `freeze table` (`*#[T]`) for shared read tables | Passing copies of static tables | O(1) immutable handle shared across scopes |
| ``x `F32.min` y`` or `|>` chains | Deeply nested right-leaning parens | Clear left-to-right data flow |
| Small `handler`s composed with `layer` | Monolithic effect records | Easier deterministic testing and local reuse |
