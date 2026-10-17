# 105 — Admit agreeing generalized local instances

## Status, dependencies, and originating requirements

- **Status:** In progress — implementation and focused checks recorded on 16
  October 2026; the full gate and commit remain.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 16 October
  2026 as [issue #10](https://github.com/mewhhaha/blot2/issues/10); owner
  approved the checker-side fix the same day.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Valid programs whose generalized locals reach their uses through aliases, `:=`
rebinding chains, repeated same-layout uses or no use at all compile with
checked ownership instead of failing with `ownership_unproved`.

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
- [ ] Runtime-dependent initializers used at different layouts (for example
      `let k = pair x` then `k x` and `k 1.0`) still decline.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Re-run the Ink ownership repro folder.

## Acceptance criteria

- [ ] Alias, dead alias, same-layout multi-use, partial application, rebinding
      chain and unobserved-local laws execute correctly with stable guest
      memory, and fail on the unpatched compiler.
- [ ] Closed initializers used at different layouts execute correctly;
      runtime-dependent ones report `ownership_unproved`.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending.
- Validation: the seven new laws pass with the patched dev compiler; six fail
  and the decline law passes with the unpatched `2b2ffbb` compiler. Of Ink's
  ownership repros, every compiler-side `ownership_unproved` case now builds and
  returns the expected value except the three different-layout cases (`e6`,
  `twodiff`, `z5`).
- Comparison: not applicable; emission admission change only.
- Remaining limitations: runtime-dependent initializers used at different
  layouts, and promoted values whose uses leave holes open (Ink `app-hooks`).
- Durable record: [CONTRACT.md](../zig-native/CONTRACT.md) generalized-local
  paragraph.
