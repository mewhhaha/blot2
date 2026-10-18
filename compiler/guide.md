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

An edit loop compiles with the development tier (`codegenTier: "development"` in
a project session), which skips the optional scalar and vector passes and
behaves the same; release builds use the default optimized tier. See
`zig-native/PROJECT_CLIENT.md`.

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

While editing, `@hole` stands for an unfinished expression. The checker infers
its expected type from surrounding code, then reports `typed_hole` with that
type and the current lexical bindings. It checks unused declarations too. Holes
always prevent output publication; correcting one allows a retained compiler
session to continue from its last successful revision. The client also returns
`diagnostic.hole`: a structured type graph, the visible bindings, and the
enclosing binding's generic requirements. Record fields, nominal identities,
effect arguments, repeated effect labels and open row tails remain explicit. The
graph shares repeated types and bounds its size; `truncated` signals omitted
detail. These are diagnostic-local identities, not reusable type witnesses.
Editor completion uses the same checked types and scope in a private query; it
does not build Wasm or replace a successful revision. Helix Ctrl-x requests
suggestions from unsaved buffers. See the
[completion contract](../zig-native/EDITOR_COMPLETION.md). Failed dispatch is
explained below.

```text
const unfinished = fn (value: U32) -> F32 => @hole
// Unfilled expression; expected: F32; in scope: value: U32
```

`let name = expression` binds a pure value; `let name: Type = expression`
annotates it. `name := expression` shadows an existing local or parameter.
Inside its RHS, `self` and the old name refer to the previous binding. Earlier
closures keep old captures; aliases are not mutated. The new binding can have a
different type and is visible in the remaining suite. An outer `self` is
restored after the RHS. Rebinding requires purity, like `let`; record and array
paths such as `world.camera.position := self + offset` are supported.

`return` exits the nearest `do` block in the current function. Falling through
returns Unit; a last expression statement is discarded. Branch-local bindings do
not escape. Rebinding an existing outer name flows out of `if`, `if let`, and
the `do:` arms of a `case` used as a statement; a branch or arm that leaves it
alone carries its previous value. Outcomes that reach the join must have the
same type; a branch that returns, or a branch or arm that panics or breaks,
contributes nothing. A `return` written directly in such an arm still exits only
the arm's `do:`: its value is discarded and the arm's rebindings carry out. A
`return` nested in an `if` or loop inside an arm that rebinds an outer name is
rejected with `case_arm_return`. For a value, use
`if condition then value else alternative`.

```blot
type Beat is data = #Up | #Down
entry const count = fn (up: Bool) -> U32 => do:
  let beat = if up then #Up else #Down
  let total = 0
  case beat of
    #Up => do:
      total := 7
    #Down => do:
      total := 3
  return total
```

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
branches and statement `case` arms also carry outward. Any other nested `do:`,
such as a statement-level `do:` or an arm of a `case` whose value is used, keeps
its own scope: a `:=` of an outer local there that is never read inside that
block is rejected with `dead_rebinding`. Rebind with `if`/`else` or a statement
`case`, or assign the value of a `case` expression. `return` exits the enclosing
`do`; a loop creates no new return boundary. `break` exits the nearest loop and
carries its latest local values into the statements after it. In a request loop
it also cancels the captured computation. There is no `continue` statement yet.

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

Transparent aliases name an existing type without introducing a constructor or
changing layout, equality, or associated dispatch. Aliases may refer forward to
other types, take the same shaped parameters as data declarations, and be
imported through either import form. Recursive alias expansion is an error;
recursive structures still use nominal data declarations. Alias names currently
belong in fully applied type positions, including effect-operation arguments,
not runtime type-constructor values. Named type parameters must be declared.
Written effect-row parameters, such as `e` in
`type Action a = Unit -> a ! {| e}`, are fresh at each alias use and remain
polymorphic across imports and compiled dependency files. Data and effect
declaration bodies cannot hide an unbound effect row through an alias. Pass the
full callable type as a type parameter, such as the `f` in
`type Box f is data = #Box f`, or use an alias with a closed row.

