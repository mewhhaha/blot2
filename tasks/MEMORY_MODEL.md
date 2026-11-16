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

Later on 16 November 2026, asked whether a generic call that returns what
it was lent (`grid.at 0` on an array of arrays) should be the error of the
approved text or should share like `grid[0]`, the owner chose sharing: "Do
your plan."

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
2. **`own` and borrowed parameters.** The default since 16 November 2026:
   "Phase 2 is the default" below. Open: `own` in function types, and a
   temporary holder giving ownership back.
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
- **Ownership returns at a holder's last use** (rule 3). Moves are built
  ("Phase 2 as built so far"): the value goes to the new holder at the
  local's last read. Open: a temporary holder giving ownership back, for
  which facts need to know which names hold a value, not only that some
  other name does.
- **`own`.** Built for top-level named functions ("Phase 2 as built so
  far"): the syntax, the argument that must be owned and the spent name.
  Open: `own` in function types.
- **`own` and depth.** An `own` parameter is unique all the way down only
  when the argument was. Either the call requires that, or the callee may
  update only the outer array in place. Built: the call requires it.
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

## Phase 2 is the default (16 November 2026)

The owner asked on 16 November 2026: "Can you finish the conversion so we
don't have the mutable = anymore?" This is how far that got, and what is
left.

**Done.** The rules of "Plan for the rest of phase 2" apply to every
module; the `BLOT_BORROWED_RULES` switch is gone.

- std has no store. The prelude's `values.write` is gone (write
  `values[i] = v` while `=` exists); `simd.store`, `text.from_scalars` and
  `text.scalars` take their array over with `own`.
- The guest and host suite passes (1,063 cases). 24 test programs changed:
  a function that returned a parameter, a field of one or a module
  constant now copies it or takes it `own`; tests that pinned "writes
  through aliases" for `simd.store` now pin the take-over.
- 379 stores in Ink and Gdev whose place was provably unique became `:=`
  (171 in Ink, commit 2699436, whose subject says 380 by mistake; 208 in
  Gdev, commit a09ba7a). One more was converted and put back: as a `:=`
  inside a loop it made its array a loop carry, which was not unique.
  Ink's suite gives the same result as before (268 passed, 1 failed, 3 did
  not compile), and Gdev's first frame is byte-identical (frame.png
  c1ff619f…, frames.trace 86d50101…). Gdev's Wasm is now dd97fe15…,
  2,724,223 bytes.

**One rule set for every module (16 November 2026, later the same day).**
The split into old-style and converted modules is gone. It could not carry
the rest of the conversion: a call into an old-style module shared its
arguments, so a caller could never keep ownership across such a call, and
a writer could only be converted together with every function between it
and the frame loop.

- Every function's result is its caller's alone and a call only borrows
  its arguments, in every module. That now covers calls through function
  values (a parameter, a field, a local), because everything that can be a
  function value obeys the result rule.
- `=` stays for now as a write through what the function was lent. What it
  stores is kept by that storage, so it must be owned or plain data
  (`kept_value`); the same for a push into growable storage the function
  was given and for an argument of an effect operation. `@simd.store` on
  storage the function does not own is the same kind of store.
- A function that still returns or keeps what it was lent is marked
  `lent` (`lent func`, `lent const`). It is not checked and not trusted:
  a call to it shares its arguments and its result is not unique, as phase
  1 treated every call. Entry functions are treated the same way.
- A constructor, a primitive or an effect operation used as a function
  value, or given only some of its arguments, is `lent_result_value` where
  it would keep an array; so is a `lent` or entry function whose result
  owns an array and has no part that borrows.
- Where the result type has a part that borrows, a call through a function
  value shares its arguments and gives a result that is not unique. That
  is what lets a `lent` function stand as a callback (Gdev's `bind_frame`
  in the application record).

- A call that is given a `lent` function as an argument is treated like a
  call to one: it shares its arguments and its result is not unique. That
  is what keeps `apply_to same rows` honest.
- A call's arguments are read as one call even when it is a chain of
  applications (`world.total a b`, a function value given two arguments):
  none of them is shared unless the result borrows. Before, every argument
  but the last was.
- A closure written as an argument gives back what it captured when the
  call returns, if the call's result has no part that borrows. For that
  to hold, a function may not keep a function it was lent: storing or
  pushing a parameter or a capture that can hold one is `kept_value`.
  This is the "temporary holder" of the plan, for closures; it is what
  lets the collect-into-a-captured-buffer fixtures of Gdev's tests
  compile (36 more of its test modules do).

- A read under a `return` that leaves the function moves its local even
  inside a loop: no later iteration runs.

