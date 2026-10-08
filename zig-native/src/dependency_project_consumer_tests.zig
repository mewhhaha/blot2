const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const relink = @import("dependency_relink.zig");
const symbols = @import("symbols.zig");
const consumer = @import("dependency_project_consumer.zig");
const loader = @import("dependency_project_loader.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(7)), .settings = @as([32]u8, @splat(8)), .source = @as([32]u8, @splat(9)), .dependencies = @as([32]u8, @splat(10)) };
const files = .{
    .{ "main.blot", @embedFile("closure-fixtures/main.blot") },
    .{ "left.blot", @embedFile("closure-fixtures/left.blot") },
    .{ "right.blot", @embedFile("closure-fixtures/right.blot") },
    .{ "shared.blot", @embedFile("closure-fixtures/shared.blot") },
};
const Owned = struct {
    bytes: []u8,
    expected: []u8,
    fn deinit(self: *Owned) void {
        a.free(self.bytes);
        a.free(self.expected);
    }
};
fn freezeEntry(path: []const u8) !Owned {
    var source = try project.load(a, std.testing.io, path, .{});
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try a.alloc(core.Module, source.units.items.len);
    defer a.free(units);
    var initialized: usize = 0;
    defer for (units[0..initialized]) |*unit| unit.deinit(a);
    for (units, 1..) |*unit, id| {
        unit.* = try core.lower(a, &source.unit(@intCast(id)).tree, &source.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
    }
    const emission_owners = try a.alloc(@import("runtime_identity.zig").Owner, units.len);
    defer a.free(emission_owners);
    for (emission_owners, 1..) |*owner, id| owner.* = .{ .unit = @intCast(id), .path = source.filename(@intCast(id)) };
    var names = try @import("runtime_identity.zig").Metadata.capture(a, &source.symbols, emission_owners, units.len);
    defer names.deinit(a);
    var compiled = try backend.compileWithIdentity(a, units, source.entry, names.view());
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    const expected = try a.dupe(u8, compiled.bytes);
    errdefer a.free(expected);
    var frozen = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &frozen);
    return .{ .bytes = try format.encode(a, key, frozen), .expected = expected };
}

test "fresh entry owns normal diamond imports after dependency frontends are released" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    inline for (files) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    var loaded = try format.decode(D.FrozenDependency, a, owned.bytes, key);
    defer format.deinit(a, &loaded);
    try closure.validate(a, &loaded);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &loaded, &pool, &.{ 1, 2, 3 });
    const before = try format.encode(a, key, loaded);
    defer a.free(before);
    var result = try consumer.compile(a, std.testing.io, path, files[0][1], .{}, &pool, &loaded);
    defer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("{s} {d} {s}\n", .{ issue.code, issue.start, issue.message });
    if (result.compiled.diagnostic) |issue| std.debug.print("emit {s} {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, owned.expected, result.compiled.bytes);
    const after = try format.encode(a, key, loaded);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    try std.testing.expect(result.stats.body_elaborations < 10);
}

test "changed entry dependency set declines without exposing an unused cached catalog" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    inline for (files) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    var loaded = try format.decode(D.FrozenDependency, a, owned.bytes, key);
    defer format.deinit(a, &loaded);
    try closure.validate(a, &loaded);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &loaded, &pool, &.{ 1, 2, 3 });
    try std.testing.expectError(error.DependencySetChanged, consumer.compile(a, std.testing.io, path, "entry const answer:Unit->U32=fn()=>42\n", .{}, &pool, &loaded));
}

test "fresh entry nominal State operation and record order match ordinary conceptual owners" {
    const entry_source = files[0][1] ++
        \\data EntryCell = #EntryCell U32
        \\data EntryRecord = #EntryRecord { zebra: U32, alpha: F32 }
        \\effect Ask: Unit -> F32
        \\const evaluate = fn () => do (@effect.provider Ask (fn () => 0.5)):
        \\  let (_, #EntryCell count) = @state.run (#EntryCell 42) (fn () => @state.get #EntryCell)
        \\  use fraction <- Ask ()
        \\  let record = #EntryRecord { zebra: count, alpha: fraction }
        \\  return @f32.add (@u32.to_f32 record.zebra) record.alpha
        \\entry const owned: Unit -> F32 = fn () => evaluate ()
        \\entry const folded = evaluate ()
        \\
    ;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    inline for (files) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = entry_source });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    var loaded = try format.decode(D.FrozenDependency, a, owned.bytes, key);
    defer format.deinit(a, &loaded);
    try closure.validate(a, &loaded);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &loaded, &pool, &.{ 1, 2, 3 });
    var result = try consumer.compileOwned(a, std.testing.io, path, entry_source, .{}, &pool, &loaded);
    defer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("{s} {d} {s}\n", .{ issue.code, issue.start, issue.message });
    if (result.compiled.diagnostic) |issue| std.debug.print("emit {s} {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, owned.expected, result.compiled.bytes);
    for (loaded.modules) |module| try std.testing.expectEqual(@as(usize, 0), module.interface.bindings.len);
}