```blot
type Coordinate = F32
type Pair a = (a, a)
type Position = Pair Coordinate
const origin: Position = (0.0, 0.0)
entry const horizontal = fn () => @product.get origin 0
```

Currying is explicit in the declaration. `Curried U32` remains a constructor;
`(Curried U32) Bool` supplies its remaining argument. A free lowercase type name
in an annotation is inferred and shared within its binding. A local `let`
inherits type and effect-row names already introduced by an enclosing
annotation: a parameter's `a` and a local `let`'s `a` refer to the same type
variable. A name introduced only in that `let` gets a fresh scope, so sibling
`let` bindings may each use `b` independently.

Structural records use `{ x: value, y: value }`; their exact types use
`{ x: U32, y: F32 }`. A transparent alias such as
`type Point = { x: U32, y: F32 }` adds a name without a constructor. Named data
declarations retain their `#Constructor { ... }` forms. Field order does not
affect structural type equality or the executable layout.

Supply each field once; shorthand `{ x, y }` uses locals. Field expressions
execute once in written order. An ordinary call can pass a record directly:
`function { x: 1, y: 2 }`. Destructure a known record shape with `{ x, y }`;
fields can be reordered or omitted. An unannotated parameter's shape must be
known before destructuring; generic `record.x` access instead infers a field
requirement. Read a field with `value.field`; `value.field := expression`
rebinds the local root, with `self` naming the old field value inside the
replacement. Structural updates may change that field's type and preserve the
remaining fields, including nested records.

`@record.merge left right` constructs a structural record with all fields of
both operands. Right-hand fields replace same-named left fields, including their
types. Both operands execute once, left to right, even when a field is replaced.
The operation copies field words and shares nested values; merging with an empty
record reuses the other record. Nominal constructor values must be explicitly
unpacked before merging. A generic function can retain this shape equation using
a `merge Left Right Result` predicate:

```blot
type Merge [a, b, c] is contract = { merge a b c }
const extend: a -> b -> c where { Merge [a, b, c] } =
  fn left => fn right => @record.merge left right
const original = { x: 40, enabled: #False }
const updated = extend original { enabled: #True, extra: 2 }
entry const answer = fn () => @u32.add updated.x updated.extra
```

Tuples use `(a, b)`; project with patterns or `@product.get tuple 0` with a
literal index and known tuple shape.

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

When dispatch fails, the diagnostic explains it. The client returns
`diagnostic.explanation` (CLI JSON: `details.explanation`): the operator, the
member looked up, and each candidate in the order dispatch considered it. A
candidate has a `side` (`left`, `builtin`, `right`, `destination` for
`@type.result`, or `receiver`), the type's spelling and an `outcome`:
`unknown_operand`, `no_member`, `incompatible` (the member rejects these
operands), `unsupported_scalar`, or `result_mismatch` (selected, but its result
conflicts with the expected type, so no later candidate was tried). A right type
equal to the left is not listed twice. Explanations hold at most four candidates
and 256 bytes per spelling; `truncated` marks cut detail.

```text
entry const answer = fn () => 1 + 2.5
// missing_associated; `+` (add): left U32 incompatible, right F32 incompatible
```

Named constructor fields support `point.x`. A field must exist on every
constructor of its type; use a pattern when a field is variant-specific. A field
and associated function with the same name produce an ambiguity error.
`point.x := self + 1` constructs a successor and rebinds the local `point`.
Paths can mix fields and indices: `grid.rows[row][column] := self + 1`. The root
and each index are evaluated once, left to right, before the replacement; `self`
is the old value at the selected leaf. Existing aliases keep the old root. As
with plain `:=`, the replacement must be pure; use `use` first for effects.

`std/path` packages pure getters and setters as
`Path source target focus replacement`. `make read write` constructs a path,
`get path source` reads its focus, and `set path replacement source` returns the
target. `modify path transform source` applies the transform once to the old
focus; the transform may perform effects. Each ordinary argument evaluates once,
left to right. Paths construct successors, so existing aliases and untouched
fields, including callbacks, keep their values.