Known gap, for as long as `lent` exists: a function that passes what it
was lent on to a `lent` function is not itself marked, though the `lent`
function may keep it.

`GrowArray` and `ResizeArray` are owned values since 16 November 2026
(below). Until then they counted as borrowing in a type.

What it took: 54 `lent` marks in Ink and Gdev (25 and 29), 8 in the
guest tests and one fixture; three callbacks in Gdev that returned what
they were lent now copy (`migrate` in celebrations and locale, the pack
migrations in robots, which take their array with `own`), and three test
fixtures of Gdev copy what a closure returned. `pen codegen`
no longer wraps `project.draw_extra` in a closure, and it emits `=` where
the committed encoders have it, so `pen codegen --check` agrees again.

Checked on 16 November 2026: the gate (1,165 guest and host cases: 1,064
pass, 101 ignored, none fail; 147 uniqueness programs, 18 of them new and
named `h`; 187 fixtures); Ink's suite as before (268 passed, 1 failed, 3
did not compile); Gdev's first frame byte-identical (frame.png c1ff619f…,
frames.trace 86d50101…; Wasm 406f4d8b…, 2,724,075 bytes).

Gdev's own tests (`pen test-blot` in ../gdev) were compared module by
module with the state before: 362 pass, 27 fail and 118 do not compile,
where 218 passed, none failed and 155 did not compile. No module that
compiled stopped compiling and none passes fewer tests. 37 more compile,
because a captured buffer is given back; the 27 failures are all in 13 of
those, so they were hidden before, not caused by this. 96 of the 118 are
`missing_file`.

**`own` in function types (16 November 2026).** Built, because Gdev's
systems reach the world through callbacks and a continuation.

- A function type's parameter can be `own T`. The checker keeps it as the
  existing wrapper type node with a ninth kind, `own`, which every type
  traversal already carried; the usage-contract machinery ignores that
  kind (`has_usage_contracts` is not set by it).
- The type of a function or lambda with an `own` parameter has it, so an
  `own` function is a value. A lambda is `own` by its annotation or by the
  type expected where it is written. An application gives the parameter
  the argument's type; `own T` never unifies with `T`, and nothing has a
  type `own T`, so a generic function cannot call an `own` function on a
  value it borrowed.
- `own` now parses as a prefix of a type application, and a parameter is
  taken over when its whole annotation is `own T`. So `(step: own A -> B)`
  is a parameter holding a function, where it used to be a function
  parameter taken over.
- The pass reads which arguments a call gives away from the callee's
  type, for `f a b`, a local, a parameter or a record field alike. A
  member reached as `value.member` is still found by its declaration,
  because the signature the checker writes at such a use does not always
  carry the `own`. The tables by binding are gone.
- A call that gives an `own` argument gives every argument of the type;
  `own_function_value` is now only that, and `value.member` of an `own`
  member without arguments.
- `func (a: own A) -> (b: B) => …` as a lambda is a closure whose body is
  a closure. The inner one keeps the fact of what the outer one took,
  since the two only ever run together.
- Still `own_parameter`: contract members, implementation members,
  operator members, and `own` in any other type position.

Checked: 155 uniqueness programs (8 new, named `i`), the guest suite
(1,065 pass), Ink and Gdev unchanged.

**Growable arrays are owned values (16 November 2026).** `GrowArray` and
`ResizeArray` counted as borrowing in a type, as a reference does: a
record of them was not checked as a result, and an `own` parameter of such
a type accepted storage that was shared, so `:=` through it would have
been the same shared write as `=` under another name. Now they own their
storage as an array does. A push into a growable array the function was
lent stays what `=` is: a write through it, for as long as `=` exists.

It was cheap. Gdev's main program needed 8 more `lent` functions in Ink
(the spatial index and shape geometry, which hand back the buffers they
were given), 5 in Gdev's devtools (the diagnostics HUD's fluent row
builders), one guest test and three fixtures. Three places changed for
real: the salt simulation reads `access.salt` instead of calling a
`pools` accessor from its policy record; `spatial.build_into` builds its
index outside the continuation it passes; and a constant that names a
`lent` function is written `lent const`.

That makes 66 `lent` functions (33 in Ink, 33 in Gdev) and 4,524 stores.
Checked: the gate (1,065 pass, 101 ignored), Ink's suite as before, Gdev's
first frame byte-identical (Wasm now 24013ca4…, 2,721,854 bytes, because
of the salt simulation), Gdev's own tests as before (362, 27, 118).

**First conversions (16 November 2026).** With those three pieces in, the
`own` style was tried on what was ready for it.

