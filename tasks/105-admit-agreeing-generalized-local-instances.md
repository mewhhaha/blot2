# 105 — Admit agreeing generalized local instances

## Status, dependencies, and originating requirements

- **Status:** In progress — agreeing instances and closed promotion recorded on
  16 October 2026; per-use-layout runtime instances and their checks recorded
  on 17 October 2026; Ink's app-hooks builders recorded on 17 October 2026;
  ambiguous holes recorded on 17 October 2026; the commit remains.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 16 October
  2026 as [issue #10](https://github.com/mewhhaha/blot2/issues/10); owner
  approved the checker-side fix the same day.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Valid programs whose generalized locals reach their uses through aliases, `:=`
rebinding chains, repeated same-layout uses, uses at different layouts or no
use at all compile with checked ownership instead of failing with
`ownership_unproved`.

## Starting point

Commit `23a934f` made production emission require checked whole-module
ownership. Before it, `wasm.zig` absorbed an unproven body with a tracing
fallback. A generalized local only received physical facts for its quantified
holes when it had exactly one concrete checked use
([CONTRACT.md](../zig-native/CONTRACT.md)), so `let c = b`, a second use or a
`:=` chain left a tuple word erased. `rcPlan` rejects erased `value` words,
which broke Ink's ECS builders.

## Implementation checklist

- [x] Visit body bindings last to first in `localStorageMappings`
      (`zig-native/src/backend/backend_emission.zig`) so later locals' facts
      close the uses feeding them.
- [x] Admit application and local-alias producers, and several uses when all
      agree on one concrete layout.
- [x] Ignore a use read only by an unused local alias, and give the holes of an
      unobserved local scalar word storage (`layout.word`).
- [x] Add executed-Wasm laws in
      `zig-native/tests/generalized_local_instance_execution.test.ts` and update
      the contract paragraph.
- [x] Uses at different layouts: a closed initializer built by a call,
      application, projection or constructor is evaluated speculatively
      (`Session.attemptClosedNode`) and kept as a static value serialized per
      use; the attempt restores the evaluator diagnostic when it declines and
      marks the code fresh. A compilation that fails after such a promotion
      retries once without promotions (`compileWithOptions`), so a promoted
      value that a use cannot serialize never replaces the ordinary diagnostic.
- [x] Runtime-dependent initializers used at different layouts (for example
      `let k = pair x` then `k x` and `k 1.5`): no single physical value can
      serve them, because closure signatures (`closureSignature`) and field
      words depend on the layout. A pure producer (call, application, member
      projection, constructor, product, record or local alias, built only from
      pure construction and local reads) with a representation-free value
      (`dataShape`) now runs once per distinct concrete use layout, at most
      four, in order at its binding (`decideInstances`, `prepareInstances`,
      `bindInstances`). Each instance owns a Body prepared under facts that
      close only the local's quantified type holes and its quantified or still
      unknown rows, because plans are keyed by node and one Body has one set of
      substitutions. Each use reads the instance of its own layout
      (`emitReference`). A read inside an instanced producer counts once per
      instance, so alias and `:=` rebinding chains instance every link.
- [x] Declines keep the current path: closure captures, merges, carries,
      qualified or generative schemes, authority-bearing or usage-contract
      values, blocks, matches, effects, collection edits proven to run in place
      (`ownsArrayUpdate`; a second evaluation would edit the edited array), more
      than four layouts and any use that leaves a hole open. A declined
      runtime-dependent initializer whose uses disagree still reports
      `ownership_unproved`; without that report the program would trap with a
      latent `call_indirect` signature mismatch, as it did under the old
      tracing fallback.
- [x] Replace the runtime-dependent decline law with executed laws (the issue
      program, a second entry returning the F32 field, an allocating producer
      with exported memory, three uses at two layouts, loop and early-return
      uses, an alias chain and a `:=` builder chain), keep the in-place edit and
      closure-capture declines as failure laws, and add a native replay,
      checkpoint and OOM law in `persistent_roots_tests.zig`.
- [x] Ink's app-hooks builders. The uses that leave the action result open
      (`reset_scoped`, `advance_scoped`, `render_scoped`) were already served:
      a static call keeps the promoted value in the compiler and serializes
      only the fields it selects (`inlineStaticCall`). Two other gaps failed
      the promoting attempt, and the retry then hit the captured local's
      erased scope tuple:
  - `app.run` reads only the engine, so the systems' rows stay open at that
    use and each callback is serialized at the instance its own body infers
    (`inferClosure`). `closeRetainedRows` (`core_eval.zig`) closed only the
    outer arrow of an anonymous closure, so the curried render system
    `fn presentation => fn frame => ...` stayed open and declined. A closure
    literal that is an anonymous closure's whole body is now closed like a
    named curried body's parameter arrow.
  - In a `:=` builder chain only the head `app.new policy` was closed; each
    later link read it, so `attemptClosedNode` declined and the head was
    serialized at the next link's erased layout. The attempt now reads
    enclosing locals that already hold evaluator values, so every link is
    promoted.
  - `closureWithStaticCaptures` kept a slice of the layout store across
    `closureFunction`, which can grow the store; it now copies the capture
    layouts first (it read freed storage, a safe-build index-out-of-bounds
    panic, on the first versions of the new law programs).
- [x] Executed laws for both shapes with exported, stable guest memory and a
      native replay, checkpoint and OOM law combining them.
- [x] Ambiguous holes. A promoted value serialized whole at a use that leaves
      a type variable open (`let boxed = #[b, b]` read only for its length;
      Ink's effect repro `c1`, whose route callback `fn (e: u) => e` reaches
      `create_world` with `u` and its row unconstrained) failed both attempts.
      A naive word stand-in at that serialization is unsound: the hole there
      is `boxed`'s own quantified variable, and a later use may read its
      shared storage at an array.
  - A use whose remaining holes are all ambiguous type variables, which no
    scheme, type declaration, operation, contract or implementation of the
    unit quantifies, now closes with scalar word storage for them and the
    closed empty row for its ambiguous row tails, throughout the body
    (`closeAmbiguousUse` in `localStorageMappings`). Checking left such a
    variable unconstrained, so no value of its type is ever built. The choice
    depends only on the variable, so bodies that make it agree, and nested
    closures and callee instances receive it through their layouts. Quantified
    holes still decline, so `boxed`'s own variable then takes one instance per
    use layout (F32, an array and the `.length` use's word), or stays open and
    reports `ownership_unproved` when a closure captures `boxed`.
  - Built data, arrays included, with one use takes a single instance
    (`decideInstances`), which gives `boxed` storage when `.length` is its
    only use.
  - In the promoting attempt a promotable local that only ambiguous storage
    closes stays undecided, so a closed initializer keeps its evaluator value.
    Otherwise Ink's builder chains (and the concrete-route variant of `c1`,
    which already built) would run their producers at runtime and reach
    `new_with`'s first link, whose row layout `decideInstances` cannot
    reconcile. Leaving it undecided is speculation: a runtime-dependent
    initializer (`let k = pair x` read inside `#[k, k]`) is not promoted, so
    that attempt fails and the retry instances it.
  - An inlined named body (`inlineNamedValuesMode`) encodes under the
    substitutions its plans were prepared under, local storage and ambiguous
    facts included, instead of the inline call's own.
  - The new native law's OOM pass caught a double free in the final merge of
    ambiguous facts; the merged list's `errdefer` is scoped to its own block.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Re-run the Ink ownership repro folder.

## Acceptance criteria

- [ ] Alias, dead alias, same-layout multi-use, partial application, rebinding
      chain and unobserved-local laws execute correctly with stable guest
      memory, and fail on the unpatched compiler.
- [ ] Closed initializers used at different layouts execute correctly, and so
      do pure runtime-dependent ones, with one instance per use layout and
      stable guest memory; declined runtime-dependent ones report
      `ownership_unproved`.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending.
- Validation (16 October): the seven new laws pass with the patched dev
  compiler; six fail and the decline law passes with the unpatched `2b2ffbb`
  compiler. Of Ink's ownership repros, every compiler-side
  `ownership_unproved` case now builds and returns the expected value except
  the three different-layout cases (`e6`, `twodiff`, `z5`), which closed
  promotion then served.
- Validation (17 October, runtime instances): all 16 laws in
  `generalized_local_instance_execution.test.ts` pass with the release and dev
  compilers; against an unpatched `05401a9` build the seven new executed laws
  fail with `ownership_unproved` and the other nine pass. The native law
  "generalized runtime locals used at different layouts evaluate one checked
  instance per layout through replay checkpoint and OOM" passes. Without the
  in-place edit guard the decline law's program compiles and returns 909
  instead of 808, which is why that guard exists. Ink's ownership and effect
  repro folders give the same outcomes as the unpatched build (every ownership
  repro builds; `apprt`, `c1` and `hooks` still report `ownership_unproved`).
  Nearby guest suites (14 files, 53 tests) pass, and `deno task lint:zig`
  reports 0 findings. `deno task test:compiler --budget-seconds 5400
  --phase-seconds 3600` passes in 18 minutes: native 2 × 1178 tests with no
  leaks, guests 1508, harness 28 and smoke 48.
- Validation (17 October, app-hooks): Ink's `app-hooks.blot` builds; with
  release and dev compilers `paused_frame` returns
  `[11, 0, 0, 0.5, 1, 2, 5, 6]` and `pause_events`
  `[11, 2, 0, 0.5, 0, 1, 2, 1, 2, 1, 2, 3, 4, 4, 5, 6]`, as
  `app-hooks_test.ts` expects, and `schedule_workload n` returns
  `[n, n, n(n+1)/2]`; guest memory stays at 131072 bytes over 1,000 repeated
  calls. All 18 laws in `generalized_local_instance_execution.test.ts` pass;
  against an unpatched `f6a2942` build the two new laws fail with
  `ownership_unproved` and the other 16 pass. The new native law passes and
  fails unpatched. Against the unpatched build, Ink's 50 test programs, 124
  ownership repros and 30 effect repros keep their build
  outcomes and every compared entry result (599 calls over the Ink tests and
  478 over the ownership repros), except `app-hooks` and the effect repro
  `hooks`, which now build. Seventeen nearby guest suites (119
  tests) pass and `deno task lint:zig` reports 0 findings. `deno task
  test:compiler --budget-seconds 5400 --phase-seconds 3600` passes in 21
  minutes: native 2 × 1181 tests with no leaks, guests 1516, harness 28 and
  smoke 48.
- Validation (17 October, ambiguous holes): the issue's `boxed` program
  returns 9 for `main 7`, and Ink's effect repro `c1` builds and returns its
  argument, with guest memory steady at 131072 bytes over 4,096 calls (memory
  exported for the check). All 23 laws in
  `generalized_local_instance_execution.test.ts` pass with the release and dev
  compilers; against an unpatched `48eda0a` build the four new executed laws
  fail with `ownership_unproved` and the other 19 pass, the new captured-`boxed`
  decline law among them. The new native law "ambiguous holes at generalized
  local uses take word storage through replay checkpoint and OOM" passes, and
  fails unpatched; its OOM pass found the double free fixed above. Against the
  unpatched build, Ink's 50 test programs, 124 ownership repros and 30 effect
  repros keep their build outcomes and every compared entry result (599 calls
  over 47 Ink test modules, 478 over 118 ownership repros), except `c1`, which
  now builds; `apprt` still reports `ownership_unproved`. Seventeen nearby
  guest suites (128 tests) pass with both compilers, and `deno task lint:zig`
  reports 0 findings. `deno task test:compiler --budget-seconds 5400
  --phase-seconds 3600` passes in 20 minutes: native 1182 + 1181 tests over
  two shards with no leaks, guests 1521, harness 28 and smoke 48.
- Comparison: not applicable; emission admission change only.
- Remaining limitations: ambiguous storage closes holes only at uses of a
  body's own generalized locals. The effect repro `apprt` needs it at the call
  instances of a named function: `app.run (application n) world ...` and
  `app.create_world (application n) ()` read only the engine, so
  `application`'s own type variables stay open there and its instance compiles
  with erased holes. Inside that instance those holes are quantified, so the
  builder chain stays undecided, `new_with` runs at an erased instance, and
  `ecs.new`'s promoted builder is serialized at an erased scope result
  (`unresolved_type` in the promoting attempt; the retry reports
  `public_arena`). Fixing it would mean taking ambiguous storage for every node
  of a body, call results and callee keys included, which changes callee
  instances broadly. `decideInstances` also still declines `new_with`'s
  single-use first link, whose binding row layout does not reconcile with its
  use; Ink reaches it only when a builder chain runs at runtime. Also
  generalized locals in nested blocks (only a body's own statements are
  decided); producers containing blocks, matches, effects or proven in-place
  collection edits; locals captured by closures, whose quantified holes stay
  open (the captured-`boxed` law); more than four distinct use layouts. Each of
  these keeps reporting `ownership_unproved` rather than emitting a latent
  signature mismatch or storing a quantified hole as a word.
- Durable record: [CONTRACT.md](../zig-native/CONTRACT.md) generalized-local
  paragraph.
