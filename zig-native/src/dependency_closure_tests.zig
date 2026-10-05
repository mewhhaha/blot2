const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const core = @import("core.zig");
const relink = @import("dependency_relink.zig");
const symbols = @import("symbols.zig");
const a = std.testing.allocator;
const compiler = @as([32]u8, @splat(7));
const settings = @as([32]u8, @splat(8));
const files = .{
    .{ "main.blot", @embedFile("closure-fixtures/main.blot") },
    .{ "left.blot", @embedFile("closure-fixtures/left.blot") },
    .{ "right.blot", @embedFile("closure-fixtures/right.blot") },
    .{ "shared.blot", @embedFile("closure-fixtures/shared.blot") },
};
const Fixture = struct {
    dir: std.testing.TmpDir,
    source: project.Project,
    checked: checker.CheckedProject,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (files) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        defer a.free(path);
        var source = try project.load(a, std.testing.io, path, .{});
        errdefer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        var checked = try checker.checkProject(a, &source);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |d| std.debug.print("{s} unit{d} {d}\n", .{ d.codeName(), d.unit, d.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .dir = dir, .source = source, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.source.deinit(a);
        self.dir.cleanup();
    }
};
fn key(source: *const project.Project) !format.Key {
    return closure.sourceKey(compiler, settings, source);
}
fn bytes(value: D.FrozenDependency) ![]u8 {
    return format.encode(a, .{ .compiler = compiler, .settings = settings, .source = compiler, .dependencies = settings }, value);
}

test "whole diamond closure retains producers, aliases, rows and ordered imports with dense units" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    try std.testing.expectEqual(@as(usize, 3), value.modules.len);
    try std.testing.expectEqual(f.source.symbols.entries.items.len + 1, value.symbols.len);
    try std.testing.expectEqualDeep(try key(&f.source), closure.payloadKey(compiler, settings, &value));
    try std.testing.expectEqualSlices(u32, &.{2}, value.modules[0].imports);
    try std.testing.expectEqualSlices(u32, &.{2}, value.modules[2].imports);
    try std.testing.expectEqual(@as(usize, 1), value.modules[1].fixities.len);
    try std.testing.expectEqual(@as(u32, 2), value.modules[1].fixities[0].producer.unit);
    const alias = f.source.symbols.lookup("id").?;
    const found = for (value.modules[0].interface.bindings) |b| {
        if (b.name == alias and b.external != null) break b.external.?;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 2), found.unit);
    const original = try bytes(value);
    defer a.free(original);
    var decoded = try format.decode(D.FrozenDependency, a, original, .{ .compiler = compiler, .settings = settings, .source = compiler, .dependencies = settings });
    defer format.deinit(a, &decoded);
    try closure.validate(a, &decoded);
    try closure.validateSources(&decoded, &f.source);
}

fn freezeFail(allocator: std.mem.Allocator, source: *const project.Project, checked: *const checker.CheckedProject) !void {
    var value = try closure.freeze(allocator, source, checked);
    defer format.deinit(allocator, &value);
    try closure.validate(allocator, &value);
}
test "complete closure freeze and validation clean every failure without changing source principal facts" {
    var f = try Fixture.init();
    defer f.deinit();
    var baseline = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &baseline);
    const before = try bytes(baseline);
    defer a.free(before);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeFail, .{ &f.source, &f.checked });
    var after_value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &after_value);
    const after = try bytes(after_value);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

fn validateFail(allocator: std.mem.Allocator, value: *const D.FrozenDependency) !void {
    try closure.validate(allocator, value);
}
test "decoded owner validation allocation failures preserve the immutable payload" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const before = try bytes(value);
    defer a.free(before);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, validateFail, .{&value});
    const after = try bytes(value);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

fn relocationFail(allocator: std.mem.Allocator, wire: []const u8) !void {
    var value = try format.decode(D.FrozenDependency, allocator, wire, .{ .compiler = compiler, .settings = settings, .source = compiler, .dependencies = settings });
    defer format.deinit(allocator, &value);
    try closure.validate(allocator, &value);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    _ = try pool.intern(allocator, "prior-symbol");
    relink.relink(allocator, &value, &pool, &.{ 7, 5, 9 }) catch |err| {
        try std.testing.expectEqual(@as(usize, 1), pool.entries.items.len);
        for (value.modules, 1..) |m, id| {
            try std.testing.expectEqual(id, m.core.unit);
            try std.testing.expectEqual(id, m.interface.unit);
        }
        return err;
    };
    for (value.modules, [_]u32{ 7, 5, 9 }) |m, id| {
        try std.testing.expectEqual(id, m.core.unit);
        try std.testing.expectEqual(id, m.interface.unit);
    }
    try std.testing.expectEqualSlices(u32, &.{5}, value.modules[0].imports);
}
test "whole closure decode and numeric relocation publication are atomic through every failure" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const wire = try bytes(value);
    defer a.free(wire);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, relocationFail, .{wire});
}

