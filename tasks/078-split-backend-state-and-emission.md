# 078 — Split backend state and emission

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** [077](077-split-checker-responsibilities.md)
- **Originating requirements:** PLAN: Hill 14 / backend structure. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

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
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Compare complete Wasm, diagnostics, data layouts and code-instance counts
  across the full suite.
- Run serialization/relocation, ownership/OOM, dependency/checkpoint and
  failed-revision gates.
- Measure cold/retained CPU and allocation and document remaining justified size
  exceptions.

## Acceptance criteria

- [x] Backend responsibilities and state owners are separated and large routines
      are substantially reduced.
- [x] Code generation, cleanup, relocation and reuse remain equivalent.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Current local milestone: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`; compiler
  and exact source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: Backend planning, static data, representation and emission owners
  pass current native/OOM, guest, relocation and retained/restart gates.
- Remaining limits: Compilation entry wrappers are not counted as substantive
  routine reductions. Recorded larger dispatch/ABI exceptions remain explicit.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending; the continuation handoff authorizes no commit or push.
- Implementation: the four storage/work owners and the compilation-attempt owner
  exist. Generator falls from 59 to 30 fields and `core_backend.zig` from 13,374
  to 3,127 lines; the largest remaining dispatch/ABI exceptions are recorded
  with their responsibilities.
- Validation: Root's qualification passes 8 native laws with complete allocation
  failures and 38 guest groups. After Root's bounded-slice amendment for an
  unchecked static-data range endpoint (same output and allocation), the
  affected-closure analyzer passes all 429 files with zero findings; an earlier
  17-file zero-finding claim was premature and is corrected in the durable
  record.
- Comparison: five-phase retained bytes, ordered diagnostics, work and archive
  payloads are exact. Ordinary Cost remains 12,902 bytes with its matched
  allocation record unchanged (4,731,000 allocated bytes, 12,609 allocations,
  1,162,755 peak, zero live) on Root's fixed paths; private-agent path totals
  differ. Pins and failed logs:
  `build/bench/finish-rest-20261015/backend-owners/`.
- Remaining limitations: the final common release/full compiler gate and matched
  CPU/performance qualification keep the task in progress.
- Durable record: [Backend ownership](../zig-native/BACKEND_OWNERSHIP.md).
