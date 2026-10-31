# Executable prelude

[prelude.blot](prelude.blot) is ordinary Blot source, implicitly available to
source compiler sessions. It currently covers generic functions, `Maybe`,
`Result`, type witnesses, Bool, U32, and F32. Root declarations can shadow
prelude names; the prelude keeps its own scope and nominal identities. Top-level
bindings are public to other Blot modules. Import [text.blot](text.blot) for
Unicode-scalar text operations, formatting, validation and a linear builder.
Import [equality.blot](equality.blot) for structural equality contracts and
[codec.blot](codec.blot) for explicit numeric-lane codecs; the
[derivation guide](../compiler/derive.md) shows opt-in equality, debug and codec
generation from checked data declarations. Only the root module's `entry const`
and `entry let` declarations become Wasm exports; they must fit the guest ABI,
and Wasm emission keeps the declarations they reach. Unused source declarations
are still checked. Use `{ prelude: null }` with `createCompiler` for a
freestanding module, or `--prelude none` with the CLI. The project API and CLI
resolve relative file imports and map `std/` to this directory. Configure
additional directory aliases through `imports` or `--alias`. General module
re-exports are not implemented yet.

All examples below use the default prelude. Values/functions use `snake_case`;
types and constructors use `PascalCase`. Functions are curried:
`func left -> right
=> return ...` abbreviates
`func left => return func right => return ...`, and both are called
`function left right`.

See the [API and performance audit](PERFORMANCE.md) for measured costs,
optimization guarantees and remaining work.

## Pure functions

| Function                    | Result or behavior                        |
| --------------------------- | ----------------------------------------- |
| `identity value`            | `value`                                   |
| `apply function value`      | `function value`, also `function $ value` |
| `always value ignored`      | `value`                                   |
| `compose outer inner value` | `outer (inner value)`                     |
| `flip combine right left`   | `combine left right`                      |
| `on combine project a b`    | `combine (project a) (project b)`         |
| `Bool.not value`            | Exchanges `true` and `false`              |

```blot
const increment = func value => return value + 1
const double = U32.mul 2
const transform = compose double increment

entry const answer = func () => return transform 20

entry const inferred = func () => return do:
  let same = func value => return value
  if same true:
    break same 42
  break 0
```

`answer ()` returns 42. Closures capture values; captured owner descriptors
retain their mutable aliases. Pure local bindings generalize independently at
each use. Higher-order functions propagate the inferred effect rows of
callbacks. Creating an effectful closure is pure; calling it requires the
corresponding provider. Demand parameters use `~` and are evaluated explicitly
with `@demand`. See [effects and controlled IO](../compiler/effects-and-io.md).

Plain `do:` blocks already return `()` when they fall through. No trailing
`break ()` is needed, and their last expression statement is discarded. A
non-unit result needs an explicit `break value` on every reachable path.
Expression bodies such as `const answer = func () => return 42` still return
their expression.

## Type equality

Wrap a value or constructor/function witness with `$Type` (or prefix it with
`:`) to compare its concrete type using ordinary `==` and `!=`:

```blot
type Count is data = $Count U32
type Other is data = $Other U32

entry const same_value = 1 == 2                         // False
entry const same_type = $Type 1 == $Type 2                // True
entry const same_nominal = $Type $Count == $Type ($Count 42) // True
entry const different = $Type $Count != $Type $Other       // True

entry const compare = func () => return do:
  let head = $Type $Count
  let witness = $Type ($Count 0)
  break head == witness
```

`Type` and its associated `eq`/`ne` functions are ordinary prelude declarations.
`Type.eq` unwraps both witnesses and uses `@type.same`, which resolves during
specialization. Comparisons include nominal module identity, generic arguments,
and structural element types. Constructor/function witnesses describe their
final result type and are never called by the comparison. Witness expressions
still evaluate once, left to right.

`$Type` takes a value expression: use `$Type 0` for U32 or a constructor witness
such as `$Type $Count`; bare type names such as `U32` are only valid in type
positions. Ordinary value equality continues to use the value type's own `eq`
implementation.

## Maybe and Result

```blot
type Maybe a is data = $Some a | $Nothing
type Result [value, error] is data = $Ok value | $Err error
type Iteration [state, result] is data = $Continue state | $Done result
```

