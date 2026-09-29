# Blot 2 design baseline

This document records the agreed language direction. Its examples describe the
target language; they are not yet accepted by the executable core grammar as a
whole. The implementation status and remaining choices are listed below.

## Goals

- Compile to WebAssembly 3.0+ with a declared, tested target feature set.
- Keep compilation and edit-to-running-game latency low.
- Support hot reload while preserving compatible game state.
- Make arrays first-class, with predictable storage and update costs.
- Provide type inference, generic types, pattern matching, and effects.
- Keep source values immutable.

## Naming

Values, functions, fields, and module namespace aliases use `snake_case`. Types
and constructors use `PascalCase`; generic type parameters use lowercase names.
The proposed effect declarations also use `PascalCase`.

## Functions and blocks

Functions use `fn pattern => expression`. Bind them at the top level with
`const name = fn pattern => expression` or
`let name = fn pattern => expression`. Both forms bind ordinary function values
and are public by default.

```blot
const identity = fn value => value
const add_pair = fn (left, right) => left + right
const curried_add = fn left => fn right => left + right

const increment = fn value => value + 1
const add_ten = curried_add 10
```

The parameter is one pattern. A tuple pattern accepts a tuple; currying uses
another explicit function. Type annotations use `:`.

Rank-one bindings can state their required implementation evidence after a
complete annotation:
`const twice: a -> a where { associated "add" a a a } =
fn value => value + value`.
The same clause is available on a local `let` and constrains the final value
after expression tags. The word `where` remains an ordinary identifier
elsewhere. Inferred constraints and explicit clauses share the same semantic
predicates; a clause must account for the body's obligations, while extra
predicates intentionally restrict callers. Open effect rows use
`! {OperationType | e}` or `! {| e}`. A binding cannot use one free name as both
a type and row variable. Qualified parameter types remain unsupported. The first
implementation accepts concrete labels before an open row tail; symbolic generic
effect labels need a later row-identity representation.

```blot
const squared = fn (value: F32) -> F32 => value * value
```

`do:` makes a statement suite into an expression. A function with statements is
written with `=> do:`; there is no `fn pattern:` block-function form.

```blot
const squared = fn (value: F32) => do:
  let result = value * value
  return result

let initial_position = do:
  let spawn = choose_spawn level
  return #Vec2 { x: spawn.x, y: spawn.y + 1.0 }
```

In plain `do:`, `return` supplies that expression's result and falling through
produces `Unit`. Evaluating a `do` executes it; placing it inside a function
delays that execution until the function is called. Statement suites such as
`if` and `for` do not implicitly introduce another `do` result boundary.

Consequently, a statement-bodied function needs no trailing `return ()`. This is
already implemented for plain blocks: a final expression statement is discarded,
not implicitly returned. Expression-bodied `fn x => expression` still returns
its expression. An explicit non-unit return on one path and unit fallthrough on
another is a type error; no optional/union result is invented.

### Pure and effectful bindings

`let name = expression` requires a pure right-hand side. Use
`use name <- expression` to bind the result of a possibly effectful computation:

```blot
const move = fn () => do:
  use velocity <- ecs.get #Velocity
  use position <- ecs.get #Position
  let next = advance (position, velocity)
  use _ <- ecs.set next
  return ()
```

In plain `do:`, `use` evaluates its RHS once before the remaining statements,
binding its result as an immutable value. `_` discards that result without
introducing a name. It also accepts pure computations, so effect-polymorphic
code need not switch binding syntax when an effect row becomes empty. Both
binding forms evaluate in the current stage; `use` does not permit runtime
effects during const evaluation.

`use expression` is exactly shorthand for `use _ <- expression`. It still
evaluates the RHS and performs the bind; only the result's name is omitted:

```blot
use ecs.insert (Ghost { remaining: 1.0 })
```

This distinction applies to the RHS, not to the rest of the block. The checker
must follow inferred effects through helpers, arguments, and branches rather
than recognize operation names. Tail calls such as `return ecs.get Velocity`
also propagate effects; `use` is the binding form, not a required marker on
every effectful call.

`use` neither handles effects nor constructs a boxed action. A provider supplies
an operation's meaning; an enclosing function delays execution until called. The
ECS example below makes that provider's world/entity inputs explicit.

### Resolver-valued do blocks

`do resolver:` selects a resolver using an ordinary expression. Parentheses
around that expression are optional; named const values work the same way:

```blot
const try = monad Maybe

const chain_maybe = fn (my_maybe, my_other_maybe) => do:
  let smth = do try:
    use value <- my_maybe
    return $ my_other_maybe value
  return smth
```

`do monad Maybe:` and `do (monad Maybe):` select the same resolver as `do try:`.
Neither `monad` nor `try` is a keyword or a compiler-recognized name. `Maybe` is
a const-time type constructor; the ordinary library function `monad` builds a
resolver from its source-defined `bind` and `pure` operations.

For `monad Maybe`:

- `use value <- expression` expects `Maybe a`. `#Some value` continues the
  block; `#Nothing` ends that block with `#Nothing` without running its
  remainder.
- `use expression` has the same behavior, discarding the successful payload. In
  particular, `use #Nothing` still short-circuits.
