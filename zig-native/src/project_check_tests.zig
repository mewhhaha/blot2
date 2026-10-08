const std = @import("std");
const ast = @import("ast.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const check = @import("check.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const Source = struct { name: []const u8, text: []const u8 };
const named_scalar_shadow_source =
    \\infixl 60 `subtract`
    \\const subtract = fn left => fn right => @u32.sub left right
    \\entry const run = fn (subtract: U32) -> U32 => 20 `subtract` 22
;
const named_function_shadow_source =
    \\infixl 60 `combine`
    \\const combine = fn left => fn right => @u32.sub left right
    \\entry const run = fn () -> U32 => do:
    \\  let combine = fn left => fn right => @u32.add left right
    \\  return 20 `combine` 22
;
const symbolic_captured_target_source =
    \\infixl 60 (+) = subtract
    \\const subtract = fn left => fn right => @u32.sub left right
    \\entry const run = fn (subtract: U32) -> U32 => 20 + 22
;
const default_named_source =
    \\const combine = fn left => fn right => @u32.add left right
    \\entry const run = fn () -> U32 => 20 `combine` 22
;
const Fixture = struct {
    tmp: std.testing.TmpDir,
    path: [:0]u8,
    source: project.Project,

    fn init(sources: []const Source) !Fixture {
        return initWithPrelude(sources, null);
    }
    fn initWithPrelude(sources: []const Source, prelude: ?[]const u8) !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        for (sources) |source| try tmp.dir.writeFile(io, .{ .sub_path = source.name, .data = source.text });
        const canonical = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(canonical);
        const prelude_path = if (prelude) |path| try tmp.dir.realPathFileAlloc(io, path, a) else null;
        defer if (prelude_path) |path| a.free(path);
        var loaded = try project.load(a, io, canonical, .{ .prelude_path = prelude_path });
        errdefer loaded.deinit(a);
        return .{ .tmp = tmp, .path = canonical, .source = loaded };
    }
    fn deinit(self: *Fixture) void {
        self.source.deinit(a);
        a.free(self.path);
        self.tmp.cleanup();
    }
};
fn requireValid(checked: *const project_check.CheckedProject) !void {
    for (checked.diagnostics) |diagnostic| std.debug.print("Unit{d} {s} at{d}: {s}\n", .{ diagnostic.unit, diagnostic.codeName(), diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
fn exported(checked: *const project_check.CheckedProject, source: *const project.Project, unit: project.UnitId, name: []const u8) !check.ExternalTarget {
    for (checked.module(unit).exports) |value| if (std.mem.eql(u8, source.symbols.get(value.name), name)) return value.target;
    return error.MissingExport;
}
fn hasDiagnostic(checked: *const project_check.CheckedProject, code: []const u8, unit: project.UnitId) bool {
    for (checked.diagnostics) |diagnostic| if (diagnostic.unit == unit and std.mem.eql(u8, diagnostic.codeName(), code)) return true;
    return false;
}

test "tags on catalog declarations and fixities reject without evaluating tag expressions" {
    const sources = [_][]const u8{
        "@[missing_tag]\neffect Read: Unit -> U32\nentry const answer = 42\n",
        "@[missing_tag]\ntype Read is effect = Unit -> U32\nentry const answer = 42\n",
        "@[missing_tag]\ntype Box value is effect = {get: Unit -> value}\nentry const answer = 42\n",
        "@[missing_tag]\ntype Box value is data = #Box value\nentry const answer = 42\n",
        "@[missing_tag]\ninfixl 60 (+) = add\nconst add = fn left => fn right => @u32.add left right\nentry const answer = 40 + 2\n",
        "@[missing_tag]\ninfixl 60 `add`\nconst add = fn left => fn right => @u32.add left right\nentry const answer = 40 `add` 2\n",
    };
    for (sources) |text| {
        var fixture = try Fixture.init(&.{.{ .name = "main.blot", .text = text }});
        defer fixture.deinit();
        const original_nodes = try a.dupe(ast.Node, fixture.source.unit(1).tree.nodes.items);
        defer a.free(original_nodes);
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expect(hasDiagnostic(&checked, "unsupported_attribute", 1));
        try std.testing.expectEqualDeep(original_nodes, fixture.source.unit(1).tree.nodes.items);
    }
}

test "diamond modules publish one principal body and independently copy imported schemes" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text =
        \\import * as left from "./left"
        \\import * as right from "./right"
        \\import { twice as doubled } from "./shared"
        \\import * as common from "./shared"
        \\const integer = fn (value: U32) -> U32 => doubled value
        \\const floating = fn (value: F32) -> F32 => common.twice value
        \\entry const run = fn (value: U32) -> U32 => left.integer value
        },
        .{ .name = "left.blot", .text =
        \\import { twice, identity as id } from "./shared"
        \\const integer = fn (value: U32) -> U32 => twice (id value)
        },
        .{ .name = "right.blot", .text =
        \\import * as common from "./shared"
        \\const floating = fn (value: F32) -> F32 => common.twice (common.identity value)
        },
        .{ .name = "shared.blot", .text =
        \\infixl 60 (+) = _fixity_add
        \\const identity = fn value => value
        \\const twice = fn value => value + value
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
        },
    });
    defer fixture.deinit();
    const syntax_nodes = fixture.source.unit(1).tree.nodes.items.len;
    const symbols_count = fixture.source.symbols.entries.items.len;
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    try std.testing.expectEqual(@as(usize, 4), checked.modules.len);
    try std.testing.expectEqual(@as(usize, 8), checked.body_elaborations);
    // The private arithmetic producer is copied with its shared scheme.
    try std.testing.expectEqual(@as(usize, 11), checked.imported_schemes);
    try std.testing.expectEqual(syntax_nodes, fixture.source.unit(1).tree.nodes.items.len);
    try std.testing.expectEqual(symbols_count, fixture.source.symbols.entries.items.len);
    const shared = fixture.source.unitImports(2)[0].target;
    const twice = try exported(&checked, &fixture.source, shared, "twice");
    const principal = checked.interface(twice);
    try std.testing.expectEqual(@as(u32, 2), principal.scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), principal.scheme.obligations.len);
    try std.testing.expectEqual(@as(usize, 3), checked.module(shared).checked.body_elaborations);
    const main = &checked.module(1).checked;
    try std.testing.expectEqual(@as(usize, 5), main.imported_schemes);
    var matching: usize = 0;
    for (main.bindings) |binding| if (binding.external) |target| {
        if (std.meta.eql(target, twice)) {
            matching += 1;
            const root = main.types.node(binding.scheme.root);
            try std.testing.expectEqual(types.Tag.variable, main.types.node(root.a).tag);
            try std.testing.expectEqual(@as(u32, 2), binding.scheme.variables.len);
            try std.testing.expect(&main.types != principal.types.store);
        }
    };
    try std.testing.expectEqual(@as(usize, 1), matching);
}