`compose outer inner` selects the inner focus within the outer focus. Setters
rebuild from the inner target outward, allowing the replacement and enclosing
record types to change. `identity` selects the whole value. These are ordinary
source functions; custom getters and setters must be pure, and the type checker
checks their common source type and every composition boundary.

```blot
import * as path from "std/path"
const position = path.make (fn source => source.position)
  (fn replacement => fn source => @record.merge source { position: replacement })
const x = path.make (fn source => source.x)
  (fn replacement => fn source => @record.merge source { x: replacement })
const position_x = path.compose position x
entry const answer = fn () => do:
  let original = { position: { x: 40, y: 7 }, health: 2 }
  let changed = path.set position_x 2.5 original
  return @f32.add (path.get position_x changed) (@u32.to_f32 original.health)
```

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
grow with demand, up to 244 words. Exclusive end edits reuse storage; shared
edits copy one leaf and its tree path, preserving earlier versions. Traversal
caches the current leaf; word-element loops traverse a whole leaf before
resolving the next one. Arrays stay contiguous with constant-time indexing;
array append/prepend copies the contents.

Lists and arrays of small, flat scalar tuples or records store the fields
consecutively, without a separate heap object for each row. Reads still produce
ordinary immutable values: keeping a row, capturing it or editing the array
preserves the earlier value. Nested and reference-bearing rows retain their
existing boxed storage. Lengths and slices count logical elements, including
when a packed row crosses a list leaf boundary. List/Array conversion copies
spans of words without constructing a separate object for each row.

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
array. For rectangular generators with total, allocation-free bounds and no
intermediate observations, the compiler can allocate the exact final storage
directly. Filters, ragged generators and observable intermediate values keep the
growing-list path; iteration and element evaluation order stay the same.

`for` and comprehension generators also accept user-defined iterables. The
ordinary associated `iter` function creates a cursor once; its `next` function
returns `#Some (value, next_cursor)` or `#Nothing`. These are the usual prelude
Maybe constructors. Iterator types and adapters receive no name-specific
optimization.

```blot
type Countdown is data = #Countdown U32
const Countdown.iter = fn (cursor: Countdown) => cursor
const Countdown.next = fn (cursor: Countdown) => do:
  let #Countdown remaining = cursor
  return if remaining == 0 then #Nothing
    else #Some (remaining, #Countdown (remaining - 1))

entry const sum = fn count => do:
  let total = 0
  for value in #Countdown count:
    total := self + value
  return total
```

Both operations may have effects. Each pull happens before the corresponding
body, and `break` or `return` stops further pulls. Nested loops and
`do (monad Maybe)` retain their normal control flow. Array/list loops and
numeric ranges keep their direct traversal paths.

`values.iter` gives an immutable snapshot cursor for a List or Array. Copying a
cursor preserves its position; advancing one never changes another. Later
updates to the original collection preserve the cursor's snapshot. The opaque
types are `Cursor (List a)` and `Cursor (Array a)`. The low-level operations
`@cursor.has cursor`, `@cursor.value cursor` and `@cursor.advance cursor` expose
the same sequential interface; value/advance on an exhausted cursor trap. They
do not add indexing to List.

`std/iter` supplies ordinary source functions. Adapters take the iterable last:

```blot
import * as iter from "std/iter"
const selected = fn count =>
  iter.collect_list (iter.take count
    (iter.map (fn value => value * 2)
      (iter.filter (fn value => value > 2) [1, 2, 3, 4, 5])))
```

The module includes `range start end`, `map`, `filter`, `take`, `take_while`,
`enumerate`, `zip`, `zip_strict`, `windows`, `fold_left`, `any`, `all`,
`collect_list` and `collect_array`. `take 0` never pulls its input. `zip` stops
when either input ends and polls left before right; if the right ends first, one
unpaired left value may have been consumed. `zip_strict` polls both and traps on
unequal lengths. `windows width input` requires positive width and returns only
complete sliding List windows. Saved windows remain immutable. These pipelines
avoid intermediate collections explicitly. Bounded ordinary inlining and scalar
replacement remove eligible local wrappers and step values; escaping or opaque
state can still allocate.

`std/list` provides structural operations with the collection last:

