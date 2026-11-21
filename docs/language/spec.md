# Blot Language Specification (vNext)

Revision 4 — 21 November 2026.

This document specifies the Blot vNext language: its lexical and syntactic
grammar, static rules, ownership and sharing model, effects, traits, compile-time
metaprogramming, and dynamic traps. It supersedes earlier competing drafts and
is the single language target. [The executable guide](guide.md) continues to
describe the current compiler while migration is in progress;
[the compiler roadmap](../compiler/VNEXT_ROADMAP.md) tracks implementation.

---

## 1. Core Identity & Design Rules

Blot is a pure, value-semantic, data-oriented language compiling directly to
WebAssembly. Every design rule below is an invariant:

1. **Pure shadowing is the only mutation model.** Every value is logically
   immutable, arrays included. `let` always introduces new names; `:=` (with
   `self`) always evolves an existing binding, nested path, or loop/branch
   carry. No code can ever observe another name mutating a value it holds.
2. **Intrinsics are symbols; user types are names.** Built-in type constructors
   and modes use compact symbols (`#[T]`, `#[+T]`, `#[~T]`, `#[n; T]`, `*T`,
   `->`, `*(A -> B)`). User-defined and standard-library types use `PascalCase`
   names.
3. **No borrow-checker lifetimes, no hidden copies.** Read borrows are lexical
   and non-escaping. Ownership transfers explicitly via `own`. The compiler
   reuses linear memory in place and never inserts an implicit `O(n)` copy:
   diverging timelines explicitly choose `copy`, `freeze` (`*T`), or `fork`.
4. **A module parses without knowing any declaration.** The operator table is
   fixed, name casing decides syntactic class, and no declaration alters parsing.
5. **A module's interface is known after parsing.** Every module-level
   declaration writes its full name and type. Compile-time evaluation (`#run`)
   and typed reflection (`#for` / `#if`) run inside bodies only and never
   synthesize module-level names or types.
6. **One meaning per program.** Every build tier preserves identical wrapping
   integers, IEEE 754 floats, trap behavior, and effect order.
7. **Effects are visible.** Effectful calls appear only in `use` statements
   (or `return use`). Everything between `use` lines is pure and freely
   reorderable, shareable, or skippable when traps are preserved.

Terms:
- **Error**: static rejection during compilation (no Wasm emitted).
- **Trap**: immediate termination of the current host invocation (uncatchable).
- **Linear (owned)**: a value with exactly one live holder, eligible for
  in-place reuse on `:=` and transfer to `own`.
- **Frozen (`*T`)**: an immutable, `O(1)`-shareable value with `0..∞` holders.

---

## 2. Notation

```
Name       = Alternative | Alternative
"text"     terminal token
A?         optional
A*         zero or more
A+         one or more
A,+        one or more separated by ",", optional trailing ","
A,*        zero or more separated by ",", optional trailing ","
```

`NEWLINE`, `INDENT`, and `DEDENT` are layout tokens (Section 3.2).
`Suite = NEWLINE INDENT Statement+ DEDENT`.

---

## 3. Lexical Grammar

### 3.1 Source Text & Comments

A module is UTF-8. Outside string literals and comments, only ASCII is allowed.
Line endings are LF or CRLF. `//` starts a line comment to end of line; there
are no block comments.

### 3.2 Layout

- Top-level items begin at column 0. Indentation uses spaces only (tabs are an
  error).
- **Suite.** A line ending in `:`, `of`, or `=>` opens an indented suite.
- **Continuation.** A line indented further than the current suite continues the
  preceding item. A line starting with `|` at the current suite's indentation
  continues a data or `case` alternative. A line starting with `.name` continues
  the expression above it (Section 8.4).
- **Brackets.** Line breaks inside `( )`, `[ ]`, and `{ }` are ignored except
  inside a nested suite.

### 3.3 Names & Keywords

```
LowerName = [a-z_] [a-z0-9_]*
UpperName = [A-Z] [A-Za-z0-9_]*
```

- `LowerName`: values, functions, fields, module aliases, type/length variables.
- `UpperName`: types, traits, effects, constructors (always prefixed `$Name`).
- `_` alone is a wildcard in patterns and a typed hole in expressions.

Reserved everywhere:
```
and  as  break  case  const  continue  data  effect  else  ever  false  for
fork  func  if  import  in  is  let  not  of  or  return  then  true  type
use  with
```

