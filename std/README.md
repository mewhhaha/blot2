# Executable prelude

[prelude.blot](prelude.blot) is ordinary Blot source, implicitly available to
source compiler sessions. It currently covers generic functions, `Maybe`,
`Result`, Bool, U32, and F32. Root declarations can shadow prelude names; the
prelude keeps its own scope and nominal identities. Only root exports become
Wasm exports. Use `{ prelude: "none" }` when creating a compiler for a
freestanding module. File imports are supported through the CLI or
`loadSourceProject`; the CLI maps `std/` to this directory. Raw source-string
compilation does not load imports automatically. General module re-exports are
not implemented yet.

All examples below use the default prelude. Values/functions use `snake_case`;
types and constructors use `PascalCase`. Functions are explicitly curried: a
two-argument function is written `fn left => fn right => ...` and called
`function left right`.

## Pure functions

| Function                    | Result or behavior                        |
| --------------------------- | ----------------------------------------- |
| `identity value`            | `value`                                   |
| `apply function value`      | `function value`, also `function $ value` |
| `always value ignored`      | `value`                                   |
| `compose outer inner value` | `outer (inner value)`                     |
| `flip combine right left`   | `combine left right`                      |
| `on combine project a b`    | `combine (project a) (project b)`         |
| `Bool.not value`            | Exchanges `True` and `False`              |

```blot
fn increment value => value + 1
const double = U32.mul 2
const transform = compose double increment

export fn answer () => transform 20

export fn inferred () => do:
  let same = fn value => value
  if same True:
    return same 42
  return 0
```

`answer ()` returns 42. Closures capture immutable values, and pure local
bindings generalize independently at each use. Higher-order functions propagate
the inferred effect rows of callbacks. Creating an effectful closure is pure;
calling it requires the corresponding provider. Demand-driven parameters remain
unimplemented. See [effects and controlled IO](../compiler/effects-and-io.md).

Plain `do:` blocks already return `()` when they fall through. No trailing
`return ()` is needed, and their last expression statement is discarded. A
non-unit result needs an explicit return on every reachable path. Expression
bodies such as `fn answer () => 42` still return their expression.

## Maybe and Result

```blot
data Maybe a = Some a | Nothing
data Result value error = Ok value | Err error
```

Those declarations describe the prelude's types; do not redeclare them unless
you intend a new nominal type. Constructors are ordinary values. `Some value`
and `Some(value)` are equivalent in expressions and patterns.

| Function                               | Behavior                                                         |
| -------------------------------------- | ---------------------------------------------------------------- |
| `Maybe.pure value`                     | `Some value`                                                     |
| `Maybe.map transform candidate`        | Transforms a present value                                       |
| `Maybe.bind candidate next`            | Calls `next` on a present value; `next` returns a `Maybe`        |
| `Maybe.unwrap_or fallback candidate`   | Extracts `Some`, otherwise returns `fallback`                    |
| `Maybe.is_some candidate`              | Returns a Bool                                                   |
| `Maybe.to_result error candidate`      | Converts `Some value` to `Ok value`, or `Nothing` to `Err error` |
| `Result.pure value`                    | `Ok value`                                                       |
| `Result.map transform candidate`       | Transforms only `Ok`                                             |
| `Result.map_error transform candidate` | Transforms only `Err`                                            |
| `Result.bind candidate next`           | Calls `next` on `Ok`; `next` returns a `Result`                  |
| `Result.unwrap_or fallback candidate`  | Extracts `Ok`, otherwise returns `fallback`                      |
| `Result.to_maybe candidate`            | Keeps `Ok` as `Some`, discards `Err` as `Nothing`                |

```blot
fn nonzero value => do:
  if value == 0:
    return Nothing
  return Some value

const candidate = Maybe.bind (Some 40) nonzero

export fn answer () => do:
  let Some(value) = Maybe.map (U32.add 2) candidate else:
    return 0
  return Result.unwrap_or 0 (Maybe.to_result False (Some value))

export fn inspect () => case Some (Some 42) of
  Some (Some value) => value
  Some Nothing => 0
  Nothing => 0
```

Matches must be exhaustive. `if let` binds only in its successful branch;
`let pattern = value else:` requires an exiting failure branch. The RHS is pure
and evaluated once. Use ordinary calls to `Maybe.bind`/`Result.bind` for now:
`do monad Maybe:` and `return $` do not execute custom resolvers yet.

