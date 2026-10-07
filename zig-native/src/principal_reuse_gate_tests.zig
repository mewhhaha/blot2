//! Gate laws use checked/lowered frozen Core, rather than mock admission flags.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("runtime_identity.zig");
const dependencies = @import("declaration_dependencies.zig");
const Gate = @import("principal_reuse_gate.zig").Gate;
const a = std.testing.allocator;

const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,

    fn init(allocator: std.mem.Allocator, sources: []const []const u8) !Fixture {
        const units = try allocator.alloc(core.Module, sources.len);
        errdefer allocator.free(units);
        var initialized: usize = 0;
        errdefer for (units[0..initialized]) |*unit| unit.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var first: ?check.Checked = null;
        defer if (first) |*checked| checked.deinit(allocator);
        for (sources, units, 0..) |source, *module, i| {
            var tokens = try lexer.lex(allocator, source);
            defer tokens.deinit(allocator);
            var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
            defer tree.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
            const imports: []const check.ImportedBinding = if (i == 0) &.{} else &.{.{
                .name = try pool.intern(allocator, "schema"),
                .target = .{ .unit = 1, .binding = target(&units[0], "schema").binding },
                .interface = .{ .types = .{ .store = &first.?.types }, .scheme = first.?.bindings[target(&units[0], "schema").binding].scheme, .obligations = first.?.obligations },
                .origin = 0,
            }};
            var checked = try check.checkModule(allocator, &tree, &pool, imports, &.{}, @intCast(i + 1));
            errdefer checked.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
            module.* = try core.lower(allocator, &tree, &pool, &checked);
            initialized += 1;
            try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
            if (i == 0) first = checked else checked.deinit(allocator);
        }
        var owners: [2]identity.Owner = undefined;
        try std.testing.expect(sources.len <= owners.len);
        for (owners[0..sources.len], 0..) |*owner, i| owner.* = .{ .unit = @intCast(i + 1), .path = if (i == 0) "/gate/producer.blot" else "/gate/consumer.blot" };
        return .{ .units = units, .names = try identity.Metadata.capture(allocator, &pool, owners[0..sources.len], sources.len) };
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        for (self.units) |*module| module.deinit(allocator);
        allocator.free(self.units);
        self.names.deinit(allocator);
        self.* = undefined;
    }
};

const Pinned = struct {
    /// Only the identity/module boundary is relevant to this admission helper;
    /// no evaluator, backend layout, slot or function pool participates.
    pools: artifacts.Pools,

    fn init(allocator: std.mem.Allocator, fixture: *Fixture) !Pinned {
        const pins = try allocator.alloc(artifacts.ModulePin, fixture.units.len);
        for (fixture.units, pins, 0..) |*module, *pin, i| pin.* = .{ .unit = @intCast(i + 1), .module = module, .canonical_path = @constCast(fixture.names.view().owner(@intCast(i + 1)).?), .stamp = artifacts.stamp(module.*) };
        var pools: artifacts.Pools = undefined;
        pools.project_identity = true;
        pools.identity = fixture.names;
        pools.modules = pins;
        return .{ .pools = pools };
    }

    fn deinit(self: *Pinned, allocator: std.mem.Allocator) void {
        allocator.free(self.pools.modules);
        self.* = undefined;
    }
};

fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies[1..]) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = module.unit, .binding = body.binding };
    unreachable;
}

fn root(module: *const core.Module, name: []const u8) core.Id {
    return module.body(target(module, name).binding).?.root;
}

fn recapture(module: *core.Module) !void {
    a.free(module.declaration_dependencies);
    a.free(module.dependency_references);
    a.free(module.dependency_members);
    module.declaration_dependencies = &.{};
    module.dependency_references = &.{};
    module.dependency_members = &.{};
    try dependencies.capture(a, module);
}

const independent =
    \\entry const schema: U32 = 7
    \\entry const builder = fn (value: U32) -> U32 => value
;
const direct_transitive =
    \\entry const schema: U32 = 7
    \\entry const direct: U32 = schema
    \\entry const transitive: U32 = direct
    \\entry const builder = fn (value: U32) -> U32 => value
;

const changed_function_producer =
    \\entry const schema = fn (value: U32) -> U32 => @u32.add value 7
    \\entry const builder = fn (value: U32) -> U32 => value
;
const changed_function_consumer =
    \\entry const dependent = fn (value: U32) -> U32 => schema value
    \\entry const safe = fn (value: U32) -> U32 => value
