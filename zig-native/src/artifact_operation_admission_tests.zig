const std = @import("std");
const artifacts = @import("code_artifacts.zig");
const capture = @import("artifact_capture.zig");
const emitter = @import("artifact_emitter.zig");
const fragment = @import("artifact_fragment.zig");
const importer = @import("artifact_import.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const layout = @import("layout.zig");
const substitutions = @import("substitution_keys.zig");
const identity = @import("runtime_identity.zig");
const operations = @import("runtime_operations.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const a = std.testing.allocator;
const Allocator = std.mem.Allocator;

const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init() !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        const units = try a.alloc(core.Module, 2);
        errdefer a.free(units);
        var initialized: usize = 0;
        errdefer for (units[0..initialized]) |*unit| unit.deinit(a);
        for (units, 1..) |*unit, id| {
            const source = if (id == 1)
                "data Cell = #Cell U32\neffect Read: Unit -> F32\nconst read = fn () => Read ()\nentry const answer = fn (value: F32) => value\n"
            else
                "data Fresh = #Fresh U32\nentry const answer = fn (value: F32) => value\n";
            var tokens = try lexer.lex(a, source);
            defer tokens.deinit(a);
            var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
            defer tree.deinit(a);
            for (tree.diagnostics.items) |issue| std.debug.print("operation fixture parse {any}\n", .{issue});
            try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
            var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, @intCast(id), .{});
            defer checked.deinit(a);
            for (checked.diagnostics) |issue| std.debug.print("operation fixture check {any}\n", .{issue});
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
            unit.* = try core.lower(a, &tree, &pool, &checked);
            initialized += 1;
            unit.unit = @intCast(id);
        }
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{
            .{ .unit = 1, .path = "/operation-admission/library.blot" },
            .{ .unit = 2, .path = "/operation-admission/main.blot" },
        }, 2) };
    }
    fn deinit(self: *Fixture) void {
        self.names.deinit(a);
        for (self.units) |*unit| unit.deinit(a);
        a.free(self.units);
    }
    fn key(self: *const Fixture) artifacts.Key {
        for (self.units[0].bodies) |body| if (body.exported and body.is_function) {
            var result: artifacts.Key = .{ .target = .{ .unit = 1, .binding = body.binding }, .count = 1, .result = 4 };
            result.parameters[0] = 4;
            return result;
        };
        unreachable;
    }
};

const Generator = struct {
    evaluator: eval.Session,
    layouts: layout.Store,
    row_keys: substitutions.Store,
    template_keys: substitutions.Store,
    static_keys: substitutions.Store,
    template_catalog: std.ArrayList(artifacts.CapturedTemplate) = .empty,
    template_instances: std.AutoHashMapUnmanaged(artifacts.CapturedTemplate, u32) = .empty,
    runtime_operations: operations.Store,
    request_owner: ?u32 = null,
    allocator: Allocator,
    fn init(allocator: Allocator, fixture: *const Fixture) !Generator {
        var evaluator = try eval.Session.init(allocator, fixture.units);
        errdefer evaluator.deinit();
        return .{ .evaluator = evaluator, .layouts = try layout.Store.init(allocator), .row_keys = substitutions.Store.init(allocator), .template_keys = substitutions.Store.init(allocator), .static_keys = substitutions.Store.init(allocator), .runtime_operations = operations.Store.initProject(allocator, fixture.names.view()), .allocator = allocator };
    }
    fn deinit(self: *Generator) void {
        self.template_catalog.deinit(self.allocator);
        self.template_instances.deinit(self.allocator);
        self.runtime_operations.deinit();
        self.template_keys.deinit();
        self.static_keys.deinit();
        self.row_keys.deinit();
        self.layouts.deinit();
        self.evaluator.deinit();
    }
};

