# Language coherence: one small language

Source: the syntax and language coherence review by session blot2-2c on
14 November 2026, relayed to the direct-backend session. The owner's approval,
as relayed: "These are all good suggestions, message the other process that
they should implement it as part of their work". Sequencing against
tasks/FAST_COMPILE.md is still open with the owner.

Several items reverse decisions in NEXT_MIGRATION.md and RFC #46 (section 11).
Update those, DESIGN.md, docs/language/guide.md and LANGUAGE_EVOLUTION.md as
each item lands.

## Premise

Gdev (src + devtools) and Ink (lib), about 56k lines, are written in a small
language: named functions, records and sum types, pattern matching, index
loops, and in-place writes to named arrays passed in access records.

Approximate grep counts:

| Form | Uses |
| --- | ---: |
| indexed writes `a[i] := v` | 1,741 |
| `[0]` on one-element arrays | 1,517 |
| `:=` with `self` | 1,249 |
| `@storage.*` | 884 |
| `Bool.not` | 727 |
| `is contract` / `impl` / `where {` | 1 / 8 / 4 |
| `List` | 2 |

These forms have no uses at all: `is effect`, providers, request handlers,
`do (monad ...)`, `|>`, selectors `.x`, witnesses, `@[tags]`, `#run`, custom
fixity, `@code.*`, `@usage.*`, `@proof.*` and `forall`.

The direction is to make the language those programs are written in the whole
language. Zero use is only evidence: the approved removals are the ones listed
below, nothing more.

## A. Memory model: one model, Goose's

Settle this first. It answers the "later review" in FAST_COMPILE decision 1.

1. Withdraw RFC #46 section 11 together with the matching NEXT_MIGRATION
   bullet and table row: immutable collections, last-use moves and automatic
   copies.
   - That design needs ownership facts to cross call boundaries, which
     decision 1 removes.
   - It hides O(n) copies.
   - It would be a third rewrite of app semantics.
2. Two tiers:
   - Values (scalars, records, sums, closures) are immutable and copied.
     `:=` rebinds a local, and nothing outside the function can observe it.
   - Storage (arrays, pools) has identity and is written in place.
3. Stores into storage get their own operator, distinct from `:=`. The
   compiler rejects the wrong one, so mutation is visible by eye. The spelling
   is open; the review illustrated it as the statement `place = value`.
4. Write authority lives in types.
   - `&T` and `&[T]` become read-only, as RFC section 11.6 already intended.
   - Owner-typed parameters (`Array`, `GrowArray`, `ResizeArray`) are the
     writable form.
   - Today `@storage.write` writes through a `&T`.
5. Add the two owner forms the apps imitate today:
   - A one-value cell, replacing `#[x]` plus `[0]`.
   - An owner group like Goose's `root struct`. It replaces `with_owners` in
     gdev/src/world_storage.blot, which declares about 300 locals and hands
     them to a continuation.
6. Runtime epoch checks stay the safety baseline. Static lifetime checks can
   come later as diagnostics.
7. One meaning per program. The counted backend's snapshot semantics go with
   task 120. `tests/guest/entry_execution.test.ts:67` and
   `tests/guest/development_tier.test.ts:64` still expect `array_snapshot` =
   22 (an alias write is not visible), while the guide says the owned profile
   writes through aliases.

## B. Effects: keep the small core

1. Keep effect rows, `Foreign`, and user effects resolved by lexically scoped
   providers.
2. Drop `use`. Every call is bound with `let x = f ()`, and its effects stay
   in the type. The `let` / `:=` purity rule goes with it. 545 of the 773
   `use` lines in Gdev and Ink are the statement form.

   The review's probes show why:
   - A `Foreign` call as a bare statement compiles with or without `use`.
   - `let x = send 3` is rejected (`let_effect`).
   - A `let` that reads an array just mutated through an alias compiles as
     pure, and so does a `let` bound to a panicking call.
3. Drop:
   - Request handlers: `@computation`, `@requests`, `effect` / `complete`
     clauses and `yield`.
   - `do (monad ...)` with `iterate`.
   - Effect reflection: `@effect.of` / `has` / `count` / `same` /
     `descriptor`.
   - Scoped effect identities: `@effect.scope`, and capability rows such as
     `{state.get}`.

