//! Gate laws use checked/lowered frozen Core, rather than mock admission flags.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("../backend/runtime_identity.zig");
const dependencies = @import("declaration_dependencies.zig");
const Gate = @import("principal_reuse_gate.zig").Gate;
const a = std.testing.allocator;

test "call identity ignores unrelated source positions but rejects its own movement and changed source" {
    const source =
        \\entry const earlier = fn (x: U32) -> U32 => @u32.add x 1
        \\entry const edited = fn (x: U32) -> U32 => @u32.add x 2
        \\entry const later = fn (x: U32) -> U32 => @u32.add x 3
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    const changed = try std.mem.replaceOwned(u8, a, source, "@u32.add x 2", "@u32.add x 20");
    defer a.free(changed);
    var after = try Fixture.init(a, &.{changed});
    defer after.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!@import("../structural.zig").equal(before.units[0].source_names, after.units[0].source_names));
    const earlier = target(&after.units[0], "earlier");
    const edited = target(&after.units[0], "edited");
    const later = target(&after.units[0], "later");
    try std.testing.expect(gate.admitsLocalSource(earlier));
    try std.testing.expect(gate.admitsCallIdentity(edited));
    try std.testing.expect(!gate.admitsLocalSource(edited));
    try std.testing.expectEqual(Gate.IdentityFailure.source_position, gate.callIdentityFailure(later));
    var moved = try Fixture.init(a, &.{"\n" ++ source});
    defer moved.deinit(a);
    var shifted = try Gate.init(a, &pinned.pools, moved.units, moved.names.view());
    defer shifted.deinit();
    try std.testing.expectEqual(Gate.IdentityFailure.source_position, shifted.callIdentityFailure(earlier));
}

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
        for (fixture.units, pins, 0..) |*module, *pin, i| pin.* = artifacts.ModulePin.validated(@intCast(i + 1), module, @constCast(fixture.names.view().owner(@intCast(i + 1)).?));
        var pools: artifacts.Pools = undefined;
        pools.dependency_certificate = null;
        pools.project_identity = true;
        pools.identity = fixture.names;
        pools.modules = pins;
        return .{ .pools = pools };
    }

    fn deinit(self: *Pinned, allocator: std.mem.Allocator) void {
        if (self.pools.dependency_certificate) |*certificate| certificate.deinit(allocator);
        allocator.free(self.pools.modules);
        self.* = undefined;
    }
};

fn certify(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture, pins: []const artifacts.ModulePin) !void {
    var gate = try Gate.init(allocator, old, current.units, current.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled and gate.dependencies_validated);
    var certificate = (try gate.freezeValidation(allocator, pins)).?;
    defer certificate.deinit(allocator);
    try std.testing.expectEqual(pins.len, certificate.record.dependencies.modules.len);
}

