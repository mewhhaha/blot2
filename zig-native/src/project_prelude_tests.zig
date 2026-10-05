const std = @import("std");
const project = @import("project.zig");
const semantic = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const check = @import("check.zig");
const a = std.testing.allocator;

fn write(dir: std.Io.Dir, file: []const u8, bytes: []const u8) !void {
    try dir.writeFile(std.testing.io, .{ .sub_path = file, .data = bytes });
}
fn path(dir: std.Io.Dir, file: []const u8) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(std.testing.io, &buffer);
    return std.fs.path.join(a, &.{ buffer[0..len], file });
}
fn valid(loaded: *const project.Project, checked: *const semantic.CheckedProject) !void {
    for (loaded.diagnostics.items) |item| std.debug.print("prelude source {d}: {s}\n", .{ item.unit, item.message() });
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    for (checked.diagnostics) |item| std.debug.print("prelude check {d}: {s}\n", .{ item.unit, item.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
const prelude_source =
    \\infixr 90 (++) = add
    \\type Maybe a is data = #Some a | #Nothing
    \\const add = fn left => fn right => @type.call "add" left right
    \\const U32.add = fn left => fn right => @u32.add left right
    \\const F32.add = fn left => fn right => @f32.add left right
    \\const identity = fn value => value
;
const entry_source =
    \\import { answer } from "./helper"
    \\entry const integer = fn () -> U32 => identity (20 ++ answer)
    \\entry const floating = fn () -> F32 => 1.5 ++ 2.5
    \\const maybe: Maybe U32 = #Some 42
;

test "implicit prelude is a real producer shared by modules and syntax fixities" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude_source);
    try write(tmp.dir, "main.blot", entry_source);
    try write(tmp.dir, "helper.blot", "const answer = identity 22\n");
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    var loaded = try project.load(a, std.testing.io, entry, .{ .prelude_path = prelude });
    defer loaded.deinit(a);
    var checked = try semantic.checkProject(a, &loaded);
    defer checked.deinit(a);
    try valid(&loaded, &checked);
    try std.testing.expectEqual(@as(usize, 3), loaded.units.items.len);
    try std.testing.expectEqual(@as(project.UnitId, 1), loaded.prelude_unit);
    try std.testing.expectEqual(@as(project.UnitId, 2), loaded.entry);
    try std.testing.expectEqualSlices(project.UnitId, &.{ 1, 3, 2 }, loaded.order.items);
    try std.testing.expect(!loaded.unit(loaded.prelude_unit).implicit_prelude);
    try std.testing.expect(loaded.unit(loaded.entry).implicit_prelude);
    const consumer = &checked.module(loaded.entry).checked;
    var imported_identity: ?check.ExternalTarget = null;
    for (consumer.bindings) |binding| if (std.mem.eql(u8, loaded.symbols.get(binding.name), "identity") and binding.kind == .external) {
        imported_identity = binding.external;
    };
    try std.testing.expectEqual(loaded.prelude_unit, imported_identity.?.unit);
    const prelude_semantics = &checked.module(loaded.prelude_unit).checked;
    try std.testing.expectEqual(@as(usize, 2), prelude_semantics.associated.len);
    try std.testing.expectEqual(@as(usize, 2), consumer.associated.len);
    for (consumer.associated) |method| try std.testing.expectEqual(loaded.prelude_unit, consumer.bindings[method.binding].external.?.unit);
    const tree = &loaded.unit(loaded.entry).tree;
    const floating = tree.node(tree.valueDecl(tree.roots.items[2]).body);
    try std.testing.expectEqual(@import("ast.zig").Tag.binary, tree.node(floating.b).tag);
}

test "source fixities and lexical names shadow ordinary prelude exports" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude_source);
    try write(tmp.dir, "main.blot",
        \\infixl 90 (++) = subtract
        \\const identity = fn value => value
        \\const subtract = fn left => fn right => @u32.sub left right
        \\entry const answer = fn () -> U32 => identity (44 ++ 2)
    );
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    var loaded = try project.load(a, std.testing.io, entry, .{ .prelude_path = prelude });
    defer loaded.deinit(a);
    var checked = try semantic.checkProject(a, &loaded);
    defer checked.deinit(a);
    try valid(&loaded, &checked);
    const consumer = &checked.module(loaded.entry).checked;
    var count: usize = 0;
    for (consumer.bindings) |binding| if (std.mem.eql(u8, loaded.symbols.get(binding.name), "identity")) {
        count += 1;
        try std.testing.expectEqual(check.Kind.global, binding.kind);
    };
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "prelude dependency closure bootstraps once and failed declarations remain visible" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "seed.blot", "const seed = 40\n");
    try write(tmp.dir, "prelude.blot", "import { seed } from \"./seed\"\nconst value = seed\n");
    try write(tmp.dir, "main.blot", "entry const answer = @u32.add value 2\n");
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    var loaded = try project.load(a, std.testing.io, entry, .{ .prelude_path = prelude });
    defer loaded.deinit(a);
    var checked = try semantic.checkProject(a, &loaded);
    defer checked.deinit(a);
    try valid(&loaded, &checked);
    try std.testing.expectEqualSlices(project.UnitId, &.{ 2, 1, 3 }, loaded.order.items);
    try std.testing.expect(!loaded.unit(2).implicit_prelude);
    try std.testing.expectEqual(@as(usize, 3), checked.body_elaborations);
    var absent = try project.load(a, std.testing.io, entry, .{});
    defer absent.deinit(a);
    var without = try semantic.checkProject(a, &absent);
    defer without.deinit(a);
    try std.testing.expectEqual(@as(project.UnitId, 0), absent.prelude_unit);
    try std.testing.expect(without.diagnostics.len != 0);
    try write(tmp.dir, "prelude.blot", "const unused_bad: Bool = 42\nconst value = 40\n");
    var invalid = try project.load(a, std.testing.io, entry, .{ .prelude_path = prelude });
    defer invalid.deinit(a);
    var bad = try semantic.checkProject(a, &invalid);
    defer bad.deinit(a);
    try std.testing.expect(bad.diagnostics.len != 0);
    try std.testing.expect(!bad.module(invalid.prelude_unit).valid);
}