Contextual keywords (ordinary names elsewhere): `opaque`, `trait` (after `is`);
`private`, `entry`, `export` (start of module item); `from` (imports); `where`
(after signature); `self` (RHS of `:=`); `own` (before parameter type).

### 3.4 Literals

```
Integer  = Digit ("_"? Digit)* | "0" ("x" | "X") Hex ("_"? Hex)*
Float    = Digits "." Digits Exponent? | Digits Exponent
Exponent = ("e" | "E") ("+" | "-")? Digits
String   = '"' (Character | Escape)* '"'
Escape   = '\"' | "\\" | "\n" | "\r" | "\t"
```

- Integer literals adopt the expected integer type, defaulting to `U32`.
- Float literals adopt the expected float type, defaulting to `F32`.
- Out-of-range literals are errors. Integers never coerce to floats.
- String literals are single-line UTF-8 `Text` (`#[U8]`).
- `true` / `false` have type `Bool`; `()` has type `Unit`.

### 3.5 Punctuation Table

| Mark | Expressions & Statements | Types | Patterns |
| --- | --- | --- | --- |
| `.` | member / chain / field splice `.(f)` | type member / trait output | |
| `..` | range (`start..end`) | | |
| `:` | suite opener; annotation; field | annotation; field | field |
| `=` | definition; `with` binding | definition; field default | |
| `:=` | shadowing evolution | | |
| `->` | curried parameter separator | function type | |
| `=>` | function / arm body | | arm body |
| `<-` | comprehension generator; `use` bind | | |
| `$` | constructor (`$Some`) | | constructor |
| `#[` | array literal / comprehension | array type (`#[T]`, `#[+T]`, `#[~T]`, `#[n; T]`) | |
| `*` | multiplication | frozen / shared (`*T`, `*(A -> B)`) | |
| `+` | addition | grow-only array (`#[+T]`) | |
| `~` | | resizable array (`#[~T]`) | |
| `;` | | length separator (`#[n; T]`) | |
| `&` | bitwise and | | |
| `^` | bitwise xor | | pin existing value (`^name`) |
| `\|` | bitwise or; comprehension bar | data alternative | alternative |
| `!` | | closed effect set (`! {Log}`) | |
| `#` | compile-time (`#run`, `#for`, `#if`, `#fields`, `#variants`) | | |
| `@` | intrinsic (`std` only) | tag (`@[expr]`) | |
| `_` | typed hole | | wildcard |

### 3.6 Significant Adjacency

- `$` touches its constructor name (`$Some`).
- `#[` has no internal space.
- `#` touches `run`, `for`, `if`, `else`, `fields`, `variants`; `@` touches its
  name or `[`.
- `*` in type position touches its operand (`*#[U32]`, `*(U32 -> U32)`).
- `[` touching the preceding expression is indexing (`rows[i]`).
- `-` preceded by whitespace and followed immediately by an operand starts a
  negated argument (`f -1.0` parses as `f (-1.0)`); `a - b` and `a-b` remain
  subtraction.
- A line starting with `.name` continues the expression above it.

---

## 4. Modules

```
Module      = Import* Item*
Import      = "import" "*" "as" LowerName "from" String
            | "import" "{" ImportName,+ "}" "from" String
ImportName  = Name ("as" Name)?
Name        = LowerName | UpperName
Item        = Reexport | Tag* "private"? "entry"? Declaration
Reexport    = "export" "{" ImportName,+ "}" "from" String
Declaration = FuncDecl | ConstDecl | LetDecl | TypeDecl
```

- Imports precede all declarations. Import cycles are errors.
- Declarations are public by default; `private` restricts to the defining module.
- A public signature cannot expose a private type or effect.
- `entry` marks host Wasm exports on the entry module only (at least one entry
  required). Only the entry module may declare entries.
- Module-level names are declared once (no ad-hoc overloads).

---

## 5. Declarations

### 5.1 Functions

```
FuncDecl  = "func" ValuePath Param ("->" Param)* ":" Type ("!" EffectSet)?
            Where? "=>" Body
ValuePath = (UpperName ".")* LowerName
Param     = "(" ")" | "(" "own"? Pattern ":" Type ")"
Body      = Expression | Suite
```

