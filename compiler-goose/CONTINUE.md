# Finish the Goose compiler experiment

Build the actual complete C/header/native compiler, then qualify CLI/server,
request OOM/retry and retention against Zig. **No whole compiler artifact exists.**
No forwarding to compiler/ and no ABI fallback.

Whole289 clears fixed conversion stacks. Whole290 clears the effect Handle
reader, then stops at partial expectation interning (`code_expectation:79`).
163.377s, unchanged 461 inputs, no artifacts. A grouped backend check reproduces
that frontier in 77.878s; use that bounded partial probe before another whole.

The emission index and infinite lookup fixes clear their backend frontiers.
Seven closed-local bindings now preserve borrowed module/body identity. Its native
law passes in 2.666s, covering lookup order, fallback/missing IDs, data shapes and
actual function dependencies. The wider loop-copy audit finds no other definite
matches. Backend 294 clears the family in 78.281s with unchanged source, then
stops at `owned_arrays.goose:103`: a nullable field needs a locally narrowed
reference. Audit that pattern before the next repair batch.

Physical Store now keeps scalar publication/effect authority instead of foreign
Core/effect views. Existing registries/pools supply invocation-local descriptors;
no payload copies/newpins. Core catalog identity and effect generation checked.
Retained children survive growth; reset with a live view rejects2.755s. Frame release
invalidates both keys. Six stable-array experiment removed afterclear failures;
original GS physicaltables retained. Two maps reuse existing Buckets.

Three hard-bounded stacks use fixed 128/128/16384 backing and scalar counts. Five
native laws pass 26.09s summed stages, including full bounds, overflow, nested
failure unwind and repeatedcanonical IDs. Earlier Run/startup/scanner/bridge
loans cleared by coherent source families. Native runner now seals immutable
receipts/rawlogs automatically; current full 45-law inventory still pending.

Private checker:build/goose-port/finite-root-diagnostics/goose. Parent finite
exact-global copiedcontents precision passes33lifetime/3runtime/24semantic
controls; metadata/traversal build repeats 33 lifetime/24 semantic controls.
Unknown/inexact/local/recursive/over-64-root paths remain conservative. Installed
Goose unchanged. Trace:GOOSE_OPTIONS_ROOT_TRACE=1. Repair120s/emission180s/
whole300s limits remain. No cap lifting or suppressed borrow checks.

Once actual executable exists, run tools/qualify_compiler.ts withit and
compiler/zig-out-native-fast/bin/blotc. Covers CLI/executedABI8, project lifecycle,
cold/retained OOM/retry,2warmup/6measured edit/restore revisions under16MiB RSS
growth. Allocator livebytes unavailable. Runnerstatic checks pass; actualGoose
runtime checks have notrun. No freshGdev/Main/frame orspeed/sizewin. Preserve
ABI8/session2, explicitowners/copies andsiblings. No environment publication.

See [root frontier](../CONTINUE.md), [receipt index](../benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json)
and [storage task](../tasks/STORAGE_REWRITE.md) forremaining requirements.
