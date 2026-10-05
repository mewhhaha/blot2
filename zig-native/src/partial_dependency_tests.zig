const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(7)), .settings = @as([32]u8, @splat(8)), .source = @as([32]u8, @splat(9)), .dependencies = @as([32]u8, @splat(10)) };
const prelude = "infixl 60 (+) = plus\nconst plus = fn left => fn right => @u32.add left right\nconst identity = fn value => value\ndata Box a = #Box a\n";
const seed = "entry const initial:Unit->U32 = fn () => 42\n";
const shared = "const unwrap = fn box => case box of\n  #Box value => identity value\n";
const left = "import {unwrap} from \"./shared\"\nconst first = fn value => unwrap (#Box value)\n";
const right = "import {unwrap} from \"./shared\"\nconst second = fn value => unwrap (#Box value)\n";
const entry = "import {first} from \"./left\"\nimport {second} from \"./right\"\nentry const answer:Unit->U32 = fn () => first 20 + second 22\nentry const fraction:Unit->F32 = fn () => first 0.5\n";

const field_library = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\n";
const field_entry = "import {Box, select} from \"./library\"\nentry const answer = fn () => select (#Box 1)\n";
const field_prelude = "const prelude_identity = fn value => value\n";
const field_renamed_entry = "import {Box, select} from \"./producer\"\nentry const answer = fn () => select (#Box 1)\n";
const field_entry_nominal = "import {select} from \"./producer\"\ntype EntryBox is data = #EntryBox U32\nconst EntryBox.read = fn value => 42\nentry const answer = fn () => select (#EntryBox 1)\n";
const FieldMode = enum { source, prelude, full, full_consumer };
const FieldControl = enum { library, renamed, entry_nominal };

fn fieldEnvelope(issue: backend.Diagnostic, unit: u32, message: []const u8) !void {
    try std.testing.expectEqual(backend.Code.missing_field, issue.code);
    try std.testing.expectEqual(unit, issue.unit);
    try std.testing.expectEqual(core.Span{ .start = 81, .end = 81 }, issue.span);
    try std.testing.expectEqualStrings(message, issue.message());
}

fn ordinaryFieldResult(path: []const u8, prelude_path: []const u8) !backend.Result {
    var source = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
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
        unit.* = try core.lowerWithOrigins(a, &source.unit(@intCast(id)).tree, &source.symbols, &checked.module(@intCast(id)).checked, .{ .context = &source, .lookup = checker.diagnosticModuleOrigin });
        initialized += 1;
    }
    return backend.compile(a, units, source.entry);
}

fn fieldSeedBytes(path: []const u8, prelude_path: []const u8, library: bool, display_name: []const u8) ![]u8 {
    var source = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    if (library) {
        try std.testing.expectEqual(@as(u32, 2), source.entry);
        var original_origin = false;
        for (checked.module(3).checked.obligations) |obligation| if (obligation.explicit and obligation.kind == .field) {
            try std.testing.expectEqual(@as(u32, 3), obligation.qualification_unit);
            original_origin = true;
        };
        try std.testing.expect(original_origin);
    }
    var frozen = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &frozen);
    if (library) {
        try std.testing.expectEqual(@as(usize, 2), frozen.modules.len);
        const producer = &frozen.modules[1];
        var relocated_origin = false;
        for (producer.core.obligations) |obligation| if (obligation.explicit and obligation.kind == .field) {
            try std.testing.expectEqual(@as(u32, 2), obligation.qualification_unit);
            try std.testing.expectEqual(@as(u32, 81), obligation.qualification_span.?.start);
            relocated_origin = true;
        };
        try std.testing.expect(relocated_origin);
        var principal_origin = false;
        for (producer.interface.obligations) |obligation| if (obligation.explicit and obligation.kind == .field) {
            try std.testing.expectEqual(@as(u32, 2), obligation.qualification_unit);
            principal_origin = true;
        };
        try std.testing.expect(principal_origin);
        var display = false;
        for (producer.core.nominals) |nominal| if (nominal.identity.decl != 0) {
            try std.testing.expectEqualStrings("Box", producer.core.name(nominal.diagnostic_name));
            try std.testing.expectEqualStrings(display_name, producer.core.name(nominal.diagnostic_origin));
            display = true;
        };
        try std.testing.expect(display);
    } else try std.testing.expectEqual(@as(usize, 1), frozen.modules.len);
    return format.encode(a, key, frozen);
}

