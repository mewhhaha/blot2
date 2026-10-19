# Core owners

`src/check/core.zig` owns the immutable module representation, table readers and
module destruction. IDs, spans and physical table order are unchanged by the
builder split. Its `lower` entry aliases remain available to existing readers.
Production construction paths import `src/check/core_builder.zig` directly.

The private builder has four fields: allocator, borrowed Source inputs,
published Tables and temporary Scratch. Source holds the tree, symbol pool,
checked module and diagnostic-origin callback only for the lowering call.
Scratch owns remapping buffers, capture epochs and temporary callback frames;
none of it enters the published module.

Tables owns every construction buffer that can enter a module. Its finish
operation drains them in the established order, normalizes feature flags and
remaps dictionary introductions before returning the module. An error destroys
the partially published module while the builder destroys undrained buffers.
Capability contracts are selected last under a second publication guard.
Successful lowering also captures declaration dependencies before source owners
end. Every returned module must eventually be deinitialized by its owner.

Focused split qualification compares exact Wasm for fresh, literal edit, revert,
failed-edit repair and restart, exact language diagnostics, and exact serialized
dependency payloads. The compiler provenance key changes because compiler source
changed. Existing lowering, freeze, clone and complete failed allocation laws
check the ownership boundary. The combined compiler/lint gate and prerequisite
qualification remain necessary before a milestone commit.

The [19 October cloud gate](CLOUD_QUALIFICATION.md) supplies the current common
native, guest, release and packaging checks. The earlier matched split
comparison above remains historical evidence for the ownership extraction.
