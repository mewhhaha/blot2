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
