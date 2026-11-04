const std = @import("std");
const wasm = @import("../backend/wasm.zig");
fn emit(allocator: std.mem.Allocator) !void {
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const owner = try module.addGlobal(.u32, 0, true);
    const functions = try @import("task_context.zig").emit(&module, owner);
    inline for (.{ "create", "save", "restore", "drop" }) |name|
        try module.exportFunction(@field(functions, name), name, .u32, .u32);
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > 8);
}
test "task context helper publication owns every failed compiler allocation" {
    try emit(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, emit, .{});
}
