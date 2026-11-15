//! The module tests/direct/writer.goose builds, through compiler/src/direct/writer.zig.
//! tools/test_direct.py runs both and compares the bytes.
const std = @import("std");
const writer = @import("writer.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    var m = writer.Module.init(a);
    defer m.deinit();
    const unit = try m.signature(&.{}, &.{});
    const binary = try m.signature(&.{ .i32, .i32 }, &.{.i32});
    const again = try m.signature(&.{ .i32, .i32 }, &.{.i32});
    const mixed = try m.signature(&.{ .f32, .i32, .externref }, &.{ .f32, .i32 });
    std.debug.assert(again == binary);
    _ = try m.importFunction("host", "log", unit);
    _ = try m.importFunction("host", "pick", mixed);
    const first = try m.addFunction(binary);
    const second = try m.addFunction(unit);
    const third = try m.addFunction(mixed);
    try m.setBody(first, &.{ 0, 0x20, 0, 0x20, 1, 0x6a, 0x0b });
    try m.setBody(second, &.{ 0, 0x0b });
    try m.setBody(third, &.{ 1, 2, 0x7f, 0x20, 0, 0x41, 0xc0, 0xbb, 0x78, 0x0b });
    _ = try m.addGlobal(.i32, true, 65536);
    _ = try m.addGlobal(.f32, false, 0x3fc00000);
    _ = try m.addGlobal(.i32, false, 0xffffff80);
    try m.exportItem("add", .function, first);
    try m.exportItem("memory", .memory, 0);
    try m.exportItem("limit", .global, 0);
    _ = try m.tableSlot(first);
    _ = try m.tableSlot(third);
    m.host_slots = 3;
    m.memory_pages = 300;
    m.start = second;
    m.data_offset = 1024;
    try m.data.appendSlice(a, "blot data \x00\xff");
    try m.custom("blot:abi", &.{ 8, 0, 0, 0 });
    try m.names.put(a, first, "add");
    try m.names.put(a, third, "a much longer name that needs more than one hundred and twenty-seven bytes to spell so that its length takes two bytes in the map");
    const bytes = try m.assemble(a);
    defer a.free(bytes);
    var out_buffer: [16384]u8 = undefined;
    var out = std.Io.File.stdout().writerStreaming(init.io, &out_buffer);
    for (bytes) |b| try out.interface.print("{x:0>2}", .{b});
    try out.interface.print("\n", .{});
    try out.interface.flush();
}
