const std = @import("std");
const artifacts = @import("code_artifacts.zig");
const core = @import("core.zig");
const core_eval = @import("core_eval.zig");
const layout = @import("layout.zig");
const bridge = @import("layout_bridge.zig");
const substitutions = @import("substitution_keys.zig");
const runtime_identity = @import("runtime_identity.zig");
const runtime_operations = @import("runtime_operations.zig");
const owned_arrays = @import("owned_arrays.zig");
const discarded_bindings = @import("discarded_bindings.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const types = @import("types.zig");
const wasm = @import("wasm.zig");
const Allocator = std.mem.Allocator;
const a = std.testing.allocator;

test "compilation scoped exact stamps recognize independent Core copies without admitting unrelated owners" {
    var first = try Fixture.init();
    defer first.deinit();
    var second = try Fixture.init();
    defer second.deinit();
    var views = [_]core.Module{ first.units[0], second.units[0] };
    var memo: artifacts.ModuleStamps = .{ .allocator = a, .current = &views, .previous = null, .compare_contents = true };
    defer memo.deinit();
    try std.testing.expect(!try memo.proveSame(&views[0], &views[1]));
    const expected = artifacts.stampReference(views[0]);
    try std.testing.expectEqual(expected, try memo.get(&views[0]));
    try std.testing.expect(try memo.proveSame(&views[0], &views[1]));
    try std.testing.expectEqual(expected, try memo.get(&views[1]));
    try std.testing.expectEqual(@as(usize, 1), memo.computed);
    try std.testing.expectEqual(@as(usize, 1), memo.copied);
    try std.testing.expectEqual(@as(usize, 2), memo.reused);
    const unrelated = views[1];
    try std.testing.expect(!try memo.proveSame(&views[0], &unrelated));
    try std.testing.expect(!try memo.proveSame(&unrelated, &views[1]));
    try std.testing.expectEqual(expected, try memo.get(&unrelated));
    try std.testing.expectEqual(@as(usize, 1), memo.computed);
    try std.testing.expectEqual(@as(usize, 1), memo.copied);
}

test "compilation scoped exact stamps reject changed executable type catalog span and source metadata" {
    var first = try Fixture.init();
    defer first.deinit();
    const expected = artifacts.stampReference(first.units[0]);
    for (0..10) |change| {
        var second = try Fixture.init();
        defer second.deinit();
        const module = &second.units[0];
        switch (change) {
            0 => module.unit += 1,
            1 => module.nodes[0].a ^= 1,
            2 => module.types.nodes[0].a ^= 1,
            3 => module.spans[0].start ^= 1,
            4 => module.bindings[0].ty ^= 1,
            5 => module.bodies[0].span.end ^= 1,
            6 => module.names[0] ^= 1,
            7 => module.nominals[0].identity.decl ^= 1,
            8 => module.constructors[0].payload ^= 1,
            9 => module.body_lowerings += 1,
            else => unreachable,
        }
        var views = [_]core.Module{ first.units[0], module.* };
        const changed = artifacts.stampReference(views[1]);
        try std.testing.expect(!std.mem.eql(u8, &expected, &changed));
        var memo: artifacts.ModuleStamps = .{ .allocator = a, .current = &views, .previous = null, .compare_contents = true };
        defer memo.deinit();
        try std.testing.expectEqual(expected, try memo.get(&views[0]));
        try std.testing.expect(!try memo.proveSame(&views[0], &views[1]));
        try std.testing.expectEqual(changed, try memo.get(&views[1]));
        try std.testing.expectEqual(@as(usize, 2), memo.computed);
        try std.testing.expectEqual(@as(usize, 0), memo.copied);
    }
}

fn exactStampAllocationScenario(allocator: Allocator, units: []const core.Module) !void {
    var memo: artifacts.ModuleStamps = .{ .allocator = allocator, .current = units, .previous = null, .compare_contents = true };
    defer memo.deinit();
    const expected = artifacts.stampReference(units[0]);
    for (units, 0..) |*module, index| {
        if (index != 0) try std.testing.expect(try memo.proveSame(&units[0], module));
        try std.testing.expectEqual(expected, try memo.get(module));
    }
    try std.testing.expectEqual(@as(usize, 1), memo.computed);
    try std.testing.expectEqual(units.len - 1, memo.copied);
}
test "compilation scoped exact stamp allocation failure preserves copied owners across memo growth" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var views: [80]core.Module = undefined;
    var initialized: usize = 0;
    defer for (views[0..initialized]) |module| a.free(module.names);
    for (&views) |*module| {
        module.* = fixture.units[0];
        module.names = try a.dupe(u8, module.names);
        initialized += 1;
    }
    const before = artifacts.stampReference(fixture.units[0]);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, exactStampAllocationScenario, .{&views});
    try exactStampAllocationScenario(a, &views);
    try std.testing.expectEqual(before, artifacts.stampReference(fixture.units[0]));
}