fn compileFailing(allocator: std.mem.Allocator, bytes: []const u8, path: []const u8) !void {
    var loaded = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &loaded);
    try closure.validate(allocator, &loaded);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    try relink.relink(allocator, &loaded, &pool, &.{1});
    const before = try format.encode(allocator, key, loaded);
    defer allocator.free(before);
    var result = try consumer.compile(allocator, std.testing.io, path, "import {identity} from \"./shared\"\nentry const answer:Unit->U32=fn()=>identity 42\n", .{}, &pool, &loaded);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    const after = try format.encode(allocator, key, loaded);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
test "project cache complete fresh consumer releases every failed allocation and preserves frozen evidence" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const identity=fn value=>value\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {identity} from \"./shared\"\nentry const answer:Unit->U32=fn()=>identity 42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compileFailing, .{ owned.bytes, path });
}

test "project cache admission rejects current producer edits before symbol publication" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    inline for (files) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    var loaded = try format.decode(D.FrozenDependency, a, owned.bytes, key);
    defer format.deinit(a, &loaded);
    const actual_key = closure.payloadKey(key.compiler, key.settings, &loaded);
    const bytes = try format.encode(a, actual_key, loaded);
    defer a.free(bytes);
    var stats: loader.Stats = .{};
    var admitted = try loader.load(a, std.testing.io, bytes, key.compiler, key.settings, .{}, &stats);
    defer format.deinit(a, &admitted);
    try std.testing.expect(stats.source_bytes > 0);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const identity=fn value=>@u32.add value 1\n" });
    stats = .{};
    try std.testing.expectError(error.InvalidArtifact, loader.load(a, std.testing.io, bytes, key.compiler, key.settings, .{}, &stats));
}

fn loadFailing(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var stats: loader.Stats = .{};
    var candidate = try loader.load(allocator, std.testing.io, bytes, key.compiler, key.settings, .{}, &stats);
    defer format.deinit(allocator, &candidate);
    try std.testing.expectEqual(@as(usize, 1), candidate.modules.len);
}
test "project cache decoded current-source admission releases partial owners at every allocation" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const identity=fn value=>value\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {identity} from \"./shared\"\nentry const answer:Unit->U32=fn()=>identity 42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    var loaded = try format.decode(D.FrozenDependency, a, owned.bytes, key);
    defer format.deinit(a, &loaded);
    const bytes = try format.encode(a, closure.payloadKey(key.compiler, key.settings, &loaded), loaded);
    defer a.free(bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, loadFailing, .{bytes});
}

