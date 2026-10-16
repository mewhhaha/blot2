# 093 — Close the gdev edit gap

## Status, dependencies, and originating requirements

- **Status:** In progress — milestone `aef65e7`; no completion is claimed.
- **Dependencies:** [088](088-restore-summary-job-inference-cost.md)
- **Originating requirements:** discovered while qualifying task
  [088](088-restore-summary-job-inference-cost.md), whose outcome asked for
  retained-edit inference back at the cost before call-summary jobs; PLAN: Hill
  6 / cheap edits. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Retained literal edits on gdev cost no more than at `f7be6e7`, before
call-summary jobs, while keeping the later reuse and summary benefits.

## Starting point

After task 088 (`86db5b1`), a retained scalar literal edit on the frozen gdev
copy costs about 570 ms CPU against 400 ms at `f7be6e7`, at load 2–3 (see
[summary-job cost](../zig-native/CALL_SUMMARIES.md#summary-job-cost-11-october-2026)).
Inference is 240 versus 199 ms with 1,034 versus 433 regions per edit; the
residual regions were not attributed. The backend's lookup (+46 ms), capture
(+21 ms) and prepare (+25 ms) timers grew alongside reuse that regenerates 102
instead of 264 functions. Principal regions that consume non-source-complete
graphs, or jobs finished outside their recording, still drop their input keys.

## Progress

Milestone `aef65e7` cuts gdev retained edits from 570 to 440 ms (`f7be6e7`: 400
ms) by indexing old signatures, matching retained values through a reused
scratch, and giving dependency certificates their own budget so gdev keeps them.
See [retained edit cost](../zig-native/RETAINED_EDIT_COST.md). Remaining: about
39 ms of module-stamp integrity checks (a design decision), 26 ms of extra
constant evaluation (task 086's area) and about 27 ms in fragment lookup,
assembly and journal freezing.

The 13 October isolated collection-length path removes 220 inference regions and
170,960 scopes per captured revision. LLVM/Fast seven-pair edit CPU falls
1232.855→961.714 ms, with exact Wasm and source fuel; fresh/revert CPU also
falls. The optimizer invalidation worklist separately restores 2,862/2,864
retained body matches. Combined `ae001bb` passes the full gate; seven pairs
measure edit 1247.822→906.212 ms and revert 1147.918→813.715 ms against
`38e822d`, with exact Wasm and source fuel. These current-snapshot improvements
do not establish the historical target or complete task 093. See
[collection shape members](../zig-native/COLLECTION_SHAPE_MEMBERS.md) and
[retained assembly](../zig-native/RETAINED_ASSEMBLY_WORKLIST.md).

The 30 ms literal-edit target in the final gates is owned by task
[101](101-reach-the-literal-edit-target.md); finishing this task does not meet
it.

## Implementation checklist

- [x] Attribute the residual inference regions and the lookup, capture and
      prepare growth with deterministic counters and a profile.
- [ ] Remove the costs that do not pay for themselves on gdev, keeping equal
      judgments, diagnostics and fresh/retained byte equality.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Pair gdev retained edits and cold builds against `f7be6e7` and the current
  compiler; run the synthetic corpus and the public examples.

## Acceptance criteria

- [ ] gdev retained edits reach the `f7be6e7` cost, or each remaining cost is
      attributed and justified explicitly.
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