test "compilation scoped stamps reuse identical immutable storage but distinguish owners boundaries and header values" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const copied_nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(copied_nodes);
    var views: [5]core.Module = @splat(fixture.units[0]);
    views[2].nodes = copied_nodes;
    views[3].unit += 1;
    views[4].nodes = views[4].nodes[0 .. views[4].nodes.len - 1];
    var memo: artifacts.ModuleStamps = .{ .allocator = a, .current = &views, .previous = null };
    defer memo.deinit();
    for (&views, 0..) |*module, index| {
        const actual = try memo.get(module);
        const expected = artifacts.stampReference(module.*);
        try std.testing.expectEqualSlices(u8, &expected, &actual);
        try std.testing.expectEqual(@as(usize, if (index == 0) 1 else index), memo.computed);
    }
    try std.testing.expectEqual(@as(usize, 1), memo.reused);
    // An equal view outside the declared owners must not read or populate the
    // memo. Its content is still hashed normally.
    const unrelated = fixture.units[0];
    const expected = artifacts.stampReference(unrelated);
    const actual = try memo.get(&unrelated);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
    try std.testing.expectEqual(@as(usize, 4), memo.computed);
    try std.testing.expectEqual(@as(usize, 1), memo.reused);
}

test "compilation scoped stamps rehash reused addresses after the immutable borrow ends" {
    for ([_]bool{ false, true }) |exact| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const original = blk: {
            var first: artifacts.ModuleStamps = .{ .allocator = a, .current = fixture.units, .previous = null, .compare_contents = exact };
            defer first.deinit();
            const digest = try first.get(&fixture.units[0]);
            _ = try first.get(&fixture.units[0]);
            try std.testing.expectEqual(@as(usize, 1), first.computed);
            break :blk digest;
        };
        fixture.units[0].nodes[0].a ^= 1;
        var next: artifacts.ModuleStamps = .{ .allocator = a, .current = fixture.units, .previous = null, .compare_contents = exact };
        defer next.deinit();
        const changed = try next.get(&fixture.units[0]);
        try std.testing.expect(!std.mem.eql(u8, &original, &changed));
        const expected = artifacts.stampReference(fixture.units[0]);
        try std.testing.expectEqualSlices(u8, &expected, &changed);
        try std.testing.expectEqual(@as(usize, 1), next.computed);
        try std.testing.expectEqual(@as(usize, 0), next.reused);
    }
}

fn stampAllocationScenario(allocator: Allocator, units: []const core.Module) !void {
    var memo: artifacts.ModuleStamps = .{ .allocator = allocator, .current = units, .previous = null };
    defer memo.deinit();
    for (units) |*module| {
        const expected = artifacts.stampReference(module.*);
        const actual = try memo.get(module);
        try std.testing.expectEqualSlices(u8, &expected, &actual);
    }
}

test "compilation scoped stamp allocation failure releases storage and leaves source owners unchanged" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var views: [80]core.Module = undefined;
    for (&views, 0..) |*module, index| {
        module.* = fixture.units[0];
        module.unit = @intCast(index + 1);
    }
    const before = artifacts.stampReference(fixture.units[0]);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, stampAllocationScenario, .{&views});
    const after = artifacts.stampReference(fixture.units[0]);
    try std.testing.expectEqualSlices(u8, &before, &after);
    try stampAllocationScenario(a, &views);
}

