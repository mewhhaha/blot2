# 039 — Guarantee and explain demand lowering

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [038](038-eliminate-demands-through-known-callbacks.md),
  [033](033-own-suspended-effects-and-cancellation.md)
- **Originating requirements:** DEMANDS: Predictable cost guarantee,
  diagnostics, acceptance and measurements. Sources:
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Guarantee Boolean-shaped demand elimination across supported paths and expose
bounded source-span explanations and counters.

## Starting point

Direct bounded Boolean lowering and forwarding exist, but
[zig-native/DEMANDS.md](../zig-native/DEMANDS.md) still requires a cost
guarantee across aliases/imports/bundles, loop/callback coverage and
explanations.

## Implementation checklist

- [ ] Enforce branch lowering for fully applied statically resolved
      and/or-shaped bodies with known captures and proved local control,
      independent of source names.
- [ ] Apply it in debug/release, aliases, custom fixities, imports and compiled
      dependencies; analyze available retained bodies when summaries are absent.
- [ ] Report eliminated/direct/local-memo/stored with bounded spans/reasons and
      counters for allocations, memo slots, indirect calls, summary reuse and
      visited nodes.
- [ ] Keep unknown-control fallback documented and bound cloning/long-chain
      work.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare false conjunction/true disjunction and taken branches with explicit
  if: no demand cell, capture allocation, memo check or demand-specific indirect
  call.
- Run the complete demand acceptance matrix: repeats, loop scopes,
  rebinding/collections, providers, persistent aliases,
  cancellation/traps/recursion, unused ill-typed arguments and body-edit
  recovery.
- Benchmark chains of 1, 8, 64 and 256 operators, taken/skipped and in loops;
  separate guest cost from compiler time, size, allocation and summary work.

## Acceptance criteria

- [ ] The documented cost guarantee passes every build mode and
      source/dependency path without changing evaluation semantics.
- [ ] Explanations and structural counters are bounded and accurate; retained
      edits track bodies/evidence rather than just unchanged types.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
