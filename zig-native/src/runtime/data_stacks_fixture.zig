//! Private runtime protocol exports for executed-Wasm memory laws.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const stacks = @import("data_stacks.zig");
pub fn build(a: std.mem.Allocator) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    const runtime = try stacks.emit(&module);
    try stacks.finishPlan(&module, runtime, .{ .region_capacities = &.{ 32768, 4096, 8192 }, .owner_capacity = 320 });
    // Private fixture hook makes carry and exhaustion executable without a soak.
    const seed = try module.addTypedFunction(&.{ .i32, .i32 }, .none, .scalar);
    const c: @import("../backend/runtime_code.zig").Code = .{ .module = &module, .function = seed };
    try c.value(@import("../backend/runtime_code.zig").Local{ .id = 0 });
    try c.op(.global_set, runtime.serial);
    try c.value(@import("../backend/runtime_code.zig").Local{ .id = 1 });
    try c.op(.global_set, runtime.serial_high);
    try module.exportFunction(seed, "seed_epoch", .u32, .u32);
    inline for (@typeInfo(stacks.Functions).@"struct".field_names) |name| try module.exportFunction(@field(runtime.functions, name), name, .u32, .u32);
    return module;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = try build(init.gpa);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