test "source validation certificates reject exact graph namespace producer order and foreign bound mutations despite unchanged stamps" {
    var before = try Fixture.init(a, &.{ independent, "entry const safe = fn (value:U32) => value\n" });
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var gate = try Gate.init(a, &pinned.pools, before.units, before.names.view());
    defer gate.deinit();
    var certificate = (try gate.freezeValidation(a, pinned.pools.modules)).?;
    defer certificate.deinit(a);
    const units = [_]*const core.Module{ &before.units[0], &before.units[1] };
    const context: @import("../check/frozen_core_validation.zig").Context = .{ .units = &units, .symbol_count = before.names.symbols.len };
    try std.testing.expect(certificate.matches(context, before.names.view(), context.units));
    try std.testing.expect(certificate.admits(0, pinned.pools.modules[0]));
    try std.testing.expect(!certificate.admits(0, pinned.pools.modules[1]));
    try std.testing.expect(!certificate.admits(2, pinned.pools.modules[0]));
    var changed_bounds = context;
    changed_bounds.symbol_count = context.symbol_count.? + 1;
    try std.testing.expect(!certificate.matches(changed_bounds, before.names.view(), context.units));
    changed_bounds = context;
    changed_bounds.source_length = 1;
    try std.testing.expect(!certificate.matches(changed_bounds, before.names.view(), context.units));
    const binding_owner = before.units[1].bindings;
    before.units[1].bindings = binding_owner[0 .. binding_owner.len - 1];
    try std.testing.expect(!certificate.matches(context, before.names.view(), context.units));
    before.units[1].bindings = binding_owner;
    const spelling = before.names.bytes[0];
    before.names.bytes[0] ^= 1;
    try std.testing.expect(!certificate.matches(context, before.names.view(), context.units));
    before.names.bytes[0] = spelling;
    std.mem.swap(@TypeOf(before.names.symbols[0]), &before.names.symbols[1], &before.names.symbols[2]);
    try std.testing.expect(!certificate.matches(context, before.names.view(), context.units));
    std.mem.swap(@TypeOf(before.names.symbols[0]), &before.names.symbols[1], &before.names.symbols[2]);
    var renamed = pinned.pools.modules[0];
    renamed.canonical_path = @constCast("/forged/producer.blot");
    try std.testing.expect(!certificate.admits(0, renamed));
    const node = root(&before.units[0], "schema");
    const payload = before.units[0].nodes[node].a;
    before.units[0].nodes[node].a ^= 1;
    // Deliberately leave the public fingerprint unchanged. Exact stored bytes
    // still detect mutation of the previously validated immutable graph.
    try std.testing.expect(!certificate.admits(0, pinned.pools.modules[0]));
    before.units[0].nodes[node].a = payload;
    try std.testing.expect(certificate.admits(0, pinned.pools.modules[0]));
    try std.testing.expect(certificate.matches(context, before.names.view(), context.units));
    const Certificate = @import("dependency_certificate.zig").Certificate;
    try std.testing.expect((try Certificate.captureWithBudget(a, context, pinned.pools.modules, before.names.view(), 0)) == null);
    try std.testing.expect((try Certificate.captureWithBudget(a, context, pinned.pools.modules, before.names.view(), 1024)) == null);
}

test "published dependency validation certificates retain exact graphs context and failure ownership" {
    const consumer = "entry const dependent: U32 = schema\nentry const safe = fn (value: U32) => value\n";
    var before = try Fixture.init(a, &.{ independent, consumer });
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, certify, .{ &pinned.pools, &before, pinned.pools.modules });
    var initial = try Gate.init(a, &pinned.pools, before.units, before.names.view());
    defer initial.deinit();
    try std.testing.expect(initial.enabled);
    pinned.pools.dependency_certificate = (try initial.freezeValidation(a, pinned.pools.modules)).?;
    var current = try Fixture.init(a, &.{ independent, consumer });
    defer current.deinit(a);
    current.units[0].nodes[root(&current.units[0], "schema")].a = 8;
    var admitted_ = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer admitted_.deinit();
    try std.testing.expect(admitted_.enabled);
    try std.testing.expectEqual(@as(usize, 0), admitted_.dependency_validations);
    try std.testing.expectEqual(@as(usize, 2), admitted_.reused_dependency_validations);
    try std.testing.expect(!admitted_.admits(target(&current.units[0], "schema")));

    // Changing a validator input revokes the certificate even if all pins
    // match. Restore it and it can still be used after this discarded attempt.
    pinned.pools.dependency_certificate.?.record.key.symbol_count = 0;
    var uncached = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer uncached.deinit();
    try std.testing.expect(uncached.enabled);
    try std.testing.expectEqual(@as(usize, 2), uncached.dependency_validations);
    pinned.pools.dependency_certificate.?.record.key.symbol_count = before.names.view().symbols.len;

    // A changed retained graph cannot be hidden by replacing its public pin.
    // The certificate owns the digest of the graph actually validated.
    const node = root(&before.units[0], "schema");
    const saved = before.units[0].nodes[node];
    before.units[0].nodes[node].ty = std.math.maxInt(u32);
    pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
    current.units[0].nodes[node] = before.units[0].nodes[node];
    var corrupt = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer corrupt.deinit();
    try std.testing.expect(!corrupt.enabled and !corrupt.dependencies_validated);
    try std.testing.expect((try corrupt.freezeValidation(a, pinned.pools.modules)) == null);
    before.units[0].nodes[node] = saved;
}

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
    var gate = try Gate.init(allocator, old, current.units, current.names.view());
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
    try unaffectedModules(a, &pinned.pools, &after);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, unaffectedModules, .{ &pinned.pools, &after });
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
        if (variant == 2) pinned.pools.modules[0].stamp.?[0] ^= 1;
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, admitted, .{ &pinned.pools, &after });
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
        try std.testing.expect(!gate.admitsPrincipal(target(&after.units[0], "schema")));
        if (shared) try std.testing.expect(!gate.admitsPrincipal(target(&after.units[0], "builder")));
    }
}