const Inputs = struct { stable: u32, fresh: u32, state_stable: u32, state_fresh: u32 };
fn buildInputs(g: *Generator, fixture: *const Fixture) !Inputs {
    var decl: u32 = 0;
    for (fixture.units[0].types.operations) |operation| if (operation.identity.unit == 1 and operation.identity.decl != 0) {
        decl = operation.identity.decl;
        break;
    };
    if (decl == 0) std.debug.print("operation fixture has no producer, {d} operation catalog entries\n", .{fixture.units[0].types.operations.len});
    try std.testing.expect(decl != 0);
    const stable_payload = try g.evaluator.evidence.intern(.nominal, 1, nominalDecl(&fixture.units[0]), &.{3});
    const fresh_payload = try g.evaluator.evidence.intern(.nominal, 2, nominalDecl(&fixture.units[1]), &.{3});
    const stable_label = try g.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = decl }, &.{3});
    const fresh_label = try g.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = decl }, &.{fresh_payload});
    const stable_state = try g.evaluator.evidence.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = 1 }, &.{stable_payload});
    const fresh_state = try g.evaluator.evidence.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = 1 }, &.{fresh_payload});
    return .{
        .stable = try g.runtime_operations.intern(g.evaluator.evidence.view(), stable_label),
        .fresh = try g.runtime_operations.intern(g.evaluator.evidence.view(), fresh_label),
        .state_stable = try g.runtime_operations.intern(g.evaluator.evidence.view(), stable_state),
        .state_fresh = try g.runtime_operations.intern(g.evaluator.evidence.view(), fresh_state),
    };
}
fn nominalDecl(module: *const core.Module) u32 {
    for (module.nominals) |nominal| if (nominal.identity.decl != 0) return nominal.identity.decl;
    unreachable;
}
fn copyNames(view: identity.View) !identity.Metadata {
    const bytes = try a.dupe(u8, view.bytes);
    errdefer a.free(bytes);
    const names = try a.dupe(@typeInfo(@TypeOf(view.symbols)).pointer.child, view.symbols);
    errdefer a.free(names);
    return .{ .bytes = bytes, .symbols = names, .owners = try a.dupe(@typeInfo(@TypeOf(view.owners)).pointer.child, view.owners) };
}
fn pools(g: *const Generator, fixture: *const Fixture) !artifacts.Pools {
    var result = std.mem.zeroes(artifacts.Pools);
    errdefer result.deinit(a);
    result.project_identity = true;
    result.identity = try copyNames(fixture.names.view());
    var pins: std.ArrayList(artifacts.ModulePin) = .empty;
    defer pins.deinit(a);
    errdefer for (pins.items) |pin| a.free(pin.canonical_path);
    for (fixture.units, 1..) |*unit, id| {
        const path = try a.dupe(u8, fixture.names.view().owner(@intCast(id)).?);
        errdefer a.free(path);
        try pins.append(a, .{ .unit = @intCast(id), .module = unit, .canonical_path = path, .stamp = artifacts.stamp(unit.*) });
    }
    result.modules = try pins.toOwnedSlice(a);
    result.layouts.nodes = try a.dupe(layout.Node, g.layouts.nodes.items);
    result.layouts.extra = try a.dupe(u32, g.layouts.extra.items);
    result.layouts.effects = try g.layouts.effects.copyOwned(a);
    result.evaluator = try g.evaluator.copySnapshot(a);
    result.field_locations = try a.alloc(artifacts.FieldLocation, g.evaluator.field_locations.count());
    var fields = g.evaluator.field_locations.iterator();
    var field_index: usize = 0;
    while (fields.next()) |field| : (field_index += 1) result.field_locations[field_index] = .{ .family = field.key_ptr.family, .tag = field.key_ptr.tag, .name = field.key_ptr.name, .field = field.value_ptr.field, .len = field.value_ptr.len };
    result.field_locations_stamp = artifacts.stamp(result.field_locations);
    var symbols_: std.ArrayList(artifacts.Operation) = .empty;
    defer symbols_.deinit(a);
    errdefer for (symbols_.items) |operation| a.free(operation.key);
    for (g.runtime_operations.entries.items) |operation| {
        const key = try a.dupe(u8, operation.key);
        errdefer a.free(key);
        try symbols_.append(a, .{ .key = key, .foreign = operation.foreign, .runtime = operation.runtime });
    }
    result.operations = try symbols_.toOwnedSlice(a);
    return result;
}
fn tableStamp(g: *const Generator) [32]u8 {
    return artifacts.stamp(.{ g.runtime_operations.entries.items, g.runtime_operations.relocations.items, g.runtime_operations.finalized });
}
fn oldStamp(old: *const artifacts.Pools) [32]u8 {
    return artifacts.stamp(.{ old.operations, old.evaluator.evidence, old.layouts });
}