Those declarations describe the prelude's types; do not redeclare them unless
you intend a new nominal type. Constructors are ordinary values. `$Some value`
and `$Some(value)` are equivalent in expressions and patterns.

| Function                               | Behavior                                                             |
| -------------------------------------- | -------------------------------------------------------------------- |
| `Maybe.pure value`                     | `$Some value`                                                        |
| `Maybe.map transform candidate`        | Transforms a present value                                           |
| `Maybe.bind candidate next`            | Calls `next` on a present value; `next` returns a `Maybe`            |
| `Maybe.iterate initial step`           | Iterates with constant call stack; `$Nothing` stops immediately      |
| `Maybe.unwrap_or fallback candidate`   | Extracts `$Some`, otherwise returns `fallback`                       |
| `Maybe.is_some candidate`              | Returns a Bool                                                       |
| `Maybe.to_result error candidate`      | Converts `$Some value` to `$Ok value`, or `$Nothing` to `$Err error` |
| `Result.pure value`                    | `$Ok value`                                                          |
| `Result.map transform candidate`       | Transforms only `$Ok`                                                |
| `Result.map_error transform candidate` | Transforms only `$Err`                                               |
| `Result.bind candidate next`           | Calls `next` on `$Ok`; `next` returns a `Result`                     |
| `Result.iterate initial step`          | Iterates with constant call stack; preserves the first `$Err`        |
| `Result.unwrap_or fallback candidate`  | Extracts `$Ok`, otherwise returns `fallback`                         |
| `Result.to_maybe candidate`            | Keeps `$Ok` as `$Some`, discards `$Err` as `$Nothing`                |

```blot
const nonzero = func value => return do:
  if value == 0:
    break $Nothing
  break $Some value

const candidate = Maybe.bind ($Some 40) nonzero

entry const answer = func () => return do:
  let $Some value = Maybe.map (U32.add 2) candidate else:
    break 0
  break Result.unwrap_or 0 (Maybe.to_result false ($Some value))

entry const inspect = func () => return case $Some ($Some 42) of
  $Some ($Some value) => value
  $Some $Nothing => 0
  $Nothing => 0
```

Matches must be exhaustive. `if let` binds only in its successful branch;
`let pattern = value else:` requires an exiting failure branch. The RHS is pure
and evaluated once. Monadic blocks use the same source-defined `pure` and `bind`
functions:

```blot
const try = monad Maybe
const add_present = func left -> right => return do try:
  use first <- left
  use second <- right
  break first + second
```

`$Nothing` skips the rest of the block. `monad Result` propagates `$Err` in the
same way. `break value` lifts with `pure`; `break $ candidate` forwards an
already wrapped result. `use candidate` binds and discards its successful
payload, so it still short-circuits. Falling through lifts Unit. Ordinary `let`
and expression statements do not unwrap values. Nested `do` blocks select their
own rules, and unrelated effects still require providers.

`monad` is an ordinary prelude function. Declared data-type constructors such as
`Maybe` can be aliased, imported, and passed through functions; user-defined
monads supply their own associated `pure` and `bind` functions.

Loops inside a monadic block also use its `iterate initial step` member. The
callback receives a state and returns a wrapped `Iteration state result`:
`$Continue next` advances with the next state; `$Done result` finishes with a
result, which can have a different type. `$Nothing` or `$Err error` propagates
immediately. Callback effects remain visible to callers. These functions also
work as ordinary calls:

```blot
const step = func count => return
  if count < 42 then $Some ($Continue (count + 1)) else $Some ($Done count)
entry const answer = func () => return Maybe.unwrap_or 0 (Maybe.iterate 0 step)
```

`Maybe.iterate` and `Result.iterate` finish each callback before starting the
next, using constant call stack. For a custom monad `M`, `iterate` must
implement the same result and sequencing as repeatedly binding `step state`:
`$Continue` repeats and `$Done value` finishes with `M.pure value`. Its
implementation is responsible for stack safety and any branching behavior of the
monad. This does not make arbitrary recursion stack safe. Blocks without loops
do not require an `iterate` member.

`unwrap_or` is eager. `Maybe.unwrap_or_else fallback candidate` and
`Result.unwrap_or_else fallback candidate` have a demand parameter: they
evaluate `fallback` only for `$Nothing` or `$Err`, once per captured argument.
`Maybe.filter predicate candidate` keeps a matching `$Some`, and `Maybe.flatten`
removes one nested `Maybe`.

