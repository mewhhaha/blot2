# Blot executable language guide

Read this before writing Blot. This describes the current executable language;
[spec.md](spec.md) records the full **Blot vNext** specification, and
[VNEXT_ROADMAP.md](../compiler/VNEXT_ROADMAP.md) tracks the compiler pruning
roadmap. Each `blot` code block below is an independent, compilable module.

The Goose compiler emits Wasm directly. Applications use named owners, explicit
copies and invocation-local borrows with guest ABI 8. The
[ownership contract](../compiler/CONTRACT.md) describes how values cross calls.
The [migration handoff](../../CONTINUE.md) tracks current frontier metrics and
qualification.

## Blot vNext quick reference (implemented today)

- **Function syntax:** single-expression `func x => expr` (implicit return) and
  block-bodied `func x =>` indented suites with explicit `return value` /
  `return use call`. Legacy `=> return expr` and `=> return do:` remain accepted
  during migration.
- **Array & ownership type symbols:**
  - `#[T]` (unified owned dynamic array, equivalent to `Array T`),
  - `#[n; T]` (equal-length-checked fixed array family),
  - `&[T]` (read-only borrowed view, equivalent to `View T`),
  - `*T` (shared immutable handle via `freeze` / `seal`),
  - `*(A -> B)` (frozen closure value).
- **Scoped effect handlers:** `with Effect = { op: func arg => body }:` handles
  an effect inline over an indented suite without separate `@effect.provider`
  wiring.
- **Speculative undo scopes:** `fork x:` borrows linear `x` mutably inside an
  indented suite, logs writes, and restores `x` on exit (rejecting `Foreign`
  effects inside `fork`).
- **Typed compile-time introspection:** `#for field in #fields T:` and
  `#for variant in #variants T:` unroll over a concrete record/sum type's
  fields or variants, supporting `val.(field)` reads, `val.(field) := expr`
  updates, `#if` / `#else` compile-time conditionals, field metadata
  (`field.name`, `field.index`, `field.has_default`, `field.default`,
  `field.has_tag`, `field.tag`), and expression-position reflected record
  builders (`let built: T = #for field in #fields T: ... break value`).

## Commands

From the Blot repository:

```sh
just guide                                  # this reference; no compiler build
deno task blot guide                        # same CLI command
deno task blot fmt examples/syntax.blot      # normalize spacing
deno task build:compiler
deno task blot check examples/arrays.blot
deno task blot build examples/arrays.blot build/arrays.wasm
```

The host loads the Wasm module and calls the `io`, `io const` and
`io let` declarations of the compiled file. In the sibling Gdev checkout,
`just dev` starts Pen with hot reload. `just run` compiles once and plays.

An edit loop compiles with the development tier (`codegenTier: "development"` in
a project session), which skips the optional scalar and vector passes and
behaves the same; release builds use the default optimized tier. See
`docs/compiler/PROJECT_CLIENT.md`.

## Layout, names, values, functions

Indent suites after `do:`, `if ...:`, and `case ... of`. No suite braces,
semicolons, or implicit final-expression returns in `do`. `//` starts a line
comment. Values use `snake_case`; types/constructors use `PascalCase`. Names are
lexically scoped. Scalar and inline aggregate values copy by value; named array
owners permit explicit mutation through aliases. `F32.sqrt` names a function,
not a method on an implicit receiver.

Scalars: `Unit` (`()`), `Bool` (`true`, `false`), `U32` (`42`, `0xFF`, `4_096`),
and `F32` (`1.0`, `1e-5`). No implicit numeric conversion. U32 arithmetic wraps
at 32 bits; F32 rounds to binary32 and can yield infinity or canonical positive
quiet NaN (`0x7fc00000`) on arithmetic and rounding producers (`+`, `-`, `*`,
`/`, `sqrt`, `floor`, `ceil`, `trunc`). Prefix `-` negates F32 bitwise;
parenthesize negative arguments: `F32.abs (-2.0)`.

Functions take one argument at a time. Calls associate left: `f a b` means
`(f a) b`. Application binds tighter than infix operators. `f(x)` also calls a
function; `f(a, b)` passes one tuple. Unit thunks defer work until called with
`()`, without memoization. Recursion is supported.

Scalar numeric primitives are ordinary functions: `const multiply = @f32.mul`
and `const increment = @u32.add 1` work as aliases, partial applications and
callbacks. Captured scalar arguments copy their current value. The prelude uses
these aliases for terminal U32/F32 operations. Storage capacities and SIMD lane
selectors retain their literal-only rules.

Function bodies support both single-expression implicit return
(`func x => x + 1`) and indented block bodies (`func x =>` followed by an
indented suite ending with explicit `return x` or `return use call`). The
earlier explicit forms `func x => return x`, `func x => do:` with `return x`,
and `func x => return do:` with `break value` remain supported for existing
code. Every path through a block body must return; `break value` finishes a
`do:` block.

Separate curried parameters with `->`: `func first -> second => return body`
means `func first => return func second => return body`, and
`func (first: U32) -> (second: U32) : U32 => return body` places the result
annotation on the final stage. A call still uses `f first second`; `f first`
remains a partial application. The same rule applies to associated functions and
callbacks. Parameter names in this positional form are local names, not part of
the callable's public type. To run work **between** curried stages, write the
explicit nested lambdas; the short form introduces no such work or extra
allocation beyond the equivalent chain.

Write a result annotation with `:` before `=>`, for example
`func (x: U32) -> (y: U32): U32 => return x + y`. Type arrows keep their usual
meaning in a binding annotation: `const add: U32 -> U32 -> U32 = ...`.
Whitespace-separated function parameters and implicit function results are
rejected.

Module functions may also use a named declaration. Parameters, currying, result
annotations and explicit returns work like function values:

```blot
func add (left: U32) -> (right: U32): U32 => return @u32.add left right
const plus_two = add 2
io answer (): U32 => return plus_two 40
```

`private func` hides a module declaration from imports. Tags may decorate the
whole function, including `io` entry functions. Named module functions support forward
references and recursion. Function tags preserve every parameter type and any
written result type; wrappers may change inferred effects.
`const f = func ...` remains an ordinary function
value. The current implementation admits one declaration per name; overloads
and local named-function hoisting remain part of the
[language migration](NEXT_MIGRATION.md). Use `let f = func ...` for local closures.

Static associated functions use qualified names, for example
`func Vec2.add (left: Vec2) -> (right: Vec2): Vec2 => ...`.
Bare function names start with a lowercase letter or underscore.
A declaration's `where` follows its result type:
`func eq (left: a) -> (right: a): Bool where { Eq a } => return Eq.eq left right`.
Such declarations require written parameter and result types; ordinary function
values retain binding signatures and their existing predicate rules.

For many same-typed arguments, use a parameter record as a named-call
convention. The record type gives names a public interface, so renaming a field
requires updating callers. Field expressions run once in their written order,
even when that differs from the record type's order; unknown and duplicate
supplied fields receive diagnostics at the supplied field.

```blot
func rectangle (left: U32) -> (top: U32) -> (width: U32) -> (height: U32) => return
  @u32.add (@u32.add left top) (@u32.mul width height)
const placed = rectangle 2 3
func named_rectangle (args: { left: U32, top: U32, width: U32, height: U32 }) => return
  rectangle args.left args.top args.width args.height
io area () => return named_rectangle { height: 4, width: 5, top: 3, left: 2 }
```

A record parameter gives callers named fields in any order. Small scalar-record
helpers can be inlined without a record allocation in optimized builds; the
development tier may allocate a temporary record.

```blot
func twice value => return value + value
func apply_twice transform => return func value => return transform (transform value)
io factorial (value: U32) : U32 => return do:
  if value <= 1:
    break 1
  break value * factorial (value - 1)

io offset (value: F32): F32 => return value + 1.0
io answer (value: F32) : F32 => return apply_twice offset (twice value)
io let delayed = func () => return (func () => return factorial 5) ()
```

Function inputs and results start as fresh unknown types. Uses constrain them;
unconstrained types remain generic at generalization boundaries. Types are
inferred, including generic functions and callback effects. Type syntax:
`Array F32`, `Maybe U32`, `Result [U32, Bool]`, `(U32, Bool)`, `U32 -> F32`,
`U32 -> U32 ! {Foreign}`. Arrows associate right; parenthesize function argument
types. An annotation such as `(value: U32)` constrains the fresh argument type;
`a is U32` describes that idea but is not source syntax. Local `let` bindings
generalize only when bound to a syntactic `func` (the value restriction);
effectful `use` bindings and rebindings (`:=`) do not generalize.

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
[completion contract](../compiler/EDITOR_COMPLETION.md). Failed dispatch is
explained below.

```text
func unfinished (value: U32) : F32 => return @hole
// Unfilled expression; expected: F32; in scope: value: U32
```

