# 106 — Fit small guest objects and journal pages

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 16 October
  2026: `array.generate 4096 (fn index => #[128578, 97 + index % 26])` grew
  guest memory from 256 KiB at `86a527b` to 448 KiB at `2b2ffbb`.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Small guest objects and persistent-root journal pages no longer waste half of
their allocation class.

## Starting point

Bisect: `cb41a6d` grew the object header from 16 to 32 bytes by design
([SHARED_OWNERSHIP.md](../zig-native/SHARED_OWNERSHIP.md)); power-of-two classes
then move a 12-byte inner array from a 32- to a 64-byte block. `2798ff9` added
journal pages of 4096 payload bytes plus the header, which land in the 8192-byte
class; `2689ad5` narrowed slots to 8 bytes.

## Implementation checklist

- [x] Size journal pages so payload plus header fits the 4096-byte class
      (4064-byte payload, 507 slots), and derive slots per page from it
      (`zig-native/src/runtime/root_runtime.zig`).
- [x] Add 1.5x companion classes below 2 KiB (48, 96, 192, 384, 768 and 1536
      bytes) in the unused free-list heads 0–5, keeping 16-byte payload
      alignment and the static layout
      (`zig-native/src/runtime/arena_runtime.zig`).
- [x] Update runtime documentation that states the old classes.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` before the local milestone
commit. Measure the Ink workload at 1024, 2048, 4096 and 8192 elements before
and after.

## Acceptance criteria

- [x] The 4096-element workload commits less guest memory than 448 KiB, with a
      heap histogram explaining the change.
- [x] Every changed allocation-count or byte expectation is explained by the new
      classes.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Current local milestone: the commit containing this record; compiler and exact
  source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: The current 1,024/2,048/4,096/8,192-element measurements and
  allocation-class histograms pass; the 4,096-element case commits less than 448
  KiB.
- Remaining limits: The histogram includes retired/recycled dynamic blocks at
  return; committed pages, block traffic and live payload are distinct. Classes
  at or above 2 KiB and List leaf doubling retain their documented policies.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending.
- Validation: in the implementation worktree the native suite passed 2,355 laws
  with no leaks, guests passed 1,488 including two new class and journal laws,
  and lint reported zero findings; the combined gate is pending. Only
  `zig-native/tests/arena.test.ts` changed expectations: 128-byte payloads plus
  the 32-byte header now take 192-byte blocks instead of 256.
- Comparison: guest memory after `gen N` on a fresh guest, before → after: 1024:
  192 → 192 KiB, 2048: 256 → 256 KiB, 4096: 448 → 384 KiB, 8192: 832 → 640 KiB.
  The heap at 4096 drops from 360.1 to 260.0 KiB: inner arrays move from 64- to
  48-byte blocks and nine journal pages from 8192 to 4096 bytes.
- Remaining limitations: blocks of 2 KiB and more stay power-of-two, and list
  leaves keep doubling through power classes.
- Durable record: [SHARED_RC.md](../zig-native/SHARED_RC.md) and
  [PERSISTENT_ROOTS.md](../zig-native/PERSISTENT_ROOTS.md).
