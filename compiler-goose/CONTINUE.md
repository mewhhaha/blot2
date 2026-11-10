# Finish the Goose compiler experiment

Build the actual complete C/header/native compiler, then qualify CLI/server,
request OOM/retry and retention against Zig. **No whole compiler artifact exists.**
No forwarding to compiler/ and no ABI fallback.

Whole 290 is the latest complete build attempt: 163.377s, unchanged 461 inputs,
no artifact. Grouped backend repairs take about 75–78s and remain partial,
check-only. Backend 295 clears the array walker/nullable-field family, then stops
at backend_representations38 projected-state bridge binding (77.441s, unchanged).
Production callers should use existing compile_workspace.bridgeForGenerator;
generic representations API remains for lexical contexts.

Actual captured-borrow law passes in 2.848s: recursive invocation parameters carry
the original borrow engine without storing it in local walkers; shared caches and
captured-read updates pass. No new pools/registries. Three nullable artifact hooks
also fixed. Shape/index/closed-local native receipts are in the root index.
Whole build and actual CLI/server/OOM/retry/retention remain pending.

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
receipts/rawlogs automatically; current full 46-law inventory still pending.

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