`let name = expression` binds a pure value; `let name: Type = expression`
annotates it. `name := expression` shadows an existing local or parameter.
Inside its RHS, `self` and the old name refer to the previous binding. Earlier
closures keep old captures; aliases are not mutated. The new binding can have a
different type and is visible in the remaining suite. An outer `self` is
restored after the RHS. Rebinding requires purity, like `let`; record and array
paths such as `world.camera.position := self + offset` are supported. A path
through storage needs a unique root (see [Owned updates and copies](#owned-updates-and-copies)).

`break value` finishes the nearest `do` block with that value, even from inside
a loop. Bare `break` exits the nearest loop; `return value` exits the innermost
function. Falling through a `do` produces Unit; a last expression statement is
discarded. Branch-local bindings do not escape. Rebinding an existing outer name
flows out of `if`, `if let`, and the `do:` arms of a `case` used as a statement;
a branch or arm that leaves it alone carries its previous value. Outcomes that
reach the join must have the same type; a branch that exits, panics, or breaks
contributes nothing. A `break value` written directly in such an arm still exits
only the arm's `do:`: its value is discarded and the arm's rebindings carry out.
A `break value` nested in an `if` or loop inside an arm that rebinds an outer
name is rejected with `case_arm_return`. For a value, use
`if condition then value else alternative`.

A `return` cannot cross a monadic continuation: a resolver may skip or repeat
that continuation, so the compiler reports `return_across_continuation` at the
source. Use `break value` to finish the monadic block, then return from the
enclosing function. An effect clause can return from a request loop in the
function body's `do`; this cancels the captured computation. A request callback
inside a nested `do` has the same diagnostic. Its `break value` exits that inner
block.

When migrating older code, change a `return value` that supplied a `do` result
to `break value`, and change monadic `return $ wrapped` to `break $ wrapped`.
Keep `return value` where the intent is to leave the whole function, including
from a nested match arm. A bare `break` still leaves only the nearest loop.

```blot
io choose (flag: Bool) : U32 => return do:
  let inner = do:
    if flag:
      return 7
    break 3
  break inner + 1

io from_case (flag: Bool) : U32 => return do:
  case flag of
    true => do:
      return 42
    false => do:
      let ignored = ()
  break 0
```

```blot
type Beat is data = $Up | $Down
io count (up: Bool) : U32 => return do:
  let beat = if up then $Up else $Down
  let total = 0
  case beat of
    $Up => do:
      total := 7
    $Down => do:
      total := 3
  break total
```

```blot
type Builder is data = $Builder U32
func add_step amount => return func builder => return case builder of
  $Builder value => $Builder (value + amount)
func plugin builder => return do:
  builder := add_step 10 self
  builder := add_step 20 self
  break builder

const application = do:
  let builder = $Builder 0
  builder := plugin self
  builder := add_step 12 self
  break builder

io answer () => return case application of
  $Builder value => value
```

Plugins/builders are ordinary source functions/types. The compiler has no
built-in ECS, resources, schedules, graphics, or application lifecycle.

## Loops

The owned-storage backend currently supports direct self-recursion in closed
named functions with U32 and fixed `Array U32` parameters and a Unit result.
Existing initialized arrays may be read and updated; allocation, resizing,
freezing, global-owner access, indirect calls and mutual recursion inside the
recursive component remain unsupported. Allocate work arrays in the caller.

Prefer `for` for iteration; reserve recursion for recursive structures and
algorithms. `for index in start..end:` uses U32 bounds and excludes `end`.
Reversed/equal bounds run zero iterations. `for pattern in values:` iterates an
array with an irrefutable pattern. Bounds/the array evaluate once.
`for let value in values:` spells the binding explicitly. `for start..end:`
discards the range index. `for ever:` repeats without a bound; the body must
eventually suspend through a host callback, finish its enclosing `do` with
`break value`, or continue running.

An outer local rebound directly in the loop with `:=` carries its new value to
the next iteration and after the loop. Its type must stay the same across
iterations. New locals and the index remain inside the loop. Nested loops carry
successors through their enclosing loop. Rebindings inside `if`/`if let`
branches and statement `case` arms also carry outward. Any other nested `do:`,
such as a statement-level `do:` or an arm of a `case` whose value is used, keeps
its own scope: a `:=` of an outer local there that is never read inside that
block is rejected with `dead_rebinding`. Rebind with `if`/`else` or a statement
`case`, or assign the value of a `case` expression. `break value` exits the
enclosing `do`; a loop creates no new `do` boundary. Bare `break` exits the
nearest loop and carries its latest local values into the statements after it.
In a request loop it also cancels the captured computation. `continue` skips the
rest of the nearest loop's current iteration and carries the values visible at
that point into the next one. Range and collection loops still advance one
element; effects already performed stay performed, and temporary values from the
skipped path are cleaned up. A `continue` in a monadic loop produces its
resolver's `Continue` state. A request handler can use `continue` in a loop
inside that handler, but it cannot continue the enclosing request loop across
the handler callback boundary.

Use `let pattern = value else: continue` as a flat pattern guard. A successful
match binds names for the rest of the loop body; a failed match starts the next
iteration.

```blot
type Candidate is data = $Keep U32 | $Skip
io kept_total () => return do:
  let total = 0
  for candidate in #[$Skip, $Keep 2, $Keep 5]:
    let $Keep value = candidate else:
      continue
    if value > 3:
      continue
    total := self + value
  break total
```

```blot
io sum_to (end: U32) => return do:
  let total = 0
  for index in 0..end:
    total := self + index
  break total

io weighted () => return do:
  let total = 0
  for (value, weight) in #[(2, 3), (4, 5)]:
    total := self + value * weight
  break total

io first_five () => return do:
  let count = 0
  for 0..5:
    count := self + 1
  break count
```

## Data, records, tuples, patterns

Declare nominal algebraic types with `type ... is data`, including generic
parameters: `type Tree a is data = $Leaf a | $Branch (Tree a, Tree a)`.
Constructors have zero or one payload; use a tuple or named fields for several
values. Constructors themselves are values/functions. The prelude defines
`Maybe a = $Some a | $Nothing` and
`Result [value, error] = $Ok value | $Err error`.

Constructors use `$` in declarations, expressions and patterns:
`type Choice is data = $Some U32 | $None` and `$Some 42`. Booleans use plain
`true` and `false`, without a constructor marker. Keep `$` adjacent to the
constructor name. A spaced `f $ value` remains ordinary operator application.
Arrays keep their `#[...]` spelling.

A type or effect constructor takes at most one argument pattern. Use a list,
tuple, or record to bind several types. These shapes can nest; record arguments
match by field name. Record constructor declarations also support field
shorthand.

```blot
type Entry { head, tail } is data = $Entry { head, tail }
type Pair [left, right] is data = $Pair (left, right)
type Curried left => type right is data = $Curried (left, right)
func first (entry: Entry { head: U32, tail: a }) : U32 => return do:
  let $Entry { head } = entry
  break head
func number (pair: (Curried U32) Bool) => return do:
  let $Curried (value, flag) = pair
  break value
io answer () => return first ($Entry { head: 42, tail: true })
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
`type Box f is data = $Box f`, or use an alias with a closed row.

```blot
type Coordinate = F32
type Pair a = (a, a)
type Position = Pair Coordinate
const origin: Position = (0.0, 0.0)
io horizontal () => return @product.get origin 0
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
declarations retain their `$Constructor { ... }` forms. Field order does not
affect structural type equality or the executable layout.

Supply each field once; shorthand `{ x, y }` uses locals. Field expressions
execute once in written order. An ordinary call can pass a record directly:
`function { x: 1, y: 2 }`. Destructure a known record shape with `{ x, y }`;
fields can be reordered or omitted. An unannotated parameter's shape must be
known before destructuring; generic `record.x` access instead infers a field
requirement. A named record declaration is unnecessary: the body can infer the
requirement and each concrete call must satisfy it. Callback effects remain part
of the check. Read a field with `value.field`; `value.field := expression`
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
  func left => return func right => return @record.merge left right
const original = { x: 40, enabled: false }
const updated = extend original { enabled: true, extra: 2 }
io answer () => return @u32.add updated.x updated.extra
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
type Vec2 is data = $Vec2 { x: F32, y: F32 }
io const selected = 7
func length position => return do:
  let $Vec2 { x, y } = position
  break F32.sqrt (x * x + y * y)
func unpack candidate => return do:
  let $Some value = candidate else:
    break 0
  break value

io distance () => return length ($Vec2 { y: 4.0, x: 3.0 })
io classify (key: U32) => return case key, true of
  ^selected, true => unpack ($Some 42)
  _, _ => 0
io conditional () => return do:
  if let $Some (number, true) = $Some (42, true):
    break number
  break 0
```

## Operators and compile-time associated dispatch

Precedence and associativity are determined lexically by each operator's spelling (no `infix` declarations are needed):

- `$` (0, right) — application syntax (`f $ g x` means `f (g x)`), built into the language and available without the prelude
- `|>`… (5, left), `<|`… (5, right) — pipes
- `$`… (10, right) — multi-character `$`-prefixed operators (`$>`, `$$`)
- `or` (20, right), `and` (25, right) — short-circuit boolean words, built into the language
- `==`, `!=`, `<`, `<=`, `>`, `>=` (30, non-associative) — comparisons; other `=`, `!`, `<`, `>`-prefixed operators (`<>`, `<+>`, `<*>`, `===`, `==>`) (30, left)
- `|`… (40, left), `^`… (45, left), `&`… (50, left), shifts `<<`, `>>`, `<<<`, `>>>` (55, left)
- `+`, `-`, `~`, `?`-prefixed (60, left) — e.g. `+`, `-`, `++`, `~>`, `??`
- `*`, `/`, `%`-prefixed (70, left) — e.g. `*`, `/`, `%`, `/=`
- `**`… (75, right) — exponentiation and power-like operators

Custom and standard symbolic operators are ordinary functions or bindings named in parentheses:

```blot
func (++) (a: Text) -> (b: Text): Text => a.concat b
const (><) = func left -> right => left * 10 + right
import { (++) } from "./ops"
let sum = fold (+) 0 xs
```

Parenthesized operator names work in `func`, `const`, `let`, `import`/`export`, first-class value references (`(+)`), and module-qualified lookups (`ops.(++)`).

The standard operators (`+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `<<`, `>>`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `|>`, `<|`) are ordinary Blot definitions in `std/prelude.blot`, implemented with `@type.call` and `@pipe`. For example, `func (+) left -> right => @type.call "add" left right` and `func (|>) value -> function => @pipe value function`. User-defined operators written the same way get the same compile-time associated/trait dispatch and zero-overhead lowering.

With `@type.call "member" left right`, the left operand's type supplies `member` (either via a trait implementation or an associated function in the type's defining module); its signature determines which right operand it accepts. Use an explicit qualified call for other operand orders. A compatible left implementation wins even if its result conflicts with an annotation. `@type.call` accepts any literal member name.

