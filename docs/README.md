# Documentation map

Start with [CONTINUE.md](../CONTINUE.md), [AGENTS.md](../AGENTS.md) and the
[owned-storage tasks](../tasks/STORAGE_REWRITE.md). This greenfield rewrite
removes superseded implementations and APIs; breaking changes are welcome.

Current contracts are in the [language guide](../compiler/guide.md),
[scoped storage](../zig-native/SCOPED_STORAGE.md),
[rewrite review](../zig-native/STORAGE_REWRITE_REVIEW.md) and
[guest ABI](../compiler/guest-abi.md). Some reference sections still need
migration verification; the active handoff records what has actually executed.

Older cumulative plans, checkpoint diaries and compiler work logs have been
removed from the working tree. Their surviving evidence links use the exact
[pre-cleanup Git revision](https://github.com/mewhhaha/blot2/tree/e2fbe95b4ece3e2d4fd442d95274bb6156815705).
Historical results do not qualify the owned-storage candidate. Dedicated
qualification reports, source tests and current handoff evidence remain in
place.