The review did not cover `@effect.state`, `@effect.run`, `@effect.reader` or
`@effect.writer`.

## C. Dispatch: contracts only

This holds the 11 November decision.

1. No static overloads.
2. No `::`; `.` stays the only qualifier.
3. No type values, `#type_of`, validators or `TypeInfo`.
4. Explicit type application replaces witnesses (`:x`, `$Type`,
   `@type.same`), as effect families already do (`State.get U32 ()`).
5. Contracts stay small.
   - The homogeneous operator case reads `where { Add a }`, not
     `where { Add [a, a], type_eq (Add.Output [a, a]) a }`. This amends the
     11 November sketch.
   - Open: how to express mixed operands such as `Vec3 * F32`. Gdev uses them
     (`ray.direction * distance`).
6. `from` is resolved from the locally expected type only. A comment in
   ink/lib/lanes.blot says it costs thousands of inference steps per use.
7. With mandatory signatures (FAST_COMPILE decision 2), remove row-polymorphic
   records: `field` predicates, `@record.merge` (one app use), type-changing
   updates and `std/path`. Closed structural records and nominal data stay.
8. Retire these the way tasks were retired, and cut them before the Goose port
   so nothing is implemented twice:
   - Polymorphic packages (`forall` / `exists` / `pack` / `unpack`).
   - Typed staging (`@code.*`).
   - Erased proofs (`@proof.index`).
   - Usage contracts (`@usage.*`).

The review did not cover parameter patterns, or extending `#run` to
statements and build capabilities.

### Amendment to C3, C5 and C8: traits as records, `#run` fills bodies

Provisional. The owner's reply to blot2-2c's proposal: "For now it seems
reasonable and we can add it and then iterate on it." Spellings are open.

The owner's concern behind it: "contract" is too general a word, the system
should compose better and be more orthogonal, and `#run` metaprogramming
should be enabled more.

1. **Split contracts into ordinary parts.**
   - The interface is a nominal record type, with `trait` replacing
     `contract` in the `is` slot:
     `type Eq a is trait = { eq: a -> a -> Bool }`
   - An implementation is a named constant of that record type, marked as the
     canonical one for lookup:
     `impl eq_u32: Eq U32 = { eq: U32.eq }`
   - A conditional implementation has its own `where`:
     `impl eq_array: Eq (Array a) where { Eq a } = { eq: equal_array }`
   - `where { Eq a }` on a function is a hidden argument the compiler fills in
     at compile time. This lookup is the only new rule.
   - The explicit form needs no feature: the record is an ordinary
     parameter, as in `member_by (eq: Eq a) -> ...`.

   This replaces:
   - Default members: a function builds the record, e.g.
     `Ord.from_compare U32.compare`.
   - Contract inclusion: a field holds another record.
   - Opaque wrappers for a second implementation: pass a different record to
     the `_by` form.

   `where` keeps one predicate form, the trait application. `associated`,
   `result`, `receiver`, `update`, `type_eq`, `operation`, `type_rep` and
   `effect_rep` go.

   Constraints:
   - No run-time dictionaries. The record is a compile-time constant fixed by
     the type arguments, so the `(binding, type arguments)` instance key does
     not grow.
   - Implementation heads are disjoint.
   - An impl lives in the trait's module or the key type's module, so lookup
     stays a table hit with no search.
2. **Output parameters instead of associated types.** This settles the open
   question in C5. A trait marks some parameters as determined by the others.
   Lookup uses the inputs and unifies the outputs, so there are no projection
   types to normalise.
   - `type Mul [left, right] -> out is trait = { mul: left -> right -> out }`
   - `impl mul_vec3_f32: Mul [Vec3, F32] -> Vec3 = { mul: Vec3.scale }`
   - `func square (value: a): a where { Mul [a, a] -> a } => value * value`

   This covers `Vec3 * F32` and removes `type_eq (Add.Output [a, a]) a`. The
   four contracts in std and Ink today (`Eq`, `Format`, `Codec` twice) are
   single-parameter records of functions, so none of them needs associated
   types. The `-> out` spelling is illustrative.
