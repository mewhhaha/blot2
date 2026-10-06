# Blot executable language guide

Read this before writing Blot. This describes the current executable language;
`DESIGN.md` also contains proposals. Each `blot` code block below is an
independent, compilable module.

The handwritten Zig compiler implements the language and collection syntax in
this guide.

## Commands

From the Blot repository:

```sh
just guide                                  # this reference; no compiler build
deno task blot guide                        # same CLI command
deno task blot fmt examples/syntax.blot      # normalize spacing
deno task build:compiler
deno task blot check examples/lists.blot
deno task blot build examples/lists.blot build/lists.wasm
```

Blot compiles to Wasm; a host loads the module and calls its entrypoints, the
`entry const` and `entry let` declarations of the file you compile. In the
sibling gdev checkout, `just run` starts Deno Desktop/WebGPU with source hot
reload.

## Layout, names, values, functions

Indent suites after `do:`, `if ...:`, and `case ... of`. No suite braces,
semicolons, or implicit final-expression returns in `do`. `//` starts a line
comment. Values use `snake_case`; types/constructors use `PascalCase`. Names are
lexically scoped and values immutable. `F32.sqrt` names a function, not a method
on an implicit receiver.

Scalars: `Unit` (`()`), `Bool` (`#True`, `#False`), `U32` (`42`, `0xFF`,
`4_096`), and `F32` (`1.0`, `1e-5`). No implicit numeric conversion. U32
arithmetic wraps at 32 bits; F32 rounds to binary32 and can yield infinity or
NaN. Prefix `-` negates F32; parenthesize negative arguments: `F32.abs (-2.0)`.

Functions take one argument; curry explicitly for several. Calls associate left:
`f a b` means `(f a) b`. Application binds tighter than infix operators. `f(x)`
also calls a function; `f(a, b)` passes one tuple. Unit thunks defer work until
called with `()`, without memoization. Recursion is supported.

```blot
const twice = fn value => value + value
const apply_twice = fn transform => fn value => transform (transform value)
entry const factorial = fn (value: U32) -> U32 => do:
  if value <= 1:
    return 1
  return value * factorial (value - 1)

entry const offset = fn value => value + 1.0
entry const answer = fn (value: F32) -> F32 => apply_twice offset (twice value)
entry let delayed = fn () => (fn () => factorial 5) ()
```

Function inputs and results start as fresh unknown types. Uses constrain them;
unconstrained types remain generic at generalization boundaries. Types are
inferred, including generic functions and callback effects. Type syntax:
`Array F32`, `Maybe U32`, `Result [U32, Bool]`, `(U32, Bool)`, `U32 -> F32`,
`U32 -> U32 ! {Foreign}`. Arrows associate right; parenthesize function argument
types. An annotation such as `(value: U32)` constrains the fresh argument type;
`a is U32` describes that idea but is not source syntax. Pure local `let`
bindings generalize; effectful `use` bindings do not introduce polymorphic
effects.

## Blocks, shadowing, and composition

`let name = expression` binds a pure value; `let name: Type = expression`
annotates it. `name := expression` shadows an existing local or parameter.
Inside its RHS, `self` and the old name refer to the previous binding. Earlier
closures keep old captures; aliases are not mutated. The new binding can have a
different type and is visible in the remaining suite. An outer `self` is
restored after the RHS. Rebinding requires purity, like `let`; record and array
paths such as `world.camera.position := self + offset` are supported.

`return` exits the nearest `do` block in the current function. Falling through
returns Unit; a last expression statement is discarded. Branch-local bindings do
not escape. Rebinding an existing outer name flows out of `if` and `if let`; a
branch that leaves it alone carries its previous value. Both outcomes must have
the same type. For a value, use `if condition then value else alternative`.

```blot
type Builder is data = #Builder U32
const add_step = fn amount => fn builder => case builder of
  #Builder value => #Builder (value + amount)
const plugin = fn builder => do:
  builder := add_step 10 self
  builder := add_step 20 self
  return builder

const application = do:
  let builder = #Builder 0
  builder := plugin self
  builder := add_step 12 self
  return builder

entry const answer = fn () => case application of
  #Builder value => value
```

Plugins/builders are ordinary source functions/types. The compiler has no
built-in ECS, resources, schedules, graphics, or application lifecycle.

## Loops