- Every module-level parameter and result type is written explicitly.
- Parameters are separated by `->` (curried syntax: `func add (a: U32) -> (b: U32): U32 => a + b`).
- `own` marks a parameter taken linearly (Section 9.3).
- `=> expression` returns that expression directly. `=>` at end of line opens a
  suite; `return value` leaves the function, and falling off the end returns
  `()` (error if the declared result type is not `Unit`).
- `func Type.name ...` declares a member in `Type`'s namespace (defining module
  only).
- Module-level functions may refer to one another in any order.

### 5.2 Constants and Module-Level `let`

```
ConstDecl = "const" ConstPath ":" Type Where? "=" Expression
ConstPath = (UpperName ".")* Name
LetDecl   = "let" LowerName ":" Type "=" Expression
```

- `const` evaluates purely at compile time under a bounded step budget and
  cannot read module-level `let` bindings.
- Module-level `let` initializes once at module startup in dependency order;
  initialization cycles are errors.

### 5.3 Types

```
TypeDecl    = "type" TypeHead "=" Type
            | "type" TypeHead "is" "data" "=" "|"? Constructor ("|" Constructor)*
            | "type" TypeHead "is" "opaque" "=" Type
            | "type" TraitHead "is" "trait" "=" RecordType
            | "type" TypeHead "is" "effect" "=" RecordType
TypeHead    = TypeName TypeParams?
TypeName    = (UpperName ".")* UpperName
TypeParams  = LowerName | "[" LowerName,+ "]"
Constructor = Tag* "$" UpperName (TypeAtom | "{" DataField,* "}")?
DataField   = Tag* LowerName ":" Type ("=" Expression)?
```

- **Alias** (`type A = T`): transparent; recursive aliases are errors.
- **Data** (`is data`): nominal sum/product type. Constructors take 0 or 1
  payload (use a tuple or `{ ... }` named fields for multiple values). Named
  fields may specify pure module-level defaults (`hp: F32 = 100.0`).
- **Opaque** (`is opaque`): nominal wrapper with one private constructor `$Name`,
  erased at runtime with zero allocation overhead.
- **Type members**: `type Pool.Id = U32` lives in `Pool`'s namespace.
- **Length variables in data**: A data record may share a length variable across
  fields (Section 6.2), proving equal length across parallel arrays:
  ```blot
  type Robots is data = $Robots {
    pos: #[+n; Vec2],
    vel: #[+n; Vec2],
    hp:  #[+n; F32],
  }
  ```

### 5.4 Traits

```
TraitHead   = UpperName LowerName ("{" LowerName,+ "}")?
Where       = "where" "{" Predicate,+ "}"
Predicate   = TypePath TypeAtom OutputTypes?
OutputTypes = "{" OutputType,+ "}"
OutputType  = LowerName ":" Type
```

```blot
type Eq a is trait = { eq: a -> a -> Bool }
type Mul left { right, out } is trait = { mul: left -> right -> out }

const U32.Eq: Eq U32 = { eq: U32.eq }
const Vec3.Mul: Mul Vec3 { right: F32, out: Vec3 } = { mul: Vec3.scale }

func square (x: a): a where { Mul a { right: a, out: a } } => x * x
```

- A trait is a compile-time nominal record type. Braced names are output types
  determined by the dispatch type.
- There is **no `impl` keyword**. Implementing trait `T` for type `X` is
  declaring `const X.T: T X ...` in either `X`'s module or `T`'s module.
  Uniqueness is guaranteed by the namespace.
- Trait implementations are keyed by the resolved trait identity (not spelling),
  so two same-named traits from different modules never collide.
- `where { T a }` is a compile-time hidden argument resolved statically at each
  concrete use. No runtime dictionaries exist unless passed explicitly as a
  normal record parameter.
- On a type variable `c` with `where { Collection c }`, `c.item` names the
  output type (qualify as `Collection.item c` if ambiguous).
- **Read-only lift to `*T`**: Any trait whose operations only borrow `a`
  (no `own a` parameter) automatically applies to `*a` as well.
- **Array traits**: Implementing a read-only trait for `#[a]` automatically
  covers `#[+a]`, `#[~a]`, `#[n; a]`, and `*#[a]` (Section 6.2).

### 5.5 Effects

```blot
type Log is effect = { write: Text -> Unit }
```

- An effect is a nominal record type of operations. Declaring one grants no IO.
- Calling `Log.write msg` requires `Log` in the enclosing function's effect set
  (`! {Log}`) unless handled by an enclosing `with Log = ...:` block.
