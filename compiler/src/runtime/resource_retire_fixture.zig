//! Isolated owning-token retirement laws, without source acquisition lowering.
const std = @import("std");
const w = @import("../backend/wasm.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = w.Module.init(init.gpa);
    defer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.rc_enabled].mutable = true;
    module.globals.items[arena.rc_enabled].bits = 1;
    _ = try module.importFunction("blot:resource/2", "retire", &.{.i32}, .none);
    module.globals.items[arena.root_enabled].mutable = true;
    try module.exportGlobal(arena.root_enabled, "ownership_mode");
    inline for (.{ "root_allocate", "root_enter", "root_leave", "root_open", "root_close", "root_reserve", "root_store", "decrement" }) |name|
        try module.exportFunction(@field(arena, name), name, .u32, .u32);
    inline for (.{ "allocate_typed", "retain", "release", "release_lease", "store_word", "cycle_collect", "cycle_safe" }) |name|
        try module.exportFunction(@field(arena, name), name, .u32, .u32);
    try module.exportGlobal(arena.rc_enabled, "allocator_mode");
    try module.exportGlobal(arena.heap, "heap");
    try module.exportGlobal(arena.cycle_head, "cycle_head");
    try module.exportGlobal(arena.cycle_members, "cycle_members");
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