test "same declaration spelling in distinct modules preserves foreign identities" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as left from \"./left\"\nimport * as right from \"./right\"\nconst integer = left.value\nconst floating = right.value\n" },
        .{ .name = "left.blot", .text = "const value = 42\n" },
        .{ .name = "right.blot", .text = "const value = 1.5\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    const integer = try exported(&checked, &fixture.source, 1, "integer");
    const floating = try exported(&checked, &fixture.source, 1, "floating");
    const main = &checked.module(1).checked;
    try std.testing.expectEqual(types.u32_type, main.bindings[integer.binding].ty);
    try std.testing.expectEqual(types.f32_type, main.bindings[floating.binding].ty);
    try std.testing.expectEqual(@as(usize, 2), main.imported_schemes);
    var targets: [2]check.ExternalTarget = undefined;
    var count: usize = 0;
    for (main.bindings) |binding| if (binding.external) |target| {
        targets[count] = target;
        count += 1;
    };
    try std.testing.expect(targets[0].unit != targets[1].unit);
}

test "imported generic constraints reject invalid uses at their own source site" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import { twice, integer } from \"./library\"\nconst bad = twice #True\nconst mismatch = integer #False\n" },
        .{ .name = "library.blot", .text = "infixl 60 (+) = _fixity_add\nconst twice = fn value => value + value\nconst integer = fn (value: U32) -> U32 => value\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    // The explicit generic producer retains Bool evidence for the reached
    // body proof; the independently annotated call fails during inference.
    const bad = try exported(&checked, &fixture.source, 1, "bad");
    const bad_scheme = checked.interface(bad).scheme;
    try std.testing.expect(bad_scheme.obligations.len != 0);
    try std.testing.expect(hasDiagnostic(&checked, "type_mismatch", 1));
    try std.testing.expectEqual(@as(usize, 3), checked.module(2).checked.body_elaborations);
    try std.testing.expectEqual(@as(usize, 3), checked.module(1).checked.imported_schemes);
    for (checked.diagnostics) |diagnostic| if (diagnostic.unit == 1)
        try std.testing.expect(diagnostic.span.end <= fixture.source.unit(1).source.len);
}

