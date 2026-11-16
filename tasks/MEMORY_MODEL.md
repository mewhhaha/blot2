# Memory model A: immutable values, reused in place

The owner's direction (14 November 2026): "Just immutable and then our goal
is to reuse as much memory as possible", aiming at "efficient immutability.
Maybe even more efficient than mutable languages." The syntax is in
docs/language/spec.md (sections 6.5 and 10). Asked in this session (14
November 2026), the owner chose:
- "Approve, with owning modify": the `own` parameter design (parameters
  borrowed by default, `own` takes over, call results owned by the caller),
  plus a state `modify` that hands the state over as `own`.
- "Keep `=` until apps move": the `=` store that landed before the
  immutable decision stays, unspecified, until Ink and Gdev are rewritten,
  and is then deleted.

On 16 November 2026 the owner approved ("Yes. Do all of that."):
- parameters stay borrowed by default, with `own` as the mark;
- the two changes to the borrowed rules recommended under "Phase 2" below
  (a result may borrow through a view, a reference or a function; the
  generic-read rule is checked at the call), and the transitional third;
- `values.copy x` is a move when `x` owns its array at its last use;
- advice, not inference: the compiler suggests `own` for a function that
  copies a borrowed parameter and updates the copy;
- no ownership passed at run time to a borrowed parameter;
- building starts with `own` on the parameters of named functions.

This replaces the earlier plan for a store statement, `Cell` and `is root`.
App code spells intrinsics as round 2, item 2 approved (`values.copy`,
`panic`); std may keep `@name` forms.

## Rules

1. **Everything is a value.** Scalars, tuples, records, sums, closures and
   arrays are immutable. `:=` is the only way anything changes, and it
   always builds the successor: `rows[i] := row` is
   `rows := @array.set rows i row`, and `point.x := 1` is a record update.
   A group of arrays is an ordinary data type with field defaults (round 2,
   item 10).
2. **Reuse in place, never copy behind the user's back.** A `:=` through an
   array is done in place when the local owns the array. Otherwise it is an
   error (`aliased_update`) that asks for `values.copy`.
3. **Ownership inside a function.** A local owns its array:
   - when it is bound to a fresh value: a literal, a comprehension, an
     `@array` result, `values.copy`, an owned call result, or an `own`
     parameter;
   - after a `:=` update of itself.

   It stops owning while another holder exists:
   - another name;
   - a closure capture;
   - an argument passed to a borrowed parameter;
   - a storage-holding element or field read out of it.

   Ownership comes back at that holder's last use. A holder with no last
   use inside the function (an escaping closure, a value stored in a
   returned record) keeps it until the end of the scope. Branches meet as
   "owned only if owned on every path"; loop carries meet with their
   backedges.
4. **Parameters are borrowed, unless marked `own`.**
   - A borrowed parameter can be read and lent to other calls, but not
     updated with `:=`, returned, or put into a returned value. Lending an
     array to a call does not end the caller's ownership.
   - An `own` parameter is taken over. The argument must be owned at the
     call, and the caller's name is spent until rebound
     (`world := world.damage 3`). Inside the callee the parameter is owned.
     `own` is part of the function type, and a partial application cannot
     supply an `own` parameter.
   - Every call result is owned by the caller.
   - A generic result whose type may hold an array can't be read out of a
     borrowed parameter without `values.copy`.
5. **State effects.** A state's `modify` hands the state to its function as
   `own` and stores the successor, so array state is updated in place
   rather than copied (with effects as records, round 2 item 4).
6. **Runtime epoch checks** stay the safety net (A6). Nothing is inferred
   across calls (FAST_COMPILE decision 1); signatures state ownership.

## Phases

Each phase keeps check:dev, the guest suite, Ink, the Gdev frame and the
full gate green, and moves std, ../ink and ../gdev itself.

1. **Uniqueness and `aliased_update`** — done (bf582a9c), "Phase 1 as built"
   below. It also landed the `=` store and `blotc migrate-stores`, which
   turned 1,880 `:=` in Ink and 3,011 in Gdev into `=`. `=` stays until
   phase 3.
2. **`own` and borrowed parameters.** Measured, not built: "Phase 2: what
   the borrowed rules reject" below has the counts, the recommended rules
   and what is still open.
   - In the checker: `own` in function types, spent names, owned call
     results, borrowed parameters not updatable or returnable, ownership
     returning at a holder's last use, and the generic-read rule.
   - Fix the in-place append on non-owned arrays (below).
   - The state `modify`, once effects are records (round 2, item 4).
3. **Move the apps off `=`.**
   - Rewrite each `=` site in Ink and Gdev into the immutable style: take
     the record or array `own`, update it with `:=`, return it, and rebind
     at the call site.
   - This is a style rewrite of how systems thread their world state, not a
     mechanical one, so go module by module, keeping Ink's suite and the
     Gdev frame green.
   - Then delete the `=` statement, `migrate-stores` and `store`-only
     grammar.
