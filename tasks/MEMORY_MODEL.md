# Memory model A: immutable values, reused in place

The owner's direction (14 November 2026): "Just immutable and then our goal
is to reuse as much memory as possible", aiming at "efficient immutability.
Maybe even more efficient than mutable languages." The syntax is in
docs/language/spec.md (section 10). The owner approved:
- the `own` parameter design, together with an owning state `modify`;
- keeping the `=` store as a transitional form until the apps move off it.

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
2. **`own` and borrowed parameters.**
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

## Measured scope before phase 1

| Tree | Lines | Path `:=` | `@storage.write` |
| --- | ---: | ---: | ---: |
| std | 1,367 | 1 | 3 |
| ink/lib | 23,526 | 1,006 | 0 |
| ink/tests | 20,161 | 1,659 | 0 |
| gdev/src | 27,134 | 2,092 | 9 |