```blot
import * as list from "std/list"
const joined = list.concat [1, 2, 3] [4, 5]
const middle = list.slice 1 3 joined       // [2, 3, 4]
const halves = list.split_at 2 joined      // ([1, 2], [3, 4, 5])
const prefix = list.take 20 joined         // clamps to the length
const suffix = list.drop 2 joined          // [3, 4, 5]
```

Concatenation shares complete subtrees and rebuilds the boundary paths. Slices
copy partial boundary leaves, so a one-element slice does not retain a large
discarded leaf or its original root. Tiny adjacent leaves may be combined with a
bounded copy. `slice start count` and `split_at index` check their ranges;
`take` and `drop` clamp. `@list.concat` and `@list.slice` provide the underlying
operations. `std/array` also exposes `concat` and `slice`; arrays copy
contiguous storage. List/array conversion copies whole leaf spans.

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

Passing an array to a saturated direct call is not an alias once the call
returns if the callee only reads that parameter: lengths, element or
`@simd.load` lane reads, finite traversal, or passing it on to another such
parameter. A closure literal that
`@array.generate` or such a call runs and then drops borrows the captures its
body only reads in the same way. The proof follows each callee's body, whether
or not it is inlined, so a later `values[i] := x` updates in place. Returning
the argument, storing it in a value, capturing it in a closure that survives,
generic dispatch the proof cannot resolve, or an edit of the same array in a
later argument of that call keeps the copy. A non-scalar element the callee
reads still blocks nested in-place edits, as a direct read does.

For proven local temporaries, the compiler releases storage after the final
borrowed read or write. This also covers objects larger than the scalar
replacement limit, branches, early returns and loop exits. Direct calls can
borrow storage or transfer a proven fresh result to their caller. Escapes,
unknown addresses, recursive calls without a usable summary and opaque calls
keep the existing reclamation policy. When references stay within a proven group
of allocations, each member's temporary owner is released after the group's
final use. Other owners remain valid. Numeric array payloads and numeric List
leaves have no child pointers; pointer-looking integer bits stay scalar.

Dynamic sharing uses counted strong edges, journal leases and a nonmoving
allocator in linear memory. Trial deletion reclaims real unreachable cycles.
Plain data never enters it: records, data types from any module, arrays and
lists whose types reach no State, closure, demand, provider or erased value
cannot form a cycle, so their allocations are not cycle candidates.
Loop frames own incoming and outgoing carries; allocation traffic does not
trigger a separate production tracing scan. Invocation retirement releases
temporary owners while preserving module initialization values and independently
held results. Generated host callbacks, suspended requests and demand memos keep
counted roots until completion or cancellation. Production emission requires
complete ownership facts and returns a diagnostic when that proof is incomplete.
See `zig-native/TRACING_REPLACEMENT.md`, `zig-native/PERSISTENT_ROOTS.md` and
`zig-native/SUSPENDED_OWNERSHIP.md` for ownership and qualification records.

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

## SIMD

`std/simd` exposes `U32x4` and `F32x4` as ordinary four-element product aliases.
Construct or destructure lanes with tuples and use ordinary partial application
on the source functions:

```blot
import * as simd from "std/simd"
const translated = fn lanes => simd.u32_add lanes (1, 2, 3, 4)
const scaled = fn lanes => simd.f32_mul lanes (2.0, 2.0, 2.0, 2.0)
```

Every operation with a scalar counterpart gives the bits of that scalar kernel
in each lane, including NaN, signed zero and wrapping. Collection arguments and
lane operands come last, so `lanes |> simd.u32_shl 13` pipelines.

- Arithmetic: U32 add/subtract/multiply and bitwise and/or/xor; F32 arithmetic,
  abs/negate, sqrt and rounding; saturating F32-to-U32 and U32-to-F32
  conversion.
- Shifts: `u32_shl count lanes`, `u32_shr count lanes` (logical) and
  `u32_sar count lanes` (arithmetic) take a scalar U32 count that wraps modulo
  32, like `<<` and `>>`.
