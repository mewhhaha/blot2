# Host allocation adaptation

Writing only; no Goose compiler, runtime or allocation check has run.

The native `runtime/session_heap.zig` implements a Zig allocator vtable with
size-class free lists. Goose does not expose a replaceable allocator vtable or
untyped pointer casts. Its `reusable` and `reusable[]` typed pools replace that
implementation throughout the port; each compiler process owns its pools.
Numeric allocation-owner identities still bind captures and retained reuse.
Copied workers have separate process heaps and return owned packets.

This preserves typed allocation and reuse in the source model. It does not
establish the native heap's memory bound, class statistics, lock diagnostics or
physical allocation-failure behavior. `runtime/memory.goose` records supplied
allocation events, but whole-runtime observation is unavailable. The server
therefore emits null for `sessionHeap`; incomplete allocation counts emit null
with explicit coverage. No zero-work or successful fault sweep is fabricated.

The retained oracle keeps the full size-class implementation, deterministic
allocation-fault sweeps, profile helpers and benchmark/fixture executables.
These remain requirements and evidence for later runtime qualification. If
Goose pool retention or physical OOM differs materially, fix the selected Goose
runtime or explicit pool policy before claiming corresponding parity. Source
inventory completion alone cannot close this requirement.