;
fn mutateFunction(fixture: *Fixture) !void {
    const node = fixture.units[0].nodes[root(&fixture.units[0], "schema")];
    try std.testing.expectEqual(core.Tag.scalar, node.tag);
    try std.testing.expectEqual(core.Tag.constant, fixture.units[0].nodes[node.b].tag);
    fixture.units[0].nodes[node.b].a = 8;
}
fn unaffectedModules(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var gate = try Gate.initWithExecution(allocator, old, current.units, current.names.view(), .{ .reuse_unaffected_modules = true, .reuse_equivalent_validation = true });
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!gate.structural_units[0] and gate.structural_units[1]);
    try std.testing.expectEqual(@as(usize, 3), gate.dependency_validations);
    try std.testing.expect(!gate.admits(target(&current.units[0], "schema")));
    try std.testing.expect(!gate.admits(target(&current.units[0], "builder")));
    try std.testing.expect(!gate.admits(target(&current.units[1], "dependent")));
    try std.testing.expect(gate.admits(target(&current.units[1], "safe")));
    const receipt = @import("specialization_receipt.zig");
    const Reads = struct {
        sources: []const core.BindingRef = &.{},
        scalar_reads: []const receipt.ScalarRead = &.{},
        call_reads: []const receipt.CallRead = &.{},
        call_publications: []const receipt.CallRead = &.{},
    };
    try std.testing.expect(gate.admitsReceipt(Reads{ .sources = &.{target(&current.units[1], "safe")} }));
    const changed = target(&current.units[0], "schema");
    try std.testing.expect(!gate.admitsReceipt(Reads{ .scalar_reads = &.{.{ .target = changed, .evidence = 3 }} }));
    try std.testing.expect(!gate.admitsReceipt(Reads{ .call_reads = &.{.{ .unit = changed.unit, .binding = changed.binding, .evidence = 3, .present = false }} }));
    try std.testing.expect(!gate.admitsReceipt(Reads{ .call_publications = &.{.{ .unit = changed.unit, .binding = changed.binding, .evidence = 3, .present = true }} }));
}
test "unaffected module queries survive function edits while changed owners transitive readers and proof publications invalidate" {
    var before = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer after.deinit(a);
    try mutateFunction(&after);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var baseline = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer baseline.deinit();
    try std.testing.expect(!baseline.enabled);
    try unaffectedModules(a, &pinned.pools, &after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, unaffectedModules, .{ &pinned.pools, &after });
}

test "unaffected module queries still validate current cross unit edges and reject changed semantic graphs and stale pins" {
    var before = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer after.deinit(a);
    try mutateFunction(&after);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    inline for (0..3) |variant| {
        const old_type = after.units[0].types.nodes[T.u32_type];
        const old_target = after.units[1].calls[0].target;
        const old_stamp = pinned.pools.modules[0].stamp;
        defer {
            after.units[0].types.nodes[T.u32_type] = old_type;
            after.units[1].calls[0].target = old_target;
            pinned.pools.modules[0].stamp = old_stamp;
        }
        if (variant == 0) after.units[0].types.nodes[T.u32_type].tag = .f32;
        if (variant == 1) after.units[1].calls[0].target.binding = std.math.maxInt(u32);
        if (variant == 2) pinned.pools.modules[0].stamp[0] ^= 1;
        var gate = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true, .reuse_equivalent_validation = true });
        defer gate.deinit();
        try std.testing.expect(!gate.enabled);
    }
}

fn admitted(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var gate = try Gate.init(allocator, old, current.units, current.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(gate.admits(target(&current.units[0], "builder")));
    try std.testing.expect(!gate.admits(target(&current.units[0], "schema")));
    try std.testing.expect(gate.structural_units[0]);
}

test "principal gate admits independent builder after scalar schema edit and cleans every allocation failure" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try admitted(a, &pinned.pools, &after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, admitted, .{ &pinned.pools, &after });
}

test "principal gate invalidates direct and transitive staged declaration dependencies" {
    var before = try Fixture.init(a, &.{direct_transitive});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{direct_transitive});
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    for ([_][]const u8{ "schema", "direct", "transitive" }) |name| try std.testing.expect(!gate.admits(target(&after.units[0], name)));
    try std.testing.expect(gate.admits(target(&after.units[0], "builder")));
    try std.testing.expect(!gate.admits(.{ .binding = target(&after.units[0], "builder").binding }));
    try std.testing.expect(!gate.admits(.{ .unit = 2, .binding = 1 }));
    try std.testing.expect(!gate.admits(.{ .unit = 1, .binding = std.math.maxInt(u32) }));
}

test "principal gate declines unchanged builders reading changed constants directly or transitively" {
    const source =
        \\entry const schema: U32 = 7
        \\entry const direct = fn (value: U32) -> U32 => schema
        \\entry const transitive = fn (value: U32) -> U32 => direct value
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!gate.admits(target(&after.units[0], "direct")));
    try std.testing.expect(!gate.admits(target(&after.units[0], "transitive")));
    try std.testing.expect(gate.admits(target(&after.units[0], "builder")));
}

test "principal gate rejects shared scalar IR roots and runtime scalar root edits" {
    inline for ([_]bool{ true, false }) |shared| {
        var before = try Fixture.init(a, &.{independent});
        defer before.deinit(a);
        var after = try Fixture.init(a, &.{independent});
        defer after.deinit(a);
        for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| {
            const scalar = root(module, "schema");
            if (shared) {
                const builder = target(module, "builder");
                module.bodies[module.bindings[builder.binding].body_id].root = scalar;
                try recapture(module);
            } else {
                const schema = target(module, "schema");
                module.bodies[module.bindings[schema.binding].body_id].runtime = true;
            }
        }
        after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
        var pinned = try Pinned.init(a, &before);
        defer pinned.deinit(a);
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer gate.deinit();
        try std.testing.expect(!gate.enabled);
    }
}