4. **Value restriction** in full: a `let` generalizes only when its value
   is a syntactic `func` (phase 1 did the part for array-holding lets).
   - Done for rebinding (15 November 2026): the new version a `:=` gives a
     name is never generalized. No program in the suites, Ink or Gdev
     changed.
   - Measured for `let`, not built: "Phase 4: the value restriction for
     `let`" below.
5. **Read-only references** (A4) and the end of references as a write
   path, after phase 3.

## Phase 1 as built (14 November 2026)

- **Uniqueness** (compiler/src/check/uniqueness.zig) runs on each module's
  Core at the end of lowering, so `aliased_update` is a lowering diagnostic
  with the update's span.
  - Facts belong to binding versions and follow evaluation order. A version
    has no fact, is unique (`shell`: the array's own storage; `deep`: it and
    every array inside it), or has per-field facts for a record local.
  - Branches meet through an undo trail, and an arm that leaves the
    function contributes nothing.
  - Each loop body is probed once with the carries' incoming facts, then
    checked with the carries met with the probe's backedges.
  - A `for` over an array reads it throughout.
  - An escape kills the whole version.
  - Phase 2 adds `own` parameters, owned call results and the return of
    ownership at last use.
- **`values.copy`.** The prelude's `Array.copy`, `GrowArray.copy` and
  `ResizeArray.copy` (over `@storage.copy`) count as fresh copies.
- **Value restriction, storage part.** A `let` whose value's type is open
  and holds an array is not generalized.
- **Open: in-place append on a non-owned array.** `let ys = @array.append xs
  v` with `xs` named once is appended in place by the direct backend
  (`linearAppend`). When `xs` is a parameter or alias, that grows the
  caller's array: a hidden write. Phase 2 must restrict it to owned `xs`.
- **`@storage.write`** is gone; the prelude's `values.write i v` is a `=`
  store until phase 3.
- **Transitional:** the `=` statement (`store_stmt`, `UpdateInfo.store`) and
  `blotc migrate-stores`.

## Phase 2: what the borrowed rules reject (15 November 2026)

`wip/memory-phase2-own` (0afccb55) fails 585 guest cases. The cause is the
breadth of its rules, with one bug beside it. Nothing is migrated yet.
[The record](../benchmarks/evidence/measurements/2026-11-15-memory-phase2-borrow-rules.json)
has the commands and every count, and the patch next to it rebuilds the
variants.

**Cause.** Every failing case fails with `borrowed_escape`, and 14,028 of
the 14,687 diagnostics the suite prints are in std/prelude.blot, which each
case compiles. The branch rejects the prelude for three reasons:

- It treats a type variable as an array. That rejects `identity`, `min`,
  `max`, `Maybe.unwrap_or` and every other generic function that returns a
  parameter. This is the generic-read rule of spec section 10.3 as written.
- It treats a call result of function or variable type as borrowed when an
  argument is, because the call may be a partial application. That rejects
  `apply`, `compose`, `Maybe.map`, `array.map` and each `with_…` function
  that ends in `return consume (…)`.
- It rejects a `=` store or a push of a borrowed value, which is what the
  transitional `=` exists to do.

**The bug.** A shallow copy of a borrowed array whose elements hold storage
gets the one fact `borrowed`, so the copy's own storage is not unique. The
branch therefore rejects `moved[0].position := …` after
`let moved = @storage.copy sources` (ink/tests/next-improvements.blot:177),
which phase 1 accepts. The copy needs "unique storage, borrowed elements".

**Counts.** Distinct rejected sites when the rules are narrowed one step at
a time:

| Rules | Gdev Main build | Ink's tests build | Guest cases failing |
| --- | ---: | ---: | ---: |
| The branch | 352 | 350 | 585 |
| 1. Stores, function values and variable-typed call results are not escapes | 187 | 152 | |
| 2. Also, a type variable holds no array inside a generic body | 130 | 88 | |
| 3. Also, a return is an escape only when its type owns an array | 44 | 27 | 75 |

Both builds include std and the Ink modules they import. Under rule set 3
the Gdev build has 1 site in std, 26 in ink/lib and 17 in gdev/src:

