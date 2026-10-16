//! Isolated ABI fixture for suspended task root ownership, not source admission.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = wasm.Module.init(init.gpa);
    defer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.root_enabled].bits = 1;
    module.globals.items[arena.root_enabled].mutable = true;
    module.globals.items[arena.rc_enabled].mutable = true;
    const cancelled = try module.addGlobal(.u32, 0, true);
    const functions = try @import("task_context.zig").emit(&module, cancelled);
    const suspension = try module.importFunction("tasks:fixture", "host", &.{.i32}, .i32);
    const checkpoint = try module.importFunction("tasks:fixture", "checkpoint", &.{.i32}, .i32);
    const run = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const runtime = @import("../backend/runtime_code.zig");
    const c: runtime.Code = .{ .module = &module, .function = run };
    const owner = try c.temp();
    const result = try c.temp();
    try c.set(owner, .{ .call, arena.root_allocate, 4, 0 });
    try c.value(.{ .call, arena.store_word, owner, owner, 42 });
    try c.value(runtime.Local{ .id = 0 });
    try c.op(.call_import, suspension);
    try c.op(.local_set, result.id);
    // A resumed Wasm frame installs its saved owner before any cancellation
    // check or source operation. Promise reaction order is never authority.
    try c.value(.{ .call, functions.restore, runtime.Local{ .id = 0 } });
    try c.op(.drop, 0);
    try c.value(runtime.Local{ .id = 0 });
    try c.op(.call_import, checkpoint);
    try c.op(.drop, 0);
    try c.trap(.{ .i32_ne, .{ .load, owner, 0 }, 42 });
    try c.value(result);
    try module.exportFunction(run, "run", .u32, .u32);
    inline for (.{ "create", "save", "restore", "drop" }) |name|
        try module.exportFunction(@field(functions, name), name, .u32, .u32);
    inline for (.{ "root_enter", "root_leave", "root_allocate", "root_force", "store_word", "retain", "release_lease", "cycle_safe" }) |name|
        try module.exportFunction(@field(arena, name), name, .u32, .u32);
    inline for (.{ "rc_enabled", "root_enabled", "root_count", "root_active", "root_frame", "root_page", "root_top", "heap" }) |name|
        try module.exportGlobal(@field(arena, name), name);
    try module.exportGlobal(cancelled, "cancelled");
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