- **Closed effect sets only (no `! {| e}` row variables).** Because downward
  higher-order callbacks are templated (Section 6.4), effects performed inside
  callbacks flow directly into the caller without row polymorphism. Storable
  `A -> B` and `*(A -> B)` types declare concrete closed effect sets.
- `Foreign` is the sole built-in effect, marking host callbacks. Source cannot
  declare or handle `Foreign`.
- **No magic built-in `State` effect.** Scoped `with` handlers may capture and
  linearly shadow outer locals (Section 9.9), expressing scoped state, counters,
  accumulators, and deterministic replay recorders in ordinary source code.

### 5.6 Tags

```
Tag = "@[" Expression "]"
```

Tags attach compile-time constants to type declarations, constructors, or data
fields (`@[Codec.since 3] stamina: F32 = 1.0`). They are readable inside `#for`
reflection (Section 10) and have no other runtime effect.

---

## 6. Types & Intrinsic Symbols

```
Type        = "own"? TypeApply "->" Type ("!" EffectSet)? | TypeApply
TypeApply   = TypePrefix (TypeArg OutputTypes?)?
TypeArg     = TypePrefix | "[" Type,+ "]"
TypePrefix  = "*" TypePrefix | TypeAtom
TypeAtom    = TypePath
            | ArrayType
            | LowerName ("." LowerName)?
            | "(" Type ")"
            | "(" Type "," Type,+ ")"
            | RecordType
ArrayType   = "#[" ("+" | "~")? (LengthExpr ";")? Type "]"
LengthExpr  = LowerName | Integer
TypePath    = (LowerName ".")? UpperName ("." UpperName)*
RecordType  = "{" FieldType,* "}"
FieldType   = LowerName ":" Type
EffectSet   = "{" EffectLabel,* "}"
EffectLabel = TypePath TypeArg?
```

### 6.1 Scalars & Text

- `Unit`, `Bool`
- Signed integers: `I8`, `I16`, `I32`, `I64` (wrapping arithmetic)
- Unsigned integers: `U8`, `U16`, `U32`, `U64` (wrapping arithmetic)
- Floats: `F32`, `F64` (IEEE 754)
- `Text`: alias for `#[U8]` holding UTF-8 bytes (length counts bytes).
- No implicit numeric conversions; conversions are explicit member calls
  (`count.to_f32`).

### 6.2 Intrinsic Array Symbols (`#[T]`, `#[+T]`, `#[~T]`, `#[n; T]`)

Array modes encode length-stability guarantees directly in the type symbol:

| Symbol | Mode | Length / Bounds Guarantee |
| --- | --- | --- |
| `#[T]` | Fixed | Length never changes; every checked index remains valid forever |
| `#[+T]` | Grow-only | Length only increases (`push`); existing indices never invalidate |
| `#[~T]` | Resizable | Length may grow or shrink (`push`, `pop`, `truncate`); shrinking invalidates prior indices |
| `#[n; T]` / `#[+n; T]` / `#[~n; T]` | Length-linked | Shares symbolic or literal length `n` across fields or parameters; proves equal length at zero runtime cost and eliminates redundant bounds checks |

- **Read-only borrow coercion:** A borrowed (non-`own`) parameter of type `#[T]`
  (or `#[n; T]`) accepts `#[T]`, `#[+T]`, `#[~T]`, and `*#[T]`. Inside the
  callee the array cannot grow or shrink, so its length is fixed for the call.
- **Zero-copy mode narrowing:**
  - `seal`: `own #[+T] -> #[T]` (and `own #[~T] -> #[T]`) removes growth/shrink
    authority in place, reusing the exact allocation.
  - `freeze`: `own T -> *T` converts any linear value (including any array mode)
    into an immutable, `O(1)`-shareable `*T` (for arrays, yielding `*#[T]`) in
    place with zero copy.
- **Linked-length updates:** When a record binds a length variable `n` across
  multiple `#[+n; ...]` fields, growing all linked fields together when
  constructing the successor record advances `n` to `n + 1` in lockstep; leaving
  one field behind is a compile error.

### 6.3 Frozen / Shared Values (`*T`)

- `*T` is an immutable, freely aliasable value with `0..∞` holders.
- Creating `*T` via `freeze` is `O(1)` and consumes the linear input (same
  memory, no copy).
