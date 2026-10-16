# 067 — Implement typed code and descriptors

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed typed-staging acceptance
  traces by owner decision on 15 October 2026; trace-to-law index and a passing
  full gate on current source remain.
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

- [ ] Implement the specified typed code/descriptor nodes, constructors and
      stage checking.
- [ ] Preserve type/effect/identity evidence and reject incompatible code shapes
      or unavailable cross-stage values.
- [ ] Integrate evaluation and portable ownership without reparsing generated
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

- [ ] Typed code and descriptors pass the specified introduction/use laws in the
      ordinary pipeline.
- [ ] Invalid stage boundaries and shapes have precise diagnostics and never
      publish partial generated artifacts.
- [ ] Applicable checks pass and completion evidence records remaining
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
[STAGING_QUALIFICATION.md](../zig-native/STAGING_QUALIFICATION.md). No such
trace-to-law index exists yet; build it from the passing gate.

## Completion evidence

Native and client syntax own `code [T, row E]`, descriptor targets and stage
intrinsics, retaining contextual value names. Native syntax/OOM passes 17
filtered laws; client syntax/formatting passes 25 tests with one existing
ignored test. Logs:
`build/bench/continuation-20261013/staging-syntax-{native,client-v3}.log`.

Owned staging now passes seven executed guest laws, including imported callable
descriptors, independent expansion sites, same-type input/body edits, failed
revision recovery and restart parity. Portable native laws reject forged shapes,
effects, capture stages and replacement payloads; source teardown, roundtrip and
allocation-failure controls pass. Callable descriptors retain the quoted
closure's exact row certificate and preserve declared operation effects. The
previous imported `InvalidArtifact` blocker is repaired for this admitted
frontier. [The durable staging record](../zig-native/STAGING_QUALIFICATION.md)
pins the focused implementation and remaining limits. These results do not
qualify complete staging or generation.

- Commit: pending; record the local milestone revision.
- Validation: focused laws above; full compiler qualification remains open. Pure
  statement-if helpers additionally pass six native and twelve selected staging
  guest groups, with complete portable/restart OOM and exact both-tier
  source/archive/checkpoint parity. Pins:
  `build/bench/finish-program-20261014/staging-statement-if/`.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: general named pattern/request/resolver helpers and
  staged borrow/resource captures and general qualified producer transport
  remain open.
- Durable record:
  [staging qualification](../zig-native/STAGING_QUALIFICATION.md); full gate and
  cost qualification remain pending.

The 14 October follow-on admits bounded first-order generic named helpers and
public nominal lifts. Substitution and constructor payload ownership are
reconstructed independently at portable boundaries. Focused malformed-owner,
payload, allocation-failure and all twelve staging guest groups pass; tracked
JSON byte edits, recovery and restart now have executed controls. The exact
six-file patch SHA-256 is
`928b4dd9a1bd80147ce1ae18dc89c7356b1ea4313a8ef52e82b0a6bbbda8595d`. The single
final full compiler gate remains outstanding.

The later stage-owner batch passes 60 portable staging laws, including declared
request signatures, actual Foreign clauses, unused handlers, earlier-stage
affine lift/splice operands, nested quotes and once generators. Together with
operation/task/usage controls, 73 native laws, 25 guest groups and 413 selected
analyzer files pass. Source/archive/checkpoint/cache edits preserve fresh bytes
and last-good execution. Exact focused pins:
`build/bench/finish-rest-20261015/staging-stage-owners/`. General transport and
the final common gate remain required.

A further owned-data slice admits immutable producer-local initializers and
aliases while rejecting runtime, foreign and cyclic owners. Seven focused native
laws and the three changed imported-helper groups pass; thirteen guest groups
now have focused coverage. Exact source and pins are in
`build/bench/finish-program-20261014/staging-producer-data-source/`.

Public nominal field descriptors now reconstruct common constructor fields and
their generic substitutions. Four focused native laws and all fourteen staging
guest groups pass, including changed field types, source/compiled imports,
failed-edit recovery, restart and portable allocation failures. Exact pins are
in `build/bench/finish-program-20261014/nominal-descriptor-source/`.

Straight-line helper blocks now validate earlier local bindings and their exact
return target. Nested generic aliases survive producer teardown, roundtrip and
complete allocation failures. Forward reads, caller-local capture, duplicate
binding owners and foreign return targets reject. Two focused native laws and
four helper guest groups pass; fresh/retained/restart work agrees at 38 steps
for the new local-helper fixture. Exact pins are in
`staging-local-blocks-source/`.

Pure named helpers now construct ordinary nominal data, including generic,
nullary and positional constructors. Portable readers reconstruct result and
payload substitutions; private families, forged inputs and hidden callables
reject. Five native laws and five imported helper guest groups pass. Exact pins
are in `build/bench/finish-program-20261014/staging-nominal-helpers/`; full
qualification remains outstanding.

Pure collection helper bodies now reconstruct element, index and result types
for length, indexing, identity, concatenation, slicing and Array/List
conversion. Four focused native laws and seven helper guest groups pass,
including producer teardown, 64 complete roundtrip allocation failures, forged
shapes and both-tier out-of-bounds edit recovery. Fresh/retained/restarted work
agrees at 76 steps; unchanged/recovered input uses zero. The exact three-file
delta and pins are in
`build/bench/finish-program-20261014/staging-collection-helpers/`. General
staging and the final compiler gate remain outstanding.

Pure nominal field-reader helper bodies now own exact public family identities,
constructor tags, physical payload positions and generic substitutions. Seven
native laws and nine helper guest groups pass, including 64 complete roundtrip
allocation failures and forged same-type field paths. Both guest tiers preserve
40 work steps through edits and restart. Pins and the three-file delta are in
`build/bench/finish-program-20261014/staging-nominal-reads/`; general staging
and the final compiler gate remain outstanding.
