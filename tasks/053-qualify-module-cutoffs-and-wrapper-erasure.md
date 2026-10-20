# 053 — Qualify module cutoffs and wrapper erasure

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed acceptance rows by owner
  decision on 17 October 2026. The 20 October continuation passes the full
  compiler gate and exact wrapper comparisons. Row 3's unchanged-public-contract
  gap has a fix, including authored scheme origins and used contracts. Its new
  full gate passes 2,489 native laws, 1,578 guest/client checks and 37 harness
  checks; all 96 release wrapper contexts also pass. Its first CPU guard failed
  (paired median 1.187 against 1.05); the independent identity control and
  expanded 15-pair comparison pass (0.983 and 1.021). Strict compile parity
  passes 162 samples plus fresh-edited controls, including restart/shared.
  Public-contract correspondence is qualified. Bounded implementation catalogs
  still give 0/0 caller reuse, and an initial associated-method artifact failure
  needs diagnosis. No completion is claimed.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / interface
  cutoff and zero-cost wrappers. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Prove that private implementation edits reuse callers and eligible abstraction
wrappers add no runtime representation cost.

## Starting point

Task 052 supplies opacity and task 024 general interface cutoff.
[module_frontend_cutoff.zig](../zig-native/src/reuse/module_frontend_cutoff.zig),
resolved layouts and optimizer captures provide the reuse/representation
boundaries.

## Implementation checklist

- [ ] Make private implementation dependencies distinct from public interface
      dependencies for semantic callers.
- [ ] Preserve executable invalidation where private code is inlined or staged,
      even when semantic callers reuse.
- [ ] Identify eligible wrapper erasure and compare layouts/operations without
      weakening nominal identity or privacy.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit a private body/representation with an unchanged public interface; compare
  caller query work and fresh/retained output.
- Change the public contract and prove invalidation resumes across source and
  compiled dependencies.
- Compare wrapped/unwrapped layout and generated operations for eligible cases;
  test escapes and non-eligible fallback.

## Acceptance criteria

- [ ] Private edits achieve the specified semantic cutoff while executable
      dependencies stay correct.
- [ ] Eligible wrappers add no representation allocation or indirection;
      retained nominal/privacy laws still pass.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 17 October 2026

