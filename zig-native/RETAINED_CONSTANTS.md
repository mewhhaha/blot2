# Retained aggregate constants

Task 022 lets a retained function or closure fragment keep its code when it
serializes an aggregate constant, not only a scalar one. Before, any constant
child job whose value was not a scalar marked its fragment fresh, so every
caller of an array, record, nominal or closure constant was rebuilt on every
edit. The compiler milestone is `62241e2f2d315b46c6b32a1785dfe1942ba44720`;
qualification is recorded below.

## Admission

[artifact_fragment.zig](src/reuse/artifact_fragment.zig) admits an aggregate
constant child of a retained fragment when all of the following hold:

- the old job completed with a value that is not a scalar, demand suspension,
  computation, request decision, type constructor, resolver or provider, and
  whose old serialized root (value and layout, never a suspension key) is
  recorded in the previous capture's `serialized` pool;
- the current target is an admitted, non-runtime body whose slot is already
  complete, so admission never demands evaluation;
- the old value graph matches the current value through the ordinary graph Plan
  (`inspectRootsWithRows` and `matchInto`): scalar bits, nominal identities,
  closures, alias topology and children must agree, exactly as for static reads,
  and the anchors are recorded with the importer;
- the constant's layout imports into the current owner.

Each admission is memoized per old child job. The caller may then keep
`static_address` operands, in instructions and data words, that name exactly
that old root; interior addresses still decline. The admitted child's own
subtree of jobs and records is not admitted or replayed, because it is never
reused.

## Reconstruction

When a retained fragment's replay reaches an admitted aggregate child, the
current generator runs its ordinary `constant` path (`replayConstant`). The
current value is serialized into the current owner's data with the current memo,
exactly as a fresh compile at that point would, and the job is entered in the
current Context. The old root address then resolves to the returned address for
every remaining operand of the fragment. Relocated data, function indices and
memo hits therefore follow the current revision; retained output stays
byte-identical to a fresh build.

Evaluation order, constant jobs, fuel and failures are unchanged: constants are
still evaluated by the current Session, and a trapping constant fails the
revision with its ordinary diagnostic. Demand cells and other generative or
operational values always rebuild their callers, so creation identity and
once-per-creation sharing are preserved, and no runtime memo result is merged by
a code key.

`Result.reuse.reused_aggregate_constants` counts replayed aggregate children.

## Qualification on 10 October 2026

The baseline is the task-021 compiler sources (`696051e`); the candidate release
compiler is pinned with its probe in
[the pins](qualification/aggregate-constants-pins.json).

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 627 guest/client tests; `deno task lint:zig` reports
  zero findings across 308 files.
- [Native laws](src/backend/aggregate_constant_tests.zig): an unrelated edit
  replays both aggregate callers with fresh-identical output under an
  allocation-failure sweep; a changed array element, a changed nominal payload
  or both rebuild exactly the affected callers.
- [A process-level law](tests/aggregate_constant_reuse.test.ts) compares a
  retained server with fresh servers through an unrelated edit, inserted
  functions and data that move every later address, an element edit, a trapping
  constant and its correction. Array, nominal, aliased-tuple and
  imported-dependency aggregates execute correctly; bytes and native work steps
  equal fresh builds; aggregate replays occur.
- Existing scalar-constant, retained-record and static-capture laws pass.

### Measurements

The task-021 retained probe ran 21 alternating repetitions over the earlier
eight example workloads plus a generated aggregate program
([CSV](qualification/aggregate-constants.csv)). Every phase emits identical Wasm
in both compilers and retained memory plateaus.

| Workload                                    | Steady edit/revert                                                                           |
| ------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Generated aggregate program, unrelated edit | 0 → 4 functions and 4 aggregate constants replayed; 4.9 KB less requested; CPU 0.992 / 1.003 |
| Public examples                             | Replay counts unchanged; requested allocation +8 bytes to +3.3 KB; CPU within noise          |

Steady-phase CPU geomeans are 0.999 (edit) and 1.001 (revert); rejected-edit and
no-op controls are 0.996 and 0.982. Population samples are bimodal in both
compilers (for example 16–18 ms versus 27–29 ms on ecs, with minima 15.8 and
16.2 ms); population performs no retained replay, so its geomean of 1.07 is host
noise rather than a change. One-minute load was about 5. No public example
replays an aggregate constant in these workloads, and the reason their callers
stay fresh was not investigated; the measured benefit is the generated program.
The small allocation increases include one more statistic in every result and,
on retained compiles, an index of the previous revision's serialized roots.

## Remaining scope

- Aggregate data is re-serialized every revision; only the caller's code is
  retained. Old data bytes are not replayed.
- Interior addresses into an aggregate, demand cells, computations, request
  decisions, providers and runtime globals still rebuild their callers.
- Constants are still evaluated each revision; evaluation reuse across revisions
  is outside this task's proof boundary.