- Aliasing, storing in history buffers, or capturing `*T` in closures is `O(1)`.
- Linear types (`#[T]`, `#[+T]`, `#[~T]`, structs containing them) pay **zero**
  reference-counting overhead. Only `*T` carries shared lifetime management.
- To evolve a `*T` in place again, take an explicit `copy` (yielding linear `T`).

### 6.4 Callables (2A + 2B Model)

Functions keep curried `a -> b -> c` syntax while distinguishing three callable
forms with explicit cost and zero lifetime annotations:

1. **Saturated direct calls (`add 2 3`)**: compiled to direct Wasm calls with
   zero closure allocation.
2. **Downward templated closures & partial applications (2A)**: a capturing
   lambda (`func x => x + bias`) or partial application (`add 2`) may be called
   locally or passed *down* into a higher-order function (`xs.map (add 2)`). The
   compiler templates/specializes the callee directly—zero heap allocation, zero
   `call_indirect`, captures borrow lexically with no lifetimes, and effects flow
   automatically to the caller. Downward closures **cannot** be stored in data
   or returned from a function.
3. **Storable capture-free function pointers (`A -> B`) (2A)**: any top-level
   `func` or capture-free lambda may be stored in records, arrays, or returned
   as `A -> B`. Represented as a single 4-byte Wasm table index with a closed
   effect set (`! {Log}`). Zero ownership/lifetime interaction.
4. **Storable frozen closures (`*(A -> B)`) (2B)**: created explicitly via
   `freeze (add 2)` or `freeze (func x => ...)`. Represented as a uniform 2-word
   fat pointer `(fn_idx, *env)` with a closed effect set. Captures **must** be
   inline values or `*T`—never borrowed locals or unshared linear values—so no
   lifetime checker is ever required.

### 6.5 Structural Records & Tuples

- Structural records `{ x: U32, y: F32 }` are **closed** (no row polymorphism
  or `@record.merge`). Field order does not affect type equality or layout.
- Tuples `(a, b)` have two or more elements and are read via pattern matching.

---

## 7. Patterns

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

- `LowerName` binds a new local; `^name` compares against an existing integer or
  `Bool` binding.
- Record patterns may omit fields and list them in any order.
- Duplicate binder names in one pattern are errors.

---

## 8. Expressions

```
Expression = Lambda | IfExpr | CaseExpr | ForkExpr | RunExpr | Operators
```

Expressions are pure. Calls with effects appear only in `use` statements (or
`return use`).

### 8.1 Fixed Operator Table (Weakest to Strongest)

| Level | Operators | Grouping |
| --- | --- | --- |
| 1 | `or` | right (short-circuit `Bool`) |
| 2 | `and` | right (short-circuit `Bool`) |
| 3 | `not` | prefix (`Bool`) |
| 4 | `==` `!=` `<` `<=` `>` `>=` | non-associative |
| 5 | `\|` | left |
| 6 | `^` | left |
| 7 | `&` | left |
| 8 | `<<` `>>` | left |
| 9 | `+` `-` | left |
| 10 | `*` `/` `%` | left |
| 11 | `-` | prefix |
| 12 | application (`f a b`) | left |
| 13 | `.name`, `.(field)`, `[index]` | postfix |

Custom fixity declarations and user-defined operators do not exist. Arithmetic
and comparison operators dispatch statically through standard traits on the left
operand's type.

### 8.2 Application & Primary Expressions

```
Application = Postfix Postfix*
Postfix     = Primary ("." Name | ".(" LowerName ")" | "[" Expression "]")*
Primary     = Integer | Float | String | "true" | "false" | "()"
            | LowerName | UpperName | "self" | "_"
            | "$" CtorPath
            | "(" Expression ")"
            | "(" Expression "," Expression,+ ")"
            | "{" Field,* "}"
            | "#[" Expression,* "]"
            | "#[" Expression "|" Qualifier,+ "]"
            | "#fields" TypeAtom | "#variants" TypeAtom
Field       = LowerName (":" Expression)?
Qualifier   = Pattern "<-" (Range | Expression) | "let" Pattern "=" Expression
            | Expression
Range       = Expression ".." Expression
```

- Arguments evaluate eagerly left-to-right.
- `#[1, 2, 3]` builds `#[T]`, `#[+T]`, or `#[~T]` according to the expected type
  (defaulting to `#[T]`). Empty `#[]` requires an expected type.