Arguments are eager. In particular, an `unwrap_or` fallback expression is
evaluated even when the candidate succeeds; put conditional work inside `case`
or a function passed to `bind`.

## U32 and operators

U32 literals are decimal or hexadecimal, optionally separated by underscores:
`42`, `4_096`, `0xFFFF_FFFF`. Values outside 0..2^32−1 are rejected. `U32.add`,
`U32.sub`, and `U32.mul` wrap modulo 2^32; subtraction is not signed arithmetic.

| Operations                             | Purpose                    |
| -------------------------------------- | -------------------------- |
| `U32.add`, `U32.sub`, `U32.mul`        | Binary arithmetic          |
| `U32.eq`, `ne`, `lt`, `le`, `gt`, `ge` | Binary comparisons to Bool |
| `U32.to_f32 value`                     | Rounded numeric conversion |

The prelude's `+`, `-`, `*`, `==`, `!=`, `<`, `<=`, `>`, and `>=` operators
reference these U32 functions. They are not polymorphic numeric operators.
`F32.add 1.0 2.0` works; `1.0 + 2.0` is a type error with the default fixities.
There is no implicit conversion between U32 and F32, including under an
annotation: write `42.0` or `U32.to_f32 42` for an F32 value.

Operators are source-defined aliases for functions, not compiler arithmetic
special cases. Backticks also call a named function infix:

```blot
fn plus left => fn right => U32.add left right
export fn answer () => 20 `plus` 22
```