- Min/max: `f32_min a b` is the prelude's `min a b`, `if a < b then a else b`,
  in each lane, so NaN and equal zeros choose `b`; `f32_max a b` is
  `if a > b then a else b`. They lower to `f32x4.pmin b a` and `f32x4.pmax b a`,
  whose definitions are exactly those selections. `u32_min`/`u32_max` compare
  unsigned.
- Comparisons: `f32_eq`/`ne`/`lt`/`le`/`gt`/`ge` and the unsigned `u32_*`
  versions return a `U32x4` mask, all ones where the comparison holds and zero
  elsewhere. `f32_select mask yes no` and `u32_select mask yes no` select
  bitwise: a mask bit of one takes `yes`. `u32_not`, `u32_andnot a b`
  (`a & ~b`), `any_true` and `all_true` (every lane nonzero) complete the mask
  helpers.
- Lane movement: `f32_shuffle (i0, i1, i2, i3) a b` takes lanes 0–3 from `a` and
  4–7 from `b`; `f32_swizzle (i0, i1, i2, i3) a` and `f32_broadcast i a` select
  from `a`. U32 versions exist for all three. Lane selectors must be in-range
  U32 literals at a direct, fully applied call; anything else is the
  `simd_lane_literal` compile error.
- Horizontal: `f32_sum` adds left to right; `f32_sum_pairwise` explicitly
  chooses `(a + b) + (c + d)`. `f32_dot a b` and `f32_dot3 a b` (lanes 0–2)
  multiply lanes and add them left to right, the grouping of `std/vector`'s
  `Vec3.dot`, so they match the scalar dot bit for bit.
- Reinterpretation: `f32_bits lanes` gives the U32 bits of each lane and
  `f32_from_bits lanes` rebuilds F32 lanes, payloads included.
- `f32_relaxed_madd a b c` computes `a * b + c` fused or separately rounded, as
  the host chooses, so its results can differ between machines and from
  compile-time evaluation, which fuses. It uses the relaxed-SIMD instruction set
  and is never chosen implicitly.
- `load index values` and `store index lanes values` read or replace four
  consecutive U32, F32 or Bool elements after one range check, which precedes
  the index arithmetic. A store keeps the Array snapshot contract and edits in
  place when the Array is exclusive; a direct `load` wrapper call only reads its
  Array, so it does not force a later update to copy.

Explicit compiler operations use `@simd.u32x4.*` and `@simd.f32x4.*` with their
full argument lists, like the scalar compiler operations;
`@simd.load values
index` and `@simd.store values index lanes` take the Array
first.

In the optimized tier a private four-lane value lives in a v128 local: tuple
construction, destructuring, operations, loop carries and copies of parameters,
call results and fields need no heap object. A value boxes once where it leaves
the function (a non-inlined call, a stored record or closure field, a return)
when that point runs no more often than the value was produced; otherwise it
keeps ordinary refcounted storage. A private function whose parameter or
result such operations prove to be four lanes takes and returns it as a v128
value at direct calls, so a non-inlined helper, recursion or a pipeline into a
named function allocates nothing. Closure calls, including partial applications
and pipelines into them, keep the boxed ABI and box the value once per call.

Eligible independent numeric array-construction kernels automatically use
four-lane Wasm SIMD and a scalar tail. Admission follows bounded ordinary
function bodies, including private numeric locals and unconditional block
returns; it does not recognize library names. Memory reads, effects, conditional
branches and potentially trapping integer division remain scalar. Four checked
F32 row fields multiplied by the same factor may share a vector product. Stores,
calls and unproved control edges end that proof. F32 expression order and U32
wrapping are preserved. No reduction is automatically regrouped: `f32_sum` adds
left to right, while `f32_sum_pairwise` explicitly chooses `(a + b) + (c + d)`
and can round differently.

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
operation labels, including symbolic generic arguments such as `State.get a`,
before an open tail. Instantiation preserves their exact declaration and family
arguments. Reflection still requires complete closed descriptors; unresolved
arguments cannot become a closed reflected effect set.