3. **`#run` only fills in bodies.** Every declaration's name and type are
   written in source, so module interfaces stay knowable from parsing alone
   and parallel checking is unaffected. Reflection flows one way: type to
   data to term.
   - Example: `impl codec_robot: Codec Robot = #run derive.codec (#type Robot)`
   - `#type T` returns a plain data description: constructors, field names
     and field types. C3 still holds for everything else: no evaluation
     results in annotations, no validators, no `TypeInfo`.
   - `derive.codec` is an ordinary function from that description to a code
     value, using ordinary loops over fields.
   - The result is spliced and checked against the written type at the splice
     site.
   - C8 changes from "retire typed staging" to "replace it". Code values are
     untyped until spliced, instead of `code [T, row E]`. The proposer's
     reading is that typed quotes cannot express "for each field of T",
     because each piece's type depends on the description. Check that before
     relying on it.
   - Customer: Gdev and Ink have 202 hand-written encode/decode functions
     across 68 files; derivation currently lives in host/derive_cli.ts.
   - Left out for now: a blanket impl that runs a generator per instance, and
     `#run` that generates declarations.

Trade-offs to record:
- Explicit passing lets two orderings meet in one data structure; storing the
  record in the structure avoids it.
- Errors in generated code surface at the splice site, so diagnostics need
  both the generator's location and the splice's.

### Update: no `impl`, dotting types, chaining values

The owner approved this ("Yeah, add all that. Sounds good."). It supersedes the
`impl` declaration form above. It is still provisional, and the spellings are
illustrative.

1. **No `impl`.** The implementation is the constant named after the trait,
   in the type's namespace.

   ```
   type Eq a is trait = { eq: a -> a -> Bool }
   const U32.Eq: Eq U32 = { eq: U32.eq }
   const Array.Eq: Eq (Array a) where { Eq a } = { eq: equal_array }
   const Vec3.Mul: Mul Vec3 -> [F32, Vec3] = { mul: Vec3.scale }
   ```

   - Lookup is a name lookup: `where { Eq a }` at `a = U32` resolves to
     `U32.Eq`. The same name passes the record explicitly, so there are no
     invented names like `eq_u32`.
   - Uniqueness comes free, because a namespace holds one member per name. No
     disjointness check is needed.
   - `T.Trait` may be declared in the type's module or the trait's module.
   - A trait dispatches on one type, and every other parameter is an output:
     `Mul left -> [right, out]`. So `*` cannot be both `Vec3 * F32` and
     `Vec3 * Vec3`. Current code agrees: each operator member has one
     signature per type (`Vec3.mul` takes F32, `Quat.mul` takes Quat; Vec2,
     Vec4 and Color likewise). If dispatch on both operands is wanted later, a
     keyword and a keyed table return then.
   - Open: two traits of the same name from different modules would both want
     `U32.Format`.
   - The rest of the amendment stands: traits are nominal record types,
     defaults are functions that build the record, inheritance is a field
     holding another record, the `_by` form takes the record as a parameter,
     `where` is a compile-time hidden argument, and there are no run-time
     dictionaries.
2. **Dotting a type finds types.** A concrete type holds type members in its
   namespace, as it already holds functions:
   `type Pool.Id = U32`, `type Pool.Row a = Maybe a`,
   `func Pool.read (pool: Pool a) -> (id: Pool.Id): Pool.Row a`.

   A type variable finds a trait's output by name. The checker looks only in
   the function's own `where` clause, so this is a rewrite to the
   output-parameter form, not a projection type.

   ```
   type Collection c -> item is trait = { length: c -> U32, at: c -> U32 -> item }
   const Array.Collection: Collection (Array a) -> a = { length: Array.length, at: Array.at }

   func first (values: c): Maybe c.item where { Collection c } => ...
   // means exactly:
   func first (values: c): Maybe item where { Collection c -> item } => ...
   ```

   - On a concrete type, lookup tries inherent members first, then the
     outputs of traits implemented for it: `(Array U32).item` is U32.
   - When two traits offer the same name, qualify it: `Collection.item c`.
   - Open: whether outputs are lowercase (type parameters) or PascalCase like
     other type names.