test "aliases reject collisions and missing exports including empty namespaces" {
    const invalid = [_][]const u8{
        "import * as name from \"./library\"\nimport * as name from \"./library\"\n",
        "import * as name from \"./library\"\nconst name = 1\n",
        "import { value as name } from \"./library\"\nimport * as name from \"./library\"\n",
        "import * as name from \"./library\"\nimport { value as name } from \"./library\"\n",
        "import { value as name, value as name } from \"./library\"\n",
        "import { value } from \"./library\"\nconst value = 1\n",
        "import * as name from \"./empty\"\nimport * as name from \"./empty\"\n",
    };
    for (invalid) |source| {
        var fixture = try Fixture.init(&.{ .{ .name = "main.blot", .text = source }, .{ .name = "library.blot", .text = "const value = 42\n" }, .{ .name = "empty.blot", .text = "" } });
        defer fixture.deinit();
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try std.testing.expect(hasDiagnostic(&checked, "duplicate_name", 1));
    }
    var fixture = try Fixture.init(&.{ .{ .name = "main.blot", .text = "import { absent } from \"./library\"\n" }, .{ .name = "library.blot", .text = "const value = 42\n" } });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try std.testing.expect(hasDiagnostic(&checked, "unknown_export", 1));
    const diagnostic = checked.diagnostics[0];
    try std.testing.expectEqualStrings("absent", fixture.source.unit(1).source[diagnostic.span.start..diagnostic.span.end]);
}

test "all unused module declarations are checked and dependency entries are forbidden" {
    const invalid = [_]Source{
        .{ .name = "library.blot", .text = "const unused = missing\n" },
        .{ .name = "library.blot", .text = "entry const private_host = fn () => 42\n" },
        .{ .name = "library.blot", .text = "effect Foreign: U32 -> U32\n" },
    };
    const codes = [_][]const u8{ "unknown_value", "entry_module", "sealed_effect" };
    for (invalid, codes) |library, code| {
        var fixture = try Fixture.init(&.{ .{ .name = "main.blot", .text = "import * as unused from \"./library\"\nentry const answer = fn () => 42\n" }, library });
        defer fixture.deinit();
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try std.testing.expect(hasDiagnostic(&checked, code, 2));
        try std.testing.expect(hasDiagnostic(&checked, "dependency_failed", 1));
        try std.testing.expect(!checked.module(2).valid);
    }
}

test "namespace names do not bypass lexical shadowing after a cached lookup" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as lib from \"./library\"\nconst first = fn () => lib.value\nconst second = fn (lib: U32) => lib.value\n" },
        .{ .name = "library.blot", .text = "const value = 42\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try std.testing.expect(hasDiagnostic(&checked, "missing_member", 1));
    var grouped = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as lib from \"./library\"\nentry const answer = fn () => (lib).value\n" },
        .{ .name = "library.blot", .text = "const value = 42\n" },
    });
    defer grouped.deinit();
    var admitted = try project_check.checkProject(a, &grouped.source);
    defer admitted.deinit(a);
    try requireValid(&admitted);
}

test "source cycles and malformed dependencies cannot publish interfaces" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as library from \"./library\"\n" },
        .{ .name = "library.blot", .text = "import * as main from \"./main\"\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try std.testing.expect(hasDiagnostic(&checked, "import_cycle", 2));
    try std.testing.expectEqual(@as(usize, 0), checked.modules.len);
}