test "principal gate rejects a changed state-provider initial value and its consumers only" {
    const source =
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\entry const schema: U32 = 7
        \\entry const state = @effect.state (State.get U32) (State.set U32) 42
        \\entry const builder = fn (value: U32) -> U32 => value
        \\entry const consumer = fn () => do:
        \\  let (_, old) = do state:
        \\    break State.get U32 ()
        \\  break old
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
    // The operation catalog is unchanged; the provider's initial value is
    // projected through its own declaration and reaches only its consumers.
    // The edited module still declines whole-module executable admission.
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!gate.admitsPrincipal(target(&after.units[0], "state")));
    try std.testing.expect(!gate.admitsPrincipal(target(&after.units[0], "consumer")));
    try std.testing.expect(gate.admitsPrincipal(target(&after.units[0], "builder")));
    try std.testing.expect(gate.admitsPrincipal(target(&after.units[0], "schema")));
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
    try std.testing.expect(!declined.admitsPrincipal(target(&new_function.units[0], "builder")));
    try std.testing.expect(declined.admitsPrincipal(target(&new_function.units[0], "schema")));
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

const selecting =
    \\type Pair is data = #Pair { left: U32, right: U32 }
    \\entry const schema: U32 = 7
    \\entry const direct: U32 = schema
    \\entry const transitive: U32 = direct
    \\entry const builder = fn (value: U32) -> U32 => value
    \\entry const doubled: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
    \\entry const user = fn (value: U32) -> U32 => doubled value
    \\entry const projected = fn (pair: Pair) -> U32 => pair.left
    \\entry const reader = fn (pair: Pair) -> U32 => projected pair