3. **Chaining from values.** `value.name` looks in three places, in order:
   - a field of the value;
   - a function in its type's namespace that takes the value first
     (`Vec3.length`);
   - a member of a trait the type implements: `robot.eq other` is
     `Robot.Eq.eq robot other`. In generic code this step looks only at the
     function's own `where` clause. When two traits supply the name, it must
     be qualified.

   A line that starts with `.name` continues the expression above it:

   ```
   let reach = robots
     .filter (func robot => robot.charge > 0.2)
     .map (func robot => robot.home.length)
     .fold 0.0 F32.max
   ```

   - This replaces `|>` and takes over the leading-dot spelling from
     selectors (`.x` as a function), so selectors go. They have no uses in
     Gdev or Ink.
   - One-liners use parentheses: `(values.filter keep).map double`. A space
     before a mid-line dot means nothing, so `keep.map` and `keep .map` are
     the same.
   - It depends on data-first, lambda-last order (E4), because the receiver's
     type must be known at the dot.

In summary, the dot on a type finds types, functions, constants and trait
implementations; on a value it finds fields, functions and trait members.
`::` is still not needed (C2).

The `#run` example in this form:

```
type Robot is data = $Robot { id: U32, charge: F32, home: Vec3 }
const Robot.Eq: Eq Robot = #run derive.eq (#type Robot)

// std/derive; `#quote` and `#( )` are placeholder names
func eq (target: Type): Code =>
  let checks = [#quote (Eq.eq left.#(field.name) right.#(field.name)) | field <- target.fields]
  return #quote { eq: func left -> right => #(code.all_of checks) }
```

Other modules check against the hand-written `Eq Robot` before the generator
runs; the spliced record is then checked against it.

## D. Systems gaps

1. Decide the numeric set and literal typing before finalising operator
   contracts: signed integers, bytes, 64-bit, F64. `Text` is `Array U32`
   today.
2. Measure what runtime closures without inlining (decisions 4 and 6) cost in
   `array.map (func ...)`-style code. Gdev and Ink have about 1,300 inline
   lambdas. If the cost shows, add an explicit "specialize on this function
   argument" marker rather than optimizer heuristics.

## E. Syntax

1. One function body form: `=> expr`, or `=>` followed by an indented suite
   with explicit `return` that falls through to Unit.
   - It replaces `=> return expr`, `=> return do:` with `break v`, and
     `=> do:` with `return v`.
   - `=> return do:` appears 2,706 times, and std, Ink and Gdev each use a
     different return convention.
2. `not x` becomes a keyword operator beside `and` / `or`.
3. Reject expression statements whose value is not Unit. Probes: `bump values
   0` (missing its third argument) and `1 + 2` both compile silently as
   statements.
4. Data-first argument order everywhere, with the lambda last. Drop `|>` and
   `$` application. std is data-last today (`array.at index values`), while
   receivers are data-first (`values.at index`).
5. `@` intrinsics only inside std, with one public spelling per operation.
   Today the same operation is spelled `@storage.push v x`, `v.push x` and
   `GrowArray.push v x`.
6. `[...]` becomes the array literal. Drop `List` and the rope /
   packed-sequence plan.
7. Accept ranges as comprehension generators. `array.generate n identity` is
   used 47 times as an index source.
8. One spelling for each of these pairs. The review did not choose; its
   author would keep the first of each.
   - `&T` / `Ref T`
   - `&[T]` / `View T`
   - `^T` / `Link T`
   - `for x in` / `for let x in`
   - `#run do:` / `#do:`
   - `f x` / `f(x)`
9. A fixed operator table: remove custom fixity declarations and user-defined
   operators, so parsing no longer depends on declarations.
10. Type parameters in list form only. There are 45 list-shaped declarations
    and no record, tuple or curried ones.

## Keep

- `:=` with `self`
- `let ... else`
- `case a, b of`
- `type X is kind`
- `$Constructor`
- `entry`
- the array capability types
- typed holes
- the six FAST_COMPILE decisions

## Illustrative target

The spellings are open.

```
func level_receive (access: FrameAccess) -> (context: EventContext): Unit =>
  if not (goals.busy access ()):
    access.station_state = station.idle    // store: every alias sees it
  let rates = output.read_state access
  rates.shown := 0.0                       // rebinding: local only
  output.write_state access rates
```

## Caveats

- The counts are grep approximations.
- The owned-profile alias behaviour is quoted from the guide; the review did
  not execute it.
