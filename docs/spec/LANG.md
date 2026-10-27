# Blot K1: normative language, contracts, and relational data

**Specification ID: K1-LANG. Edition: K1 revision 1, 26 October 2026.**
**Parent and full handoff:** [Language design program — issue #37](https://github.com/mewhhaha/blot2/issues/37). Read K1-LANG, K1-MEM, K1-CORE, and K1-EXEC together; the parent links every part.

**Status:** proposed implementation specification. These rules deliberately break current Blot syntax and behavior where needed. They are the acceptance contract for the K1 mode; they are not a claim that the current compiler already implements them. The memory/ABI and compiler/validation chapters complete this specification. “Must” is a requirement, not a future suggestion.

## 1. What acceptance means

A successfully checked K1 program has no unchecked array access, integer operation with undefined or unintended overflow, use of uninitialized storage, use after an ownership move, escaping loan, or incompatible domain substitution within the safe language. Every ordinary function completion is explicit. Every fallible primitive returns a value representing failure. User storage has no tracing collector, cycle collector, or per-value reference counting.

These are specified safety and contract properties. Acceptance does not establish an unstated business requirement, prove a numerical algorithm accurate, guarantee that a requested backing reservation succeeds, or prove the memory consumption of a browser, JIT, operating system, or host application. Incorrect contracts cannot be trusted merely because they appear in source: implementations must establish their postconditions, effects, usage, and resource bounds before publication.

Required checking runs before optional optimization. The same source, semantic policy, and imported interfaces must receive the same acceptance verdict with optimization disabled, with different worker counts, and with cold or warm caches. A failed K1 obligation must never fall back to permissive legacy checking.

## 2. Source conventions and grammar

K1 uses indentation-delimited suites, two spaces per indentation level, and no indentation tabs. A syntactically incomplete declaration/header continues one indentation level relative to that original declaration/header; a leading `=` may instead align with its original declaration. A suite starts two spaces below its final header line. Identifiers are ASCII letters or underscore followed by letters, digits, or underscores. `//` starts a line comment. `()` is Unit; `#True` and `#False` are Bool. Unsuffixed integer literals denote U32 and must fit. A decimal literal containing a decimal point or exponent denotes F32 and is rounded once to binary32. There are no implicit scalar conversions. General strings, text interpolation, and user-defined literal syntax are outside K1; quoted module paths remain compiler metadata.

The following is the normative structural grammar. Ordinary precedence parsing supplies `expression`; comma-separated lists may be empty only where the production says so. Newlines inside parentheses, brackets, or braces are whitespace.

```text
import       := "import" quoted_path "as" name
declaration  := "pub let" name ":" type "=" expression
              | "let" pattern [":" type] "=" expression
              | "static let" pattern [":" type] "=" expression
              | ["pub"] "type" name ["[" binders "]"]
                ["where" "[" constraints "]"] "=" type
function     := "fn" ["in" name] pattern "=>" function_body
function_body:= "return" expression | "do:" suite
statement    := declaration | expression | "return" expression
              | "break" [expression] | "continue"
              | ("next" | "stop") "(" expressions ")"
              | ("seal" | "abort") "(" expression "," expression ")"
              | "if" expression ":" suite ["else:" suite]
              | "case" expression ":" arms
value_do     := "do:" suite
for          := "for" name "in" expression ".." expression
               ["carry" "(" carries ")"]
               ["invariant" "[" facts "]"] "do:" suite
carry        := name "=" expression
pattern      := name | "_" | "()" | "(" patterns ")"
              | "{" named_patterns "}" | "(" pattern ":" type ")"
type         := name | "(" types ")" | "{" named_types "}"
              | "#" name ["(" type ")"] | type "|" type
              | name "[" type_arguments "]" | type "->" type
              | "forall" "[" binders "]" ["where" "[" constraints "]"]
                "=>" type
              | "exists" "[" binders "]" "=>" type
fn_suffix    := ["!" "{" effects "}"]
               ["requires" "[" facts "]"] ["ensures" "[" facts "]"]
               ["on_true" "[" facts "]"] ["on_false" "[" facts "]"]
               ["resources" "{" "depth:" integer "," "frame:" integer "}"]
binder       := name ":" ("Type" | "Region" | "Nat" | "Domain")
constraint   := ("Plain" | "Share") "(" type ")"
effect       := ("read" | "write" | "place" | "reset") name
              | "reserve" | "release" | "host"
fact         := ("Eq" | "Lt" | "Le" | "AddFits" | "SubFits" | "MulFits")
                "(" term "," term ")" | "Index" "(" name "," term "," term ")"
term         := integer | name | term "." selector
              | ("Len" | "Cap" | "Init") "(" term ")" | "MAX -" term
```

The suffix attaches to a callable type after its argument/result types; its clauses do not attach to an enclosing tuple or forall. `A -> B` associates right; an arrow result containing its own suffix must be parenthesized. Lists use commas. `arg`, `result`, and in-scope Nat binders are the permitted interface term roots; local invariants additionally use visible bindings. `.length` and `.capacity` elaborate to their observations. Type arguments are types, kind-appropriate names, Nat literals, or the special Owned Region hole. `static` names the builtin permanent Region. Body-only `local` names the current lexical activation, respecting block and loop-iteration limits; it grants no Owner/Space and cannot escape or occur free in a public signature. It permits explicit callback instantiations such as `map@[local,...]` without heap placement. Many/Once and Append/Resize are closed builtin mode tags, not user-quantifiable kinds.

Reserved words are `import`, `as`, `pub`, `let`, `static`, `local`, `type`, `fn`, `in`, `do`, `return`, `break`, `continue`, `next`, `stop`, `seal`, `abort`, `if`, `else`, `case`, `for`, `carry`, `invariant`, `forall`, `exists`, `where`, `requires`, `ensures`, `on_true`, `on_false`, `resources`, `region`, `owned`, `pack`, and `open`. Region/owned also prefix their fixed namespaces. Effect names and resource keys are contextual keywords. Builtin type/mode names and namespaces `region`, `owned`, `space`, `dest`, `env`, `builder`, `view`, `index`, `array`, `U32`, and `F32` cannot be rebound. Fixed intrinsic selectors such as `array.in` are recognized in their namespace despite reserved-word spelling.

Each UTF-8 source file is a module. Imports precede declarations and use `import "./relative/path.blot" as module`; names are selected as `module.name`. Paths resolve relative to the importing file inside the explicitly supplied package root. Reject absolute paths, parent escape, symlink escape, duplicate aliases, and import cycles. Only `pub` declarations are exported. There are no wildcard/re-export imports, implicit downloads, or runtime module initialization; top-level values are static Share data or checked Many functions. Static affine globals are rejected. Package-root mappings and canonical module hashes are artifact inputs.

`case` has arms `pattern => statement` or `pattern => do: suite`. Refutable patterns are one top-level constructor with an irrefutable payload pattern, a scalar literal, or `_`. Arms must be disjoint and exhaustive; `_` can occur only last. Nested discrimination uses nested case statements. Guards, or-patterns, and a general pattern-matrix solver are absent. A case-arm suite is not a value do; producing a case value requires an enclosing value do and explicit breaks.

Calls use parentheses: `f(x)` supplies one argument, `f(x, y)` supplies the single tuple `(x, y)`, and `f()` supplies Unit. Generic application is `f@[T, r, n, d](argument)`; `a[i]` is always element access. Fields use `.name`; tuple components use `.0`, `.1`, and so on. Generic type application uses `View[r, T, n, d]`. Constructors use `#Ok(value)` or a nullary tag such as `#None`. Records are `{name: value, ...}`. Record field order in a declaration determines layout; structural type equality compares the same canonical field sequence.

Every function accepts one irrefutable parameter pattern. A tuple is one value; automatic currying and multi-parameter desugaring are removed. Refutable parameter patterns, omitted tuple fields, and duplicate binders are errors. To curry, return another function explicitly.

`let` evaluates its initializer once and binds an immutable value. It can name an effectful computation when the enclosing contract permits that effect. The old semantic distinction between `let` and `use` is removed. There is no `:=`, implicit type-changing rebinding, branch-local rebinding export, or assignment to ordinary fields. Mutation happens through explicit exclusive capabilities and collection primitives. An expression statement is permitted only for Unit; other values require a binding or explicit control transfer.

Evaluation is left to right: callee, argument components, record fields, arithmetic operands, and constructor payloads. Ordinary Share arguments copy with their loans preserved; affine arguments move. Affine field moves require complete destructuring. Only registered observations borrow without moving: builder reads/length/capacity observations, plus owned.open. View observations copy immutable loans. Once calls consume the callee; Many calls copy it. Simplification must preserve ordering wherever failure, effects, ownership, or termination makes it observable.

Operators have this fixed precedence, strongest first:

| Level | Forms | Association |
|---|---|---|
| 1 | call, generic application, field, index | left |
| 2 | `!`, `~`, floating unary `-` | right |
| 3 | `*`, `/`, `%` | left |
| 4 | `+`, `-` | left |
| 5 | `<<`, `>>` | left |
| 6–8 | `&`, then `^`, then `\|` | left |
| 9 | `<`, `<=`, `>`, `>=` | nonassociative |
| 10 | `==`, `!=` | nonassociative |
| 11–12 | `&&`, then `\|\|` | left, short circuit |

Comparisons cannot chain. Operators are closed intrinsics; there is no user operator overloading, implicit trait search, associated-type reduction, or custom precedence. Use an explicitly passed function dictionary for generic operations. There is no pointer, View, or function equality primitive.

`static let` requires successful evaluation in the bounded required-static evaluator. It cannot perform placement, backing reservation, host operations, or observation of runtime identity. Ordinary `let` does not request compile-time evaluation. Static failure or exhaustion is a compile error, not an invitation to run the initializer at runtime.

## 3. Explicit completion and control targets

Every reachable normal function path must execute `return expression`. No final expression supplies a return value; Unit functions also write `return ()`. Each of these definitions is valid and has the same result behavior:

```blot
let a: U32 -> U32 = fn x => return x

let b: U32 -> U32 = fn x => do:
  return x

let c: U32 -> U32 = fn x => return do:
  break x
```

The body `do` immediately following `=>` is a function-body suite. Other `do` expressions introduce value-block targets and require `break value` on every normally completing path. There is no implicit Unit for a value block. `return` exits the nearest enclosing function. `break value` exits the nearest lexical value `do`; it never means loop exit. Bare `break` exits the nearest loop without carries. `continue` advances such a loop. `next (...)` advances the nearest loop with carries.

A function boundary resets all return, block, and loop target stacks. A nested function cannot break a caller’s block or continue a caller’s loop. `if`, `case`, and loop suites introduce scopes, but no value-block targets. A control operation without a target is `k1_bad_control_target`.

A return operand evaluates once. If evaluation itself executes a return, that inner return transfers control and the pending outer return never executes. All transfers account for live affine values and loans at their target. Moving a result out of a scope does not lengthen the lifetime of storage it borrows.

Required reachability recognizes literal conditions, exhaustive constructor cases, impossible states established by the specified finite facts, and unconditional control transfers. It does not invoke the optional optimizer to decide whether a missing return is harmless. Code after an unconditional transfer is rejected as unreachable, rather than silently becoming an unchecked region of the program. Potentially reachable fallthrough is `k1_missing_return`.

## 4. Types, kinds, and usage classes

The scalar runtime types are Unit, Bool, U32, and F32. Fixed tuples, records, and tagged sums are admitted. User `type` declarations are transparent aliases, not opaque nominal wrappers. All declared type dependencies must form an acyclic graph, including references through Fn and View. Recursive data types and aliases are outside K1. Builtin authority types, Index, and Result retain their specified distinct identities through aliases.

The generic kinds are `Type`, `Region`, `Nat`, and `Domain`. Nat denotes an integer in `0..U32.MAX`, not an unbounded mathematical natural. Region names lifetime/storage authority. Domain names the identity of an immutable indexed collection. Region and Domain are not integers and cannot be produced by casting.

Each Nat has a recoverable runtime U32 witness unless it is a known constant. A View length or Builder length can supply it at a call boundary when the completed ABI designates that field. Every existential package stores one U32 prefix word per hidden Nat binder, in binder order, followed by its payload; K1 does not deduplicate that prefix against payload lengths. A function accepting a Nat independently receives its witness as a hidden ordinary integer argument. Proof evidence, Region, and Domain have no runtime tag. Erasing a proof must never erase a numeric value needed by execution.

The collection and ownership forms are:

```text
RegionOwner[r]
Space[r]
Dest[r, T, c]
EnvDest[r, c]
Builder[r, T, n, c, Append]
Builder[r, T, n, c, Resize]
View[r, T, n, d]
Index[d, n]
Fn[r, Many, A, B]
Fn[r, Once, A, B]
Owned[P]
```

The memory chapter defines their transition signatures and byte layouts. `n` is initialized length; `c` is capacity. Capacity is never evidence of initialization. Unit elements occupy zero bytes but still require logical bounds. An empty View has no valid Index.

`Plain(T)` means a fixed-layout, copyable, independently discardable value with no borrowed address, callable environment, owned resource, or drop action. Scalars, Index, and finite products/sums of Plain values are Plain. K1 arrays store Plain elements only, with an element limit of 16 Wasm32 words. This admits numeric rows and graph endpoints, but excludes arrays containing Views, functions, owners, or nested dynamic arrays.

`Share(T)` includes Plain values, immutable Views, Many functions, and finite products/sums of Share values. Copies retain borrowed region footprints. Ordinary records can contain Views/functions even though those records are not array elements. Existential Nat/Domain packages inherit Plain/Share from their payload, subject to their complete prefix-plus-payload layout. Aggregate/result descriptors are limited to 64 Wasm32 words; closed sums have at most four constructors. These are profile limits, not optimizer heuristics.

Owners, remaining-space tokens, destinations, builders, Once functions, and Owned values are affine. A general `T: Type` is conservatively affine: identity can move T, but cannot copy/discard it without a published constraint or callback. Affine products require complete destructuring; there is no partial-move bitmap. An unused Once may explicitly be discarded with `_` because its captures own no resources. Live ownership capabilities require their specified terminal transition.

`Result[T,E]` is a distinct builtin affine must-handle wrapper, never Plain or Share even when both payloads are Plain. It must be matched, returned, or transferred to a function that accepts it. Placing it inside another aggregate preserves this obligation. `_` cannot discard Result or an ownership capability. Its `#Ok`/`#Err` constructors require a Result expected type; a transparent alias cannot erase that identity into a copyable sum. Explicitly handling an error may recover, return another error, or deliberately return Unit. `Option[T]` is the ordinary structural sum `#None | #Some(T)` and has the classes of its payload.

Declared types have derived `LayoutFits` obligations. The checker publishes these in the interface and evaluates the fixed bounded layout expressions at instantiation; it does not recheck a generic body. A Result tag or existential Nat prefix counts toward the descriptor limit. A 256-byte payload cannot fit inside an additional tagged 256-byte Result slot. Violations report `k1_layout_limit`.

## 5. Generic and callable interfaces

Polymorphism is explicit and rank one:

```blot
pub let identity: forall [T: Type] =>
  Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256}
= fn x => return x
```

Ordinary local bindings are monomorphic. Expected types and annotated parameter patterns support local bidirectional inference; unresolved type variables at declaration completion are errors. An identity lambda with no usable annotation is not silently generalized. A reusable generic must be a declared `forall` boundary, and instantiations supply explicit arguments with `@[...]`. User higher-rank parameters, polymorphic recursion, and existential Type boxing are unsupported.

`A -> B` abbreviates `Fn[static, Many, A, B]`. It denotes callable lifetime, not purity. Capturing callable types state `Fn[r,...]`. Many allows repeated invocation; Once permits at most one invocation and consumes the callable when called. Many can weaken to Once, but not conversely. Noncapturing code can weaken from static lifetime to a shorter valid callable lifetime.

A complete callable type has these suffixes in this order:

```text
Fn[r, mode, A, B]
  ! {effects}
  requires [facts]
  ensures [facts]
  on_true [facts]
  on_false [facts]
  resources {depth: integer, frame: integer}
```

Empty fact clauses may be omitted. The Boolean clauses are legal only when B is Bool. Public declarations must state their complete input/result types, effects, and finite resource bounds. Private acyclic declarations may synthesize missing effect/resource suffixes; the completed artifact still contains all fields. Every function-typed parameter or returned callable must have a complete contract. Missing imported slots are `k1_incomplete_interface`, never a request to inspect a callee’s source body.

Contract roots are reserved `arg` and `result`, with field/tuple selectors; named Nat parameters can also appear. Contract meaning therefore does not depend on lambda-local parameter names. Preconditions must hold at every call. Postconditions must hold at every normal return. Boolean predicates publish only facts actually established for their true and false results. Public facts cannot refer to an undocumented environment field; private capture evidence is represented by the checked capture mapping.

Effects are `read r`, `write r`, `place r`, `reset r`, `reserve`, `release`, and `host`. A callable lists an upper bound. Private-region read/write/place/reset effects discharge when that storage scope closes/seals with complete nonescape checks. An owned.open also hides its private read effect when its lexical borrow ends; it cannot hide write/place/reset. Latent reserve/release/host and caller-region effects remain public. Core retains exact release targets. Capture footprints and exposed regions remain in the interface. K1 has no user effect handlers, exceptions, tasks, suspension, or arbitrary host imports. Only the specified runtime/bridge boundary is allowed. Read authority never permits View mutation.

Resource fields are closed U32 upper bounds in K1; symbolic resource polymorphism is deferred. `depth` lies in 1–128 and bounds nested K1 calls including this invocation. `frame` bounds peak live **K1-managed linear-memory frame bytes**, including callees; it does not describe engine/JIT/native stack bytes. The validator establishes `1 + max(callee.depth) <= caller.depth` and `own_frame + max(callee.frame) <= caller.frame`, with zero maxima for a leaf. Direct and indirect calls obey the same rule. A code handle must satisfy the contract under which it is called. Weakening can increase either bound, never decrease it. These rules reject dynamic callback cycles as well as named recursion. The host must support the separately declared call/local envelope.

Function subtyping is deliberately limited: exact argument/result types, identical requires/ensures clauses, effect-set widening, lifetime shortening where valid, Many-to-Once weakening, and resource-bound widening. There is no general variance or predicate-implication search. An explicit adapter function handles other changes and is checked normally.

## 6. Closures and explicit environment placement

Closures capture Share values only, transitively. Capturing another Many function supports composition. Capturing a RegionOwner, Space, destination, Builder, Owned value, Result, or Once function is rejected. Pass affine state explicitly through arguments/results. Invocation mode does not grant permission to hide an owned resource inside an environment.

A nonescaping ordinary `fn` may place its fixed environment in the current frame. An escaping captured function requires an explicit destination:

```blot
let add_bias = fn in env_dest (x: F32) => return x + bias
```

`env_dest` is a previously bound `EnvDest[r,c]` from `env.try_alloc`; bind a more complex destination expression first. The function expression consumes it. Its computed aligned environment must fit c, otherwise `k1_environment_capacity` reports the required size. There is no hidden box. Captured loans must outlive the callable, whose interface includes lifetime, effects, footprints, and resources.

Owned construction is the sole region-hiding mechanism. Its payload is Share and can refer only to the owned region or static data. `Owned[Fn[...Many...]]` supports independently escaping captured functions. Owned payloads cannot contain nested owners or Once callables. Moving an Owned handle moves authority, not backing bytes; ordinary closure placement never implies ownership transfer.

`#[]` remains the sole array literal family. `array.in(dst, #[e1,e2])` is a contextual construction intrinsic: evaluate/consume dst first, then evaluate and initialize its Plain elements left to right, prove their count fits capacity, and return a frozen existential View. Account for the held destination on any early transfer. Array literals are otherwise legal only as required-static initializers. There is no implicit heap literal. Append/Resize behavior belongs to named constructors and types, not additional bracket spellings.

### Lexical region and Owned forms

These reserved construction forms use explicit generic-value notation:

```text
region_scope := "region@[" type "](" expression ") as" name
                "(" name "," name ") in do:" suite
owned_scope  := "owned@[" schema "," type "](" expression ") as"
                name name "in do:" suite
owned_open   := "owned.open(" expression ") as" name name "in do:" suite
```

`region@[T](bytes) as r (owner,free) in do: ...` returns `Result[T,ReserveError]`. Failure produces Err without executing the body; success introduces fresh r, RegionOwner[r], and Space[r]. Every body exit must end descendants, call `space.end(final_space)`, and call `region.close(owner)` before leaving. Its value-do result T cannot retain r. `region.reset(owner)` similarly requires ended descendants/frontier and returns the owner plus fresh Space/epoch. There is no implicit cleanup bypass. `region.reserve` and `owned.begin` are internal elaboration primitives, never source-callable functions returning an existential Region.

Loans end lexically, not through unspecified last-use inference. A View/closure/package binding keeps its loans until its scope ends. Before reset/close, put temporary borrowed values in an inner do/open and let that scope finish; only permitted independent values and surviving capabilities leave it. Core records those explicit scope endings. K1 does not require nonlexical loan analysis.

`owned@[P,E](bytes) as r free in do: ...` returns `Result[Owned[P], #Reserve(ReserveError) | #Body(E)]`, requiring Plain(E). P is a payload schema with exactly one internal Region hole, for example `Graph[_,U32]`. That hole is allowed only in Owned schema syntax; it introduces no general higher-kinded polymorphism. A region-independent payload may use a declared one-Region alias whose parameter is unused. The runtime reserves the separate root capsule plus working bytes. The source exposes Space[r] and retains the BuildingOwned construction authority internally; ordinary RegionOwner/reset/close operations are unavailable for it.

The owned body must end with `seal(final_space,payload)` or `abort(final_space,error)` on every path. Seal checks P[r], internalizes its permitted loans, consumes construction authority/frontier, and yields Ok of Owned[P]. Abort checks E, ends all local descendants, consumes the frontier, releases the region, and yields Err(#Body(error)). Both require every other exclusive capability discharged; abort cannot leak r in its error. No outer return/break may bypass these terminals. A function boundary resets construction targets along with control targets. Reservation failure is Err(#Reserve(error)).

`owned.open(handle) as r payload in do: ...` borrows the handle, introduces fresh hidden r and payload of P[r], and yields the block result. Neither r nor an opened package brand may escape that result. Open exposes no reset/release authority. Afterwards the owner can be moved or explicitly consumed by `owned.close(handle)` when all openings have ended.

## 7. Finite loops and explicit carries

K1 has finite half-open `for` loops only. The bounds evaluate once and require `lo <= hi`; `lo == hi` executes zero iterations. The saved bound and iterable identities remain fixed. Iteration i establishes `lo <= i < hi`. The compiler-controlled increment executes only when `i < hi`, so the next value cannot overflow U32. No final increment beyond hi occurs.

A loop without carries yields Unit and requires `continue`, bare `break`, or another explicit control transfer on each body path. A loop with carries evaluates its initial values once, introduces fresh current bindings each iteration, and returns their final tuple; a single carry is unwrapped. Every continuing path writes `next (values...)` with the same arity. `stop (values...)` exits immediately with those carries and proves the invariant at the current i, without incrementing it. Zero iterations return the initial values. Bare break/continue are rejected for carry loops. An enclosing `do` can be exited with `break value`, provided all live carried resources are accounted for in that transfer.

Carry types keep the same constructor, region, element type, capacity, mode, and domain structure. A Builder’s initialized Nat can change through checked transitions. Each iteration and the result receive fresh witnesses constrained by the invariant/exit intersection. A stop result is not silently assigned length hi; exports must explicitly quantify/package any remaining fresh witness. Arbitrary type-changing loops are unsupported. Body facts do not automatically become invariants.

An invariant is a finite conjunction checked at entry and assumed at the body header. Next checks `I[i := i+1, carries := next_values]`; stop checks `I[carries := stop_values]` without increment. Natural exhaustion has i=hi; stop retains current i. Join those exit facts without assuming i=hi when stop is possible. No inferred induction or fixed-point widening occurs. Range facts are automatic. This example uses the memory chapter’s Builder primitives:

```blot
pub let copy_into:
  forall [r: Region, s: Region, T: Type, n: Nat, c: Nat, d: Domain]
  where [Plain(T)] =>
  Fn[static, Many,
    (View[r,T,n,d], Builder[s,T,0,c,Append]),
    Builder[s,T,n,c,Append]]
  ! {read r, write s}
  requires [Le(n,c)]
  resources {depth: 1, frame: 256}
= fn (source, initial) => do:
  let built = for i in 0..n carry (b = initial)
    invariant [Eq(Init(b),i)] do:
      next (builder.append(b, source[i]))
  return built
```

The invariant proves the read bound and append capacity independently, then proves the output length at exit. The backend must check the stated frame bound; the number 256 is an upper-bound assertion, not permission to truncate a larger frame. Builder operations in this example lower to kernel primitives; any helper call contributes its actual resource summary.

Source recursive binding strongly connected components, including self-reference passed as a value, are rejected with `k1_recursive_call`. `while`, unbounded `loop`, recursion through recursive types, and direct self-tail recursion are deferred. Finite loops plus bounded higher-order calls are the complete K1 iteration mechanism.

## 8. Scalar operations and failure

U32 represents `0..4_294_967_295`. Ordinary arithmetic has these required preconditions:

| Operation | Required fact |
|---|---|
| `x + y` | `AddFits(x,y)` |
| `x - y` | `SubFits(x,y)`, equivalent to `y <= x` |
| `x * y` | `MulFits(x,y)` |
| `x / y`, `x % y` | `0 < y` |
| `x << k`, `x >> k` | `k < 32` |

Shifts have fixed-width bit semantics: left shift discards high bits after validating the count. Arithmetic multiplication does not silently become a shift. Unsigned unary minus does not exist. Bitwise operations are total. `U32.wrapping_add`, `wrapping_sub`, and `wrapping_mul` explicitly compute modulo 2^32. Dynamic alternatives `U32.try_add`, `try_sub`, `try_mul`, `try_div`, and `try_shift_left/right` return Result, with the corresponding success facts attached to the selected payload. There is no implicit panic for an unproved ordinary operation.

`U32.fits_add`, `fits_sub`, and `fits_mul` are trusted Boolean intrinsics with verified true/false contracts. Fits-multiply must use a checked arithmetic implementation or zero/division guards; it must not perform the possibly overflowing multiplication to decide whether multiplication fits. Conversions from F32 or host integers are explicit fallible intrinsics and never mint a valid Index directly.

F32 follows Wasm f32 semantics: separate rounding, exact non-NaN results including signed zero, and the specified [NaN propagation sets](https://www.w3.org/TR/2025/CRD-wasm-core-2-20250616/#nan-propagation). With no noncanonical NaN input, an arithmetic NaN result is canonical with either sign; otherwise the permitted arithmetic quiet-NaN set applies. Loads, stores, and copies preserve every bit; negation changes only the sign bit. Only arithmetic has this NaN nondeterminism. Required-static evaluation chooses positive canonical NaN deterministically. No source bitcast exposes payloads; host/differential comparisons accept the specified result set. Integer proof rules do not apply to F32 comparisons. F32 division by zero needs no U32 nonzero fact. `%`/bitwise/shifts are U32-only. Reassociation, implicit FMA, and fast-math are forbidden.

## 9. Required finite proof checking

### 9.1 Terms and facts

The required checker uses a small closed algebra, extending the existing numeric proof terms instead of importing an SMT solver. Terms identify literals, formal components, capture components, immutable SSA versions, saved length/capacity/initialized-length observations, Nat witnesses, and `MAX - x` complements. A checked intrinsic result has an exact operand/result provenance record. This supports narrowly listed transport rules; it is not an arbitrary symbolic arithmetic expression language.

Admitted facts are `Eq(x,y)`, `Lt(x,y)`, `Le(x,y)`, `AddFits(x,y)`, `SubFits(x,y)`, `MulFits(x,y)`, and `Index(d,n,i)`. `Len(view)`, `Cap(builder_or_dest)`, and `Init(builder)` select the corresponding exact witness. `Index(d,n,i)` means that i is a U32 in `[0,n)` associated with domain d. Well-typed View/Builder constructors additionally establish their published initialization and capacity relations. Unknown predicate forms are `k1_unsupported_fact`; they are not interpreted optimistically.

### 9.2 Algorithm and closure rules

Intern terms in deterministic source/provenance order. Equality classes choose the smallest stable term ID. Represent known `<=` and `<` relations as directed edges with a strictness bit; a path establishes `<` exactly when at least one edge is strict. Queries traverse adjacent edges in stable term-ID order. U32’s universal lower/upper bounds and literal comparisons are supplied as axioms. Equality substitution may reuse facts only for compatible term sorts and exact checked provenance.

The complete additional rule families are:

1. Normalize `>`/`>=` by operand exchange. Negating a U32 `<` produces reversed `<=`; negating `<=` produces reversed `<`. Equality/inequality establishes equality on its equality edge. The unequal edge for zero establishes `0 < x`, and for MAX establishes `x < MAX`; unequal arbitrary U32 values otherwise imply no ordering.
2. `SubFits(x,y)` is `Le(y,x)`. `AddFits(x,y)` is `Le(x,MAX-y)` and is symmetric. Complements reverse known order when both complement terms are present; do not generate unbounded new terms.
3. Multiplication fits for literal operands by exact compiler arithmetic, for a zero operand, from a trusted fits predicate, or for a positive literal k when `x <= MAX/k` is established. No unrestricted nonlinear inference is allowed.
4. An exact successful checked addition/subtraction records its operands and result. Equal canonical operands under the same intrinsic establish equal results. For successor, `i < bound` establishes that `i+1` fits and is `<= bound`. Builder append links its new initialized length to that same checked successor. These are the only arithmetic-result transport rules required by K1.
5. A View access using raw U32 i requires `Lt(i,Len(the_exact_view))`. An `Index[d,n]` directly authorizes access only to a View with the same d and n. A successful `index.try_make(view,i)` returns Some of that refined value; failure returns None. A matching Index’s `.value` projection exposes its raw U32 and range fact.
6. Literal length, formal requirements, checked postconditions, and capture substitutions supply facts with recorded provenance. Optional analysis, source-name coincidence, and ABI ordinals cannot supply authority.

The algorithm stores a finite graph and answers queries on demand; it must not materialize all transitive pairs. Congruence is limited to the explicitly listed intrinsic observations/results. A fact’s validity is tied to the exact SSA value, collection identity, domain, and storage state. A cache hit can replay checked evidence, but cannot skip its logical proof charge.

### 9.3 Branches, joins, and mutation

`if i < a.length:` establishes the access fact on its true edge. If that branch exits, its complement remains on the continuing edge. For `p && q`, q executes under p’s true facts; for `p || q`, q executes under p’s false facts. Facts from an unevaluated operand are unavailable. An arbitrary Bool-returning function contributes no refinement unless its completed Boolean contract supplies it.

At a join, rename incoming values to explicit join parameters and retain the intersection of established normalized facts. A terminated predecessor is omitted. There is no path-disjunction expansion. A join of affine values must transfer exactly one compatible live state on every incoming edge. Inconsistent declared requirements are diagnosed, rather than treating an impossible public contract as a way to validate arbitrary code.

Immutable aliases preserve identity. New values get new versions. A Builder mutation consumes the old state and produces a new one; only its intrinsic transfer contract transports facts. No outstanding builder loan may survive append, resize, set, truncate, freeze, or discard in K1. Frozen Views remain immutable. An unrelated pure call does not invalidate their facts; an effectful call must still respect the ownership/loan interface.

An unreachable branch may be pruned only by the required literal/finite-fact reachability rules. A runtime assertion followed by a trap is not a proof of failure-free execution. Untrusted host data, serialized endpoints, and unchecked casts must enter through explicit validation returning Result. Safe source has no `assume`, unchecked index, or unsafe integer escape hatch.

### 9.4 Budgets and failures

Each completed declaration has limits of **4,096 distinct proof terms, 16,384 active fact/evidence edges, and 65,536 charged proof visits**. Charge term/edge interning, examined adjacency edges, substitutions, intrinsic-rule attempts, and evidence validation. Helper traversals count. Use deterministic logical charges independent of cache warmth, elapsed time, and worker scheduling. The compiler chapter defines the versioned policy identifier and trace format.

The required-static evaluator separately allows **100,000 primitive steps, depth 128, and 4 MiB of produced immutable data per declaration**. All required traversals additionally share a **1,048,576 visit ceiling per declaration**, covering types, effects, usage, layouts, and evidence. These checks never guess on exhaustion. Optional optimization exhaustion instead retains valid baseline code.

Bounds failures use `k1_bounds_not_established`; arithmetic failures use `k1_arithmetic_not_established`. Diagnostics state whether the property is disproved, merely not established, unsupported, or blocked by exhaustion, and identify the missing fact and the conflicting value/state when applicable. A safe program outside this decidable fragment may be rejected; explicit checks and simpler contracts are the supported way to make its proof visible.

## 10. Storable relational data and generative packages

An `Index[d,n]` is a normal **one-word U32 runtime value** whose type records its validated relation. It is Plain and can be stored in records and arrays. It is not an erased proof object pretending to be ordinary data. The length witness belongs to its lexical/type context or package; Index itself does not carry a second length word.

An immutable domain is fresh for every dynamic freeze or slice, including repeated calls at one source site and repeated loop iterations. These primitives return `exists [d: Domain] => View[r,T,n,d]`; ordinary `open` binds that d for subsequent source operations. A static immutable global has its own module-instance domain. Packing existing fields preserves their supplied domains rather than inventing substitutes. Equal lengths, equal contents, or identical source locations do not establish domain equality. The optimizer can share bytes only while preserving distinct semantic identities.

User existential syntax binds Nat and Domain only. Type/Region existential erasure is not available; Owned supplies the checked region-hiding operation. Packing is `pack [witnesses] as Type expression`. Opening is `open expression as [binders] name in do: suite`. The latter introduces fresh rigid lexical binders, checks the suite as a value `do`, and forbids them from escaping in the result unless explicitly repackaged. It retains all ordinary region footprints. Reopening the same package is conservatively a fresh opening in K1; keep related operations within one opening instead of assuming independently opened brands equal.

For example, this is a complete relational type, with no free domain or length variables:

```blot
type Graph[r: Region, T: Type] where [Plain(T)] =
  exists [d: Domain, n: Nat, e: Domain, m: Nat] =>
    {nodes: View[r,T,n,d],
     edges: View[r,(Index[d,n],Index[d,n]),m,e]}
```

The edge collection has its own domain e, while every endpoint refers to the nodes’ domain d. A node row can be numeric data or a Plain user record. Ordinary untyped integers do not become endpoints by being placed in this record.

The constructor sequence is mandatory:

1. Build initialized nodes in their destination and freeze them, obtaining fresh d and final n.
2. Validate each raw endpoint against that frozen node View using `index.try_make`. Handle None explicitly and preserve or dispose every live destination/builder through its specified transition.
3. Append pairs of successful `Index[d,n]` values to the edge builder; freeze it, obtaining e and m.
4. Pack the four witnesses and the two Views as Graph. The checker validates every field under that same witness substitution.

The resulting invariant survives storage and function boundaries without rescanning edges. Zero nodes permits zero valid endpoints, regardless of allocated capacity. A promised future length or spare node capacity cannot validate current endpoints. A malformed input graph returns an error; it never produces a partly trusted Graph.

Matching a package and reading a node is ordinary checked source:

```blot
let value = open graph as [d,n,e,m] g in do:
  case index.try_make(g.nodes, requested):
    #Some(position) => break #Some(g.nodes[position])
    #None => break #None
```

The resulting optional node is Plain and contains no free package brand. Conversely, returning `position` directly from this opening is rejected unless its Domain/Nat are repackaged. An existential index alone remains unusable with an unrelated View until an explicit validation or a matching package provides the relation.

K1 does not thaw a View. Shrinking, reordering, deletion, and structural graph edits construct a new destination and a fresh domain. Previously stored endpoints cannot be silently relabeled. Revalidating their raw values is the default rebuilding operation. A future certified whole-package transport operation can avoid redundant checks, but no unchecked transport or arbitrary quantified record invariant is in K1.

Equal numeric lengths can justify a raw bounds fact for another collection once equality is proved; they still do not justify coercing `Index[d1,n]` to `Index[d2,n]`. This distinction keeps semantic relations intact without requiring a runtime domain tag.

## 11. Required positive and negative behavior

This function accepts dynamic positions and explicitly handles the invalid case:

```blot
pub let lookup:
  forall [r: Region, T: Type, n: Nat, d: Domain] where [Plain(T)] =>
  Fn[static, Many, (View[r,T,n,d], U32), #None | #Some(T)]
  ! {read r} resources {depth: 1, frame: 128}
= fn (a,i) => do:
  if i < a.length:
    return #Some(a[i])
  return #None
```

Without the `if` or a corresponding precondition/refined input, `a[i]` is rejected. Changing `<` to `<=` is rejected for the equality case. Establishing `i < capacity` is insufficient when initialized length is smaller. Proving a bound on one Builder state and then shrinking it does not preserve that fact for the new state. Proving a bound on a frozen View and attempting to reset its live region fails the loan check before an invalid access can exist.

This checked arithmetic idiom succeeds:

```blot
let add: (U32,U32) -> Result[U32,#Overflow] = fn (x,y) => do:
  if U32.fits_add(x,y):
    return #Ok(x + y)
  return #Err(#Overflow)
```

The same body with an unconditional ordinary `x + y` is rejected. `U32.wrapping_add(x,y)` is accepted with explicitly wrapping semantics. `x / 0`, `x << 32`, `a[a.length]`, and an index from another Graph opening are rejected. A floating test such as `x == x` cannot be replaced with true because x might be NaN.

These complete private definitions exercise both lifecycles; their local resource summaries are synthesized:

```blot
let region_unit: Unit -> Result[Unit,ReserveError] ! {reserve,release}
= fn () => return region@[Unit](0) as r (owner,free) in do:
  space.end(free)
  region.close(owner)
  break ()

type UnitPayload[r: Region] = Unit
let owned_unit:
  Unit -> Result[Unit,#Reserve(ReserveError) | #Body(#Cancelled)]
  ! {reserve,release}
= fn () => do:
  let built = owned@[UnitPayload[_],#Cancelled](0) as r free in do:
    seal(free,())
  case built:
    #Err(error) => return #Err(error)
    #Ok(handle) => do:
      let value = owned.open(handle) as r payload in do:
        break payload
      owned.close(handle)
      return #Ok(value)
```

This initialized-array example preserves both allocation failures and closes its inner View loan before region release:

```blot
let singleton:
  Unit -> Result[Result[U32,AllocError],ReserveError] ! {reserve,release}
= fn () => return region@[Result[U32,AllocError]](4)
  as r (owner,free) in do:
    let (rest,answer): (Space[r],Result[U32,AllocError]) = do:
      case region.try_alloc@[U32](free,1):
        #Err((unused,error)) => break (unused,#Err(error))
        #Ok((unused,dst)) => do:
          let packed = array.in(dst,#[41])
          let value = open packed as [d] a in do:
            break a[0]
          break (unused,#Ok(value))
    space.end(rest)
    region.close(owner)
    break answer
```

Builtin type/shape arguments follow their fixed registry schemas; `try_alloc@[U32]` selects T while its r and capacity witness come from actual operands. This is prescribed intrinsic elaboration, not general generic inference.

Conformance must cover paired accepted/rejected cases with optimization off/on, independent artifact validation, and malformed imported evidence. Wasm linear-memory bounds do not substitute for logical object and initialized-prefix bounds.

### Diagnostic category contract

The following is the closed K1 category catalogue. Messages include source origins and specific missing/conflicting facts; structured subreasons do not create new categories. Core/artifact meanings follow the compiler chapter.

| Code | Required meaning |
|---|---|
| `k1_syntax` | Invalid tokens, grammar, or indentation |
| `k1_unbound_name` | Missing/invalidly scoped declaration |
| `k1_type_mismatch` | Incompatible source types |
| `k1_kind_mismatch` | Wrong generic kind or binder usage |
| `k1_nonexhaustive_case` | Missing, overlapping, or forbidden case patterns |
| `k1_effect_mismatch` | Body/call exceeds allowed effects |
| `k1_contract_not_established` | Required nonnumeric pre/postcondition absent |
| `k1_missing_return` | Reachable implicit function/block completion |
| `k1_bad_control_target` | Invalid return/break/continue/next/stop/construction target |
| `k1_bounds_not_established` | Missing initialized-extent fact, including obsolete versions |
| `k1_arithmetic_not_established` | Missing integer operation precondition |
| `k1_domain_mismatch` | Incompatible collection brands |
| `k1_use_after_move` | Reuse or second transfer of consumed authority |
| `k1_usage_not_permitted` | Copy/discard lacks a class/operation contract |
| `k1_ownership_not_discharged` | Live capability lost at an exit |
| `k1_lifetime_escape` | Region/domain binder or loan escapes its scope |
| `k1_loan_conflict` | Incompatible live loan and storage transition |
| `k1_incomplete_initialization` | Publication/read of incomplete typed storage |
| `k1_invalid_capture` | Forbidden capture or capture footprint |
| `k1_invalid_owned_payload` | Owned closedness/Share/payload rule violation |
| `k1_unhandled_result` | Result obligation discarded or hidden |
| `k1_recursive_call` | Source recursive binding component |
| `k1_resource_bound` | Frame/depth bound, including indirect cycles, exceeded |
| `k1_layout_limit` | Derived fixed representation limit exceeded |
| `k1_environment_capacity` | Placed closure environment does not fit |
| `k1_incomplete_interface` | Missing required published contract field |
| `k1_unsupported_fact` | Predicate outside the closed proof algebra |
| `k1_unsupported_feature` | Construct outside the K1 language |
| `k1_source_limit` | Source, nesting, or import-graph ceiling reached |
| `k1_semantic_limit` | Total required semantic traversal ceiling reached |
| `k1_core_limit` | Required completed-Core size ceiling reached |
| `k1_proof_limit` | Required proof-specific budget exhausted |
| `k1_static_limit` | Required evaluation budget exhausted |
| `k1_invalid_artifact` | Malformed or semantically invalid artifact |
| `k1_incompatible_artifact` | Valid artifact under an incompatible policy/ABI |

## 12. Deliberately closed K1 boundary

K1 reports `k1_unsupported_feature` for arbitrary recursion, higher-rank inference, recursive types, general SMT predicates, arbitrary user proof code, custom operators, associated-type search, general effect handlers, continuations, tasks, suspension, hidden allocation, reference-counted fallbacks, dynamic array elements containing references, and user FFI. There is no silent legacy lowering for these features.

The selected restrictions create a complete implementable first language: immutable scalar/record/sum values, bounded arrays and builders, lexical loans, explicitly owned escaping data, first-class functions with finite contracts, explicit Result handling, finite iteration, and stored collection relations. Extensions must add a precise source rule, Core rule, interface representation, validator rule, ABI/resource effect, and positive/negative conformance cases together.

### Implementation anchors

Reuse the existing source concepts where their rules match this specification; do not preserve old permissive behavior merely for compatibility. Pinned starting points are the [numeric proof algebra](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/check/numeric_proof_terms.zig), [Core numeric proof validation](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/check/numeric_proof_core.zig), [package validation](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/check/package_core.zig), and [generative validation](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/zig-native/src/check/generative_core.zig). Current [language behavior](https://github.com/mewhhaha/blot2/blob/1e39b5d8a4268b9edf769c2813d5231abe1c963b/compiler/guide.md) is a migration baseline, not the normative K1 behavior.