The owner closed this task's scope to the fixed rows below. Rows 1–9 are the
private-edit rows of the
[module abstraction acceptance laws](../zig-native/MODULE_ABSTRACTION.md#acceptance-laws)
that concern semantic cutoff, including the cases the
[implementation limits](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#limits-and-next-qualification)
name as still open (unrelated private insertion, private declaration relocation
and alpha-renamed parameters). Rows 10–13 are the
[wrapper erasure](../zig-native/MODULE_ABSTRACTION.md#wrapper-erasure) cases,
including the operation-body and allocation-traffic comparison those limits
leave to this task. The checklist and acceptance criteria above are read against
these rows. "Eligible wrapper" means the single-constructor opaque scalar,
reference and generic record representations of rows 10–12.

1. A private body changes while its public signature stays fixed: semantic
   callers reuse, executable readers rebuild, and source, dependency and
   checkpoint output equals fresh output. Evidence: an opaque three-module law
   reuses both callers (fallback elaborations 5 → 3; values 42 → 43 → 42); see
   [chains](../zig-native/BODY_CUTOFF.md#chains-with-no-clean-dependency-15-october-2026).
2. A private local is added to or removed from an opaque producer's last
   function: callers keep semantic reuse. Evidence:
   [inert principal suffixes](../zig-native/BODY_CUTOFF.md#inert-principal-suffixes-15-october-2026).
3. An unrelated or private declaration is inserted before an opaque type, or a
   private declaration moves: identity and public interface are preserved and
   semantic callers reuse. Open: insertions that shift shared principal slots
   still decline, and an append-only symbol-prefix experiment was rejected.
4. Parameters are alpha-renamed under an unchanged scheme: semantic callers
   reuse. Open: exact positional comparisons may recheck callers.
5. A private representation changes from U32 to F32 behind unchanged public
   signatures: semantic callers reuse; storage and call consumers rebuild. Open:
   executed laws check fresh parity, not semantic reuse.
6. A private record field is renamed with an unchanged layout: semantic callers
   reuse; executable readers of the changed private facts rebuild. Open, as in
   row 5.
7. A representation gains a reference word: the semantic interface may stay
   equal, while ABI and ownership consumers rebuild and roots are preserved.
   Fresh parity passes in the scalar-to-reference edit laws; semantic reuse is
   not yet shown.
8. A public type, visibility, relationship or forwarding producer changes:
   affected semantic callers recheck across source and compiled dependencies and
   no old evidence is admitted. Evidence: the 052 laws and the body-cutoff
   revocation laws (changed binding records, equal-interface retargets).
9. A malformed or old artifact, failed edit or allocation failure: reject or
   recompute without changing last-good owners or output. Evidence: the 052
   allocation-failure sweeps and the body-cutoff replay sweeps.
10. Scalar opaque wrappers (U32/F32, including NaN, negative zero and infinity
    bits) have the payload's machine parameter/result shape and storage
    operations and use no heap. Evidence: executed laws, the scalar no-memory
    law and F32 sums at 83.344 → 83.016 μs/call (paired median 0.9976). Open:
    the recorded operation-body comparison.
11. Reference and generic record wrappers add no tag, cell, allocation or
    indirection beyond their representation's own, and keep aliasing, ownership
    and effect order. Evidence: reference aliases at 3.734 → 3.703 μs/call
    (paired median 1.0000). Open: the allocation-traffic comparison.
12. Wrapped values through imports, portable dependencies, captured and returned
    values and retained edits keep the unwrapped program's machine bodies and
    layouts, results, traps, effects and memory counters (whole-Wasm equality
    only where nominal metadata is held equal). Open.
13. Shapes that are not eligible (multi-constructor data; deep, exhausted or
    unresolved ABI proofs) stay ordinary data or decline emission, never a
    guessed machine type. Evidence:
    [052 limits](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#limits-and-next-qualification).

The task completes when rows 3–7 and 10–12 are demonstrated, every native law
and guest test mapped to rows 1–13 passes in the full compiler gate
(`deno task test:compiler` and `deno task lint:zig`) on committed source, and
the row-to-law mapping, with fresh/retained work and requested/live allocation,
is recorded in
[MODULE_ABSTRACTION_QUALIFICATION.md](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md).

What moved where (nothing is dropped silently):

- **CPU and allocation targets:** this task records work and allocation; the
  targets stay with tasks [102](102-reach-the-body-edit-target.md) and
  [104](104-reduce-requested-allocation-below-100-mb.md).
- **Private edits inside body forms that task
  [024](024-apply-general-body-interface-cutoff.md) leaves on ordinary
  checking:** they follow 024's closed acceptance (recorded limitations, moved
  to task 102 only when measurement shows them blocking the body-edit target).
- **Stable declaration-local IDs and symbol order:** task 102's structural work
  may satisfy row 3; this task still owns the module-level law.
- **Namespace-wide exports:** outside the reviewed syntax, as recorded in the
  052 limits.

No new task is added: every row is finite and specified.

## Completion evidence

- Current state: rows 1, 2, 8, 9 and 13 have evidence in committed source (the
  continuation landed in `23a934f`; the `05401a9` gate passes 2,355 native laws
  and 1,501 guest tests with zero analyzer findings). The qualified 20 October
  slice extends this evidence below; the task remains open for its remaining
  fixed acceptance cases.
- Prior evidence: task 052's implementation (focused 37 native and 31
  executed-Wasm laws; joint full gate at `f184dde` with 1,400 native laws, 871
  guest/client laws and 343 analyzer files at zero) erases scalar and reference
  wrappers to their payloads. `scripts/bench_module_abstraction.ts` measures the
  wrapper operations in rows 10–11 over 15 alternating pairs. The `f184dde`
  joint gate also reruns the representation, root, callback and privacy laws
  against task 032's result roles, which the 052 limits required.
- Cutoff evidence for rows 1 and 2 comes from task 024's 15 October
  all-dirty-chain and inert-suffix slices. The rejected append-only
  symbol-prefix experiment noted in row 3 (`growing-symbol-cutoff/`) is
  summarized in [CONTINUE.md](../CONTINUE.md).
- Remaining: rows 3–7 and 10–12 and the durable row-to-law mapping.
- Durable record: [module abstraction](../zig-native/MODULE_ABSTRACTION.md),
  [implementation qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md)
  and [body interface cutoff](../zig-native/BODY_CUTOFF.md).

The qualified 20 October cloud continuation covers known storage changes,
derived opaque producers, value-parameter alpha changes and unrelated opaque
callers with native/OOM and both-tier executed laws. Scalar and reference/record
wrappers pass exact executable and allocation controls. The complete compiler
gate, CI/local analyzers, pinned compile parity and CPU guard pass as recorded
below. Remaining public-contract correspondence is developed separately.

The
[continuation law map](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#task-053-continuation-19-october-2026-qualification-in-progress)
records the focused binding/type relocation and generic alpha laws, while
keeping unqualified private authority/catalog cases open. The expanded 96-row
matrix now passes exact exported and private function signatures/bodies and
allocation/ownership traffic, including traps and ordered host callbacks. The
earlier extra callback descriptor and reference bounds branch are removed by
bounded adapter emission and exact operand preservation. All 96 rows also match
whole non-custom Wasm sections in development and release screens. The first
full gate passes 2,476 native laws, 1,570 guest/client checks and 37 harness
checks, but a subsequent circular foreign-recipe control found an
artifact-validation gap. A bounded positive-only role proof now rejects it in
focused checks; the repaired source now passes the replacement full gate and
analyzers. Private binding/type insertion, relocation and generic alpha changes
now pass focused native/OOM and executed checks together with that repair and
are integrated. Both analyzers and the activated local uncached checks pass 510
source files plus the fixture module with zero findings. The final forced full
gate on 20 October passes 2,484 native laws executed, 1,574 guest/client checks
and 37 harness checks, with no native skips, failures, leaks or logged errors.
The final release's 96 context rows and five operation pairs also match exact
executable sections and allocation traffic. Pinned compile parity and the
seven-pair CPU guard also pass. Private-only effect/contract insertions and
public effect alpha now pass the expanded controls. The standalone
68-observation allocation campaign records lower requested revision bytes but
higher retained publication peaks, with zero final live bytes. Complex public
authority/catalog correspondence still needs work.

The additional unchanged-public-contract control confirms a concrete row-3 gap:
a private insertion reuses neither caller when the producer also has an unused
public contract, while the same insertion without that contract reuses both.
Fresh bytes and executed witnesses agree. The
[durable screen](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#remaining-public-contract-cutoff-20-october-2026)
records the original gap and the integrated focused fix. Complete qualification
of the public-catalog and authored-origin continuation remains required.