Prefer `for` for iteration; reserve recursion for recursive structures and
algorithms. `for index in start..end:` uses U32 bounds and excludes `end`.
Reversed/equal bounds run zero iterations. `for pattern in values:` iterates an
array with an irrefutable pattern. Bounds/the array evaluate once.
`for let value in values:` spells the binding explicitly. `for start..end:`
discards the range index. `for ever:` repeats without a bound; the body must
eventually suspend through a host callback, return from its enclosing `do`, or
continue running.

An outer local rebound directly in the loop with `:=` carries its new value to
the next iteration and after the loop. Its type must stay the same across
iterations. New locals and the index remain inside the loop. Nested loops carry
successors through their enclosing loop. Rebindings inside `if`/`if let`
branches also carry outward. A separately nested `do:` keeps its own scope.
`return` exits the enclosing `do`; a loop creates no new return boundary.
`break` exits the nearest loop and carries its latest local values into the
statements after it. In a request loop it also cancels the captured computation.
There is no `continue` statement yet.

```blot
entry const sum_to = fn (end: U32) => do:
  let total = 0
  for index in 0..end:
    total := self + index
  return total

entry const weighted = fn () => do:
  let total = 0
  for (value, weight) in [(2, 3), (4, 5)]:
    total := self + value * weight
  return total

entry const first_five = fn () => do:
  let count = 0
  for 0..5:
    count := self + 1
  return count
```

## Data, records, tuples, patterns

Declare nominal algebraic types with `type ... is data`, including generic
parameters: `type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)`.
Constructors have zero or one payload; use a tuple or named fields for several
values. Constructors themselves are values/functions. The prelude defines
`Maybe a = #Some a | #Nothing` and
`Result [value, error] = #Ok value | #Err error`.

A type or effect constructor takes at most one argument pattern. Use a list,
tuple, or record to bind several types. These shapes can nest; record arguments
match by field name. Record constructor declarations also support field
shorthand.

```blot
type Entry { head, tail } is data = #Entry { head, tail }
type Pair [left, right] is data = #Pair (left, right)
type Curried left => type right is data = #Curried (left, right)
const first = fn (entry: Entry { head: U32, tail: a }) -> U32 => do:
  let #Entry { head } = entry
  return head
const number = fn (pair: (Curried U32) Bool) => do:
  let #Curried (value, flag) = pair
  return value
entry const answer = fn () => first (#Entry { head: 42, tail: #True })
```

Currying is explicit in the declaration. `Curried U32` remains a constructor;
`(Curried U32) Bool` supplies its remaining argument. A free lowercase type name
in an annotation is inferred and shared within its binding. A local `let`
inherits type and effect-row names already introduced by an enclosing
annotation: a parameter's `a` and a local `let`'s `a` refer to the same type
variable. A name introduced only in that `let` gets a fresh scope, so sibling
`let` bindings may each use `b` independently.

Records use named constructors. Supply each field once; shorthand `{ x, y }`
uses locals. Fields evaluate in written order. Destructure with named patterns;
fields can be reordered or omitted. Read a named field with `value.field`;
`value.field := expression` rebinds the local root, with `self` naming the old
field value inside the replacement. Tuples use `(a, b)`; project with patterns
or `@product.get tuple 0` with a literal index and known tuple shape.

Matches must be exhaustive. `case a, b of` evaluates inputs once left-to-right;
each arm has the same number of patterns. Patterns include constructors,
records, tuples, U32/Bool literals, local binders, and `_`. `^name` matches an
existing U32/Bool local, parameter, or constant instead of binding a new name.
`if let` conditionally matches; `let pattern = value else:` requires an exiting
failure branch.

```blot
type Vec2 is data = #Vec2 { x: F32, y: F32 }
entry const selected = 7
const length = fn position => do:
  let #Vec2 { x, y } = position
  return F32.sqrt (x * x + y * y)
const unpack = fn candidate => do:
  let #Some value = candidate else:
    return 0
  return value

entry const distance = fn () => length (#Vec2 { y: 4.0, x: 3.0 })
entry const classify = fn (key: U32) => case key, #True of
  ^selected, #True => unpack (#Some 42)
  _, _ => 0
entry const conditional = fn () => do:
  if let #Some (number, #True) = #Some (42, #True):
    return number
  return 0
```

## Operators and compile-time associated dispatch