fn importedFieldOwners(mode: FieldMode, control: FieldControl) !void {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const entry_name = if (control == .library) "main.blot" else "program.blot";
    const producer_name = if (control == .library) "library.blot" else "producer.blot";
    const source = switch (control) {
        .library => field_entry,
        .renamed => field_renamed_entry,
        .entry_nominal => field_entry_nominal,
    };
    const expected_message = switch (control) {
        .library => "no field read on library.blot::Box",
        .renamed => "no field read on producer.blot::Box",
        .entry_nominal => "no field read on program.blot::EntryBox",
    };
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = entry_name, .data = source });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = producer_name, .data = field_library });
    inline for (.{ .{ "prelude.blot", field_prelude }, .{ "seed.blot", seed } }) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, entry_name, a);
    defer a.free(path);
    const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
    defer a.free(prelude_path);
    if (mode == .source) {
        // The result owns its envelope after source/checker/Core teardown.
        var result = try ordinaryFieldResult(path, prelude_path);
        defer result.deinit(a);
        try fieldEnvelope(result.diagnostic orelse return error.MissingDiagnostic, 3, expected_message);
        return;
    }
    const seed_path = try dir.dir.realPathFileAlloc(std.testing.io, "seed.blot", a);
    defer a.free(seed_path);
    const full = mode == .full or mode == .full_consumer;
    const bytes = try fieldSeedBytes(if (full) path else seed_path, prelude_path, full, if (control == .library) "library.blot" else "producer.blot");
    defer a.free(bytes);
    var dependency = try format.decode(D.FrozenDependency, a, bytes, key);
    var dependency_live = true;
    defer if (dependency_live) format.deinit(a, &dependency);
    try closure.validate(a, &dependency);
    if (mode == .full_consumer) {
        var pool: @import("symbols.zig").Pool = .{};
        defer pool.deinit(a);
        try @import("dependency_relink.zig").relink(a, &dependency, &pool, &.{ 1, 2 });
        var result = try @import("dependency_project_consumer.zig").compileOwned(a, std.testing.io, path, source, .{ .prelude_path = prelude_path }, &pool, &dependency);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        format.deinit(a, &dependency);
        dependency_live = false;
        try fieldEnvelope(result.compiled.diagnostic orelse return error.MissingDiagnostic, 2, expected_message);
        return;
    }
    var result = try partial.compileOwned(a, std.testing.io, path, null, .{ .prelude_path = prelude_path }, &dependency);
    defer result.deinit(a);
    try std.testing.expect(result.result.diagnostic == null);
    try std.testing.expectEqual(@as(usize, if (mode == .full) 2 else 1), result.cached_modules);
    format.deinit(a, &dependency);
    dependency_live = false;
    try fieldEnvelope(result.result.compiled.diagnostic orelse return error.MissingDiagnostic, if (mode == .full) 2 else 3, expected_message);
    try std.testing.expect(std.mem.endsWith(u8, result.diagnostic_filename.?, producer_name));
}

test "imported demanded field exact source envelope outlives all frontend and Core owners" {
    try importedFieldOwners(.source, .library);
}

test "imported demanded field exact prelude-only cache envelope retains library declaration ownership" {
    try importedFieldOwners(.prelude, .library);
}

test "imported demanded field exact full-cache envelope preserves relocated qualifier and nominal owners" {
    try importedFieldOwners(.full, .library);
}

test "imported demanded field exact full-cache entry consumer preserves diagnostic owners" {
    try importedFieldOwners(.full_consumer, .library);
}

test "imported demanded field exact renamed producer and entry owners across all boundaries" {
    inline for (std.meta.tags(FieldMode)) |mode| try importedFieldOwners(mode, .renamed);
}

