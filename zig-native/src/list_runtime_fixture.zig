//! Executable layout/sharing laws use the same emitted helpers as user programs.
const std = @import("std");
const wasm = @import("wasm.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = wasm.Module.init(init.gpa);
    defer module.deinit();
    const runtime = try module.ensureLists();
    module.public_arena = true;
    inline for (.{ "new", "address", "copy", "push", "set", "from_array", "to_array" }) |field|
        try module.exportFunction(@field(runtime, field), field, .u32, .u32);
    const lists = @import("list_runtime.zig");
    const static_chunk = try lists.staticChunk(&module, &.{123}, 0, false);
    const static_list = try lists.staticDescriptor(&module, 1, static_chunk, static_chunk);
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