fn compileOwnedFailing(allocator: std.mem.Allocator, bytes: []const u8, expected: []const u8, path: []const u8) !void {
    var loaded = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &loaded);
    try closure.validate(allocator, &loaded);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    try relink.relink(allocator, &loaded, &pool, &.{1});
    var result = try consumer.compileOwned(allocator, std.testing.io, path, "import {identity} from \"./shared\"\nentry const answer:Unit->U32=fn()=>identity 42\n", .{}, &pool, &loaded);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.compiled.bytes);
    for (loaded.modules) |module| try std.testing.expectEqual(@as(usize, 0), module.interface.bindings.len);
}
test "consuming project cache emits after principal teardown and cleans every failed allocation" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const identity=fn value=>value\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {identity} from \"./shared\"\nentry const answer:Unit->U32=fn()=>identity 42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var owned = try freezeEntry(path);
    defer owned.deinit();
    try compileOwnedFailing(a, owned.bytes, owned.expected, path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compileOwnedFailing, .{ owned.bytes, owned.expected, path });
}
fn retainedPurity(allocator: std.mem.Allocator, bytes: []const u8, path: []const u8, source: []const u8, expected: []const u8) !void {
    var result = blk: {
        var loaded = try format.decode(D.FrozenDependency, allocator, bytes, key);
        defer format.deinit(allocator, &loaded);
        try closure.validate(allocator, &loaded);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        try relink.relink(allocator, &loaded, &pool, &.{1});
        const before = try format.encode(allocator, key, loaded);
        defer allocator.free(before);
        var rejected = try consumer.compileOwned(allocator, std.testing.io, path, source, .{}, &pool, &loaded);
        errdefer rejected.deinit(allocator);
        const after = try format.encode(allocator, key, loaded);
        defer allocator.free(after);
        try std.testing.expectEqualSlices(u8, before, after);
        break :blk rejected;
    };
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.compiled.bytes.len);
    try std.testing.expectEqualStrings("initializer_effect", result.diagnostic.?.code);
    try std.testing.expectEqualStrings(expected, result.diagnostic.?.message);
}
test "cached producer canonical effect witnesses outlive all input owners and retain rejection at every allocation" {
    const cases = .{
        .{
            "effect ask:Unit->U32\n",
            "import {ask as query} from \"./shared\"\nentry const answer=42\n",
            "import {ask as query} from \"./shared\"\nlet value=do:\n  use answer<-query ()\n  return answer\nentry const answer=42\n",
            "pure evaluation cannot perform shared.blot::ask; sequence an operation with use inside a provider scope",
        },
        .{
            "type Box {pair:(a,b)} is data=#Box (a,b)\ntype Reader a is effect={read:Unit->a}\n",
            "import * as api from \"./shared\"\nentry const answer=42\n",
            "import * as api from \"./shared\"\nlet value=api.Reader.read (api.Box ({pair:(U32,F32)})) ()\nentry const answer=42\n",
            "", // Compare the complete canonical specialization with the source compiler below.
        },
    };
    inline for (cases) |case| {
        var dir = std.testing.tmpDir(.{});
        defer dir.cleanup();
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = case[0] });
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = case[1] });
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        defer a.free(path);
        var owned = try freezeEntry(path);
        defer owned.deinit();
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = case[2] });
        const expected = blk: {
            var original = try project.load(a, std.testing.io, path, .{});
            defer original.deinit(a);
            var checked = try checker.checkProject(a, &original);
            defer checked.deinit(a);
            const issue = checked.diagnostics[0];
            try std.testing.expectEqual(@import("check.zig").Code.initializer_effect, issue.semantic.?);
            break :blk try @import("purity_diagnostics.zig").format(a, &original.symbols, "unused", issue.purity.?);
        };
        defer a.free(expected);
        if (case[3].len != 0) try std.testing.expectEqualStrings(case[3], expected);
        if (case[3].len == 0) {
            try std.testing.expect(std.mem.find(u8, expected, "shared.blot::Reader.read<") != null);
            try std.testing.expect(std.mem.find(u8, expected, "shared.blot3:Box6:1:i1:f") != null);
        }
        try retainedPurity(a, owned.bytes, path, case[2], expected);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedPurity, .{ owned.bytes, path, case[2], expected });
    }
}

fn retainedEntryWitness(allocator: std.mem.Allocator, bytes: []const u8, path: []const u8, source: []const u8, owned: bool, code: backend.Code, unit: u32, point: u32, message: []const u8) !void {
    var result = blk: {
        var loaded = try format.decode(D.FrozenDependency, allocator, bytes, key);
        defer format.deinit(allocator, &loaded);
        try closure.validate(allocator, &loaded);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        try relink.relink(allocator, &loaded, &pool, &.{1});
        const before = if (owned) &.{} else try format.encode(allocator, key, loaded);
        defer if (!owned) allocator.free(before);
        var rejected = if (owned)
            try consumer.compileOwned(allocator, std.testing.io, path, source, .{}, &pool, &loaded)
        else
            try consumer.compile(allocator, std.testing.io, path, source, .{}, &pool, &loaded);
        errdefer rejected.deinit(allocator);
        if (owned) {
            for (loaded.modules) |module| try std.testing.expectEqual(@as(usize, 0), module.interface.bindings.len);
        } else {
            const after = try format.encode(allocator, key, loaded);
            defer allocator.free(after);
            try std.testing.expectEqualSlices(u8, before, after);
        }
        break :blk rejected;
    };
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), result.compiled.bytes.len);
    const issue = result.compiled.diagnostic.?;
    try std.testing.expectEqual(code, issue.code);
    try std.testing.expectEqual(unit, issue.unit);
    try std.testing.expectEqual(point, issue.span.start);
    try std.testing.expectEqual(point, issue.span.end);
    try std.testing.expectEqualStrings(message, issue.message());
    try std.testing.expectEqual(@as(usize, 0), result.compiled.constant_steps);
}