test "closure keys exclude new entry bytes and reject changed dependencies paths settings and topology" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const original = try key(&f.source);
    const entry = &f.source.units.items[f.source.entry - 1];
    const saved_entry = entry.source;
    entry.source = "entry const newly_named: Unit -> F32=fn()=>42.5\n";
    try std.testing.expectEqualDeep(original, try key(&f.source));
    try closure.validateSources(&value, &f.source);
    entry.source = saved_entry;
    const dependency = &f.source.units.items[1];
    const saved = dependency.source;
    dependency.source = "const altered=42\n";
    try std.testing.expect(!std.meta.eql(original, try key(&f.source)));
    try std.testing.expectError(error.InvalidArtifact, closure.validateSources(&value, &f.source));
    dependency.source = saved;
    var changed = settings;
    changed[0] ^= 1;
    try std.testing.expect(!std.meta.eql(original, try closure.sourceKey(compiler, changed, &f.source)));
    try std.testing.expectError(error.InvalidArtifact, closure.validateProducer(&value.modules[0], "/different/path", saved));
    try std.testing.expectError(error.InvalidArtifact, closure.validateProducer(&value.modules[0], value.modules[0].identity.normalized_path, "different source"));
    const edge = &f.source.imports.items[f.source.unit(2).imports.start];
    const target = edge.target;
    edge.target = 4;
    try std.testing.expect(!std.meta.eql(original, try key(&f.source)));
    try std.testing.expectError(error.InvalidArtifact, closure.validateSources(&value, &f.source));
    edge.target = target;
}

test "decoded closure rejects dependency cycles excluded entry producers and foreign binding owners" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const imports = try a.alloc(u32, 1);
    imports[0] = 1;
    a.free(value.modules[1].imports);
    value.modules[1].imports = imports;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &value));
    a.free(value.modules[1].imports);
    value.modules[1].imports = &.{};
    const binding = for (value.modules[0].interface.bindings, 0..) |b, id| {
        if (b.external != null) break id;
    } else return error.TestUnexpectedResult;
    const saved = value.modules[0].interface.bindings[binding].external;
    value.modules[0].interface.bindings[binding].external = .{ .unit = 3, .binding = std.math.maxInt(u32) };
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &value));
    value.modules[0].interface.bindings[binding].external = saved;
    value.modules[0].core.bodies[1].exported = true;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &value));
    value.modules[0].core.bodies[1].exported = false;
    const old_entry = f.source.entry;
    f.source.entry = 2;
    try std.testing.expectError(error.InvalidArtifact, closure.freeze(a, &f.source, &f.checked));
    f.source.entry = old_entry;
}

test "prelude bootstrap imports remain directed dependencies without an implicit reverse edge" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "entry const answer: Unit -> U32=fn()=>prelude_value 42\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = "import {identity} from \"./bootstrap\"\nconst prelude_value=fn value=>identity value\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "bootstrap.blot", .data = "const identity=fn value=>value\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    const prelude = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
    defer a.free(prelude);
    var source = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude });
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var value = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &value);
    try std.testing.expectEqual(@as(usize, 2), value.modules.len);
    try std.testing.expect(value.modules[0].identity.prelude);
    try std.testing.expectEqualSlices(u32, &.{2}, value.modules[0].imports);
    try std.testing.expectEqual(@as(usize, 0), value.modules[1].imports.len);
    try std.testing.expectEqualDeep(try key(&source), closure.payloadKey(compiler, settings, &value));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeFail, .{ &source, &checked });
}

test "source record payload declaration order survives prior symbol identities and duplicate fields reject" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {Pair} from \"./data\"\nentry const answer=42\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "data.blot", .data = "const second=fn value=>value\ndata Pair=#Pair {first:U32,second:U32}\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var source = try project.load(a, std.testing.io, path, .{});
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var value = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &value);
    const g = &value.modules[0].interface.graph;
    const record = for (g.nodes) |n| {
        if (n.tag == .record and n.b == 2) break n;
    } else return error.TestUnexpectedResult;
    const fields = g.extra[record.a..][0..4];
    try std.testing.expectEqual(source.symbols.lookup("first").?, fields[0]);
    try std.testing.expectEqual(source.symbols.lookup("second").?, fields[2]);
    try std.testing.expect(fields[0] > fields[2]);
    const saved = fields[2];
    fields[2] = fields[0];
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &value));
    fields[2] = saved;
    try closure.validate(a, &value);
}