Default precedence, weakest first: `$` (0), `|>` (5), `||` (20), `&&` (25),
comparisons `== != < <= > >=` (30), bitwise `|` (40), `^` (45), `&` (50), shifts
`<< >>` (55), `+ -` (60), `* / %` (70), then application. `$`, `&&`, and `||`
associate right; comparisons are non-associative; the others associate left.
`f $ g x` means `f (g x)` and does not delay evaluation. Backticks call ordinary
functions infix. Declare custom fixities before other declarations:
`infixl 60 (++) = combine`, `infixr 50 (**) = power`, or
`infix 30 (~=) = close`. A backtick function can also have a fixity declaration.

Arithmetic/comparison operators call generic prelude functions. `add` uses
`@type.call "add" left right`. At compile time, try the left type's `add`, then
the right type's if the first cannot accept both operands. Never swap arguments.
A compatible left implementation wins even if its result conflicts with an
annotation. Associated functions belong to the nominal type's defining module;
`@type.call` accepts other literal member names too.

Receiver syntax selects a member from the receiver's type:
`tail.contains(witness)` means the type's `contains` function applied to `tail`,
then `witness`. `tail.contains` is a bound function; `values.length` is
`Array.length values`. This lookup never falls back to an argument's type. A
lexical receiver shadows a same-named module namespace. Ordinary qualified names
such as `Array.get` and `geometry.Point.add` still work.

Named constructor fields support `point.x`. A field must exist on every
constructor of its type; use a pattern when a field is variant-specific. A field
and associated function with the same name produce an ambiguity error.
`point.x := self + 1` constructs a successor and rebinds the local `point`.
Paths can mix fields and indices: `grid.rows[row][column] := self + 1`. The root
and each index are evaluated once, left to right, before the replacement; `self`
is the old value at the selected leaf. Existing aliases keep the old root. As
with plain `:=`, the replacement must be pure; use `use` first for effects.

