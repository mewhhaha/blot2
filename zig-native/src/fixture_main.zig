//! Runtime fixture programs share the compiler module root for cross-area imports.
pub const main = switch (@import("fixture_options").kind) {
    .arena => @import("runtime/arena_fixture.zig").main,
    .shared_rc => @import("runtime/shared_rc_fixture.zig").main,
    .cohort => @import("runtime/cohort_fixture.zig").main,
    .list => @import("runtime/list_runtime_fixture.zig").main,
    .resource => @import("runtime/resource_retire_fixture.zig").main,
    .region => @import("runtime/region_fixture.zig").main,
    .task_context => @import("runtime/task_context_fixture.zig").main,
    .packed_layout => @import("runtime/packed_layout_fixture.zig").main,
    .data_stacks => @import("runtime/data_stacks_fixture.zig").main,
};