test "imported operator targets and product schemes retain checked producer structure" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text =
        \\import * as arithmetic from "./library"
        \\infixl 60 (+) = arithmetic.subtract
        \\const integer_pair = arithmetic.duplicate 42
        \\const floating_pair = arithmetic.duplicate 1.5
        \\entry const answer = fn () -> U32 => 20 + 22
        \\const shadowed_operator = fn (arithmetic: Bool) -> U32 => 20 + 22
        },
        .{ .name = "library.blot", .text =
        \\const duplicate = fn value => (value, value)
        \\const subtract = fn (left: U32) => fn (right: U32) => @u32.sub left right
        },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    const main = &checked.module(1).checked;
    const integer = try exported(&checked, &fixture.source, 1, "integer_pair");
    const floating = try exported(&checked, &fixture.source, 1, "floating_pair");
    const integer_node = main.types.node(main.bindings[integer.binding].ty);
    const float_node = main.types.node(main.bindings[floating.binding].ty);
    try std.testing.expectEqual(types.Tag.product, integer_node.tag);
    try std.testing.expectEqual(types.Tag.product, float_node.tag);
    try std.testing.expectEqualSlices(types.Id, &.{ types.u32_type, types.u32_type }, main.types.list(.{ .start = integer_node.a, .len = integer_node.b }));
    try std.testing.expectEqualSlices(types.Id, &.{ types.f32_type, types.f32_type }, main.types.list(.{ .start = float_node.a, .len = float_node.b }));
    const subtract = try exported(&checked, &fixture.source, 2, "subtract");
    var calls: usize = 0;
    for (fixture.source.unit(1).tree.nodes.items, 0..) |node, index| if (node.tag == .binary) {
        const target = main.bindings[main.resolved[index]].external.?;
        try std.testing.expectEqual(subtract, target);
        calls += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), calls);
}

test "named fixity resolves lexical targets and symbolic fixity keeps its captured target" {
    var rejected = try Fixture.init(&.{.{ .name = "main.blot", .text = named_scalar_shadow_source }});
    defer rejected.deinit();
    var bad = try project_check.checkProject(a, &rejected.source);
    defer bad.deinit(a);
    try std.testing.expect(hasDiagnostic(&bad, "type_mismatch", 1));
    const bad_module = &bad.module(1).checked;
    for (rejected.source.unit(1).tree.nodes.items, 0..) |node, index| if (node.tag == .binary)
        try std.testing.expectEqual(check.Kind.parameter, bad_module.bindings[bad_module.resolved[index]].kind);

    const sources = [_][]const u8{ named_function_shadow_source, symbolic_captured_target_source, default_named_source };
    const kinds = [_]check.Kind{ .local, .global, .global };
    for (sources, kinds) |source, kind| {
        var fixture = try Fixture.init(&.{.{ .name = "main.blot", .text = source }});
        defer fixture.deinit();
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try requireValid(&checked);
        const module_ = &checked.module(1).checked;
        var count: usize = 0;
        for (fixture.source.unit(1).tree.nodes.items, 0..) |node, index| if (node.tag == .binary) {
            try std.testing.expectEqual(kind, module_.bindings[module_.resolved[index]].kind);
            try std.testing.expectEqual(types.u32_type, module_.expr_types[index]);
            count += 1;
        };
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

fn inheritedFixityScenario(allocator: std.mem.Allocator, source: *project.Project) !void {
    var checked = try project_check.checkProject(allocator, source);
    defer checked.deinit(allocator);
    try requireValid(&checked);
    const main = &checked.module(source.entry).checked;
    const producer = try exported(&checked, source, source.prelude_unit, "combine");
    var symbolic: usize = 0;
    var named: usize = 0;
    for (source.unit(source.entry).tree.nodes.items, 0..) |node, index| if (node.tag == .binary) {
        const binding = main.bindings[main.resolved[index]];
        if (std.mem.eql(u8, source.symbols.get(node.a), "%%")) {
            try std.testing.expectEqual(producer, binding.external.?);
            try std.testing.expectEqual(types.f32_type, main.expr_types[index]);
            symbolic += 1;
        } else {
            try std.testing.expectEqualStrings("combine", source.symbols.get(node.a));
            if (binding.external) |target| try std.testing.expect(!std.meta.eql(producer, target));
            try std.testing.expectEqual(types.u32_type, main.expr_types[index]);
            named += 1;
        }
    };
    try std.testing.expectEqual(@as(usize, 2), symbolic);
    try std.testing.expectEqual(@as(usize, 1), named);
    var copies: usize = 0;
    for (main.bindings) |binding| if (binding.external) |target| {
        if (std.meta.eql(producer, target)) copies += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), copies);
}

const inherited_fixity_prelude =
    \\infixl 60 (%%) = combine
    \\infixl 60 `combine`
    \\const combine = fn (left: F32) => fn (right: F32) => @f32.add left right
;
const inherited_fixity_uses =
    \\entry const floating = 1.5 %% 2.5
    \\entry const named = 40 `combine` 2
    \\entry const shadowed = fn (combine: Bool) => 1.5 %% 2.5
;

test "inherited symbolic fixities retain producer identity through local and imported target shadowing" {
    const shadows = [_][]const u8{
        "const combine = fn left => fn right => @u32.sub left right\n",
        "import { subtract as combine } from \"./library\"\n",
    };
    for (shadows) |shadow| {
        const text = try std.mem.concat(a, u8, &.{ shadow, inherited_fixity_uses });
        defer a.free(text);
        var fixture = try Fixture.initWithPrelude(&.{
            .{ .name = "main.blot", .text = text },
            .{ .name = "prelude.blot", .text = inherited_fixity_prelude },
            .{ .name = "library.blot", .text = "const subtract = fn left => fn right => @u32.sub left right\n" },
        }, "prelude.blot");
        defer fixture.deinit();
        const count = fixture.source.symbols.entries.items.len;
        const frozen = try a.dupe(ast.Node, fixture.source.unit(fixture.source.entry).tree.nodes.items);
        defer a.free(frozen);
        try inheritedFixityScenario(a, &fixture.source);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, inheritedFixityScenario, .{&fixture.source});
        try std.testing.expectEqual(count, fixture.source.symbols.entries.items.len);
        try std.testing.expectEqualDeep(frozen, fixture.source.unit(fixture.source.entry).tree.nodes.items);
    }
}