test "principal publication keeps reusable globals and Core retains later-constrained local array facts" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {make} from \"./data\"\nentry const answer: Unit -> U32=fn()=>@array.length (make ())\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "data.blot", .data = "data Item=#Item U32\nconst make=fn()=>do:\n  let found=#[]\n  for item in #[#Item 42]:\n    found := #[item]\n  return found\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var source = try project.load(a, std.testing.io, path, .{});
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    for (checked.diagnostics) |d| std.debug.print("principal {s} unit{d} {d}\n", .{ d.codeName(), d.unit, d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var old = try @import("dependency_snapshot.zig").freeze(a, &source.unit(2).tree, &checked.module(2).checked);
    defer @import("dependency_snapshot.zig").deinit(a, &old);
    try std.testing.expectError(error.InvalidArtifact, @import("dependency_interface_validation.zig").validate(&old, source.symbols.entries.items.len + 1, 2));
    var value = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &value);
    const found = source.symbols.lookup("found").?;
    const local = for (value.modules[0].interface.bindings, 0..) |b, id| {
        if (b.kind == .local and b.name == found) break id;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), value.modules[0].interface.bindings[local].ty);
    try std.testing.expectEqual(@as(u32, 0), value.modules[0].interface.bindings[local].scheme.root);
    try std.testing.expectEqual(@as(u32, 0), value.modules[0].interface.bindings[local].scheme.variables.len);
    try std.testing.expect(value.modules[0].core.bindings[local].ty != 0);
    const make = source.symbols.lookup("make").?;
    const global = for (value.modules[0].interface.bindings, 0..) |b, id| {
        if (b.kind == .global and b.name == make) break id;
    } else return error.TestUnexpectedResult;
    try std.testing.expect(value.modules[0].interface.bindings[global].scheme.root != 0);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeFail, .{ &source, &checked });
}

fn validatePrincipalFail(allocator: std.mem.Allocator, owner: *const @import("principal_interface.zig").Interface) !void {
    try @import("dependency_interface_validation.zig").validateGraph(allocator, owner);
}
test "wide unordered source record uniqueness uses one bounded symbol-stamp lane and releases every failed allocation" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const g = &value.modules[1].interface.graph;
    const record_id = for (g.nodes, 0..) |n, id| {
        if (n.tag == .record) break id;
    } else return error.TestUnexpectedResult;
    const count: usize = 4096;
    const start = g.extra.len;
    const additional = try std.math.mul(usize, count, 2);
    const length = try std.math.add(usize, start, additional);
    const enlarged = try a.alloc(u32, length);
    @memcpy(enlarged[0..start], g.extra);
    for (0..count) |id| {
        enlarged[start + id * 2] = @intCast(count - id + 100);
        enlarged[start + id * 2 + 1] = @import("types.zig").u32_type;
    }
    a.free(g.extra);
    g.extra = enlarged;
    g.nodes[record_id] = .{ .tag = .record, .a = @intCast(start), .b = @intCast(count) };
    try @import("dependency_interface_validation.zig").validate(&value.modules[1].interface, count + 101, value.modules.len);
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = a };
    try @import("dependency_interface_validation.zig").validateGraph(tracked.allocator(), &value.modules[1].interface);
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
    try std.testing.expect(tracked.counts.allocated_bytes < 128 * 1024);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, validatePrincipalFail, .{&value.modules[1].interface});
    enlarged[start + (count - 1) * 2] = enlarged[start];
    try std.testing.expectError(error.InvalidArtifact, @import("dependency_interface_validation.zig").validateGraph(a, &value.modules[1].interface));
}

test "genuine global scheme quantifiers stay strict after neutral local publication" {
    var f = try Fixture.init();
    defer f.deinit();
    var value = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &value);
    const identity = f.source.symbols.lookup("identity").?;
    const binding = for (value.modules[1].interface.bindings) |b| {
        if (b.kind == .global and b.name == identity) break b;
    } else return error.TestUnexpectedResult;
    try std.testing.expect(binding.scheme.variables.len != 0);
    const slot = &value.modules[1].interface.graph.extra[binding.scheme.variables.start];
    const saved = slot.*;
    slot.* = @import("types.zig").u32_type;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &value));
    slot.* = saved;
    try closure.validate(a, &value);
}

test "entry-only project freezes an owned empty closure without treating its names as dependency source" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "entry const answer=42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var source = try project.load(a, std.testing.io, path, .{});
    defer source.deinit(a);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var value = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &value);
    try std.testing.expectEqual(@as(usize, 0), value.modules.len);
    try std.testing.expect(value.symbols.len > 1);
    try std.testing.expectEqualDeep(try key(&source), closure.payloadKey(compiler, settings, &value));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeFail, .{ &source, &checked });
}