fn graphScenario(allocator: Allocator) !void {
    var context = artifacts.Context.init(allocator);
    defer context.deinit();
    {
        var parent = try context.enter(.{ .named = .{ .target = .{ .unit = 1, .binding = 11 }, .count = 1, .result = types.f32_type, .templates = 7, .template_result = true } });
        defer parent.deinit();
        try parent.reserve(0);
        // Emission resources use the same clock. Gaps preserve their insertion
        // between metadata events rather than flattening parent/child ranges.
        context.clock += 2;
        var mappings = [_]layout.Mapping{.{ .variable = 17, .layout = types.f32_type }};
        var rows = [_]layout.RowMapping{ .{ .variable = 0, .row = 0 }, .{ .variable = 1, .row = layout.unknown_row } };
        var templates = [_]substitutions.Entry{.{ .variable = 9, .value = 1 }};
        try parent.solved(&mappings, &rows, &templates);
        // Surviving substitutions cannot borrow an emitter's temporary arrays.
        mappings[0].layout = types.u32_type;
        rows[0].row = layout.unknown_row;
        templates[0].value = 8;
        try std.testing.expectEqual(types.f32_type, context.jobs.items[0].mappings[0].layout);
        try std.testing.expectEqual(@as(u32, 0), context.jobs.items[0].rows[0].row);
        try std.testing.expectEqual(layout.unknown_row, context.jobs.items[0].rows[1].row);
        try std.testing.expectEqual(@as(u32, 1), context.jobs.items[0].templates[0].value);
        // A failed replacement must retain the previous complete solved view.
        parent.solved(&mappings, &rows, &templates) catch |err| {
            try std.testing.expectEqual(types.f32_type, context.jobs.items[0].mappings[0].layout);
            try std.testing.expectEqual(@as(u32, 1), context.jobs.items[0].templates[0].value);
            return err;
        };
        {
            var child = try context.enter(.{ .closure = .{ .unit = 2, .catalog = 3, .ty = 8, .captures = 9, .templates = 1, .evidence = 4, .rows = 5, .parameter_template = 2, .template_result = true } });
            defer child.deinit();
            try child.reserve(1);
            {
                var recursion = try context.enter(context.jobs.items[0].request);
                defer recursion.deinit();
                try recursion.hit(0);
                try std.testing.expectEqual(artifacts.State.reserved, context.jobs.items[0].state);
                try std.testing.expectEqual(parent.id, context.jobs.items[2].target_job);
            }
            try std.testing.expectEqual(child.id, context.active_job);
            try child.solved(&.{}, &.{}, &.{.{ .variable = 5, .value = 2 }});
            try child.complete(1, 2);
        }
        try std.testing.expectEqual(parent.id, context.active_job);
        {
            var constant = try context.enter(.{ .constant = .{ .target = .{ .unit = 1, .binding = 7 }, .ty = types.f32_type } });
            defer constant.deinit();
            try constant.completeValue(3, types.f32_type);
        }
        {
            var global = try context.enter(.{ .runtime_global = .{ .unit = 1, .binding = 8 } });
            defer global.deinit();
            try global.completeGlobal(0);
        }
        {
            var hit = try context.enter(.{ .runtime_global = .{ .unit = 1, .binding = 8 } });
            defer hit.deinit();
            try hit.hitGlobal(0);
        }
        for (0..32) |i| {
            var wrapper = try context.enter(.{ .callable = .{ .target = .{ .unit = 3, .binding = @intCast(i + 1) }, .ty = 8, .applied = 1 } });
            defer wrapper.deinit();
            try wrapper.reserve(@intCast(i + 2));
            try wrapper.complete(@intCast(i + 2), null);
        }
        try parent.complete(0, 1);
    }
    try std.testing.expectEqual(@as(u32, 0), context.active_job);
    try std.testing.expectEqual(artifacts.State.complete, context.jobs.items[0].state);
    try std.testing.expectEqual(@as(?u32, 1), context.jobs.items[0].result_template);
    try std.testing.expectEqual(@as(u32, 1), context.function_jobs.items[0]);
    try std.testing.expectEqual(@as(u32, 2), context.function_jobs.items[1]);
    try std.testing.expectEqual(@as(?u32, null), context.jobs.items[3].function);
    try std.testing.expectEqual(@as(u32, 3), context.jobs.items[3].value.?.value);
    try std.testing.expectEqual(@as(u32, 5), context.jobs.items[5].target_job);
    try std.testing.expectEqual(@as(?u32, null), context.jobs.items[4].function);
    const last = context.events.items[context.events.items.len - 1].event.leave;
    try std.testing.expectEqual(@as(u32, 1), last.job);
    try std.testing.expectEqual(@as(u32, 0), last.parent);
    for (context.events.items[1..], context.events.items[0 .. context.events.items.len - 1]) |next, previous| try std.testing.expect(next.sequence > previous.sequence);
    try std.testing.expectEqual(context.clock, context.events.items[context.events.items.len - 1].sequence + 1);
    try std.testing.expect(context.clock > context.events.items.len);
}
test "artifact demand graph preserves recursive reservations, solved ownership and chronological parent restoration" {
    try graphScenario(a);
}
test "artifact graph publication and parent restoration release every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, graphScenario, .{});
}

