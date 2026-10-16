# 078 — Split backend state and emission

## Status, dependencies, and originating requirements

- **Status:** In progress — implementation and focused checks are recorded;
  final common qualification remains required.
- **Dependencies:** [077](077-split-checker-responsibilities.md)
- **Originating requirements:** PLAN: Hill 14 / backend structure. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Separate backend planning, serialization, layouts and emission and split
remaining large compilation routines.

## Starting point

[core_backend.zig](../zig-native/src/backend/core_backend.zig) contains
`Generator`, `compileWithOptions`, `serialize` and emission state. Tasks 025–028
already establish the semantic boundary.

## Implementation checklist

- [x] Extract planning, static data serialization, layout and resolved
      instruction emission into cohesive owners.
- [x] Reduce oversized `Generator` state and long functions toward the
      approximately 120-line target.
- [x] Preserve resolved-body, optimizer, relocation and cleanup boundaries with
      explicit ownership and no forwarding-only layers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare complete Wasm, diagnostics, data layouts and code-instance counts
  across the full suite.
- Run serialization/relocation, ownership/OOM, dependency/checkpoint and
  failed-revision gates.
- Measure cold/retained CPU and allocation and document remaining justified size
  exceptions.

## Acceptance criteria

- [ ] Backend responsibilities and state owners are separated and large routines
      are substantially reduced.
- [ ] Code generation, cleanup, relocation and reuse remain equivalent.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

The four storage/work owners and the compilation-attempt owner are implemented.
Generator falls from 59 to 30 fields; `core_backend.zig` from 13,374 to 3,127
lines. The largest dispatch/ABI exceptions and their responsibilities are
recorded in [Backend ownership](../zig-native/BACKEND_OWNERSHIP.md).

Root qualification in `build/bench/finish-rest-20261015/backend-owners/` records
8 native laws with complete allocation failures, 38 guest groups, and exact
five-phase retained bytes, ordered diagnostics, work and archive payloads.
Ordinary Cost remains 12,902 bytes with the matched allocation record unchanged
(4,731,000 allocated bytes, 12,609 allocations, 1,162,755 peak, zero live).
These totals use Root's fixed paths; the private-agent path totals differ.

The first affected-closure analyzer run found an unchecked static-data range
endpoint. Root's bounded-slice amendment preserves the same output and
allocation behavior; the rerun passes all 429 affected files with zero findings.
The agent's earlier 17-file zero-finding statement was premature and is
corrected in the durable record. Failed logs and exact before/source pins are
retained.

Status remains in progress pending the final common release/full compiler gate
and matched CPU/performance qualification. No commit or push is authorized by
the continuation handoff.