Receiver syntax selects a member from the receiver's type:
`tail.contains(witness)` means the type's `contains` function applied to `tail`,
then `witness`. `tail.contains` is a bound function; `values.length` is
`Array.length values`. This lookup never falls back to an argument's type. A
lexical receiver shadows a same-named module namespace. Ordinary qualified names
such as `Array.get` and `geometry.Point.add` still work.

When dispatch fails, the diagnostic explains it. The client returns
`diagnostic.explanation` (CLI JSON: `details.explanation`): the operator, the
member looked up, and each candidate in the order dispatch considered it. A
candidate has a `side` (`left`, `builtin`, `destination` for
`@type.result`, or `receiver`), the type's spelling and an `outcome`:
`unknown_operand`, `no_member`, `incompatible` (the member rejects these
operands), `unsupported_scalar`, or `result_mismatch` (selected, but its result
conflicts with the expected type, so no later candidate was tried). Explanations hold at most four candidates
and 256 bytes per spelling; `truncated` marks cut detail. For an operator
failure, `explanation.contexts` gives up to two source operand locations, even
when dispatch is checked inside an imported generic function. For a direct type
or effect mismatch at a call, `diagnostic.contexts` gives the callee and
argument locations. These spans use UTF-8 byte offsets, like the primary
diagnostic.

```text
io answer () => return 1 + 2.5
// missing_associated; `+` (add): left U32 incompatible
```