## U32 and operators

U32 literals are decimal or hexadecimal, optionally separated by underscores:
`42`, `4_096`, `0xFFFF_FFFF`. Values outside 0..2^32−1 are rejected. `U32.add`,
`U32.sub`, and `U32.mul` wrap modulo 2^32; subtraction is not signed arithmetic.

| Operations                             | Purpose                    |
| -------------------------------------- | -------------------------- |
| `U32.add`, `U32.sub`, `U32.mul`        | Binary arithmetic          |
| `U32.eq`, `ne`, `lt`, `le`, `gt`, `ge` | Binary comparisons to Bool |
| `U32.to_f32 value`                     | Rounded numeric conversion |

The prelude's arithmetic and comparison operators call generic functions such as
`add`, `mul`, and `lt`. `1.0 + 2.0` selects `F32.add`; `1 + 2` selects
`U32.add`. `/` also supports U32 division. There is no implicit numeric
conversion: use `42.0`, `U32.to_f32 42`, or `from 42` when an F32 result is
required by the context.

The generic functions use `@type.call "add" left right`. At compile time this
tries `LeftType.add(left, right)`, then `RightType.add(left, right)` if the
first function cannot accept both operands. Arguments keep their original order.
The selected function determines the result type and effects. A matching left
implementation takes precedence; an incompatible return annotation is an error,
not a reason to switch to the right implementation.

Nominal types can define associated functions in their owning module:

```blot
type Vec2 is data = $Vec2 { x: F32, y: F32 }
const Vec2.add = func (a: Vec2) -> (b: Vec2) => return do:
  let $Vec2 { x: ax, y: ay } = a
  let $Vec2 { x: bx, y: by } = b
  break $Vec2 { x: ax + bx, y: ay + by }

const twice = func value => return value + value
entry const answer = func (value: F32) => return twice value
```

Generic functions that depend on associated dispatch are specialized for their
uses before const evaluation and Wasm emission. Dispatch whose operand types the
function itself already fixes, such as `Array.get`'s bounds comparison of a
`U32` index, resolves once inside the function and needs no per-use copy. This
also works through closures, local function aliases, and recursive functions. No
runtime member lookup is emitted. An entry function must have enough type
information to select a concrete implementation; annotate an otherwise
unconstrained entry parameter. Dispatch is selected while specializing reachable
code, so a call with no implementation (`true + false`) in a declaration no
entry reaches is type checked but not reported. `@type.call` also accepts other
literal member names, such as `"distance"`.

Operators are source-defined aliases for functions, not compiler arithmetic
special cases. Backticks also call a named function infix:

```blot
const plus = func left -> right => return U32.add left right
entry const answer = func () => return 20 `plus` 22
```