const Fixture = struct {
    units: []core.Module,
    names: runtime_identity.Metadata,
    names_alive: bool = true,
    folded: core.BindingRef,
    factory: core.BindingRef,
    retained: core.BindingRef,
    item: core.BindingRef,
    right: u32,
    left: u32,
    fn init() !Fixture {
        const source =
            \\type Cell is data = #Cell { right: F32, left: U32 }
            \\effect Read: Unit -> F32
            \\const reader = @effect.provider Read (fn () => 42.5)
            \\const factory = fn amount => fn extra => @f32.add amount extra
            \\const retained = factory 40.0
            \\const item = #Cell { right: 42.5, left: 1 }
            \\entry const folded = do reader:
            \\  return Read ()
            \\entry const answer = fn () => folded
        ;
        var lexed = try lexer.lex(a, source);
        defer lexed.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, source, lexed.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("artifact fixture {s}:{d}\n", .{ issue.message(), issue.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        units[0].unit = 1;
        try std.testing.expectEqual(@as(usize, 0), units[0].diagnostics.len);
        var names = try runtime_identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/artifact-fixture/main.blot" }}, 1);
        errdefer names.deinit(a);
        return .{ .units = units, .names = names, .folded = binding(units[0], "folded"), .factory = binding(units[0], "factory"), .retained = binding(units[0], "retained"), .item = binding(units[0], "item"), .right = try pool.intern(a, "right"), .left = try pool.intern(a, "left") };
    }
    fn binding(module: core.Module, name: []const u8) core.BindingRef {
        for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = 1, .binding = body.binding };
        // Nonexported names are intentionally not a codegen ABI. Resolve them
        // from the source order in this small fixture's checked binding table.
        if (std.mem.eql(u8, name, "factory")) return .{ .unit = 1, .binding = module.bodies[1].binding };
        if (std.mem.eql(u8, name, "retained")) return .{ .unit = 1, .binding = module.bodies[2].binding };
        if (std.mem.eql(u8, name, "item")) return .{ .unit = 1, .binding = module.bodies[3].binding };
        unreachable;
    }
    fn deinit(self: *Fixture) void {
        self.deinitNames();
        self.units[0].deinit(a);
        a.free(self.units);
    }
    fn deinitNames(self: *Fixture) void {
        if (self.names_alive) self.names.deinit(a);
        self.names_alive = false;
    }
};
const SerializedKey = struct { value: core_eval.ValueId, ty: layout.Id, suspension: bool = false };
const RuntimeSlot = struct { global: u32, initializer: u32, active: bool = false };
/// The capture API sees the same owners as a Generator without importing it.
/// Actual backend+Wasm replay is exercised separately by the recorder tests.
const Generator = struct {
    units: []const core.Module,
    evaluator: core_eval.Session,
    layouts: layout.Store,
    representation_bridge: ?bridge.Store = null,
    row_keys: substitutions.Store,
    template_keys: substitutions.Store,
    template_catalog: std.ArrayList(artifacts.CapturedTemplate) = .empty,
    runtime_operations: runtime_operations.Store,
    instances: std.AutoHashMapUnmanaged(artifacts.Key, u32) = .empty,
    template_results: std.AutoHashMapUnmanaged(artifacts.Key, u32) = .empty,
    closures: std.AutoHashMapUnmanaged(artifacts.ClosureKey, u32) = .empty,
    closure_template_results: std.AutoHashMapUnmanaged(artifacts.ClosureKey, u32) = .empty,
    callables: std.AutoHashMapUnmanaged(artifacts.CallableKey, u32) = .empty,
    constructor_functions: std.AutoHashMapUnmanaged(artifacts.ConstructorKey, u32) = .empty,
    primitive_functions: std.AutoHashMapUnmanaged(artifacts.PrimitiveKey, u32) = .empty,
    operation_functions: std.AutoHashMapUnmanaged(artifacts.OperationKey, u32) = .empty,
    host_functions: std.AutoHashMapUnmanaged(layout.Id, u32) = .empty,
    serialized: std.AutoHashMapUnmanaged(SerializedKey, u32) = .empty,
    runtime_globals: std.AutoHashMapUnmanaged(core.BindingRef, RuntimeSlot) = .empty,
    runtime_order: std.ArrayList(u32) = .empty,
    array_proofs: std.AutoHashMapUnmanaged(u32, owned_arrays.Proof) = .empty,
    discard_proofs: std.AutoHashMapUnmanaged(u32, discarded_bindings.Proof) = .empty,
    physical: u32 = 0,
    function_shape: u32 = 0,
    semantic_row: u32 = 0,
    layout_row: u32 = 0,
    template_key: u32 = 0,
    row_key: u32 = 0,
    folded_value: u32 = 0,
    item_value: u32 = 0,
    operation: u32 = 0,
    fn init(fixture: *const Fixture) !Generator {
        var evaluator = try core_eval.Session.init(a, fixture.units);
        const layouts = layout.Store.init(a) catch |err| {
            evaluator.deinit();
            return err;
        };
        var result: Generator = .{ .units = fixture.units, .evaluator = evaluator, .layouts = layouts, .row_keys = substitutions.Store.init(a), .template_keys = substitutions.Store.init(a), .runtime_operations = runtime_operations.Store.initProject(a, fixture.names.view()) };
        errdefer result.deinit();
        result.physical = try result.layouts.intern(.record, 0, 0, &.{ fixture.right, types.f32_type, fixture.left, types.u32_type });
        const semantic_label = try result.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = 23 }, &.{types.f32_type});
        result.semantic_row = try result.evaluator.evidence.effects.internRow(&.{ semantic_label, semantic_label });
        const physical_label = try result.layouts.effects.internOperation(.{ .unit = 1, .decl = 23 }, &.{types.f32_type});
        result.layout_row = try result.layouts.effects.internRow(&.{ physical_label, physical_label });
        result.function_shape = try result.layouts.internWithEffects(.function, types.f32_type, types.f32_type, result.layout_row, &.{});
        result.representation_bridge = try bridge.Store.init(a, &result.layouts, &result.evaluator.evidence);
        _ = try result.representation_bridge.?.toEvidence(@fromBackingInt(@intCast(result.physical)));
        _ = try result.representation_bridge.?.toCodeExpectation(@fromBackingInt(@intCast(result.function_shape)));
        result.folded_value = try result.evaluator.richValue(fixture.folded);
        result.item_value = try result.evaluator.richValue(fixture.item);
        _ = try result.evaluator.richValue(fixture.retained);
        result.row_key = try result.row_keys.intern(&.{ .{ .variable = 1, .value = result.semantic_row }, .{ .variable = 2, .value = 0 } });
        result.template_key = try result.template_keys.intern(&.{.{ .variable = 8, .value = 1 }});
        var closure_node: u32 = 0;
        for (fixture.units[0].nodes, 0..) |node, index| if (node.tag == .closure) {
            closure_node = @intCast(index);
            break;
        };
        try std.testing.expect(closure_node != 0);
        try result.template_catalog.append(a, .{ .unit = 1, .node = closure_node, .captures = result.physical, .templates = 0, .has_environment = true, .evidence = types.f32_type, .rows = result.row_key });
        try result.template_catalog.append(a, .{ .unit = 1, .node = closure_node, .captures = result.physical, .templates = result.template_key, .has_environment = true, .computation = true, .evidence = types.f32_type, .rows = result.row_key });
        const named: artifacts.Key = .{ .target = fixture.factory, .count = 1, .result = result.function_shape, .templates = result.template_key, .template_result = true };
        try result.instances.put(a, named, 0);
        try result.template_results.put(a, named, 2);
        const closure: artifacts.ClosureKey = .{ .unit = 1, .catalog = 0, .ty = result.function_shape, .captures = result.physical, .templates = result.template_key, .evidence = types.f32_type, .rows = result.row_key, .parameter_template = 1, .template_result = true };
        try result.closures.put(a, closure, 1);
        try result.closure_template_results.put(a, closure, 2);
        try result.callables.put(a, .{ .target = fixture.factory, .ty = result.function_shape, .applied = 1 }, 2);
        try result.constructor_functions.put(a, .{ .unit = 1, .catalog = 0, .ty = result.function_shape }, 3);
        result.operation = try result.runtime_operations.intern(result.evaluator.evidence.view(), semantic_label);
        try result.operation_functions.put(a, .{ .operation = result.operation, .ty = result.function_shape }, 4);
        try result.host_functions.put(a, result.function_shape, 5);
        try result.serialized.put(a, .{ .value = result.item_value, .ty = result.physical }, 32);
        try result.runtime_globals.put(a, fixture.item, .{ .global = 0, .initializer = 6 });
        try result.runtime_order.append(a, 6);
        const updates = try a.dupe(bool, &.{ false, true });
        result.array_proofs.put(a, 1, .{ .updates = updates }) catch |err| {
            a.free(updates);
            return err;
        };
        const unused = try a.dupe(bool, &.{ true, false });
        result.discard_proofs.put(a, 1, .{ .unused = unused }) catch |err| {
            a.free(unused);
            return err;
        };
        var module = wasm.Module.init(a);
        defer module.deinit();
        const function = try module.addFunction(&.{}, .i32);
        try result.runtime_operations.emit(&module, function, result.operation);
        const address = try module.dataWords(&.{0});
        try result.runtime_operations.dataWord(&module, address, result.operation);
        try result.runtime_operations.finish(&module);
        return result;
    }
    fn deinit(self: *Generator) void {
        if (self.representation_bridge) |*value| value.deinit();
        self.evaluator.deinit();
        self.layouts.deinit();
        self.row_keys.deinit();
        self.template_keys.deinit();
        self.template_catalog.deinit(a);
        self.runtime_operations.deinit();
        self.instances.deinit(a);
        self.template_results.deinit(a);
        self.closures.deinit(a);
        self.closure_template_results.deinit(a);
        self.callables.deinit(a);
        self.constructor_functions.deinit(a);
        self.primitive_functions.deinit(a);
        self.operation_functions.deinit(a);
        self.host_functions.deinit(a);
        self.serialized.deinit(a);
        self.runtime_globals.deinit(a);
        self.runtime_order.deinit(a);
        var arrays = self.array_proofs.valueIterator();
        while (arrays.next()) |proof| proof.deinit(a);
        self.array_proofs.deinit(a);
        var discards = self.discard_proofs.valueIterator();
        while (discards.next()) |proof| proof.deinit(a);
        self.discard_proofs.deinit(a);
    }
};

