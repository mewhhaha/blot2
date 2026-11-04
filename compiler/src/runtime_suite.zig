//! Independently compiled runtime laws.
comptime {
    _ = @import("backend/packed_layout.zig");
    _ = @import("backend/wasm.zig");
    _ = @import("backend/wasm_table_tests.zig");
    _ = @import("runtime/memory.zig");
    _ = @import("runtime/session_heap.zig");
    _ = @import("backend/runtime_ir.zig");
    _ = @import("runtime/shared_rc_tests.zig");
    _ = @import("runtime/cohort_runtime_tests.zig");
    _ = @import("runtime/task_context_tests.zig");
    _ = @import("runtime/data_stacks_tests.zig");
    _ = @import("runtime/list_runtime.zig");
}
