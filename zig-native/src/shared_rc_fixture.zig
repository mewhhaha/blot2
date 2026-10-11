//! Checked runtime operations; source admission is exercised separately.
const std = @import("std");
const wasm = @import("wasm.zig");
const gen = @import("runtime_code.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = wasm.Module.init(init.gpa);
    defer module.deinit();
    const arena = try module.ensureArena();
    const noop = try module.addFunction(&.{.i32}, .none);
    try module.exportFunction(noop, "noop", .u32, .u32);
    inline for (.{ "allocate_typed", "retain", "release", "release_lease", "store_word", "copy_words", "reset" }) |name|
        try module.exportFunction(@field(arena, name), name, .u32, .u32);
    const collect = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(collect, &.{ .{ .op = .local_get }, .{ .op = .global_get, .operand = arena.base }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.collect } });
    try module.exportFunction(collect, "collect", .u32, .u32);
    const chain = try module.addFunction(&.{.i32}, .i32);
    const c: gen.Code = .{ .module = &module, .function = chain };
    const index = try c.temp();
    const head = try c.temp();
    const next = try c.temp();
    try c.loop(.{ .i32_lt_u, index, gen.Local{ .id = 0 } });
    try c.set(next, .{ .call, arena.allocate_typed, 4, 1 });
    try c.value(.{ .call, arena.store_word, next, next, head });
    try c.when(head);
    try c.value(.{ .call, arena.release_lease, head });
    try c.end();
    try c.set(head, next);
    try c.set(index, .{ .i32_add, index, 1 });
    try c.again();
    try c.when(head);
    try c.value(.{ .call, arena.release_lease, head });
    try c.end();
    try c.value(.{ .global, arena.rc_leases });
    try module.exportFunction(chain, "chain", .u32, .u32);
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