- `return value` lifts the value with `Maybe.pure`, producing `#Some value`.
- `return $ expression` forwards an existing `Maybe` result without another
  wrapper. `$` here is return syntax, not an overloadable application operator.
- `let value = expression` stays an ordinary pure binding and does not unwrap
  anything. There is no implicit choice between lifting and binding a value.
- Falling through lifts Unit, producing `#Some ()`. Ordinary expression
  statements merely discard their result; use `use` to perform a monadic bind.

The inner block above is equivalent to:

```blot
case my_maybe of
  Nothing => Nothing
  Some value => my_other_maybe value
```

This is immediate sequencing, not a deferred action object. The resolver
expression is evaluated once before its block. Its implementation strategy must
be statically known, but a resolver may carry runtime inputs such as a world and
entity. `const try` stores the resolver without executing any future block.

The nearest `do` owns its binding/return rules. A nested plain `do:` keeps
direct binding and return; it does not inherit monadic syntax from an enclosing
block. `return $` requires an explicit resolver on that nearest block. Calling a
function does not rewrite its body's binding rules. Scoped effect providers can
still interpret operations performed through helpers.

A monad adapter sequences wrapped values; it does not erase unrelated effects.
An ECS provider instead interprets its registered storage effects, keeping
direct value bindings. The complete RHS of an outer `let` must be pure after the
resolver has done its work, including effects of evaluating the resolver itself.
Unresolved effects remain visible to callers and scheduling.

The lowering target for `Maybe`/`Result` is ordinary branching after resolving
the source operations. This is not a claim that arbitrary resolvers are free or
that general resumable handlers are implemented. The compiler currently parses
resolver headers and forwarding returns but reports unsupported resolver
execution; it does not special-case `Maybe` or aliases such as `try`.

### Demand-driven parameters

`~` marks a demand-driven parameter, available to any function:

```blot
const unwrap_or_else = fn value => fn ~fallback =>
  case value of
    #Some found => found
    #Nothing => @force fallback

const duplicate_if = fn enabled => fn ~value =>
  case enabled of
    #False => #Nothing
    #True => #Some (@force value, @force value)
```

Calling such a function captures the argument expression without evaluating it.
The parameter names a suspended computation, not its computed value; merely
referencing it does not force it. The first `@force` evaluates that computation,
and subsequent forces of the same parameter binding reuse the result. An
unforced argument is never evaluated. Ordinary parameters remain eager; calling
a function directly or through an operator does not change its parameter's
demand mode.

Demand mode belongs in the function's checked signature so higher-order calls
and partial application preserve it. Deferred computations retain their effects;
functions that may demand them must account for those effects. This is not a way
to make an effectful computation pure. The executable signature notation is
`~T`. Escaping closures retain their deferred bindings; the first force uses the
providers active at that force. Cached values survive later guest calls.

## Modules

Imports are static declarations at the top of the module. Top-level `const`,
`let`, type, constructor, and effect declarations are public by default.

An optional adjacent declaration file, such as `math.d.blot` for `math.blot`,
can describe the API presented by autocomplete and documentation. This is a
tooling convention planned for future editor support; the compiler does not
consume declaration files yet. Omitted bindings remain accessible by explicit
name. Declaration files curate discoverability and never restrict access.

```blot
import { Vec2 } from "./math.blot"
import { clamp as clamp_value } from "./numeric.blot"
import * as render from "engine/render"

const origin = #Vec2 { x: 0.0, y: 0.0 }
const identity = fn value => value
```

An import is not a value-producing expression. A module does not export its
final `return` value. Named initialization functions can produce runtime state.

## Data types

Use `data` for new nominal data types. A type has one or more constructors; a
struct is the one-constructor case. Separate `struct` and `enum` declarations
are unnecessary.

```blot
data Vec2 = #Vec2 { x: F32, y: F32 }

data Maybe a = #Some a | #Nothing

type Result [value, error] is data = #Ok value | #Err error

data EntityId = #EntityId U32

data Contact =
  | #Separated
  | #Touching { point: Vec2, normal: Vec2 }
  | #Overlapping { depth: F32, normal: Vec2 }
```

Construction mirrors the declaration:

```blot
let position = #Vec2 { x: 1.0, y: 2.0 }
let selected = #Some position
```

Data constructor names require `#` in declarations, construction, and patterns,
including `#Some`, `#Nothing`, `#True`, and `#False`. Qualified constructors put
the marker before the whole name: `#math.Vec3`. Types stay unmarked; generic
type application uses forms such as `Maybe Vec2` and `Array (Maybe Vec2)`.

Types and effects accept at most one argument at each application stage, like
functions. A list, tuple, or record can bind several type values:

```blot
type Pair [left, right] is data = #Pair (left, right)
type Entry { head, tail } is data = #Entry { head, tail }
type Curried left => type right is data = #Curried (left, right)
```

These argument shapes can nest. Record arguments match by field name.
`Pair [U32, a]` infers `a`; free lowercase annotation names share the enclosing
declaration's scope. Currying is explicit: `Curried U32` remains a constructor
until another argument is supplied, as in `(Curried U32) Bool`.

`type` names an existing type expression without creating another identity or
constructor. There is no `type alias` form or separate `alias` keyword.