test "principal gate rejects a changed state-provider initial value" {
    const source =
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\entry const schema: U32 = 7
        \\entry const state = @effect.state (State.get U32) (State.set U32) 42
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    const state = after.units[0].nodes[root(&after.units[0], "state")];
    try std.testing.expectEqual(core.Tag.state_provider, state.tag);
    try std.testing.expectEqual(core.Tag.constant, after.units[0].nodes[state.c].tag);
    after.units[0].nodes[state.c].a = 43;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(!gate.enabled);
    try std.testing.expect(!gate.admits(target(&after.units[0], "builder")));
}

test "principal gate accepts no-op and revert while rejecting changes to function constants" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    after.units[0].nodes[root(&after.units[0], "schema")].a = 7;
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(gate.admits(target(&after.units[0], "schema")));
    try std.testing.expect(gate.admits(target(&after.units[0], "builder")));
    const fixture =
        \\entry const schema: U32 = 7
        \\entry const builder = fn (value: U32) -> U32 => 4
    ;
    var old_function = try Fixture.init(a, &.{fixture});
    defer old_function.deinit(a);
    var new_function = try Fixture.init(a, &.{fixture});
    defer new_function.deinit(a);
    var function_pin = try Pinned.init(a, &old_function);
    defer function_pin.deinit(a);
    new_function.units[0].nodes[root(&new_function.units[0], "builder")].a = 5;
    var declined = try Gate.init(a, &function_pin.pools, new_function.units, new_function.names.view());
    defer declined.deinit();
    try std.testing.expect(!declined.enabled);
}

test "principal gate propagates external alias and producer references across units" {
    const producer = "entry const schema: U32 = 7\n";
    const consumer =
        \\entry const direct: U32 = schema
        \\entry const transitive: U32 = direct
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{ producer, consumer });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ producer, consumer });
    defer after.deinit(a);
    var alias: core.BindingId = 0;
    for (before.units[1].bindings, 0..) |binding, i| if (binding.kind == .external) {
        alias = @intCast(i);
        break;
    };
    try std.testing.expect(alias != 0);
    // Exercise an explicit alias edge as well as the producer edge normally
    // emitted by lowering. Both are valid frozen Core producer references.
    for ([_]*core.Module{ &before.units[1], &after.units[1] }) |module| {
        module.references[0] = .{ .binding = alias };
        try recapture(module);
    }
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(gate.dirty[gate.offsets[1] + alias]);
    try std.testing.expect(!gate.admits(target(&after.units[1], "direct")));
    try std.testing.expect(!gate.admits(target(&after.units[1], "transitive")));
    try std.testing.expect(gate.admits(target(&after.units[1], "builder")));
}

test "principal gate preserves erased source dependency invalidation" {
    const source =
        \\entry const schema: U32 = 7
        \\entry const direct = fn (value: U32) -> U32 => schema
        \\entry const erased = @effect.of direct
        \\entry const transitive: U32 = @effect.count erased
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), before.units[0].erased_declaration_references.len);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!gate.admits(target(&after.units[0], "direct")));
    try std.testing.expect(!gate.admits(target(&after.units[0], "erased")));
    try std.testing.expect(!gate.admits(target(&after.units[0], "transitive")));
    try std.testing.expect(gate.admits(target(&after.units[0], "builder")));
}

test "principal gate rejects missing erased source metadata even when dependency recipes agree" {
    const source =
        \\entry const schema: U32 = 7
        \\entry const direct = fn (value: U32) -> U32 => schema
        \\entry const erased = @effect.of direct
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| {
        a.free(module.erased_declaration_references);
        module.erased_declaration_references = &.{};
        try recapture(module);
    }
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(!gate.enabled);
    try std.testing.expect(gate.structural_units[0]);
}

test "principal gate globally rejects dirty associated candidates and their transitive closure" {
    var before = try Fixture.init(a, &.{direct_transitive});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{direct_transitive});
    defer after.deinit(a);
    for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| module.associated = try a.dupe(core.Associated, &.{.{ .identity = .{ .unit = 1, .decl = 1 }, .member = 0, .operator = .add, .target = target(module, "transitive") }});
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(!gate.enabled);
    try std.testing.expect(!gate.admits(target(&after.units[0], "builder")));
    try std.testing.expect(gate.structural_units[0]);
}

