# Memory model A: stores, successors, cells and roots

The owner's decisions are in tasks/LANGUAGE_COHERENCE.md, section A,
"Decisions (owner, 14 November 2026)". This file turns them into rules and
phases. App code spells the intrinsics as round 2, item 2 approved
(`Cell.new`, `World.new ()`, `values.copy`); std may keep `@name` forms.

## Rules

1. **Values and storage.** Scalars, tuples, records, sums and closures are
   values: immutable and copied. Arrays (`Array`, `GrowArray`,
   `ResizeArray`), cells and roots are storage: they have identity, and a
   copy of a value that holds storage holds the same storage.
2. **Store: `place = value`.** This is a statement. The place is a path that
   ends in storage: an element `rows[i]`, a nested element `grid[r][c]`, a
   field of an element `rows[i].x`, a cell's value `c.value`, or any of these
   through a root's component (`world.counts[i]`, `world.menu.value`). The
   path's root is any expression of storage type, or a local whose path
   reaches storage through record fields. The store writes in place, and
   every alias sees it.
   - `=` on a path that never reaches storage, such as a record field of a
     local record, is an error: use `:=`.
   - `@storage.write` goes away. References (`&T`, `&[T]`) become read-only
     (A4); writable code takes the owner (an array, cell or root).
3. **Successor: `name := value` and `name.path := value`.**
   - `:=` rebinds a local. On a path it builds the successor of the local's
     value with the leaf replaced: `rows[i] := row` is
     `rows := @array.set rows i row`, and `point.x := 1` is a record update.
   - Aliases keep the old root.
   - `self` is the old leaf, as today.
4. **No hidden copies.** When a `:=` path goes through storage, the compiler
   updates in place. That is correct only if nothing else can observe the old
   root, so the root must be **unique** at that point (below). Otherwise the
   update is an error (`aliased_update`) whose message offers the two
   fixes:
   - `=` (store in place, aliases see it);
   - an explicit copy (`values.copy`) before the update.

   A copy trait (traits redesign, C) may later allow an implicit copy. Paths
   that stay within values never need uniqueness.
5. **Uniqueness, inside one function.** No facts cross calls.
   - A local's storage is unique after it is bound to a fresh allocation:
     - an array literal;
     - `@array.fill`, `@array.generate`, `@array.set`, `@array.concat`,
       `@array.slice` or `@array.flatten`;
     - a copy (`values.copy`);
     - `Cell.new`;
     - a comprehension.
   - It stays unique after a `:=` update of itself, and it is unique
     inside a record when every storage field reached by the path is unique.
   - It stops being unique, for the rest of its scope, when the same version:
     - is bound to another name (`let b = rows`, or a pattern);
     - is captured by a closure;
     - is passed as an argument to any call or constructor, or used in a
       literal, tuple, record or spread;
     - is returned, broken out or yielded;
     - has a storage-typed element or field read out of it (`let row = grid[r]`).
   - Reading a plain element (`rows[i]` where the element type holds no
     storage) and taking the length do not alias.
   - Parameters, call results, constants, pattern bindings and loop carries
     whose incoming versions are not all unique are not unique.
   - A loop carry is unique when its initial value and every backedge value
     are.
   - Branches merge with "unique only if unique on every path".
6. **Cell.** `Cell a` is storage holding one value. `Cell.new x` creates one,
   `c.value` reads it, and `c.value = v` stores into it. In the backend it
   is a one-element array.
7. **Root.** A root declares a fixed group of storage components with their
   initial values. Creating it allocates every component, and they share one
   lifetime. A component can't be replaced (`world.counts := …` is an error),
   but its storage can be written (`world.counts[i] = v`). A root is
   storage, so passing it passes write authority to all its components.

   ```blot
   type World is root = {
     entities: ResizeArray Entity = #[],
     viewport: Cell Viewport = Cell.new viewport.default,
   }
   let world = World.new ()
   ```

   It replaces Gdev's `with_owners`. The backend lowers it to a record of
   its components' handles; the declaration, defaults and the "fixed
   components" rule live in the checker.
8. **Value restriction.** A `let` generalizes only when its value is a
   syntactic function (`func`), not when it is a constructor application,
   call or partial application. A generalized local is still instantiated
   per use as today.

## Phases

Each phase lands with its tests, keeps check:dev, the guest suite, Ink and
the Gdev frame green, and migrates std, ../ink and ../gdev itself.

1. **Store statement and uniqueness.**
   - Parse `place = value`, check it, and lower it to the in-place write the
     direct backend already emits for indexed updates.
   - Add the uniqueness analysis and the `aliased_update` error.
   - Add `blotc migrate-stores ENTRY [project options]`. It rewrites each
     `:=` that gets `aliased_update` into `=`, which keeps today's meaning
     exactly, because today's `:=` already writes in place. Run it until the
     program is clean.
   - Migrate std, Ink and Gdev with the tool, and review the diff.
   - Replace `@storage.write` (3 in std, 9 in Gdev) with `=` and remove it.
   - Update the guide.
2. **Value restriction.** Change it in the checker, then update the ignored
   guest cases that relied on generalized non-function locals: they become
   errors or are rewritten.
3. **Cell.** Add the type, `Cell.new` and `.value`, and migrate the `#[x]` /
   `[0]` cells in Ink and Gdev where the array is used only as a cell.
4. **Root.** Add the declaration, `World.new ()`, defaults and the fixed-component
   rule, then move Gdev's `with_owners` to a root.
5. **Read-only references** (A4). Reject stores through `&T` / `&[T]`.
   Escaping references are checked at run time (A6).

## Measured scope (14 November 2026)

| Tree | Lines | Path `:=` | `@storage.write` | `[0]` reads |
| --- | ---: | ---: | ---: | ---: |
| std | 1,367 | 1 | 3 | 5 |
| ink/lib | 23,526 | 1,006 | 0 | 325 |
| ink/tests | 20,161 | 1,659 | 0 | 681 |
| gdev/src | 27,134 | 2,092 | 9 | 1,088 |