test "operation admission qualifies cached and exact entry catalogs without publishing tags" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    var old = try pools(&producer, &fixture);
    defer old.deinit(a);
    var current = try Generator.init(a, &fixture);
    defer current.deinit();
    const foreign = try current.evaluator.evidence.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    _ = try current.runtime_operations.intern(current.evaluator.evidence.view(), foreign);
    const before = tableStamp(&current);
    const old_before = oldStamp(&old);
    var imports = try importer.Importer.init(a, &old, fixture.units, fixture.names.view(), 1);
    defer imports.deinit();
    for (0..2) |_| {
        try std.testing.expect(try imports.admitOperation(&current, inputs.stable));
        try std.testing.expect(try imports.admitOperation(&current, inputs.state_stable));
        try std.testing.expect(try imports.admitOperation(&current, inputs.fresh));
        try std.testing.expect(try imports.admitOperation(&current, inputs.state_fresh));
        try std.testing.expect(!try imports.admitOperation(&current, 0));
        try std.testing.expectEqual(before, tableStamp(&current));
        try std.testing.expectEqual(old_before, oldStamp(&old));
    }
}

const Reference = enum { instruction, symbol, demand };
fn journalCapture(fixture: *const Fixture, reference: Reference, id: u32) !capture.Capture {
    var producer = try Generator.init(a, fixture);
    defer producer.deinit();
    _ = try buildInputs(&producer, fixture);
    var result: capture.Capture = .{ .metadata = artifacts.Context.init(a), .emission = emitter.Recorder.init(a), .cached_units = 1 };
    errdefer result.deinit();
    result.emission.owner = &result.metadata.active_job;
    result.emission.clock = &result.metadata.clock;
    var scope = try result.metadata.enter(.{ .named = fixture.key() });
    var scope_alive = true;
    defer if (scope_alive) scope.deinit();
    try result.emission.signature(0, &.{ .f32, .i32 }, .f32);
    try result.emission.append(.{ .function = .{ .id = 0, .signature = 0 } });
    try scope.reserve(0);
    switch (reference) {
        .instruction => try result.emission.append(.{ .instruction = .{ .function = 0, .op = .i32_const, .operand = .{ .role = .operation, .value = id } } }),
        .symbol => {
            const operation = producer.runtime_operations.entries.items[id - 1];
            try result.emission.operationSymbol(id, operation.key, operation.foreign);
        },
        .demand => try result.emission.append(.{ .demand = .{ .kind = .operation, .id = id, .hit = true } }),
    }
    try scope.complete(0, null);
    scope.deinit();
    scope_alive = false;
    result.metadata.pools = try pools(&producer, fixture);
    result.metadata.pools.?.functions = try a.dupe(artifacts.Function, &.{.{ .request = .{ .named = fixture.key() }, .function = 0 }});
    result.emission.seal();
    try result.emission.freezeFunctions(result.metadata.function_jobs.items);
    try result.sealExecutableQueries();
    return result;
}
test "operation admission validates exact entry catalogs in inline references and unused demands" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    for ([_]Reference{ .instruction, .symbol, .demand }) |reference| for ([_]u32{ inputs.stable, inputs.fresh }) |id| {
        var old = try journalCapture(&fixture, reference, id);
        defer old.deinit();
        try std.testing.expectEqual(@as(usize, 1), old.metadata.jobs.items.len);
        try std.testing.expect(old.metadata.jobs.items[0].request == .named);
        var current = try Generator.init(a, &fixture);
        defer current.deinit();
        const before = tableStamp(&current);
        var state = try fragment.State.init(a, &old, fixture.units, fixture.names.view(), 1);
        defer state.deinit();
        try std.testing.expect(state.enabled);
        const hit = try state.find(&current, .{ .named = fixture.key() });
        try std.testing.expectEqual(@as(?u32, 1), hit);
        try std.testing.expectEqual(before, tableStamp(&current));
    };
}

test "executable fragment queries decline unsealed and saturated captures while preserving the live request owner" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    for (0..3) |limit| {
        var old = try journalCapture(&fixture, .instruction, inputs.stable);
        defer old.deinit();
        try std.testing.expect(old.executable_queries_complete);
        try std.testing.expectEqual(@as(usize, 1), old.executable_queries.records.items.len);
        var current = try Generator.init(a, &fixture);
        defer current.deinit();
        const before = tableStamp(&current);
        var state = try fragment.State.init(a, &old, fixture.units, fixture.names.view(), 1);
        defer state.deinit();
        try std.testing.expectEqual(@as(?u32, 1), try state.find(&current, .{ .named = fixture.key() }));
        old.executable_queries_complete = false;
        try std.testing.expect(try state.find(&current, .{ .named = fixture.key() }) == null);
        old.executable_queries.deinit(a);
        old.executable_queries = .{};
        switch (limit) {
            0 => old.executable_queries.limits.records = 0,
            1 => old.executable_queries.limits.retained_capacity = 0,
            2 => {
                // A prefix can be complete locally while the whole optional
                // table is incomplete. No such partial index authorizes reuse.
                try old.sealExecutableQueries();
                old.executable_queries_complete = false;
            },
            else => unreachable,
        }
        if (limit != 2) try old.sealExecutableQueries();
        try std.testing.expect(!old.executable_queries_complete);
        try std.testing.expect(try state.find(&current, .{ .named = fixture.key() }) == null);
        try std.testing.expectEqual(before, tableStamp(&current));
    }
}