test "principal gate rejects changed types catalog providers and runtime constants globally" {
    inline for (0..5) |mutation| {
        var before = try Fixture.init(a, &.{independent});
        defer before.deinit(a);
        var after = try Fixture.init(a, &.{independent});
        defer after.deinit(a);
        const schema = target(&after.units[0], "schema");
        switch (mutation) {
            0 => after.units[0].types.nodes[T.u32_type].a = 1,
            1 => after.units[0].associated = try a.dupe(core.Associated, &.{.{ .identity = .{ .unit = 1, .decl = 1 }, .member = 0, .operator = .add, .target = schema }}),
            2 => after.units[0].nodes[root(&after.units[0], "builder")].tag = .state_provider,
            3 => after.units[0].bodies[after.units[0].bindings[schema.binding].body_id].runtime = true,
            4 => after.units[0].names[0] = 'X',
            else => unreachable,
        }
        var pinned = try Pinned.init(a, &before);
        defer pinned.deinit(a);
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer gate.deinit();
        try std.testing.expect(!gate.enabled);
        try std.testing.expect(!gate.admits(target(&before.units[0], "builder")));
    }
}

test "principal gate rejects mutated pins missing metadata and malformed namespaces" {
    inline for (0..7) |mutation| {
        var before = try Fixture.init(a, &.{direct_transitive});
        defer before.deinit(a);
        var after = try Fixture.init(a, &.{direct_transitive});
        defer after.deinit(a);
        var pinned = try Pinned.init(a, &before);
        defer pinned.deinit(a);
        var names: ?identity.View = after.names.view();
        switch (mutation) {
            0 => before.units[0].nodes[root(&before.units[0], "schema")].a = 8,
            1 => names = null,
            2 => {
                before.names.owners[0].start = std.math.maxInt(u32);
                after.names.owners[0].start = std.math.maxInt(u32);
            },
            3 => {
                before.names.symbols[1] = before.names.symbols[2];
                after.names.symbols[1] = after.names.symbols[2];
            },
            4 => pinned.pools.modules[0].canonical_path = @constCast("/gate/wrong.blot"),
            5 => {
                after.units[0].declaration_dependencies[1].references.len = std.math.maxInt(u32);
                before.units[0].declaration_dependencies[1].references.len = std.math.maxInt(u32);
                pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
            },
            6 => {
                for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| {
                    const direct = target(module, "direct");
                    module.declaration_dependencies[module.bindings[direct.binding].body_id].references.len = 0;
                }
                pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
            },
            else => unreachable,
        }
        var gate = try Gate.init(a, &pinned.pools, after.units, names);
        defer gate.deinit();
        try std.testing.expect(!gate.enabled);
        try std.testing.expect(!gate.admits(target(&after.units[0], "builder")));
    }
}

const shared_query_gate = @import("shared_query_gate.zig");

fn shareGateFailure(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var source = try Gate.init(allocator, old, current.units, current.names.view());
    defer source.deinit();
    const enabled = source.enabled;
    const bytes = artifacts.stamp(.{ source.structural_units, source.offsets, source.dirty });
    var lease = shared_query_gate.share(allocator, old, current.units, &source) orelse return error.ExpectedLease;
    defer lease.deinit();
    try std.testing.expectEqualSlices(u8, &bytes, &artifacts.stamp(.{ lease.structural_units, lease.offsets, lease.dirty }));
    try std.testing.expectEqual(enabled, lease.enabled);
}

test "shared query gate preserves exact scalar dirty closure and independent strict importer admission" {
    var before = try Fixture.init(a, &.{direct_transitive});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{direct_transitive});
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var source = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer source.deinit();
    var lease = (shared_query_gate.share(a, &pinned.pools, after.units, &source)) orelse return error.ExpectedLease;
    defer lease.deinit();
    try std.testing.expect(lease.enabled and lease.structural_units[0]);
    for ([_][]const u8{ "schema", "direct", "transitive" }) |name| try std.testing.expect(!lease.admits(target(&after.units[0], name)));
    try std.testing.expect(lease.admits(target(&after.units[0], "builder")));
    var strict = try @import("artifact_import.zig").Importer.init(a, &pinned.pools, after.units, after.names.view(), after.units.len);
    defer strict.deinit();
    try std.testing.expect(strict.enabled);
    try std.testing.expect(!strict.stable[0]);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, shareGateFailure, .{ &pinned.pools, &after });
}

test "shared query gate refuses mismatched Pools Core and allocator owners before sharing" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var other = try Fixture.init(a, &.{independent});
    defer other.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var other_pin = try Pinned.init(a, &before);
    defer other_pin.deinit(a);
    var source = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer source.deinit();
    try std.testing.expect(shared_query_gate.share(a, &other_pin.pools, after.units, &source) == null);
    try std.testing.expect(shared_query_gate.share(a, &pinned.pools, other.units, &source) == null);
    try std.testing.expect(shared_query_gate.share(a, &pinned.pools, after.units[0..0], &source) == null);
    var never_allocate = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expect(shared_query_gate.share(never_allocate.allocator(), &pinned.pools, after.units, &source) == null);
    try std.testing.expectEqual(@as(usize, 0), never_allocate.alloc_index);
    try std.testing.expect(source.admits(target(&after.units[0], "builder")));
}

