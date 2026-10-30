# 053 — Qualify module cutoffs and wrapper erasure

## Status, dependencies, and originating requirements

- **Status:** Complete — the owner-defined fixed rows 1–13 pass on the repaired
  20 October 2026 source. The full LLVM gate executes 2,497 native laws, 1,585
  guest/client checks and 37 harness checks with zero native skips, failures,
  leaks or logged errors. Both analyzers report zero findings over 511 source
  files and the fixture; all 96 wrapper contexts, five operation comparisons,
  CPU controls and strict compile parity pass. The failed package-getter gate
  and earlier noisy CPU screens remain recorded separately.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / interface
  cutoff and zero-cost wrappers. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Prove that private implementation edits reuse callers and eligible abstraction
wrappers add no runtime representation cost.

## Starting point

Task 052 supplies opacity and task 024 general interface cutoff.
[module_frontend_cutoff.zig](../zig-native/src/reuse/module_frontend_cutoff.zig),
resolved layouts and optimizer captures provide the reuse/representation
boundaries.

## Implementation checklist

- [x] Make private implementation dependencies distinct from public interface
      dependencies for semantic callers.
- [x] Preserve executable invalidation where private code is inlined or staged,
      even when semantic callers reuse.
- [x] Identify eligible wrapper erasure and compare layouts/operations without
      weakening nominal identity or privacy.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Edit a private body/representation with an unchanged public interface; compare
  caller query work and fresh/retained output.
- Change the public contract and prove invalidation resumes across source and
  compiled dependencies.
- Compare wrapped/unwrapped layout and generated operations for eligible cases;
  test escapes and non-eligible fallback.

## Acceptance criteria

- [x] Private edits achieve the specified semantic cutoff while executable
      dependencies stay correct.
- [x] Eligible wrappers add no representation allocation or indirection;
      retained nominal/privacy laws still pass.
- [x] Applicable checks pass and completion evidence records remaining
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
   semantic callers reuse. Evidence: owned
   binding/type/contract/associated/implementation catalog correspondence,
   original method capability facts and both-tier relocation guests pass. The
   rejected append-only symbol-prefix experiment remains historical.
4. Parameters are alpha-renamed under an unchanged scheme: semantic callers
   reuse. Evidence: type/scheme/value/effect alpha laws preserve graph sharing,
   callable roles and fresh/source/archive/checkpoint parity.
5. A private representation changes from U32 to F32 behind unchanged public
   signatures: semantic callers reuse; storage and call consumers rebuild.
   Evidence: native/OOM and both-tier storage laws demonstrate semantic reuse
   with current executable recipes and exact fresh output.
6. A private record field is renamed with an unchanged layout: semantic callers
   reuse; executable readers of the changed private facts rebuild. Evidence: the
   storage edit laws demonstrate semantic reuse and fresh executable parity
   through reverts and restart.
7. A representation gains a reference word: the semantic interface may stay
   equal, while ABI and ownership consumers rebuild and roots are preserved.
   Evidence: scalar/reference and derived-storage laws show semantic reuse,
   current machine consumers, root preservation, rollback and restart.
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
    law and F32 sums at 83.344 → 83.016 μs/call (paired median 0.9976). The
    final release also passes exact operation bodies and allocation traffic in
    the wrapper matrix.
11. Reference and generic record wrappers add no tag, cell, allocation or
    indirection beyond their representation's own, and keep aliasing, ownership
    and effect order. Evidence: reference aliases at 3.734 → 3.703 μs/call
    (paired median 1.0000). The final release passes the exact
    allocation/ownership-traffic comparison.
12. Wrapped values through imports, portable dependencies, captured and returned
    values and retained edits keep the unwrapped program's machine bodies and
    layouts, results, traps, effects and memory counters (whole-Wasm equality
    only where nominal metadata is held equal). Evidence: all 96 context rows
    pass exact public/private machine bodies, executable sections, callbacks,
    traps and allocation/ownership traffic.
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

- The fixed rows 1–13 are complete. The
  [final qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#final-task-053-qualification-20-october-2026)
  records the row-to-law map and exact source, binary, timing and report pins.
- Private storage, binding/type/effect/contract insertion and movement,
  parameter alpha changes, public contracts, associated methods and bounded
  public implementations retain semantic callers. Executable readers consume
  current original-producer recipes. Native allocation-failure laws and
  both-tier source/archive/checkpoint/restart/failed-edit guests preserve
  last-good owners.
- Release `1b05518e…` passes the complete LLVM gate: 2,497 executed native laws,
  1,585 guest/client checks and 37 harness checks; zero native skips, failures,
  leaks or logged errors. CI/local analyzers and uncached local checks cover all
  511 source files and the fixture with zero findings.
- All 96 exact wrapper contexts and five operation comparisons pass. The
  preselected seven-pair identity control and 15-pair candidate comparison on
  CPU 2 pass; the candidate paired median is 0.998133 against the 1.05 limit.
  Broad distributions establish no speedup. All 162 strict compile samples and
  14 fresh-edited controls pass, including restart/shared sessions, with no
  output waivers or hash writes. The protocol test keeps its expected rejection.
- The repaired requested-allocation campaign passes 176 observations/88 pairs
  across both tiers. All fourteen Session groups end at zero requested live
  bytes. The record separates fresh/retained work, requested bytes, publication
  peaks, guest allocation traffic and release CPU; it makes no RSS claim.
- The initial package-getter failure is retained. Its repair derives the checked
  receiver and uses the existing exact public member/scheme proof; legacy
  metadata, incorrect members/receivers and physical payload guesses have full
  native/OOM and executed controls.
- No fixed acceptance row remains open. Unsupported or exhausted forms retain
  task 024's recorded ordinary-checking limits; performance targets stay with
  tasks 100–104. No private workload source or benchmark artifact is committed.
