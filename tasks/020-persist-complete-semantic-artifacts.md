# 020 — Persist complete semantic artifacts

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `8803452`.
- **Dependencies:** [019](019-serialize-the-query-table.md)
- **Originating requirements:** PLAN: Earlier programs / portable complete
  semantic artifacts. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

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
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

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
  the previous revision's complete selected-specialization owner: exact checked
  Core per unit with type-node certificate bytes, namespace, evaluator snapshot,
  slots, field locations and completed receipts under claim
  `selected_complete_proof`. Decoding validates namespace, every Core graph,
  snapshot ordinal, slot and receipt, then rebuilds a Capture used only as the
  query predecessor of a compile without an in-process previous revision; the
  ordinary Gate, Importer and graph Plan admit every receipt against current
  source. Principal imports admit builtin State/Computation nominals. Owners
  with no namespace or no replayable receipt are omitted.
- Fixes found on the way: frozen Core validation rejected resolver
  continuations' `.local` parameters, so libraries with a monadic `do` could not
  be packed as dependency artifacts; an OOM in the backend's fresh query Gate
  left a partial non-null state that crashed at teardown; artifact encoding
  allocated roughly six times the encoded bytes and now uses one exact buffer.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 626 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 305 files at analyzer pin
  `756bfd5`. Native laws cover restart replay with fresh parity under an
  allocation-failure sweep, edited bodies/captures/recursion and a failing
  source, forged namespaces, graphs, certificates, values, closures, slots,
  receipts and field locations, a forged stamp that admits nothing, and owner
  omission. TS laws require selected replay after every example restart that
  records a receipt, pack and execute a monadic dependency artifact, and restart
  a dependency-loaded project with selected replay plus edited, failing and
  corrected revisions compared to fresh servers.
- Comparison: task-019 compiler (`69e8692e…`) versus candidate (`640c744d…`). 31
  alternating rounds over 18 workloads (3,348 CLI builds) give identical Wasm in
  every phase with equal principal/optimizer reuse; seven examples replay 1–3
  selected receipts after restart. Their checkpoints grow 177–338 KB, decode CPU
  rises from 66–252 to 552–1,114 µs, restart requested allocation 1.12–1.86 MB
  and restart median CPU 14–26% (1.2–3.4 ms). The other 11 workloads grow by 4
  bytes and allocate 4–135 KB less. No restart speedup is claimed.
- Remaining limitations: on small programs the owner costs more restart CPU than
  it saves; Core is validated at decode and again by the Gate. Executable
  fragments, retained principal evidence, layouts, templates, provider/request
  state, canonical plans and builtin effect operations remain declined and
  recompute. Large-program benefit is unmeasured without private gdev (tasks 002
  and 084).
- Durable record:
  [persisted semantic artifacts](../zig-native/SEMANTIC_ARTIFACTS.md),
  [restart distributions](../zig-native/qualification/semantic-artifacts-restart.csv),
  [decode distributions](../zig-native/qualification/semantic-artifacts-decode.csv)
  and [pins](../zig-native/qualification/semantic-artifacts-pins.json).