- 19 build a record of array handles from parameters, or read one out
  (`func access state -> text -> asked => return $Access {state, text, asked}`,
  Ink's `$Scene`, `$Index` and `$Geometry`).
- 18 return a parameter that owns an array, changed or not
  (`ground.cells := …` then `return ground` in gdev/src/world/trails.blot).
- 6 return a constant array (`kind_name` in ink/lib/pen/semantic.blot).
- 1 is std's `simd.store`, which returns the storage it wrote.

The 75 failing guest cases are in 39 files. 84 of their 108 diagnostics are
in std/iter, std/list and std/simd; the first two are on the removal list
(round 2, item 11 and E6).

### The rules (approved 16 November 2026)

Rule set 3 was the implementer's recommendation and is now in spec section
10.3. It keeps what section 10.3
is for: a call result that owns an array is unique, so `:=` on it is in
place. It changes two of that section's rules and adds one for the
transition.

1. **A result may borrow through a view, a reference or a function.** The
   spec says a function may not return "anything that holds" a borrowed
   parameter. Recommended instead:
   - A type *owns* an array when it is `Array`, `GrowArray` or
     `ResizeArray`, or data that holds one. A view (`&[a]`), a reference
     (`&a`), a link and a function only *borrow*.
   - A function may return borrowed storage in a part of the result whose
     type borrows. It may not return it in a part whose type owns.
   - At a call, a result whose type has a borrowing part holds the call's
     arguments, like a closure that captured them. Every other result is
     unique.

   Each side reads only the signature. It keeps `line_of (text: &[U32])`
   returning `$Line { text, caret }`, a closure that captures a parameter,
   and a partial application, which is why the branch's second rule is not
   needed.
2. **The generic-read rule is checked where the type variable gets its
   type.** The spec rejects the generic function. Recommended instead: when
   a type variable occurs in the result and, as data, in a borrowed
   parameter, each call must give it a type that owns no array. Inside the
   body such a variable is plain data. `identity`, `min` and `Array.at` stay
   as they are, `identity rows` on an `Array U32` is the error, and
   `func identity (value: own a): a` lifts it. A variable under a function
   type in the parameter does not count, so `array.map` may still build an
   array of arrays.
3. **Until phase 3, a `=` store and a push are not escapes.** They write
   where aliases see it, which is their meaning, and both go in phase 3.

### What the finished pass still needs

The branch and the variants leave these open:

- **A returned value must be unique in itself.** The branch only rejects
  borrowed storage. It accepts `return {left: rows, right: rows}`, and the
  caller then updates `left` in place and sees it in `right`. A result that
  owns an array must be unique at the `return`. That needs the next item,
  or `let before = rows` rejects `return rows`.
- **Ownership returns at a holder's last use** (rule 3). Not started. Facts
  need to know which names hold a value, not only that some other name
  does.
- **`own`.** Not started: the syntax, `own` in function types, the
  argument that must be owned, and the spent name.
- **`own` and depth.** An `own` parameter is unique all the way down only
  when the argument was. Either the call requires that, or the callee may
  update only the outer array in place.
- **The call-site check of recommendation 2** needs the callee's scheme at
  each call, including calls into other modules. Core keeps the callee's
  type at the call (`CallInfo.callee_type`) and names a binding of another
  module by unit and number, so the pass must be handed that binding's
  scheme. The checker has it (`check.Binding.scheme`).
- **In-place append** on a non-owned array (above).

### Order of work

`own` in function types touches about 200 places that build a function type
and 200 that inspect one, in check.zig, the package, staging, usage and
proof modules, and the dependency format. Sections B3 and C8 of
tasks/LANGUAGE_COHERENCE.md remove most of those modules. Doing those
removals first means `own` is written once, in a smaller checker.

A smaller first step is possible without it: `own` on the parameters of
named functions only, recorded per binding and called directly. That covers
all 44 sites. A lambda with an `own` parameter, which `State.modify` needs,
waits for `own` in types.

## Phase 4: the value restriction for `let` (measured 15 November 2026)

[The patch](../benchmarks/evidence/measurements/2026-11-15-value-restriction.patch)
generalizes a `let` only when its value is a written `func`. It is 11
lines in check.zig and is not applied.

- **std, Ink and Gdev need no change.** The Gdev build and Ink's 62 test
  programs check without a diagnostic.
- **It must keep solving fields at each `let`.** A generalized `let` solves
  the pending field requirements on its way to a scheme. Without that,
  gdev/src/buildings/cannon.blot:329 fails with `ambiguous_operator`, so
  the patch calls `solveFields` for a plain `let` too.
- **Gdev's Wasm changes and its frame does not.** The Wasm is 2,720,283
  bytes against 2,720,970. The first Pen frame is byte-identical on the
  software Vulkan driver: frame.png c1ff619f…, frames.trace 86d50101… (the
  recorded trace).
- **24 tests pin the old rule** and must be restated or go with it:
  - 13 guest cases: 7 in generalized_local_instance_execution (one local
    used at two layouts), 2 in unused_aggregate_execution (an unused tuple
    of generic constants now has an open type), and one each in
    associated_execution, where_execution, qualified_evidence_execution and
    result_execution (a local alias of a generic function).
  - 11 native laws, in check_result_tests, check_effect_tests (2),
    check_where_tests (3), check_shared_scheme_tests (4) and
    scoped_effect_backend_tests. Most bind a local with a `where` clause or
    an alias of a generic global.
- **It saves little time:** 6.33 billion instructions for a Gdev build
  against 6.41, with 8,313 schemes computed against 11,766. The cost of a
  `let` is solving its fields, which stays.

## Measured scope before phase 1

| Tree | Lines | Path `:=` | `@storage.write` |
| --- | ---: | ---: | ---: |
| std | 1,367 | 1 | 3 |
| ink/lib | 23,526 | 1,006 | 0 |
| ink/tests | 20,161 | 1,659 | 0 |
| gdev/src | 27,134 | 2,092 | 9 |