;
fn symbolId(names: identity.View, spelling: []const u8) u32 {
    for (1..names.symbols.len) |id| if (std.mem.eql(u8, names.symbol(@intCast(id)).?, spelling)) return @intCast(id);
    unreachable;
}
fn selectionScenario(allocator: std.mem.Allocator, member: []const u8, operator: T.Operator) !void {
    var before = try Fixture.init(allocator, &.{selecting});
    defer before.deinit(allocator);
    var after = try Fixture.init(allocator, &.{selecting});
    defer after.deinit(allocator);
    const name = if (member.len == 0) 0 else symbolId(before.names.view(), member);
    for ([_]*core.Module{ &before.units[0], &after.units[0] }) |module| module.associated = try allocator.dupe(core.Associated, &.{.{ .identity = .{ .unit = 1, .decl = 1 }, .member = name, .operator = operator, .target = target(module, "transitive") }});
    after.units[0].nodes[root(&after.units[0], "schema")].a = 8;
    var pinned = try Pinned.init(allocator, &before);
    defer pinned.deinit(allocator);
    var gate = try Gate.init(allocator, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    // The dirty candidate dirties only the bodies resolving its key and
    // their readers; their own sources stay admitted for receipts.
    try std.testing.expect(gate.enabled and gate.structural_units[0]);
    try std.testing.expect(!gate.admits(target(&after.units[0], "transitive")));
    try std.testing.expect(gate.admits(target(&after.units[0], "builder")));
    const add = std.mem.eql(u8, member, "add");
    const left = std.mem.eql(u8, member, "left");
    try std.testing.expectEqual(!add, gate.admits(target(&after.units[0], "doubled")));
    try std.testing.expectEqual(!add, gate.admits(target(&after.units[0], "user")));
    try std.testing.expectEqual(!left, gate.admits(target(&after.units[0], "projected")));
    try std.testing.expectEqual(!left, gate.admits(target(&after.units[0], "reader")));
    try std.testing.expect(gate.admitsLocalSource(target(&after.units[0], "doubled")));
    try std.testing.expect(gate.admitsLocalSource(target(&after.units[0], "projected")));
}
test "principal gate dirties the declarations that may select a dirty associated candidate" {
    // A named member resolved by @type.call, a field-syntax member that the
    // published recipe does not list, and an operator nothing here resolves.
    try selectionScenario(a, "add", .none);
    try selectionScenario(a, "left", .none);
    try selectionScenario(a, "", .add);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, selectionScenario, .{ @as([]const u8, "left"), T.Operator.none });
}
test "published recipes omit field-syntax members that selection scans include" {
    var fixture = try Fixture.init(a, &.{selecting});
    defer fixture.deinit(a);
    const module = &fixture.units[0];
    const left = symbolId(fixture.names.view(), "left");
    const binding = target(module, "projected").binding;
    const body = module.body(binding).?.*;
    const recipe = module.declaration_dependencies[module.bindings[binding].body_id];
    for (module.dependency_members[recipe.members.start..][0..recipe.members.len]) |published| try std.testing.expect(published.name != left);
    const scanned = try dependencies.selectionMembers(a, module, body);
    defer a.free(scanned);
    for (scanned) |use| {
        if (use.name == left) break;
    } else return error.TestUnexpectedResult;
}

test "principal gate rejects changed catalogs and the affected provider or runtime declaration" {
    inline for (0..6) |mutation| {
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
            5 => after.units[0].bindings[schema.binding].private = true,
            else => unreachable,
        }
        var pinned = try Pinned.init(a, &before);
        defer pinned.deinit(a);
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer gate.deinit();
        if (mutation == 2 or mutation == 3) {
            try std.testing.expect(!gate.admitsPrincipal(target(&after.units[0], if (mutation == 2) "builder" else "schema")));
        } else try std.testing.expect(!gate.enabled);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, shareGateFailure, .{ &pinned.pools, &after });
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
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, queryPreparationFailure, .{ &pinned.pools, &after });
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
    var reused = try Gate.init(allocator, old, current.units, current.names.view());
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
        var changed: usize = 0;
        for (reused.structural_units) |structural| if (!structural) {
            changed += 1;
        };
        try std.testing.expectEqual(current.units.len + changed, ordinary.dependency_validations);
        try std.testing.expectEqual(ordinary.dependency_validations, reused.dependency_validations);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, equivalentGate, .{ &pinned.pools, &after });
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
        var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
    var checked = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
        var rejected = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer rejected.deinit();
        try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 0);
    }
    pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
    after.units[0].nodes[root(&after.units[0], "schema")].op = .add;
    try equivalentGate(a, &pinned.pools, &after);
    var rejected = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer rejected.deinit();
    try std.testing.expect(!rejected.admitsPrincipal(target(&after.units[0], "schema")));
    try std.testing.expect(!rejected.structural_units[0]);
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
        // The forged body no longer proves identity flow. Keep its header
        // conservative so bounds validation reaches the intended cycle check.
        module.bindings[target(module, "builder").binding].capability_flow = .unknown;
        const views = [_]*const core.Module{module};
        try @import("../check/frozen_core_validation.zig").validateBounds(module, .{ .units = &views, .symbol_count = before.names.view().symbols.len });
    }
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    try equivalentGate(a, &pinned.pools, &after);
    var rejected = try Gate.init(a, &pinned.pools, after.units, after.names.view());
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
    var rejected = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer rejected.deinit();
    try std.testing.expect(!rejected.enabled and rejected.dependency_validations == 1);
}