Custom fixity declarations belong before other declarations. Application binds
tighter than operators. See the
[compiler syntax reference](../compiler/README.md#prelude-and-operators) for
precedence/associativity. `and` and `or` are reserved Boolean operators. They
short-circuit: the right operand runs only when the left operand does not
determine the result.

The prelude also defines `infixr 0 ($) = apply`. Like Haskell's application
spelling, `f $ g $ x` groups as `f (g x)` and binds below arithmetic and default
backtick operators. Unlike Haskell, Blot still evaluates ordinary arguments
eagerly; `$` neither defers work nor handles effects.

```blot
entry const answer = func () => return U32.mul 2 $ U32.add 1 $ 20
entry const discarded = func () => return do:
  use identity $ 42

const invoke = func callback => return callback 41
entry const callback_example = func () => return invoke $ func value => return value + 1
```

An infix RHS can also be a `do:` block or `case` expression without parentheses.
`break f $ value` gives the call result to the block; `break $ value`
resolver-forwarding syntax passes through an already wrapped monadic result.

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
entry const negative_zero = -0.0
entry const rounded = F32.add 16_777_216.0 1.0

entry const vector_length = func () => return F32.length3 2.0 3.0 6.0
entry const bounded_speed = func (value: F32) => return F32.clamp 0.0 12.0 value
entry const halfway = func (value: F32) => return F32.lerp value 10.0 0.5
entry const integer_part = func (value: F32) => return F32.to_u32 value
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
regressions in
[native prelude execution tests](../zig-native/tests/prelude_execution.test.ts)
check native/JS parity and error over the supported domain.

Host scalar exports use actual Wasm `f32` parameters/results and return normal
JavaScript numbers. There is no compiler-specific ECS storage ABI. See
[the ABI and lifetime boundary](../compiler/README.md#evaluation-and-wasm-representation).

## Lists and arrays

In the Zig compiler, `[1, 2]` has type `List U32`; `#[1, 2]` has type
`Array U32` by default. A type annotation selects fixed-length `Array a`,
append-only `GrowArray a`, or `ResizeArray a` with push and truncate
capabilities; all three use `#[...]` literals. Lists and arrays are separate
types, with `List.from_array` and `Array.from_list` for explicit conversion.
Both expose `length` and `is_empty`. Only arrays support indexing, indexed
updates, `get`, and `set`. Numeric arrays remain the collection type accepted by
the host ABI.

Import [list.blot](list.blot) for `generate`, `fill`, `map`, `filter`,
`fold_left`, `any`, `all`, `append`, `prepend`, `concat`, `slice`, `split_at`,
`take`, `drop`, `splice` and `splice_many`, plus length and conversion helpers.
`fold_left`, `filter`, `any`, and `all` propagate callback effects; `any`/`all`
stop early and return false/true respectively on an empty list. `generate` and
`map` require pure callbacks. Spreads express prepend (`[value, ...values]`) and
append (`[...values, value]`); use `#[...]` to construct an array instead.
Comprehensions and `for` loops traverse either input collection. The opening
bracket selects a comprehension's output type: `[x * x | x <- values, x > 0]` is
a list. Convert a list to an array when indexed access is needed.

`list.splice start delete_count replacement values` replaces one checked range.
`list.splice_many edits values` accepts a list of
`{start, delete_count, replacement}` records in original-list coordinates. Edits
must be ordered, nonoverlapping and in bounds; insertions at the same position
retain their written order. Both are ordinary source functions that share
unchanged subtrees and preserve snapshots. For example:

```blot
list.splice 1 2 [20, 30, 40] [1, 2, 3, 4] // [1, 20, 30, 40, 4]
list.splice_many [
  {start: 1, delete_count: 1, replacement: [20, 21]},
  {start: 3, delete_count: 0, replacement: [30]}
] [1, 2, 3, 4] // [1, 20, 21, 3, 30, 4]
```

List operations retain their value semantics; runtime List support depends on
the selected backend. Arrays use contiguous checked rows. Persistent helpers
such as `array.push` construct independent output; use a named `GrowArray` when
appending into the same owner is intended. Access records and views retain
aliases, so copy explicitly for an independent version. See
[the list example](../examples/lists.blot) and
[collection and ownership contracts](../compiler/guide.md#lists-arrays-and-libraries).

### Iterators and SIMD

`values.iter` provides sequential cursors. In the owned profile an Array cursor
reads its owner rather than taking an independent payload snapshot.
`cursor.next` returns the ordinary `$Some (value, next_cursor)` or `$Nothing`.
User-defined types can provide the same associated `iter`/`next` functions and
work in `for` and comprehensions, including effectful traversal and early exit.
Independent cursor copies retain their own positions.

Import [iter.blot](iter.blot) for source-defined `range`, `zip`, `zip_strict`,
`enumerate`, `windows`, `take`, `take_while`, `map`, `filter`, `fold_left`,
`any`, `all`, `collect_list` and `collect_array`. Adapters are lazy; collection
is explicit. `windows` requires positive width and returns complete List
windows. `zip` polls left before right and stops at either end; `zip_strict`
traps if lengths differ.
[The protocol and examples](../compiler/guide.md#lists-arrays-and-libraries)
describe pull order, aliasing and copy requirements.

[rolling.blot](rolling.blot) provides complete overlapping reductions.
`fold step initial width values` reduces each window in order, including
effectful reducers and F32 arithmetic. `monoid combine identity width values`
uses a balanced persistent buffer; `group combine inverse identity width
values`
removes the oldest value on the left before adding the incoming value. The fast
callbacks must be pure. Callers promise an associative, total combine, a
two-sided identity and, for groups, a two-sided inverse. These are explicit
algebra contracts; use `fold` when they do not hold. Width zero traps before
obtaining the input cursor. Copies of a cursor keep independent windows.

[summary.blot](summary.blot) provides opaque persistent `Summary s` trees.
`build combine identity values` reads its input once; `length tree`,
`get index
tree`, `query combine identity start count tree`,
`set combine index value tree` and `concat combine left right` preserve earlier
versions. Queries use half-open ranges and return the identity for an empty
range. Reuse the same algebra and immutable captures for every operation. Build
is linear; queries, updates and concatenation follow logarithmic paths. The
[full contracts](../zig-native/ROLLING_SUMMARIES.md) specify ordering and
bounds.

[simd.blot](simd.blot) supplies explicit four-lane U32/F32 operations on
ordinary tuple aliases: arithmetic, shifts, min/max, comparison masks and
bitwise selection, literal shuffles, dot products, bit reinterpretation, an
opt-in relaxed multiply-add, checked array load/store, and ordered or explicitly
pairwise reductions. Lane, rounding and relaxed-multiply-add contracts follow
the language guide; source spelling does not guarantee a particular optimizer
representation. [SIMD semantics](../compiler/guide.md#simd) specify the exact
arithmetic and admission limits.

Named owners and lexical lifetime checks govern the owned-storage profile.
Aliases share writes; retained independent data requires an explicit copy. The
profile uses planned data stacks without a tracing collector.

### Array library

Arrays expose prelude members without importing `std/array`: `values.length`,
`values.is_empty`, `values.get(index)`, and `values.set(index)(replacement)`.
The checked operations return `Maybe`. `values[index]` reads with a bounds
check. In the owned profile `values[index] := replacement` writes through the
owner and its aliases; `self` denotes the old element. Nested writes require
checked fixed rows or valid borrowed links, not arbitrary fresh child owners.

Receiver members are ordinary receiver-first associated functions. For example,
`values.get` is `Array.get values`, a function awaiting its index. Record fields
use the same dot syntax and preserve their values during functional updates.

Import [array.blot](array.blot) for additional collection functions:

```blot
import * as array from "std/array"

const values: Array U32 = #[10, 20, 12]
entry const answer = func () => return array.fold_left U32.add 0 values
```

- `length values` and `is_empty values` inspect length without visiting elements
  in Wasm.
- `at index values` reads an element; `replace index value values` returns an
  updated array. An invalid U32 index traps in Wasm or fails const evaluation.
- `get index values` and `set index value values` return `Maybe` instead of
  trapping on an invalid index.
- `fill count value` allocates an array with a repeated value;
  `generate count generator` calls a pure generator for each index in order.
- `fold_left reduce initial values` visits elements left-to-right.
- `any predicate values` and `all predicate values` stop as soon as the result
  is known. Empty arrays return `false` for `any` and `true` for `all`.

`fold_left`, `any`, and `all` propagate callback effects. Array construction
through `generate`, `map`, `filter`, and `filter_map` requires pure callbacks.
Array elements are homogeneous. The owned profile requires checked fixed inline
rows and valid borrowed descriptors; arbitrary nested owning arrays and runtime
closures are not promised. Empty arrays infer their element type from use.
Tuples use `(42, true)` and `(U32, Bool)` syntax; `@product.get pair 0` requires
a statically known tuple shape.

Owned-profile arrays use checked contiguous rows. Direct element writes mutate
their owner; named grow/shrink operations follow the owner's capabilities.
Source folds and predicates preserve iteration order and callback effects.
Explicit copies and caller destinations express independent versions rather than
depending on last-reference/COW optimization.

The Zig const evaluator retains immutable collection values. Appending or
prepending to the latest version uses unused buffer slots and grows the buffer
geometrically, making repeated construction linear in work and storage. Earlier
versions retain their original contents. Branching from an older version copies
its elements; indexed updates also copy and can still make staged update loops
quadratic. Reserved slots count against the evaluator's storage budget.
Collection patterns remain unimplemented. Numeric arrays cross the host ABI as
copied `Uint32Array` or `Float32Array` values; tuples and other composite values
remain internal.

See [the executable array example](../examples/arrays.blot).

## Current boundary

This prelude is a useful executable core, not the complete standard library. It
does not yet provide collection patterns, F64, general type-valued programming,
or resumable handlers. The generic core supports closed source-declared
operations, scoped providers, and compile-time effect descriptors. Libraries
provide application behavior through explicit entrypoint IO capabilities.
Runtime `Text` values have no implicit IO or privileged asset/window operations.

For a complete small program, see
[examples/prelude.blot](../examples/prelude.blot).

## Readability helpers

| Form                                 | Behavior                                                       |
| ------------------------------------ | -------------------------------------------------------------- |
| `from value`                         | Converts using the expected destination type's `from` function |
| `value \|> transform`                | Applies `transform` to `value`                                 |
| `.name`                              | Selects a field or receiver member as a function               |
| `:value`, `:(expression)`            | Creates an ordinary `Type` witness                             |
| `left and right`, `left or right`    | Short-circuits primitive Boolean operands                      |
| `value / divisor`, `value % divisor` | U32 quotient and remainder; zero divisor fails/traps           |
| `a & b`, `a \| b`, `a ^ b`           | U32 bitwise operations                                         |
| `value << bits`, `value >> bits`     | U32 shifts, masking the count to its low five bits             |
| `bit_not value`                      | U32 complement                                                 |

From low to high, infix precedences are `$` (0), `|>` (5), `or` (20), `and`
(25), comparisons (30), `|` (40), `^` (45), `&` (50), shifts (55), addition and
subtraction (60), and multiplication, division, remainder (70). `$`, `and`, and
`or` associate right; comparisons are non-associative; the other listed
operators associate left.

`from` is ordinary source. Its body uses the general result-directed intrinsic
`@type.result "member" value`; there is no compiler rule for the name `from`.
Use a result annotation when context does not determine the destination.
`F32.from` and `U32.from` delegate to `to_f32` and `to_u32`, respectively.

Math helpers include generic `abs`, `min`, `max`, `clamp`, `lerp`, `square`; F32
`sqrt`, `floor`, `ceil`, `trunc`, `sin`, `cos`, `tan`, `sin_cos`, `wrap`,
`lerp_angle`, `is_finite`, `saturate`, and `smoothstep`, plus `pi` and `tau`.
`sin_cos` returns `(sine, cosine)` using one angle reduction. `tan` also shares
its angle reduction between sine and cosine. `smoothstep low high value` expects
`low < high`; `saturate` clamps to 0..1.

Import [vector.blot](vector.blot) for `Vec2` and `Vec3` records. Their owning
members supply vector `+`/`-`, scalar `*`/`/` (vector on the left), `dot`,
`length_squared`, `length`, and `normalized`; `Vec3` also supplies `cross`.
Normalizing the zero vector returns zero. Vector `lerp` constructs its result
directly from scalar interpolations, avoiding intermediate vectors.

Additional functions in `std/array`:

| Function                                      | Behavior                                       |
| --------------------------------------------- | ---------------------------------------------- |
| `map transform values`                        | Transforms elements in order                   |
| `filter predicate values`                     | Keeps matching elements in order               |
| `filter_map transform values`                 | Keeps the payloads of `$Some` results          |
| `indices flags`                               | Indices of `true` values, in order             |
| `prefix_sums values`                          | Inclusive U32 prefix sums, wrapping at 32 bits |
| `slice start count values`                    | Copies a checked contiguous range              |
| `concat left right`, `flatten ranges payload` | Concatenates arrays or payload ranges in order |
| `push value values`                           | Appends one value                              |
| `zip left right`                              | Pairs elements up to the shorter length        |
| `unzip pairs`, `unzip3 triples`               | Separates tuple columns                        |

Filtering evaluates its predicate/transform once per element. These helpers
handle empty arrays. An invalid slice traps or fails constant evaluation.
Filtering and `indices` append selected values into a private `GrowArray`, then
freeze it into the result array. `prefix_sums` traverses the input in order,
writing each inclusive sum into one independent fixed-length destination.
Evaluator operation and storage limits still apply.

## Constructor spelling

Data constructors use `$` in declarations, expressions and patterns (`#` is also
accepted):

```blot
type Optional x is data = $Present x | $Absent
const value: Optional U32 = $Present 42
const answer = case value of
  $Present number => number
  $Absent => 0
```

Primitive Boolean values are `true` and `false`. A type annotation uses the type
name without `$`; qualified construction puts the marker before the namespace,
such as `$vector.Vec3 { x: 0.0, y: 0.0, z: 0.0 }`. `:value` is shorthand for the
source-defined witness `$Type value`.