test "entry witnesses preserve imported source owners after borrowed and consuming cache teardown at every allocation" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const compare = fn left => fn right => @type.same left right\nconst alias = compare\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {compare, alias} from \"./shared\"\nentry const answer = 42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var frozen = try freezeEntry(path);
    defer frozen.deinit();
    const cases = .{
        .{ "import {compare} from \"./shared\"\nentry const failure = compare (@panic \"left witness\") (@panic \"right witness\")\n", backend.Code.invalid_annotation, @as(u32, 2), @as(u32, 45), "Never is an internal control-flow type" },
        .{ "import {alias} from \"./shared\"\nentry const failure = alias (@panic \"left witness\") (@panic \"right witness\")\n", backend.Code.ambiguous_associated, @as(u32, 1), @as(u32, 39), "cannot select @type.same until operand types can be inferred; annotate the exported parameter or call the generic function with concrete types" },
    };
    inline for (cases) |case| {
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = case[0] });
        inline for (.{ false, true }) |owned| {
            try retainedEntryWitness(a, frozen.bytes, path, case[0], owned, case[1], case[2], case[3], case[4]);
            try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedEntryWitness, .{ frozen.bytes, path, case[0], owned, case[1], case[2], case[3], case[4] });
        }
    }
}

fn retainedStartup(allocator: std.mem.Allocator, bytes: []const u8, path: []const u8, owned: bool, point: u32, filename: []const u8) !void {
    // Returned diagnostic outlives the decoded cache, PI and symbol owners.
    var result = blk: {
        var loaded = try format.decode(D.FrozenDependency, allocator, bytes, key);
        defer format.deinit(allocator, &loaded);
        try closure.validate(allocator, &loaded);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        const units = try allocator.alloc(u32, loaded.modules.len);
        defer allocator.free(units);
        for (units, 1..) |*unit, i| unit.* = @intCast(i);
        try relink.relink(allocator, &loaded, &pool, units);
        const before = if (owned) &.{} else try format.encode(allocator, key, loaded);
        defer if (!owned) allocator.free(before);
        var rejected = if (owned)
            try @import("partial_dependency.zig").compileOwned(allocator, std.testing.io, path, null, .{}, &loaded)
        else
            try @import("partial_dependency.zig").compile(allocator, std.testing.io, path, null, .{}, &loaded);
        errdefer rejected.deinit(allocator);
        if (owned) {
            for (loaded.modules) |module| try std.testing.expectEqual(@as(usize, 0), module.interface.bindings.len);
        } else {
            const after = try format.encode(allocator, key, loaded);
            defer allocator.free(after);
            try std.testing.expectEqualSlices(u8, before, after);
        }
        break :blk rejected;
    };
    defer result.deinit(allocator);
    try std.testing.expect(result.result.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.bytes.len);
    const issue = result.result.compiled.diagnostic.?;
    try std.testing.expectEqual(backend.Code.initialization_cycle, issue.code);
    try std.testing.expectEqual(point, issue.span.start);
    try std.testing.expectEqual(point, issue.span.end);
    try std.testing.expectEqualStrings("top-level let initializers form a dependency cycle", issue.message());
    try std.testing.expectEqualStrings(filename, result.diagnostic_filename.?);
}

test "startup source edges and project component order survive borrowed and consuming cache teardown under OOM" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const library = "let first: U32 = second\nlet second = first\nconst read: Unit -> U32 = fn () => first\nconst metadata = @effect.count (@effect.of read)\n";
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "left.blot", .data = library });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "right.blot", .data = library });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {read, metadata} from \"./left\"\nimport {read as other} from \"./right\"\nentry const answer = 42\n" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    const left = try dir.dir.realPathFileAlloc(std.testing.io, "left.blot", a);
    defer a.free(left);
    const right = try dir.dir.realPathFileAlloc(std.testing.io, "right.blot", a);
    defer a.free(right);
    var frozen = try freezeEntry(path);
    defer frozen.deinit();
    const cases = .{
        .{ "import {read} from \"./left\"\nimport {read as unused} from \"./right\"\nentry const answer = if #True then 42 else read ()\n", left },
        .{ "import {metadata} from \"./left\"\nimport {read as unused} from \"./right\"\nentry const answer = metadata\n", left },
        .{ "import {read as first} from \"./left\"\nimport {read as second} from \"./right\"\nentry const answer = fn () => @u32.add (first ()) (second ())\n", right },
    };
    inline for (cases) |case| {
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = case[0] });
        inline for (.{ false, true }) |owned| {
            try retainedStartup(a, frozen.bytes, path, owned, 28, case[1]);
            try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedStartup, .{ frozen.bytes, path, owned, @as(u32, 28), case[1] });
        }
    }
}