test "imported demanded field exact renamed entry nominal owner follows project context" {
    inline for (std.meta.tags(FieldMode)) |mode| try importedFieldOwners(mode, .entry_nominal);
}

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude_path: [:0]u8,
    bytes: []u8,
    expected: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "prelude.blot", prelude }, .{ "seed.blot", seed }, .{ "main.blot", entry }, .{ "left.blot", left }, .{ "right.blot", right }, .{ "shared.blot", shared } }) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        errdefer a.free(prelude_path);
        const seed_path = try dir.dir.realPathFileAlloc(std.testing.io, "seed.blot", a);
        defer a.free(seed_path);
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        errdefer a.free(path);
        var source = try project.load(a, std.testing.io, seed_path, .{ .prelude_path = prelude_path });
        defer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        var checked = try checker.checkProject(a, &source);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var frozen = try closure.freeze(a, &source, &checked);
        defer format.deinit(a, &frozen);
        try std.testing.expectEqual(@as(usize, 1), frozen.modules.len);
        const bytes = try format.encode(a, key, frozen);
        errdefer a.free(bytes);
        var ordinary = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
        defer ordinary.deinit(a);
        var normal = try checker.checkProject(a, &ordinary);
        defer normal.deinit(a);
        for (normal.diagnostics) |issue| std.debug.print("ordinary {s}:{d}\n", .{ issue.codeName(), issue.span.start });
        try std.testing.expectEqual(@as(usize, 0), normal.diagnostics.len);
        const units = try a.alloc(core.Module, ordinary.units.items.len);
        defer a.free(units);
        var initialized: usize = 0;
        defer for (units[0..initialized]) |*unit| unit.deinit(a);
        for (units, 1..) |*unit, id| {
            unit.* = try core.lower(a, &ordinary.unit(@intCast(id)).tree, &ordinary.symbols, &normal.module(@intCast(id)).checked);
            initialized += 1;
            unit.unit = @intCast(id);
        }
        const owners = try a.alloc(@import("runtime_identity.zig").Owner, units.len);
        defer a.free(owners);
        for (owners, 1..) |*owner, unit| owner.* = .{ .unit = @intCast(unit), .path = ordinary.filename(@intCast(unit)) };
        var identity = try @import("runtime_identity.zig").Metadata.capture(a, &ordinary.symbols, owners, units.len);
        defer identity.deinit(a);
        var compiled = try backend.compileWithIdentity(a, units, ordinary.entry, identity.view());
        defer compiled.deinit(a);
        try std.testing.expect(compiled.diagnostic == null);
        return .{ .dir = dir, .path = path, .prelude_path = prelude_path, .bytes = bytes, .expected = try a.dupe(u8, compiled.bytes) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude_path);
        a.free(self.bytes);
        a.free(self.expected);
        self.dir.cleanup();
    }
};
fn run(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.bytes, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    var result = try partial.compile(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency);
    defer result.deinit(allocator);
    if (result.result.diagnostic) |issue| std.debug.print("partial {s}:{d} {s}\n", .{ issue.code, issue.start, issue.message });
    if (result.result.compiled.diagnostic) |issue| std.debug.print("emit {s}:{d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fixture.expected, result.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, 1), result.cached_modules);
    try std.testing.expectEqual(@as(usize, 4), result.fresh_modules);
    // Cached syntax is never recreated or fed to checking/lowering.
    try std.testing.expectEqual(@as(usize, 5), result.result.stats.body_elaborations);
    const after = try format.encode(allocator, key, dependency);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, fixture.bytes, after);
}
test "partial prelude composes fresh diamond modules with exact generic nominal fixity evidence" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try run(a, &fixture);
}
test "partial prelude composition allocation failures release all owners and preserve the seed" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, run, .{&fixture});
}
test "partial fresh source error owns producer diagnostic after teardown and protects output" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const unwrap:U32 = 0.5\n" });
    var dependency = try format.decode(D.FrozenDependency, a, fixture.bytes, key);
    defer format.deinit(a, &dependency);
    var result = try partial.compile(a, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency);
    defer result.deinit(a);
    const issue = result.result.diagnostic orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("type_mismatch", issue.code);
    try std.testing.expect(std.mem.endsWith(u8, result.diagnostic_filename.?, "/shared.blot"));
    const shared_path = try fixture.dir.dir.realPathFileAlloc(std.testing.io, "shared.blot", a);
    defer a.free(shared_path);
    try std.testing.expectError(error.OutputIsSource, partial.compile(a, std.testing.io, fixture.path, shared_path, .{ .prelude_path = fixture.prelude_path }, &dependency));
    const after = try format.encode(a, key, dependency);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, fixture.bytes, after);
}
test "partial fresh import cycles and missing exports retain normal loader checker diagnostics" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "import {first} from \"./left\"\nconst unwrap = fn value => value\n" });
    var dependency = try format.decode(D.FrozenDependency, a, fixture.bytes, key);
    defer format.deinit(a, &dependency);
    var cycle = try partial.compile(a, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency);
    defer cycle.deinit(a);
    try std.testing.expectEqualStrings("import_cycle", cycle.result.diagnostic.?.code);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "shared.blot", .data = "const missing = 42\n" });
    var missing = try partial.compile(a, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency);
    defer missing.deinit(a);
    try std.testing.expectEqualStrings("unknown_export", missing.result.diagnostic.?.code);
}