- Comprehensions accept arrays, ranges (`#[i * 2 | i <- 0..n]`), and any
  `Collection` trait implementation.
- `_` in expression position is a typed hole (compile error reporting expected
  type and locals in scope).

### 8.3 Lambdas

```
Lambda      = "func" LambdaParam ("->" LambdaParam)*
              (":" Type ("!" EffectSet)?)? "=>" Body
LambdaParam = LowerName | "_" | "(" ")" | "(" "own"? Pattern (":" Type)? ")"
```

Lambdas follow the 2A/2B rules (Section 6.4).

### 8.4 Members and Chaining

`value.name` resolves in order:
1. A field of `value` (for multi-constructor data, every constructor must have
   the field).
2. A function in `value`'s type namespace taking `value` as its first parameter.
3. A member of a trait implemented for `value`'s type (in generic code, checked
   only against the function's `where` clause).

A line starting with `.name` continues the expression above it:
```blot
let reach = robots
  .filter (func r => r.charge > 0.2)
  .map (func r => r.home.length)
```

### 8.5 Conditionals, `case`, and `fork`

```
IfExpr   = "if" Expression "then" Expression "else" Expression
CaseExpr = "case" Expression,+ "of" NEWLINE INDENT Arm+ DEDENT
Arm      = PatternRow ("|" PatternRow)* ("if" Expression)? "=>" (Expression | Suite)
ForkExpr = "fork" LowerName,+ ":" Suite
```

- `case` must be exhaustive; guards do not contribute to coverage. Value `case`
  arms must be expressions of the same type; statement `case` arms may be suites.
- `fork x:` creates an inner lexical shadow of one or more linear locals at
  `O(edits)` cost (Section 9.4).

---

## 9. Statements, Shadowing, Ownership & Effects

```
Statement = LetStmt | UseStmt | Rebind | IfStmt | CaseExpr | ForStmt
          | WithStmt | ComptimeFor | ComptimeIf
          | "return" "use"? Expression
          | "break"
          | "continue"
          | Expression
```

### 9.1 `let` (Always New Names)

```
LetStmt = "let" Pattern (":" Type)? "=" Expression ("else" ":" Suite)?
```

- `let` always introduces new names. Rebinding an already in-scope local or
  parameter with `let` or `if let` is an error; use `:=` instead.
- With `else:`, a failed pattern runs the suite, which must exit (`return`,
  `break`, `continue`, or trap).
- **Value restriction:** Only a `let` bound to a syntactic `func` generalizes.
- The RHS of `let` must be pure.

### 9.2 Shadowing: `:=` and `self`

```
Rebind = Place ":=" Expression
Place  = LowerName ("." LowerName | "[" Expression "]")*
```

- `name := expr` consumes the old version of `name` (visible as `self` on the
  RHS) and shadows `name` with the new value for the rest of its scope.
- `name.path := expr` builds the successor along `path` with `self` naming the
  old leaf value. The root and all index expressions evaluate once, left to
  right.
- **Type-changing shadowing:** `name := expr` (on a whole local, outside a loop
  carry or branch join) may change `name`'s type (e.g., `xs := seal self`,
  `xs := freeze self`), reusing the underlying allocation in place.
- **In-place reuse & FBIP:** Updating an array path (`rows[i] := ...`) or
  reconstructing a matching data variant on a linear local reuses storage in
  place with zero allocation. If the compiler cannot prove linearity at an array
  update, it rejects the statement with an error suggesting `copy` or `own`.
- Rebinding an outer local inside `if`, `if let`, statement `case`, `with`, or
  `for` carries out to the statements that follow (types must match at joins and
  loop backedges).

### 9.3 Ownership, Borrowing, `own`, `freeze`, and `copy`

1. **Inline values** (scalars, tuples, flat records/enums containing no heap
   arrays) copy implicitly in `O(1)`.
2. **Linear ownership inside a function:**
   - A local is linear when bound to an array literal, comprehension, `copy`,
     call result, or `own` parameter, and remains linear across its own `:=`.
   - Record fields are **independently linear along disjoint paths**: borrowing
     `world.terrain` does not prevent shadowing `world.robots.pos[i] := ...` in
     the same expression or statement.
   - Binding a read alias or iterating with `for` temporarily borrows the owner;
     linearity returns automatically after the borrow's last read.
   - Moving a local at its last read transfers linearity (`let r = $Box xs`).
