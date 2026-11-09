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

Seventeen executed production families pass together, including complete native
asset preparation/error ownership, completion snapshots, loader/parallel
scheduling and editor lifetime controls. Their exact inputs and binary identities
are pinned in the root completion evidence; none is whole-port qualification.

Project checker engines and shallow workers are invocation-local values.
Synchronous callback contexts borrow the local engine; caller-owned compiled
module/mask views and execution observers remain borrowed. The old engine
registry and editor-prefix copy/writeback machinery are removed. Worker requests
own Option<Engine> and destroy it before source/packet ownership. No project
graphs are cloned to solve invocation lifetimes.

Source/Patterns retain 49/2 alias guards, frozen proof headers are values, import
maps hold scalar arena indices, and SourceValidation owns 19 registered views.
Loader and scheduler scratch use existing fixed pooled headers. NativeAssets
sorts scalar indices instead of aggregate metadata; generated error codes remain
owned after generator cleanup. Final Sources publication still has a worst-case
quadratic owner lookup, pending a measured optimization.

Source/semantic diagnostics and CheckedProject/Prepared headers publish exact
owned views. Parallel lowering owns its fixed slot run; fixed-mode result payloads
are reconstructed after mutation. Snapshot owned-header factories preserve
existing owner journals and shared/pin lifetimes. All 17 executed families pass;
the current combined entry check is pending after explicit generic annotations.
No whole C/header/executable exists; CLI/server/OOM qualification remains pending.
Repair stages cap at 120s; final emission may use 180s after entry checks, sharing
the 300s whole-build limit. Source-only manifest metadata remains unqualified;
the actual builder regenerates identity before emission.

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