Generic functions depending on dispatch monomorphize at their uses before const
evaluation and Wasm emission, including closures and recursion. No runtime
member lookup. Dispatch whose operand types (for members and fields: the
receiver's type constructor, such as `Array` or `Point`) are already fixed
inside the function by annotations, literals, primitives or other calls resolves
once at the function itself, so the function compiles once instead of once per
caller; only dispatch on types a caller supplies is specialized per use. Each
field access through the same nominal type and field shares one accessor. For
type identity, use the prelude's ordinary `Type` wrapper: `:head == :witness` or
`:head != :witness`. When both bindings already contain wrapped witnesses,
`head == witness` works directly. `Type.eq` uses
`@type.same left_witness right_witness` to compare concrete types at compile
time, including nominal module identity and generic arguments. A witness may be
a value or an uncalled constructor/function describing its final result type;
both witness expressions still evaluate once, left to right. Witnesses are value
expressions, not type literals: `:0` represents U32. Ordinary value equality
keeps using each value type's `eq` implementation. Exported functions need
enough type information to resolve dispatch; annotate unconstrained parameters.
`1 + 2` selects `U32.add`; `1.0 + 2.0` selects `F32.add`. Mixed operands fail
unless an implementation explicitly accepts them. `/` supports F32 and U32; U32
division truncates and a zero divisor fails/traps. Bool/record equality is not
automatically derived.

```blot
type Count is data = #Count U32
type Other is data = #Other U32
entry const same_value = 1 == 2
entry const same_type = #Type 1 == #Type 2
entry const same_nominal = #Type #Count == #Type (#Count 42)
entry const different = #Type #Count != #Type #Other
entry const compare = fn () => do:
  let head = #Type #Count
  let witness = #Type (#Count 0)
  return head == witness
```

```blot
type Box a is data = #Box a
const Box.add = fn left => fn right => case left, right of
  #Box a, #Box b => #Box (a + b)
const twice = fn value => value + value
entry const answer = fn (value: F32) => case twice (#Box value) of
  #Box result => result
```

## Lists, arrays, and libraries

Lists and arrays are distinct homogeneous, immutable types. `[]`, `[1, 2]`, and
`[[1], [2]]` construct `List` values. `#[]`, `#[1, 2]`, and `#[#[1], #[2]]`
construct `Array` values. Use `List T` and `Array T` in annotations. Passing one
to a function expecting the other is a type error. `List.from_array values` and
`Array.from_list values` explicitly copy between representations.

The Zig runtime backs lists with balanced trees of dense leaves. Small leaves
grow with demand, up to 248 elements. Exclusive end edits reuse storage; shared
edits copy one leaf and its tree path, preserving earlier versions. Traversal
caches the current leaf. Arrays stay contiguous with constant-time indexing;
array append/prepend copies the contents.

Both types have ordinary prelude members `values.length` and `values.is_empty`.
Only arrays support `values[index]`, `values[index] := replacement`, `get`, and
`set`. Lists use `for`, comprehensions, `map`, `filter`, and folds; convert with
`Array.from_list` when positional access is required. Generic indexing therefore
infers an Array argument, while generic traversal accepts either type. Lengths
and indices use U32. Indexing binds more tightly than application:
`f values[index]` passes the element to `f`. Separate an array argument with a
space (`f #[1]`), or write `f(#[1])`.

Spreads append or prepend while preserving written evaluation order:

```blot
const prepend = fn value => fn values => [value, ...values]
const append = fn value => fn values => [...values, value]
const surrounded = fn values => [0, ...values, 99]
const append_array = fn value => fn values => #[...values, value]
```

The spread operand must have the same collection type as the result. One spread
is allowed, with any number of prefix and suffix elements. The cons form
`[head | tail]` is also accepted.

Comprehensions construct the collection selected by their opening bracket:

```blot
const squares: List U32 = [x * x | x <- [1, 2, 3]]
const pairs: Array U32 = #[x * 10 + y | x <- [1, 2], y <- #[3, 4]]
const selected = [square | x <- [1, 2, 3], x > 1, let square = x * x]
```

Generators run from left to right, with the leftmost as the outer loop. Later
sources can use earlier bindings. A Bool guard skips every subsequent qualifier
and the result expression when false. Bindings stay inside the comprehension;
each generator source sees the scope before its own binding. The output is built
with a private growing list, then copied once if the requested result is an
array.

Direct array reads and updates check bounds at runtime and fail during constant
evaluation for an invalid index. `values.get(index)` returns `#Some value` or
`#Nothing`; `values.set(index)(replacement)` returns `#Some updated_array` or
`#Nothing`. These are ordinary functions, including their bounds checks. A guard
such as `if index < values.length:` is also useful. Direct accesses keep their
bounds checks inside guards; no proof token is required.

`@array.length`, `@array.get`, and `@array.set` are the underlying array
primitives. Lists have `@list.length`, but no `@list.get` or `@list.set`.
`@array.fill count value` evaluates the fill value once;
`@array.generate count generator` calls a pure `U32 -> T` generator in ascending
index order. Lists also have `@list.fill` and `@list.generate`. Empty
collections can need a `List T` or `Array T` annotation.

Wasm reuses locally allocated storage when its last reference is consumed,
including a single array carried through a loop. It copies when uniqueness
cannot be established: for example, live aliases, captured arrays, function
parameters, module values, or arrays reached through another collection. Reuse
is an optimization, not a change to immutable semantics. Record updates
reconstruct the record; they do not mutate it.

Direct `array.replace`, `list.append` and `list.prepend` calls preserve this
ownership optimization, including aliases and source wrappers whose body passes
each parameter exactly once to the primitive. Arguments still evaluate in their
written order. Arbitrary higher-order wrappers remain conservative.

Constant evaluation uses a separate representation. Append/prepend can extend
the latest collection version into unused buffer slots, with geometric growth;
all previously published elements remain immutable. Branches from older versions
and indexed replacements copy. Consequently, sequential staged builders are
linear, while large staged indexed-update loops can still be quadratic. Unused
reserved slots count against the evaluator's storage limit.

Import `std/array` for `generate`, `fill`, `length`, `is_empty`,
`at index values`, `replace index value values`, `get index values`,
`set index value values`, `fold_left reduce initial values`, `any`, and `all`.
`get`/`set` return Maybe on bounds failure; folds propagate callback effects;
`any`/`all` stop early.

```blot
import * as array from "std/array"

const squares = array.generate 4 (fn index => index * index)
entry const total = fn () => array.fold_left U32.add 0 squares
entry const snapshot = fn () => do:
  let values = #[1, 2]
  let original = values
  values[0] := self + 40
  return original[0] + values[0]
const checked = fn index => squares.get(index)
```

Import `std/list` for `generate`, `fill`, `from_array`, `to_array`, `length`,
`is_empty`, `map`, `filter`, `append`, `prepend`, `fold_left`, `any`, and `all`.
The fold and predicates propagate callback effects, and `any`/`all` stop early.
Lists have no indexed access or indexed updates. Direct compiler conversions are
`@list.from_array` and `@array.from_list`.

The implicit prelude supplies `identity`, `apply`, `always`, `compose`, `flip`,
`on`, `Bool.not`; `Maybe.map/bind/unwrap_or/is_some/to_result`;
`Result.map/map_error/bind/unwrap_or/to_maybe`; numeric arithmetic/comparisons;
`U32.to_f32`, `F32.to_u32`; `F32.abs/sqrt/floor/ceil/trunc/min/max`,
`clamp low high value`, `lerp left right weight`, `is_finite`, `sin/cos/tan`,
`wrap period value`, and `lerp_angle left right weight`.

Ordinary arguments are eager, including `Maybe.unwrap_or` fallbacks. `&&` and
`||` call the source-defined `and` and `or`, whose right parameters use `~`.
`Maybe.unwrap_or_else fallback candidate` and
`Result.unwrap_or_else fallback candidate` also defer their fallbacks.

`std/array` also supplies `map`, `filter`, `filter_map`, `slice start count`,
`concat`, `flatten`, `push`, `zip`, `unzip`, and `unzip3`. Collection arguments
come last for pipelines. Construction callbacks are pure; use `fold_left` or a
loop to sequence effects. Import `Vec2` and `Vec3` from `std/vector` for vector
operators and receiver members such as `dot`, `length`, and `normalized`.

```blot
import * as array from "std/array"
import { Vec2 } from "std/vector"

entry const total_length = fn () =>
  #[#Vec2 { x: 3.0, y: 4.0 }, #Vec2 { x: 0.0, y: 0.0 }]
  |> array.map .length
  |> array.fold_left .add 0.0
```

## Effects and host capabilities

`type Name a is effect = Input -> Output` declares a family of closed
operations, granting no IO. `@effect.provider Name implementation` creates a
provider; `do provider:` handles it in that scope. `use value <- call` sequences
an effectful result; `use call` discards it. `let` and `:=` require purity.
Providers are synchronous function implementations, not resumable continuations.

Host callbacks are explicit values with the sealed `Foreign` effect; source
cannot declare or handle it. Executable exports cannot leave ordinary source
effects unhandled. Closures retain their latent effects.

```blot
type Reader a is effect = { ask: Unit -> a }
const read_twice = fn () => do:
  use first <- Reader.ask U32 ()
  use second <- Reader.ask U32 ()
  return first + second

const reader = @effect.provider (Reader.ask U32) (fn () => 21)
entry const mocked = fn () => do reader:
  use answer <- read_twice ()
  return answer

entry const main = fn (read: Unit -> U32 ! {Foreign}) => do (@effect.provider (Reader.ask U32) read):
  use answer <- read_twice ()
  return answer

entry const uses_host = @effect.has (@effect.of main) Foreign
```

Const reflection: `@effect.of named_function`, `@effect.descriptor Operation`,
`@effect.has effects Operation`, `@effect.count effects`, and
`@effect.same descriptor descriptor`. These describe closed checked effects;
they cannot be runtime-reachable or create authority.

### Request handlers

`@computation thunk` captures a function taking Unit without running it.
`for request in @requests computation:` handles the thunk's operations. Its body
is one `case request of`, with distinct `effect` clauses and exactly one
`complete` clause:

```blot
type Validate is effect = { check: U32 -> U32 }

const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if value == 0:
          return 0
        yield value
      complete value =>
        return value

entry const answer = fn () => checked (@computation (fn () => do:
  use first <- Validate.check 40
  use second <- Validate.check 2
  return first + second
))
```

Indent each clause suite after `=>`. `yield value` supplies the operation result
and ends the clause. `return value` cancels the computation and exits the
nearest enclosing `do`. `break` cancels the computation, exits the request loop,
and runs the following statements. A `complete` clause receives the thunk's
final result and must return or break; it cannot yield. Every operation clause
must reply or exit on each path. There are no prelude constructors to import.

Outer locals rebound with `:=` carry handler state between requests and after
`break`. A captured computation can run again with fresh handler state. Calls
through helpers use the same handler; unrelated effects remain visible. Clause
bodies run outside the request installation, allowing forwarding to an outer
handler or provider. Generic operation clauses name a closed instance with
parentheses, as in `effect (Reader.ask U32) () =>`. This interface supports one
reply per request, without an exposed continuation value. See
[examples/requests.blot](../examples/requests.blot).

### Effect families and scoped state

An effect family declares operations for any type argument. Apply its name to a
type with spaces, just like `Maybe U32`: `State U32` is the U32 instance of the
effect family. `State.get U32` names that instance's `get` operation, and
`State.get U32 ()` calls it. Each concrete type selects distinct operations. The
single-operation form uses the family name as its operation name.

```blot
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Get a is effect = Unit -> a

const increment = fn () => do:
  use count <- State.get U32 ()
  use State.set U32 (count + 1)
  return count

entry const counted = fn () => do:
  let (next, previous) = do (@effect.state (State.get U32) (State.set U32) 41):
    return increment ()
  return next + previous

const fixed = @effect.provider (Get U32) (fn () => 7)
entry const read_fixed = fn () => do fixed:
  return Get U32 ()
```

Effect declarations name operations; providers supply their behavior in a `do`
scope. `State U32` and `State F32` can have different providers at the same
time.

For scoped state, `@effect.state ReadOp WriteOp initial` supplies a read/write
pair with signatures `Unit -> S` and `S -> Unit`. Its `do` block returns
`(successor_state, body_result)`. Each scope starts fresh, preserves the input
snapshot, and forwards unrelated effects.

Generic effect operations are ordinary functions. Their family arguments are
inferred from the operation's value argument and result context. A library can
express the relationship to a constructor witness with ordinary annotations:

```blot
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Counter is data = #Counter U32

const get = fn (witness: p -> a) -> a => State.get ()
const set = fn value => State.set value

const increment = fn () => do:
  use counter <- get #Counter
  let #Counter value = counter
  return set (#Counter (value + 1))

entry const answer = fn () => do:
  let (#Counter next, _) = @effect.run State.get State.set (#Counter 41) increment
  return next
```

`State.set value` infers the family argument from `value`. `State.get ()` infers
it from the expected result type. The `get` wrapper's `p -> a` parameter and `a`
result annotations connect a constructor's result to the operation's result. The
witness function is never called; an unused, unannotated witness would not
establish that relationship. Composite and curried effect arguments are inferred
by the same rules. Explicit arguments, including free annotation variables,
remain available: `State.get a ()`.

`@effect.run` installs the declared family's read/write pair, calls its Unit
thunk, and returns `(successor_state, result)`. `@effect.reader` and
`@effect.writer` install custom scoped implementations. These runner shortcuts
currently require a family with one plain type binder. Ordinary operation calls
and explicit providers support composite and curried families. Specialization
resolves operations before const evaluation and Wasm emission; there is no
runtime type lookup. Unhandled effects remain visible in function types; pure
annotations and const evaluation reject unhandled calls. An effect annotation
may include an open tail, as in `U32 -> U32 ! {State.get U32 | e}` or
`U32 -> U32 ! {| e}`. The tail is a row variable; using `e` as both a type
variable and a row variable in one binding is an error. Checked rows preserve
repeated labels; reflected effect sets discard repetitions. This release accepts
concrete operation labels, including closed instances of generic effects, before
an open tail. A label applied to a free type variable, such as `State a`,
reports `unsupported_polymorphic_effect_label`; symbolic generic labels require
a later effect-identity representation.

## Qualified bindings

An inferred generic function keeps the associated operations, members, fields,
or effect operations it needs as constraints on its type. A caller selects the
implementation when it supplies concrete arguments. You may write the same
constraints explicitly after a complete binding annotation:

```blot
const twice: a -> a where { associated "add" a a a } = fn value => value + value
const first: a -> b where { field "first" a b } = fn value => value.first
entry const answer = fn () => twice 21
```

The `where` clause is available on top-level `const`/`let` and local `let`;
`where` remains an ordinary identifier elsewhere. Predicates are separated by
commas, and a final comma is allowed. The forms are `associated "member" T T
T`,
`receiver "member" T T T`, `field "member" T T`, `update "member" T T
T`,
`operation Operation.name T...`, `type_rep T`, and `effect_rep !{...}`.
Parenthesize a non-atomic type argument. `associated`, `receiver`, and `update`
may end in an effect row such as `! {| e}`; without one, their invocation
effects are inferred. The clause constrains the binding's callers and must cover
the requirements of its body. Extra predicates deliberately narrow the public
type. Parameter annotations cannot contain `where` clauses.

In gdev, const resource/component registrations determine the nested world type;
`ecs.build` discards registration metadata and retains initial state, scope and
checkpoint closures. Storage values remain runtime state. Its `get`, `previous`,
column and query helpers require a unary constructor/function witness; wrap a
nullary constructor as `(fn () => #Idle)`.

## Expression tags

Put `@[expression]` before a top-level `const` or `let` to apply the expression
as a function to the initializer. A tag can use local names, named imports,
qualified imports, and function arguments. It may share the declaration line.
With several tags, the nearest runs first: `@[f] @[g] const x = value` binds
`f (g value)`. The declaration's type annotation constrains the result of all
tags, including when the initializer is a function.

```blot
const add = fn amount => fn value => value + amount
@[add 1]
@[fn value => value * 2] entry const answer: U32 = 20
@[add 1] entry let started: U32 = 41
```

`const` decorators execute at compile time under the usual step budget; `let`
decorators execute once at module startup. Unreachable tagged declarations are
type checked but not evaluated. A direct reference to the tagged declaration's
own bound name receives `recursive_tag`; tags on types, effects, and fixities
receive `unsupported_attribute`.

## Modules, constants, current limits

Imports precede declarations: `import * as math from "./math"` or
`import { Point as Position, distance } from "./geometry"`. Relative paths may
omit `.blot`; the CLI maps `std/` to the source library. Cycles are errors.
Top-level declarations are public by default: every declaration of every module
stays importable. Importing a type does not import differently named
constructors. Imported operator functions need local fixity declarations.

`entry const` and `entry let` mark host entrypoints. Exactly the entry module's
entry declarations become Wasm exports, under their own names; a build needs at
least one, and nothing else is exported. An entry's final type must fit the
guest ABI: functions over Unit, U32, F32, Bool, Array U32 or Array F32 (or one
scalar `! {Foreign}` callback) that handle every other effect, and Unit, U32,
F32 or Bool values. A generic entry, an `Array` value or a function that leaves
an effect unhandled is an error. Only the entry module reaches the host, so a
module it imports cannot declare entries. `entry` is contextual: it is a
modifier only before `const` or `let` at the start of a top-level declaration
and an ordinary name everywhere else (`fn entry => entry` is fine).

```blot
const helper = fn (value: U32) => value + 1
entry const answer = fn () => helper 41
entry let started: U32 = helper 1
```

Compilation keeps only what the entries reach. Every declaration is type
checked, but unreachable ones are never specialized, const-evaluated, run at
startup or emitted: an unused constant that would panic or exhaust the step
budget no longer fails the build. Associated dispatch is selected while
specializing, so a missing implementation such as `#True + #False` is reported
only in reachable code.

Functions are ordinary values: write `const name = fn argument => body` or
`let name = fn argument => body` at the top level. `const name = expression`
evaluates at compile time under a step budget. `let name = expression`
initializes once at runtime when the module starts, if an entry reaches it.
Compile-time expressions can build immutable values, closures, and builders, but
cannot do foreign IO. `@panic "message"` fails const evaluation or traps in
Wasm. Strings currently serve literal intrinsic arguments (panic messages/member
names), not runtime text. There is no general type-valued/comptime reflection
beyond the intrinsics.

Startup orders `let` initializers by their dependencies and rejects cycles.
Dependency analysis includes referenced function bodies, even when a function is
passed without being called. This conservative rule can reject a deferred cycle
such as:

```text
const read = fn () => value
let value = (fn ignored => 42) read // rejected: initialization_cycle
```

Compile-time initializers cannot read top-level `let` values or functions.
Runtime initializers must handle their effects with providers; module startup
does not supply implicit handlers.

Monadic blocks use an ordinary prelude adapter:

```blot
const try = monad Maybe
const sequence = fn candidate => do try:
  use value <- candidate
  return value + 1
entry const answer = fn () => Maybe.unwrap_or 0 (sequence (#Some 41))
```

`use` calls the selected type's `bind` with the remaining block as a function.
`return` calls `pure`; `return $` forwards an existing wrapped result. A failed
`Maybe` or `Result` bind skips subsequent effects and loop iterations. The
resolver expression runs once, nested `do` blocks have independent rules, and
unrelated effects remain visible. The same adapter accepts imported types and
user-defined data types with `pure` and `bind` members. Type-constructor values
can be aliased or passed through ordinary functions.

Monadic loops use the selected type's `iterate initial step` member. Each step
returns a wrapped `#Continue state` or `#Done result` using the prelude's
`Iteration state result` type. `Maybe.iterate` and `Result.iterate` use constant
call stack; failure skips later steps, and `return` still exits the nearest
`do`. Custom monads need an `iterate` member only for blocks containing loops.

```blot
const step = fn count =>
  if count < 42 then #Some (#Continue (count + 1)) else #Some (#Done count)
entry const answer = fn () => Maybe.unwrap_or 0 (Maybe.iterate 0 step)
```

Not yet executable: collection patterns, general text, F64/SIMD, general
type-valued computation, and exposed continuation values. Do not infer
availability from editor highlighting or design examples.

Hosts use `compiler/guest.ts` and guest ABI 2. Numeric arrays cross as copied
typed arrays; host callbacks are explicit scalar or numeric-array capabilities.
Async capabilities suspend a guest invocation without discarding its local
state. Records, general arrays and persistent guest handles are not host ABI
values yet. There are no implicit window/filesystem/network imports. For details
read `compiler/guest-abi.md`, `compiler/effects-and-io.md`,
`compiler/README.md`, and `std/README.md`.

## Selectors, conversion, and type witnesses

`.name` is a function that selects a field or associated member. Chained
selectors such as `.position.x` select both fields from the eventual argument.
Write member access without a space (`point.x`); write a separate selector with
a space (`array.map .x points`). `.add` selects a receiver's `add` member and
returns its remaining curried function. It is useful in
`array.fold_left .add 0 values`. Uppercase names are allowed when the owning
type actually declares that member.

`from` is defined in the prelude as `fn value => @type.result "from" value`. The
expected result type chooses that type's ordinary `from` function. Primitive
implementations use `to_f32`/`to_u32`; custom types can define their own
conversions. There is no default target when the context leaves it ambiguous.

```blot
entry const normalized = fn (first: U32) => from first / 6555.0
entry const explicit = fn (value: U32) => do:
  let converted: F32 = from value
  return converted
entry const different = if :1 == :2.0 then #False else #True
```

`:value` abbreviates `#Type value`; `:(expression)` groups a larger expression.
The existing witness rules apply: a constructor/function witness describes its
final result type. Its body is not called; an ordinary witness expression is
evaluated once. Type names belong in annotations, constructors in expressions
and patterns. Constructors require `#` in declarations, expressions and
patterns, including qualified names (`#time.Clock`) and Boolean constructors
(`#True`, `#False`). Type names and explicit type arguments stay unmarked.

`value |> transform` calls `transform value`. Both `pipe` and its fixity are
ordinary prelude declarations. For longer builder sequences, `:=` keeps each
step on its own line.

## Demand parameters

`fn ~value => body` captures an argument without evaluating it. A typed
parameter is `fn ~(value: U32) => body`. `@demand value` evaluates the captured
expression once; later demands share its result. `@force` remains a compatible
alias. Returning a closure that captures a demand is supported. Merely
referencing a demand does not force it.

```blot
const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
const call_lazy = fn (callback: ~U32 -> U32) => callback (20 + 1)
entry const answer = fn () => call_lazy twice
entry const skipped = #False && (@panic "unreachable")
```

Demand mode is part of the function type and survives aliases and partial
application. `~T` denotes a demand for a result of type `T`; latent effects are
inferred. Forcing requires those effects in the surrounding function, using the
providers active at the first force. An unused demand needs no provider. To
forward an existing demand to another lazy parameter, pass `@demand value`. Unit
callbacks remain available for work that should run on every call.

Known, fully applied small expression functions composed of parameter reads,
primitive scalar operations, conditionals and demands can use branches and local
values without a heap cell. This includes the prelude's `&&` and `||`, aliases,
and equivalent user functions. Repeated reads cache the result in a local at the
first demand; a new call starts a new cache. Escaping demands and more complex
bodies retain the shared runtime cell. Evaluation order, capture versions and
first-demand providers are the same in both cases.

## Pattern alternatives and layout

Alternative rows bind the same names and share one body. A failed guard falls
through to the next arm. Guards do not count toward exhaustiveness: retain an
unguarded fallback covering their cases.

```blot
type Choice is data =
  | #First U32
  | #Second U32
  | #Empty

entry const answer = fn value => case #Second value of
  #First amount | #Second amount if amount >= 40 => amount
  #First amount | #Second amount => amount + 2
  #Empty => 0
```

Indented expression continuations extend the preceding expression; `:` and `of`
open statement and case suites. Leading `|` can align with the first alternative
in a case arm. Parentheses also allow continuation across lines.
`blot fmt path.blot` normalizes spacing and blank lines, separates long data
alternatives, and removes parentheses that do not affect expression grouping.
`--check` checks without writing. The formatter verifies that the parsed
structure is unchanged before writing.