[Scoped effect identities](../zig-native/SCOPED_EFFECTS.md) specifies the
checked representation: symbolic family arguments, distinct same-typed
capabilities and checked scope/capture lifetimes. The direct annotated-family
subset accepts `@effect.scope (fn (state: State U32) => body)`, with member
operations such as `state.get ()`. Each entry creates fresh authority. Local
aliases and providers preserve its identity; its operations must be handled
before exit. Generic scope factories may use symbolic family payloads such as
`State a`; returning the same inherited payload shape retains its original
lifetime. A longer-lived outer capability may pass through an inner scope in
structural data; only the exiting owner is forbidden in that result. Primitive
and structural data may return; callable, demand, provider, nominal and
unresolved results or transferred arguments conservatively reject. Direct source
closures may return when a bounded capture proof excludes the exiting owner;
unknown captures still reject. A direct anonymous adapter whose whole body
invokes its callback may borrow a capturing callable with a structural result.
Exact generic identity and Unit callback helpers own validated public flow
contracts. A single annotated capability parameter may read a Unit operation
through source or compiled helpers, for example
`fn (state: State a) -> a ! {state.get} => state.get ()`; calls substitute the
argument's exact identity in that row. Exact curried callback helpers also
preserve it, for example
`fn (state: State a) => fn (callback: Unit -> a ! {state.get | e}) => callback ()`.
Complete annotations may bind the same capability relationship:
`const read: (state: State a) -> a ! {state.get} = fn input => input.get ()`.
For curried invocation, group the resulting callable type:
`(state: State a) -> ((Unit -> a ! {state.get | e}) -> a ! {state.get | e})`.
Binder names belong only to subsequent parts of that annotation; the
implementation may use different parameter names. The callback's remaining
effects must still be handled before their owner's scope exits. A direct source
closure may be written to a trusted local `@effect.state` cell installed inside
every captured capability's lifetime. Older cells, ordinary provider overrides
and unknown captures reject; a lambda does not inherit handlers from where it
was constructed. Fully applied helpers with two capability inputs may read a
Unit operation from either input; each argument retains its own identity, even
when the inputs share a family or payload. For example,
`fn (left: State a) => fn (right: State b) => right.get ()` preserves `right` in
its result row. The complete header form is
`(left: State a) -> ((right: State b) -> b ! {right.get})`.

A local `if flag then left else right` may select capabilities with the same
family and payload. Its aliases retain one selected identity; handling that
value subtracts its operation, while independent roots or another selection keep
their own requirements. Its footprint includes both possible owners. This
bounded form must be evaluated once in the active scope callback and reach that
scope's owner. A factory may resolve a symbolic payload while keeping that
identity. Repeated callback/loop selection and public generic selection schemes
still reject. Pure named helpers may construct nested products or records from
up to 16 parameters and scalar constants, such as
`fn first => fn second => {second, nested: (first, 42)}`. Their owned result
footprint records every retained input; unused inputs add no result footprint. A
named helper may also directly invoke one callback with Unit, such as
`fn unused => fn run => fn other => run ()`. Its contract retains the selected
callback's exact operation row. Exact helpers may pass ordered formal inputs to
one callback, such as `fn run => fn left => fn right => run left right`. The
actual literal or checked named callback must prove that it does not store those
inputs; earlier captures keep their own lifetimes. Local callback aliases
preserve their selected owners. Repeated effect labels still require separate
handler occurrences, including when two inputs alias one owner. These contracts
use the existing 16-parameter bound. Named forwarding helpers compose those
relationships through exact checked producers, including imported helpers.
Factory/projected callbacks remain unsupported. Other hidden capture/store
contracts and mixed-owner State pairs remain unsupported. See
[qualification](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md).

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

Use `type Name parameters is contract = { ... }` to name a reusable bundle of
predicates. Contracts can include other contracts, refer forward, take shaped or
explicitly curried type parameters, and be imported by name or namespace. They
introduce no runtime values or dictionaries; the ordinary evidence and
associated-dispatch rules still choose implementations.

```blot
type Add a is contract = { associated "add" a a a }
type Arithmetic a is contract = { Add a, associated "mul" a a a }
type Project [owner, value] is contract = { field "value" owner value }
type Box a is data = #Box { value: a }
const twice: a -> a where { Arithmetic a } = fn value => value + value
const read: a -> b where { Project [a, b] } = fn box => box.value
entry const answer = fn () => twice (read (#Box { value: 21 }))
```