test "shared query gate owns its arrays through independent source and lease teardown" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var source = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    var source_live = true;
    defer if (source_live) source.deinit();
    var lease = (shared_query_gate.share(a, &pinned.pools, after.units, &source)) orelse return error.ExpectedLease;
    defer lease.deinit();
    var disposable = (shared_query_gate.share(a, &pinned.pools, after.units, &source)) orelse return error.ExpectedLease;
    disposable.deinit();
    try std.testing.expect(source.admits(target(&after.units[0], "builder")));
    source.deinit();
    source_live = false;
    try std.testing.expect(lease.admits(target(&after.units[0], "builder")));
    try std.testing.expectEqual(@as(usize, after.units.len), lease.structural_units.len);
}

test "shared query gate never strengthens disabled admission and new preparation detects old pin mutation" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    {
        var source = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer source.deinit();
        var lease = (shared_query_gate.share(a, &pinned.pools, after.units, &source)) orelse return error.ExpectedLease;
        defer lease.deinit();
        try std.testing.expect(lease.enabled);
    }
    // Every prior Gate is dead before changing this fixture for a new epoch.
    before.units[0].nodes[root(&before.units[0], "schema")].a = 9;
    var source = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer source.deinit();
    try std.testing.expect(!source.enabled);
    var lease = (shared_query_gate.share(a, &pinned.pools, after.units, &source)) orelse return error.ExpectedLease;
    defer lease.deinit();
    try std.testing.expect(!lease.enabled);
    try std.testing.expect(!lease.admits(target(&after.units[0], "builder")));
}

const query_importer = @import("artifact_import.zig").Importer;

test "semantic catalog identity survives body edits without granting executable owner identity" {
    const source =
        \\data Box a = #Box a
        \\type Read a is effect = Unit -> a
        \\entry const schema = fn (value: U32) -> U32 => @u32.add value 7
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    try mutateFunction(&after);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var other = try Pinned.init(a, &before);
    defer other.deinit(a);
    var gate = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true });
    defer gate.deinit();
    try std.testing.expect(gate.admitsCatalog(&pinned.pools, 1));
    try std.testing.expect(!gate.admitsCatalog(&other.pools, 1));
    try std.testing.expect(!gate.admitsCatalog(&pinned.pools, 0));
    try std.testing.expect(!gate.admitsCatalog(&pinned.pools, 2));
    try std.testing.expect(!gate.admits(target(&after.units[0], "builder")));
    var maps = (try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &gate)).?;
    defer maps.deinit();
    try std.testing.expect(maps.semantic_catalogs and !maps.stable[0]);
    var ordinary = try query_importer.init(a, &pinned.pools, after.units, after.names.view(), 1);
    defer ordinary.deinit();
    try std.testing.expect(!ordinary.semantic_catalogs and !ordinary.stable[0]);
}

test "semantic catalog admission rejects payload constructor and effect argument changes" {
    const old_source =
        \\data Choice = #First (List U32) | #Second (Array U32)
        \\type Read a is effect = Unit -> a
        \\entry const schema = fn (value: U32) -> U32 => @u32.add value 7
    ;
    const cases = [_][]const u8{
        "data Choice = #First (Array U32) | #Second (Array U32)\ntype Read a is effect = Unit -> a\nentry const schema = fn (value: U32) -> U32 => @u32.add value 7\n",
        "data Choice = #Second (Array U32) | #First (List U32)\ntype Read a is effect = Unit -> a\nentry const schema = fn (value: U32) -> U32 => @u32.add value 7\n",
        "data Choice = #First (List U32) | #Second (Array U32)\ntype Read a is effect = a -> a\nentry const schema = fn (value: U32) -> U32 => @u32.add value 7\n",
    };
    var before = try Fixture.init(a, &.{old_source});
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    for (cases) |source| {
        var after = try Fixture.init(a, &.{source});
        defer after.deinit(a);
        var gate = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true });
        defer gate.deinit();
        try std.testing.expect(!gate.admitsCatalog(&pinned.pools, 1));
        try std.testing.expect(try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &gate) == null);
    }
}

fn queryPreparationFailure(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var checked = try Gate.init(allocator, old, current.units, current.names.view());
    defer checked.deinit();
    const before = artifacts.stamp(.{ checked.structural_units, checked.offsets, checked.dirty });
    var prepared = (query_importer.initCheckedQuery(allocator, old, current.units, &checked) catch |err| {
        try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(.{ checked.structural_units, checked.offsets, checked.dirty }));
        try std.testing.expect(checked.admits(target(&current.units[0], "builder")));
        return err;
    }) orelse return error.ExpectedPreparedImporter;
    defer prepared.deinit();
    try std.testing.expect(prepared.enabled);
    try std.testing.expectEqualSlices(bool, checked.structural_units, prepared.stable);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(.{ checked.structural_units, checked.offsets, checked.dirty }));
}