fn completePipeline(allocator: std.mem.Allocator, entry: []const u8, prelude: []const u8) !void {
    var loaded = try project.load(allocator, std.testing.io, entry, .{ .prelude_path = prelude });
    var source_live = true;
    defer if (source_live) loaded.deinit(allocator);
    var checked = try semantic.checkProject(allocator, &loaded);
    var checked_live = true;
    defer if (checked_live) checked.deinit(allocator);
    try valid(&loaded, &checked);
    const entry_unit = loaded.entry;
    const units = try allocator.alloc(core.Module, loaded.units.items.len);
    var initialized: usize = 0;
    defer {
        for (units[0..initialized]) |*unit| unit.deinit(allocator);
        allocator.free(units);
    }
    for (loaded.units.items, 0..) |*source_unit, index| {
        const unit: u32 = @intCast(index + 1);
        units[index] = try core.lower(allocator, &source_unit.tree, &loaded.symbols, &checked.module(unit).checked);
        initialized += 1;
        units[index].unit = unit;
        try std.testing.expectEqual(@as(usize, 0), units[index].diagnostics.len);
    }
    checked.deinit(allocator);
    checked_live = false;
    loaded.deinit(allocator);
    source_live = false;
    var result = try backend.compile(allocator, units, entry_unit);
    defer result.deinit(allocator);
    if (result.diagnostic) |item| std.debug.print("prelude backend {d}: {s}\n", .{ item.unit, item.message() });
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "complete implicit-prelude pipeline releases all owners at every allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude_source);
    try write(tmp.dir, "main.blot", entry_source);
    try write(tmp.dir, "helper.blot", "const answer = identity 22\n");
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, completePipeline, .{ entry, prelude });
}