- Nine `lent` functions took their parameter with `own` and lost the mark
  with no caller changed: the devtools HUD's five row builders (already
  called as `hud := row self …`), `construction_kit.structure`,
  `impact.fringes`, `contact.reduce` and `field.mark`.
  The trial was mechanical: add `own` to the parameter a `lent` function
  returns, and keep it if every program still checks clean. Eight more
  failed it because a caller does not own what it passes.
- `stores_to_updates.py` found 58 more stores it can prove unique (32 in
  Ink, 26 in Gdev), since locals stay unique across calls now.
- Left: 4,466 stores and 57 `lent` functions.

**What blocks the rest, in order.** The stores are writes through Gdev's
`FrameAccess` and what is made from it, and nothing can take that with
`own` until the top of the program owns it. From the top:

1. Done (gdev 6ca8ca6, ink d2628e6): `world_storage.with_owners` makes
   every buffer as a local, so it owns them, until it built `hooks`: a
   closure that captured the whole record to despawn, reset and stash on
   demand. The hooks are one function that is given the access now.
2. Done, see "The session owns the world" below. `with_owners` handed the record to a continuation, and Ink's
   `host.run` hands it on to `program.run`'s loop. Each has to take it
   with `own` and give it back (`own` in function types is there for
   this). An owned value can be rebound across the loop's suspension to
   the host: tried on a small program, it is accepted. But it cannot be
   done before step 3, because the first `bind_frame` shares the record
   for good.
3. Done, see "The world is one value" below. Each frame
   `host.with_frame` made the frame's buffers and
   `bind_frame` builds one `FrameAccess` out of them and the persistent
   record, field by field (170 fields), and nothing takes it apart again.
   Either the pass learns to move fields out of a record at its last use,
   or the frame's buffers live in the persistent record and are emptied
   each frame. The second is the one that fits the model: the world is
   one value the loop owns, `FrameAccess` is that value, and `bind_frame`
   and `host.with_frame` go. It changes Ink's host, Gdev's
   `world_storage` and the test fixtures that bind their own frames, and
   the frame's buffers are then reused instead of made fresh, so the
   first frame has to be compared again.
4. Then the 20 or so functions that hand out a part of the access as a
   record of its own (`simulation_access`, `read_state`, `read_surface`,
   Ink's `scene.access`, `spatial.access`, …) are replaced by passing the
   part itself, and each system takes what it writes with `own`. From
   there the writers convert one at a time, and the generated encoders
   (half the stores) with their caller, `host.encode_frame`.

**The world is one value (16 November 2026, steps 1 and 3 of the list
above).** Approved by the owner on 16 November ("Sounds good. Do all of
that.").

- Ink's `host.frame_owners ()` makes the frame's buffers once, and
  `host.empty_frame access` empties them where a frame starts. Gdev's
  `with_owners` takes that record apart and builds one `FrameAccess` out
  of its own buffers, the hooks and the frame's buffers. The session's
  `frame` and `execute` work on that value directly; `host.with_frame`
  and `bind_frame` remain only for tests that bind their own frames.
- For that the pass learned to take a value apart: `let {a, b} = v`,
  `let (a, b) = v` and `let ($Box a) = v` give each name a value of its
  own when `v` is fresh, or a unique local at its last read. Zig's `b18`
  and one site of `c22` are accepted for that reason now.
- Gdev's first frame is byte-identical with the buffers reused (Wasm
  00582e5e…, 2,677,305 bytes).
- Gdev's `application` record wraps each callback in a lambda with
  written types (`func (access: FrameAccess) => return keep access`). With
  the bare generic functions as fields the backend failed with "closure
  argument of 1 words for a never parameter of 0 words" at the session's
  calls: the field's type variable was left unresolved where the session
  is given the world's nominal type. It was not tracked down. Five of
  Gdev's test modules failed to compile on the same message at the old
  `bind_frame` call and compile now.
- Gdev's own tests: 376 pass, 57 fail, 113 do not compile (362, 27, 118
  before). Compared module by module nothing that compiled got worse; the
  30 new failures are in those five modules (`codec_saved_state`,
  `ecs_sandbox`, `game`, `game_history`, `restore_game`), which call
  `host.frame` with a frame they bound themselves. Whether their
  expectations are stale or the reused buffers matter there is not known.
- The devtools program does not build before or after
  (`storage_unsupported`); its world takes the frame's buffers by a
  record merge so that it still checks.