fn verify(pool: *const artifacts.Pools, fixture: *const Fixture, physical: u32, folded_value: u32, template_key: u32, row_key: u32) !void {
    try std.testing.expect(pool.project_identity);
    try std.testing.expectEqualStrings("/artifact-fixture/main.blot", pool.modules[0].canonical_path);
    try std.testing.expectEqualStrings("/artifact-fixture/main.blot", pool.identity.?.view().owner(1).?);
    try std.testing.expectEqualStrings("right", pool.identity.?.view().symbol(fixture.right).?);
    try std.testing.expectEqualSlices(u32, &.{ fixture.right, types.f32_type, fixture.left, types.u32_type }, pool.layouts.children(physical));
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42.5))), pool.evaluator.values[folded_value].bits);
    try std.testing.expect(pool.evaluator.closures.len != 0);
    try std.testing.expect(pool.evaluator.children.len != 0);
    try std.testing.expectEqual(@as(usize, 2), pool.field_locations.len);
    var right_found = false;
    for (pool.field_locations) |field| if (field.name == fixture.right) {
        right_found = true;
        try std.testing.expectEqual(@as(u32, 0), field.field);
        try std.testing.expectEqual(@as(u32, 2), field.len);
    };
    try std.testing.expect(right_found);
    try std.testing.expectEqual(@as(u32, 1), pool.templates.get(template_key)[0].value);
    try std.testing.expectEqual(@as(u32, 0), pool.rows.get(row_key)[1].value);
    try std.testing.expectEqual(template_key, pool.captures[1].templates);
    try std.testing.expectEqual(row_key, pool.captures[1].rows);
    try std.testing.expectEqual(@as(usize, 6), pool.functions.len);
    try std.testing.expectEqual(@as(?u32, 2), pool.functions[0].result_template);
    try std.testing.expectEqual(@as(?u32, 2), pool.functions[1].result_template);
    try std.testing.expectEqual(@as(u32, 32), pool.serialized[0].address);
    try std.testing.expectEqual(@as(u32, 6), pool.runtime_globals[0].initializer);
    try std.testing.expectEqualSlices(u32, &.{6}, pool.runtime_order);
    try std.testing.expect(pool.bridge.?.nodes.len > 6);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, pool.array_proofs[0].updates);
    try std.testing.expectEqualSlices(bool, &.{ true, false }, pool.discard_proofs[0].unused);
    try std.testing.expectEqual(@as(usize, 2), pool.operation_relocations.len);
    try std.testing.expect(pool.operations_finalized);
    try std.testing.expect(pool.operations[0].runtime != 0);
    try std.testing.expect(pool.operations[0].key.len != 0);
    try std.testing.expectEqualSlices(u8, &artifacts.stamp(fixture.units[0]), &pool.modules[0].stamp);
    try std.testing.expectEqualSlices(u8, &artifacts.stamp(pool.field_locations), &pool.field_locations_stamp);
    for (pool.bodies) |body| {
        try std.testing.expectEqualSlices(u8, &pool.modules[0].stamp, &body.module_stamp);
        try std.testing.expectEqualSlices(u8, &artifacts.stamp(.{ body.module_stamp, body.body }), &body.stamp);
    }
}
test "artifact pools survive evaluator layout template identity teardown with physical catalog order and nested captures" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var generator = try Generator.init(&fixture);
    var live = true;
    defer if (live) generator.deinit();
    var context = artifacts.Context.init(a);
    defer context.deinit();
    const physical = generator.physical;
    const folded_value = generator.folded_value;
    const template_key = generator.template_key;
    const row_key = generator.row_key;
    try context.capturePools(&generator, fixture.names.view());
    try std.testing.expect(context.pools.?.layouts.nodes.ptr != generator.layouts.nodes.items.ptr);
    try std.testing.expect(context.pools.?.evaluator.values.ptr != generator.evaluator.values.items.ptr);
    try std.testing.expect(context.pools.?.identity.?.bytes.ptr != fixture.names.bytes.ptr);
    try std.testing.expect(context.pools.?.modules[0].module == &fixture.units[0]);
    // Mutation of every live catalog domain cannot rewrite published metadata.
    generator.layouts.extra.items[generator.layouts.nodes.items[physical].a] = fixture.left;
    generator.evaluator.values.items[folded_value].bits = 0;
    generator.template_catalog.items[1].templates = 0;
    generator.template_keys.entries.items[0].value = 99;
    generator.row_keys.entries.items[1].value = 99;
    @memset(generator.runtime_operations.entries.items[0].key, 0);
    generator.deinit();
    live = false;
    fixture.deinitNames();
    try verify(&context.pools.?, &fixture, physical, folded_value, template_key, row_key);
}
fn captureFailureScenario(allocator: Allocator, fixture: *const Fixture, generator: *Generator) !void {
    var context = artifacts.Context.init(allocator);
    defer context.deinit();
    try context.capturePools(generator, fixture.names.view());
    const old_identity = context.pools.?.identity.?.bytes.ptr;
    const old_values = context.pools.?.evaluator.values.ptr;
    const old_stamp = context.pools.?.field_locations_stamp;
    context.capturePools(generator, fixture.names.view()) catch |err| {
        try std.testing.expect(old_identity == context.pools.?.identity.?.bytes.ptr);
        try std.testing.expect(old_values == context.pools.?.evaluator.values.ptr);
        try std.testing.expectEqual(@as(u64, 1), context.pools.?.generation);
        try std.testing.expectEqualSlices(u8, &old_stamp, &context.pools.?.field_locations_stamp);
        try verify(&context.pools.?, fixture, generator.physical, generator.folded_value, generator.template_key, generator.row_key);
        return err;
    };
    try std.testing.expectEqual(@as(u64, 2), context.pools.?.generation);
    try verify(&context.pools.?, fixture, generator.physical, generator.folded_value, generator.template_key, generator.row_key);
}
test "artifact complete pool publication and replacement preserve previous owners through every allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var generator = try Generator.init(&fixture);
    defer generator.deinit();
    // Imported scratch lookup caches are absent from the finished pools; their
    // semantic outputs, not borrowed hash-table storage, are the retained data.
    try captureFailureScenario(a, &fixture, &generator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, captureFailureScenario, .{ &fixture, &generator });
}