fn projectedPrincipals(allocator: std.mem.Allocator, old: *artifacts.Pools, current: *Fixture) !void {
    var gate = try Gate.init(allocator, old, current.units, current.names.view());
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, projectedPrincipals, .{ &pinned.pools, &after });
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
    var optimized = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer optimized.deinit();
    try std.testing.expect(optimized.enabled);
    try std.testing.expectEqual(@as(usize, 3), optimized.dependency_validations);
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
    var extended = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer extended.deinit();
    try std.testing.expect(extended.enabled);
    try std.testing.expectEqual(@as(usize, 4), extended.dependency_validations);
    after.units[0].bindings = bindings[0..1];
    var shortened = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer shortened.deinit();
    try std.testing.expect(!shortened.enabled);
}

fn reusedCertificate(allocator: std.mem.Allocator, gate: *const Gate, pins: []const artifacts.ModulePin) !void {
    var certificate = (try gate.freezeValidation(allocator, pins)).?;
    defer certificate.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), certificate.reused_images);
    // The unchanged unit shares the previous certificate's image allocation.
    const old = &gate.source_pools.?.dependency_certificate.?.record.dependencies.modules[1];
    const shared = certificate.record.dependencies.modules[1].lease.?;
    try std.testing.expect(shared == old.lease.?);
    try std.testing.expect(shared.references >= 2);
    try std.testing.expect(certificate.record.dependencies.modules[0].lease.? != gate.source_pools.?.dependency_certificate.?.record.dependencies.modules[0].lease.?);
    for (pins, 0..) |pin, unit| try std.testing.expect(certificate.admits(unit, pin));
}

test "published certificates share exactly proven unchanged images and recapture edited units" {
    const consumer = "entry const dependent: U32 = schema\nentry const safe = fn (value: U32) => value\n";
    var before = try Fixture.init(a, &.{ independent, consumer });
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var initial = try Gate.init(a, &pinned.pools, before.units, before.names.view());
    defer initial.deinit();
    pinned.pools.dependency_certificate = (try initial.freezeValidation(a, pinned.pools.modules)).?;
    try std.testing.expectEqual(@as(usize, 0), pinned.pools.dependency_certificate.?.reused_images);

    // A scalar edit keeps unit one structural but not exact; unit two is
    // stream-equal to its pin in separate storage.
    var current = try Fixture.init(a, &.{ independent, consumer });
    defer current.deinit(a);
    current.units[0].nodes[root(&current.units[0], "schema")].a = 8;
    var current_pins = try Pinned.init(a, &current);
    defer current_pins.deinit(a);
    var stamps: artifacts.ModuleStamps = .{ .allocator = a, .current = current.units, .previous = &pinned.pools, .compare_contents = true };
    defer stamps.deinit();
    var gate = try Gate.initWithStamps(a, &pinned.pools, current.units, current.names.view(), &stamps);
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, gate.certified_images);
    // As a capture does, current pins take their tokens from this memo: the
    // stream-equal unit keeps its pin's token and the edited one gets a new one.
    for (current_pins.pools.modules, current.units, pinned.pools.modules, 0..) |*pin, *module, old, unit| {
        pin.token = try stamps.get(module);
        try std.testing.expectEqual(unit == 1, pin.token == old.token);
    }
    // The copied image must equal the current graph exactly: `admits` walks
    // every byte against the current module.
    try reusedCertificate(a, &gate, current_pins.pools.modules);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, reusedCertificate, .{ &gate, current_pins.pools.modules });

    // Even if a caller wrongly marks the edited unit reusable, its changed
    // stamp declines sharing and the unit is captured from current Core.
    const Certificate = @import("dependency_certificate.zig").Certificate;
    var units: [2]*const core.Module = .{ &current.units[0], &current.units[1] };
    var forced = (try Certificate.captureReusing(a, .{ .units = &units, .symbol_count = current.names.view().symbols.len }, current_pins.pools.modules, current.names.view(), &pinned.pools.dependency_certificate.?, &.{ true, true })).?;
    defer forced.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), forced.reused_images);
    for (current_pins.pools.modules, 0..) |pin, unit| try std.testing.expect(forced.admits(unit, pin));

    // A forged old certificate image is never admitted, so nothing is shared.
    const saved = pinned.pools.dependency_certificate.?.record.dependencies.modules[1].graph.bytes[0];
    pinned.pools.dependency_certificate.?.record.dependencies.modules[1].graph.bytes[0] ^= 1;
    defer pinned.pools.dependency_certificate.?.record.dependencies.modules[1].graph.bytes[0] = saved;
    var stamps_forged: artifacts.ModuleStamps = .{ .allocator = a, .current = current.units, .previous = &pinned.pools, .compare_contents = true };
    defer stamps_forged.deinit();
    var forged = try Gate.initWithStamps(a, &pinned.pools, current.units, current.names.view(), &stamps_forged);
    defer forged.deinit();
    try std.testing.expectEqualSlices(bool, &.{ false, false }, forged.certified_images);
    var recaptured = (try forged.freezeValidation(a, current_pins.pools.modules)).?;
    defer recaptured.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), recaptured.reused_images);
    for (current_pins.pools.modules, 0..) |pin, unit| try std.testing.expect(recaptured.admits(unit, pin));
}