test "local symbolic redeclaration replaces inherited capture while named fixity remains lexical" {
    var fixture = try Fixture.initWithPrelude(&.{
        .{ .name = "main.blot", .text =
        \\infixl 60 (%%) = combine
        \\const combine = fn left => fn right => @u32.sub left right
        \\entry const answer = fn (combine: Bool) => 40 %% 2
        \\entry const invalid = fn (combine: Bool) => 40 `combine` 2
        },
        .{ .name = "prelude.blot", .text = inherited_fixity_prelude },
    }, "prelude.blot");
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try std.testing.expect(hasDiagnostic(&checked, "type_mismatch", fixture.source.entry));
    const main = &checked.module(fixture.source.entry).checked;
    var count: usize = 0;
    for (fixture.source.unit(fixture.source.entry).tree.nodes.items, 0..) |node, index| if (node.tag == .binary) {
        const binding = main.bindings[main.resolved[index]];
        const symbolic = std.mem.eql(u8, fixture.source.symbols.get(node.a), "%%");
        try std.testing.expectEqual(if (symbolic) check.Kind.global else check.Kind.parameter, binding.kind);
        try std.testing.expect(binding.external == null);
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "named imported targets obey aliases and local shadowing at each use" {
    const sources = [_][]const u8{
        "import { subtract as combine } from \"./library\"\ninfixl 60 `combine`\nentry const run = fn () -> U32 => 20 `combine` 22\n",
        "import * as arithmetic from \"./library\"\ninfixl 60 `arithmetic.subtract`\nentry const run = fn () -> U32 => 20 `arithmetic.subtract` 22\n",
    };
    for (sources) |source| {
        var fixture = try Fixture.init(&.{ .{ .name = "main.blot", .text = source }, .{ .name = "library.blot", .text = "const subtract = fn left => fn right => @u32.sub left right\n" } });
        defer fixture.deinit();
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try requireValid(&checked);
        const target = try exported(&checked, &fixture.source, 2, "subtract");
        const module_ = &checked.module(1).checked;
        for (fixture.source.unit(1).tree.nodes.items, 0..) |node, index| if (node.tag == .binary)
            try std.testing.expectEqual(target, module_.bindings[module_.resolved[index]].external.?);
    }
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import { subtract as combine } from \"./library\"\ninfixl 60 `combine`\nentry const run = fn (combine: U32) -> U32 => 20 `combine` 22\n" },
        .{ .name = "library.blot", .text = "const subtract = fn left => fn right => @u32.sub left right\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try std.testing.expect(hasDiagnostic(&checked, "type_mismatch", 1));
}

test "checked module type ownership survives release of every source and syntax owner" {
    var checked = semantic: {
        var fixture = try Fixture.init(&.{
            .{ .name = "main.blot", .text = "import * as lib from \"./library\"\nconst integer = lib.identity 42\nconst floating = lib.identity 1.5\n" },
            .{ .name = "library.blot", .text = "const identity = fn value => value\n" },
        });
        defer fixture.deinit();
        var result = try project_check.checkProject(a, &fixture.source);
        errdefer result.deinit(a);
        try requireValid(&result);
        break :semantic result;
    };
    defer checked.deinit(a);
    const main = &checked.module(1).checked;
    const producer = &checked.module(2).checked;
    try std.testing.expectEqual(@as(usize, 1), main.imported_schemes);
    for (main.bindings) |binding| if (binding.external) |target| {
        const interface = checked.interface(target);
        const root = main.types.node(binding.scheme.root);
        try std.testing.expectEqual(types.Tag.function, root.tag);
        try std.testing.expectEqual(root.a, root.b);
        try std.testing.expectEqual(types.Tag.variable, main.types.node(root.a).tag);
        try std.testing.expectEqual(@as(u32, 1), interface.scheme.variables.len);
        try std.testing.expect(interface.types.store == &producer.types);
        try std.testing.expect(interface.types.store != &main.types);
    };
}

test "foreign scheme imports scale with distinct targets rather than uses or aliases" {
    for ([_]usize{ 1, 16, 128 }) |count| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "import { identity as direct } from \"./library\"\nimport * as lib from \"./library\"\nentry const answer = fn () -> U32 => do:\n");
        for (0..count) |index| try text.appendSlice(a, if (index % 2 == 0) "  direct 42\n" else "  lib.identity 1.5\n");
        try text.appendSlice(a, "  return 42\n");
        var fixture = try Fixture.init(&.{
            .{ .name = "main.blot", .text = text.items },
            .{ .name = "library.blot", .text = "const identity = fn value => value\n" },
        });
        defer fixture.deinit();
        var checked = try project_check.checkProject(a, &fixture.source);
        defer checked.deinit(a);
        try requireValid(&checked);
        try std.testing.expectEqual(@as(usize, 2), checked.body_elaborations);
        try std.testing.expectEqual(@as(usize, 1), checked.imported_schemes);
        const region = &checked.module(1).checked.types;
        try std.testing.expect(region.nodes.items.len < 8 * count + 100);
        try std.testing.expect(region.versions.items.len < 5 * count + 100);
    }
}