3. **Across calls (no cross-call inference; signatures decide):**
   - Default parameter = **borrowed** (read-only; cannot be shadowed in place or
     returned in an owning position). Lending an argument does not end the
     caller's linearity.
   - `own` parameter = **taken linearly**. The argument must be linear (or a
     disjoint linear field of a linear local). The caller's name/field is spent
     until shadowed again (`let (plan, w) = step world dt; world := w`).
   - Every non-`entry` call result is linear and belongs solely to the caller.
   - Partial application cannot supply an `own` parameter unless the whole call
     is saturated.
4. **Explicit `copy` and `freeze`:**
   - `copy x`: explicit independent linear clone (`O(n)`). When `x` is already
     linear at its last use, `copy x` compiles to a zero-cost move.
   - `freeze x`: `O(1)` linear transfer `own T -> *T` (same memory, zero copy).

### 9.4 Speculative Shadowing: `fork`

```blot
let score = fork world:
  let (_, w) = step world candidate_move
  world := w
  return evaluate world
// Outer `world` is bit-for-bit untouched!
```

- `fork x:` takes one or more linear locals, allows shadowing them freely inside
  the suite (including passing them `own` to helpers and updating arrays/pushing
  to `#[+T]`), and produces the suite's returned value.
- **Semantics:** Identical to copying each listed local before the suite and
  discarding the copy on exit.
- **Cost:** `O(edits)` via a scratch undo journal recording overwritten words
  and prior lengths, replayed in reverse on exit—never an `O(size)` upfront
  copy.
- **Rules:**
  - The listed linear locals cannot be returned out of `fork` (return computed
    results, scalars, or an explicit `copy` of a small slice).
  - Inside `fork`, `Foreign` effects are forbidden (speculative work must be
    pure or locally handled).

### 9.5 Conditionals, Loops, Leaving & Statements

- `if cond:` / `if let pat = expr:` / `else if` / `else:`.
- `for ever:`, `for start..end:`, `for pat in range_or_collection:`.
- `return expr` (or `return use call`) leaves the innermost function (or `fork`
  block). `break` leaves the innermost loop; `continue` starts its next
  iteration.
- An expression used as a statement must have type `Unit`; discard non-`Unit`
  values explicitly with `let _ = expr`.

### 9.6 Scoped Effect Handlers: `with`

```
WithStmt  = "with" WithEntry,+ ":" Suite
WithEntry = TypePath "=" "{" HandlerField,* "}"
          | Expression
```

```blot
let lines: #[+Text] = #[]
with Log = { write: func msg => lines := self.push msg }:
  use run_game ()
```

- `with` installs one or more effect handlers for its suite and all transitive
  calls inside it. Handlers are **strictly scoped (non-escaping)**.
- A handler may be a pre-built pure effect record (`with quiet:`) or an inline
  scoped handler (`with Log = { ... }:`).
- An inline scoped handler may:
  - capture outer locals (including `Foreign` host callbacks);
  - perform outer effects (those effects become effects of the `with` statement);
  - **linearly shadow outer locals** (`lines := self.push msg`). While inside
    the `with` suite, any outer local shadowed by the handler is exclusively
    owned by the handler (inaccessible directly from the suite body) and returns
    to the outer scope with its final shadowed value when `with` exits.

### 9.7 Effects: `use`

```
UseStmt = "use" (Pattern (":" Type)? "<-")? Expression
```

- Every call whose target has a non-empty effect set must appear in `use pat <- call`,
  `use call` (discarding the result), or `return use call`.
- `use` on a pure expression is an error.
- `use` statements execute strictly in source order; pure code between them may
  be reordered, shared, or eliminated while preserving traps.

---

## 10. Compile-Time `#run` and Typed `#for` / `#if`

### 10.1 Value Evaluation: `#run`

`#run expr` evaluates a pure expression during compilation under a bounded step
budget and embeds the resulting value (scalars, records, arrays, lookup tables,
parsed build assets via `std/build.include`). It cannot perform `Foreign` IO or
read module-level `let` bindings. Traps during `#run` are compile errors.

### 10.2 Typed Body-Only Reflection: `#for` and `#if`

```
ComptimeFor = "#for" LowerName "in" ("#fields" | "#variants") TypeAtom ":" Suite
ComptimeIf  = "#if" Expression ":" Suite ("#else" ":" Suite)?
```