fn ownedRun(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.bytes, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    var result = partial.compileOwned(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency) catch |err| {
        // OOM before lowering preserves all interfaces. OOM in specialization
        // leaves all consumed interfaces zeroed, with Core still owned by the
        // bundle. The transition performs no allocations and cannot be partial.
        const consumed = dependency.modules[0].interface.bindings.len == 0;
        for (dependency.modules) |module| {
            try std.testing.expectEqual(consumed, module.interface.bindings.len == 0);
            try std.testing.expect(module.core.nodes.len != 0);
        }
        return err;
    };
    defer result.deinit(allocator);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fixture.expected, result.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, 1), result.cached_modules);
    try std.testing.expectEqual(@as(usize, 4), result.fresh_modules);
    try std.testing.expectEqual(@as(usize, 5), result.result.stats.body_elaborations);
    for (dependency.modules) |module| {
        try std.testing.expectEqualDeep(std.mem.zeroes(@import("principal_interface.zig").Interface), module.interface);
        try std.testing.expect(module.core.nodes.len != 0);
    }
}
test "partial owned composition consumes every principal interface before specialization with exact code" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try ownedRun(a, &fixture);
}
test "partial owned composition OOM releases fresh owners and atomically preserves or consumes the seed" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ownedRun, .{&fixture});
}