fn closureIn(module: *const core.Module, text: []const u8, declaration: []const u8, next: ?[]const u8) u32 {
    const start: u32 = @intCast(std.mem.find(u8, text, declaration).?);
    const end: u32 = if (next) |name| @intCast(std.mem.find(u8, text, name).?) else @intCast(text.len);
    for (module.closures, 0..) |closure, index| {
        const at = module.spans[closure.body].start;
        if (at >= start and at < end) return @intCast(index);
    }
    unreachable;
}

test "closure roots in an edited module follow their owner's exact projection" {
    const source =
        \\entry const helper = fn (x: U32) -> U32 => @u32.add x 1
        \\entry const apply = fn (x: U32) -> U32 => do:
        \\  let inner = fn (y: U32) => helper y
        \\  break inner x
        \\entry const other = fn (x: U32) -> U32 => do:
        \\  let inner = fn (y: U32) => @u32.add y 3
        \\  break inner x
        \\entry const edited = fn (x: U32) -> U32 => @u32.add x 2
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    const edits = [_]struct { from: []const u8, to: []const u8, apply: bool, other: bool }{
        // An unrelated declaration changes: both closures keep their roots.
        .{ .from = "@u32.add x 2", .to = "@u32.add 2 x", .apply = true, .other = true },
        // The closure body itself changes.
        .{ .from = "@u32.add y 3", .to = "@u32.add 3 y", .apply = true, .other = false },
        // The callee body changes; the owner reads only its interface.
        .{ .from = "@u32.add x 1", .to = "@u32.add 1 x", .apply = true, .other = true },
    };
    for (edits) |edit| {
        const text = try std.mem.replaceOwned(u8, a, source, edit.from, edit.to);
        defer a.free(text);
        var after = try Fixture.init(a, &.{text});
        defer after.deinit(a);
        var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
        defer gate.deinit();
        try std.testing.expect(gate.enabled and !gate.structural_units[0]);
        const module = &after.units[0];
        const apply = closureIn(module, text, "entry const apply", "entry const other");
        const other = closureIn(module, text, "entry const other", "entry const edited");
        try std.testing.expectEqual(edit.apply, gate.admitsClosure(1, apply));
        try std.testing.expectEqual(edit.other, gate.admitsClosure(1, other));
        try std.testing.expect(!gate.admitsClosure(1, @intCast(module.closures.len)));
        try std.testing.expect(!gate.admitsClosure(2, 0));
    }
    // A referenced declaration's binding record, which carries its
    // interface, is part of every referencing projection. Editing the last
    // declaration's annotation leaves every earlier ID in place, yet revokes
    // the referencing owner's closures but not an unrelated owner's.
    const reordered =
        \\entry const apply = fn (x: U32) -> U32 => do:
        \\  let inner = fn (y: U32) => helper y
        \\  break inner x
        \\entry const other = fn (x: U32) -> U32 => do:
        \\  let inner = fn (y: U32) => @u32.add y 3
        \\  break inner x
        \\entry const helper = fn (x: U32) -> U32 => @u32.add x 1
    ;
    var first = try Fixture.init(a, &.{reordered});
    defer first.deinit(a);
    var first_pins = try Pinned.init(a, &first);
    defer first_pins.deinit(a);
    const changed = try std.mem.replaceOwned(u8, a, reordered, "fn (x: U32) -> U32 => @u32.add x 1", "fn x => @u32.add x 1");
    defer a.free(changed);
    var after = try Fixture.init(a, &.{changed});
    defer after.deinit(a);
    var gate = try Gate.init(a, &first_pins.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled and !gate.structural_units[0]);
    try std.testing.expect(!gate.admitsLocalSource(target(&after.units[0], "helper")));
    try std.testing.expect(!gate.admitsClosure(1, closureIn(&after.units[0], changed, "entry const apply", "entry const other")));
    try std.testing.expect(gate.admitsClosure(1, closureIn(&after.units[0], changed, "entry const other", "entry const helper")));
}

