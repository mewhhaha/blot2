//! An edited associated function is selected by type, often through no named
//! reference: receiver syntax, operators and `from` resolve it from the
//! operand's catalog. Retained revisions rebuild exactly the declarations that
//! may select it and keep the rest; output always equals a cold build.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const shapes =
    \\type Box is data = #Box { value: U32 }
    \\const Box.size = fn (box: Box) -> U32 => @u32.add box.value 1
    \\const Box.add = fn (left: Box) => fn (right: Box) -> Box => #Box { value: @u32.add left.value right.value }
    \\const Box.from = fn (value: U32) -> Box => #Box { value: @u32.add value 1 }
    \\const measure = fn box => box.size
    \\const combine = fn left => fn right => @type.call "add" left right
    \\const convert = fn value => @type.result "from" value
    \\const unrelated = fn (value: U32) -> U32 => @u32.add value 1
;
const main =
    \\import {Box, measure, combine, convert, unrelated} from "./shapes"
    \\entry const measured = fn (value: U32) -> U32 => (#Box { value }).size
    \\entry const generic = fn (value: U32) -> U32 => measure (#Box { value })
    \\entry const summed = fn (value: U32) -> U32 => (combine (#Box { value }) (#Box { value: 2 })).value
    \\entry const converted = fn (value: U32) -> U32 => do:
    \\  let box: Box = convert value
    \\  return box.value
    \\entry const plain = fn (value: U32) -> U32 => unrelated value
;
// Same-length edits with no new spelling keep the namespace and every
// published interface, so only the bodies' selectors are rebuilt.
const Edit = struct { search: []const u8, replace: []const u8 };
const edits = [_]Edit{
    .{ .search = "@u32.add box.value 1", .replace = "@u32.add box.value 2" },
    .{ .search = "@u32.add left.value right.value", .replace = "@u32.add right.value left.value" },
    .{ .search = "@u32.add value 1 }", .replace = "@u32.add value 3 }" },
};

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "shapes.blot", .data = shapes });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn write(self: *Fixture, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = "shapes.blot", .data = text });
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
};

fn cold(fixture: *const Fixture) !partial.Result {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var preparation = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    switch (preparation) {
        .rejected => |result| return result,
        .ready => |*prepared| {
            defer prepared.deinit(a);
            return prepared.emit(a);
        },
    }
}

/// Revises and requires cold-build output. Some named instances are reused
/// (the unrelated one) and some rebuilt (the selectors of the edited member).
fn revise(session: *retained.Session, fixture: *const Fixture, original: []const u8, changed: bool) !void {
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    var expected = try cold(fixture);
    defer expected.deinit(a);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expect(expected.result.diagnostic == null and expected.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, result.result.compiled.bytes);
    try std.testing.expectEqual(changed, !std.mem.eql(u8, original, result.result.compiled.bytes));
    const reuse = result.result.compiled.reuse;
    if (reuse.reused_named == 0) return error.NothingReused;
    if (reuse.fresh_named == 0) return error.NothingRebuilt;
}

test "an edited associated function rebuilds every declaration that selects it and keeps the rest" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var original = try cold(&fixture);
    defer original.deinit(a);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    initial.deinit(a);
    for (edits) |edit| {
        const text = try std.mem.replaceOwned(u8, a, shapes, edit.search, edit.replace);
        defer a.free(text);
        try std.testing.expect(!std.mem.eql(u8, text, shapes));
        try fixture.write(text);
        try revise(&session, &fixture, original.result.compiled.bytes, true);
        try fixture.write(shapes);
        try revise(&session, &fixture, original.result.compiled.bytes, false);
    }
}
