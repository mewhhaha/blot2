# 061 — Check usage and call multiplicity

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
- **Dependencies:** [060](060-specify-usage-and-lifetime-contracts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 5 / checked usage
  and invocation. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Enforce the specified usage and invocation rules across branches, loops,
aliases, captures and higher-order calls.

## Starting point

Task 060 defines source contracts;
[check.zig](../zig-native/src/check/check.zig), resolved ownership and summary
evidence provide implementation boundaries. Existing uniqueness optimizations
remain insufficient as source-level proofs.

## Implementation checklist

- [ ] Track uses and ownership flow by binding identity, joining branches and
      iterating loop facts conservatively.
- [ ] Check unique/shared and borrowed uses plus once/many function invocation
      and capture contracts.
- [ ] Import/export complete usage evidence and reject hidden duplication or
      borrow escape through generic/higher-order calls.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test valid exclusive transfer, sharing, scoped borrowing and specified
  once/many callbacks.
- Reject double use, duplicate aliases, illegal loop invocation, incompatible
  branches and captured borrowed escapes.
- Exercise imported contracts, polymorphic calls, failed edits, OOM and bounded
  recursive analysis.

## Acceptance criteria

- [ ] Every specified usage and multiplicity law is enforced at source and
      dependency boundaries.
- [ ] Valid programs remain accepted and diagnostics identify the conflicting
      use or lifetime.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract | Qualified requirements                      |
| -------- | ------------------------------------------- |
| Usage    | Moves, aliases, branches, loops, once/many  |
| Usage    | Loans, sharing, qualified polymorphic calls |

Intentional rejections under the normative design: affine values hidden in
unrestricted type binders.

The task completes when every native law and guest test mapped to these rows
passes in the full compiler gate (`deno task test:compiler` and
`deno task lint:zig`) on the committed source. The rows passed in the 15 October
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Commit: pending; record the local milestone revision.
- Focused evidence: the isolated lexical loan freeze passed 19 native usage
  laws, three executed guest tests and zero analyzer findings (354 selected Zig
  files), using Zig 0.17.0. Native/guest controls cover immutable mutants,
  allocation failures, imports, sync/JSPI, failed revisions and restart replay.
  The paired scalar resource candidate also passes all 19 usage laws and three
  usage guests unchanged; the earlier isolated 416-file analyzer claim is
  withdrawn because its Zig/std backend was missing. Combined release
  qualification remains pending.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Reference continuation: fresh primitive Array/List literals and resource
  payloads have source/Core and executed both-tier sync/JSPI controls; existing
  unrestricted/shared bindings cannot acquire unique ownership by annotation.
  The paired reference scope preserves zero roots/leases and flat warmed memory
  across failure/recovery, imports, archive and checkpoint restart.
- Sharing continuation: explicit unique-to-shared conversion has source/Core,
  complete allocation sweeps and both-tier archived/restart execution controls.
  Returned once captures preserve their exact owning header; existing shared,
  loaned and unrestricted inputs cannot be cast into conversion authority.
- Remaining limitations: complete nominal/package affinity, generic and
  higher-order usage evidence, resource transfer and task 062 cleanup remain
  open.
- Durable record:
  [bounded qualification](../zig-native/USAGE_CONTRACTS.md#bounded-implementation-and-qualification).

- Transfer prerequisite: unique/shared primitive and primitive Array/List values
  now retain an explicit counted payload box through specialization, capture,
  portable artifacts and the owning input ABI. Scoped loans still expose only
  payload and retain their exact region identity. Generic shared substitutions
  use the selected physical owner graph; unknown generic affine invocation
  remains rejected. Acquired owning public outputs and borrowed cleanup captures
  reject. Broader nominal/generic affinity and the final combined gate remain
  open; this prerequisite does not finish task 061.
