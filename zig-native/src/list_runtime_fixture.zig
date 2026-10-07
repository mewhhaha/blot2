//! Executable layout/sharing laws use the same emitted helpers as user programs.
const std = @import("std");
const wasm = @import("wasm.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = wasm.Module.init(init.gpa);
    defer module.deinit();
    const runtime = try module.ensureLists();
    module.public_arena = true;
    inline for (.{ "address", "copy", "push", "set", "to_array", "concat", "slice" }) |field|
        try module.exportFunction(@field(runtime, field), field, .u32, .u32);
    inline for (.{ "new", "from_array" }) |field| {
        const numeric = try module.addFunction(&.{.i32}, .i32);
        try module.emitSlice(numeric, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .call, .operand = @field(runtime, field) } });
        try module.exportFunction(numeric, field, .u32, .u32);
    }
    const references = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(references, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const }, .{ .op = .call, .operand = runtime.new } });
    try module.exportFunction(references, "new_references", .u32, .u32);
    const collect = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(collect, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .global_get, .operand = module.arena.?.base }, .{ .op = .i32_const }, .{ .op = .call, .operand = module.arena.?.collect } });
    try module.exportFunction(collect, "collect", .u32, .u32);
    const lists = @import("list_runtime.zig");
    const static_chunk = try lists.staticChunk(&module, &.{123});
    const static_list = try lists.staticDescriptor(&module, 1, &.{static_chunk});
    const static_function = try module.addFunction(&.{}, .i32);
    try module.emit(static_function, .{ .op = .i32_const, .operand = static_list });
    try module.exportFunction(static_function, "static", .unit, .u32);
    const heap = try module.addFunction(&.{}, .i32);
    try module.emit(heap, .{ .op = .global_get, .operand = module.arena.?.heap });
    try module.exportFunction(heap, "heap", .unit, .u32);
    const bytes = try module.assemble();
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