Custom fixity declarations belong before other declarations. Application binds
tighter than operators. See the
[compiler syntax reference](../compiler/README.md#prelude-and-operators) for
precedence/associativity. `&&`/`||` are intentionally absent until demand
parameters or another proper short-circuit mechanism is implemented.

The prelude also defines `infixr 0 ($) = apply`. Like Haskell's application
spelling, `f $ g $ x` groups as `f (g x)` and binds below arithmetic and default
backtick operators. Unlike Haskell, Blot still evaluates ordinary arguments
eagerly; `$` neither defers work nor handles effects.

```blot
export fn answer () => U32.mul 2 $ U32.add 1 $ 20
export fn discarded () => do:
  use identity $ 42

fn invoke callback => callback 41
export fn callback_example () => invoke $ fn value => value + 1
```

An infix RHS can also be a `do:` block or `case` expression without parentheses.
`return f $ value` returns the call result; the existing `return $ value`
resolver-forwarding syntax remains separate and is still unimplemented.

## F32 and game math

F32 is an actual IEEE binary32 scalar in inference, const evaluation, and Wasm.
Decimal literals require a decimal point or exponent: `1.0`, `-0.25`, `1e-5`,
`1_000.5_0`. Prefix `-` negates F32 expressions. Parenthesize negative function
arguments: `F32.mul speed (-2.5)`.

| Operations                                 | Purpose                                     |
| ------------------------------------------ | ------------------------------------------- |
| `F32.add`, `sub`, `mul`, `div`             | Binary arithmetic                           |
| `F32.eq`, `ne`, `lt`, `le`, `gt`, `ge`     | IEEE comparisons returning Bool             |
| `F32.neg`, `abs`, `sqrt`                   | Unary math                                  |
| `F32.floor`, `ceil`, `trunc`               | Rounding with an F32 result                 |
| `F32.min left right`, `F32.max left right` | Comparison-based selection                  |
| `F32.clamp low high value`                 | Bounds a value; supply `low <= high`        |
| `F32.lerp left right weight`               | `left + (right - left) * weight`, unclamped |
| `F32.square value`, `F32.length3 x y z`    | Squared value and 3D Euclidean length       |
| `F32.is_finite value`                      | False for NaN and either infinity           |
| `F32.to_u32 value`                         | Truncating, saturating conversion           |
| `F32.wrap period value`                    | Wraps into a positive period                |
| `F32.lerp_angle left right weight`         | Interpolates along the shortest angular arc |
| `F32.sin`, `cos`, `tan`                    | Pure Blot trigonometric approximations      |

```blot
export const negative_zero = -0.0
export const rounded = F32.add 16_777_216.0 1.0

export fn vector_length () => F32.length3 2.0 3.0 6.0
export fn bounded_speed (value: F32) => F32.clamp 0.0 12.0 value
export fn halfway (value: F32) => F32.lerp value 10.0 0.5
export fn integer_part (value: F32) => F32.to_u32 value
```

`rounded` is 16,777,216, and `vector_length ()` is 7. Arithmetic rounds each
operation to F32; `lerp` is separate multiply/add, not a fused operation.
Decimal literals round once, ties-to-even, using exact midpoint checks so native
and JavaScript compiler backends agree even at subnormal boundaries. Literal
overflow is an error. Finite underflow can become a subnormal or zero.

Arithmetic follows IEEE behavior: division by zero can produce infinity,
`0.0 / 0.0` expressed as `F32.div 0.0 0.0` produces NaN, and signed zero is
preserved. NaN is unequal to every value, including itself; ordered comparisons
with it are false. `min`/`max` select the right operand when their comparison is
false, including unordered comparisons. Use `is_finite` at application
boundaries that require finite geometry.

`F32.to_u32` truncates toward zero, then saturates to 0..4,294,967,295. Negative
values and NaN yield zero; positive overflow/infinity yield 4,294,967,295.
`U32.to_f32` rounds to the nearest representable F32, so large integers may lose
precision. No bit reinterpretation is exposed as one of these conversions.

Trigonometry uses split-constant range reduction and F32 polynomial evaluation,
not host calls. `sin`/`cos` support `|radians| <= 8192`; nonfinite/out-of-domain
arguments produce NaN. `tan` divides those approximations and is ill-conditioned
near its poles. Keep accumulated game angles wrapped. The compiled numeric
regressions in [prelude_math.test.ts](../compiler/prelude_math.test.ts) check
native/JS parity and error over the supported domain.

Host scalar exports use actual Wasm `f32` parameters/results and return normal
JavaScript numbers. There is no compiler-specific ECS storage ABI. See
[the ABI and lifetime boundary](../compiler/README.md#evaluation-and-wasm-representation).

## Immutable arrays

Import [array.blot](array.blot) explicitly:

```blot
import * as array from "std/array"

const values: Array U32 = [10, 20, 12]
export fn answer () => array.fold_left U32.add 0 values
```

- `length values` and `is_empty values` inspect length without visiting elements
  in Wasm.
- `at index values` reads an element; `replace index value values` returns an
  updated array. An invalid U32 index traps in Wasm or fails const evaluation.
- `get index values` and `set index value values` return `Maybe` instead of
  trapping on an invalid index.
- `fold_left reduce initial values` visits elements left-to-right.
- `any predicate values` and `all predicate values` stop as soon as the result
  is known. Empty arrays return `False` for `any` and `True` for `all`.

The higher-order functions propagate callback effects; they do not install
providers or acquire host authority. Array elements are homogeneous, including
tuples, nested arrays, constructors and closures. Empty arrays infer their
element type from use. Tuples use `(42, True)` and `(U32, Bool)` syntax;
`@product.get pair 0` requires a statically known tuple shape.

The bootstrap array representation uses contiguous lanes and preserves old
aliases. Every update currently copies the full array, so repeated updates are
not yet suitable for high-throughput component columns. These source folds use
recursion, not an optimized loop primitive. The const evaluator currently stores
arrays as immutable lists, so const indexing/length also traverse elements;
large const folds can be quadratic despite constant-time Wasm reads. The step
budget counts source evaluation and array-copy work, not elapsed time.
Indexing/update sugar, array spread/patterns, resizing and bulk builders remain
unimplemented. Tuples and arrays cannot cross the current scalar host ABI.

See [the executable array example](../examples/arrays.blot).

## Current boundary

This prelude is a useful executable core, not the complete standard library. It
does not yet provide record field access/update syntax, general text values,
F64, SIMD, type-valued programming, or resumable handlers. The generic core
supports closed source-declared operations, scoped providers, and compile-time
effect descriptors. The [3D sandbox](../case-study/ecs/README.md) is paused
while its compiler-specific backend is replaced by a source-defined ECS and
explicit entrypoint IO capabilities. Literal strings are accepted as panic
messages, not as general runtime `Text` values or privileged asset/window
operations.

For a complete small program, see
[examples/prelude.blot](../examples/prelude.blot).