test "checked query importer matches fresh query maps while strict fragments reject scalar edits" {
    var before = try Fixture.init(a, &.{direct_transitive});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{direct_transitive});
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer checked.deinit();
    var prepared = (try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &checked)) orelse return error.ExpectedPreparedImporter;
    defer prepared.deinit();
    var fresh = try query_importer.init(a, &pinned.pools, after.units, after.names.view(), after.units.len);
    defer fresh.deinit();
    try std.testing.expect(prepared.enabled and fresh.enabled);
    try std.testing.expect(!fresh.stable[0]);
    try std.testing.expectEqualSlices(u32, fresh.unit_map, prepared.unit_map);
    try std.testing.expectEqualSlices(u32, fresh.symbol_map, prepared.symbol_map);
    try std.testing.expectEqualSlices(u8, fresh.names.?.bytes, prepared.names.?.bytes);
    try std.testing.expect(prepared.names.?.bytes.ptr != fresh.names.?.bytes.ptr);
    for (fresh.stable, checked.structural_units) |*stable, structural| stable.* = structural;
    try std.testing.expectEqualSlices(bool, fresh.stable, prepared.stable);
    for ([_][]const u8{ "schema", "direct", "transitive" }) |name| try std.testing.expect(!checked.admits(target(&after.units[0], name)));
    try std.testing.expect(checked.admits(target(&after.units[0], "builder")));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, queryPreparationFailure, .{ &pinned.pools, &after });
}

test "checked query importer refuses wrong owners allocator and disabled gate without allocation" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var other = try Fixture.init(a, &.{independent});
    defer other.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var other_pin = try Pinned.init(a, &before);
    defer other_pin.deinit(a);
    var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer checked.deinit();
    try std.testing.expect(try query_importer.initCheckedQuery(a, &other_pin.pools, after.units, &checked) == null);
    try std.testing.expect(try query_importer.initCheckedQuery(a, &pinned.pools, other.units, &checked) == null);
    try std.testing.expect(try query_importer.initCheckedQuery(a, &pinned.pools, after.units[0..0], &checked) == null);
    var never_allocate = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expect(try query_importer.initCheckedQuery(never_allocate.allocator(), &pinned.pools, after.units, &checked) == null);
    try std.testing.expectEqual(@as(usize, 0), never_allocate.alloc_index);
    checked.enabled = false;
    try std.testing.expect(try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &checked) == null);
    var fresh = try query_importer.init(a, &pinned.pools, after.units, after.names.view(), after.units.len);
    defer fresh.deinit();
    try std.testing.expect(fresh.enabled and fresh.stable[0]);
}

test "checked query importer owns maps independently and new epoch rechecks changed pinned Core" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    {
        var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        var checked_live = true;
        defer if (checked_live) checked.deinit();
        var prepared = (try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &checked)) orelse return error.ExpectedPreparedImporter;
        defer prepared.deinit();
        var disposable = (try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &checked)) orelse return error.ExpectedPreparedImporter;
        disposable.deinit();
        checked.deinit();
        checked_live = false;
        try std.testing.expect(prepared.enabled and prepared.stable[0]);
        try std.testing.expectEqualSlices(u8, "/gate/producer.blot", prepared.names.?.view().owner(1).?);
    }
    // Prior checked facts/importers are all dead before the next compile epoch.
    const same_owner = &pinned.pools;
    before.units[0].nodes[root(&before.units[0], "schema")].a = 9;
    var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer checked.deinit();
    try std.testing.expect(same_owner == &pinned.pools and !checked.enabled);
    try std.testing.expect(try query_importer.initCheckedQuery(a, &pinned.pools, after.units, &checked) == null);
    var fresh = try query_importer.init(a, &pinned.pools, after.units, after.names.view(), after.units.len);
    defer fresh.deinit();
    try std.testing.expect(fresh.enabled and !fresh.stable[0]);
}

fn equivalentGate(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    const before_old = artifacts.stamp(old.modules[0].module.*);
    const before_current = artifacts.stamp(current.units);
    var ordinary = try Gate.init(allocator, old, current.units, current.names.view());
    defer ordinary.deinit();
    var reused = try Gate.initWithExecution(allocator, old, current.units, current.names.view(), .{ .reuse_equivalent_validation = true });
    defer reused.deinit();
    try std.testing.expectEqual(ordinary.enabled, reused.enabled);
    try std.testing.expectEqualSlices(bool, ordinary.structural_units, reused.structural_units);
    try std.testing.expectEqualSlices(usize, ordinary.offsets, reused.offsets);
    try std.testing.expectEqualSlices(bool, ordinary.dirty, reused.dirty);
    for (current.units, 0..) |module, unit| for (module.bindings, 0..) |_, binding| {
        const reference: core.BindingRef = .{ .unit = @intCast(unit + 1), .binding = @intCast(binding) };
        try std.testing.expectEqual(ordinary.admits(reference), reused.admits(reference));
    };
    if (ordinary.enabled) {
        try std.testing.expectEqual(current.units.len * 2, ordinary.dependency_validations);
        try std.testing.expectEqual(current.units.len, reused.dependency_validations);
    }
    try std.testing.expectEqualSlices(u8, &before_old, &artifacts.stamp(old.modules[0].module.*));
    try std.testing.expectEqualSlices(u8, &before_current, &artifacts.stamp(current.units));
}