fn numericRun(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    // Build expected publication using the ordinary complete source checker.
    // Own it before tearing down every source/checker owner.
    var expected = expected_scope: {
        var ordinary = try project.load(allocator, std.testing.io, fixture.path, .{ .prelude_path = fixture.prelude_path });
        defer ordinary.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), ordinary.diagnostics.items.len);
        var checked = try checker.checkProject(allocator, &ordinary);
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
        try std.testing.expectEqual(@as(usize, 0), checked.imported_schemes);
        for (checked.modules) |module| try std.testing.expect(module == null);
        const issue = checked.diagnostics[0];
        const fault = issue.numeric_literal orelse return error.TestUnexpectedResult;
        break :expected_scope try @import("dependency_consumer.zig").publishedDiagnostic(allocator, issue.unit, "check-project", ordinary.unit(issue.unit).source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message(), .actual_token = fault.actual_token }, @as([]const @import("ast.zig").NumericFault, &.{fault}));
    };
    defer expected.deinit(allocator);
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.bytes, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    {
        var loaded = try project.loadCompiled(allocator, std.testing.io, fixture.path, .{ .prelude_path = fixture.prelude_path }, &dependency);
        defer loaded.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), loaded.compiled_modules.len);
        // Cached source, syntax and source solver remain absent even when
        // declaration-only static validation needs their nominal headers.
        try std.testing.expectEqual(@as(usize, 0), loaded.units.items[0].source.len);
        try std.testing.expectEqual(@as(usize, 0), loaded.units.items[0].tree.nodes.items.len);
        var checked = try checker.checkProject(allocator, &loaded);
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
        try std.testing.expectEqual(@as(usize, 0), checked.imported_schemes);
        for (checked.modules) |module| try std.testing.expect(module == null);
        try std.testing.expectEqualStrings(expected.code, checked.diagnostics[0].codeName());
        try std.testing.expectEqual(expected.start, checked.diagnostics[0].span.start);
    }
    var result = try partial.compileOwned(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency);
    defer result.deinit(allocator);
    const actual = result.result.diagnostic orelse return error.TestUnexpectedResult;
    try std.testing.expect(result.result.compiled.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.bytes.len);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.syntax_nodes);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.body_elaborations);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.body_lowerings);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.imported_schemes);
    try std.testing.expectEqualStrings(fixture.path, result.diagnostic_filename.?);
    try std.testing.expectEqualStrings(expected.stage, actual.stage);
    try std.testing.expectEqualStrings(expected.code, actual.code);
    try std.testing.expectEqual(expected.start, actual.start);
    try std.testing.expectEqual(expected.end, actual.end);
    try std.testing.expectEqualStrings(expected.message, actual.message);
    try std.testing.expectEqualDeep(expected.publication.?.utf16, actual.publication.?.utf16);
    try std.testing.expectEqual(expected.publication.?.actual_token, actual.publication.?.actual_token);
    try std.testing.expectEqualSlices(u8, expected.publication.?.details_json, actual.publication.?.details_json);
    // Frontend rejection must remain reusable, even in the consuming API.
    const after = try format.encode(allocator, key, dependency);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, fixture.bytes, after);
}
const numeric_sources = [_][]const u8{
    "entry const answer=identity 4294967296\n",
    "// 雪🙂\r\nentry const answer=identity 0x1_0000_0000\r\n",
    "entry const answer=fn()=>identity 1e999\n",
    "const untouched=fn()=>identity 42\nconst overflow=#Box 4294967296\nentry const answer:Unit->U32=fn()=>42\n",
};
test "partial fresh numeric validation retains source publication and cached generic nominal headers" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for (numeric_sources) |source| {
        try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = source });
        try numericRun(a, &fixture);
    }
}
test "partial fresh numeric rejection and preserved seed release all failed allocations" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for (numeric_sources) |source| {
        try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = source });
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, numericRun, .{&fixture});
    }
}

fn loaderRejectionRun(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.bytes, key);
    defer format.deinit(allocator, &dependency);
    const cases = [_]struct { options: project.Options, code: []const u8 }{
        .{ .options = .{ .prelude_path = fixture.prelude_path, .aliases = &.{.{ .prefix = "invalid", .root = "." }} }, .code = "invalid_alias" },
        .{ .options = .{ .prelude_path = fixture.prelude_path, .std_root = "" }, .code = "invalid_alias" },
        .{ .options = .{ .prelude_path = "" }, .code = "invalid_prelude" },
    };
    for (cases) |case_| {
        inline for (.{ false, true }) |consume| {
            var result = try (if (consume) partial.compileOwned else partial.compile)(allocator, std.testing.io, fixture.path, null, case_.options, &dependency);
            defer result.deinit(allocator);
            const issue = result.result.diagnostic orelse return error.TestUnexpectedResult;
            try std.testing.expectEqualStrings(case_.code, issue.code);
            try std.testing.expectEqualStrings(fixture.path, result.diagnostic_filename.?);
            try std.testing.expectEqual(@as(u32, 0), issue.unit);
            try std.testing.expectEqual(@as(usize, 0), result.cached_modules);
            try std.testing.expectEqual(@as(usize, 0), result.fresh_modules);
            try std.testing.expectEqual(@as(usize, 0), result.result.compiled.bytes.len);
            const unchanged = try format.encode(allocator, key, dependency);
            defer allocator.free(unchanged);
            try std.testing.expectEqualSlices(u8, fixture.bytes, unchanged);
        }
    }
}
test "partial loader rejection before seed installation owns diagnostics without consuming modules" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try loaderRejectionRun(a, &fixture);
}
test "partial initial loader rejection releases every failed allocation and preserves interfaces" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, loaderRejectionRun, .{&fixture});
}
