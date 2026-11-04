const std = @import("std");
const w = @import("../backend/wasm.zig");
const cohort = @import("cohort_runtime.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    var m = w.Module.init(allocator);
    defer m.deinit();
    const a = try m.ensureArena();
    const count = m.functions.items.len;
    const before = try allocator.dupe(w.Instruction, m.functions.items[a.retire].instructions.items);
    defer allocator.free(before);
    try std.testing.expect(m.cohorts == null);
    const runtime = try cohort.install(&m);
    try std.testing.expectEqual(count + 3, m.functions.items.len);
    try std.testing.expectEqualDeep(runtime, try cohort.install(&m));
    try std.testing.expectEqual(count + 3, m.functions.items.len);
    try std.testing.expectEqualSlices(w.Instruction, before, m.functions.items[a.retire].instructions.items);
    inline for (.{ "begin", "allocate", "retire_members" }) |name| try std.testing.expect(m.runtimeHelper(@field(runtime, name)));
}
test "activation cohort installation is late idempotent and leaves ordinary runtime bodies unchanged" {
    try scenario(std.testing.allocator);
}
test "activation cohort installation releases every allocation on OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}

fn fixtureScenario(allocator: std.mem.Allocator) !void {
    var m = try @import("cohort_fixture.zig").build(allocator);
    defer m.deinit();
    const a = m.arena.?;
    try std.testing.expectEqual(m.cohorts.?.retire_members, m.functions.items[a.retire].instructions.items[1].operand);
}
test "activation cohort fixture patches both collector guards and releases every allocation on OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, fixtureScenario, .{});
}