**The session owns the world (16 November 2026, step 2).** Gdev's
`world_storage.owners` returns the world as a value, Ink's `host.run`
takes it with `own`, and `program.run` rebinds it round the loop:
`access := execute access operation …`. `host.execute` takes it and
returns it. Everything below still writes through what it is lent.

What the compiler needed for it:

- `(own name)`: a parameter taken over whose type is left to be found.
  Most of Ink and Gdev is written against "any record with these fields",
  so most `own` parameters will be this form.
- A name that borrows gives back (rule 3 of the model). `let response =
  access.response` shares `access` only until `response` is read for the
  last time; then `access` has its fact back, provided the name's value
  went nowhere else and nothing else touched `access`. It is decided at
  the end of each statement of the block that binds the name, and at the
  block's end. Only a `let` borrows: a name rebound with `:=` carries its
  value into later versions that no reference shows (Core's `bind` node
  now says which it is, in `c`).
- Merging two records that are each their holder's own gives one that is.
- `result_not_owned` points at the part of a record literal that is
  shared, when there is one, instead of at the whole result. That found
  the two things that kept Gdev's world from being owned: Ink's
  `services.access` and `platform.access` were `lent` constructors (their
  parameters are `own` now), and the world held one buffer under two
  names (`requests` and `persist_requests`).

Checked: gate 1,067 pass; Ink's suite as before; Gdev's first frame
byte-identical (Wasm 7fab4303…, 2,677,122 bytes); Gdev's tests 376 pass,
57 fail, 113 do not compile, as before this step.

**The stages own the world (16 November 2026).** The layer under the
session is converted: `host.frame`, Ink's `app` (`start`, `begin_frame`,
`run_event`, `advance`, `render`), `clock.advance`, and the ten stage
lambdas of Gdev's `game.blot`. Each takes the world with `own` and hands
it back; the callers rebind (`access := app.begin_frame stages access`).

- `app.advance` and `clock.advance` return the plan and the world as a
  pair; `app.advanced` is `advance` for a caller with no use for the
  plan. They read `access.clock`, `access.control` and `access.wall`
  themselves: a part cannot be lent beside the whole that is given away.
- `app.stages` has a signature now. Every stage is a stage of the same
  world `a`: `own a -> a`, or `own a -> argument -> a` for the stages
  that take an event, the seconds or the presentation; `route` reads the
  world and makes what `interface` and `event` are given. Without it a
  stage record used by two runners left one stage's world undetermined,
  and the backend could not build that stage (`no member … for this
  receiver`). It also makes an untyped lambda given to `app.stages` an
  `own` function by the type it is expected to have.
- `app.lent f` and `app.lent_with f` turn a function that still writes
  through a lent world into a stage. Devtools, the performance programs
  and the tests use them for their stage functions; they go when those
  functions are converted. `app.no_keep` is the no-op for the session's
  `keep` hook, which is lent the world (`app.no_action` is a stage).
- Tests: 90 of Gdev's test, fixture, devtools and performance files and
  12 of Ink's called the changed functions. A helper that runs a frame
  takes the world `own` and returns it, or returns `(result, world)`;
  the tests rebind. Six workers converted them in parallel from one
  brief (the patterns are in the two examples `tests/cursor.blot` and
  `tests/menu_feedback.blot`).
- `own` is not a name any more. `f own x` gives `x` away, so a constant
  called `own` (thirteen of Gdev's fixtures had one for their stage
  record) made every call that passed it read as a marker. Binding a
  local, a parameter or a constant called `own` is `own_parameter` now.

What the compiler needed for it, found by the conversion (every worker
met the first):

- **A borrowed value without a name is given back.** `salt.stored
  (salt.read_state access)` or `(buildings.read_state access).sites[0]`
  used to share `access` for good, because the result that borrows had
  no name whose last read could end it. Now the result of a call that
  borrows its arguments is given back when what is around it has been
  read, where that keeps nothing: it is the argument of a call whose
  result borrows nothing, or a plain value is read out of it. Through a
  call that hands its argument on in its result (`narrowed (window
  rows)`) it goes to wherever that result goes: the `let` that names it,
  or the expression that ends it. In a record or tuple literal, or as
  the argument of a `lent` function or a function value, it is kept as
  before.
- **What a loop walks is given back after the loop**, with what a call
  borrowed to make it (`for row in rows_of world`). Elements that hold
  storage alias what is walked, and an element can leave the loop only
  in a carry, so it is given back when every carry that can hold
  storage is its own all the way down after the loop.
- **A name nothing reads borrows nothing.** `let seen = view world`
  with no read of `seen` used to keep `world` shared to the end of the
  block.