test "shifted source positions keep the catalog while shifted declarations are revoked" {
    const source =
        \\// a short comment
        \\entry const early: U32 = 1
        \\entry const doubled: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
        \\entry const late = fn (x: U32) -> U32 => doubled x
    ;
    var before = try Fixture.init(a, &.{source});
    defer before.deinit(a);
    try std.testing.expect(before.units[0].obligations.len != 0);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    // A longer comment shifts every later span; `early` also changes.
    const changed = try std.mem.replaceOwned(u8, a, source, "// a short comment\nentry const early: U32 = 1", "// a much longer leading comment\nentry const early: U32 = 2");
    defer a.free(changed);
    var after = try Fixture.init(a, &.{changed});
    defer after.deinit(a);
    try std.testing.expectEqual(before.units[0].obligations.len, after.units[0].obligations.len);
    try std.testing.expect(before.units[0].obligations[0].span.start != after.units[0].obligations[0].span.start);
    var gate = try Gate.init(a, &pinned.pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled and !gate.structural_units[0]);
    try std.testing.expect(!gate.admitsLocalSource(target(&after.units[0], "early")));
    try std.testing.expect(!gate.admitsLocalSource(target(&after.units[0], "doubled")));
    try std.testing.expect(!gate.admitsLocalSource(target(&after.units[0], "late")));
}

