# 020 — Persist complete semantic artifacts

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `8803452`.
- **Dependencies:** [019](019-serialize-the-query-table.md)
- **Originating requirements:** PLAN: Earlier programs / portable complete
  semantic artifacts. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Extend portable artifacts to fully represented semantic results and their
dependencies across processes.

## Starting point

Existing
[backend_checkpoint.zig](../zig-native/src/backend/backend_checkpoint.zig) and
[dependency_bundle.zig](../zig-native/src/reuse/dependency_bundle.zig) retain
only eligible subsets.
[source_value_template.zig](../zig-native/src/reuse/source_value_template.zig)
and evidence import code represent ownership-sensitive graphs; unsupported
providers and generative domains currently decline.

## Implementation checklist

- [x] Identify and implement every graph node needed for complete semantic
      results admitted by the design, including type/effect evidence and capture
      relationships.
- [x] Reconstruct owners, aliases, source and nominal identities on import;
      never reuse native IDs as cross-process identities.
- [x] Record all semantic dependencies and reject unsupported or incomplete
      graphs conservatively. Document represented versus deliberately declined
      cases.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Run process-boundary round trips for higher-order, captured, nominal,
  effectful and recursive semantic results.
- Test unsupported nodes, forged identities, missing edges, corruption and OOM
  during graph remapping.
- Compare fresh, retained, dependency-loaded and restarted
  diagnostics/execution, including failed-edit correction.

## Acceptance criteria

- [x] Every supported semantic result is represented completely and reconstructs
      valid independent ownership.
- [x] No incomplete artifact certifies reuse; remaining unsupported cases are
      explicit and cannot be mislabeled as complete coverage.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `88034529833783de881e59a0aca3e2b93fab69bb` (compiler milestone).
- Implementation:
  [semantic_archive.zig](../zig-native/src/reuse/semantic_archive.zig) persists
  the previous revision's complete selected-specialization owner (exact checked
  Core per unit with type-node certificate bytes, namespace, evaluator snapshot,
  slots, field locations and completed receipts) under claim
  `selected_complete_proof`. Decoding validates every graph and ordinal, then
  rebuilds a Capture used only as the query predecessor of a compile without an
  in-process previous revision; the ordinary Gate, Importer and graph Plan admit
  every receipt against current source. Owners with no namespace or no
  replayable receipt are omitted.
- Fixes found on the way: libraries with a monadic `do` can now be packed as
  dependency artifacts; an OOM in the backend's fresh query Gate no longer
  crashes at teardown; artifact encoding uses one exact buffer instead of
  roughly six times the encoded bytes.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 626 guest/client tests;
  `deno task lint:zig` reports zero findings across 305 files (analyzer pin
  `756bfd5`). Native laws cover restart replay with fresh parity under an
  allocation-failure sweep, edits, failing sources, forged inputs and owner
  omission; TS laws cover example restarts, a packed monadic dependency and a
  dependency-loaded project through edited, failing and corrected revisions.
- Comparison: task-019 compiler (`69e8692e…`) versus candidate (`640c744d…`), 31
  alternating rounds over 18 workloads (3,348 CLI builds): identical Wasm in
  every phase with equal reuse. Seven examples replay 1–3 selected receipts
  after restart at 14–26% (1.2–3.4 ms) more restart median CPU and 177–338 KB
  larger checkpoints; the other 11 workloads allocate 4–135 KB less. No restart
  speedup is claimed.
- Remaining limitations: on small programs the owner costs more restart CPU than
  it saves; Core is validated at decode and again by the Gate. Executable
  fragments, retained principal evidence, layouts, templates, provider/request
  state, canonical plans and builtin effect operations remain declined and
  recompute. Large-program benefit was unmeasured without private gdev and is
  left to task 084.
- Durable record:
  [persisted semantic artifacts](../zig-native/SEMANTIC_ARTIFACTS.md),
  [restart distributions](../zig-native/qualification/semantic-artifacts-restart.csv),
  [decode distributions](../zig-native/qualification/semantic-artifacts-decode.csv)
  and [pins](../zig-native/qualification/semantic-artifacts-pins.json).
