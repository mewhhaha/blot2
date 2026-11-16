# Blot language specification: syntax

Draft of 14 November 2026, third revision.

This document states what Blot source text is expected to look like and mean:
what a compiler must accept, what it must reject, and the meaning a reader may
rely on. It does not describe any compiler. [The guide](guide.md) describes
what the current compiler does.

## 1. Scope and status

The specification covers the lexical grammar, the syntactic grammar, the
static rules that reject a module, and the dynamic errors that stop a program.
It leaves out the Wasm ABI, type layouts, the standard library, diagnostic
wording and compile speed.

The owner's decisions are recorded in
[the coherence list](../../tasks/LANGUAGE_COHERENCE.md) and
[the memory model](../../tasks/MEMORY_MODEL.md). When this document disagrees
with them, they are right and this document is corrected.

Each rule has one of three statuses:

- **Unmarked.** The language does this today and keeps it.
- **(approved)** The owner approved it. The compiler may not implement it yet.
- **(open)** Approved in substance, but a spelling or detail is undecided. The
  text uses an illustrative spelling, and
  [Annex B](#annex-b-open-spellings-and-questions) lists the question.

The second revision adds the twelve changes the owner approved after reading
the first draft. [Annex A](#annex-a-removed-forms) labels them "round 2".
[Annex C](#annex-c-considered-and-declined) lists ideas that were considered
and declined.

The third revision removes mutation. The owner's instruction: "remove 'real'
mutation from the spec. Just immutable and then our goal is to reuse as much
memory as possible." The store statement `place = value`, `Cell` and
`is root` are gone, and section 10.3 states the reuse rules. The memory model
file predates this decision, and here this document is the newer one.

The same revision restores `use`, which the first approvals had dropped. The
owner: "I would differentiate effects with `use x <- my_effect ()` so that we
can organize it easier and optimize it." Section 10.10 has the rule.

Terms:

- **Error**: the compiler rejects the module and produces no output.
- **Trap**: execution of the current host invocation stops. A program cannot
  catch a trap.
- **Owns**: a local owns an array when no other name, value or lambda holds
  that array (section 10.3).

## 2. Rules the syntax obeys

A change to the language must keep these.

1. **A module parses without knowing any declaration.** The operator table is
   fixed, the first letter of a name decides its class, and no declaration
   changes how later text parses.
2. **A module's interface is known after parsing.** Every module-level
   declaration starts with a keyword and writes its full name and type.
   Compile-time evaluation fills in bodies and never produces a name or a
   type.
3. **One spelling per meaning.**
4. **Nothing is mutated.** Every value is immutable, arrays included. `:=`
   gives a name a new value, and no code can observe another piece of code
   changing a value it holds.
5. **Cost is visible.** The compiler reuses memory and never copies an array
   on its own: an update it cannot make in place is an error. There is no
   implicit numeric conversion.
6. **One meaning per program.** A program behaves the same in every build
   mode. Checks that trap are part of the meaning.
7. **Effects are visible.** A call with effects is written with `use`.
   Every other expression is pure: it gives the same value wherever and
   however often it is evaluated.

## 3. Notation

Productions use this form:

```
Name     = Alternative | Alternative
"text"     a terminal
A?         optional
A*         zero or more
A+         one or more
A,+        one or more, separated by ","  with an optional trailing ","
A,*        zero or more, separated by "," with an optional trailing ","
```

`NEWLINE`, `INDENT` and `DEDENT` are the layout tokens of section 4.2. A
`Suite` is `NEWLINE INDENT Statement+ DEDENT`.

## 4. Lexical grammar

### 4.1 Source text

A module is one UTF-8 file. Outside string literals and comments, only ASCII
characters are allowed. A line ends at LF or CR LF.

### 4.2 Layout

Blot has no braces around suites and no statement terminators.

- The first token of a module starts in column 0.
- Indentation is made of spaces. A tab in indentation is an error.
- **Suite.** A line that ends in `:`, `of` or `=>` opens a suite. The next
  line must be indented further than the line that opened it. The lines at
  that indentation are the suite's items, and the first line indented less
  closes it. A closing line must match the indentation of an enclosing suite.
  The `=>` case is **(approved)**; today `=>` continues the expression.
- **Continuation.** A line indented further than the current suite's items
  continues the item above it. A line that starts with `|` at the same
  indentation as the item above it also continues it.
- **Brackets.** Line breaks inside `( )`, `[ ]` and `{ }` separate nothing,
  except inside a suite opened within the brackets.

### 4.3 Comments

`//` starts a comment that runs to the end of the line. There are no block
comments.

### 4.4 Names

```
LowerName = [a-z_] [a-z0-9_]*
UpperName = [A-Z] [A-Za-z0-9_]*
```

A `LowerName` names a value, a function, a field, a module alias or a type
variable. An `UpperName` names a type, a trait, an effect or a constructor. A
constructor is always written with its marker: `$Some`. `_` alone is not a
name: it is the wildcard in a pattern and a hole in an expression.

### 4.5 Keywords

Reserved everywhere:

```
and  as  break  case  const  continue  data  effect  else  ever  false  for
func  if  import  in  is  let  not  of  or  return  then  true  type  use
with
```

`not` and `with` are **(approved)**.

Reserved only in the position that gives them meaning, and ordinary names
elsewhere: `opaque` and `trait` after `is`; `private`, `entry` and `export`
at the start of a module item; `from` in an import; `where` after a
signature; `self` on the right of `:=`; `own` before a parameter's type.

These words stop being keywords **(approved)**: `do`, `yield`, `complete`,
`infix`, `infixl`, `infixr`, `contract`, `impl`.

### 4.6 Literals

```
Integer = Digit ("_"? Digit)* | "0" ("x" | "X") Hex ("_"? Hex)*
Float   = Digits "." Digits Exponent? | Digits Exponent
Exponent = ("e" | "E") ("+" | "-")? Digits
String  = '"' (Character | Escape)* '"'
Escape  = '\"' | "\\" | "\n" | "\r" | "\t"
```

- **(approved)** An integer literal takes the integer type expected where it
  appears, and `U32` when nothing expects one. A float literal takes the
  expected float type, and `F32` otherwise. An integer literal is never a
  float.
- A literal outside its type's range is an error.
- A string literal stays on one line and has type `Text`.
- `true` and `false` have type `Bool`. `()` is the one value of type `Unit`.

### 4.7 Punctuation

Each mark has one role in each of the three grammars.

| Mark | In expressions and statements | In types | In patterns |
| --- | --- | --- | --- |
| `.` | member of a module, type or value | member of a type | |
| `..` | range | | |
| `:` | suite opener; annotation; field | annotation; field | field |
| `=` | definition | definition; default | |
| `:=` | rebinding | | |
| `->` | parameter separator | function type | |
| `=>` | body | | arm body |
| `<-` | generator; result of a `use` | | |
| `$` | constructor | | constructor |
| `&` | reference to a place; bitwise and | read-only reference | |
| `^` | link to an element; bitwise xor | link | match an existing name |
| `\|` | bitwise or; comprehension bar | row tail; data alternative | alternative |
| `!` | | effect row | |
| `#` | compile-time form | | |
| `@` | intrinsic (std only) | tag | |
| `_` | hole | | wildcard |

### 4.8 Adjacency

Whitespace is significant in exactly these places:

- `$` touches its constructor name.
- `#` touches `run`, `type`, `quote` and `(`. `@` touches its name or `[`.
- A prefix `&` or `^` touches its operand.
- `[` that touches the expression before it is an index: `rows[i]`. After a
  space it starts an array literal, so `f rows [i]` passes two arguments.
- **(approved)** A `-` that follows an operand is subtraction, except when it
  has whitespace before it and none after. Then it starts a new, negated
  argument: `f -1.0` is `f (-1.0)`, and `a - b`, `a-b` and `a -  b` are
  subtractions.
- A line that starts with `.name` continues the expression above it
  (section 9.4). A space before a dot in the middle of a line means nothing.

Adjacency of `(` means nothing: `f(x)` is `f (x)` **(open)**.

## 5. Modules

```
Module     = Import* Item*
Import     = "import" "*" "as" LowerName "from" String
           | "import" "{" ImportName,+ "}" "from" String
ImportName = Name ("as" Name)?
Name       = LowerName | UpperName
Item       = Reexport | Tag* "private"? "entry"? Declaration
Reexport   = "export" "{" ImportName,+ "}" "from" String
Declaration = FuncDecl | ConstDecl | LetDecl | TypeDecl
```

- Imports come before every other item. A path may leave out `.blot`.
- An import cycle is an error.
- A declaration is public unless it is marked `private`. Constructors and
  operations have the visibility of their type.
- Importing a type does not import constructors that have another name.
- A public signature that names a private type is an error.
- `entry` may precede `func`, `const` or `let`. The entry module's entry
  declarations are the program's exports, under their own names, and nothing
  else is exported. Only the module being compiled may declare entries, and
  it must declare at least one.
- A module-level name is declared once. There are no overloads **(approved)**.

## 6. Declarations

### 6.1 Functions

```
FuncDecl  = "func" ValuePath Param ("->" Param)* ":" Type ("!" EffectRow)?
            Where? "=>" Body
ValuePath = (UpperName ".")* LowerName
Param     = "(" ")" | "(" Pattern ":" "own"? Type ")"
Body      = Expression | Suite
```

- Every parameter and the result are annotated **(approved)**.
- `own` marks a parameter the function takes over (section 10.3)
  **(approved)**.
- `->` separates parameters. A function takes them one at a time:
  `func add (left: U32) -> (right: U32): U32` has type `U32 -> U32 -> U32`,
  and `add 2` is a function.
- A parameter pattern must match every value of its type.
- Parameter names are local. They are not part of the function's type.
- `func Vec2.add …` declares `add` in the namespace of the type `Vec2`. Only
  the module that declares a type may add functions to its namespace.
- **Body (approved).** `=> expression` returns the expression's value.
  `=>` at the end of a line opens a suite. The suite returns with `return`,
  and reaching its end returns `()`. Reaching the end of a suite whose
  function's result type is not `Unit` is an error.
- Module-level functions may refer to each other in any order.

### 6.2 Constants and module-level `let`

```
ConstDecl = "const" ConstPath (":" Type Where?)? "=" Expression
ConstPath = (UpperName ".")* Name
LetDecl   = "let" LowerName (":" Type)? "=" Expression
```

- A `const` is evaluated at compile time. Its expression has no effects and
  cannot read a module-level `let`.
- A module-level `let` is evaluated once when the module starts, in
  dependency order. A dependency cycle is an error.
- `const Type.name` declares a member in a type's namespace.

### 6.3 Types

```
TypeDecl   = "type" TypeHead "=" Type
           | "type" TypeHead "is" "data" "=" "|"? Constructor ("|" Constructor)*
           | "type" TypeHead "is" "opaque" "=" Type
           | "type" TraitHead "is" "trait" "=" RecordType
           | "type" TypeHead "is" "effect" "=" RecordType
TypeHead   = TypeName TypeParams?
TypeName   = (UpperName ".")* UpperName
TypeParams = LowerName | "[" LowerName,+ "]"
Constructor = Tag* "$" UpperName (TypeAtom | "{" DataField,* "}")?
DataField  = Tag* LowerName ":" Type ("=" Expression)?
```

- **Alias.** `type Name = Type` adds a name and nothing else. A recursive
  alias is an error.
- **Data.** A nominal type with one or more constructors. A constructor has
  no payload or one; several values go in a tuple or in named fields.
- **Field defaults (approved).** A named field may have a default:
  `$Config { volume: F32 = 1.0, muted: Bool = false }`. A construction may
  leave such a field out, and the default is then evaluated at that
  construction. A default has no effects and may name only module-level
  declarations, never a sibling field or a local.
- **Opaque.** A nominal type with one private constructor of the same name.
  Only the declaring module can construct or match it.
- **Type parameters (approved).** One name, or a bracketed list of names:
  `type Tree a`, `type Result [value, error]`. An application mirrors it:
  `Tree U32`, `Result [U32, Text]`.
- **Type members (approved).** `type Pool.Id = U32` declares the type `Id` in
  the namespace of `Pool`. Only the module that declares `Pool` may do so.

### 6.4 Traits

**(approved)**

```
TraitHead   = UpperName LowerName ("{" LowerName,+ "}")?
Where       = "where" "{" Predicate,+ "}"
Predicate   = TypePath TypeAtom OutputTypes?
OutputTypes = "{" OutputType,+ "}"
OutputType  = LowerName ":" Type
```

```blot
type Eq a is trait = { eq: a -> a -> Bool }
type Collection c { item } is trait = { length: c -> U32, at: c -> U32 -> item }
type Mul left { right, out } is trait = { mul: left -> right -> out }

const U32.Eq: Eq U32 = { eq: U32.eq }
const Array.Eq: Eq (Array a) where { Eq a } = { eq: equal_array }
const Array.Collection: Collection (Array a) { item: a } =
  { length: Array.length, at: Array.at }
const Vec3.Mul: Mul Vec3 { right: F32, out: Vec3 } = { mul: Vec3.scale }

func member (values: Array a) -> (wanted: a): Bool where { Eq a } => ...
func first (values: c): Maybe c.item where { Collection c } => ...
func square (value: a): a where { Mul a { right: a, out: a } } => value * value
```

- A trait is a nominal record type. Its parameter is the type it dispatches
  on. The names in braces are its outputs: the dispatch type determines
  them. Outputs are written by name wherever the trait is applied, so a
  trait application never contains `->`.
- The implementation of trait `T` for type `X` is the constant `X.T`. Its
  type is `T X`, with every output given. There is no other way to implement
  a trait, so a type has at most one implementation of each trait.
- `X.T` may be declared in the module that declares `X` or the module that
  declares `T`. Anywhere else is an error.
- **Identity.** The name after the dot is resolved as a trait in the
  declaring module's scope, and the implementation is recorded under that
  trait, not under its spelling. Two traits that share a name do not collide.
  A module that imports both renames one in its import and uses that name.
- An implementation for a generic type may have its own `where` clause.
- `where { T a }` on a function is an argument the compiler supplies. At
  each use it must find `X.T` for the concrete `X`, or the same predicate in
  the caller's own `where` clause. Otherwise the use is an error.
- A predicate is a trait applied to a type, with any outputs it wants to
  fix, and nothing else.
- On a type variable `c` with `where { Collection c }`, `c.item` names the
  trait's output. If two predicates on `c` offer the same output name, the
  name must be qualified: `Collection.item c`.
- No trait record exists at run time unless the program passes one as an
  ordinary argument.

### 6.5 Effects

**(approved)**

```blot
type Log is effect = { write: Text -> Unit }
type State a is effect = { get: Unit -> a, set: a -> Unit }

func report (count: U32): Unit ! {Log} =>
  use Log.write "started"

const quiet: Log = { write: func text => () }

entry func main (): Unit =>
  with quiet:
    use report 3
```

- An effect is a nominal record type whose fields are functions, called its
  operations. Declaring one grants nothing.
- A **provider** is any value of the effect's type. It is built like any
  record and may be a constant, a local or a parameter.
- `Log.write text` calls the `write` of the provider in scope. A function
  that calls an operation with no provider installed around the call has the
  effect in its row: `! {Log}`.
- `with provider:` installs a provider for its suite (section 10.9).
- A trait is a record the compiler finds by type at compile time. An effect
  is a record the program finds by scope at run time. Both have the same
  explicit form: take the record as a parameter and call its fields, as in
  `log.write text`, which needs no row.
- `Foreign` is the one built-in effect. It marks host callbacks. Source
  cannot declare or provide it.

**State (approved; spellings open).** The prelude declares one effect,
`State a`, whose operations and provider are built in:

```blot
State.get:    Unit -> a ! {State a}
State.set:    own a -> Unit ! {State a}
State.modify: (own a -> a) -> Unit ! {State a}
State.read:   (a -> b) -> b ! {State a}

func count (items: Array Item): U32 =>
  let total = 0
  with State.new 0:
    use visit items
    use seen <- State.get U32 ()
    total := seen
  return total
```

- `State.new initial` gives a provider that keeps one value for the `with`
  that installs it.
- `modify` hands that value to its function as `own` and keeps the result,
  so state that holds an array is updated in place.
- `read` lends the value to its function, as a borrowed parameter. The
  result cannot hold an array of the state without `values.copy`
  **(open)**.
- `get` is allowed only when the state's type holds no array. For a type
  that may hold one, type variables included, `get` is an error that points
  to `read` **(open)**. Otherwise `get` would hand out a second holder of
  an array that `modify` changes in place.
- The meaning is state passing: the program behaves as if every function
  called under the `with` took the state and returned it. No value that a
  name holds ever changes.
- A program cannot write this provider itself, because nothing else in the
  language keeps a value between calls.

### 6.6 Tags

**(approved)**

```
Tag = "@[" Expression "]"
```

```blot
type Save is data = $Save {
  @[codec.since 3] stamina: F32 = 1.0,
  position: Vec3,
}
```

- A tag attaches a compile-time constant to the type declaration,
  constructor or field that follows it.
- `#type` shows the tags of what it describes (section 11). A tag changes
  nothing else about the program.
- A tag anywhere else is an error, because nothing could read it.

## 7. Types

```
Type       = "own"? TypeApply "->" Type ("!" EffectRow)? | TypeApply
TypeApply  = TypePrefix (TypeArg OutputTypes?)?
TypeArg    = TypePrefix | "[" Type,+ "]"
TypePrefix = "&" TypePrefix | "&" "[" Type "]" | "^" TypePrefix | TypeAtom
TypeAtom   = TypePath
           | LowerName ("." LowerName)?
           | "(" Type ")"
           | "(" Type "," Type,+ ")"
           | RecordType
TypePath   = (LowerName ".")? UpperName ("." UpperName)*
RecordType = "{" FieldType,* "}"
FieldType  = LowerName ":" Type
EffectRow  = "{" EffectLabel,* ("|" LowerName)? "}"
EffectLabel = TypePath TypeArg?
```

- `->` associates to the right. A function type as a parameter needs
  parentheses.
- `! {…}` follows the result of the arrow it belongs to and lists the
  effects of calling that function. No `!` means no effects. A label is an
  effect applied to its argument: `{Log, State U32}`. `{Foreign | e}` leaves
  the rest of the row open, and `e` is a row variable. A name used as both a
  type variable and a row variable in one signature is an error.
- A lowercase name is a type variable, shared across one declaration's
  signature.
- A type takes one argument or a bracketed list, matching its declaration.
  Braces after the argument give a trait's outputs (section 6.4); braces in
  place of the argument are a record type.
- Record types are structural, and field order does not matter. Records are
  closed: a function cannot abstract over "any record with field `x`"
  **(approved)**.
- **Numbers (approved).** The integer types are `U8`, `U16`, `U32`, `U64`,
  `I8`, `I16`, `I32` and `I64`. The float types are `F32` and `F64`. No
  value converts to another numeric type unless the program calls a
  conversion.
- **Text (approved).** `Text` is `Array U8` holding UTF-8. Its length counts
  bytes.
- `own` before a parameter's type is part of the function type
  (section 10.3) **(approved)**.
- **Arrays.** `Array a` has a fixed length, `GrowArray a` can append, and
  `ResizeArray a` can also shrink. All three are immutable values: an
  append, like any update, gives a successor **(approved)**.
- **References.** `&a` refers to one value and `&[a]` to a range of an
  array, without copying it. `^a` is a link to an element of a stable pool.
  While a reference to an array is in use, the array has another holder.

## 8. Patterns

```
Pattern      = "$" CtorPath PatternAtom? | PatternAtom
PatternAtom  = "_" | LowerName | Integer | "true" | "false" | "()"
             | "^" ValueName
             | "$" CtorPath
             | "(" Pattern ")"
             | "(" Pattern "," Pattern,+ ")"
             | "{" FieldPattern,* "}"
FieldPattern = LowerName (":" Pattern)?
CtorPath     = (LowerName ".")? UpperName
ValueName    = (Name ".")* LowerName
```

- A lowercase name binds a new local. `^name` instead compares against an
  existing integer or `Bool` local, parameter or constant.
- An integer pattern has the integer type of the value it matches.
- A constructor pattern with a payload must be parenthesized when it is
  itself a payload: `$Some ($Pair (a, b))`.
- A record pattern may leave fields out and list them in any order.
- A name bound twice in one pattern is an error.

## 9. Expressions

```
Expression = Lambda | IfExpr | CaseExpr | RunExpr | Operators
```

An expression never contains statements, except in the body of a lambda
**(approved)**. A value that takes several statements to compute is computed
by a function.

An expression is pure. The one place a call with effects may appear is a
`use` statement (section 10.10).

### 9.1 Operators

The table is fixed **(approved)**. Programs cannot declare operators or
change precedence. Weakest first:

| Level | Operators | Grouping |
| --- | --- | --- |
| 1 | `or` | right |
| 2 | `and` | right |
| 3 | `not` | prefix |
| 4 | `==` `!=` `<` `<=` `>` `>=` | none: `a < b < c` is an error |
| 5 | `\|` | left |
| 6 | `^` | left |
| 7 | `&` | left |
| 8 | `<<` `>>` | left |
| 9 | `+` `-` | left |
| 10 | `*` `/` `%` | left |
| 11 | `-` | prefix |
| 12 | application | left |
| 13 | `.name`, `[index]` | postfix |

- `and` and `or` take `Bool` operands and evaluate the right one only when
  needed. `not` takes a `Bool`. None of the three can be redefined.
- `not a == b` is `not (a == b)` **(open)**.
- The other operators call the member of a trait implemented for the left
  operand's type **(approved)**. The right operand's type is an output of
  the trait, so one type has one meaning for `*`.
- A prefix `-` at the start of an expression negates the application that
  follows: `-f x` is `-(f x)`. In argument position it follows the rule of
  section 4.8. It is defined for signed integers and floats.
- **Integers (approved).** `+`, `-` and `*` wrap at the type's width in
  every build. Division or remainder by zero traps, and so does dividing the
  smallest signed value by `-1`. A shift count wraps modulo the width, and
  `>>` copies the sign bit of a signed operand.
- **Floats.** Arithmetic follows IEEE 754 and can give infinity or NaN.

### 9.2 Application

```
Application = Postfix Postfix*
Postfix     = Primary ("." Name | "[" Expression "]")*
```

- `f a b` is `(f a) b`. Application binds tighter than every operator, and
  indexing and member access bind tighter than application:
  `f rows[i].x` passes one argument.
- Arguments are evaluated before the call, left to right.
- A lambda used as an argument is parenthesized:
  `values.map (func value => value * 2)`. Library functions take their data
  first and a function argument last **(approved)**.
- **Type arguments (approved).** A type may be passed where inference cannot
  choose: `State.get U32 ()`. A type argument is a type name, or a
  parenthesized type application such as `(Maybe U32)`.
- **Conversions (approved).** A numeric conversion is a member call on the
  value, such as `count.to_f32`. A conversion that can lose information is
  named for what it loses.

### 9.3 Primary expressions

```
Primary = Integer | Float | String | "true" | "false" | "()"
        | LowerName | UpperName | "self" | "_"
        | "$" CtorPath
        | "(" Expression ")"
        | "(" Expression "," Expression,+ ")"
        | "{" Field,* "}"
        | "[" Expression,* "]"
        | "[" Expression "|" Qualifier,+ "]"
        | "&" Postfix | "&" Postfix "[" Range "]" | "^" Postfix
        | "#type" TypeAtom | "#quote" Primary | "#(" Expression ")"
Field     = LowerName (":" Expression)?
Qualifier = Pattern "<-" (Range | Expression) | "let" Pattern "=" Expression
          | Expression
Range     = Expression ".." Expression
```

- **Constructors.** `$Some 42` applies a constructor. A constructor alone is
  a function, or a value when it has no payload.
- **Records.** `{ x: 1, y }` builds a record; `y` alone means `y: y`. Fields
  are evaluated in written order. An unknown or repeated field is an error,
  and so is a missing field that has no default.
- **Tuples.** `(a, b)` has two or more parts. They are read with patterns.
- **Arrays (approved).** `[1, 2, 3]` builds an array. The expected type
  chooses `Array`, `GrowArray` or `ResizeArray`; without one it is `Array`.
  An empty literal needs an expected type.
- **Comprehensions.** `[x * x | x <- values, x > 1]` builds an array.
  Qualifiers run left to right, the leftmost outermost. A `Bool` qualifier
  skips the rest when false. A generator draws from whatever `for` accepts
  (section 10.5), including a range **(approved)**: `[i * 2 | i <- 0..count]`.
  A bitwise `|` before the bar needs parentheses.
- **Ranges.** `start..end` counts up from `start` and stops before `end`.
  It is syntax, not a value: it appears in `for`, in a generator and in a
  range reference.
- **References.** `&place` refers to one value in an array,
  `&items[start..end]` to a range, and `^items[i]` to an element of a stable
  pool.
- `self` is defined only on the right of `:=` (section 10.2).

### 9.4 Members and chains

**(approved)**

A dotted path is parsed uniformly, and its first name decides the meaning:

1. a local or parameter: the rest are members of its value;
2. a module alias: the next name is a declaration of that module;
3. a type: the rest are members of its namespace.

A local shadows a module alias of the same name.

**On a type**, `Type.name` finds, in order: a function or constant declared in
the type's namespace, a type member (`Pool.Id`), an implementation
(`U32.Eq`), and for a concrete type the output of a trait it implements
(`(Array U32).item`).

**On a value**, `value.name` finds, in order:

1. a field of the value. For data with several constructors, every
   constructor must have the field;
2. a function in the namespace of the value's type that takes the value as
   its first parameter: `position.length` is `Vec3.length position`;
3. a member of a trait the type implements: `robot.eq other` is
   `Robot.Eq.eq robot other`. In a generic function this step looks only at
   the function's own `where` clause.

A field and a namespace function with the same name are an error where the
function is declared. A name that two traits supply must be qualified.

The receiver's type must be known at the dot. If it is not, the access is an
error that asks for an annotation.

A line that starts with `.name` continues the expression on the lines above
it:

```blot
let reach = robots
  .filter (func robot => robot.charge > 0.2)
  .map (func robot => robot.home.length)
  .fold 0.0 F32.max
```

Each such line applies to everything above it in the same expression. On one
line, parentheses do the same: `(values.filter keep).map double`.

### 9.5 Functions

```
Lambda      = "func" LambdaParam ("->" LambdaParam)*
              (":" Type ("!" EffectRow)?)? "=>" Body
LambdaParam = LowerName | "_" | "(" ")" | "(" Pattern (":" Type)? ")"
```

- A lambda's types are inferred where they are not written.
- A lambda captures the values of the locals it names at the point where it
  is created. A captured array is shared with the lambda, not copied, so
  the local no longer owns it.
- The body follows the rules of section 6.1.
- A local bound to a lambda may be generic (section 10.1).

### 9.6 Conditionals and matches

```
IfExpr   = "if" Expression "then" Expression "else" Expression
CaseExpr = "case" Expression,+ "of" NEWLINE INDENT Arm+ DEDENT
Arm      = PatternRow ("|" PatternRow)* ("if" Expression)? "=>"
           (Expression | Suite)
PatternRow = Pattern ("," Pattern)*
```

- A `case` evaluates its inputs once, left to right. Every arm has one
  pattern for each input.
- Arms are tried in order. Alternatives joined by `|` bind the same names
  with the same types.
- A guard that is false passes to the next arm. Guards do not count toward
  coverage.
- The arms must cover every value of the inputs. A match that is not
  exhaustive is an error.
- When the value of a `case` is used, every arm is an expression and all
  have the same type. An arm with a suite is allowed only in a `case` used
  as a statement, and a `return` in it leaves the function.

### 9.7 Holes

**(approved; spelling open)** `_` in an expression stands for one not yet
written. A module with a hole is an error, and the error reports the type
expected there and the locals in scope.

## 10. Statements

```
Statement = LetStmt | UseStmt | Rebind | IfStmt | CaseExpr | ForStmt
          | WithStmt
          | "return" Expression
          | "break"
          | "continue"
          | Expression
```

### 10.1 `let`

```
LetStmt = "let" Pattern (":" Type)? "=" Expression ("else" ":" Suite)?
```

- Without `else`, the pattern must match every value of its type.
- With `else`, a failed match runs the suite, which must leave: by `return`,
  `break`, `continue` or a trap.
- The names are in scope for the rest of the enclosing suite.
- The expression of a `let` is pure. A call with effects is bound with
  `use` (section 10.10) **(approved)**.
- **Value restriction (approved).** A `let` binding is generic only when its
  expression is itself a `func`. A constructor application, a call or a
  partial application gives the local one type.
- **(approved)** `let` introduces new names. A `let` or `if let` that binds
  a name already in scope as a local or parameter of the function is an
  error. A new value for an old name is written with `:=`. Lambda
  parameters, `case` arms and loop patterns may reuse a name.

### 10.2 Rebinding: `:=`

```
Rebind = Place ":=" Expression
Place  = LowerName ("." LowerName | "[" Expression "]")*
```

- `name := value` gives an existing local or parameter a new value for the
  rest of its scope. The name must already be bound in the function.
- `name.path := value` builds the successor of the local's value with that
  one leaf replaced, and rebinds the local to it. The name and each index
  are evaluated once, left to right.
- On the right, `self` is the old value of the place.
- Nothing outside the function observes a rebinding. A closure created
  earlier keeps the value it captured.
- This is the only way a program changes anything **(approved)**. There is
  no statement that writes into a value another name holds.

### 10.3 Reuse

**(approved)**

The owner's goal: "efficient immutability. Maybe even more efficient than
mutable languages." An immutable program must cost no more than the same
program written with writes, and the compiler may use what immutability
guarantees, that no two names ever share an array that changes.

The meaning of a program never depends on reuse: `:=` always gives the
successor. This section fixes the cost.

**In place or not at all.** An update whose path passes through an array
changes that array in place. Nothing can observe that only if the local owns
the array, so the compiler must prove ownership inside the one function. If
it cannot, the statement is an error that asks for an explicit copy
(`values.copy`). The compiler never copies an array on its own.

**Owning inside a function.**

- A local owns an array from the point it is bound to a new one: an array
  literal, a comprehension, a copy, or the result of a call.
- It stays the owner through its own `:=` updates.
- It stops owning the array when the array is bound to another name,
  captured by a lambda, placed in another value, or referenced with `&`.
  It owns the array again after the last use of that other holder. A
  lambda that is returned, placed in a value or given to an `own` parameter
  has no last use in the function, so what it captures stays shared to the
  end of the scope.
- Reading an element that holds no array, and taking the length, change
  nothing.
- Where branches join, a local owns its array only if it does on every
  branch. A local carried round a loop owns its array only if it does on
  entry and at the end of every iteration.
- A record owns the arrays in its fields in the same way, so
  `world.entities[i].health := 3` is in place when `world` owns `entities`.

[The memory model](../../tasks/MEMORY_MODEL.md) lists these rules in full
under "Uniqueness".

**Across calls.** No fact about ownership is inferred across a call. The
signature states it.

- A parameter is **borrowed** unless marked. The function may read it and
  lend it on. It may not update it in place, return it, or return anything
  that holds it. Lending an array to a call does not end the caller's
  ownership.
- A parameter marked `own` is **taken over**. The argument must be owned at
  the call, and the caller's name is spent: using it again before rebinding
  it is an error. Inside the function the parameter is owned, so it can be
  updated in place and returned.
- A type **owns** an array when it is `Array`, `GrowArray` or
  `ResizeArray`, or data that holds one. A view (`&[a]`), a reference
  (`&a`), a link and a function only **borrow**.
- A function may return borrowed storage in a part of the result whose type
  borrows: a view of a parameter, or a closure that captured one. It may
  not return it in a part whose type owns; that needs `values.copy` or an
  `own` parameter.
- At a call, a result whose type has a borrowing part holds the call's
  arguments, like a closure that captured them. Every other result is owned
  by the caller.
- A generic function may return a parameter of variable type (`identity`,
  `min`, `Array.at`). The rule is checked where the variable gets its type:
  when a type variable occurs in the result and, as data, in a borrowed
  parameter, each call must give it a type that owns no array. Marking the
  parameter `own` lifts this. A variable under a function type in the
  parameter does not count.
- `own` is part of the function's type: `own (Array U32) -> U32 -> Array U32`.
- A partial application cannot supply an `own` parameter.
- On a type that holds no array, `own` changes nothing.

**A copy that is not needed costs nothing.** `values.copy x` is a move when
`x` owns its array and this is the last use of `x`. So a caller that is
done with its array passes it to an `own` parameter as it is, and a caller
that still needs it passes `values.copy xs` and pays for one copy, at the
call, where it is written. No ownership is passed at run time and no
function is compiled twice.

**The compiler says when `own` would help.** A function that copies a
borrowed parameter and then updates the copy gets the advice to mark the
parameter `own`. The error for updating a borrowed parameter says the same.
The signature stays what decides.

```blot
func damage (world: own World) -> (index: U32): World =>
  world.entities[index].health := self - 1
  return world

world := world.damage 3
```

### 10.4 `if`

```
IfStmt    = "if" Condition ":" Suite ("else" "if" Condition ":" Suite)*
            ("else" ":" Suite)?
Condition = Expression | "let" Pattern "=" Expression
```

`if let pattern = value:` runs its suite when the pattern matches, with the
pattern's names in scope there.

### 10.5 Loops

```
ForStmt = "for" "ever" ":" Suite
        | "for" Range ":" Suite
        | "for" Pattern "in" (Range | Expression) ":" Suite
```

- A range's bounds have one integer type and are evaluated once. An empty
  or reversed range runs no iterations.
- **(approved)** `for pattern in values:` accepts an array, a range
  reference, or a value of any type that implements `Collection`. It
  evaluates `values` and its length once, then reads each element by index
  in order. The pattern must match every element.
- `break` leaves the nearest loop. `continue` starts its next iteration.

### 10.6 Scope and joins

- A name bound by `let`, a pattern or a loop is visible to the end of its
  suite and not outside it.
- A rebinding of an outer local inside an `if`, an `if let`, a `case` used as
  a statement, a `with` or a loop carries out to the statements that follow.
- Where branches join, a rebound name has the same type on every branch that
  reaches the join. A branch that leaves contributes nothing.
- In a loop, a rebound outer local keeps one type across iterations.

### 10.7 Leaving

**(approved)** Each word has one target.

- `return value` leaves the innermost function.
- `break` leaves the innermost loop.
- `continue` starts the next iteration of the innermost loop.
- `break` or `continue` outside a loop is an error.

### 10.8 Expression statements

**(approved)** An expression used as a statement must have type `Unit`. To
discard another value, bind it: `let _ = expression`. This rejects a call
that is missing an argument.

### 10.9 Providers: `with`

**(approved)**

```
WithStmt = "with" Expression,+ ":" Suite
```

- Each expression is a provider (section 6.5). The statement installs them
  for its suite and for every function called from it. The innermost
  provider of an effect is the one an operation reaches.
- A lambda uses the providers in scope where it is called, not where it was
  created.
- The effects of a provider's own functions are effects of the `with`
  statement **(open)**.
- A `return` in the suite leaves the function.
- An exported function must provide every effect except `Foreign`.

### 10.10 Effects: `use`

**(approved)**

```
UseStmt = "use" (Pattern (":" Type)? "<-")? Expression
```

```blot
use line <- read_line ()
use Log.write line
```

- A call has effects when the function it calls has an effect row: an
  operation, a host callback, or a function whose type has `! {…}`.
- `use pattern <- call` makes the call and binds its result. The pattern
  must match every value of the result's type.
- `use call` makes the call and discards its result.
- A call with effects anywhere else is an error: in a `let`, on the right of
  `:=`, as an argument, in a condition, or as a bare statement **(open** for
  `return call` and a one-expression body**)**.
- `use` on an expression that has no effects is an error. This also rejects
  a call that is missing an argument.
- `use` statements run in the order written. Between them, everything is
  pure, so the compiler may reorder, share or skip that work when the result
  and any trap stay the same.
- A function that contains a `use` has the called effects in its row, less
  those a surrounding `with` provides.

## 11. Compile-time evaluation

```
RunExpr = "#run" Expression
```

- `#run expression` is evaluated by the compiler, and its value takes the
  expression's place. A `const` initializer is evaluated the same way.
- Compile-time evaluation gives the result that run-time evaluation would
  give. It cannot perform `Foreign` operations or read a module-level `let`.
- A trap during compile-time evaluation is an error.
- **Reflection (approved; spellings open).** `#type T` gives a plain data
  description of a type: its constructors, field names, field types,
  defaults and tags. `#quote e` gives a code value, and `#( e )` inside a
  quote inserts one. A code value has no type until `#run` places it, and it
  is checked there against the type the declaration wrote.
- `#run` cannot produce a declaration, a name or a type (rule 2).

```blot
type Robot is data = $Robot { id: U32, charge: F32, home: Vec3 }
const Robot.Eq: Eq Robot = #run derive.eq (#type Robot)
```

## 12. Dynamic errors

The language defines these traps:

- an index outside an array, or a range outside it;
- integer division or remainder by zero, and the smallest signed value
  divided by `-1`;
- use of a reference or link whose array is gone or has been reused;
- appending beyond the capacity planned for a `GrowArray` or `ResizeArray`;
- `panic "message"`;
- calling a host callback after the invocation that supplied it has ended;
- running out of memory or call stack.

Arithmetic overflow is not an error: integers wrap and floats follow
IEEE 754.

## Annex A. Removed forms

A conforming compiler rejects these. All are **(approved)**. The last column
names the item in the coherence list, or "round 2" for the changes approved
with this revision.

| Removed | Write instead | Item |
| --- | --- | --- |
| `=> return expr`, `=> return do:` with `break v`, `=> do:` with `return v` | `=> expr`, or `=>` and a suite with `return` | E1 |
| `Bool.not x` | `not x` | E2 |
| A statement whose value is not `Unit` | `let _ = …` | E3 |
| `value \|> f`, `f $ x` | `value.f`, parentheses | E4 |
| `@name` outside std | the std function | E5 |
| `#[…]` arrays, `[…]` lists, `List`, `[head \| tail]` | `[…]` arrays | E6 |
| `Ref a`, `View a`, `Link a`, `for let x in` | `&a`, `&[a]`, `^a`, `for x in` | E8 |
| `infix`, `infixl`, `infixr`, symbolic operators | named functions | E9 |
| Record, tuple and curried type parameters | one name or a list | E10 |
| A call with effects outside `use` | `use x <- call`, `use call` | round 3 |
| `@computation`, `@requests`, `effect` and `complete` clauses, `yield` | none | B3 |
| `do (monad M):`, `iterate` | `let … else` | B3 |
| `@effect.of`, `has`, `count`, `same`, `descriptor`, `scope`; rows such as `{state.get}` | none | B3 |
| `.name` as a function | a lambda, or a chain | C |
| `:x`, `$Type x`, `@type.same` | a type argument | C4 |
| `is contract`, `impl`, and the predicates `associated`, `result`, `receiver`, `update`, `field`, `type_eq`, `operation`, `type_rep`, `effect_rep` | `is trait` and `const X.Trait` | C |
| `@record.merge`, updates that change a field's type, `std/path` | closed records | C7 |
| `forall`, `exists`, `pack`, `unpack`, `@code.*`, `@proof.*`, `@usage.*` | `#run` with `#type` for staging; none for the rest | C8 |
| `@storage.write`, writes through `&a`, and any write that an alias can see | `:=` on an array the function owns | round 3 |
| `place = value`, `Cell a`, `is root` (approved earlier on 14 November) | `:=`; a local or a record field; data with field defaults | round 3 |
| `[x]` with `[0]` as a one-value cell | a local, or a field of a record that is passed and returned | round 3 |
| `Trait T -> out`, `Trait T -> [a, b]` | `Trait T { out: … }` | round 2 |
| `@storage.copy values`, `@panic "…"`, `@hole` | `values.copy`, `panic "…"`, `_` | round 2 |
| `@effect.provider`, `@effect.state`, `@effect.run`, `@effect.reader`, `@effect.writer`; `type Get a is effect = Unit -> a`; operation labels in rows | a provider record; the prelude's `State`; a record-form effect; effect labels | round 2 |
| `do:` with `break value`, `#run do:`, `#do:` | a function that returns the value; `#run` of a call | round 2 |
| `do provider:` | `with provider:` | round 2 |
| `let` over a local or parameter in scope | `:=`, or a new name | round 2 |
| `@[f]` applying a function to a declaration | `const x = f value` | round 2 |
| `iter` / `next` members, `@cursor.*`, `std/iter` | `Collection`, or an index loop | round 2 |
| `[...values, value]` | an append, or a named copy | round 2 |
| `Text` as `Array U32` of scalar values | UTF-8 in `Array U8` | round 2 |

`(-1.0)` stays valid; the rule of section 4.8 only makes the parentheses
unnecessary.

## Annex B. Open spellings and questions

0. **Ownership across calls.** Approved as section 10.3 states it. It
   differs from the memory model file in three places, and that file is the
   older one: passing an array to a call no longer ends ownership, a call's
   result is owned, and ownership returns at the other holder's last use.
   Still open: section 6.5 forbids `State.get` on state that may hold an
   array and adds a lending `State.read`. That is the implementer's
   recommendation, chosen because the alternative is a copy on every `get`.
   The owner has not seen it.
1. **Spellings chosen by this document.** The owner approved the changes and
   has not seen these spellings: `State.new`; `with`; `values.copy`,
   `panic`; `_`
   for a hole; the braces for trait outputs; `#quote` and `#( )`; the names
   of the description and code types.
2. **Output names.** Lowercase like type variables, as written here, or
   `UpperName` like other types.
3. **Providers with effects of their own.** A host callback used as an
   operation has `Foreign` in its type, while the effect declares the
   operation without it. Section 10.9 says where the effect goes. How the
   record type admits such a provider is undecided.
4. **Conversion names.** Section 9.2 gives the rule and names no functions.
   Gdev and Ink call `to_f32`, `to_u32` and `from` on about 1,200 lines.
5. **ABI.** UTF-8 text and the new numeric types change what crosses the
   host boundary. The repository's instructions say to preserve ABI 8.
6. **E8 pairs.** The review suggested the first of each pair and the owner
   has not chosen. This document uses the first.
7. **`not` precedence.** This document puts it below comparison.
8. **Backtick infix** (`` a `add` b ``). E9 removes fixity declarations and
   does not name backticks. This document leaves them out. Gdev and Ink do
   not use them.
9. **Module-level `let`.** Specified as today. Gdev and Ink do not use it.
10. **Tags on functions and constants.** Section 6.6 allows tags only where
    `#type` can read them.
11. **`Cell` and `is root`.** Both existed to share writes, so this revision
    removes them. A group of arrays is a data type with field defaults.
12. **How strict `use` is.** Section 10.10 allows a call with effects only
    in a `use`. That makes `return call ()` and `=> call ()` errors for a
    call with effects; allowing those two would save a line each. `use call`
    discards a result of any type, as it does today.
13. **What a result may borrow.** Section 10.3 forbids returning anything
    that holds a borrowed parameter, and rejects a generic function that
    reads a type variable out of one. Measured on 15 November 2026, those
    two rules reject 352 places in the Gdev build, the prelude's `identity`
    and `Maybe.map` among them. The implementer recommends two changes,
    which leave 44: a view, a reference or a function in a result may borrow
    from the arguments, and the generic rule is checked at each call, on
    the type the variable gets.
    [The memory model](../../tasks/MEMORY_MODEL.md) has the rules and the
    counts under "Phase 2". The owner has not seen them.

## Annex C. Considered and declined

Counts are grep approximations over Gdev (`src`, `devtools`) and Ink (`lib`),
about 56,000 lines.

- **A `?` or `try` operator.** `Result` appears on 20 lines, and
  `let $Some … else` (191 uses) covers early exit.
- **`while`.** `for ever` has 12 uses.
- **String interpolation.** There are 9 formatting calls.
- **`defer`.** Memory is released by scope, so nothing needs cleaning up.
- **In-language tests.** Ink's tests return reports that are compared with
  Rust references, which a `test` form would not replace.
- **Goose's `const for` over fields.** It needs a generic body checked again
  for each instance. `#run` with `#type` covers the same ground.

Two Goose features are worth another look later: index types,
which move a bounds check to where the index is made, and verified byte
images of arrays for snapshots.
