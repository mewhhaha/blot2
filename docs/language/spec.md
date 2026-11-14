# Blot language specification: syntax

Draft of 14 November 2026.

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
  text uses the illustrative spelling, and [Annex B](#annex-b-open-spellings-and-questions)
  lists the question.

Proposals the owner has not approved appear only in
[Annex C](#annex-c-proposals) and are not part of the specification.

Terms:

- **Error**: the compiler rejects the module and produces no output.
- **Trap**: execution of the current host invocation stops. A program cannot
  catch a trap.
- **Storage**: arrays, cells and roots. Everything else is a **value**.

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
4. **Mutation is visible.** A statement shows whether it rebinds a local
   (`:=`) or writes storage (`=`), and a parameter's type shows whether the
   function may write through it.
5. **Cost is visible.** No implicit copy of storage and no implicit numeric
   conversion.
6. **One meaning per program.** A program behaves the same in every build
   mode. Checks that trap are part of the meaning.

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
constructor is always written with its marker: `$Some`.

### 4.5 Keywords

Reserved everywhere:

```
and  as  break  case  const  continue  data  do  effect  else  ever  false
for  func  if  import  in  is  let  not  of  or  return  then  true  type
```

`not` is **(approved)**.

Reserved only in the position that gives them meaning, and ordinary names
elsewhere: `opaque`, `trait` and `root` after `is`;
`private`, `entry` and `export` at the start of a module item; `from` in an
import; `where` after a signature; `self` on the right of `:=`.

These words stop being keywords **(approved)**: `use`, `yield`, `complete`,
`infix`, `infixl`, `infixr`, `contract`, `impl`.

### 4.6 Literals

```
Integer = Digit ("_"? Digit)* | "0" ("x" | "X") Hex ("_"? Hex)*
Float   = Digits "." Digits Exponent? | Digits Exponent
Exponent = ("e" | "E") ("+" | "-")? Digits
String  = '"' (Character | Escape)* '"'
Escape  = '\"' | "\\" | "\n" | "\r" | "\t"
```

- An integer literal has type `U32` and a float literal has type `F32`. A
  literal outside its type's range is an error.
- A string literal stays on one line and has type `Text`.
- `true` and `false` have type `Bool`. `()` is the one value of type `Unit`.
- There is no negative literal. `-` is the prefix operator of section 9.1, so
  a negative argument needs parentheses: `F32.abs (-2.0)`.

### 4.7 Punctuation

Each mark has one role in each of the three grammars.

| Mark | In expressions and statements | In types | In patterns |
| --- | --- | --- | --- |
| `.` | member of a module, type or value | member of a type | |
| `..` | range | | |
| `...` | spread in an array literal | | |
| `:` | suite opener; annotation; field | annotation; field | field |
| `=` | definition; store | definition | |
| `:=` | rebinding | | |
| `->` | parameter separator | function type; trait outputs | |
| `=>` | body | | arm body |
| `<-` | generator | | |
| `$` | constructor | | constructor |
| `&` | reference to a place; bitwise and | read-only reference | |
| `^` | link to an element; bitwise xor | link | match an existing name |
| `\|` | bitwise or; comprehension bar | row tail; data alternative | alternative |
| `!` | | effect row | |
| `#` | compile-time form | | |
| `@` | intrinsic (std only); tag | | |
| `_` | | | wildcard |

### 4.8 Adjacency

Whitespace is significant in exactly these places:

- `$` touches its constructor name.
- `#` touches `run`, `type`, `quote` and `(`. `@` touches its name or `[`.
- A prefix `&` or `^` touches its operand.
- `[` that touches the expression before it is an index: `rows[i]`. After a
  space it starts an array literal, so `f rows [i]` passes two arguments.
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
Param     = "(" ")" | "(" Pattern ":" Type ")"
Body      = Expression | Suite
```

- Every parameter and the result are annotated **(approved)**.
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
           | "type" TypeHead "is" "effect" "=" (RecordType | Type)
           | "type" UpperName "is" "root" "=" "{" RootField,+ "}"
TypeHead   = TypeName TypeParams?
TypeName   = (UpperName ".")* UpperName
TypeParams = LowerName | "[" LowerName,+ "]"
Constructor = "$" UpperName TypeAtom?
RootField  = LowerName ":" Type "=" Expression
```

- **Alias.** `type Name = Type` adds a name and nothing else. A recursive
  alias is an error.
- **Data.** A nominal type with one or more constructors. A constructor has
  no payload or one; several values go in a tuple or a record.
- **Opaque.** A nominal type with one private constructor of the same name.
  Only the declaring module can construct or match it.
- **Type parameters (approved).** One name, or a bracketed list of names:
  `type Tree a`, `type Result [value, error]`. An application mirrors it:
  `Tree U32`, `Result [U32, Text]`.
- **Type members (approved).** `type Pool.Id = U32` declares the type `Id` in
  the namespace of `Pool`. Only the module that declares `Pool` may do so.

### 6.4 Traits

**(approved; spellings open)**

```
TraitHead = UpperName LowerName ("->" TraitOutputs)?
TraitOutputs = LowerName | "[" LowerName,+ "]"
Where     = "where" "{" Predicate,+ "}"
Predicate = TypePath TypeAtom ("->" TypeArg)?
```

```blot
type Eq a is trait = { eq: a -> a -> Bool }
type Collection c -> item is trait = { length: c -> U32, at: c -> U32 -> item }

const U32.Eq: Eq U32 = { eq: U32.eq }
const Array.Eq: Eq (Array a) where { Eq a } = { eq: equal_array }
const Array.Collection: Collection (Array a) -> a = { length: Array.length, at: Array.at }

func member (values: Array a) -> (wanted: a): Bool where { Eq a } => ...
func first (values: c): Maybe c.item where { Collection c } => ...
```

- A trait is a nominal record type. Its first parameter is the type it
  dispatches on. Parameters after `->` are outputs: the first parameter
  determines them.
- The implementation of trait `T` for type `X` is the constant `X.T`, of
  type `T X`. There is no other way to implement a trait, so a type has at
  most one implementation of each trait.
- `X.T` may be declared in the module that declares `X` or the module that
  declares `T`. Anywhere else is an error.
- An implementation for a generic type may have its own `where` clause.
- `where { T a }` on a function is an argument the compiler supplies. At
  each use it must find `X.T` for the concrete `X`, or the same predicate in
  the caller's own `where` clause. Otherwise the use is an error.
- A predicate is a trait applied to a type and nothing else.
- On a type variable `c` with `where { Collection c }`, `c.item` names the
  trait's output. If two predicates on `c` offer the same output name, the
  name must be qualified: `Collection.item c`.
- No trait record exists at run time unless the program passes one as an
  ordinary argument.

### 6.5 Effects

```blot
type State a is effect = { get: Unit -> a, set: a -> Unit }
type Get a is effect = Unit -> a
```

- An effect declares operations and grants nothing. The single-operation
  form uses the effect's name as the operation's name.
- An operation is called like a function: `State.get U32 ()`. Its effect
  appears in the row of every function that calls it without a provider in
  scope.
- `Foreign` is the one built-in effect. It marks host callbacks. Source
  cannot declare or provide it.

### 6.6 Roots

**(approved)**

```blot
type World is root = {
  entities: ResizeArray Entity = [],
  viewport: Cell Viewport = @cell viewport.default,
}
let world = @root World
```

- A root is storage made of a fixed group of storage components. Every
  component has an initial value.
- `@cell` and `@root` are the memory model's spellings **(open)**.
- Creating a root creates all of its components, and they share one
  lifetime.
- Replacing a component (`world.entities := …`) is an error. Writing into
  one (`world.entities[i] = entity`) is a store.

### 6.7 Tags

```
Tag = "@[" Expression "]"
```

A tag before a module-level `const`, `let` or `func` applies its expression,
as a function, to the declared value. With several tags, the nearest applies
first. A tag on any other declaration is an error.

## 7. Types

```
Type       = TypeApply ("->" Type ("!" EffectRow)?)?
TypeApply  = TypePrefix TypeArg?
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
EffectLabel = TypePath ("." LowerName)? TypeArg?
```

- `->` associates to the right. A function type as a parameter needs
  parentheses.
- `! {…}` follows the result of the arrow it belongs to and lists the
  effects of calling that function. No `!` means no effects.
  `{Foreign | e}` leaves the rest of the row open, and `e` is a row variable.
  A name used as both a type variable and a row variable in one signature is
  an error.
- A lowercase name is a type variable, shared across one declaration's
  signature.
- A type takes one argument or a bracketed list, matching its declaration.
- Record types are structural, and field order does not matter. Records are
  closed: a function cannot abstract over "any record with field `x`"
  **(approved)**.
- **Storage types.** `Array a` has a fixed length, `GrowArray a` can append,
  and `ResizeArray a` can also shrink. `Cell a` holds one value
  **(approved)**. A root type is storage.
- **References.** `&a` refers to one value and `&[a]` to a range of an
  array. Both are read-only **(approved)**. `^a` is a link to an element of a
  stable pool. A function that writes takes the storage itself.

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
  existing `U32` or `Bool` local, parameter or constant.
- A constructor pattern with a payload must be parenthesized when it is
  itself a payload: `$Some ($Pair (a, b))`.
- A record pattern may leave fields out and list them in any order.
- A name bound twice in one pattern is an error.

## 9. Expressions

```
Expression = Lambda | IfExpr | CaseExpr | Block | RunExpr | Operators
```

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
  operand's type **(approved)**. The right operand's type is the trait's
  output, so one type has one meaning for `*`.
- `U32` arithmetic wraps. `U32` division or remainder by zero traps. Shift
  counts wrap modulo 32.

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

### 9.3 Primary expressions

```
Primary = Integer | Float | String | "true" | "false" | "()"
        | LowerName | UpperName | "self"
        | "$" CtorPath
        | "(" Expression ")"
        | "(" Expression "," Expression,+ ")"
        | "{" Field,* "}"
        | "[" ArrayItem,* "]"
        | "[" Expression "|" Qualifier,+ "]"
        | "&" Postfix | "&" Postfix "[" Range "]" | "^" Postfix
        | "#type" TypeAtom | "#quote" Primary | "#(" Expression ")"
Field     = LowerName (":" Expression)?
ArrayItem = Expression | "..." Expression
Qualifier = Pattern "<-" (Range | Expression) | "let" Pattern "=" Expression
          | Expression
Range     = Expression ".." Expression
```

- **Constructors.** `$Some 42` applies a constructor. A constructor alone is
  a function, or a value when it has no payload.
- **Records.** `{ x: 1, y }` builds a record; `y` alone means `y: y`. Fields
  are evaluated in written order. A missing, unknown or repeated field is an
  error.
- **Tuples.** `(a, b)` has two or more parts. They are read with patterns.
- **Arrays (approved).** `[1, 2, 3]` builds an array. The expected type
  chooses `Array`, `GrowArray` or `ResizeArray`; without one it is `Array`.
  An empty literal needs an expected type. One `...values` item copies the
  elements of another array into the new one.
- **Comprehensions.** `[x * x | x <- values, x > 1]` builds an array.
  Qualifiers run left to right, the leftmost outermost. A `Bool` qualifier
  skips the rest when false. A generator may draw from a range
  **(approved)**: `[i * 2 | i <- 0..count]`. A bitwise `|` before the bar
  needs parentheses.
- **Ranges.** `start..end` counts up from `start` and stops before `end`.
  It is syntax, not a value: it appears in `for`, in a generator and in a
  range reference.
- **References.** `&place` refers to one value in storage,
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
  is created. Captured storage is the same storage.
- The body follows the rules of section 6.1.
- A local bound to a lambda is generic only when the bound expression is
  itself a `func` **(approved)**.

### 9.6 Conditionals and matches

```
IfExpr   = "if" Expression "then" Expression "else" Expression
CaseExpr = "case" Expression,+ "of" NEWLINE INDENT Arm+ DEDENT
Arm      = PatternRow ("|" PatternRow)* ("if" Expression)? "=>" Body
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
- When the value of a `case` is used, every arm has the same type.

### 9.7 Blocks

```
Block = "do" Expression? ":" Suite
```

- `do:` runs its suite. `break value` finishes the nearest enclosing `do`
  with that value, even from inside a loop. Reaching the end gives `()`.
- `do provider:` also installs a provider for the effect operations called
  inside the suite, including those called by the functions it calls. A
  provider is a function that implements one operation. It runs when the
  operation is called and returns its result.
- A function that is exported must provide every effect except `Foreign`.

### 9.8 Typed holes

A hole stands for an expression not yet written. A module with a hole is an
error, and the error reports the type expected there and the locals in
scope. The hole is spelled `@hole` **(open)**.

## 10. Statements

```
Statement = LetStmt | Rebind | Store | IfStmt | CaseExpr | ForStmt | Block
          | "return" Expression
          | "break" Expression?
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
- Any call may be bound with `let`, whatever its effects **(approved)**.

### 10.2 Rebinding: `:=`

```
Rebind = Place ":=" Expression
Place  = LowerName ("." LowerName | "[" Expression "]")*
```

- `name := value` gives an existing local or parameter a new value for the
  rest of its scope. The name must already be bound in the function.
- `name.path := value` builds the successor of the local's value with that
  one leaf replaced, and rebinds the local to it. The root and each index
  are evaluated once, left to right.
- On the right, `self` is the old value of the place.
- Nothing outside the function observes a rebinding. A closure created
  earlier keeps the value it captured.
- **Through storage (approved).** When the path passes through storage, the
  update happens in place, which is correct only if nothing else can observe
  the old storage. The compiler must prove that within the one function,
  using the rules in [the memory model](../../tasks/MEMORY_MODEL.md).
  Otherwise the statement is an error, and the program must say what it
  means: a store with `=`, or an explicit copy first.

### 10.3 Stores: `=`

**(approved)**

```
Store = Postfix "=" Expression
```

- A store writes storage in place, and every alias sees the new value.
- The place must end in a field or an index and must reach storage: an
  element `rows[i]`, a field of an element `rows[i].x`, a cell's value
  `cell.value`, or any of these through a root's component.
- A store to a place that never reaches storage is an error: use `:=`.
- A store through `&a` or `&[a]` is an error.
- Replacing a root's component is an error.

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

- A range's bounds are `U32` and are evaluated once. An empty or reversed
  range runs no iterations.
- `for pattern in values:` visits the elements of an array in order. The
  pattern must match every element.
- `break` leaves the nearest loop. `continue` starts its next iteration.

### 10.6 Scope and joins

- A name bound by `let`, a pattern or a loop is visible to the end of its
  suite and not outside it.
- A rebinding of an outer local inside an `if`, an `if let`, a `case` used as
  a statement, or a loop carries out to the statements that follow.
- Where branches join, a rebound name has the same type on every branch that
  reaches the join. A branch that leaves contributes nothing.
- In a loop, a rebound outer local keeps one type across iterations.

### 10.7 Leaving

- `return value` leaves the innermost function.
- `break value` finishes the innermost `do`. `break` alone leaves the
  innermost loop.
- `continue` starts the next iteration of the innermost loop.

### 10.8 Expression statements

**(approved)** An expression used as a statement must have type `Unit`. To
discard another value, bind it: `let _ = expression`. This rejects a call
that is missing an argument.

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
  description of a type: its constructors, field names and field types.
  `#quote e` gives a code value, and `#( e )` inside a quote inserts one. A
  code value has no type until `#run` places it, and it is checked there
  against the type the declaration wrote.
- `#run` cannot produce a declaration, a name or a type (rule 2).

```blot
type Robot is data = $Robot { id: U32, charge: F32, home: Vec3 }
const Robot.Eq: Eq Robot = #run derive.eq (#type Robot)
```

## 12. Dynamic errors

The language defines these traps:

- an index outside an array, or a range outside it;
- `U32` division or remainder by zero;
- use of a reference or link whose storage is gone or has been reused;
- appending beyond the capacity planned for a `GrowArray` or `ResizeArray`;
- an explicit panic;
- calling a host callback after the invocation that supplied it has ended;
- running out of memory or call stack.

Arithmetic overflow is not an error: `U32` wraps and `F32` follows IEEE 754
binary32.

## Annex A. Removed forms

A conforming compiler rejects these. All are **(approved)**; the last column
names the item in the coherence list.

| Removed | Write instead | Item |
| --- | --- | --- |
| `=> return expr`, `=> return do:` with `break v`, `=> do:` with `return v` | `=> expr`, or `=>` and a suite with `return` | E1 |
| `Bool.not x` | `not x` | E2 |
| A statement whose value is not `Unit` | `let _ = …` | E3 |
| `value \|> f`, `f $ x` | `value.f`, parentheses | E4 |
| `@name` outside std | the std function | E5 |
| `#[…]` arrays, `[…]` lists, `List`, `[head \| tail]` | `[…]` arrays | E6 |
| `Ref a`, `View a`, `Link a`, `for let x in`, `#do:` | `&a`, `&[a]`, `^a`, `for x in`, `#run do:` | E8 |
| `infix`, `infixl`, `infixr`, symbolic operators | named functions | E9 |
| Record, tuple and curried type parameters | one name or a list | E10 |
| `use x <- call`, `use call` | `let x = call`, `call` | B2 |
| `@computation`, `@requests`, `effect` and `complete` clauses, `yield` | none | B3 |
| `do (monad M):`, `iterate` | `let … else` | B3 |
| `@effect.of`, `has`, `count`, `same`, `descriptor`, `scope`; rows such as `{state.get}` | none | B3 |
| `.name` as a function | a lambda, or a chain | C |
| `:x`, `$Type x`, `@type.same` | a type argument | C4 |
| `is contract`, `impl`, and the predicates `associated`, `result`, `receiver`, `update`, `field`, `type_eq`, `operation`, `type_rep`, `effect_rep` | `is trait` and `const X.Trait` | C |
| `@record.merge`, updates that change a field's type, `std/path` | closed records | C7 |
| `forall`, `exists`, `pack`, `unpack`, `@code.*`, `@proof.*`, `@usage.*` | `#run` with `#type` for staging; none for the rest | C8 |
| `@storage.write` and writes through `&a` | `place = value` on the storage | A |
| `[x]` with `[0]` as a one-value cell | `Cell a` | A |

## Annex B. Open spellings and questions

Writing the grammar out found these. Each needs the owner's decision.

1. **The trait output arrow reads as a function type.**
   `const Array.Collection: Collection (Array a) -> a` parses as a function
   from `Collection (Array a)` to `a`, and only knowing that `Collection` is
   a trait says otherwise. That breaks rule 1. Naming the outputs would
   avoid it and match `c.item`: `Collection (Array a) { item: a }`.
2. **Output names.** Lowercase like type variables, or `UpperName` like
   other types.
3. **Two traits with one name.** Two modules may each declare a trait
   `Format` and both want `U32.Format`. The slot could be keyed by the trait
   itself instead of its spelling: each module then writes the
   implementation under the name it imports the trait by, and a module that
   imports both renames one.
4. **Intrinsics in user code.** E5 keeps `@name` inside std, but the memory
   model writes `@cell x`, `@root World` and `@storage.copy` in application
   code. `@panic` (179 uses in Gdev and Ink) and `@hole` are in the same
   position. Each needs a public spelling.
5. **E8 pairs.** The review suggested the first of each pair and the owner
   has not chosen. This document uses the first.
6. **`not` precedence.** This document puts it below comparison.
7. **Backtick infix** (`` a `add` b ``). E9 removes fixity declarations and
   does not name backticks. This document leaves them out. Gdev and Ink do
   not use them.
8. **Effect bodies.** Operations are separated by line breaks today. This
   document uses commas, as in every other record type.
9. **Effect rows.** A label is an operation today (`State.get U32`). The
   alternative is the effect itself (`State U32`).
10. **Not covered by any decision:** `@effect.state`, `@effect.run`,
    `@effect.reader`, `@effect.writer`; the single-operation effect form;
    tags; spreads; module-level `let`. They are specified as they are today
    or left out, and none has a use in Gdev or Ink.
11. **Numbers.** Only `U32` and `F32` exist. The numeric set is undecided
    (D1).
12. **`#quote`, `#( )`** and the names of the description and code types.
13. **`let` over an existing local.** `let value = 1` followed by
    `let value = value + 41` in one suite compiles today. Section 10.1 does
    not say whether it should.

## Annex C. Proposals

Not approved and not part of the specification. Counts are grep
approximations over Gdev (`src`, `devtools`) and Ink (`lib`), about 56,000
lines.

1. **Effects built like traits.** An effect is a nominal record type of
   operations, and a provider is an ordinary record value of that type,
   installed for a suite. A trait is then a record found by type at compile
   time, and an effect a record found by scope at run time. This removes
   `@effect.provider`, the four `@effect.state` forms and the
   single-operation form. Evidence: no user effect is declared, and
   `Foreign` appears on 8 lines.
2. **One target for each leaving word.** Remove value blocks (`do:` with
   `break value`). `return` leaves a function, and `break` and `continue`
   act on loops. Today `break` and `break ()` leave different things. After
   E1, 8 value blocks remain. A provider block then needs its own word, such
   as `with provider:`.
3. **Negative literals without parentheses.** A `-` with a space before it
   and none after is negation, so `f -1.0` passes `-1.0`. Evidence: 537
   lines with a parenthesized negative number.
4. **Numbers.** `U8` to `U64`, `I8` to `I64`, `F32` and `F64`. A literal
   takes the expected type and defaults to `U32` or `F32`. Integers wrap in
   every build. Conversions are members named for what they lose
   (`count.to_f32`, `value.wrap_u8`). `Text` becomes UTF-8 bytes. Evidence:
   1,212 conversion sites.
5. **No `let` over an existing local.** `let` introduces a new name and
   `:=` gives an old one a new value. A `let` that reuses a local's or
   parameter's name is an error.
6. **Tags as data.** `@[…]` attaches constant data to a declaration,
   constructor or field. `#type` shows it and it changes nothing else. A
   derived codec needs per-field information such as a version. Applying a
   function is written as a call. Tags have no uses today.
7. **Field defaults in data.** Roots already give each component an initial
   value. Allow the same on a record constructor's fields, and let a
   construction leave those fields out.
8. **`for` over a trait.** `for` accepts ranges, arrays and any type with
   `Collection`, as an index loop. Remove the `iter` / `next` cursor
   protocol, `@cursor.*` and `std/iter`. None has a use.
9. **Remove spreads.** `[...values, value]` copies an array. It has no
   uses, and an append or a named copy says the same.