Named constructor fields support `point.x`. A field must exist on every
constructor of its type; use a pattern when a field is variant-specific. A field
and associated function with the same name produce an ambiguity error.
`point.x := self + 1` constructs a successor and rebinds the local `point`.
Paths can mix fields and indices: `grid.rows[row][column] := self + 1`. The root
and each index are evaluated once, left to right, before the replacement; `self`
is the old value at the selected leaf. Existing aliases keep the old root. As
with plain `:=`, the replacement must be pure; use `use` first for effects. A
path that reaches an array updates that storage in place, so its root must be
unique (see [Owned updates and copies](#owned-updates-and-copies)).

Nested path updates rebuild records cleanly while preserving existing aliases
and even changing a field's type:

```blot
func set_position_x (replacement: F32) -> (source: { position: { x: U32, y: U32 }, health: U32 }) =>
  let updated = source
  updated.position.x := replacement
  return updated

io answer (): F32 =>
  let original = { position: { x: 40, y: 7 }, health: 2 }
  let changed = set_position_x 2.5 original
  return @f32.add changed.position.x (@u32.to_f32 original.health)
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
division truncates and a zero divisor fails/traps. Bool supports ordinary
equality. Structural equality for arrays, records and algebraic data is opt-in
through [std/equality](../../std/equality.blot) and the
[derivation tool](../host/derive.md), which can also generate debug formatting
and explicitly versioned codecs from checked declarations.

```blot
type Count is data = $Count U32
type Other is data = $Other U32
io const same_value = 1 == 2
io const same_type = $Type 1 == $Type 2
io const same_nominal = $Type $Count == $Type ($Count 42)
io const different = $Type $Count != $Type $Other
io compare () => return do:
  let head = $Type $Count
  let witness = $Type ($Count 0)
  break head == witness
```

```blot
type Box a is data = $Box a
const Box.add = func left => return func right => return case left, right of
  $Box a, $Box b => $Box (a + b)
func twice value => return value + value
io answer (value: F32) => return case twice ($Box value) of
  $Box result => result
```

## Arrays and libraries

Arrays are the single homogeneous collection type. `#[]`, `#[1, 2]`, and
`#[#[1], #[2]]` construct owned `#[T]` (`Array T`) values. Fixed-length arrays
use `#[N; T]` (or `#[n; T]` to tie equal lengths across parameters), read-only
borrowed slices use `&[T]` (`View T`), and frozen shared handles use `*T` (via
`freeze value`).

Arrays have contiguous checked row storage. An owned `#[T]` supports in-place
element updates (`values[index] := replacement`), growth and truncation
(`@storage.push`, `@storage.pop`, `@storage.truncate`), and explicit copies
(`values.copy`). Reads of inline scalar/record rows copy their values; owner
and borrowed descriptors retain aliases. Copy payloads explicitly
(`values.copy`) when retaining an independent version. Exact layout and
lifetime support is in [the owned-storage profile](../compiler/SCOPED_STORAGE.md)
and [docs/language/spec.md](spec.md).

Arrays and views share ordinary prelude members `values.length` and
`values.is_empty`. Owned arrays support `values[index]`, `values[index] :=
replacement` on a unique root, `values.copy`, `get`, and `set`. Lengths and
indices use `U32`. Indexing binds more tightly than application:
`f values[index]` passes the element to `f`. Separate an array argument with a
space (`f #[1]`), or write `f(#[1])`.

Spreads append or prepend elements into a fresh array while preserving written
evaluation order:

```blot
func prepend (value: U32) -> (values: #[U32]): #[U32] => return #[value, ...values]
func append (value: U32) -> (values: #[U32]): #[U32] => return #[...values, value]
func surrounded (values: #[U32]): #[U32] => return #[0, ...values, 99]
```

One spread is allowed, with any number of prefix and suffix elements.

Comprehensions construct owned arrays with `#[...]`:

```blot
const squares: #[U32] = #[x * x | x <- #[1, 2, 3]]
const pairs: #[U32] = #[x * 10 + y | x <- #[1, 2], y <- #[3, 4]]
const selected: #[U32] = #[square | x <- #[1, 2, 3], x > 1, let square = x * x]
```

Generators run from left to right, with the leftmost as the outer loop. Later
sources can use earlier bindings. A Bool guard skips every subsequent qualifier
and the result expression when false. Bindings stay inside the comprehension;
each generator source sees the scope before its own binding. The owned backend
constructs results in a checked destination while preserving iteration and
element evaluation order. Do not depend on a particular temporary builder or
implicit snapshots of mutable input owners.

`for` and comprehension generators also accept user-defined iterables. The
ordinary associated `iter` function creates a cursor once; its `next` function
returns `$Some (value, next_cursor)` or `$Nothing`. These are the usual prelude
Maybe constructors. Iterator types and adapters receive no name-specific
optimization.

```blot
type Countdown is data = $Countdown U32
const Countdown.iter = func (cursor: Countdown) => return cursor
const Countdown.next = func (cursor: Countdown) => return do:
  let $Countdown remaining = cursor
  break if remaining == 0 then $Nothing
    else $Some (remaining, $Countdown (remaining - 1))

io sum count => return do:
  let total = 0
  for value in $Countdown count:
    total := self + value
  break total
```

Both operations may have effects. Each pull happens before the corresponding
body, and `break` or `return` stops further pulls. Array loops and numeric
ranges keep their direct traversal paths.

A cursor keeps its own traversal position; copying a cursor does not advance the
original. In the owned profile an Array cursor reads the same owner rather than
preserving an independent payload snapshot. Borrow and mutation checks still
apply. Copy the input first when traversal needs an earlier version.

`std/array` provides structural and higher-order array operations with the
collection last for pipelines:

```blot
import * as array from "std/array"

io answer (): U32 =>
  let joined = array.concat #[1, 2, 3] #[4, 5]
  let middle = array.slice 1 3 joined       // #[2, 3, 4]
  let doubled = array.map (func value => value * 2) (array.filter (func value => value > 2) middle)
  return array.fold_left U32.add 0 doubled  // (3 + 4) * 2 = 14
```

`array.concat` and `array.slice start count` copy selected elements into
independent storage.

Direct array reads and updates check bounds at runtime and fail during constant
evaluation for an invalid index. `values.get(index)` returns `$Some value` or
`$Nothing`; `values.set(index)(replacement)` returns `$Some updated_array` or
`$Nothing`. These are ordinary functions, including their bounds checks. A guard
such as `if index < values.length:` is also useful. Direct accesses keep their
bounds checks inside guards; no proof token is required.

`@array.length`, `@array.get`, and `@array.set` are the underlying array
primitives. `@array.fill count value` evaluates the fill value once;
`@array.generate count generator` calls a pure `U32 -> T` generator in ascending
index order. Empty array literals `#[]` can need an explicit `#[T]` (`Array T`)
annotation.

`array.flatten ranges payload` copies selected ranges from one readable payload
into an independent destination. Each range has `start` and `count` fields;
bounds and total length are checked before copying.
`array.flatten_read read
length ranges` accepts a pure indexed reader over the
same range representation. This avoids retaining an array of borrowed child
collections.

```blot
import * as array from "std/array"
io answer () => return do:
  let payload = #[10, 20, 30, 40]
  let ranges = #[{ start: 1, count: 2 }, { start: 0, count: 1 }]
  let copied = array.flatten ranges payload
  break copied[0] + copied[1] + copied[2]
```

### Owned updates and copies

Arrays are owned values backed by storage, while records, tuples, sums, and
scalars are plain values. `:=` is the only update statement:

- `name := value` and `name.path := value` build a successor and rebind the
  local; prior snapshots keep the old value. A path that reaches an array is
  written in place, which is the successor only when nothing else can observe
  the old root. The compiler proves uniqueness inside the function and rejects
  aliased updates with `aliased_update`: take `values.copy` first to keep the
  old value, or end earlier borrows before updating.

A root is unique after it is bound to an array literal, a comprehension,
`values.copy`, or a fresh `@array` result (`fill`, `generate`, `set`, `concat`,
`slice`, `flatten`), and it stays unique across its own `:=` updates. A record
local is unique along a path when every array the path passes through is. The
root stops being unique, for the rest of the path that follows, once the same
version is bound to another name or a pattern, captured, passed to a call or
constructor, placed in a literal or record, returned or broken out, or read out
as an array-holding element or field (`let row = grid[r]`). Reading a plain
element or the length does not alias it.

A value moves at its local's last read. When the local is named for the last
time and that read binds it to another name, puts it in a record, an array or
a constructor, stores it with `:=`, or returns or breaks with it, the new
holder is unique if the local was: `let cells = #[0, 0]` followed by
`let grid = $Grid { cells: cells, width: 2 }` leaves `grid.cells` unique when
`cells` is not read again. A read is the last one when nothing on any path
after it reads the local: not a later statement, a closure made later, or a
loop that carries it. Inside a loop only a local bound in the same iteration
moves. Parameters are borrowed unless marked `own`, and constants are never
unique; what crosses a call is described under "Ownership across calls" below.
Branches keep uniqueness only when every arm that continues keeps it; an arm
that returns contributes nothing. A loop carry is unique when its first value
and every value it carries back are.

```blot
func set_second (items: own #[U32]) -> (value: U32): #[U32] =>
  items[1] := value
  return items

io successors () => return do:
  let rows = #[1, 2, 3]
  let before = rows.copy
  let updated = set_second rows 20
  break before[1] + updated[1]
```

`successors` returns 22: `before` is a copy and keeps the old element, while
`set_second` takes ownership of `rows` and updates it in place. Without
`.copy`, `let before = rows` would make `rows[1] := 20` an `aliased_update`
(and passing `rows` to an `own` parameter an `own_argument`). Under the value
restriction, only a `let` bound to a syntactic `func` generalizes, so every
non-`func` local (including any storage-holding local) keeps one type and its
updates and reads always agree.

### Ownership across calls

A function's result belongs to its caller alone, and a call only borrows
its arguments. So a local stays unique after it is passed to a function,
and what a function returns can be updated in place with `:=`:

```blot
func scaled (rows: Array U32) -> (k: U32): Array U32 => return #[x * k | x <- rows]

io run (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  let more = scaled rows n
  more[0] := 9
  rows[1] := 5
  break more[0] + rows[1]
```

For that to hold, each `return` must give a value nothing else holds: a
fresh value, or a local that alone holds its value. A parameter, a field of
one, an element read out of an array of arrays, a module constant, or a
record that puts one array in two fields is `result_not_owned`. Return
`values.copy` of it, or take the parameter over with `own` (below). A
literal is a fresh value each time; a module constant is one shared array.

Two kinds of function are not held to this, and their results are not
taken to be unique either:

- an `io` entry function, whose result goes to the host, which copies it;
- a contract's member, which passes on what the chosen implementation
  returns. Implementations are held to it.

A result whose type owns no array is not checked: a number, a view, a
function, a type variable. Every owned array `#[T]` (`Array T`) follows these
rules: a function returning one returns its own, and an `own` parameter takes
an array nothing else holds.

**Names that borrow.** Binding a name to something a local still holds
shares it only while the name is in use:

```blot
let response = access.response     // access is shared from here
program.append response outgoing   // the last read of response
access := step access              // access is its holder's own again
```

That holds when the name's value went nowhere else (it was not bound to
another name, captured, stored or returned) and nothing else came to hold
the local meanwhile. A name rebound with `:=` does not give back. The
name gives back when the statement that read it last is done, or already
when the call that read it last has returned, so `return (count frame,
access)` hands back an `access` that `frame` borrowed from. A name that
nothing reads borrows nothing. Several names may borrow from one local at
once, the whole of it or a field each.

A borrowed value needs no name. The result of a call that borrows its
arguments is given back as soon as what is written around it is done with
it, when that keeps nothing:

```blot
let stored = salt.stored (salt.read_state access)       // an argument of a call
let site = (buildings.read_state access).sites[0].plot  // a plain value read out of it
for stack in stacks_of access:                          // what a loop walks,
  total := total + stack.count                          // given back after the loop
access := step access
```

A slice (`&rows[a..b]`) borrows its owner's elements for reading.
Assigning through its index is a type error, including through a slice
stored in a record or passed to a generic writer. After the last read, the
owner can be updated with `rows[i] := next`.

It is kept, as before, where it is put into a record, a tuple or an
array, given to a function value, or where a loop carries an element that
holds storage out of the loop.

**Taking a value apart.** `let {first, second} = parts ()`, `let (a, b) =
pair ()` and `let ($Box inside) = box` give each name a value of its own
when the value taken apart was nothing else's: a fresh value, or a local
at its last read.

**Generic functions that return what they were lent.** `Array.at`,
`identity` and `Maybe.unwrap_or` return a value of a variable type that came
in through a parameter. Called where that type is an array, the result
shares with the argument, as `grid[0]` shares with `grid`: reading is fine,
and an in-place `:=` on either side is `aliased_update` until one is
copied. The same holds for a generic function that puts its argument into
growable storage it was given (`bag.push rows`).

```blot
let grid = #[#[1, 2], #[3, 4]]
let row = grid.at 0          // shares with grid
let mine = (grid.at 0).copy  // an array of its own; grid stays unique
```

Such a function cannot be used as a value, or applied partly, where the
variable is an array (`lent_result_value`): pass a function that copies.

**Dynamic arrays and kept values.** Values pushed into an array the function
does not own, written via `@simd.store`, or passed to an effect operation
(whose handler may keep them) must hold no borrowed arrays: passing a borrowed
parameter or part of one is `kept_value`; pass `values.copy` instead. An owned
`#[T]` supports in-place `@storage.push` (which returns the updated `#[T]`,
wrapped in the prelude as `items := self.push value`), `@storage.pop`, and
`@storage.truncate` directly. To preserve a snapshot before handing a value to
a helper with an `own` parameter, copy it with `.copy`.

**Closures passed to a call.** A closure holds what it captured, so a
captured local is shared while the closure lives. A closure written as an
argument lives only as long as the call, when the call's result has no
part that borrows: nothing a function does can keep a function it was
lent (storing or pushing one is `kept_value`). So afterwards the local is
unique again:

```blot
func collect_lengths (rows: #[#[U32]]): *#[U32] =>
  let seen: #[U32] = #[]
  for row in rows:
    seen := self.push row.length
  return freeze seen   // read-only shared handle *#[U32]
```

A closure bound to a name first, or passed to a call whose result is a
function or a view, keeps what it captured shared.

**Function values.** A call through a function value (a parameter, a
field, a local) is like any other call: the arguments are lent and the
result is the caller's. So everything that can be a function value obeys
the result rule, closures included, wherever they are written. A
constructor, a primitive or an effect operation keeps its argument, so it
cannot stand for a function value where that owns an array
(`lent_result_value`); write `func value => return $Some value.copy`. Where
the result type has a part that borrows (a view, a reference, a function),
a call through a function value shares its arguments and its result is
not unique.

### `own` parameters

A function or a lambda can take a parameter over by writing `own` before
its type. Inside the function the parameter is unique, so `:=`
through it writes in place, and it can be returned.

```blot
type World is data = $World { counts: Array U32, size: U32 }

func World.damage (world: own World) -> (index: U32): World => return do:
  world.counts[index] := world.counts[index] + 1
  break world

io run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0, 0], size: 3 }
  for i in 0..n:
    world := world.damage 2
  world.counts[0] := world.size
  break world.counts[0] * 10 + world.counts[2]
```

No array is copied in `run`. The rules:

- The argument must be a value nothing else holds: a fresh value, or a
  whole local that is unique all the way down (every array in it, and
  every array in those). Anything else is `own_argument`; pass
  `values.copy` of it instead.
- The local is spent by the call. Reading it again is `spent_value`;
  rebind it to the result (`world := world.damage 2`) or use the result
  under a new name.
- In `place := f … self`, `self` is the old value of the place, which the
  update replaces, so it can be given away: `world.counts := filled self 0`
  hands the field to `filled` and puts the result back.
- Inside a loop, only a local bound in the same iteration can be given
  away, because the next iteration would give it away again. A local the
  loop rebinds each time, as `world` above, is one.

**In a function's type.** `own` is part of the type: `own World -> U32 ->
World` is a function that takes its first argument over. So an `own`
function is a value like any other, and a parameter, a record field or a
local can hold one:

```blot
type Hooks is data = $Hooks { step: own World -> U32 -> World }

func run (hooks: Hooks) -> (world: own World): World => return do:
  for index in 0..world.size:
    world := hooks.step world index
  break world
```

A parameter can be taken over without naming its type: `func step (own
world) -> (dt: F32) => …`.

A call can say that it gives an argument away: `world := step (own world)
dt`, or without the parentheses `step own world dt`. Where the function's
type is known it changes nothing. Where it is not (a function that came
in as an untyped parameter, or as a field of one) it is what tells the
compiler that the function takes the argument over:

```blot
func twice step -> (own state) => return do:
  state := step (own state) 1
  state := step (own state) 2
  break state
```

A field of a local can be given as well, when the local alone holds its
value. The field is spent until something is put back in it, usually by
the same statement; the other fields stay usable meanwhile, and the local
cannot be read as a whole:

```blot
world.robots := ecs.insert world.entities world.robots index robot
```

The other arguments of such a call are lent as in any call and are their
holder's own again after it. One call cannot be both lent a value and
given it: `mixed world.robots world.robots` is `own_argument`. A value is
given when the call happens, so another argument may read it first when
what it computes keeps nothing of it: `world := step world (count world)`.

A view borrows the field it is made of, so one field can be lent as a view
while another is given in the same call:

```blot
world.out := write (&world.rows[0..world.rows.length]) world.out
```

An arm of a `case` or an `if` that just names a local at its last read
hands that value on, so a world can be rebound from arms that change it
and arms that do not:

```blot
world := case kind of
  0 => damage world 0
  _ => world
```

A field also leaves with the function. `return stream.output` hands the
caller that field of a local of the function's own, and a returned record,
constructor or tuple may be made of such fields. Each can leave once:

```blot
func bind (parts: own Parts): World => return $World { rows: parts.rows, marks: parts.marks }
func split (world: own World) => return (world.rows, world.marks)
```

A function written against any record with certain fields can index and
update through them without saying what kind of array each is; the element
type comes from the record it is called with:

```blot
func count (own access) => return do:
  access.log[0] := access.log[0] + 1
  @storage.push access.log 7
  break access
```

A value whose type is not known inside a function (a parameter written
without a type, or a field of one) is read there as plain data, but it is
given to an `own` parameter only when the function took it over itself
and no name still borrows one of its fields:
`func stepped access => return step access` is `own_argument`, and `func
stepped (own access) => return step access` is not. A function held in a
field of such a value is called like any function value: the call only
borrows its arguments. What it returns is not known either, so a name
bound to it borrows the arguments unless its type is written (`let
context: EventContext = stages.route access event`). A call that stands
as a statement gives back what it was lent when the statement ends.

Because `own` before a name marks what follows it, `own` itself names
nothing: a local, a parameter or a constant called `own` is
`own_parameter`.

A lambda takes a parameter over when it says so, `func (world: own World)
=> …`, or when it is written where such a function is expected:
`run_with (func world -> index => …)`. In a parameter's annotation `own`
goes with the type that follows it, so `(step: own World -> World)` is a
parameter that holds such a function, and `(world: own World)` is a
parameter taken over. A function type and its `own` do not match a type
without it, and no type variable stands for `own T`: a generic function
cannot be handed an `own` function to call on a value it only borrowed.

A call that gives a parameter that is taken over must give every argument
of the function's type at once. Given only some, the function would hold
the value for any number of calls (`own_function_value`); so does
`value.member` without its arguments.

What is not built yet:

- `own` on a contract member, an implementation member or a member an
  operator stands for (`World.add` for `+`) is `own_parameter`. So is
  `own` in a type anywhere but a function type's parameter.
- A function that takes a parameter over cannot return a function to be
  called later: its type's arguments are all given in the one call.


### Named owners and explicit copies

Declare independent owners and keep their payloads alive through every borrowed
use. Assigning an owner to another binding, placing it in an access record or
capturing it in a known callback preserves its identity. Stores write through
those aliases. Inline records and scalar values copy by value.

`values.copy` (in std, `@storage.copy values`) creates independent array
storage. Use it for retained history and previous-state data; copy separately
referenced payloads as needed.
A view records a borrowed range and length, not a snapshot of its contents.
`freeze value` produces a read-only shared `*T` handle without copying the
payload. Functions can return fresh owners directly; their checked lifetime
transfers to the caller. Return an owner together with any borrowed fields that
need it. A bare borrow cannot outlive its owner. Do not store borrowed rows in
older storage or carry a fresh owner through a loop.

The planner checks fixed rows, owner capacities and lexical reuse. Capacity
exhaustion traps; it does not trigger collection or implicit growth beyond the
plan. Configured temporary, persistent and transport budgets remain distinct
from the standard Wasm memory declaration, which includes reserved regions. Zero
runtime growth is not a claim that total linear memory fits the temporary budget
alone.

Runtime allocation/collector measurements from the retired backend are
historical evidence, not cost guarantees for this profile. Preserve their exact
source/binary identities in Git history. Qualify the current backend through
executed ownership, bounds and numerical laws, then measure fresh release
artifacts separately. See [storage requirements](../compiler/SCOPED_STORAGE.md)
and [qualification](../../tasks/121-qualify-and-measure-owned-applications.md).

Import `std/array` for `generate`, `fill`, `length`, `is_empty`,
`at index values`, `replace index value values`, `get index values`,
`set index value values`, `fold_left reduce initial values`, `any`, and `all`.
`get`/`set` return Maybe on bounds failure; folds propagate callback effects;
`any`/`all` stop early.

```blot
import * as array from "std/array"

const squares = array.generate 4 (func index => return index * index)
io total () => return array.fold_left U32.add 0 squares
io snapshot () => return do:
  let values = #[1, 2]
  let original = values.copy
  values[0] := self + 40
  break original[0] + values[0]
func checked index => return squares.get(index)
```

The implicit prelude supplies `identity`, `apply`, `always`, `compose`, `flip`,
`on`, `Bool.not`; `Maybe.map/bind/unwrap_or/is_some/to_result`;
`Result.map/map_error/bind/unwrap_or/to_maybe`; numeric arithmetic/comparisons;
`U32.to_f32`, `F32.to_u32`; `F32.abs/sqrt/floor/ceil/trunc/min/max`,
`clamp low high value`, `lerp left right weight`, `is_finite`, `sin/cos/tan`,
`wrap period value`, and `lerp_angle left right weight`.

Ordinary arguments are eager, including `Maybe.unwrap_or` fallbacks. `and` and
`or` are reserved primitive operators: both operands must be `Bool`, and the
right operand runs only when needed. They cannot be rebound or given a fixity.
`Maybe.unwrap_or_else fallback candidate` and
`Result.unwrap_or_else fallback candidate` also defer their fallbacks. Local
`let` initializers are eager too. The compiler may place single-use, total
scalar work at its only use when this preserves observable behavior; trapping,
effectful and unknown work stays in source order. A value consumed directly by
the next `if` or `return` can avoid a temporary without changing that order. Use
a demand parameter or unit thunk when delayed evaluation is part of the
program's intended behavior.

`std/array` also supplies `map`, `filter`, `filter_map`, `slice start count`,
`concat`, `flatten`, `push`, `zip`, `unzip`, and `unzip3`. Collection arguments
come last for pipelines. Construction callbacks are pure; use `fold_left` or a
loop to sequence effects. Import `Vec2` and `Vec3` from `std/vector` for vector
operators and receiver members such as `dot`, `length`, and `normalized`.

```blot
import * as array from "std/array"
import { Vec2 } from "std/vector"

io total_length () => return
  #[$Vec2 { x: 3.0, y: 4.0 }, $Vec2 { x: 0.0, y: 0.0 }]
  |> array.map .length
  |> array.fold_left .add 0.0
```

## Runtime text

`Text` is an alias for `Array U32` containing Unicode scalar values. A string
literal such as `"Hi, 世界🙂"` is an ordinary `Text` value. Text length,
indexing and `std/array.slice` count scalars, rather than UTF-8 bytes or
grapheme clusters; the example has seven elements. Equality in `std/text`
compares scalar sequences exactly and does not perform Unicode normalization.
Text has no implicit IO.

```blot
import * as text from "std/text"

io greeting () => return text.join " " #["Hello,", "世界🙂"]
io label (count: U32) => return
  text.join "" #["count=", text.format count]
```

`text.from_scalars` validates an external `Array U32`, returning `Maybe Text`;
it rejects surrogate values and values above U+10FFFF. Since `Text` is a type
alias, code can also construct an array without validation. Validate values at
the host boundary: `encodeText` and `decodeText` from `mod.ts` convert between
JavaScript strings and the existing `Array U32` guest ABI, rejecting unpaired
UTF-16 surrogates and invalid scalar values. No numeric ABI change is needed.
`@panic` still requires a literal; send a dynamic assertion message through an
explicit `Array U32 -> U32 ! {Foreign}` host callback or return the `Text` to
the host.

`text.parse_u32 value` accepts a nonempty sequence of ASCII decimal digits
in a Text or borrowed text slice, returning `$Some number` (leading zeroes
are allowed) or `$Nothing` for any other character, an empty sequence or U32
overflow. It does not trim whitespace or accept signs.
`text.is_whitespace` recognizes the Unicode White_Space property.
`text.split_whitespace source` lazily yields borrowed, nonempty words separated
by those characters. `text.lines source` yields borrowed lines separated by
LF, removing CR immediately before LF. Interior empty lines are preserved;
an empty source has no lines and a terminal LF does not add another line.
Keep the source alive while using either iterator or any returned slice.
For example, the following sums decimal tokens (rejecting malformed words):

```blot
import * as text from "std/text"
io total (source: Text): U32 => do:
  let sum = 0
  for word in text.split_whitespace source:
    let $Some number = text.parse_u32 word else:
      @panic "expected U32"
    sum := self + number
  return sum
```

`text.from_u32` formats a decimal integer. `text.from_f32` formats finite `F32`
values with exact IEEE-754 bit-pattern round-trip precision (emitting decimal
digits or hex bit patterns for out-of-range magnitudes).
`text.from_f32_fixed places value` formats 0–6 fractional places rounded half
away from zero and returns `$Nothing` for non-finite values or when the scaled
result does not fit `U32`. `text.Format` is an ordinary trait: applications can
provide `Format` implementations for their own types. Each `text.concat` copies
both inputs, so repeatedly appending to a growing `Text` can take quadratic
time. Build with `text.builder`, `text.push` or `text.append`, and `text.finish`
to collect scalars in an owned `#[U32]` builder and return the final `Text`
with zero copy. `text.join` uses this path.

## SIMD

`std/simd` exposes `U32x4` and `F32x4` as ordinary four-element product aliases.
Construct or destructure lanes with tuples and use ordinary partial application
on the source functions:

```blot
import * as simd from "std/simd"
func translated lanes => return simd.u32_add lanes (1, 2, 3, 4)
func scaled lanes => return simd.f32_mul lanes (2.0, 2.0, 2.0, 2.0)
```

Every operation with a scalar counterpart gives the bits of that scalar kernel
in each lane, including canonical positive quiet NaN (`0x7fc00000`) on F32
arithmetic/rounding producers, signed zero and wrapping. Collection arguments
and lane operands come last, so `lanes |> simd.u32_shl 13` pipelines.

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
- `load index values` reads four consecutive U32, F32 or Bool elements from
  an owned `#[T]` (`Array T`) or read-only slice (`&[T]`). Indices start at the
  beginning of the supplied collection. All four lanes must fit inside that
  collection, including when a slice ends before its underlying array.
- `store index lanes values` replaces four elements of an owned array. The
  range check precedes index arithmetic for both operations.

Explicit compiler operations use `@simd.u32x4.*` and `@simd.f32x4.*`
with their full argument lists. `@simd.load values index` and
`@simd.store values index lanes` take the collection first.

The owned backend lowers supported closed four-lane values and operations
without changing lane order, bit reinterpretation or rounding contracts. Exact
support for calls, stored aggregates and callbacks follows its checked layout
rules; source spelling alone does not guarantee allocation-free execution.

Optimizations preserve F32 expression order and U32 wrapping. No reduction may
be silently regrouped: `f32_sum` adds left to right, while `f32_sum_pairwise`
explicitly chooses `(a + b) + (c + d)` and can round differently. Earlier
backend-specific automatic-vectorization admission and private-value optimizer
measurements remain in
[the historical guide](https://github.com/mewhhaha/blot2/blob/4b594a129df6683c900021f355dd771a3de4a311/compiler/guide.md#simd).
They are not cost or representation guarantees for the owned-storage profile.

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
func read_twice () => return do:
  use first <- Reader.ask U32 ()
  use second <- Reader.ask U32 ()
  break first + second

const reader = @effect.provider (Reader.ask U32) (func () => return 21)
io mocked () => return do reader:
  use answer <- read_twice ()
  break answer

io main (read: Unit -> U32 ! {Foreign}) => return do (@effect.provider (Reader.ask U32) read):
  use answer <- read_twice ()
  break answer

io const uses_host = @effect.has (@effect.of main) Foreign
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

func checked computation => return do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if value == 0:
          break 0
        yield value
      complete value =>
        break value

io answer () => return checked (@computation (func () => return do:
  use first <- Validate.check 40
  use second <- Validate.check 2
  break first + second
))
```

Indent each clause suite after `=>`. `yield value` supplies the operation result
and ends the clause. `break value` cancels the computation and exits the nearest
enclosing `do`. Bare `break` cancels the computation, exits the request loop,
and runs the following statements. `return value` exits the handler function. A
`complete` clause receives the thunk's final result and must exit; it cannot
yield. Every operation clause must reply or exit on each path. There are no
prelude constructors to import.

Outer locals rebound with `:=` carry handler state between requests and after
`break`. A captured computation can run again with fresh handler state. Calls
through helpers use the same handler; unrelated effects remain visible. Clause
bodies run outside the request installation, allowing forwarding to an outer
handler or provider. Generic operation clauses name a closed instance with parentheses, as in
`effect (Reader.ask U32) () =>`. This interface supports one reply per request,
without an exposed continuation value. For new code, prefer composable
`handler` bindings with `.handle ... .run` / `@handle` / `layer` (see [spec.md](spec.md)).

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

func increment () => return do:
  use count <- State.get U32 ()
  use State.set U32 (count + 1)
  break count

io counted () => return do:
  let (next, previous) = do (@effect.state (State.get U32) (State.set U32) 41):
    break increment ()
  break next + previous

const fixed = @effect.provider (Get U32) (func () => return 7)
io read_fixed () => return do fixed:
  break Get U32 ()
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
type Counter is data = $Counter U32

func get (witness: p -> a) : a => return State.get ()
func set value => return State.set value

func increment () => return do:
  use counter <- get $Counter
  let $Counter value = counter
  break set ($Counter (value + 1))

io answer () => return do:
  let ($Counter next, _) = @effect.run State.get State.set ($Counter 41) increment
  break next
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

[Scoped effect identities](../compiler/SCOPED_EFFECTS.md) specifies the checked
representation: symbolic family arguments, distinct same-typed capabilities and
checked scope/capture lifetimes. The direct annotated-family subset accepts
`@effect.scope (func (state: State U32) => return body)`, with member operations
such as `state.get ()`. Each entry creates fresh authority. Local aliases and
providers preserve its identity; its operations must be handled before exit.
Generic scope factories may use symbolic family payloads such as `State a`;
returning the same inherited payload shape retains its original lifetime. A
longer-lived outer capability may pass through an inner scope in structural
data; only the exiting owner is forbidden in that result. Primitive and
structural data may return; nominal and unresolved results or transferred
arguments conservatively reject. Direct source closures may return when a
bounded capture proof excludes the exiting owner; unknown captures still reject.
A direct anonymous adapter whose whole body invokes its callback may borrow a
capturing callable with a structural result. Exact generic identity and Unit
callback helpers own validated public flow contracts. A single annotated
capability parameter may read a Unit operation through source or compiled
helpers, for example
`func (state: State a) : a ! {state.get} => return state.get ()`; calls
substitute the argument's exact identity in that row. Exact curried callback
helpers also preserve it, for example
`func (state: State a) => return func (callback: Unit -> a ! {state.get | e}) => return callback ()`.
Complete annotations may bind the same capability relationship:
`const read: (state: State a) -> a ! {state.get} = func input => return input.get ()`.
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
`func (left: State a) => return func (right: State b) => return right.get ()`
preserves `right` in its result row. The complete header form is
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
`func first => return func second => return {second, nested: (first, 42)}`.
Their owned result footprint records every retained input; unused inputs add no
result footprint. A named helper may also directly invoke one callback with
Unit, such as
`func unused => return func run => return func other => return run ()`. Its
contract retains the selected callback's exact operation row. Exact helpers may
pass ordered formal inputs to one callback, such as
`func run => return func left => return func right => return run left right`.
The actual literal or checked named callback must prove that it does not store
those inputs; earlier captures keep their own lifetimes. Local callback aliases
preserve their selected owners. Repeated effect labels still require separate
handler occurrences, including when two inputs alias one owner. These contracts
use the existing 16-parameter bound. Named forwarding helpers compose those
relationships through exact checked producers, including imported helpers.
Factory/projected callbacks remain unsupported. Other hidden capture/store
contracts and mixed-owner State pairs remain unsupported. See
[qualification](../qualification/SCOPED_EFFECTS_QUALIFICATION.md).

## Qualified bindings

An inferred generic function keeps the associated operations, members, fields,
or effect operations it needs as constraints on its type. A caller selects the
implementation when it supplies concrete arguments. You may write the same
constraints explicitly after a complete binding annotation:

```blot
const twice: a -> a where { associated "add" a a a } = func value => return value + value
const first: a -> b where { field "first" a b } = func value => return value.first
const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
io answer () => return twice 21
```

The `where` clause is available on top-level `const`/`let` and local `let`;
`where` remains an ordinary identifier elsewhere. Predicates are separated by
commas, and a final comma is allowed. The forms are `associated "member" T T
T`,
`result "member" Input Output`, `receiver "member" T T T`, `field "member" T T`,
`update "member" T T
T`, `operation Operation.name T...`, `type_rep T`, and
`effect_rep !{...}`. Parenthesize a non-atomic type argument. `associated`,
`result`, `receiver`, and `update` may end in an effect row such as `! {| e}`;
without one, their invocation effects are inferred. The clause constrains the
binding's callers and must cover the requirements of its body. Extra predicates
deliberately narrow the public type. Parameter annotations cannot contain
`where` clauses.

`result "member" Input Output` requires the member selected by the **output**
type, matching `@type.result "member" input`. The input type does not supply a
fallback implementation. The selected member must accept `Input`, return
`Output`, and satisfy the optional invocation effect row. For an effectful
conversion, share that row with the function annotation:

```blot
const convert: a -> b ! {| e} where { result "from" a b ! {| e} } =
  func value => return @type.result "from" value
```

This requirement can also appear in a named contract or a local binding's
`where` clause. Inferred conversions continue to work without a written clause.
A written clause must cover an open result-selection requirement just as it
covers an associated operation or field requirement.

Use `type Name parameters is contract = { ... }` to name a reusable bundle of
predicates. Contracts can include other contracts, refer forward, take shaped or
explicitly curried type parameters, and be imported by name or namespace. They
introduce no runtime values or dictionaries; the ordinary evidence and
associated-dispatch rules still choose implementations.

```blot
type Add a is contract = { associated "add" a a a }
type Arithmetic a is contract = { Add a, associated "mul" a a a }
type Project [owner, value] is contract = { field "value" owner value }
type Box a is data = $Box { value: a }
const twice: a -> a where { Arithmetic a } = func value => return value + value
const read: a -> b where { Project [a, b] } = func box => return box.value
io answer () => return twice (read ($Box { value: 21 }))
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
const keep: a -> (Identity.Item a) where { Identity a } = func value => return value
io answer () => return keep 42
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
[associated contracts](../compiler/ASSOCIATED_CONTRACTS.md).

An explicit implementation supplies every abstract type and function member. Its
named parameters must be determined by its head; prerequisites cannot introduce
extra binders. Defined equations cannot be overridden.

```blot
type Source s is contract = { type Item, const first: s -> (Source.Item s) }
impl ArraySource a : Source (Array a) = {
  type Item = a,
  const first = func values => return @array.get values 0,
}
const read: s -> (Source.Item s) where { Source s } =
  func values => return Source.first values
io first () => return read #[42]
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
nullary constructor as `(func () => return $Idle)`.

## Expression tags

Put `@[expression]` before a top-level `const`, `let` or named `func` to apply the expression
as a function to the initializer. A tag can use local names, named imports,
qualified imports, and function arguments. It may share the declaration line.
With several tags, the nearest runs first: `@[f] @[g] const x = value` binds
`f (g value)`. The declaration's type annotation constrains the result of all
tags, including when the initializer is a function.

```blot
func add amount => return func value => return value + amount
@[add 1]
@[func value => return value * 2] io const answer: U32 = 20
@[add 1] io let started: U32 = 41
```

`const` decorators execute at compile time under the usual step budget; `let`
decorators execute once at module startup. Unreachable tagged declarations are
type checked but not evaluated. A direct reference to the tagged declaration's
own bound name receives `recursive_tag`; tags on types, effects, and fixities
receive `unsupported_attribute`.

## Modules, constants, current limits

Use `blotc check-exports FILE...` to check that a module writes the types of
its public values. Named functions may annotate their parameters and result;
`const` and `let` may annotate the whole declaration. A unit parameter spells
its own type. Local functions keep ordinary inference. The command parses the
file and reports missing signatures even when an implementation contains an
unresolved name. `--include-private` also checks private module-level values.
An ordinary build still checks bodies and infers omitted signatures.

`#run expression` evaluates a pure expression during compilation. Parentheses
delimit it inside a larger expression. Scalar results become Wasm constants. A staged function can build
arrays, named records, tuples and data constructors, select a field and read
an array element. Its returned data uses the same layout as a literal.
A table generator can use a captured value, and a staged function can produce
the implementation of a function with a declared type. For example, the
following function calculates the four entries during compilation. The runtime
argument selects an entry.

```blot
func lookup (base: U32): (U32 -> U32) => return do:
  let rows: Array U32 = @array.generate 4 (func i => return @u32.add base i)
  return func (i: U32): U32 => return @array.get rows i
io answer (i: U32): U32 => return (#run (lookup 40)) i
```

`@array.fill` and `@array.generate` charge their size against the evaluation
budget. Generators run in index order. A zero-length table invokes the
generator zero times. Staging produces a value inside a declaration; module
names and type definitions are known once parsing finishes.

The evaluator supports Unit, Bool, U32 and F32 literals,
scalar arithmetic and comparisons, conditionals, short-circuit logic, global
constants and fully applied named functions, including imports. Integer
arithmetic wraps as in Wasm. Integer division by zero fails compilation.

`#do:` is shorthand for `#run do:`. Its local statements execute at compile
time, and `break` supplies the resulting value:

```blot
io answer () => return #do:
  let base = 40
  break base + 2
```

Both forms can use bindings created inside the staged expression. A runtime
parameter, host effect, unsupported operation or exhausted evaluation budget
fails the build. Each evaluation has a 65,536-step budget for Core visits, generated elements and captured bindings, and a
depth limit of 256. Embedding the result has a separate 65,536-value budget.
Quoted code still needs backend support.

A project can grant a named file to a build by declaring a native asset with
kind `input`. Its module exports `file`. Pass that value to the ordinary
`include` function from `std/build` inside `#run`.

```blot
import { include } from "std/build"
import { file as icon } from "./icon"
func header file => return do:
  let bytes = include file
  return { magic: @array.get bytes 0, size: @array.length bytes }
io icon_size () => return #do:
  let image = header icon
  break image.size
```

The project records the selected files and definitions from the branches it
evaluated. If all checked modules are reused and those files still match, it
can return the previous Wasm. A changed source definition currently goes
through emission even when it is outside the recorded branch. [Project build
inputs](../host/assets.md#files-read-by-run)

Compile-time reflection supports `#for field in #fields T:`,
`#for variant in #variants T:`, `#if ...:` / `#else:`, `val.(field)` field
reads, `val.(field) := expr` reflected updates, field metadata (`field.name`,
`field.index`, `field.has_default`, `field.default`, `field.has_tag`,
`field.tag`), and expression-position reflected record builders (`let built: T =
#for field in #fields T: ... break value`):

```blot
type Config is data = $Config {
  width: U32 = 800,
  height: U32 = 600,
}

func default_record (): t =>
  return #for field in #fields t:
    #if field.has_default:
      break field.default
    #else:
      break field.index

io area (): U32 =>
  let cfg: Config = default_record ()
  return cfg.width * cfg.height
```

All owned arrays share the unified `#[T]` (`Array T`) type and literal syntax,
with in-place element writes and dynamic growth/truncation:

```blot
io answer (): U32 =>
  let items: #[U32] = #[41]
  let score = 42
  items := @storage.push self 9
  items[0] := 42
  let first: &U32 = &items[0]
  let local_ref: &U32 = &score
  return @u32.add (@storage.load first) (@storage.load local_ref)
```

`#[...]` constructs an owned `#[T]` (`Array T`); `#[N; T]` checks fixed-length
arrays. `&T` borrows one value (`&local`, `&record.field`, or `&items[index]`),
`&[T]` borrows a range (`&items[start..end]`), and `^T` links to an element of a
stable pool (`^items[index]`). The named forms are `Ref T`, `View T`, and
`Link T`. `@storage.load` reads a reference/link and `@storage.read` reads a
view/array. References, views, links, and shared handles (`*T`) are strictly
read-only: none of them permit indexed `:=`, field `:=`, `@simd.store`, or
length mutations. Updates use `:=` on a uniquely owned local or `own` parameter
(and fail with `aliased_update` while any borrow or alias is live; rebinding a
scalar/record local with `:=` produces a new version while existing `&local`
references keep reading the earlier value). `@storage.copy` (`values.copy`)
makes an independent copy. `freeze value` creates a read-only `*T` shared
handle; `@simd.store` likewise requires unique ownership.

`@storage.reserve owner 1048576` requests a minimum planned capacity in elements
for one owned `#[T]` array. The count must be a U32 integer literal
(parentheses are permitted); runtime values and constant-name aliases are
rejected. `Ref`, `View`, and `Link` values cannot reserve. This marker returns
`Unit` and changes no data, logical length, identity or borrow epoch. It
remains planning metadata even when its result is unused.

An explicit request replaces that owner's fallback `growerBytes` requirement; it
does not impose a logical-length limit or increase every pool of that type.
Repeated requests for an owner take their maximum, including requests through
aliases. Zero requests only the header and known initial literal contents. The
planner preserves initial contents, checks row-size/header/alignment overflow,
and sizes shared slots for every owner that can use them. Alignment or slot
sharing can provide extra physical capacity, which is not promised. Owners
without a request continue to use the configured default budget.

These features select a data-stack backend with checked scalar and aggregate
layouts, generic helpers, known callbacks and lexical storage reuse. Named
global pools, including computed initializers, persist per instance. Numeric
arrays cross browser/Pen boundaries by copy; ordinary Foreign callbacks can
suspend while the guest adapter excludes reentry. Inline records copy by value,
while stores write through array aliases. Use `values.copy` when an
independent snapshot is needed. It checks borrowed results and permits shrinking
after a local borrow’s final use. Language task execution is excluded from this
model; host worker jobs and data queues remain in scope.

The replacement does not yet cover the whole language; unsupported forms fail
compilation. Ordinary programs still use the original storage path. Ink and Gdev
use named owners and copied packets; one real Gdev main frame has passed in
native Pen, while broader application qualification remains pending. See the
[scoped storage migration](../compiler/SCOPED_STORAGE.md) for the exact
supported operations, lifetime checks, capacity limits and remaining work.

Imports precede declarations: `import * as math from "./math"` or
`import { Point as Position, distance } from "./geometry"`. Relative paths may
omit `.blot`; the CLI maps `std/` to the source library. Cycles are errors.
Top-level declarations are public by default. `private` before a value, alias,
data, opaque, contract, effect or named function declaration keeps its name inside its defining module;
constructors and operations inherit that visibility. `private io` keeps
the host export while hiding the Blot import. Importing a type does not import
differently named constructors. Imported operator functions need local fixity
declarations. `export { answer as forwarded, Token } from "./producer"` forwards
selected public names while retaining their original producer and kind.

`type Token is opaque = U32` declares a nominal type with one private
constructor, `$Token`. `opaque` takes the kind position used by `data`,
`contract` and `effect`. The producer can construct and match it, including
`func ($Token value) => return value`, and inspect record representation fields.
Callers use public factories, observers and associated declarations; aliases and
type witnesses preserve opacity. Token remains distinct from U32 inside its
producer. Public signatures cannot expose private nominal/effect identities or
predicate implementations. Scalar and reference representations erase the opaque
wrapper without adding a runtime allocation or tag. See
[module abstraction](../compiler/MODULE_ABSTRACTION.md) for import and artifact
rules.

Hosts can register typed parsers for external files through `createCompiler`'s
`assets` option. Source imports those virtual modules normally, for example
`import { value } from "./settings.json"`. Parsers return type descriptions and
values, or types and references to host resource snapshots. See
[typed asset imports](../host/assets.md) for JSON and shader integration. This
is an explicit host parser boundary; the native CLI alone does not choose file
parsers.

`io`, `io const` and `io let` mark host entrypoints. Exactly the
entry module's entry declarations become Wasm exports, under their own names; a build needs at
least one, and nothing else is exported. An entry's final type must fit the
guest ABI: functions over Unit, U32, F32, Bool, Array U32 or Array F32 (or one
scalar `! {Foreign}` callback) that handle every other effect, and Unit, U32,
F32 or Bool values. A generic entry, an `Array` value or a function that leaves
an effect unhandled is an error. Only the entry module reaches the host, so a
module it imports cannot declare entries. `io` is contextual at top level (`io main () => ...`, `io const`, `io let`), so `io`, `entry`, `kernel` and `process` remain ordinary
names elsewhere, as in `func launch io => io ()`.

```blot
func helper (value: U32) => return value + 1
io answer () => return helper 41
io let started: U32 = helper 1
```

Compilation keeps only what the entries reach. Every declaration is type
checked, but unreachable ones are never specialized, const-evaluated, run at
startup or emitted: an unused constant that would panic or exhaust the step
budget no longer fails the build. Associated dispatch is selected while
specializing, so a missing implementation such as `true + false` is reported
only in reachable code.

Function values remain ordinary values: write `const name = func argument =>
return body` or `let name = func argument => return body` when a function value
is intended. Use `func name argument => return body` for a named module
function.
`const name = expression` evaluates at compile time under a step budget.
`let name = expression` initializes once at runtime when the module starts, if
an entry reaches it. Compile-time expressions can build immutable values,
closures, and builders, but cannot do foreign IO. `@panic "message"` fails const
evaluation or traps in Wasm. String literals are also ordinary runtime Unicode `Text` (`#[U32]`) values such
as `"é🙂"`; intrinsics that require a literal still read their argument as
source syntax. Compile-time reflection is provided by `#for #fields` /
`#variants`, `#if` / `#else`, `val.(field)` reads/updates, field defaults
(`field.default`), `field.index`, `@[...]` data tags, and reflected record
builders.

Startup orders `let` initializers by their dependencies and rejects cycles.
Dependency analysis includes referenced function bodies, even when a function is
passed without being called. This conservative rule can reject a deferred cycle
such as:

```text
func read () => return value
let value = (func ignored => return 42) read // rejected: initialization_cycle
```

Compile-time initializers cannot read top-level `let` values or functions.
Runtime initializers must handle their effects with providers; module startup
does not supply implicit handlers.

Monadic blocks use an ordinary prelude adapter:

```blot
const try = monad Maybe
func sequence candidate => return do try:
  use value <- candidate
  break value + 1
io answer () => return Maybe.unwrap_or 0 (sequence ($Some 41))
```

`use` calls the selected type's `bind` with the remaining block as a function.
`break value` calls `pure`; `break $ expression` forwards an existing wrapped
result. A failed `Maybe` or `Result` bind skips subsequent effects and loop
iterations. The resolver expression runs once, nested `do` blocks have
independent rules, and unrelated effects remain visible. The same adapter
accepts imported types and user-defined data types with `pure` and `bind`
members. Type-constructor values can be aliased or passed through ordinary
functions.

Monadic loops use the selected type's `iterate initial step` member. Each step
returns a wrapped `$Continue state` or `$Done result` using the prelude's
`Iteration state result` type. `Maybe.iterate` and `Result.iterate` use constant
call stack; failure skips later steps, and `break value` still exits the nearest
`do`. Custom monads need an `iterate` member only for blocks containing loops.

```blot
func step count => return
  if count < 42 then $Some ($Continue (count + 1)) else $Some ($Done count)
io answer () => return Maybe.unwrap_or 0 (Maybe.iterate 0 step)
```

Not yet executable: collection patterns, F64, arbitrary first-class
type-valued computation outside `#for`/`#if`, and exposed multi-shot
continuation values. Do not infer availability from editor highlighting or
design examples.

Hosts use `host/guest.ts`. The owned-storage integration uses guest ABI 8 and
session protocol 2. Ordinary programs can still emit earlier profiles while the
legacy backend is being retired; the host rejects mixed-profile modules. Numeric
arrays cross as copied typed arrays; host callbacks are explicit scalar or
numeric-array capabilities. Async capabilities suspend a guest invocation
without discarding its local state. A guest closure capturing a host callback
stays bound to that invocation: calling it after the invocation ends fails; a
later host argument cannot rebind it. Records, general arrays and persistent
guest handles are not host ABI values yet. There are no implicit
window/filesystem/network imports. For details read `docs/host/guest-abi.md`,
`docs/language/effects-and-io.md`, `host/README.md`, and `std/README.md`.

## Selectors, conversion, and type witnesses

`.name` is a function that selects a field or associated member. Chained
selectors such as `.position.x` select both fields from the eventual argument.
Write member access without a space (`point.x`); write a separate selector with
a space (`array.map .x points`). `.add` selects a receiver's `add` member and
returns its remaining curried function. It is useful in
`array.fold_left .add 0 values`. Uppercase names are allowed when the owning
type actually declares that member.

`from` is defined in the prelude as
`func value => return @type.result "from" value`. The expected result type
chooses that type's ordinary `from` function. Primitive implementations use
`to_f32`/`to_u32`; custom types can define their own conversions. There is no
default target when the context leaves it ambiguous.

```blot
io normalized (first: U32) => return from first / 6555.0
io explicit (value: U32) => return do:
  let converted: F32 = from value
  break converted
io const different = if :1 == :2.0 then false else true
```

`:value` abbreviates `$Type value`; `:(expression)` groups a larger expression.
The existing witness rules apply: a constructor/function witness describes its
final result type. Its body is not called; an ordinary witness expression is
evaluated once. Type names belong in annotations, constructors in expressions
and patterns. Constructors require `$` in declarations, expressions and patterns, including
qualified names (`$time.Clock`). Boolean literals and
patterns are the bare words `true` and `false`; they have primitive type `Bool`.
Type names and explicit type arguments stay unmarked.

`value |> transform` calls `transform value`. Both `pipe` and its fixity are
ordinary prelude declarations. For longer builder sequences, `:=` keeps each
step on its own line.

## Deferred work

Use an ordinary Unit callback for work that should run only when selected. `and`
and `or` are primitive short-circuit operators; their right operand runs only
when needed. Function arguments otherwise evaluate eagerly.

```blot
func choose enabled -> callback => return
  if enabled then callback () else 42
io answer () => return
  choose false (func () => return @panic "unused callback")
io fallback () => return
  Maybe.unwrap_or_else (func () => return 42) $Nothing
```

`Maybe.unwrap_or_else` and `Result.unwrap_or_else` take a Unit callback as their
fallback. A selected callback runs once in these helpers. Calling an ordinary
callback again runs its body again; there is no implicit memoization or demand
cell. Callback effect rows and owner lifetimes follow the ordinary rules. The
former `~` parameter/type syntax and `@demand` intrinsic are removed.

## Pattern alternatives and layout

Alternative rows bind the same names and share one body. A failed guard falls
through to the next arm. Guards do not count toward exhaustiveness: retain an
unguarded fallback covering their cases.

```blot
type Choice is data =
  | $First U32
  | $Second U32
  | $Empty

io answer value => return case $Second value of
  $First amount | $Second amount if amount >= 40 => amount
  $First amount | $Second amount => amount + 2
  $Empty => 0
```

Indented expression continuations extend the preceding expression; `:` and `of`
open statement and case suites. Leading `|` can align with the first alternative
in a case arm. Parentheses also allow continuation across lines.
`blot fmt path.blot` normalizes spacing and blank lines, separates long data
alternatives, and removes parentheses that do not affect expression grouping.
`--check` checks without writing. The formatter verifies that the parsed
structure is unchanged before writing.

## Sparks, kernels and isolated processes

Blot provides three orthogonal, compiler-verified concurrency primitives:

1. **`spark #[expr | pat <- source]`** — synchronous, pure (`! {}`), ordered
   data-parallel map over a single unguarded irrefutable array or `U32` range
   generator. The compiler verifies read-only purity over outer captures, the
   generator source, and module globals, auto-vectorizing eligible scalar
   kernels to 4-wide Wasm SIMD (`v128`) and compiling non-numeric pure maps to
   a preallocated direct loop.
2. **`#kernel`** — pure, compiler-verified multi-core batch kernels
   (stateless `#kernel func name (x: Item): Out => ...` or prepared-context
   `#kernel const name: Kernel [WireCtx, Item, Out] = { prepare: p, run: r }`),
   binding an opaque entry-module `Kernel [Ctx, Item, Out]` handle and emitting
   schema-validated `blot:kernels` metadata for warm host `KernelPool`s.
3. **`#process`** — isolated stateful sequential actors
   (`#process const name: Process [Config, Cmd, Reply] = { init: i, step: s }` where
   `step` takes `own State`), emitting `blot:processes` metadata for
   deterministic host schedulers (`Processes`).

```blot
// Pure data-parallel map (vectorizes to 4-wide Wasm SIMD):
io double (xs: #[U32]): #[U32] =>
  return spark #[x * 2 | x <- xs]

// Stateless multi-core batch kernel:
#kernel func mix_u32 (x: U32): U32 =>
  return (x * 1664525) ^ 1013904223

// Isolated stateful process:
type PlannerState is data = $PlannerState { total: U32 }
func planner_init (seed: U32): PlannerState => return $PlannerState { total: seed }
func planner_step (s: own PlannerState) -> (delta: U32): (PlannerState, U32) =>
  let next = s.total + delta
  return ($PlannerState { total: next }, next)

#process const planner: Process [U32, U32, U32] = {
  init: planner_init,
  step: planner_step,
}
```

Host workers exchange canonical flat-numeric or numeric-array packets under
ABI 8 and Session Protocol 2. Guest closures, owners, borrowed views, opaque
handles, and provider capabilities stay inside their originating instance.

Host callbacks suspend the current invocation through the guest adapter. Keep
borrowed views within that invocation; retain later state by copying it into a
named owner. See [the ownership contract](../compiler/SCOPED_STORAGE.md) and
[the host boundary](../host/guest-abi.md).
