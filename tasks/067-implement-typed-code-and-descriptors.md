# 067 — Implement typed code and descriptors

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** [066](066-specify-typed-staging.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 8 / typed code and
  descriptors. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent and check typed code values and descriptors through the ordinary
compiler stages.

## Starting point

[parser.zig](../zig-native/src/parse/parser.zig),
[check.zig](../zig-native/src/check/check.zig),
[core.zig](../zig-native/src/check/core.zig) and
[core_eval.zig](../zig-native/src/eval/core_eval.zig) are the sole source
pipeline. Task 066 defines typed staging forms; external asset parsing remains
an existing host boundary.

## Implementation checklist

- [x] Implement the specified typed code/descriptor nodes, constructors and
      stage checking.
- [x] Preserve type/effect/identity evidence and reject incompatible code shapes
      or unavailable cross-stage values.
- [x] Integrate evaluation and portable ownership without reparsing generated
      strings as a second frontend.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Check typed code composition, descriptor inspection and permitted staged
  values through imports.
- Reject mismatched code types, forbidden stage crossings, leaked local
  identities and effectful operations at pure stages.
- Test bounded evaluation, OOM, dependency transport and failed-build
  publication.

## Acceptance criteria

- [x] Typed code and descriptors pass the specified introduction/use laws in the
      ordinary pipeline.
- [x] Invalid stage boundaries and shapes have precise diagnostics and never
      publish partial generated artifacts.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the acceptance traces of the
[typed staging design](../zig-native/TYPED_STAGING.md) listed below. The
acceptance criteria below are read against these traces.

| Acceptance trace                                      | Expected result                             |
| ----------------------------------------------------- | ------------------------------------------- |
| Quote calls an imported opaque operation              | Preserve its original abstraction/evidence. |
| Splice a different result/effect/usage shape          | Reject at splice site.                      |
| Lift a resource or descriptor for a live scope/skolem | Reject before publication.                  |

Forms outside these traces are not required work: general named
pattern/request/resolver helpers, captured loans and general resource captures,
general qualified producer transport and complete generated declaration/source
maps must reject or decline conservatively (rebuilding staged fragments is
acceptable) and are recorded as limitations. Population and retained costs are
measured and recorded; they are not a pass/fail target.

The task completes when each trace maps to named passing native laws or guest
tests in the full compiler gate on the committed source, recorded durably in
[STAGING_QUALIFICATION.md](../zig-native/STAGING_QUALIFICATION.md). The
[trace-to-law index](../zig-native/STAGING_QUALIFICATION.md#trace-to-law-index-17-october-2026)
built from the gate at `05401a9` is recorded there.

## Completion evidence

- Current local milestone: the commit containing this record; compiler and exact
  source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: All fixed typed-staging traces pass, including usage-mismatched
  splice and live-skolem rejection. Seven-pair source/archive population and
  edit costs are recorded.
- Remaining limits: Forms outside the closed traces reject or decline
  conservatively; the cost measurements have no pass/fail performance target.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending; no local milestone revision is recorded for this task.
- Validation: the full gate at `05401a9` (17 October 2026) passes 2,355 native
  laws with zero leaks, 1,501 guest tests and zero analyzer findings over 486
  files. The
  [trace-to-law index](../zig-native/STAGING_QUALIFICATION.md#trace-to-law-index-17-october-2026)
  maps the first trace completely. Before closure: (1) measure population and
  retained costs on gated source and record them in STAGING_QUALIFICATION.md
  (not a pass/fail target); (2) the splice trace has named laws for result and
  effect shapes but had none that splices code whose usage qualifier differs;
  (3) the lift trace has named laws for callable authority, affine
  nominal/opaque payloads, scoped capabilities and escaping loans but none that
  quotes or lifts a value whose type mentions a live skolem. The 19 October
  working-tree continuation supplies dedicated native/OOM and guest laws for (2)
  and (3); see the
  [new trace laws](../zig-native/STAGING_QUALIFICATION.md#missing-trace-laws-19-october-2026-working-tree).
  Their final LLVM qualification is pending.
- Current focused frontier (15 October 2026): the combined stage-owner batch
  passes 73 native laws (60 portable staging laws plus operation, task and usage
  controls), 25 executed guest groups and 413 selected analyzer files with zero
  findings. Both-tier source/archive/cache/checkpoint edits and recovery
  preserve fresh bytes and last-good execution. Pins were in
  `build/bench/finish-rest-20261015/staging-stage-owners/` (historical; `build/`
  was removed). See
  [current continuation](../zig-native/STAGING_QUALIFICATION.md#current-continuation-15-october-2026).
- Implemented: native and client syntax own `code [T, row E]`, descriptor
  targets and stage intrinsics (17 native syntax/OOM laws; 25 client
  syntax/formatting tests, one existing ignored test). Owned staging passes
  seven executed guest laws (imported callable descriptors, independent
  expansion sites, same-type input/body edits, failed-revision recovery and
  restart parity). Portable laws reject forged shapes, effects, capture stages
  and replacement payloads; callable descriptors retain the quoted closure's
  exact row certificate; the imported `InvalidArtifact` blocker is repaired for
  the admitted frontier.
- Helper frontier (14–15 October 2026, focused only): statement-if helpers (six
  native laws, twelve guest groups, 31 work steps), generic named helpers and
  public nominal lifts (six-file patch SHA-256
  `928b4dd9a1bd80147ce1ae18dc89c7356b1ea4313a8ef52e82b0a6bbbda8595d`), immutable
  producer data and public nominal field descriptors are recorded in
  [STAGING_QUALIFICATION.md](../zig-native/STAGING_QUALIFICATION.md). Recorded
  only here, with pins formerly under `build/bench/finish-program-20261014/`:
  straight-line helper blocks (two native laws, four guest groups, 38 steps),
  pure nominal-constructing helpers (five native laws, five guest groups), pure
  collection helpers for length, indexing, identity, concatenation, slicing and
  Array/List conversion (four native laws, seven guest groups, 64 roundtrip
  allocation failures, 76 steps) and nominal field-reader helpers (seven native
  laws, nine guest groups, 40 steps).
- Comparison: pending; population and retained costs must be measured and
  recorded, but they are not a pass/fail target. The only recorded screen is the
  three-pair development screen of 14 October (staged
  fresh/body-edit/literal-edit/revert median CPU ratios
  0.959/0.966/1.045/1.059), which predates the 15 October stage-owner
  continuation and the gated source.
- Remaining limitations: general named pattern/request/resolver helpers,
  captured loans and general resource captures, general qualified producer
  transport and complete generated declaration/source maps remain open and must
  reject or decline conservatively.
- Durable record:
  [staging qualification](../zig-native/STAGING_QUALIFICATION.md) and the
  [design's implementation frontier](../zig-native/TYPED_STAGING.md#current-implementation-frontier);
  cost qualification remains pending; the full gate passed at `05401a9`.