fn allocationScenario(allocator: std.mem.Allocator, source: *project.Project) !void {
    var checked = try project_check.checkProject(allocator, source);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), checked.module(1).checked.imported_schemes);
}
test "module interfaces and aliases release every buffer after allocation failure" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import { identity as first } from \"./library\"\nimport * as lib from \"./library\"\nconst integer = first 42\nconst floating = lib.identity 1.5\nconst doubled = lib.twice 21\n" },
        .{ .name = "library.blot", .text = "infixl 60 (+) = _fixity_add\nconst identity = fn value => value\nconst twice = fn value => value + value\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n" },
    });
    defer fixture.deinit();
    const count = fixture.source.symbols.entries.items.len;
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{&fixture.source});
    try std.testing.expectEqual(count, fixture.source.symbols.entries.items.len);
}

test "imported nominal families and associated schemes preserve structured identity across aliases" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text =
        \\import * as left from "./points"
        \\import { Point as Position, Point as P } from "./points"
        \\import * as right from "./other"
        \\infixl 60 (+) = _fixity_add
        \\const coordinate = fn value => value.x
        \\const plus = fn a => fn b => a + b
        \\entry const answer = coordinate (plus (#left.Point {x:20}) (#P {x:22}))
        \\entry const floating = coordinate (#right.Point {x:1.25})
        \\const annotated = fn (value:Position) => value.x
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
        },
        .{ .name = "points.blot", .text =
        \\type Point is data = #Point {x:U32}
        \\const Point.add = fn left => fn right => #Point {x:@u32.add left.x right.x}
        },
        .{ .name = "other.blot", .text = "type Point is data = #Point {x:F32}\n" },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    const main = &checked.module(1).checked;
    try std.testing.expectEqual(@as(usize, 3), main.nominals.len);
    try std.testing.expect(main.nominals[1].identity.unit != main.nominals[2].identity.unit);
    try std.testing.expectEqual(@as(usize, 1), main.associated.len);
    const target = main.bindings[main.associated[0].binding].external.?;
    try std.testing.expectEqual(fixture.source.unitImports(1)[0].target, target.unit);
    // Three namespace/type/constructor aliases share one owned method scheme.
    try std.testing.expectEqual(@as(usize, 1), main.imported_schemes);
    const answer = try exported(&checked, &fixture.source, 1, "answer");
    const floating = try exported(&checked, &fixture.source, 1, "floating");
    try std.testing.expectEqual(types.u32_type, main.bindings[answer.binding].ty);
    try std.testing.expectEqual(types.f32_type, main.bindings[floating.binding].ty);
}

test "imported result and demand schemes keep owned quantified relations and numeric target identity" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text =
        \\import * as lib from "./library"
        \\import { convert as from, delay as suspend } from "./library"
        \\entry const integer=fn()=>do:
        \\  let #lib.Box value:lib.Box U32=from 42
        \\  return @force (suspend value)
        \\entry const floating=fn()=>do:
        \\  let #lib.Box value:lib.Box F32=lib.convert 1.25
        \\  return @force (lib.delay value)
        },
        .{ .name = "library.blot", .text =
        \\type Box value is data = #Box value
        \\const Box.from=fn value=>#Box value
        \\const convert=fn value=>@type.result "from" value
        \\const delay=fn ~value=>value
        },
    });
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    const consumer = &checked.module(1).checked;
    try std.testing.expectEqual(@as(usize, 3), consumer.imported_schemes);
    const integer = try exported(&checked, &fixture.source, 1, "integer");
    const floating = try exported(&checked, &fixture.source, 1, "floating");
    try std.testing.expectEqual(types.u32_type, consumer.types.node(consumer.bindings[integer.binding].ty).b);
    try std.testing.expectEqual(types.f32_type, consumer.types.node(consumer.bindings[floating.binding].ty).b);
    var found = false;
    for (consumer.bindings[1..]) |binding| if (binding.external != null) {
        const function = consumer.types.node(binding.scheme.root);
        if (function.tag == .function and consumer.types.node(function.a).tag == .demand) {
            const input = consumer.types.node(function.a);
            const output = consumer.types.node(function.b);
            try std.testing.expectEqual(types.Tag.demand, output.tag);
            try std.testing.expectEqual(consumer.types.node(input.a).a, consumer.types.node(output.a).a);
            try std.testing.expectEqualDeep(consumer.types.row(input.c).tail, consumer.types.row(output.c).tail);
            try std.testing.expectEqual(@as(u32, 1), binding.scheme.variables.len);
            found = true;
        }
    };
    try std.testing.expect(found);
}

