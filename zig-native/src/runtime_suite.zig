//! Focused Wasm and storage laws. The production suite remains the complete gate.
comptime {
    _ = @import("memory.zig");
    _ = @import("runtime_ir.zig");
    _ = @import("wasm.zig");
    _ = @import("list_runtime.zig");
    _ = @import("shared_rc_tests.zig");
    _ = @import("packed_layout.zig");
}
