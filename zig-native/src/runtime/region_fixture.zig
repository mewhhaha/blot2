//! Direct owner/interior publication protocol, without Source admission.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const region = @import("region_runtime.zig");
pub const plan: region.Plan = .{ .frame_bytes = 20, .bytes = 52, .mask = 4, .members = &.{ .{ .offset = 20, .bytes = 16, .demand = true }, .{ .offset = 36, .bytes = 8 }, .{ .offset = 44, .bytes = 8 } } };
pub fn build(a: std.mem.Allocator) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.root_enabled].bits = 1;
    module.globals.items[arena.root_enabled].mutable = true;
    module.globals.items[arena.rc_enabled].mutable = true;
    const runtime = try region.install(&module, plan);
    const body = try region.forcePop(a, &module, runtime);
    module.functions.items[arena.root_pop].locals.deinit(a);
    module.functions.items[arena.root_pop].instructions.deinit(a);
    module.functions.items[arena.root_pop].locals = body.locals;
    module.functions.items[arena.root_pop].instructions = body.instructions;
    const wait = try module.importFunction("test", "wait", &.{.i32}, .none);
    const suspended = try module.addTypedFunction(&.{}, .i32, .scalar);
    const parent = try module.addLocal(suspended, .i32);
    const memo = try module.addLocal(suspended, .i32);
    const code: @import("../backend/runtime_code.zig").Code = .{ .module = &module, .function = suspended };
    const Local = @import("../backend/runtime_code.zig").Local;
    try code.value(.{ .call, arena.root_open });
    try code.op(.drop, 0);
    try code.set(.{ .id = parent }, .{ .call, runtime.allocate });
    try code.set(.{ .id = memo }, .{ .i32_add, Local{ .id = parent }, 20 });
    try code.value(.{ .call, runtime.force, Local{ .id = memo }, Local{ .id = parent } });
    try code.store(Local{ .id = memo }, @offsetOf(@import("runtime_layout.zig").Demand, "status"), 1);
    try code.value(Local{ .id = parent });
    try code.op(.call_import, wait);
    try code.store(Local{ .id = memo }, @offsetOf(@import("runtime_layout.zig").Demand, "status"), 2);
    try code.value(.{ .call, arena.root_close, 0 });
    try code.value(0);
    try module.exportFunction(suspended, "suspend", .unit, .u32);
    inline for (.{ "allocate", "project", "store", "close", "force", "force_target" }) |name| try module.exportFunction(@field(runtime, name), name, .u32, .u32);
    inline for (.{ "root_allocate", "root_open", "root_close", "root_enter", "root_leave", "root_reserve", "root_pop", "root_store", "root_force", "retain", "release", "release_lease", "reset" }) |name| try module.exportFunction(@field(arena, name), name, .u32, .u32);
    inline for (.{ "root_enabled", "rc_enabled", "root_count", "root_active" }) |name| try module.exportGlobal(@field(arena, name), name);
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