test "foreign-only certificates require actual package callers and gates recheck changed pure helper bodies" {
    const V = @import("../check/frozen_core_validation.zig");
    const Certificate = @import("dependency_certificate.zig").Certificate;
    const producer = "entry const schema: U32 -> U32 = fn value => value\n";
    const consumer =
        \\type Item = exists [a] => a
        \\entry const run: U32 -> U32 = fn value => schema (unpack (pack [U32] value as Item) as [a] hidden in 42)
    ;
    var helper = try Fixture.init(a, &.{producer});
    defer helper.deinit(a);
    // A syntactically ordinary identity needs no newly published no-store
    // recipe; the foreign-only certificate can reuse this plain owner.
    for (helper.units[0].bindings) |binding| try std.testing.expect(binding.capability_flow != .input_shape);
    var helper_pins = try Pinned.init(a, &helper);
    defer helper_pins.deinit(a);
    const foreign_units = [_]*const core.Module{&helper.units[0]};
    const foreign: V.Context = .{ .units = &foreign_units, .symbol_count = helper.names.view().symbols.len };
    var certificate = (try Certificate.capture(a, foreign, helper_pins.pools.modules, helper.names.view())).?;
    defer certificate.deinit(a);
    try std.testing.expect(certificate.matches(foreign, helper.names.view(), &foreign_units));
    try std.testing.expect(!certificate.matches(foreign, helper.names.view(), &.{}));

    var before = try Fixture.init(a, &.{ producer, consumer });
    defer before.deinit(a);
    const actual_callers = [_]*const core.Module{&before.units[1]};
    try std.testing.expect(!certificate.matches(foreign, helper.names.view(), &actual_callers));
    try std.testing.expect(!V.equivalentContext(foreign, foreign, &actual_callers, &actual_callers));
    const foreign_body: V.Context = .{ .units = &foreign_units };
    try V.validate(a, &before.units[1], foreign_body);
    const helper_root = root(&helper.units[0], "schema");
    const helper_value = helper.units[0].nodes[helper_root];
    const helper_bindings = helper.units[0].bindings.len;
    helper.units[0].nodes[helper_root] = .{ .tag = .constant, .ty = T.boolean, .a = 1 };
    try std.testing.expectEqual(helper_bindings, helper.units[0].bindings.len);
    try std.testing.expect(!certificate.matches(foreign, helper.names.view(), &actual_callers));
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &before.units[1], foreign_body));
    helper.units[0].nodes[helper_root] = helper_value;
    try V.validate(a, &before.units[1], foreign_body);
    var pinned = try Pinned.init(a, &before);
    defer pinned.deinit(a);
    var initial = try Gate.init(a, &pinned.pools, before.units, before.names.view());
    defer initial.deinit();
    try std.testing.expect(initial.enabled and initial.dependencies_validated);
    pinned.pools.dependency_certificate = (try initial.freezeValidation(a, pinned.pools.modules)).?;
    var current = try Fixture.init(a, &.{ producer, consumer });
    defer current.deinit(a);
    var candidate_gate = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer candidate_gate.deinit();
    // The existential consumer keeps the context from being reused for the
    // current modules, but the certificate was captured for exactly the
    // retained pins, so their own validation is not repeated.
    try std.testing.expect(!certificate.matches(foreign, helper.names.view(), &actual_callers));
    try std.testing.expect(candidate_gate.enabled and candidate_gate.dependency_validations == 2 and candidate_gate.reused_dependency_validations == 2);
    // A certificate for any other context (here other validation bounds)
    // certifies none of the pins.
    pinned.pools.dependency_certificate.?.record.key.symbol_count = 0;
    var other_context = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer other_context.deinit();
    try std.testing.expect(other_context.enabled and other_context.dependency_validations == 4 and other_context.reused_dependency_validations == 0);
    pinned.pools.dependency_certificate.?.record.key.symbol_count = before.names.view().symbols.len;
    // Nor can a changed retained graph hide behind a restamped pin: its image
    // no longer matches, so the pin is validated again and rejected.
    const pinned_root = root(&before.units[0], "schema");
    const kept_node = before.units[0].nodes[pinned_root];
    const kept_current = current.units[0].nodes[pinned_root];
    const kept_stamp = pinned.pools.modules[0].stamp;
    before.units[0].nodes[pinned_root].ty = std.math.maxInt(u32);
    current.units[0].nodes[pinned_root] = before.units[0].nodes[pinned_root];
    pinned.pools.modules[0].stamp = artifacts.stamp(before.units[0]);
    var corrupt = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer corrupt.deinit();
    try std.testing.expect(!corrupt.enabled and !corrupt.dependencies_validated);
    before.units[0].nodes[pinned_root] = kept_node;
    current.units[0].nodes[pinned_root] = kept_current;
    pinned.pools.modules[0].stamp = kept_stamp;
    const root_ = root(&current.units[0], "schema");
    try std.testing.expect(current.units[0].node(root_).tag == .reference);
    current.units[0].nodes[root_] = .{ .tag = .constant, .ty = T.boolean, .a = 1 };
    // The helper's header, schemes and binding count are unchanged. Package
    // admission reconstructs its body result instead of using those counts.
    var rejected = try Gate.init(a, &pinned.pools, current.units, current.names.view());
    defer rejected.deinit();
    try std.testing.expect(!rejected.enabled and !rejected.dependencies_validated);
}
