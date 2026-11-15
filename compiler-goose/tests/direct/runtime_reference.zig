//! The modules tests/direct/runtime.goose builds, through compiler/src/direct/runtime.zig.
//! tools/test_direct.py runs both and compares the text.
const std = @import("std");
const writer = @import("writer.zig");
const runtime = @import("runtime.zig");

fn show(a: std.mem.Allocator, out: *std.Io.Writer, budgets: runtime.Budgets, shifted: bool) !void {
    var m = writer.Module.init(a);
    defer m.deinit();
    if (shifted) {
        const unit = try m.signature(&.{}, &.{});
        _ = try m.importFunction("host", "log", unit);
        _ = try m.addGlobal(.f32, false, 0x3fc00000);
    }
    const r = try runtime.emit(a, &m, budgets);
    const l = r.layout;
    try out.print("layout ", .{});
    for ([_]u32{ l.free_lists, l.owner_table, l.owner_capacity, l.persistent_base, l.persistent_end, l.stack_base, l.stack_end, l.heap_base, l.heap_end, l.transport_base, l.transport_end, l.total }) |value| try out.print("{d} ", .{value});
    try out.print("\nruntime ", .{});
    for ([_]u32{ r.owner_top, r.persistent_bottom, r.stack_pointer, r.heap_top, r.persistent_top, r.transport_top, r.effect_context, r.open, r.open_persistent, r.release, r.check, r.stack, r.heap_alloc, r.heap_free, r.address, r.length, r.push, r.pop, r.truncate, r.freeze, r.create, r.copy, r.persist, r.allocate, r.reset, r.packet_length }) |value| try out.print("{d} ", .{value});
    try out.print("\n", .{});
    const bytes = try m.assemble(a);
    defer a.free(bytes);
    for (bytes) |b| try out.print("{x:0>2}", .{b});
    try out.print("\n", .{});
}

pub fn main(init: std.process.Init) !void {
    var out_buffer: [16384]u8 = undefined;
    var out = std.Io.File.stdout().writerStreaming(init.io, &out_buffer);
    try show(init.gpa, &out.interface, .{}, false);
    try show(init.gpa, &out.interface, .{ .owners = 1024, .persistent = 65536, .stack = 131072, .heap = 262144, .transport = 4096 }, true);
    try out.interface.flush();
}