```blot
func derive_encode (own out: #[+U8]) -> (val: t): #[+U8] =>
  #for field in #fields t:
    #if not (field.has_tag Codec.Skip):
      out := Encode.encode self val.(field)
  return out
```

- `#for` and `#if` appear **only inside function or `const` bodies**, so module
  interfaces remain 100% known after parsing.
- During monomorphization for a concrete type `T`, `#for field in #fields T`
  unrolls its suite once per field of `T` (and `#variants T` once per data
  constructor), type-checking each unrolled iteration with ordinary Blot rules.
- `val.(field)` projects the compile-time field from `val`; `field.name`,
  `field.has_tag`, `field.tag`, and `field.has_default` inspect field metadata
  and `@[...]` tags at compile time.
- Untyped `#quote` / `#(...)` AST splicing is not part of the language.

---

## 11. Dynamic Traps

The following conditions trap the current Wasm invocation (uncatchable):
- Array index or slice range out of bounds (when not statically eliminated by
  `#[T]`, `#[+T]`, or `#[n; T]`).
- Integer division or remainder by zero, or `MIN / -1` on signed integers.
- Explicit `panic "message"`.
- Appending beyond planned/available linear memory, or stack exhaustion.
- Invoking a host `Foreign` callback after its originating invocation ends.

Integer `+`, `-`, `*` wrap deterministically at bit width; floats follow IEEE 754.

---

## Annex A. Retired Forms (Removed From Earlier Blot)

| Retired | vNext Replacement |
| --- | --- |
| `Array T`, `GrowArray T`, `ResizeArray T` | `#[T]`, `#[+T]`, `#[~T]`, `#[n; T]` |
| `List T`, `[...]`, `[head \| tail]`, `std/list` | `#[T]` / `#[+T]` |
| `&T`, `&[T]`, `^T`, `Ref`, `View`, `Link` | Lexical read borrows, `#[T]`, `*T`, typed indices |
| `=` mutable store, `lent` functions, `@storage.write` | `:=` on `own` values + `let (a, w) = ...; x := w` |
| First-class escaping capturing closures | 2A templated downward closures, `A -> B` fn ptrs, `*(A -> B)` frozen closures |
| Open effect-row variables (`! {\| e}`) | Closed effect sets (2A templates propagate callback effects) |
| Built-in `State` / `@effect.state/run/reader/writer/provider/scope` | Scoped `with Effect = { ... }:` handlers shadowing outer locals |
| `@computation`, `@requests`, `yield`, `complete`, `do (monad ...)` | Ordinary `let ... else:` and `with` |
| `is contract`, `impl`, `@type.call`, string predicates (`associated`, `field`, `result`, `type_eq`) | `is trait`, `const Type.Trait`, named outputs `{ out }` |
| Row-polymorphic records, `@record.merge`, `std/path` | Closed structural records |
| `forall`, `exists`, `pack`, `unpack`, `@code.*`, `@proof.*`, `@usage.*` | Monomorphized generics, `#[n; T]`, `#run`, `#for` |
| Untyped `#quote` / `#(...)` macros | Typed body-only `#for` / `#if` over `#fields` / `#variants` |
| `=> return do:` with `break value`, `#do:` | `=> expr` or `=>` suite with `return`; `break` is loop-only |
| Custom `infix`/`infixl`/`infixr`, `\|>`, `$` app, `.x` selectors, `:x` witnesses | Fixed operator table, `.name` chaining, explicit type args |
| `Bool.not`, `@panic`, `@hole`, `@storage.copy` | `not`, `panic`, `_`, `copy` |

---

## Annex B. Implementation Details to Settle During Rollout

1. **`*T` reclamation policy:** Linear values pay zero refcounting. For
   long-lived `*T` (e.g., 64-frame history buffers), choose between opt-in
   per-allocation refcounting on `*T` only vs. explicit region/arena ownership.
2. **Length-variable binder syntax:** Confirm whether `#[+n; T]` binds `n`
   implicitly inside a `data` declaration / `func` header (like lowercase type
   variables `a`) or takes an explicit binder.
3. **Host ABI transition:** Expanding numeric widths (`U8..U64`, `I8..I64`,
   `F64`) and UTF-8 `Text` (`#[U8]`) coordinates with guest ABI 8 / save schema
   26 migration timing across `Pen`, `Ink`, and `Gdev`.
