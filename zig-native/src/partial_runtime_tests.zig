const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const consumer = @import("dependency_project_consumer.zig");
const relink = @import("dependency_relink.zig");
const symbols = @import("symbols.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
const source = @embedFile("partial-runtime-fixtures/namespace-ab.blot");
const prelude = "const identity=fn value=>value\n";
const SourceReady = struct {
    units: []core.Module,
    names: identity.Metadata,
    entry: u32,
    fn deinit(self: *SourceReady, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
        for (self.units) |*unit| unit.deinit(allocator);
        allocator.free(self.units);
    }
};
fn lowerSource(allocator: std.mem.Allocator, path: []const u8, prelude_path: []const u8) !SourceReady {
    var loaded = try project.load(allocator, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 4), loaded.units.items.len);
    var checked = try checker.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("source {s}:{d}\n", .{ issue.codeName(), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try allocator.alloc(core.Module, loaded.units.items.len);
    var initialized: usize = 0;
    var transferred = false;
    defer if (!transferred) {
        for (units[0..initialized]) |*unit| unit.deinit(allocator);
        allocator.free(units);
    };
    for (units, 1..) |*unit, id| {
        unit.* = try core.lower(allocator, &loaded.unit(@intCast(id)).tree, &loaded.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
        try std.testing.expectEqual(@as(usize, 0), unit.diagnostics.len);
    }
    const owners = try allocator.alloc(identity.Owner, units.len);
    defer allocator.free(owners);
    for (owners, 1..) |*owner, id| owner.* = .{ .unit = @intCast(id), .path = loaded.filename(@intCast(id)) };
    const names = try identity.Metadata.capture(allocator, &loaded.symbols, owners, owners.len);
    transferred = true;
    return .{ .units = units, .names = names, .entry = loaded.entry };
}
fn compileSource(allocator: std.mem.Allocator, path: []const u8, prelude_path: []const u8) !backend.Result {
    // No source, syntax, symbol pool or inference owner survives lowerSource.
    var ready = try lowerSource(allocator, path, prelude_path);
    defer ready.deinit(allocator);
    return backend.compileWithIdentity(allocator, ready.units, ready.entry, ready.names.view());
}
fn freeze(path: []const u8, prelude_path: []const u8) ![]u8 {
    var loaded = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try checker.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try closure.freeze(a, &loaded, &checked);
    defer format.deinit(a, &frozen);
    return format.encode(a, key, frozen);
}
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude_path: [:0]u8,
    full: []u8,
    seed: []u8,
    expected: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "a.blot", @embedFile("partial-runtime-fixtures/a.blot") }, .{ "b.blot", @embedFile("partial-runtime-fixtures/b.blot") }, .{ "main.blot", source }, .{ "prelude.blot", prelude }, .{ "seed.blot", "entry const initial:Unit->U32=fn()=>0\n" } }) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        errdefer a.free(path);
        const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        errdefer a.free(prelude_path);
        const seed_path = try dir.dir.realPathFileAlloc(std.testing.io, "seed.blot", a);
        defer a.free(seed_path);
        const full = try freeze(path, prelude_path);
        errdefer a.free(full);
        const seed = try freeze(seed_path, prelude_path);
        errdefer a.free(seed);
        var compiled = try compileSource(a, path, prelude_path);
        defer compiled.deinit(a);
        try std.testing.expect(compiled.diagnostic == null);
        return .{ .dir = dir, .path = path, .prelude_path = prelude_path, .full = full, .seed = seed, .expected = try a.dupe(u8, compiled.bytes) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude_path);
        a.free(self.full);
        a.free(self.seed);
        a.free(self.expected);
        self.dir.cleanup();
    }
};
fn checkConsumption(dependency: *const D.FrozenDependency) !void {
    const consumed = dependency.modules[0].interface.bindings.len == 0;
    for (dependency.modules) |module| {
        try std.testing.expectEqual(consumed, module.interface.bindings.len == 0);
        try std.testing.expect(module.core.nodes.len != 0);
        if (consumed) try std.testing.expectEqualDeep(std.mem.zeroes(@import("principal_interface.zig").Interface), module.interface);
    }
}
fn mixed(allocator: std.mem.Allocator, fixture: *const Fixture, full: bool, consume: bool) !void {
    const bytes = if (full) fixture.full else fixture.seed;
    var dependency = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    try std.testing.expectEqual(@as(usize, if (full) 3 else 1), dependency.modules.len);
    var result = (if (consume)
        partial.compileOwned(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency)
    else
        partial.compile(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency)) catch |err| {
        try checkConsumption(&dependency);
        if (!consume) try std.testing.expect(dependency.modules[0].interface.bindings.len != 0);
        return err;
    };
    defer result.deinit(allocator);
    if (result.result.diagnostic) |issue| std.debug.print("mixed {s}:{d} {s}\n", .{ issue.code, issue.start, issue.message });
    if (result.result.compiled.diagnostic) |issue| std.debug.print("emit {s}:{d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fixture.expected, result.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, if (full) 3 else 1), result.cached_modules);
    try std.testing.expectEqual(@as(usize, if (full) 1 else 3), result.fresh_modules);
    try checkConsumption(&dependency);
    if (consume) {
        try std.testing.expect(dependency.modules[0].interface.bindings.len == 0);
    } else {
        const after = try format.encode(allocator, key, dependency);
        defer allocator.free(after);
        try std.testing.expectEqualSlices(u8, bytes, after);
    }
}
fn oldFullCache(allocator: std.mem.Allocator, fixture: *const Fixture, consume: bool) !void {
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.full, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    try relink.relink(allocator, &dependency, &pool, &.{ 1, 2, 3 });
    var result = if (consume)
        try consumer.compileOwned(allocator, std.testing.io, fixture.path, source, .{ .prelude_path = fixture.prelude_path }, &pool, &dependency)
    else
        try consumer.compile(allocator, std.testing.io, fixture.path, source, .{ .prelude_path = fixture.prelude_path }, &pool, &dependency);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fixture.expected, result.compiled.bytes);
    try checkConsumption(&dependency);
    if (consume) {
        try std.testing.expect(dependency.modules[0].interface.bindings.len == 0);
    } else {
        const after = try format.encode(allocator, key, dependency);
        defer allocator.free(after);
        try std.testing.expectEqualSlices(u8, fixture.full, after);
    }
}
fn sourceOOM(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var result = try compileSource(allocator, fixture.path, fixture.prelude_path);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fixture.expected, result.bytes);
}
test "partial runtime identity keeps same spelling imported and entry providers and State exact across source teardown" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for ([_]bool{ false, true }) |consume| {
        try oldFullCache(a, &fixture, consume);
        for ([_]bool{ false, true }) |full| try mixed(a, &fixture, full, consume);
    }
}
test "partial runtime source fullcache and mixed identity owners release every failed allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceOOM, .{&fixture});
    for ([_]bool{ false, true }) |consume| {
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, oldFullCache, .{ &fixture, consume });
        for ([_]bool{ false, true }) |full| try @import("allocation_failures.zig").checkAllAllocationFailures(a, mixed, .{ &fixture, full, consume });
    }
}