Every use instantiates the contract's type and effect-row parameters separately.
Contracts are erased requirements, not type aliases or type-constructor values.
Their bodies are checked even when unused. Recursive bundles, undeclared type
parameters, wrong argument shapes, and missing requirements are errors. Existing
rules about written function effects remain in force: use `a -> b ! {| e}` when
a wrapper propagates effects.

Contracts also declare defined type equations, abstract types and complete
abstract function signatures. Members share one name space. Contract parameters
scope over each member; members cannot introduce additional type or row binders.

```blot
type Identity a is contract = { type Item = a }
type Source s is contract = { type Item, const first: s -> (Source.Item s) }
type View a = Identity.Item a
const keep: a -> (Identity.Item a) where { Identity a } = fn value => value
entry const answer = fn () => keep 42
```

A projection such as `Identity.Item U32` supplies the contract's complete
argument shapes and normalizes by type and effect-row substitution. A namespace
import uses `lib.Identity.Item U32`. Forwarding retains the original producer
and member identity. Generic aliases retain the projection recipe and propagate
its requirements at each use. Data and opaque payloads must discharge those
requirements when declared. Public annotations cannot expose a private contract,
even if its defined equation reduces to a public type.

`type_eq T U` gives logical semantic equality within a qualified body and must
be discharged at a concrete use. Equality includes nominal identity and exact
function effect rows. It never infers a contract input from an abstract output.
Abstract projections may remain in principal schemes under their contract
requirement; concrete execution requires implementation evidence. Residual
projections provide no backend layout. Direct, mutual and growing equation
cycles reject after alias expansion; normalization shares exact graph work
within the project budget. The complete rules are in
[associated contracts](../zig-native/ASSOCIATED_CONTRACTS.md).

An explicit implementation supplies every abstract type and function member. Its
named parameters must be determined by its head; prerequisites cannot introduce
extra binders. Defined equations cannot be overridden.

```blot
type Source s is contract = { type Item, const first: s -> (Source.Item s) }
impl ArraySource a : Source (Array a) = {
  type Item = a,
  const first = fn values => @array.get values 0,
}
const read: s -> (Source.Item s) where { Source s } =
  fn values => Source.first values
entry const first = fn () => read #[42]
```

Heads must be disjoint across the acquired public module graph, irrespective of
prerequisites. The original contract producer or the producer of the head's
anchor nominal owns each implementation. A module's `private impl` stays
lexical. Generic public callers supply their own evidence context. Known inputs
select a unique head and then discharge its complete prerequisites; an
incompatible head has no fallback. Selection never executes a method or forces
its captures. Member functions use ordinary callbacks, currying, effects and
ownership when called. They do not register legacy receiver methods or
operators.

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
Top-level declarations are public by default. `private` before a value, alias,
data, contract or effect declaration keeps its name inside its defining module;
constructors and operations inherit that visibility. `private entry const` keeps
the host export while hiding the Blot import. Importing a type does not import
differently named constructors. Imported operator functions need local fixity
declarations. `export { answer as forwarded, Token } from "./producer"` forwards
selected public names while retaining their original producer and kind.

`opaque type Token = U32` declares a nominal type with one private constructor,
`#Token`. The producer can construct and match it, including
`fn (#Token value) => value`, and inspect record representation fields. Callers
use public factories, observers and associated declarations; aliases and type
witnesses preserve opacity. Token remains distinct from U32 inside its producer.
Public signatures cannot expose private nominal/effect identities or predicate
implementations. Scalar and reference representations erase the opaque wrapper
without adding a runtime allocation or tag. See
[module abstraction](../zig-native/MODULE_ABSTRACTION.md) for import and
artifact rules.

Hosts can register typed parsers for external files through `createCompiler`'s
`assets` option. Source imports those virtual modules normally, for example
`import { value } from "./settings.json"`. Parsers return type descriptions and
values, or types and references to host resource snapshots. See
[typed asset imports](assets.md) for JSON and shader integration. This is an
explicit host parser boundary; the native CLI alone does not choose file
parsers.

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