test "equivalent validation preserves complete transitive gates and every allocation failure" {
    var before = try Fixture.init(a, &.{ direct_transitive, "entry const consumer: U32 = schema" });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ direct_transitive, "entry const consumer: U32 = schema" });
    defer after.deinit(a);
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try equivalentGate(a, &pinned.pools, &after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, equivalentGate, .{ &pinned.pools, &after });
}

test "equivalent validation admits only opaque isolated scalar payload changes" {
    const inputs = [_][]const u8{
        "entry const schema: U32 = 7\nentry const flag: Bool = #False\nentry const builder = fn (value: U32) -> U32 => value",
        "entry const schema: U32 = 7\nentry const fraction: F32 = 1.25\nentry const builder = fn (value: U32) -> U32 => value",
    };
    for (inputs, 0..) |input, index| {
        var before = try Fixture.init(a, &.{input});
        defer before.deinit(a);
        var after = try Fixture.init(a, &.{input});
        defer after.deinit(a);
        const scalar = root(&after.units[0], if (index == 0) "flag" else "fraction");
        after.units[0].nodes[scalar].a = if (index == 0) 1 else @bitCast(@as(f32, 2.5));
        var pinned = try Pinned.init(a, &before);
        defer pinned.deinit(a);
        try equivalentGate(a, &pinned.pools, &after);
        var checked = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
        defer checked.deinit();
        try std.testing.expect(checked.enabled);
        try std.testing.expect(!checked.admits(target(&after.units[0], if (index == 0) "flag" else "fraction")));
    }
}

test "equivalent validation rejects malformed equal dependency recipes after repinning" {
    var before = try Fixture.init(a, &.{direct_transitive});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{direct_transitive});
    defer after.deinit(a);
    const body = before.units[0].binding(target(&before.units[0], "direct").binding).body_id;
    before.units[0].declaration_dependencies[body].references.len = std.math.maxInt(u32);
    after.units[0].declaration_dependencies[body].references.len = std.math.maxInt(u32);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try equivalentGate(a, &pinned.pools, &after);
    var checked = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
    defer checked.deinit();
    try std.testing.expect(!checked.enabled);
    try std.testing.expectEqual(@as(usize, 1), checked.dependency_validations);
}

test "equivalent validation rechecks old pins and current nonpayload structure every epoch" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    before.units[0].nodes[root(&before.units[0], "schema")].a = 99;
    try equivalentGate(a, &pinned.pools, &after);
    {
        var rejected = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
        defer rejected.deinit();
        try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 0);
    }
    pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
    after.units[0].nodes[root(&after.units[0], "schema")].op = .add;
    try equivalentGate(a, &pinned.pools, &after);
    var rejected = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
    defer rejected.deinit();
    try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 0);
}

test "equivalent validation rejects bounds-valid equal cycles without accepting current graph" {
    var before = try Fixture.init(a, &.{independent});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{independent});
    defer after.deinit(a);
    for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| {
        const id = root(module, "builder");
        const old_node = module.nodes[id];
        const old_len = module.extra.len;
        const extra = try a.alloc(u32, old_len + 1);
        @memcpy(extra[0..old_len], module.extra);
        extra[old_len] = id;
        a.free(module.extra);
        module.extra = extra;
        module.nodes[id] = .{ .tag = .block, .ty = old_node.ty, .a = @intCast(old_len), .b = 1 };
        const views = [_]*const core.Module{module};
        try @import("frozen_core_validation.zig").validateBounds(module, .{ .units = &views, .symbol_count = before.names.view().symbols.len });
    }
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try equivalentGate(a, &pinned.pools, &after);
    var rejected = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
    defer rejected.deinit();
    try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 1);
}

test "equivalent validation retains mandatory erased source dependency checks" {
    const source =
        \\entry const schema: U32 = 7
        \\entry const direct = fn (value: U32) -> U32 => schema
        \\entry const erased = @effect.of direct
        \\entry const builder = fn (value: U32) -> U32 => value
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| {
        try std.testing.expectEqual(@as(usize, 1), module.erased_declaration_references.len);
        a.free(module.erased_declaration_references);
        module.erased_declaration_references = &.{};
        try recapture(module);
    }
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try equivalentGate(a, &pinned.pools, &after);
    var rejected = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_equivalent_validation = true });
    defer rejected.deinit();
    try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 1);
}

fn projectedPrincipals(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var gate = try Gate.initWithExecution(allocator, old, current.units, current.names.view(), .{ .reuse_unaffected_modules = true, .reuse_declaration_principals = true, .reuse_equivalent_validation = true });
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expectEqual(@as(usize, 3), gate.dependency_validations);
    const builder = target(&current.units[0], "builder");
    try std.testing.expect(gate.admitsPrincipal(builder));
    try std.testing.expect(!gate.admits(builder));
    try std.testing.expect(!gate.admitsPrincipal(target(&current.units[0], "schema")));
    try std.testing.expect(!gate.admitsPrincipal(target(&current.units[1], "dependent")));
    try std.testing.expect(gate.admitsPrincipal(target(&current.units[1], "safe")));
    var cloned = (@import("shared_query_gate.zig").share(allocator, old, current.units, &gate)).?;
    defer cloned.deinit();
    try std.testing.expect(cloned.admitsPrincipal(builder));
    try std.testing.expect(!cloned.admits(builder));
    try std.testing.expectEqualSlices(bool, gate.dirty, cloned.dirty);
}