```blot
type Position = Vec2
type Particles = Array Vec2
type Transform a = a -> a
```

`Position` and `Vec2` are interchangeable and share associated operations.
`EntityId` and `U32` are distinct types despite the wrapper's simple payload.

Booleans use PascalCase constructors: `type Bool is data = #True | #False`,
rather than separate lowercase literal spellings.

The data model does not require a runtime tag or heap allocation for every
constructor. A single-constructor plain record can have an inline representation
without a discriminant. Arrays, functions, and scalar primitives retain
dedicated representations; arrays are not implemented as recursive lists.

## Case matching

Use `of` to introduce the pattern suite, with one or more comma-separated
inputs. Single-input cases also use `of`, not `:`.

```blot
const choose = fn first => fn enabled => fn fallback =>
  case first, enabled, fallback of
    #Some value, #True, _ => value
    _, _, #Some value => value
    _, _, _ => 0
```

Inputs evaluate once, left to right. Each arm has one pattern per input; the
first matching complete row wins. Bindings are local to the arm and cannot
repeat within a row. Exhaustiveness covers combinations across all inputs, not
each column independently. Matching several inputs does not construct a tuple or
require a heap allocation.

## Pattern tests and guarded bindings

`if let pattern = expression:` tests a pattern and introduces its bindings in
the successful branch. `#Some(x)` and `#Some x` spell the same constructor
pattern; parentheses group its payload, not a new multi-argument calling form.

```blot
const double_if_present = fn (candidate: Maybe U32) -> U32 => do:
  if let #Some(value) = candidate:
    return value * 2
  else:
    return 0

const double_or_zero = fn (candidate: Maybe U32) -> U32 => do:
  let #Some(value) = candidate else:
    return 0
  return value * 2
```

Both forms evaluate the RHS once and require it to be pure, like ordinary `let`.
Bind a possibly effectful result with `use candidate <- read_candidate ()`
first, then match that immutable value. Neither form performs a monadic bind or
implicitly handles effects.

For `if let`, the names introduced by the pattern are unavailable in `else` and
after the conditional. The successful branch knows the matched constructor and
payload types; the failure branch knows the remaining possibilities. A branch
that exits does not contribute to the facts at the following statement.

