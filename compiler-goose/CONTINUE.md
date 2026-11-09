# Finish the Goose compiler experiment

The writing-first phase is over. Current work is to fix production lifetime
failures in coherent families, produce the complete native compiler, then
qualify CLI/project-server behavior and recoverable request OOM against Zig.
Run bounded batch checks at family boundaries rather than per-edit fixtures.
Never count source presence or a selected-root check as whole-port completion.

Keep `compiler/` and its installed binaries as the oracle. `oracle.json` pins
Zig commit `156f84b4810f630dff7e5efb7014b2194e3160f7`; the executable copy and
identity are in ignored `build/goose-port/oracle/`. New-language comparisons
must use the corresponding newer Zig candidate and pinned source inputs.
Preserve sibling checkouts and installed Goose toolchains.

Use the tracked private checker recipe. The newer selfhost Goose snapshot is
not a qualified replacement for this port's packages, reusable pools and native
host APIs. Selected-root diagnostics are partial. Normal whole builds emit C
and a host header, then compile and link the real Goose CLI with native OS
adapters. Repair stages cap at 120s; final emission may use 180s after engine checks.
Whole attempts share a 300s limit.

Fourteen isolated engine families pass together, including body-freeze ownership,
live/frozen readers, import-arena growth and SourceValidation publication.
Source/Patterns use existing lease keys with 49/2 validation guards. Cursors
replace held type/AST spans. The import dictionary holds scalar indices into a
separate stable arena, preserving first-wins and synthetic import order.
Frozen descriptors carry fixed metadata; proof headers use value Options and
retain the same five owned readonly payloads. The production publisher law
checks all payload identities after local producer headers end. Append-only
import/catalog inputs use grow-only arrays across three callers.

SourceValidation publishes 19 registered views without additional allocations.
Editor budget accounting now uses the existing explicit Budget reference; its
executed law covers exhaustion and rejected initializers. All five worker entry
paths pass one partial batch. The server now has its own diagnostic root;
NativeAssets aggregate metadata copying is removed in favor of scalar indices;
checked text publication and actual prepare/error/reuse laws pass. The current
server frontier is completion_probe.capture input/scratch borrowing (line21).
Final Sources publication has a worst-case quadratic ownership scan; pending
optimization requires a measured workload. The frame reader uses
append-only high-water growth; its actual 4097-byte/1-byte law passes.
The actual whole build caps at 120.271s without C or a diagnostic. No complete
executable exists; CLI/server and OOM qualification remain pending.

Keep mini laws for owned boundary families: body_freeze runs in about 5–7s,
immutable_readers 3.9s, import_arena 3.5s and source_validation_ownership 3.8s. The frozen dictionary experiments
and shrink-origin witness show why metadata must stay outside the growing map.

The optional bounded reference-closure cache/trace checker reaches a concrete
whole-build source error in 95.491s where the baseline caps at 120.262s on the
same production source except generated identity metadata. This is a shorter
diagnostic cycle, not a completed compile or overall speed ratio. Its pinned
semantic, debug/release and C parity controls pass. Use the tracked recipe;
installed toolchains remain untouched. The holder index reaches the identical
source error in 82.445s versus 104.824s in one exact-input pair. The optional
UsedAfter frame skip passes 147 laws per debug/release mode, 24 semantic controls
and six C parity cases; macro impact remains unqualified. Root CONTINUE.md links
current evidence.

Native request rollback and runtime observation components are tested; their
whole compiler integration remains unqualified. A
committed worker forks a candidate before reading each request; only a complete
staged reply can adopt it. Explicit allocation failures discard the candidate
and retain the committed heap. Generic panics and signals are not OOM. A dedicated token-bound stage-worker
capability now covers native initialization/execution/cleanup refusals; normal
and sanitizer controls pass, while whole compiler integration remains pending. Coverage
must distinguish observed pool operations, reserved capacity and RSS; unavailable
live/scratch counts must stay explicitly unavailable.

Retained contexts now use canonical typed metadata and fixed pooled buffers.
Lexical contexts may borrow caller-owned tables. Arrays cannot
become multiple owning fields in one Goose record. Backend Function/Signature
records use ranges into Module tables. Owner identities are fresh process-local
u64 values, not pointer casts; zero declines optional cache authority. Marks,
rollback, source checking and private proof ownership remain distinct.

`support/error.goose` owns explicit trailing Error results and original wire
error names. `support/option.goose` contains only fixed optional values. Native
adapters supply scalar bit representations, OS byte I/O, clocks and atomics;
they do not compile or interpret Blot or Zig.

The local Goose specification is in
`../goose-to-wasm/build/source/docs/goose_spec.md`; the live sibling is under
independent development. Its current bootstrap has gaps around native threads,
encoded references, recoverable allocation and source-package imports. Preserve
the requested source contracts and record gaps; choose and qualify the Goose
toolchain after writing. Do not work around gaps by weakening Blot checks,
forwarding compilation to Zig, or inserting placeholder successes.