test "declaration principal projection preserves an unchanged sibling and rejects edited producers and alias readers with allocation failure cleanup" {
    var before = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer after.deinit(a);
    try mutateFunction(&after);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try projectedPrincipals(a, &pinned.pools, &after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, projectedPrincipals, .{ &pinned.pools, &after });
}

test "declaration principal projection checks call arguments record destinations tags and binding metadata" {
    const source =
        \\data Pair = #Pair { left: U32, right: U32 }
        \\entry const identity = fn (value: U32) -> U32 => value
        \\entry const schema = fn (value: U32) -> U32 => identity (@u32.add value 7)
        \\entry const builder = fn (value: U32) => #Pair { left: value, right: 7 }
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{source});
    defer after.deinit(a);
    const projection = @import("declaration_projection.zig");
    const old = &before.units[0];
    const current = &after.units[0];
    const schema = target(current, "schema").binding;
    const builder = target(current, "builder").binding;
    try std.testing.expect(try projection.definitionEqual(a, old, current, schema));
    try std.testing.expect(try projection.definitionEqual(a, old, current, builder));
    const call = current.nodes[root(current, "schema")];
    try std.testing.expectEqual(core.Tag.call, call.tag);
    const argument = current.extra[call.b];
    const constant = current.nodes[argument].b;
    current.nodes[constant].a += 1;
    try std.testing.expect(!try projection.definitionEqual(a, old, current, schema));
    current.nodes[constant] = old.nodes[constant];
    current.extra[call.b] = constant;
    try std.testing.expect(!try projection.definitionEqual(a, old, current, schema));
    current.extra[call.b] = argument;
    const constructor = current.nodes[root(current, "builder")];
    try std.testing.expectEqual(core.Tag.construct, constructor.tag);
    const record = current.nodes[constructor.b];
    try std.testing.expectEqual(core.Tag.record, record.tag);
    std.mem.swap(u32, &current.extra[record.c], &current.extra[record.c + 1]);
    try std.testing.expect(!try projection.definitionEqual(a, old, current, builder));
    std.mem.swap(u32, &current.extra[record.c], &current.extra[record.c + 1]);
    a.free(current.tag_calls);
    current.tag_calls = try a.dupe(u32, &.{root(current, "schema")});
    try std.testing.expect(!try projection.definitionEqual(a, old, current, schema));
    a.free(current.tag_calls);
    current.tag_calls = &.{};
    const param = current.bodyParameters(current.body(schema).?)[0].binding;
    current.bindings[param].span.start += 1;
    try std.testing.expect(!try projection.definitionEqual(a, old, current, schema));
    current.bindings[param] = old.bindings[param];
    try std.testing.expect(try projection.definitionEqual(a, old, current, schema));
}

test "equivalent validation reuses unchanged local graphs only under equal foreign binding bounds" {
    var before = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer before.deinit(a);
    var after = try Fixture.init(a, &.{ changed_function_producer, changed_function_consumer });
    defer after.deinit(a);
    try mutateFunction(&after);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var reference = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true, .reuse_declaration_principals = true });
    defer reference.deinit();
    var optimized = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true, .reuse_declaration_principals = true, .reuse_equivalent_validation = true });
    defer optimized.deinit();
    try std.testing.expect(reference.enabled and optimized.enabled);
    try std.testing.expectEqual(@as(usize, 4), reference.dependency_validations);
    try std.testing.expectEqual(@as(usize, 3), optimized.dependency_validations);
    try std.testing.expectEqualSlices(bool, reference.dirty, optimized.dirty);
    // A valid, unused lexical binding changes the foreign bounds projection.
    // Even an unchanged consumer must then receive ordinary current validation.
    const bindings = after.units[0].bindings;
    const expanded = try a.alloc(core.Binding, bindings.len + 1);
    defer a.free(expanded);
    @memcpy(expanded[0..bindings.len], bindings);
    const parameter = for (bindings) |binding| {
        if (binding.kind == .parameter) break binding;
    } else unreachable;
    expanded[bindings.len] = parameter;
    expanded[bindings.len].target = .{ .unit = 1, .binding = @intCast(bindings.len) };
    after.units[0].bindings = expanded;
    defer after.units[0].bindings = bindings;
    var extended = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true, .reuse_declaration_principals = true, .reuse_equivalent_validation = true });
    defer extended.deinit();
    try std.testing.expect(extended.enabled);
    try std.testing.expectEqual(@as(usize, 4), extended.dependency_validations);
    after.units[0].bindings = bindings[0..1];
    var shortened = try Gate.initWithExecution(a, &pinned.pools, after.units, after.names.view(), .{ .reuse_unaffected_modules = true, .reuse_declaration_principals = true, .reuse_equivalent_validation = true });
    defer shortened.deinit();
    try std.testing.expect(!shortened.enabled);
}