- **A name's loan ends with the call that read it last**, not only at
  the end of the statement: `return (count frame, access)` works when
  `frame` borrows from `access`. Not inside a loop, a closure or an arm
  of a choice other than the statement's own: what an arm does to the
  facts is taken back when the arms are joined.
- **Two names may borrow from one local together**, the whole of it
  and one field: the field's fact is kept in what the name that
  borrows the whole gives back. Of several names that borrow the same
  thing, the earliest holds the fact (the later ones used to overwrite
  it, which was only ever too strict).

tests/uniqueness has 15 programs for these (`k01` to `k15`), and `c07`
is accepted now: rows a loop walked are the array's own again after it.

**What the backend needed.** A record too wide for registers is a block
of memory on the bump stack (Gdev's world is one). Two things made the
owned style use up that stack:

- `world.field[i] := value` copied the whole block for every update,
  though the write goes through the array and the record's words stay as
  they were. Such an update keeps its block now
  (`direct/function_data.goose`, `updateBoxed`).
- A loop that carries a boxed value never released an iteration's
  memory, because the owners inside the block are not checked word by
  word. So the session loop, which has carried the world since "the
  session owns the world", kept every frame's temporary memory: the
  pushed game stopped with a full stack after some thousands of frames
  (it ran 3,000 and not 12,000), and with the stages converted after
  about 450. Now the loop compares each boxed carry with the words its
  slot held when the iteration began, and releases when they are the
  same (`direct/function_control.goose`, `assignCarries`,
  `releaseIteration`): an iteration that leaves the value as it was
  carries out nothing it allocated.

With both, Gdev runs 200,000 frames, at 0.072 ms of guest time a frame
(median of 600 after 120; 0.071 before this layer, 0.076 with the copies)
([record](../benchmarks/evidence/measurements/2026-11-16-owned-world-runtime.json)).
tests/guest/own_parameter_execution.test.ts has the loop that failed.

Open, and it will matter as the systems are converted: an iteration that
puts a new array into the carried world (`world.rows := grown`) changes
the block's words, so that iteration releases nothing. The memory is safe
and never comes back. The same holds today for a function that stores a
fresh array into older storage: nothing it allocated is released
(`for …: put grid i` with `put` storing `#[n, n, n]` fills the stack after
some ten thousand rounds, before and after this change). What is needed
is a release that keeps the survivors: what the carried value still
refers to is moved down, the rest is released.

Not done in this layer:

- Devtools' and the performance programs' own stage functions are still
  lent ones behind `app.lent`.

Found after it, converting `tests/codec_support/counter.blot` (its
`execute` held the world across calls; it takes the world and gives it
back beside the packet now, and its two tests compile again):

- A lambda that takes a parameter over kept it only through one more
  parameter: `func (world: own World) -> (k: U32) -> (extra: Array U32)`
  lost it at the third. The chain carries it through any number now
  (`i13`).
- **Open: a call that returns the world shares its other arguments for
  good.** The world's type has parts that only borrow (views in a
  growable array, the hooks' functions), so the result of `access :=
  runtime.execute application access operation view outgoing` may hold
  any argument, and `outgoing` is not its holder's own afterwards
  (returning `@storage.freeze outgoing` is `result_not_owned`; the
  fixture returns a copy). The rule is right for a function that builds
  a view of what it was lent. It is too wide for a function that takes
  the world with `own` and returns it: the parts that borrow came in
  with the world. What a store or a push may keep is already checked
  (`kept_value`), so what is left is a record update that puts a view of
  a lent argument into the world. Closing that would let such a call
  leave its other arguments alone.
**Next: the systems.** Each of Gdev's systems that the stages call, then
what they call. A system changes in three places: its parameter becomes
`(own access)`, it returns the access, and every call of it becomes
`access := f access …`. Its own callees stay as they are. A test that
calls a system directly rebinds too, so each system goes with the tests
that call it. A system that returns a value returns it beside the world.

Its size, counted by `python3 scripts/integration/world_writers.py`: of
the 628 functions in gdev/src that take the world, 340 write through it
themselves and 371 do counting the ones they call, in 65 modules
(`ui/station` 24, `world/salt` 23, `player/hand` 21, `world/trails` 19,
`actors/robots` 16). Most stores go through a typed name for one of the
world's parts (`let stacks: Array Stack = access.salt.stacks`, then
`stacks[i] = …`); with the world owned the write is `access.salt.stacks[i]
:= …`, which the backend does in place.

**The way from here is top-down.** With one rule set, a function can be
converted on its own as soon as every caller owns what it passes: mark
the parameter `own`, return it, rebind at the call, and turn its `=` into
`:=`. A caller that owns its state keeps owning it across calls to
functions that still write through what they are lent, so the frontier
moves down from the frame loop one function at a time, with Ink's suite
and Gdev's frame checked at each step. A `lent` callee is the exception:
it has to be converted with the caller that needs ownership back.

**What is left: 4,452 stores.** Counted by line shape with
`python3 scripts/integration/count_stores.py DIR...`.
`python3 scripts/integration/stores_to_updates.py PROJECT ENTRY...` turns
into `:=` each store the compiler reports as provably unique (it runs
`blotc migrate-stores --dry-run` with `BLOT_REPORT_STORES` set); none is
left in the Gdev build or Ink's tests.

| Tree | Stores | Files |
| --- | ---: | ---: |
| ink/lib | 352 | 47 |
| ink/tests | 1,323 (1,104 in two generated protocol files) | 53 |
| gdev/src | 691 | 62 |
| gdev/tests | 701 | 131 |
| gdev/pen | 1,104 (the same two generated files) | 2 |
| gdev/test_support | 92 | 16 |
| gdev/devtools | 85 | 12 |
| gdev/performance | 104 | 17 |

None of these is a local the compiler can already see as unique. They are
of three kinds, and each needs the code restructured, not a token changed:

- **Output parameters.** A function fills an array or a growable buffer
  its caller handed it (`encoded[at] = …` in the generated protocol
  encoders, `out`, `output`, `destination`, `p` and `v` in Ink's motion
  code). The immutable form takes the buffer `own` and returns it, and the
  caller rebinds. The generated files come from `pen codegen`
  (pen/crates/pen-codegen/src/blot.rs): changing the generator converts
  2,208 of the sites, and then its callers in Ink and Gdev.
- **World state reached through shared records.** `access.x[i] = v`,
  `owners.…`, `frame.…`: records of array handles (`FrameAccess`) that
  every system is handed and writes through. Each system has to take the
  state it changes `own` and give it back, up to where the frame loop
  holds it. This is the rewrite the phases list calls "a style rewrite of
  how systems thread their world state".
- **One-element arrays used as cells.** `state[0] = next`,
  `meta[0] = next`, `settings[0] = settings`. They become plain fields of
  the state that is threaded.

Two things the compiler still lacks for that rewrite: `own` on lambdas and
in function types (a system passed as a value, the state `modify`), and
trust in calls through function values, which waits for the last store.

## Phase 2 as built so far (16 November 2026)

`own` on the parameters of top-level named functions, in the Goose
compiler. tests/guest/own_parameter_execution.test.ts,
tests/guest/store_uniqueness_execution.test.ts and the programs `e…` and
`f…` of compiler-goose/tests/uniqueness cover it; docs/language/guide.md
("`own` parameters") describes it for users.

- **Syntax.** `(name: own Type)`. The parser reads `own` as the mark when
  it stands before a type; `own` alone, or before `->`, `)` or `where`, is
  still a type variable. The host parser (host/parser/grammar.baba) is
  unchanged: it reads `own Type` as a type application, and the formatter
  prints it back as written.
- **Where the mark lives.** Each binding's `capability_parameters.own` is
  a bit mask of its `own` parameters. It travels with the binding through
  interfaces and dependency bundles, and Core's `CallInfo.own` carries the
  callee's mask on each direct call. Function types do not carry it.
- **Where it is allowed.** On a top-level `func` or `const name = func`
  that no operator stands for: `a + b` reaches `World.add` through the
  backend's dispatch, where the pass sees no call. Anywhere else it is
  `own_parameter` (checker). The uniqueness pass
  knows these functions by unit and binding (`takers`), and the members
  among them by receiver type and name (`member_takers`). A full call is a
  `call` node, a chain of `apply` on a reference, or a chain on
  `value.member`, whose value is the first argument. Any other reference
  to such a function is `own_function_value`: a function value, a partial
  application, a call through a dictionary (a function with a `where`
  clause).
- **In the function.** The parameter starts unique all the way down
  (`deep`).
- **At the call** (`ownCall` in uniqueness.goose). An `own` argument must
  be a fresh value that is unique all the way down, or a reference to a
  whole local that is. This is the first choice under "`own` and depth"
  below: the call requires depth. Otherwise `own_argument`.
  - Inside a loop the local must have been defined in the same loop body
    (`born`), because a later iteration would give it away again.
  - A record local counts when every field that holds an array is unique
    all the way down. A nominal is read through its one record
    constructor, and only when it has no type parameters.
- **Spent names.** The local gets the fact `spent`, which is below every
  other fact, so branches and loop carries keep it. A read of a spent name
  is `spent_value`. Nothing gives a spent version its storage back; the
  name is usable again after `name := …`, which is a new version.
- **Owned results, for these functions only.** Each `return` of a function
  with an `own` parameter must give a value that is unique all the way
  down, else `result_not_owned`. A `return name`, and a `break name` out of
  the block that is the function's result (`return do: … break name`),
  take the local's fact, because the function ends there. In return the
  call's result is `deep` in the caller. This is rule 1 of "The rules"
  applied to the functions that cannot break existing code.

- **Moves at a local's last read** (rule 3, in part). Each body is walked
  once without judging it, to log every read of a local in evaluation order:
  reference nodes, closure captures, loop carries, branch merges and the
  carries of a handler loop. The last logged read of each local is a last
  read; so is the last one inside an arm or a `return` that only leaves the
  function. At such a read that binds, places, stores or returns the local,
  the new holder takes the local's fact (`taken`). The local must be bound
  in the same loop iteration and the same function or closure.
  - Not built: a holder that is only temporary. After `let alias = rows`
    with both names read later, `rows` does not own its array again when
    `alias` is done.

What this leaves, besides the list under "What the finished pass still
needs":

- An argument passed to an ordinary parameter still ends the local's
  uniqueness (phase 1), so `let n = count rows` before `fill rows 0`
  rejects the second call. The borrowed rules fix this, and they are what
  makes `own` pleasant to use.
- The results of ordinary functions are not unique.
- A result of an `own` function may not hold a closure, a view or an
  element read out of the parameter (`return rows[0]` when the element
  holds an array). Tuples have no per-part facts, so `return (world, n)`
  is rejected too.
- `own` on lambdas, contract members and implementation members, which
  `State.modify` needs, waits for `own` in function types.

### Plan for the rest of phase 2 (16 November 2026, not built)

Worked out while building the part above. It is the implementer's plan
within the approved rules; the one deviation is marked.

1. **One result rule for every function.** The rule `own` functions have
   now: each `return` gives a value that is unique all the way down
   (`ownedAs`), and a call's result is `deep` in the caller. A value that
   holds a borrowed parameter, a constant, a capture or an element read out
   of something is never `deep`, so this one check also rejects every
   borrowed escape; no separate `borrowed` fact is needed, only a better
   message when the value is a parameter. It needs moves (built) so that
   `let cells = …; return $Grid { cells: cells }` passes.
2. **Results that are exempt.** A result type that owns no array (the
   `owns` predicate of the measurement patch: views, references, links,
   functions and type variables own nothing) is not checked. A call whose
   result type has a borrowing part keeps today's behaviour: the arguments
   are shared with the result and the result is not unique.
3. **Callers.** For every other call the arguments are only lent (the
   local stays unique) and the result is `deep`. This must cover direct
   calls, calls through function values (`apply`) and members selected by
   dispatch (`rows.map f`), or `return rows.map f` is rejected by rule 1.
   So lambdas, contract members and implementation members obey rule 1
   too.
4. **Generic functions.** Inside a generic body a type variable is plain
   data (`holds` and `owns` are false for it). A call is *generic-read*
   when a type variable occurs in the callee's result and, as data, in a
   borrowed parameter, and the call gives that variable a type that owns an
   array (`identity rows`, `grid.at 0`).
   - **Decided by the owner (16 November 2026, "Do your plan."):** such a
     call is not the error of the approved text. It is treated as phase 1
     treats `grid[0]`: the result shares the arguments, so neither is
     unique afterwards, and returning it needs `values.copy`. That is
     sound and rejects less. Spec section 10.3 still has the error; it
     changes when the rules become the default.
   - It must stay an error where the callee is not known at the call: a
     reference to a generic-read function, used as a value at a type that
     owns an array (`rows.map identity` on an array of arrays). Otherwise
     a function value of type `Array U32 -> Array U32` could return its
     argument and rule 3 would be unsound for `apply`.
   - Built (`reader`, `lentHere` in uniqueness.goose): the pass reads the
     callee's scheme from the module's Core bindings, which hold imported
     functions too, and matches it against the function type at the call
     to see what each type variable stands for there. A member reached as
     `value.member` is found by the receiver's type and the member's name.
     A call whose callee the pass cannot name (a contract member through a
     dictionary, a constructor used as a function, an effect operation)
     keeps phase 1's behaviour.
5. **Effects.** The result of an effect operation is not owned: a state's
   `get` returns what the state still holds. It stays shared until
   `modify` exists (rule 5).
6. **In-place append** only when the input is unique (the open item of
   phase 1).
7. **How to land it.** Rule 1 rejects existing code (at least the 44 Gdev,
   27 Ink and 75 guest sites measured for borrowed returns, more for
   results that are shared in themselves), so it goes in behind an
   environment switch that the tests set, is measured, and becomes the
   default once std, the tests, Ink and Gdev are changed. The switch is
   then deleted.

### The plan, measured (16 November 2026, before it became the default)

These numbers are from when the rules sat behind the environment variable
`BLOT_BORROWED_RULES`, applied to every module at once. They are what the
per-module scheme of "Phase 2 is the default" was chosen from; the switch
and its second reference record are gone.

With the switch on:

- each function and closure whose result type can own an array must
  return a value nothing else holds (`result_not_owned`);
- a call (`call` or `apply`) whose result type has no borrowing part only
  borrows its arguments, and its result is `deep`; an effect operation is
  excepted;
- a type variable holds no array;
- a full call of a generic function that may return what it was lent,
  where the type variable stands for a type that owns an array, shares:
  its result aliases its arguments. Using such a function as a value or
  applying it partly at such a type is `lent_result_value`, because a
  function value's result is taken to be the caller's alone;
- a constructor keeps its payload's fact, a tuple is `deep` when its parts
  are, and `@storage.freeze` of a local at its last read moves it, as does
  a pushed value;
- in a result whose type both owns arrays and has a part that borrows (a
  record with a closure field), the owned arrays are the caller's alone and
  the arguments stay shared with the borrowing part;
- a type the pass cannot read (opaque, an effect type) is exempt.

| With the switch on | |
| --- | ---: |
| Guest and host cases failing (of 1,163) | 24, in 14 files |
| Diagnostics in those runs | `result_not_owned`, and `lent_result_value` in 2 files |
| Distinct sites in std | 1 (`simd.store` returns the storage it wrote) |
| The older pass's narrowed rules, for comparison | 75 cases in 39 files |
| Gdev Main build: rejected returns | 56 (34 in gdev/src, 20 in ink/lib, 2 in std) |
| The older pass's narrowed rules, for comparison | 44 |
| Ink's 65 test files: distinct rejected returns | 33 (22 in ink/lib, 9 in the tests, 2 in std) |
| The older pass's narrowed rules, for comparison | 27 |

Two things are left out of the result rule on purpose:

- **Growable storage.** A `GrowArray` or a `ResizeArray` counts as a part
  that borrows, like a view or a reference. Ink and Gdev still write
  these through `=` from every holder, which is the transitional rule 3;
  a record of such handles is not a value anyone updates in place by
  `:=`. They become owned values when `=` goes (phase 3). Freezing a
  local one at its last read gives an owned `Array`.
- **Lists.** A `List` cannot be written in place at all, so it owns only
  what its elements own.

In the tests, a text or array literal a function returns is fresh and
passes; a module constant is one shared array, so `return table` needs
`table.copy`.

Gdev is measured with
`BLOT_BORROWED_RULES=1 blotc migrate-stores src/main.blot --project pen.json --dry-run --inference-budget 20000000`
in ../gdev; the dry run reports every diagnostic it cannot rewrite, in
every module, instead of stopping at the first. Of the 56 returns:

- about 25 return a parameter, changed or not (`return ground` after
  `ground.cells := …` in world/trails.blot, `return draws`,
  `return values`): `own`, or a copy;
- about 15 build a record from parameters' array handles (`$Scene`,
  `$FrameAccess`, `$Access`, `$Services`, `$Trails`): the parameters
  become `own`, or the record is built where the arrays are made;
- 5 are in generated or derived code whose span is the top of the file
  (codecs, `actor_observation`);
- the rest are `if`/`case` values and tuples of the same kinds, a save
  migration that returns `identity saved_values`, and `simd.store`.

An array whose elements only borrow (Ink's `Draw` holds a view) is owned
when the array itself is.

The count is higher than the older pass's 44 because that pass only
rejected borrowed storage; this one also requires the result to be unique
in itself, which the caller's in-place update relies on.

Ink's tests are measured one file at a time, in ../ink, with the same
command and each file of `compiler.settings.tests.files` in pen.json as
the entry; the sites are then counted once each.

**Why the change cannot be made ahead of the switch.** Most of these
sites want `own`. With the switch off a call's result is not unique and
lending ends uniqueness, so an `own` argument is harder to give than it
will be; code changed to `own` now would fail today. std, the tests, Ink
and Gdev therefore change in their working trees with the switch on, and
the default flips in the same step in all three repositories.

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