fn allocationScenario(allocator: Allocator, fixture: *const Fixture, old: *const artifacts.Pools, inputs: Inputs) !void {
    var current = try Generator.init(allocator, fixture);
    defer current.deinit();
    var imports = try importer.Importer.init(allocator, old, fixture.units, fixture.names.view(), 1);
    defer imports.deinit();
    const before = tableStamp(&current);
    const old_before = oldStamp(old);
    const admitted = imports.admitOperation(&current, inputs.state_stable) catch |err| {
        try std.testing.expectEqual(before, tableStamp(&current));
        try std.testing.expectEqual(old_before, oldStamp(old));
        return err;
    };
    try std.testing.expect(admitted);
    try std.testing.expect(try imports.admitOperation(&current, inputs.state_fresh));
    try std.testing.expectEqual(before, tableStamp(&current));
    try std.testing.expectEqual(old_before, oldStamp(old));
}
test "operation admission allocation failures preserve captures and runtime tables" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    var old = try pools(&producer, &fixture);
    defer old.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{ &fixture, &old, inputs });
}
test "operation admission retries failed indexing in the same owner and memoizes scope" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var producer = try Generator.init(a, &fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    var old = try pools(&producer, &fixture);
    defer old.deinit(a);
    var failures = std.testing.FailingAllocator.init(a, .{});
    const allocator = failures.allocator();
    var current = try Generator.init(allocator, &fixture);
    defer current.deinit();
    var imports = try importer.Importer.init(allocator, &old, fixture.units, fixture.names.view(), 1);
    defer imports.deinit();
    const before = tableStamp(&current);
    failures.fail_index = failures.alloc_index;
    try std.testing.expectError(error.OutOfMemory, imports.admitOperation(&current, inputs.stable));
    try std.testing.expect(imports.operation_labels == null);
    failures.fail_index = std.math.maxInt(usize);
    try std.testing.expect(try imports.admitOperation(&current, inputs.stable));
    failures.fail_index = failures.alloc_index;
    try std.testing.expectError(error.OutOfMemory, imports.admitOperation(&current, inputs.state_stable));
    try std.testing.expect(imports.operation_labels != null);
    failures.fail_index = std.math.maxInt(usize);
    try std.testing.expect(try imports.admitOperation(&current, inputs.state_stable));
    try std.testing.expect(try imports.admitOperation(&current, inputs.fresh));
    // A second hit or miss needs no scratch encoder, allocation or tag change.
    failures.fail_index = failures.alloc_index;
    try std.testing.expect(try imports.admitOperation(&current, inputs.stable));
    try std.testing.expect(try imports.admitOperation(&current, inputs.state_stable));
    try std.testing.expect(try imports.admitOperation(&current, inputs.fresh));
    try std.testing.expectEqual(before, tableStamp(&current));
}