test "generated monadic progress preserves designated prelude identity through local shadowing" {
    var fixture = try Fixture.initWithPrelude(&.{
        .{ .name = "main.blot", .text =
        \\type Iteration [state,result] is data = #LocalContinue state | #LocalDone result
        \\const sequence=fn()=>do (monad Maybe):
        \\  let total=0
        \\  for index in 0..3:
        \\    use value <- #Some 1
        \\    total:=@u32.add self value
        \\  return total
        \\entry const answer=fn()=>case sequence() of
        \\  #Some value=>value
        \\  #Nothing=>42
        },
        .{ .name = "prelude.blot", .text =
        \\type Iteration [state,result] is data = #Continue state | #Done result
        \\type Maybe value is data = #Some value | #Nothing
        \\const monad=fn constructor=>@do.monad constructor
        \\const Maybe.pure=fn value=>#Some value
        \\const Maybe.bind=fn candidate=>fn next=>case candidate of
        \\  #Some value=>next value
        \\  #Nothing=>#Nothing
        \\const Maybe.iterate=fn initial=>fn step=>do:
        \\  let state=initial
        \\  for ever:
        \\    use candidate <- step state
        \\    if let #Some (#Done result)=candidate:
        \\      return #Some result
        \\    let #Some (#Continue next)=candidate else:
        \\      return #Nothing
        \\    state:=next
        },
    }, "prelude.blot");
    defer fixture.deinit();
    var checked = try project_check.checkProject(a, &fixture.source);
    defer checked.deinit(a);
    try requireValid(&checked);
    const consumer = &checked.module(fixture.source.entry).checked;
    try std.testing.expectEqual(@as(usize, 1), consumer.resolver_loops.len);
    const loop = consumer.resolver_loops[0];
    try std.testing.expectEqual(fixture.source.prelude_unit, consumer.constructors[loop.continue_constructor].identity.unit);
    try std.testing.expectEqual(fixture.source.prelude_unit, consumer.constructors[loop.done_constructor].identity.unit);
    try std.testing.expect(fixture.source.entry != fixture.source.prelude_unit);
    try std.testing.expectEqual(fixture.source.prelude_unit, consumer.bindings[consumer.resolver_ops[loop.iterate - 1].method].external.?.unit);
}
