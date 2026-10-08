const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const publication = @import("dependency_consumer.zig");
const consumer = @import("dependency_project_consumer.zig");
const cli = @import("dependency_cli.zig");
const D = @import("frozen_dependency.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const syntax = @import("syntax_diagnostics.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const sources = [_][]const u8{
    "// 雪🙂\nentry const answer=;\n",
    "// 雪🙂\nentry const answer=\"bad\\q\"\n",
    "// 雪🙂\nentry const answer=fn()=>do:\n  use\n  return 0\n",
    "// 雪🙂\nentry const answer=(42]\n",
    "// 雪🙂\nentry const answer=4294967296\n",
    "// 雪🙂\nentry const answer=1e100\n",
    "// 雪🙂\nentry const answer=0x100000000\n",
};
fn ordinary(allocator: std.mem.Allocator, path: []const u8) !publication.Diagnostic {
    var loaded = try project.load(allocator, io, path, .{});
    defer loaded.deinit(allocator);
    if (loaded.diagnostics.items.len != 0) {
        const issue = loaded.diagnostics.items[0];
        const unit = loaded.unit(issue.unit);
        if (issue.parse_code != null) return publication.publishedDiagnostic(allocator, issue.unit, "parse-project", unit.source, issue.publication.?, unit.tree.diagnostics.items);
        return publication.publishedDiagnostic(allocator, issue.unit, "parse-project", unit.source, issue.publication.?, issue.lexical_details);
    }
    var checked = try checker.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    const issue = checked.diagnostics[0];
    const detail = issue.numeric_literal orelse return error.TestUnexpectedResult;
    return publication.publishedDiagnostic(allocator, issue.unit, "check-project", loaded.unit(issue.unit).source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message(), .actual_token = detail.actual_token }, @as([]const ast.NumericFault, &.{detail}));
}
fn snapshotFail(allocator: std.mem.Allocator, path: []const u8, source_text: []const u8) !void {
    var expected = try ordinary(allocator, path);
    defer expected.deinit(allocator);
    var result = result_scope: {
        const source = try allocator.dupe(u8, source_text);
        defer allocator.free(source);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var bundle: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
        // Fresh entry frontend and its source/pool are all destroyed before
        // inspecting or rendering the returned failure snapshot.
        break :result_scope try consumer.compileOwned(allocator, io, path, source, .{}, &pool, &bundle);
    };
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic != null and result.compiled.bytes.len == 0);
    const actual = result.diagnostic.?;
    try std.testing.expectEqualStrings(expected.stage, actual.stage);
    try std.testing.expectEqualStrings(expected.code, actual.code);
    try std.testing.expectEqualStrings(expected.message, actual.message);
    try std.testing.expectEqual(expected.start, actual.start);
    try std.testing.expectEqual(expected.end, actual.end);
    try std.testing.expectEqual(expected.publication.?.utf16, actual.publication.?.utf16);
    try std.testing.expectEqual(expected.publication.?.cause, actual.publication.?.cause);
    try std.testing.expectEqual(expected.publication.?.actual_token, actual.publication.?.actual_token);
    try std.testing.expectEqual(expected.publication.?.expected_token, actual.publication.?.expected_token);
    try std.testing.expectEqualStrings(expected.publication.?.details_json, actual.publication.?.details_json);
    var rendered: std.Io.Writer.Allocating = .init(allocator);
    defer rendered.deinit();
    actual.write(&rendered.writer, path) catch return error.OutOfMemory;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, rendered.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("details").? == .array);
}
test "cached frontend publication equals ordinary project evidence after frontend teardown and OOM" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = sources[0] });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    for (sources) |source| {
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = source });
        try snapshotFail(a, path, source);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, snapshotFail, .{ path, source });
    }
}
test "creation frontend envelopes preserve earlier complete output and match ordinary public evidence" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = sources[0] });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const destination = try std.Io.Dir.path.join(a, &.{ root, "dependencies.blotdep" });
    defer a.free(destination);
    for (sources) |source| {
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = source });
        try dir.dir.writeFile(io, .{ .sub_path = "dependencies.blotdep", .data = "previous complete artifact" });
        var expected = try ordinary(a, path);
        defer expected.deinit(a);
        var rendered: std.Io.Writer.Allocating = .init(a);
        defer rendered.deinit();
        try std.testing.expect(!try cli.process(io, a, &rendered.writer, true, path, destination, null, .{}, @as([32]u8, @splat(7))));
        const line = std.mem.sliceTo(rendered.written(), '\n');
        const parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
        defer parsed.deinit();
        const object = parsed.value.object;
        try std.testing.expectEqualStrings(expected.code, object.get("code").?.string);
        try std.testing.expectEqualStrings(expected.message, object.get("message").?.string);
        try std.testing.expectEqualStrings(expected.stage, object.get("stage").?.string);
        try std.testing.expectEqualStrings(@tagName(expected.publication.?.cause), object.get("cause").?.string);
        const utf16 = object.get("utf16").?.object;
        try std.testing.expectEqual(@as(i64, expected.publication.?.utf16.?.start), utf16.get("start").?.integer);
        try std.testing.expect(std.mem.find(u8, rendered.written(), "\"live_bytes\":0") != null);
        const kept = try dir.dir.readFileAlloc(io, "dependencies.blotdep", a, .limited(1024));
        defer a.free(kept);
        try std.testing.expectEqualStrings("previous complete artifact", kept);
    }
}
fn puritySnapshot(allocator: std.mem.Allocator) !void {
    var diagnostic = scope: {
        const code = try allocator.dupe(u8, "initializer_effect");
        defer allocator.free(code);
        const message = try allocator.dupe(u8, "pure evaluation cannot perform lib/雪::ask");
        defer allocator.free(message);
        const name = try allocator.dupe(u8, "lib/雪::ask");
        defer allocator.free(name);
        const source = try allocator.dupe(u8, "// 雪🙂\nlet saved=0\n");
        defer allocator.free(source);
        const witness: check.PurityWitness = .{ .identity = .{ .unit = 2, .decl = 1 }, .operation_name = name };
        break :scope try publication.publishedDiagnostic(allocator, 3, "check-project", source, .{ .cause = syntax.Cause.native_detail, .code = code, .span = .{ .start = 15, .end = 20 }, .message = message }, @as([]const check.PurityWitness, &.{witness}));
    };
    defer diagnostic.deinit(allocator);
    try std.testing.expectEqualStrings("initializer_effect", diagnostic.code);
    try std.testing.expect(std.mem.find(u8, diagnostic.publication.?.details_json, "lib/雪::ask") != null);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    diagnostic.write(&output.writer, "main.blot") catch return error.OutOfMemory;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("lib/雪::ask", parsed.value.object.get("details").?.array.items[0].object.get("operation_name").?.string);
}
test "owned publication code message and canonical purity details outlive all borrowed inputs with OOM" {
    try puritySnapshot(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, puritySnapshot, .{});
}