// The ordinary adapter's sources have no erased references or named dispatch
// members. This owned Core fixture makes every new qualified role nonempty
// while deliberately changing both producer and spelling namespaces.
fn namespaceFixture(reordered: bool) !Fixture {
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    _ = try pool.intern(a, if (reordered) "left" else "right");
    _ = try pool.intern(a, if (reordered) "right" else "left");
    const units = try a.alloc(core.Module, 2);
    errdefer a.free(units);
    var initialized: usize = 0;
    errdefer for (units[0..initialized]) |*unit| unit.deinit(a);
    const source = "type Cell is data = #Cell { right: F32, left: U32 }\neffect Read: Unit -> F32\nconst read = fn () => Read ()\nentry const answer = fn (value: F32) => value\n";
    for (units, 1..) |*unit, id| {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, @intCast(id), .{});
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        unit.* = try core.lower(a, &tree, &pool, &checked);
        unit.unit = @intCast(id);
        initialized += 1;
        for (unit.bodies, 0..) |body, catalog| if (body.exported and body.is_function) {
            const target: core.BindingRef = .{ .unit = if (reordered) 2 else 1, .binding = body.binding };
            const references = try a.dupe(core.BindingRef, &.{target});
            a.free(unit.dependency_references);
            unit.dependency_references = references;
            const erased = try a.dupe(core.ErasedDeclarationReference, &.{.{ .node = body.root, .target = target }});
            a.free(unit.erased_declaration_references);
            unit.erased_declaration_references = erased;
            const members = try a.dupe(core.DependencyMember, &.{ .{ .name = try pool.intern(a, "right") }, .{ .operator = .add } });
            a.free(unit.dependency_members);
            unit.dependency_members = members;
            @memset(unit.declaration_dependencies, .{});
            unit.declaration_dependencies[catalog] = .{ .references = .{ .start = 0, .len = 1 }, .members = .{ .start = 0, .len = 2 }, .runtime_metadata = body.root };
            break;
        };
    }
    return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{
        .{ .unit = 1, .path = if (reordered) "/operation-admission/b.blot" else "/operation-admission/a.blot" },
        .{ .unit = 2, .path = if (reordered) "/operation-admission/a.blot" else "/operation-admission/b.blot" },
    }, 2) };
}
fn namespaceAdmission(allocator: Allocator, old: *const artifacts.Pools, fixture: *const Fixture, key: artifacts.Key) !void {
    var current = try Generator.init(allocator, fixture);
    defer current.deinit();
    const before = artifacts.stamp(.{ old.modules[0].module.*, old.modules[1].module.* });
    var imports = try importer.Importer.init(allocator, old, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    try std.testing.expect(imports.stable[0] and imports.stable[1]);
    const maybe_request = try imports.importRequest(&current, .{ .named = key });
    try std.testing.expect(maybe_request != null);
    const request = maybe_request.?;
    try std.testing.expectEqual(@as(u32, 2), request.named.target.unit);
    try std.testing.expectEqual(before, artifacts.stamp(.{ old.modules[0].module.*, old.modules[1].module.* }));
}
test "startup dependency roles remap qualified owners and symbols while local ranges stay fixed" {
    var original = try namespaceFixture(false);
    defer original.deinit();
    var producer = try Generator.init(a, &original);
    defer producer.deinit();
    var old = try pools(&producer, &original);
    defer old.deinit(a);
    var current = try namespaceFixture(true);
    defer current.deinit();
    try std.testing.expectEqual(@as(u32, 1), original.units[0].dependency_references[0].unit);
    try std.testing.expectEqual(@as(u32, 2), current.units[1].dependency_references[0].unit);
    try std.testing.expectEqual(@as(u32, 1), original.units[0].erased_declaration_references[0].target.unit);
    try std.testing.expectEqual(@as(u32, 2), current.units[1].erased_declaration_references[0].target.unit);
    try std.testing.expect(original.units[0].dependency_members[0].name != current.units[1].dependency_members[0].name);
    try namespaceAdmission(a, &old, &current, original.key());
}
test "startup dependency role imports preserve old Core across allocation failures" {
    var original = try namespaceFixture(false);
    defer original.deinit();
    var producer = try Generator.init(a, &original);
    defer producer.deinit();
    var old = try pools(&producer, &original);
    defer old.deinit(a);
    var current = try namespaceFixture(true);
    defer current.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, namespaceAdmission, .{ &old, &current, original.key() });
}

test "entry operation payloads still reject a changed nominal catalog" {
    var original = try Fixture.init();
    defer original.deinit();
    var producer = try Generator.init(a, &original);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &original);
    var old = try pools(&producer, &original);
    defer old.deinit(a);
    var changed = try Fixture.init();
    defer changed.deinit();
    for (changed.units[1].nominals) |*nominal| if (nominal.identity.decl != 0) {
        nominal.identity.decl += 100;
    };
    var current = try Generator.init(a, &changed);
    defer current.deinit();
    var imports = try importer.Importer.init(a, &old, changed.units, changed.names.view(), 1);
    defer imports.deinit();
    const before = tableStamp(&current);
    try std.testing.expect(!try imports.admitOperation(&current, inputs.fresh));
    try std.testing.expect(!try imports.admitOperation(&current, inputs.state_fresh));
    try std.testing.expectEqual(before, tableStamp(&current));
}