Not yet executable: collection patterns, general text, F64, general type-valued
computation, and exposed continuation values. Do not infer availability from
editor highlighting or design examples.

Hosts use `compiler/guest.ts` and guest ABI 2 or 3. ABI 3 adds private
invocation ownership hooks while preserving the same host value types. Numeric
arrays cross as copied typed arrays; host callbacks are explicit scalar or
numeric-array capabilities. Async capabilities suspend a guest invocation
without discarding its local state. A guest closure capturing a host callback
stays bound to that invocation: calling it after the invocation ends fails; a
later host argument cannot rebind it. Records, general arrays and persistent
guest handles are not host ABI values yet. There are no implicit
window/filesystem/network imports. For details read `compiler/guest-abi.md`,
`compiler/effects-and-io.md`, `compiler/README.md`, and `std/README.md`.

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

A delayed argument is checked by its actual construction captures. Capture-free
work can be delayed inside a scoped effect, including work that creates its own
scope when forced. Capturing a fresh capability or operation still retains that
authority, even when the expression returns a scalar or its memo is already
ready.

A request handler's `return` or `break` cancels an unfinished demand and makes
it pending again. Its next demand starts the expression again under the then
active providers. Effects already performed are not rolled back. A handler's
`yield` resumes evaluation; only normal completion publishes the shared result.
Recursive forcing fails. If a Wasm trap or host exception interrupts a demand,
that demand remains terminal: later attempts fail without running its expression
again. Other entry calls remain usable.

Known, fully applied small functions can use branches and local values without a
heap cell. Admitted bodies include primitive scalar and collection operations,
conditionals, local aliases and structured range, collection and forever loops.
This includes the prelude's `&&` and `||`, aliases, custom operators and
equivalent user functions, including acyclic forwarding through available
imported or compiled bodies and immutable compile-time captures. Both codegen
tiers use this proof. A memo created outside a callee loop survives all its
iterations; a call inside a loop creates fresh state on each execution. Aliases
share the first normally completed result. Known lexical callbacks and local
aliases can share those same memo locals when the complete bounded proof
establishes every use and capture. Zero iterations and unchosen branches perform
no demand. Escaping demands, provider changes, arbitrary callbacks and bodies
outside the bounded proof retain the shared runtime cell. Evaluation order,
capture versions and first-demand providers are the same in both cases.

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

## Structured tasks

`@task.scope` calls a once callback with a fresh group. Spawn consumes a once
Unit thunk; join consumes its handle and transfers the result. Cancel consumes
its handle and waits for cleanup. Scope exit joins remaining children before
releasing the group. Groups, handles and views cannot escape their region.

```blot
entry const answer = fn () => @task.scope (fn group => do:
  let left = @task.spawn group (fn () => 20)
  let right = @task.spawn group (fn () => 22)
  return @u32.add (@task.join left) (@task.join right))
```

Unique captures move to one child. Immutable data can be shared. Read loans
require an owner enclosing the destination group. Mutable state/provider
capabilities and shared pending demands cannot cross tasks. A moved affine
demand may be forced by its child when its captures transfer and its latent row
is closed and empty.

`@task.split owner ranges callback` moves a unique Array into exclusive views
and returns `(owner, callback_result)` after every child finishes. Ranges are
one to sixteen literal `(first, end)` pairs, half open and nonoverlapping.
Runtime admission checks their ends against the actual Array length before
calling the callback. `@task.read view index` and `@task.write view index value`
use indices relative to that view and check bounds. A view moves into at most
one child; the Array owner is unavailable until the callback finishes.

Host callbacks used by a child require the explicit
`concurrent (U32 -> U32 ! {Foreign})` qualifier, with scalar or numeric Array
arguments/results. Bind them with `{ concurrent: true }` in the guest adapter.
An ordinary Foreign callback grants no concurrent-use authority. Tasks run
cooperatively in one instance; overlapping suspended host callbacks require JSPI
and `callAsync`. Cancellation waits for an unabortable host callback to settle.
See [the task contract](../zig-native/STRUCTURED_CONCURRENCY.md) and
[the host boundary](guest-abi.md#structured-task-extension).
