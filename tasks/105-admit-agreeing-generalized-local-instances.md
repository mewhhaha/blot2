# 105 — Admit agreeing generalized local instances

## Status, dependencies, and originating requirements

- **Status:** In progress — agreeing instances and closed promotion recorded on
  16 October 2026; per-use-layout runtime instances and their checks recorded
  on 17 October 2026; the commit remains.
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
- Comparison: not applicable; emission admission change only.
- Remaining limitations: promoted values whose uses leave holes open (Ink
  `app-hooks`; the effect repros `apprt`, `c1` and `hooks` fail identically
  before and after this change and were not diagnosed further); generalized
  locals in nested blocks (only a
  body's own statements are decided); producers containing blocks, matches,
  effects or proven in-place collection edits; locals captured by closures;
  more than four distinct use layouts. Each of these keeps reporting
  `ownership_unproved` rather than emitting a latent signature mismatch.
- Durable record: [CONTRACT.md](../zig-native/CONTRACT.md) generalized-local
  paragraph.