For `let pattern = expression else:`, the names are available after the binding,
but not in its RHS or failure suite. Every path through the `else` suite must
exit before reaching that continuation: for example, `return` from the enclosing
`do`, or `break`/`continue` targeting an enclosing loop. Falling through is a
compile error. Returning from a nested `do` inside `else` is not sufficient.
This is the same non-fallthrough principle as
[Rust's let-else](https://doc.rust-lang.org/reference/statements.html#let-statements),
adapted to Blot's nearest-`do` return boundary and its selected resolver.

Ordinary `let pattern = expression` requires a pattern that cannot fail for the
currently known type. Refutable patterns need `else` or a conditional match;
there is no implicit panic or `#Nothing` result on failure.

Narrowing tracks finite constructor/union alternatives of immutable bindings,
not arbitrary predicates. It can also describe a stable field path of an
immutable value, but not a fresh effectful read. Successor rebinding with `:=`
creates a new version; facts about the old version do not automatically apply to
it. At joins, retain only facts valid on every reachable incoming path.

Failed partial patterns must not remove a whole constructor. For example,
failure of `#Some(#Some(x))` still allows `#Some #Nothing`; only a pattern
covering every payload of `#Some` can exclude that constructor on failure.
Guards likewise do not prove a constructor absent when only the guard fails.
This bounded flow analysis does not reinstate the deferred predicate-refinement
solver.

## Closed unions

Allow `F64 | Text` as a finite union of value types. `Text` is the string type
in this design. The selected alternative is dynamic; the set of alternatives is
static. Unlike a nominal `data` declaration, it needs no named constructors:

```blot
type Reading = F64 | Text

const read_score = fn (ready: Bool) -> Reading => do:
  if ready:
    return 42.0
  return "pending"

const reading_label = fn (value: Reading) -> Text => do:
  if let (number: F64) = value:
    return "Score: ${number}"
  return value
```

The typed pattern `(name: Type)` tests a union arm at runtime and binds its
payload. Here `value` is known to be `Text` after the returning `F64` branch.
Use the same pattern in `case` arms and guarded `let` bindings; ordinary type
annotations remain compile-time checks, not runtime tests. `@type.of value`
still describes the static type, so it is not a runtime discriminant operation.
These union matching forms are proposals, not part of the executable
[syntax example](examples/syntax.blot).

Initial boundaries:

- Introduce unions explicitly in an annotation or type alias. Check branch
  results against that expected union; do not silently turn every failed type
  unification into a larger union. Ordinary inference still works within arms.
- Flatten nested unions and deduplicate identical types, including aliases.
  `F64 | F64` is just `F64`; different nominal types stay distinct even when
  their layouts match. Union order does not change type identity.
- Widen a member into its union without a source wrapper. Narrow through a
  checked pattern; reject implicit union-to-member conversion. Match concrete
  arms known after type/const resolution, not arbitrary runtime type
  expressions.
- Exhaustive `case` must cover every arm. Do not distribute unions through
  containers: `Array (F64 | Text)` is different from `Array F64 | Array Text`.
- Start with finite scalar/nominal arms, including concrete generic instances.
  Defer open `Any`, structural overlap, runtime function-signature tests, and
  unrestricted union/intersection inference. Prefer named `data` constructors
  when two alternatives carry the same payload type but have different meanings.

### Representation and cost

Prefer the same tagged, inline representation available to nominal sum types. An
illustrative memory32 layout with an eight-byte payload, a one-byte tag, and
eight-byte alignment occupies 16 bytes. The payload can hold an `F64` or a
32-bit text pointer/length pair. This is a candidate layout, not a promised ABI;
text storage and lifetime management have their own costs.

Wasm has fixed numeric/reference value types, not a direct `F64 | Text` value
type. It does support multiple result values, so a compiler can return a tag and
payload in separate results rather than allocate a union wrapper. GC references
are opaque and cannot simply be packed into a linear-memory payload. These
constraints come from the
[Wasm type model](https://webassembly.github.io/spec/core/syntax/types.html).

Compared with inline storage, a uniformly boxed GC representation can simplify
reference handling but may require allocating a box for a numeric arm. An open
dynamic-value representation needs broader runtime metadata and loses the closed
exhaustiveness boundary. Neither should be the default merely to support this
syntax. The exact ABI, memory-versus-GC strategy, and measured cost remain
implementation choices.

Expect tag construction, tests/branches, and possibly extra payload copying or
padding. Optimization can eliminate some of these when the arm is known, but the
language must not promise that. `Array (F64 | Text)` pays those storage and
dispatch costs per element; keep homogeneous numeric arrays/component columns
for predictable stride and SIMD-friendly loops. The source union spelling alone
does not make a function heap-allocating or require runtime method lookup.

Union membership and payload layouts belong in interface and reload metadata.
Changing an arm must invalidate affected compiled interfaces and trigger a live
state compatibility check, not reinterpret existing values using new tag
numbers.

## Type-associated functions

A top-level function name can be qualified by a type:

```blot
const Vec2.magnitude = fn (value: Vec2) -> F32 =>
  sqrt (value.x * value.x + value.y * value.y)

const Vec2.scaled = fn (value: Vec2) => fn (factor: F32) -> Vec2 =>
  #Vec2 { x: value.x * factor, y: value.y * factor }

let distance = Vec2.magnitude position
let enlarged = Vec2.scaled position 2.0
```

The receiver is an explicit parameter, not an implicit `self`. Qualifying a name
does not by itself define generic dispatch. Associated bindings use
`const Vec2.scaled = fn ...` and are public like other top-level bindings.

### Statically checked receiver dispatch

The executable compiler supports receiver-first application:
`position.scaled 2.0` means `Vec2.scaled position 2.0`. This binds one argument;
it does not unpack tuples or insert a `()` argument. Consequently,
`position.magnitude` means `Vec2.magnitude position`, and `position.scaled` is a
function awaiting its factor. Definitions needing another argument use an
explicit nested `fn`, just like ordinary curried functions.

```blot
// Infer a requirement for the receiver's scaled operation.
const scale_twice = fn value => do:
  let factor: F32 = 2.0
  let next = value
  next := self.scaled factor
  next := self.scaled factor
  return next
```

Here the requirement is an operation shaped like `a -> F32 -> a`, not
inheritance from `Vec2`. Both `Vec2` and another type with a compatible `scaled`
operation could satisfy it without an explicit implementation declaration. The
rebindings require the operation to preserve the receiver's type.

The current compiler resolves associated operations in the module that owns the
receiver's nominal type. It does not search unrelated namespaces. A field and
method with the same name are ambiguous; function-valued record fields can be
called with the same syntax. Shared fields must exist on every constructor of a
type, while variant-specific fields require matching first.

Generic receiver operations specialize at their uses, including recursive calls
and partial applications. Inference preserves their effects. Missing or
incompatible operations fail at compile time, and there is no runtime name
lookup. Explicit qualified calls remain available. Explicit protocols, bound
syntax, and dictionary passing remain possible future extensions.

## Compiler primitives and source-defined operators

Keep `@` for compiler-owned primitives, with ordinary source functions exposing
them through library APIs. The compiler owns each primitive's type, effects, and
ownership contract; a wrapper cannot erase those requirements. Calling a
primitive does not by itself request compile-time execution.

Game, GUI, ECS, windowing, input, rendering and assets are not compiler
primitives. Host-backed effects originate in an explicit `io` capability passed
to the entrypoint. Effect rows describe requirements; they do not grant
authority. Source libraries declare those effects and receive narrower
capabilities from callers. No source effect declaration automatically creates a
host import. See [the controlled IO contract](compiler/effects-and-io.md).

```blot
// Standard-library source, in the module owning Int.
// PROPOSAL: exact primitive names; integer representation remains open.
const Int.add = fn (left: Int) => fn (right: Int) -> Int =>
  @int.add left right
```

Every expression operator names a source function. A symbolic operator's
spelling, precedence, and associativity are declared in a source header after
imports, before other declarations. The standard operator table is source too,
not a separate compiler dispatch table. Targets may be imported or defined later
in the module.

```blot
infixl 60 (+) = add
infixl 70 (><) = dot

// PROPOSAL: exact static-type lookup spelling.
const add = fn left => fn right => (@type.of left).add left right
const dot = fn left => fn right => (@type.of left).dot left right
```

`infixl` associates left, `infixr` associates right, and `infix` rejects
unparenthesized chaining. Higher precedence binds more tightly. `prefix` names a
unary function. Binary operator targets are curried: `left + right` calls
`add left right`. Ordinary eager operands are evaluated once, left to right. The
example lookup uses the left operand's type; it does not search both operands or
unrelated modules for an overload.

The executable prelude defines low-precedence function application in source:

```blot
infixr 0 ($) = apply
const apply = fn function => fn value => function value

const answer = fn () => U32.mul 2 $ U32.add 1 $ 20
```

`f $ g $ x` means `f (g x)`. Precedence 0 is below arithmetic, comparisons and
default backtick fixities; ordinary application still binds tighter. Infix RHSs
may be lambdas, `do:` blocks or `case` expressions without parentheses, e.g.
`invoke $ fn value => value + 1`. This syntax works for source operators in
general, not through a special application opcode. Operands remain eager and
left-to-right, unlike Haskell's evaluation model, and callback effects propagate
through `apply`. The standalone `return $ value` form is still resolver-return
forwarding; `return f $ value` returns an ordinary application result.

The proposed `@type.of` queries the inferred static type without evaluating its
argument or constructing a runtime type object. Its `.add` lookup selects an
unbound associated function, so the receiver is still passed explicitly. This is
a restricted static lookup, not general type-valued computation or runtime
reflection. Generic definitions carry the inferred operation requirement and its
effects. The compiler checks that requirement at callers; a missing operation is
a type error. Aliases do not introduce separate dispatch identities.

Short-circuiting follows from demand-driven parameters, not from compiler
knowledge of particular operator spellings:

```blot
infixr 20 (||) = or
infixr 25 (&&) = and

const and = fn (left: Bool) => fn ~right => do:
  if left:
    return @force right
  return #False

const or = fn (left: Bool) => fn ~right => do:
  if left:
    return #True
  return @force right
```

`and condition expression` has the same demand behavior as
`condition && expression`. The parameter mechanism works for any source
function, including lazy fallbacks and conditional computations. The generic
`add` wrapper, by contrast, has eager parameters and cannot become lazy merely
because a selected associated operation has a deferred parameter.

Fixity import/export rules, conflicting declarations, and the prelude-loading
policy remain open. The showcase colocates library definitions with game code
for review; it does not authorize foreign extensions of primitive types.
Punctuation such as `:`, `=>`, `->`, effect binding `<-`, return forwarding
`return $`, and successor rebinding `:=` remains syntax, not an ordinary
function-call operator. The separate postfix `?` propagation sketch is
unsettled: its eventual encoding must meet the source-defined rule rather than
introducing a hardcoded operator exception.

### Backtick infix calls

A plain or qualified function name between backticks can be used in infix
position, following the
[Haskell spelling](https://www.haskell.org/onlinereport/haskell2010/haskellch3.html):

```blot
left `combine` right       // combine left right
position `Vec2.dot` offset // Vec2.dot position offset
left `math.combine` right // math.combine left right
```

This is exactly ordinary curried application, not a tuple call, implicit method
receiver, or a wrapper function. The callee resolves like an ordinary name,
including a local function value or parameter. Its argument types, effects,
evaluation order, and demand modes are unchanged. In particular,
``#False `and` expensive ()`` does not force the second argument when `and` has
a `~right` parameter. Bind possibly effectful call results with `use`, as usual.

The default fixity is left-associative precedence 80, between the showcase's
multiplication at 70 and prefix operators at 90. Function application, field
access, and indexing bind more tightly than infix calls. Without a named fixity:

```blot
f x `combine` g y           // combine (f x) (g y)
a `combine` b `combine` c   // combine (combine a b) c
```

An optional named header changes that binding's infix fixity. It belongs after
imports with the symbolic operator headers; it introduces neither a new function
nor a symbolic alias, so there is no `= target`:

```blot
infixl 60 `add`
infixr 24 `and`
infixl 10 `on`

const on = fn combine => fn project => fn left => fn right =>
  combine (project left) (project right)

const closer_to_origin = lt `on` Vec2.magnitude
```

With these headers, ``1 `add` 2 * 3`` means `add 1 (2 * 3)`. The `on` example
builds a function comparing two positions by their magnitudes; `on` is ordinary
source code, not a compiler-recognized combinator. Since application binds
tighter, call the result as `closer_to_origin first second` or
``(lt `on` Vec2.magnitude) first second``.

Named fixity is metadata for a lexically resolved binding, not a runtime
property of a function value. Passing or selecting a function cannot change
parsing; a new local alias uses the default fixity. A symbolic declaration such
as `infixl 60 (+) = add` does not implicitly set the fixity of backtick `add`:
several symbols may call that function with different fixities. Explicit named
headers preserve both predictable parsing and optional control over grouping.

Mixed operators at equal precedence require parentheses unless all are
left-associative or all are right-associative. Non-associative `infix` headers
reject unparenthesized chaining. These rules apply to symbolic/backtick mixtures
as well as repeated uses of one operator. Fixity import/export policy remains
part of the existing module-design work.

Initially, the backticks contain a function name, not an arbitrary expression.
Bind a composed or partially applied function first. Infix sections with an
omitted operand are deferred; use ordinary partial application or an explicit
`fn` instead. The compiler lowering target is the same call as prefix notation,
with no additional runtime dispatch mechanism.

## Text interpolation

Double-quoted text supports `${expression}` interpolation:

```blot
const greet = fn (world: Text) -> Text => "Hello ${world}"
const quoted_greeting = fn (world: Text) -> Text => "Message: ${greet world}"
```

Evaluate embedded expressions once, from left to right. Braces and quoted text
inside an embedded expression must be parsed as expression syntax, not as a
search for the next `}` character.

Proposal: insert `Text` directly and require a statically resolved `to_text`
operation for other types, including built-in numbers. This would reuse the
associated-operation mechanism without implicit conversion elsewhere:

```blot
// PROPOSAL: numeric and user-defined interpolation conversions.
const Vec2.to_text = fn (value: Vec2) -> Text => "(${value.x}, ${value.y})"
const position_label = fn (position: Vec2) -> Text => "Position: ${position}"
```

Missing conversions would be compile-time errors. Embedded-expression and
conversion effects contribute to the containing function's effects. Constructing
text may allocate; interpolation is not an allocation-free formatting promise.
The proposed escape `\${world}` would produce literal `${world}` text; exact
escaping and formatting options remain open.

## Immutable rebinding and self

All source values are immutable. `:=` advances a local binding to a successor
value, preserving the target's type. It does not change earlier values.

`self` names the previous value of the exact left-hand target during evaluation
of the rebinding's right-hand side.

```blot
score := self + 10
player.position.x := self + dx
particles[index] := advance (self, dt)
world.particles := array.map (step_particle, self)
```

| Left-hand target    | Value named by `self`   |
| ------------------- | ----------------------- |
| `score`             | Previous score          |
| `player.position.x` | Previous x coordinate   |
| `particles[index]`  | Previous array element  |
| `world.particles`   | Previous particle array |

A path update constructs a successor of its root and rebinds that root:

```blot
let position = Vec2 { x: 1.0, y: 2.0 }
let original = position

position.x := self + 5.0

// original.x is 1.0; position.x is 6.0.
```

The rules for `self` are:

- It is introduced only by the right-hand side of a rebinding.
- The old root, target path, and index expressions are resolved once before the
  right-hand side, with index expressions evaluated from left to right.
- It refers to the old target value throughout that right-hand side.
- A nested rebinding introduces its own `self`.
- It is a lexical binding. Closures capture that old value subject to ordinary
  ownership rules; they do not obtain a reference to a future binding version.

There is no mutable-source update model: no `let mut`, `&mut`, compound
assignment such as `+=`, or `Mut` effect for these transformations. Read-only
borrowing and ownership can still control storage reuse without permitting
observable mutation.

## Arrays, performance, and game state

Arrays are homogeneous, contiguous values with first-class construction,
indexing, and transformation operations. `Array Vec2` can store inline `Vec2`
elements.

Immutable semantics permit reuse of backing storage when no earlier value can
observe the update. If an earlier version remains accessible, the implementation
must preserve it. Updating a flat contiguous array may then require copying.
`self` does not establish uniqueness or guarantee allocation-free execution.

Game update functions produce the next world:

```blot
data Particle = Particle {
  position: Vec2,
  velocity: Vec2,
}

data World = World { particles: Array Particle }

const advance = fn (particle: Particle, dt: F32) => do:
  let next = particle
  next.position.x := self + particle.velocity.x * dt
  next.position.y := self + particle.velocity.y * dt
  return next

const update = fn (world: World, dt: F32) => do:
  let next = world
  next.particles := array.map (fn particle => advance (particle, dt), self)
  return next
```

The engine installs the returned world after an update. Hot reload replaces the
code used for later frames while preserving compatible state. State-layout
changes need migration or reset; a failed build must leave the last successful
game available. Detailed runtime linking, activation, and migration contracts
remain to be designed.

Effects and allocation costs still need explicit contracts. Immutability alone
does not establish purity of calls to external capabilities or absence of
allocation. A compiler may lower array transformations to direct loops and reuse
storage where the ownership analysis permits it.

## Const-time programming and declaration tags

`const` requires a compile-time initializer. `let` and `use` evaluate in the
current stage: normally runtime, or const time inside a const evaluation. `let`
requires a pure RHS; `use` preserves any effects rather than allowing them to
escape the stage's restrictions. Ordinary functions can run in either stage when
their operations permit it; a separate class of `const fn` is unnecessary for
the baseline. A const-known function closure does not execute its body and may
describe an effectful runtime system.

Types and resolved effect descriptors are const-time values. Types may depend on
const-known arguments, not arbitrary runtime values. `@type.of value` bridges a
checked expression to its static type without evaluating that expression. Type
descriptors do not imply runtime reflection or runtime allocation.

Proposed const-parameter spelling:

```blot
const vector_type = fn (const element: Type) => fn (const lanes: U32) -> Type =>
  @type.simd (element, lanes)

type F32x4 = vector_type F32 4
```

Const evaluation must be deterministic and bounded, with no ambient filesystem,
clock, network, or randomness. Cache keys must track every observed dependency.
Reflection on unsolved type/effect variables is not allowed; cyclic dependencies
between inference and const-generated declarations must receive a diagnostic.

Value declaration tags use `#[expression]` and apply an ordinary function to the
declaration's initializer:

```blot
const add = fn amount => fn value => value + amount
#[add 1]
#[fn value => value * 2]
entry const answer: U32 = 20 // add 1 (multiply 2 20) = 41
```

Tags may appear on separate lines or the declaration line. The nearest tag
applies first, and an annotation constrains the final decorated value. Tag
expressions resolve in the declaration's module scope, including named and
qualified imports. A tagged `const` runs its decorators at compile time under
the normal budget; a tagged `let` runs them once at module startup. Tag and
initializer references participate in reachability and incremental keys. Direct
self-reference in a tagged declaration is rejected explicitly. Tags on types,
effects, and fixity declarations still receive `unsupported_attribute`;
declaration-descriptor transforms and generated definitions remain a proposal.

## ECS as a type/effect test case

The ECS design below remains a proposal. The executable
[ECS example](examples/ecs.blot) uses const-composed world storage, generic
component columns, scoped state effects, and explicit system iteration.

In the proposed design, systems infer component/resource use through ordinary
helpers. A const-time `ecs.build` inspects **checked, closed effects**, not
function bodies or names, to determine storage and query requirements. Demanded
computations and generic helper calls must retain their effects when that
machinery is implemented.

`get` and `set` are effectful operations, not privileged function names for the
scheduler to search for. Getting T performs Read T; setting a T value performs
Write T; inserting one performs the distinct Insert T effect. These compose
through calls, while the engine supplies their interpretation for the current
entity/world. This does not change the immutability of ordinary values.

The proposed scoped runner receives that context explicitly:

```blot
const read_velocity = fn () => do:
  use velocity <- ecs.get Velocity
  return velocity

const sample_velocity = fn (world, entity) =>
  ecs.run (world, entity, read_velocity)
```

`ecs.run` invokes the action under a provider for this world and entity and
returns `(next_world, result)`. Component operations target the current entity;
resource operations target the world. `set` advances the provider's state, so
later reads in that scope see the new value without changing previously obtained
values or the input world. There is no implicit global world. The runner must
establish the required entity/component presence; it must not invent missing
values. The exact runner API and validation mechanics remain a library proposal.

Generated `game.update world` supplies the provider while iterating the selected
systems' entity queries and returns the next world. `ecs.build` inspects system
effects **before** these runners handle them, preserving scheduling
dependencies. A runner handles only its ECS effects; any other effects still
propagate. An executable boundary with unresolved provider requirements must
fail. Effectful helpers can still be inferred and checked without executing
them.

The earlier compiler-coupled ECS bootstrap was retired: its `@ecs.*` and
platform intrinsics, component/resource special cases, generated storage/query
plans, and `compileEcs`/`compileApp` entry points have been removed. Experiments
are preserved only in
[the prototype archive](case-study/ecs/prototype/README.md). They are not a
substitute for generic language machinery.

Source-library scheduling should derive hazards from checked descriptors. Reads
may share a batch, writes conflict with overlapping reads/writes, and structural
changes need an explicit engine contract. These are library rules, not compiler
knowledge. Component registration/query membership must not invent values or
silently attach components.

Nominal identity must remain stable across imports and rebuilds, using the
defining module and declaration identity rather than fresh allocation order.
Aliases retain the underlying identity. Descriptor availability precedes system
inference; closed system effects precede const world/schedule generation; the
generated code must then be checked before backend lowering. Inference must not
ask a world generated from its own unfinished effects to supply those effects.

Code-only reloads may reuse compatible schemas/query plans while updating system
implementations. Layout/ABI changes still require explicit migration or reset.
The generic compiler kernel supports scoped providers and const effect
descriptors; it does not yet implement declaration transforms or the proposed
effect-descriptor-derived world and query generation.

## SIMD boundary

Start with explicit native 128-bit vector shapes, such as F32x4, I32x4, and
F64x2. Associated source functions can expose vector intrinsics to the same
operator dispatch used by scalar types. These are vector representations, not
boxed records or a replacement for first-class arrays.

Array loads/stores need explicit bounds and ownership contracts. Immutable
semantics still apply; SIMD does not authorize overwriting observable old array
values. Relaxed SIMD should be opt-in, and automatic vectorization is not a
baseline requirement. Intrinsic names, supported lane/type combinations, and
deterministic floating-point guarantees need a separate specification.

## Remaining choices

These are not settled by the baseline above:

- Const-parameter spelling, declaration-transform APIs, reflection APIs, and
  evaluation budgets/caching policy.
- Constructor payload arity, namespace/import rules, and opaque exports.
- Whether to add structural/anonymous records or payload-free `#tag` atoms.
- The precise inference boundary, exported-signature requirements, and supported
  forms of polymorphism.
- The closed-union storage/call ABI and further generic matching support.
- Effect declarations, row notation, concrete provider adapters and runner APIs,
  resolver ownership/lifetimes, and how allocation costs are checked when
  implementations reuse storage.
- Ownership, sharing, borrowing, copying APIs, and storage-reuse guarantees.
- Fixed-size arrays, slices, numeric defaults, and bounds/overflow behavior.
- Rebinding scope and how branches and loops carry successor bindings.
- Operator header import/export and conflict rules, prelude loading, and the
  exact spelling and limits of static associated-function lookup.
- Ownership and optimization guarantees for demand captures beyond the current
  memoized `~T` implementation.
- Named-function recursion, forward references, and any local named definitions.
- Further associated-function receiver inference and import visibility beyond
  the implemented static member calls and inferred operation constraints.
- Interpolation conversions, literal interpolation escaping, and formatting.

Predicate refinement solving, unrestricted compile-time effects, general
resumable effect handlers, and automatic migration of live execution stacks were
proposed for deferral. They are not implemented here. In particular, the old
`refine` was a prelude function backed by an intrinsic, not a dedicated grammar
production.

## Implementation status

The repository contains a Deno project, Baba 9.0.1, generated lexer/parser
artifacts, and a [Bend compiler](compiler/README.md). The executable
`grammar.baba`/`baba.json` describe the generic functional core plus recognized
resolver syntax with explicit unsupported-lowering diagnostics. They no longer
claim to accept the old Blot language. The broader syntax design is preserved
here and in the case-study source proposals. Files under `examples/` use the
currently supported language.

A separate, permissive Tree-sitter grammar supports Helix highlighting of the
showcase, including proposals. It is editor support, not a validating compiler
frontend; see the [Helix setup](README.md#helix-highlighting).

| Area                    | Current status                                                                                                                               |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Deno and Baba           | Generated lexer, general CPU parser, compact-CST schema, and binding checks.                                                                 |
| Helix highlighting      | Separate editor grammar covers the syntax showcase.                                                                                          |
| Annotations             | Scalars, tuples, arrays, concrete applied nominal types, and effect-annotated arrows.                                                        |
| Modules                 | Implicit prelude; relative/explicitly mapped file imports; module scopes; public top-level bindings.                                         |
| Data declarations       | Generic `data` with mandatory `#Constructor` markers in declarations, values and patterns; no `type` aliases yet.                            |
| Pattern narrowing       | Single/multi-value `case … of`, alternatives and guards, nested tuple/record patterns, `if let`, guarded `let`.                              |
| Closed unions           | Design/editor examples only; no union inference or runtime representation.                                                                   |
| Operators and demand    | Source fixities/operators backed by ordinary functions; memoized `~` parameters and `@force`.                                                |
| Backtick calls          | Ordinary curried function calls with source fixity/default left precedence 80.                                                               |
| Named functions         | Unary/curried functions, closures, static qualified names, recursive groups.                                                                 |
| Text interpolation      | Target design only; literal strings currently serve generic panic messages.                                                                  |
| `self`                  | Previous value of a local binding or field/index path during immutable rebinding.                                                            |
| Layout and AST          | Indented continuations, a structure-preserving formatter, Baba CST; Bend name resolution and core lowering.                                  |
| Types and effects       | Rank-1 HM with inferred latent effect rows and source-declared operations.                                                                   |
| Bindings                | Pure-RHS `let`, effect-preserving `use … <- …`; `use expression` discards.                                                                   |
| Resolver blocks         | Scoped effect providers execute; monad resolvers and `return $` remain future.                                                               |
| Scheduling              | Source-library responsibility; no compiler-generated ECS scheduler.                                                                          |
| Const evaluation        | Scalars, tuples, arrays, data, closures, and matching with one shared evaluation budget.                                                     |
| Tags and const types    | Expression tags transform `const`/`let` values; closed const effect descriptors; no declaration-descriptor transforms or type-valued consts. |
| Arrays and SIMD         | Immutable arrays, checked indexing, alias-preserving updates with local storage reuse; SIMD remains future.                                  |
| Wasm compilation        | Private arena; scalars, copied numeric arrays, and explicit scalar callbacks via guest ABI 2.                                                |
| Game runtime and reload | Sandbox paused pending source ECS, capability bundles and persistent-state ABI.                                                              |

`generated/wasm` belongs to Baba's lexer/parser tooling. Separately, `just demo`
compiles [examples/prelude.blot](examples/prelude.blot) and executes it as Wasm.
[The generic effects example](examples/generic_effects.blot) tests scoped
providers, effectful callbacks, and closed compile-time reflection.
`just bench-native` measures the generic core's full builds, declaration edits,
and cache reuse; historical ECS numbers do not describe this new boundary.

[Explicit host callbacks](examples/host_io.blot) execute with a sealed `Foreign`
effect; `just demo-host` tests a host-backed provider and a pure source mock.
[Guest ABI 2](compiler/guest-abi.md) scopes opaque callback references to one
instance and invocation and copies numeric arrays across the host boundary.
Other composite host values and persistent guest handles remain future work. The
ABI does not settle persistent game state or hot-reload schema migration.
