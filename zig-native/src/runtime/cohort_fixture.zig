//! Direct runtime protocol fixture; this does not assert Source admission.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const cohort = @import("cohort_runtime.zig");
const rc = @import("shared_rc.zig");
const cycles = @import("cycles_runtime.zig");

pub fn build(allocator: std.mem.Allocator) !wasm.Module {
    var m = wasm.Module.init(allocator);
    errdefer m.deinit();
    const a = try m.ensureArena();
    m.globals.items[a.root_enabled].bits = 1;
    m.globals.items[a.root_enabled].mutable = true;
    m.globals.items[a.rc_enabled].mutable = true;
    const runtime = try cohort.install(&m);
    // Source admission and prepared-body intersection are tested separately.
    try m.functions.items[a.retire].instructions.insertSlice(allocator, 0, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = runtime.retire_members } });
    for ([_]struct { id: u32, mask: u32 }{
        .{ .id = a.cycle_enqueue, .mask = rc.lease | rc.dead | cycles.no_cycle },
        .{ .id = a.cycle_visit, .mask = rc.lease | cycles.gray },
    }) |guard| {
        var found: usize = 0;
        for (m.functions.items[guard.id].instructions.items) |*inst| {
            if (inst.op != .i32_const or inst.operand != guard.mask) continue;
            inst.operand |= cohort.member | cohort.owner;
            found += 1;
        }
        if (found != 1) return error.UnrecognizedCycleGuard;
    }
    inline for (.{ "begin", "allocate", "retire_members" }) |name| try m.exportFunction(@field(runtime, name), name, .u32, .u32);
    inline for (.{ "root_allocate", "root_open", "root_close", "root_enter", "root_leave", "root_force", "root_authority", "retain", "release", "release_lease", "retire", "store_word", "cycle_collect", "cycle_safe", "reset" }) |name| try m.exportFunction(@field(a, name), name, .u32, .u32);
    inline for (.{ "root_enabled", "rc_enabled", "root_count", "root_page", "heap", "cycle_head", "cycle_passes", "cycle_vertices", "cycle_edges" }) |name| try m.exportGlobal(@field(a, name), name);
    return m;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var m = try build(init.gpa);
    defer m.deinit();
    const bytes = try m.assembleWithOptions(.{ .export_memory = true });
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
