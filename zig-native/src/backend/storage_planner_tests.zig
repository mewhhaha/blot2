const std = @import("std");
const project = @import("../reuse/project.zig");
const checker = @import("../reuse/project_check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;
const io = std.testing.io;

fn publish(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) !void {
    var result = try scoped.compile(allocator, units, entry);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("PLANNER_FIXTURE_EMIT {any}\n", .{diagnostic});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "planner callbacks keep module local obligations through nested closure bodies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "" });
    try tmp.dir.writeFile(io, .{
        .sub_path = "helper.blot",
        .data = "const any = func predicate -> (values: Array a) => return do:\n" ++
            "  for value in values:\n    if predicate value:\n      return true\n  return false\n" ++
            "const nested = func (rows: Array item) -> values => return\n" ++
            "  any (func row => return any (func value => return @u32.eq row.value value) values) rows\n",
    });
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "import * as helper from \"./helper\"\n");
    try source.appendSlice(a, "type Meter is data = $Meter U32\n" ++
        "const Meter.amount = func ($Meter value) => return value\n" ++
        "const read = func (context: {");
    for (0..80) |index| {
        const field = try std.fmt.allocPrint(a, "a{d}: t{d},", .{ index, index });
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "zrows: rows, zvalues: values, zmeter: meter}) => return if @u32.eq context.zmeter.amount 0 then false else helper.nested context.zrows context.zvalues\n" ++
        "entry const answer = func (input: U32) => return do:\n" ++
        "  let marker: ResizeArray U32 = #[input]\n" ++
        "  let rows: Array {value: U32} = #[{value: marker[0]}]\n" ++
        "  return read {");
    for (0..80) |index| {
        const field = try std.fmt.allocPrint(a, "a{d}: input,", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "zrows: rows, zvalues: #[1], zmeter: $Meter 1}\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "main.blot", .data = source.items });
    const path = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const prelude_path = try tmp.dir.realPathFileAlloc(io, "prelude.blot", a);
    defer a.free(prelude_path);
    var loaded = try project.load(a, io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try checker.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try a.alloc(core.Module, loaded.units.items.len);
    var initialized: usize = 0;
    defer {
        for (units[0..initialized]) |*unit| unit.deinit(a);
        a.free(units);
    }
    var helper_types: usize = 0;
    var caller_field_type: u32 = 0;
    for (units, 1..) |*unit, id| {
        const input = loaded.unit(@intCast(id));
        unit.* = try core.lower(a, &input.tree, &loaded.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
        try std.testing.expectEqual(@as(usize, 0), unit.diagnostics.len);
        if (std.mem.endsWith(u8, loaded.filename(@intCast(id)), "helper.blot")) helper_types = unit.types.nodes.len;
        if (unit.unit == loaded.entry) for (unit.bodies) |body| {
            if (!std.mem.eql(u8, unit.name(body.declaration_name), "read")) continue;
            for (unit.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]) |goal| {
                if (goal.kind == .field) caller_field_type = @max(caller_field_type, goal.ty);
            }
        };
    }
    // Capturing this caller obligation into the helper would address beyond
    // that module's complete type table, even when numeric layouts coincide.
    if (caller_field_type < helper_types) std.debug.print("PLANNER_FIXTURE goal={d} helper_types={d}\n", .{ caller_field_type, helper_types });
    try std.testing.expect(caller_field_type >= helper_types);
    try publish(a, units, loaded.entry);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{ @as([]const core.Module, units), loaded.entry });
}
