const std = @import("std");
const importer = @import("artifact_import.zig");
const artifacts = @import("code_artifacts.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const evidence = @import("type_evidence.zig");
const layout = @import("layout.zig");
const identity = @import("runtime_identity.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const a = std.testing.allocator;
const Allocator = std.mem.Allocator;

const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    field: u32,
    variable: u32,
    nominal: u32,
    operation: u32,
    fn init(shifted: bool) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        if (shifted) _ = try pool.intern(a, "unrelated");
        const source = "type Cell is data = #Cell { payload: U32 }\neffect Read: Unit -> U32\nconst generic = fn value => value\nconst read = fn () => Read ()\nentry const answer = fn () => 1\n";
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{});
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
        module.unit = 1;
        const variable: u32 = for (module.types.nodes, 0..) |node, i| {
            if (node.tag == .variable) break @intCast(i);
        } else unreachable;
        const nominal: u32 = for (module.nominals) |value| {
            if (value.identity.decl != 0) break value.identity.decl;
        } else unreachable;
        const operation: u32 = for (module.types.operations) |value| {
            if (value.identity.unit == 1 and value.identity.decl != 0) break value.identity.decl;
        } else unreachable;
        try std.testing.expect(module.types.effects.variable_count != 0);
        const names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/principal-import/producer.blot" }}, 1);
        return .{ .units = .{module}, .names = names, .field = try pool.intern(a, "payload"), .variable = variable, .nominal = nominal, .operation = operation };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
};
const Generator = struct {
    evaluator: eval.Session,
    layouts: layout.Store,
    fn init(allocator: Allocator, fixture: *const Fixture) !Generator {
        var evaluator = try eval.Session.init(allocator, &fixture.units);
        errdefer evaluator.deinit();
        return .{ .evaluator = evaluator, .layouts = try layout.Store.init(allocator) };
    }
    fn deinit(self: *Generator) void {
        self.layouts.deinit();
        self.evaluator.deinit();
    }
};
const Pinned = struct {
    pools: artifacts.Pools,
    fn init(fixture: *const Fixture, generator: *const Generator) !Pinned {
        const pins = try a.alloc(artifacts.ModulePin, 1);
        errdefer a.free(pins);
        pins[0] = .{ .unit = 1, .module = &fixture.units[0], .canonical_path = @constCast(fixture.names.view().owner(1).?), .stamp = artifacts.stamp(fixture.units[0]) };
        const fields = try a.alloc(artifacts.FieldLocation, generator.evaluator.field_locations.count());
        errdefer a.free(fields);
        var iterator = generator.evaluator.field_locations.iterator();
        var index: usize = 0;
        while (iterator.next()) |entry| : (index += 1) fields[index] = .{ .family = entry.key_ptr.family, .tag = entry.key_ptr.tag, .name = entry.key_ptr.name, .field = entry.value_ptr.field, .len = entry.value_ptr.len };
        // This test pin owns every pool the principal importer reads. Identity
        // and immutable Core remain owned by the enclosing fixture.
        var pools: artifacts.Pools = undefined;
        pools.dependency_certificate = null;
        pools.project_identity = true;
        pools.identity = fixture.names;
        pools.modules = pins;
        pools.field_locations = fields;
        pools.evaluator = try generator.evaluator.copySnapshot(a);
        return .{ .pools = pools };
    }
    fn deinit(self: *Pinned) void {
        self.pools.evaluator.deinit(a);
        a.free(self.pools.field_locations);
        a.free(self.pools.modules);
    }
};
const Inputs = struct { demand: u32, row: u32, unsupported: [7]u32, state_row: u32, nested_state: u32 };
fn inputs(generator: *Generator, fixture: *const Fixture) !Inputs {
    const store = &generator.evaluator.evidence;
    const record = try store.intern(.record, 0, 0, &.{ fixture.field, 3 });
    const nominal = try store.intern(.nominal, 1, fixture.nominal, &.{});
    const product = try store.intern(.product, 0, 0, &.{ record, nominal });
    const operation = try store.effects.internOperation(.{ .unit = 1, .decl = fixture.operation }, &.{record});
    const row = try store.effects.internRow(&.{ operation, operation });
    const function = try store.internWithEffects(.function, record, product, row, &.{});
    const demand = try store.internWithEffects(.demand, function, 0, row, &.{});
    const read = try store.intern(.nominal, std.math.maxInt(u32), 1, &.{3});
    const write = try store.intern(.nominal, std.math.maxInt(u32), 2, &.{3});
    const type_constructor = try store.intern(.type_constructor, 1, fixture.nominal, &.{});
    const resolver = try store.intern(.resolver, type_constructor, 0, &.{});
    const effect = try store.intern(.nominal, 1, fixture.operation, &.{record});
    const provider = try store.intern(.provider, effect, 0, &.{});
    const state_operation = try store.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = 1 }, &.{3});
    const state_row = try store.effects.internRow(&.{state_operation});
    return .{
        .demand = demand,
        .row = row,
        .unsupported = .{ read, type_constructor, resolver, provider, try store.internStateProvider(read, write, 3), try store.intern(.nominal, 999, 1, &.{}), try store.intern(.array, resolver, 0, &.{}) },
        .state_row = state_row,
        .nested_state = try store.internWithEffects(.function, 3, 3, state_row, &.{}),
    };
}
fn importScenario(allocator: Allocator, old: *const artifacts.Pools, input: Inputs, fixture: *const Fixture) !void {
    const old_stamp = artifacts.stamp(old.evaluator.evidence);
    defer std.debug.assert(std.mem.eql(u8, &old_stamp, &artifacts.stamp(old.evaluator.evidence)));
    var generator = try Generator.init(allocator, fixture);
    defer generator.deinit();
    const prior = try generator.evaluator.evidence.intern(.array, 4, 0, &.{});
    const values = generator.evaluator.values.items.len;
    var graphs = try importer.Importer.init(allocator, old, &fixture.units, fixture.names.view(), 1);
    defer graphs.deinit();
    try std.testing.expect(graphs.stable[0]);
    var solved = (try graphs.importPrincipalEvidence(&generator, 1, &.{.{ .variable = fixture.variable, .evidence = input.demand }}, &.{.{ .variable = 0, .evidence = input.row }})).?;
    defer solved.deinit(allocator);
    const store = &generator.evaluator.evidence;
    try std.testing.expectEqual(fixture.variable, solved.types[0].variable);
    const demand = store.node(solved.types[0].evidence);
    try std.testing.expectEqual(evidence.Tag.demand, demand.tag);
    const function = store.node(demand.a);
    try std.testing.expectEqual(evidence.Tag.function, function.tag);
    const call_target: core.BindingRef = .{ .unit = 1, .binding = fixture.units[0].bodies[1].binding };
    const old_arrow = old.evaluator.evidence.view().node(input.demand).a;
    try std.testing.expectEqual(@as(?u32, demand.a), try graphs.importPrincipalCall(&generator, call_target, old_arrow));
    try std.testing.expectEqualSlices(u32, &.{ fixture.field, 3 }, store.children(function.a));
    const children = store.children(function.b);
    try std.testing.expectEqual(@as(u32, 1), store.node(children[1]).a);
    const labels = store.effects.view().rowLabels(solved.rows[0].evidence);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(@as(u32, 0), solved.rows[0].variable);
    try std.testing.expectEqual(solved.rows[0].evidence, demand.c);
    try std.testing.expectEqual(evidence.Tag.array, store.node(prior).tag);
    try std.testing.expectEqual(@as(u32, 4), store.node(prior).a);
    try std.testing.expectEqual(values, generator.evaluator.values.items.len);
    try std.testing.expectEqual(@as(usize, 0), generator.evaluator.validated_calls.count());
    var empty = (try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{})).?;
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.types.len);
    try std.testing.expectEqual(@as(usize, 0), empty.rows.len);
    var empty_row = (try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{.{ .variable = 0, .evidence = 0 }})).?;
    defer empty_row.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), empty_row.rows[0].evidence);
}
test "principal import owns remapped closed graphs and releases every failed allocation after producer teardown" {
    var before = try Fixture.init(false);
    defer before.deinit();
    var after = try Fixture.init(true);
    defer after.deinit();
    var producer = try Generator.init(a, &before);
    const input = inputs(&producer, &before) catch |err| {
        producer.deinit();
        return err;
    };
    var pinned = Pinned.init(&before, &producer) catch |err| {
        producer.deinit();
        return err;
    };
    producer.deinit();
    defer pinned.deinit();
    try importScenario(a, &pinned.pools, input, &after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importScenario, .{ &pinned.pools, input, &after });
}
test "principal import declines duplicate foreign-owner malformed and nested State facts without publishing evidence" {
    var fixture = try Fixture.init(false);
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const input = try inputs(&producer, &fixture);
    var pinned = try Pinned.init(&fixture, &producer);
    defer pinned.deinit();
    var generator = try Generator.init(a, &fixture);
    defer generator.deinit();
    var graphs = try importer.Importer.init(a, &pinned.pools, &fixture.units, fixture.names.view(), 1);
    defer graphs.deinit();
    const nodes = generator.evaluator.evidence.nodes.items.len;
    const rows = generator.evaluator.evidence.effects.rows.items.len;
    for ([_]u32{ 0, 3, @intCast(fixture.units[0].types.nodes.len) }) |variable|
        try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{.{ .variable = variable, .evidence = 3 }}, &.{})) == null);
    const mapping: evidence.Mapping = .{ .variable = fixture.variable, .evidence = 3 };
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{ mapping, mapping }, &.{})) == null);
    const row: evidence.RowMapping = .{ .variable = 0, .evidence = input.row };
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{ row, row })) == null);
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{.{ .variable = fixture.units[0].types.effects.variable_count, .evidence = 0 }})) == null);
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{.{ .variable = 0, .evidence = layout.unknown_row }})) == null);
    for ([_]u32{ 0, 2 }) |owner|
        try std.testing.expect((try graphs.importPrincipalEvidence(&generator, owner, &.{mapping}, &.{})) == null);
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{.{ .variable = fixture.variable, .evidence = 0 }}, &.{})) == null);
    for (input.unsupported) |value|
        try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{.{ .variable = fixture.variable, .evidence = value }}, &.{})) == null);
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{}, &.{.{ .variable = 0, .evidence = input.state_row }})) == null);
    try std.testing.expect((try graphs.importPrincipalEvidence(&generator, 1, &.{.{ .variable = fixture.variable, .evidence = input.nested_state }}, &.{})) == null);
    const call_target: core.BindingRef = .{ .unit = 1, .binding = fixture.units[0].bodies[1].binding };
    try std.testing.expect((try graphs.importPrincipalCall(&generator, call_target, input.nested_state)) == null);
    try std.testing.expect((try graphs.importPrincipalCall(&generator, call_target, 3)) == null);
    try std.testing.expect((try graphs.importPrincipalCall(&generator, .{ .unit = 1, .binding = 0 }, input.demand)) == null);
    try std.testing.expectEqual(nodes, generator.evaluator.evidence.nodes.items.len);
    try std.testing.expectEqual(rows, generator.evaluator.evidence.effects.rows.items.len);
}
