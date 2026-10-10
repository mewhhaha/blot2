//! Private owned source-value-template laws. Parser/checker owners are destroyed
//! by Fixture.init; immutable Core and the owned old capture remain alive.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const artifacts = @import("code_artifacts.zig");
const capture = @import("artifact_capture.zig");
const identity = @import("runtime_identity.zig");
const eval = @import("core_eval.zig");
const evidence = @import("type_evidence.zig");
const layout = @import("layout.zig");
const substitutions = @import("substitution_keys.zig");
const runtime_operations = @import("runtime_operations.zig");
const gate_api = @import("principal_reuse_gate.zig");
const graph = @import("source_value_template.zig");
const Allocator = std.mem.Allocator;
const a = std.testing.allocator;
const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    binding_names: []u32,
    entry: u32 = 1,

    fn init(source: []const u8) !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var names: symbols.Pool = .{};
        defer names.deinit(a);
        // Both catalog edits retain their complete qualified spellings in the
        // same namespace, so rejection exercises changed Core catalog facts.
        _ = try names.intern(a, "U32.add");
        _ = try names.intern(a, "U32.sub");
        _ = try names.intern(a, "@u32.add");
        _ = try names.intern(a, "@u32.sub");
        var tree = try parser.parse(a, source, tokens.tokens.items, &names);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("principal fixture check {s}: {s} at {d}\n", .{ @tagName(issue.code), issue.message(), issue.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &names, &checked);
        errdefer units[0].deinit(a);
        try std.testing.expectEqual(@as(usize, 0), units[0].diagnostics.len);
        var metadata = try identity.Metadata.capture(a, &names, &.{.{ .unit = 1, .path = "/closed-result/main.blot" }}, 1);
        errdefer metadata.deinit(a);
        const binding_names = try a.alloc(u32, checked.bindings.len);
        for (checked.bindings, binding_names) |binding, *name| name.* = binding.name;
        return .{ .units = units, .names = metadata, .binding_names = binding_names };
    }

    fn target(self: *const Fixture, name: []const u8) core.BindingRef {
        // Lowering may append operation bindings; only checked declarations
        // have source spellings in this fixture's retained name table.
        for (self.binding_names, 0..) |spelling, id| if (self.units[self.entry - 1].bindings[id].kind == .global and spelling != 0 and std.mem.eql(u8, self.names.view().symbol(spelling).?, name)) return .{ .unit = self.entry, .binding = @intCast(id) };
        unreachable;
    }
    fn project(dir: *const std.testing.TmpDir) !Fixture {
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        defer a.free(path);
        const prelude = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        defer a.free(prelude);
        var loaded = try @import("project.zig").load(a, std.testing.io, path, .{ .prelude_path = prelude });
        defer loaded.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
        var checked = try @import("project_check.zig").checkProject(a, &loaded);
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("anchor project {s}:{d}\n", .{ issue.codeName(), issue.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, loaded.units.items.len);
        errdefer a.free(units);
        var initialized: usize = 0;
        errdefer for (units[0..initialized]) |*unit| unit.deinit(a);
        for (units, 1..) |*unit, id| {
            unit.* = try core.lower(a, &loaded.unit(@intCast(id)).tree, &loaded.symbols, &checked.module(@intCast(id)).checked);
            initialized += 1;
            unit.unit = @intCast(id);
        }
        const owners = try a.alloc(identity.Owner, units.len);
        defer a.free(owners);
        for (owners, 1..) |*owner, unit| owner.* = .{ .unit = @intCast(unit), .path = loaded.filename(@intCast(unit)) };
        var names = try identity.Metadata.capture(a, &loaded.symbols, owners, units.len);
        errdefer names.deinit(a);
        const bindings = checked.module(loaded.entry).checked.bindings;
        const binding_names = try a.alloc(u32, bindings.len);
        for (bindings, binding_names) |binding, *name| name.* = binding.name;
        return .{ .units = units, .names = names, .binding_names = binding_names, .entry = loaded.entry };
    }

    fn emit(self: *const Fixture, allocator: std.mem.Allocator, options: backend.CompileOptions) !backend.Result {
        var configured = options;
        configured.identity = self.names.view();
        return backend.compileWithOptions(allocator, self.units, self.entry, configured);
    }

    fn deinit(self: *Fixture) void {
        for (self.units) |*unit| unit.deinit(a);
        a.free(self.units);
        self.names.deinit(a);
        a.free(self.binding_names);
        self.* = undefined;
    }
};

const Generator = struct {
    allocator: Allocator,
    evaluator: eval.Session,
    layouts: layout.Store,
    row_keys: substitutions.Store,
    template_keys: substitutions.Store,
    static_keys: substitutions.Store,
    template_catalog: std.ArrayList(artifacts.CapturedTemplate) = .empty,
    template_instances: std.AutoHashMapUnmanaged(artifacts.CapturedTemplate, u32) = .empty,
    runtime_operations: runtime_operations.Store,
    fn init(fixture: *const Fixture) !Generator {
        return initAt(a, fixture);
    }
    fn initAt(allocator: Allocator, fixture: *const Fixture) !Generator {
        var evaluator = try eval.Session.init(allocator, fixture.units);
        errdefer evaluator.deinit();
        // Mirror the backend's startup source-creation mode. Receipt option
        // equality remains exact; this test consumer is the same kind of owner.
        evaluator.options.retain_source_suspensions = true;
        return .{ .allocator = allocator, .evaluator = evaluator, .layouts = try layout.Store.init(allocator), .row_keys = substitutions.Store.init(allocator), .template_keys = substitutions.Store.init(allocator), .static_keys = substitutions.Store.init(allocator), .runtime_operations = runtime_operations.Store.initProject(allocator, fixture.names.view()) };
    }
    fn deinit(self: *Generator) void {
        self.template_instances.deinit(self.allocator);
        self.template_catalog.deinit(self.allocator);
        self.runtime_operations.deinit();
        self.row_keys.deinit();
        self.template_keys.deinit();
        self.static_keys.deinit();
        self.layouts.deinit();
        self.evaluator.deinit();
    }
};

const fixture_source =
    \\type Bundle is data = #Bundle { answer: U32, read: U32 -> U32 }
    \\const factory = fn (number: U32) => fn (extra: U32) => @u32.add number extra
    \\entry const schema: U32 = 7
    \\const bundle = #Bundle { answer: 42, read: factory 40 }
    \\entry const answer: U32 = bundle.read 2
;
const unsolved_source =
    \\type Bundle read is data = #Bundle { read: read, callbacks: Array read }
    \\const factory = fn number => fn extra => number
    \\entry const schema: U32 = 7
    \\const bundle = do:
    \\  let read = factory 42
    \\  return #Bundle { read: read, callbacks: @array.generate 1 (fn (index: U32) => read) }
    \\entry const answer: U32 = bundle.read ()
;
fn successful(result: *const backend.Result) !void {
    if (result.diagnostic) |issue| std.debug.print("source template backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
}
fn editSchema(after: *Fixture) void {
    const target = after.target("schema");
    after.units[target.unit - 1].nodes[after.units[target.unit - 1].body(target.binding).?.root].a = 8;
}
fn inspect(a2: Allocator, before: *const capture.Capture, gate: *const gate_api.Gate, target: core.BindingRef) !graph.Plan {
    if (!gate.enabled) std.debug.print("gate enabled {any}, structural {any}, units {d}\n", .{ gate.enabled, gate.structural_units, gate.units.len });
    const found = try graph.Plan.inspect(a2, &before.metadata.pools.?, gate, target);
    if (found.reason != .none) std.debug.print("graph inspection {s}, stats {any}\n", .{ @tagName(found.reason), found.stats });
    try std.testing.expectEqual(graph.Reason.none, found.reason);
    return found.plan orelse error.ExpectedPlan;
}
fn sameType(old: evidence.View, old_id: u32, current: evidence.View, id: u32) !void {
    const left = old.node(old_id);
    const right = current.node(id);
    try std.testing.expectEqual(left.tag, right.tag);
    switch (left.tag) {
        .unit, .boolean, .u32, .f32, .never => try std.testing.expectEqual(left, right),
        .function => {
            try sameType(old, left.a, current, right.a);
            try sameType(old, left.b, current, right.b);
            try std.testing.expectEqual(@as(u32, 0), left.c);
            try std.testing.expectEqual(@as(u32, 0), right.c);
        },
        .array => try sameType(old, left.a, current, right.a),
        .product, .record, .nominal => {
            if (left.tag == .nominal) {
                try std.testing.expectEqual(left.a, right.a);
                try std.testing.expectEqual(left.b, right.b);
            }
            const children = old.children(old_id);
            const actual = current.children(id);
            try std.testing.expectEqual(children.len, actual.len);
            for (children, actual, 0..) |child, value, index| {
                if (left.tag == .record and index % 2 == 0) try std.testing.expectEqual(child, value) else try sameType(old, child, current, value);
            }
        },
        else => return error.UnexpectedOpenTransportEvidence,
    }
}
fn sameValue(old: *const eval.Snapshot, old_id: eval.ValueId, current: *const eval.Session, id: eval.ValueId) !void {
    if (old.value_evidence[old_id] == 0) try std.testing.expectEqual(@as(u32, 0), current.valueEvidence(id)) else try sameType(old.evidence.view(), old.value_evidence[old_id], current.evidenceView(), current.valueEvidence(id));
    const before = old.values[old_id];
    const after = current.valueInfo(id);
    try std.testing.expectEqual(before.kind, after.kind);
    try std.testing.expectEqual(before.scalar, after.scalar);
    try std.testing.expectEqual(before.nominal, after.nominal);
    if (before.kind == .closure) {
        const left = old.closures[before.bits];
        const right = current.closureInfo(id);
        try std.testing.expectEqual(left.unit, right.unit);
        try std.testing.expectEqual(left.identity, right.identity);
        try std.testing.expectEqual(left.origin, right.origin);
        try std.testing.expectEqual(left.applied, right.applied);
        try std.testing.expectEqual(left.ty, right.ty);
        try std.testing.expectEqual(left.mappings.len, right.mappings.len);
        try std.testing.expectEqual(left.row_mappings.len, right.row_mappings.len);
        for (old.type_mappings[left.mappings.start..][0..left.mappings.len], current.type_mappings.items[right.mappings.start..][0..right.mappings.len]) |mapping, actual| {
            try std.testing.expectEqual(mapping.variable, actual.variable);
            try sameType(old.evidence.view(), mapping.evidence, current.evidenceView(), actual.evidence);
        }
        try std.testing.expectEqualSlices(evidence.RowMapping, old.row_mappings[left.row_mappings.start..][0..left.row_mappings.len], current.row_mappings.items[right.row_mappings.start..][0..right.row_mappings.len]);
    } else try std.testing.expectEqual(before.bits, after.bits);
    const children = old.children[before.start..][0..before.len];
    try std.testing.expectEqual(children.len, current.valueChildren(id).len);
    for (children, current.valueChildren(id)) |child, actual| try sameValue(old, child, current, actual);
    const rec = old.value_records[old_id];
    if (rec != 0) {
        const fields = old.record_layouts[rec];
        try std.testing.expectEqualSlices(u32, old.field_names[fields.start..][0..fields.len], current.recordFieldNames(id));
    }
}
fn importedAnswer(g: *Generator, fixture: *const Fixture, plan: *const graph.Plan, imported: eval.ValueId) !void {
    return importedAnswerFor(g, fixture, plan, imported, .{ .scalar = .u32, .bits = 42 });
}
fn importedAnswerFor(g: *Generator, fixture: *const Fixture, plan: *const graph.Plan, imported: eval.ValueId, expected: eval.Value) !void {
    // The production path never publishes this slot. The law supplies the
    // already-imported representation to normal fresh expression/call checking,
    // so actual closure capture behavior is exercised instead of ID equality.
    const target = fixture.target("bundle");
    const slot = g.evaluator.binding_offsets[target.unit - 1] + target.binding;
    try std.testing.expectEqual(@as(usize, 0), g.evaluator.steps);
    try sameValue(&plan.pools.evaluator, plan.root, &g.evaluator, imported);
    g.evaluator.slots[slot] = .{ .state = .complete, .value = imported };
    const value = try g.evaluator.value(fixture.target("answer"));
    try std.testing.expectEqual(expected, value);
    try std.testing.expect(g.evaluator.steps > 0);
}
test "source template imports real record closure captures into a fresh owner and normal evaluation returns 42" {
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    try std.testing.expect(plan.stats.closures > 0);
    var g = try Generator.init(&after);
    defer g.deinit();
    // Unrelated semantic allocation changes current graph IDs without changing
    // source identities or merging the old and current table owners.
    _ = try g.evaluator.evidence.intern(.array, 4, 0, &.{});
    const imported = try plan.materialize(&g);
    try importedAnswer(&g, &after, &plan, imported);
    try std.testing.expect(g.evaluator.values.items.ptr != plan.pools.evaluator.values.ptr);
    try std.testing.expect(g.evaluator.evidence.nodes.items.ptr != plan.pools.evaluator.evidence.nodes.ptr);
    const declined = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target("schema"));
    try std.testing.expectEqual(graph.Reason.source, declined.reason);
    try std.testing.expect(declined.plan == null);
}
fn oomImport(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, gate: *const gate_api.Gate) !void {
    const old_stamp = artifacts.stamp(old.metadata.pools.?.evaluator.values);
    var plan = try inspect(allocator, old, gate, fixture.target("bundle"));
    defer plan.deinit(allocator);
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    const values = g.evaluator.values.items.len;
    const children = g.evaluator.children.items.len;
    const closures = g.evaluator.closures.items.len;
    const records = g.evaluator.record_layouts.items.len;
    const parallel = .{ g.evaluator.value_evidence.items.len, g.evaluator.value_records.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.field_names.items.len, g.evaluator.demands.items.len, g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count() };
    const slots = artifacts.stamp(g.evaluator.slots);
    const imported = plan.materialize(&g) catch |err| {
        try std.testing.expectEqual(values, g.evaluator.values.items.len);
        try std.testing.expectEqual(children, g.evaluator.children.items.len);
        try std.testing.expectEqual(closures, g.evaluator.closures.items.len);
        try std.testing.expectEqual(records, g.evaluator.record_layouts.items.len);
        const now = .{ g.evaluator.value_evidence.items.len, g.evaluator.value_records.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.field_names.items.len, g.evaluator.demands.items.len, g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count() };
        inline for (parallel, now) |previous, actual| try std.testing.expectEqual(previous, actual);
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        try std.testing.expectEqualSlices(u8, &old_stamp, &artifacts.stamp(old.metadata.pools.?.evaluator.values));
        return err;
    };
    try importedAnswer(&g, fixture, &plan, imported);
    try std.testing.expectEqualSlices(u8, &old_stamp, &artifacts.stamp(old.metadata.pools.?.evaluator.values));
}
test "source template exhaustive allocation failure leaves value and slot publication untouched" {
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, oomImport, .{ &after, &initial.capture.?, &gate });
}
test "source template rejects a foreign fresh evaluator owner and quotas before publication" {
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var wrong = try Fixture.init(fixture_source);
    defer wrong.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var foreign = try Generator.init(&wrong);
    defer foreign.deinit();
    try std.testing.expectError(error.Declined, plan.materialize(&foreign));
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.max_values = g.evaluator.values.items.len;
    try std.testing.expectError(error.Declined, plan.materialize(&g));
    try std.testing.expectEqual(@as(usize, 1), g.evaluator.values.items.len);
    try std.testing.expectEqual(@as(usize, 0), g.evaluator.steps);
}

test "source template independently imports F32 captures without sharing U32 evidence ordinals" {
    const floating =
        \\type Bundle is data = #Bundle { answer: F32, read: F32 -> F32 }
        \\const factory = fn (number: F32) => fn (extra: F32) => @f32.add number extra
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { answer: 42.0, read: factory 40.0 }
        \\entry const answer: F32 = bundle.read 2.0
    ;
    var before = try Fixture.init(floating);
    defer before.deinit();
    var after = try Fixture.init(floating);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    try importedAnswerFor(&g, &after, &plan, imported, .{ .scalar = .f32, .bits = @bitCast(@as(f32, 42.0)) });
}
test "source template declines actual provider and State captures instead of preserving old numeric domains" {
    const provider_source =
        \\effect Read: Unit -> F32
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\const reader = @effect.provider Read (fn () => 1.75)
        \\const state = @effect.state (State.get F32) (State.set F32) 1.75
        \\entry const schema: U32 = 7
        \\entry const folded = do reader:
        \\  return Read ()
        \\entry const answer = fn (value: F32) => do:
        \\  let (next, old) = do state:
        \\    use old <- State.get F32 ()
        \\    use State.set F32 (@f32.add old value)
        \\    return old
        \\  return @f32.add next old
    ;
    var before = try Fixture.init(provider_source);
    defer before.deinit();
    var after = try Fixture.init(provider_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    for ([_]struct { name: []const u8, kind: eval.ValueKind }{ .{ .name = "reader", .kind = .provider }, .{ .name = "state", .kind = .state_provider } }) |case| {
        const found = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target(case.name));
        try std.testing.expectEqual(graph.Reason.domain, found.reason);
        try std.testing.expect(found.plan == null);
        try std.testing.expect(found.stats.unsupported_kinds[@backingInt(case.kind)] > 0);
        const target = after.target(case.name);
        const pools = &initial.capture.?.metadata.pools.?;
        const root = pools.slots[pools.binding_offsets[target.unit - 1] + target.binding].value;
        const rows = try graph.Plan.inspectRootsWithRows(a, pools, &gate, &.{root}, .source_declared);
        try std.testing.expectEqual(graph.Reason.domain, rows.reason);
        try std.testing.expect(rows.plan == null);
        try std.testing.expect(rows.stats.unsupported_kinds[@backingInt(case.kind)] > 0);
    }
}
test "source template declines active waiting values before admitting an independent scalar root" {
    const pending_source =
        \\entry const scalar: U32 = 42
        \\const keep = fn ~(value: U32) => value
        \\const pending = keep 42
        \\entry const schema: U32 = 7
        \\entry const answer = fn () => @force pending
    ;
    var before = try Fixture.init(pending_source);
    defer before.deinit();
    var after = try Fixture.init(pending_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    const found = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target("pending"));
    try std.testing.expectEqual(graph.Reason.open_evidence, found.reason);
    try std.testing.expect(found.plan == null);
    try std.testing.expect(found.stats.unsupported_kinds[@backingInt(eval.ValueKind.suspension)] > 0);
    var scalar = try inspect(a, &initial.capture.?, &gate, after.target("scalar"));
    defer scalar.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try scalar.materialize(&g);
    try std.testing.expectEqual(@as(u32, 42), g.evaluator.valueScalar(imported).?.bits);
}

test "source template rejects independently valid old pools even when source identity ordinals collide" {
    const alternate_source =
        \\type Bundle is data = #Bundle { answer: U32, read: U32 -> U32 }
        \\const factory = fn (number: U32) => fn (extra: U32) => @u32.add number extra
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { answer: 42, read: factory 39 }
        \\entry const answer: U32 = bundle.read 2
    ;
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var foreign = try Fixture.init(alternate_source);
    defer foreign.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var other = try foreign.emit(a, .{ .retain_artifacts = true });
    defer other.deinit(a);
    try successful(&initial);
    try successful(&other);
    try std.testing.expectEqualDeep(before.names.view(), foreign.names.view());
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.admits(after.target("bundle")));
    const found = try graph.Plan.inspect(a, &other.capture.?.metadata.pools.?, &gate, after.target("bundle"));
    try std.testing.expectEqual(graph.Reason.owner, found.reason);
    try std.testing.expect(found.plan == null);
}
test "source template imported closure and record storage survive complete old artifact and Core destruction" {
    var before = try Fixture.init(fixture_source);
    var before_live = true;
    defer if (before_live) before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    var initial_live = true;
    defer if (initial_live) initial.deinit(a);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    var gate_live = true;
    defer if (gate_live) gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    var plan_live = true;
    defer if (plan_live) plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    try sameValue(&plan.pools.evaluator, plan.root, &g.evaluator, imported);
    plan.deinit(a);
    plan_live = false;
    gate.deinit();
    gate_live = false;
    initial.deinit(a);
    initial_live = false;
    before.deinit();
    before_live = false;
    const target = after.target("bundle");
    g.evaluator.slots[g.evaluator.binding_offsets[target.unit - 1] + target.binding] = .{ .state = .complete, .value = imported };
    try std.testing.expectEqual(eval.Value{ .scalar = .u32, .bits = 42 }, try g.evaluator.value(after.target("answer")));
}

test "source template keeps generic source variables and empty rows attached to the exact closure owner" {
    const generic_source =
        \\type Bundle is data = #Bundle { read: U32 -> U32 }
        \\const factory = fn number => fn (extra: U32) => number
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { read: factory 42 }
        \\entry const answer: U32 = bundle.read 2
    ;
    var before = try Fixture.init(generic_source);
    defer before.deinit();
    var after = try Fixture.init(generic_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    try std.testing.expect(plan.stats.type_maps > 0);
    var g = try Generator.init(&after);
    defer g.deinit();
    _ = try g.evaluator.evidence.intern(.array, 4, 0, &.{});
    const imported = try plan.materialize(&g);
    try importedAnswer(&g, &after, &plan, imported);
}
test "source template preserves distinct captures of the same callback source" {
    const distinct_source =
        \\type Bundle is data = #Bundle { first: U32 -> U32, second: U32 -> U32 }
        \\const factory = fn (number: U32) => fn (extra: U32) => @u32.add number extra
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { first: factory 40, second: factory 2 }
        \\entry const answer: U32 = @u32.add (bundle.first 0) (bundle.second 0)
    ;
    var before = try Fixture.init(distinct_source);
    defer before.deinit();
    var after = try Fixture.init(distinct_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    const payload = g.evaluator.valueChildren(imported);
    try std.testing.expectEqual(@as(usize, 1), payload.len);
    const fields = g.evaluator.valueChildren(payload[0]);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    const first = g.evaluator.closureInfo(fields[0]);
    const second = g.evaluator.closureInfo(fields[1]);
    try std.testing.expectEqual(first.identity, second.identity);
    try std.testing.expect(fields[0] != fields[1]);
    try std.testing.expectEqual(@as(u32, 40), g.evaluator.valueScalar(g.evaluator.valueChildren(fields[0])[0]).?.bits);
    try std.testing.expectEqual(@as(u32, 2), g.evaluator.valueScalar(g.evaluator.valueChildren(fields[1])[0]).?.bits);
    try importedAnswer(&g, &after, &plan, imported);
}

test "source template rejects malformed cycles and compiler-owned nominal identities before publishing a plan" {
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(fixture_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const pools = &initial.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    const target = after.target("bundle");
    const root = pools.slots[pools.binding_offsets[target.unit - 1] + target.binding].value;
    const index = pools.evaluator.values[root].start;
    const child = pools.evaluator.children[index];
    pools.evaluator.children[index] = root;
    const cycle = try graph.Plan.inspect(a, pools, &gate, target);
    try std.testing.expectEqual(graph.Reason.cycle, cycle.reason);
    try std.testing.expect(cycle.plan == null);
    pools.evaluator.children[index] = child;
    var valid = try inspect(a, &initial.capture.?, &gate, target);
    valid.deinit(a);
    const original = pools.evaluator.values[root].nominal;
    pools.evaluator.values[root].nominal = (@as(u64, std.math.maxInt(u32)) << 32) | 42;
    defer pools.evaluator.values[root].nominal = original;
    const unknown = try graph.Plan.inspect(a, pools, &gate, target);
    try std.testing.expect(unknown.reason == .domain);
    try std.testing.expect(unknown.plan == null);
}
test "source template declines changed callback source despite identical capture representation and namespace ordinals" {
    const changed_source =
        \\type Bundle is data = #Bundle { answer: U32, read: U32 -> U32 }
        \\const factory = fn (number: U32) => fn (extra: U32) => @u32.sub number extra
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { answer: 42, read: factory 40 }
        \\entry const answer: U32 = bundle.read 2
    ;
    var before = try Fixture.init(fixture_source);
    defer before.deinit();
    var after = try Fixture.init(changed_source);
    defer after.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    try std.testing.expectEqualDeep(before.names.view(), after.names.view());
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    const found = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target("bundle"));
    try std.testing.expectEqual(graph.Reason.source, found.reason);
    try std.testing.expect(found.plan == null);
}
test "source template exact discovered-value cutoff includes active ancestors" {
    for ([_]usize{ 65_535, 65_536 }) |count| {
        const large_source = try a.print("const values: Array U32 = @array.generate {d} (fn (index: U32) -> U32 => index)\nentry const schema: U32 = 7\nentry const answer: U32 = @array.length values\n", .{count});
        defer a.free(large_source);
        var before = try Fixture.init(large_source);
        defer before.deinit();
        var after = try Fixture.init(large_source);
        defer after.deinit();
        editSchema(&after);
        var initial = try before.emit(a, .{ .retain_artifacts = true });
        defer initial.deinit(a);
        try successful(&initial);
        var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
        defer gate.deinit();
        const found = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target("values"));
        defer if (found.plan) |saved| {
            var owned = saved;
            owned.deinit(a);
        };
        if (count == 65_535) {
            try std.testing.expectEqual(graph.Reason.none, found.reason);
            try std.testing.expectEqual(@as(usize, 65_536), found.plan.?.order.len);
        } else {
            try std.testing.expectEqual(graph.Reason.quota, found.reason);
            try std.testing.expect(found.plan == null);
            try std.testing.expectEqual(@as(usize, 65_536), found.stats.values);
        }
    }
}
test "source template preserves real absent aggregate and callback evidence and normal fresh inference returns 42" {
    var before = try Fixture.init(unsolved_source);
    defer before.deinit();
    var after = try Fixture.init(unsolved_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    try std.testing.expect(plan.stats.template_holes > 0);
    try std.testing.expectEqual(@as(u32, 0), plan.pools.evaluator.value_evidence[plan.root]);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    try std.testing.expectEqual(@as(u32, 0), g.evaluator.valueEvidence(imported));
    // An actual alias in the physical record and array remains the same handle.
    const fields = g.evaluator.valueChildren(g.evaluator.valueChildren(imported)[0]);
    try std.testing.expectEqual(fields[0], g.evaluator.valueChildren(fields[1])[0]);
    try importedAnswer(&g, &after, &plan, imported);
}
test "source template unsolved graph exhaustive OOM leaves values and query publications untouched" {
    var before = try Fixture.init(unsolved_source);
    defer before.deinit();
    var after = try Fixture.init(unsolved_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, oomImport, .{ &after, &initial.capture.?, &gate });
}
test "source template generic same-source callbacks retain distinct U32 and F32 scoped captures" {
    const source =
        \\type Bundle [first, second] is data = #Bundle { first: first, second: second }
        \\const factory = fn number => fn extra => number
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { first: factory 42, second: factory 42.0 }
        \\entry const answer: U32 = bundle.first ()
        \\entry const other: F32 = bundle.second ()
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var after = try Fixture.init(source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    try std.testing.expect(plan.stats.template_holes > 0);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    try importedAnswer(&g, &after, &plan, imported);
    const fields = g.evaluator.valueChildren(g.evaluator.valueChildren(imported)[0]);
    try std.testing.expectEqual(g.evaluator.closureInfo(fields[0]).identity, g.evaluator.closureInfo(fields[1]).identity);
    try std.testing.expect(fields[0] != fields[1]);
    try std.testing.expectEqual(eval.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 42.0)) }, try g.evaluator.value(after.target("other")));
}
test "source template retained partial seeds reject an incompatible fresh demanded result at the ordinary boundary" {
    var before = try Fixture.init(unsolved_source);
    defer before.deinit();
    var after = try Fixture.init(unsolved_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var imported = try Generator.init(&after);
    defer imported.deinit();
    var ordinary = try Generator.init(&after);
    defer ordinary.deinit();
    const new_root = try plan.materialize(&imported);
    const old_root = try ordinary.evaluator.richValue(after.target("bundle"));
    const new_read = imported.evaluator.valueChildren(imported.evaluator.valueChildren(new_root)[0])[0];
    const old_read = ordinary.evaluator.valueChildren(ordinary.evaluator.valueChildren(old_root)[0])[0];
    try std.testing.expectEqual(@as(u32, 0), imported.evaluator.valueEvidence(new_read));
    const new_expected = try imported.evaluator.evidence.intern(.function, 4, 4, &.{});
    const old_expected = try ordinary.evaluator.evidence.intern(.function, 4, 4, &.{});
    try std.testing.expectError(error.Declined, ordinary.evaluator.specializeClosure(old_read, old_expected));
    try std.testing.expectError(error.Declined, imported.evaluator.specializeClosure(new_read, new_expected));
    try std.testing.expectEqualDeep(ordinary.evaluator.diagnostic, imported.evaluator.diagnostic);
    try std.testing.expectEqual(eval.Code.type_mismatch, imported.evaluator.diagnostic.?.code);
}
test "source template validates nominal tags record layouts and anonymous capture shape before admitting holes" {
    var before = try Fixture.init(unsolved_source);
    defer before.deinit();
    var after = try Fixture.init(unsolved_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const pools = &initial.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    const target = after.target("bundle");
    const root = pools.slots[pools.binding_offsets[0] + target.binding].value;
    const payload = pools.evaluator.children[pools.evaluator.values[root].start];
    const read = pools.evaluator.children[pools.evaluator.values[payload].start];
    const original_tag = pools.evaluator.values[root].bits;
    pools.evaluator.values[root].bits = std.math.maxInt(u32);
    const tag = try graph.Plan.inspect(a, pools, &gate, target);
    try std.testing.expectEqual(graph.Reason.bounds, tag.reason);
    pools.evaluator.values[root].bits = original_tag;
    const original_record = pools.evaluator.value_records[payload];
    pools.evaluator.value_records[payload] = 0;
    const record = try graph.Plan.inspect(a, pools, &gate, target);
    try std.testing.expectEqual(graph.Reason.bounds, record.reason);
    pools.evaluator.value_records[payload] = original_record;
    const meta = &pools.evaluator.closures[pools.evaluator.values[read].bits];
    const applied = meta.applied;
    meta.applied = applied + 1;
    const closure = try graph.Plan.inspect(a, pools, &gate, target);
    try std.testing.expectEqual(graph.Reason.bounds, closure.reason);
    meta.applied = applied;
}
test "source template retains legitimate constructor callback source origins" {
    const cases = [_]struct { source: []const u8, origin: eval.ClosureOrigin }{
        .{ .origin = .constructor, .source =
        \\type Wrap value is data = #Wrap value
        \\type Bundle read is data = #Bundle { read: read }
        \\entry const schema: U32 = 7
        \\const bundle = #Bundle { read: #Wrap }
        \\entry const answer: U32 = case bundle.read 42 of
        \\  #Wrap number => number
        },
    };
    for (cases) |case| {
        var before = try Fixture.init(case.source);
        defer before.deinit();
        var after = try Fixture.init(case.source);
        defer after.deinit();
        editSchema(&after);
        var initial = try before.emit(a, .{ .retain_artifacts = true });
        defer initial.deinit(a);
        try successful(&initial);
        var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
        defer gate.deinit();
        var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
        defer plan.deinit(a);
        try std.testing.expect(plan.stats.origins[@backingInt(case.origin)] > 0);
        var g = try Generator.init(&after);
        defer g.deinit();
        const imported = try plan.materialize(&g);
        try importedAnswer(&g, &after, &plan, imported);
    }
}
test "source template local qualified callback follows changed global source dependencies" {
    const source =
        \\type Bundle read is data = #Bundle read
        \\entry const schema: U32 = 7
        \\const bundle = do:
        \\  let read = fn extra => schema
        \\  return #Bundle read
        \\entry const answer: U32 = @array.length (@array.generate 1 (fn (index: U32) => bundle))
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var after = try Fixture.init(source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled);
    try std.testing.expect(!gate.admits(after.target("bundle")));
    const found = try graph.Plan.inspect(a, &initial.capture.?.metadata.pools.?, &gate, after.target("bundle"));
    try std.testing.expectEqual(graph.Reason.source, found.reason);
    try std.testing.expect(found.plan == null);
}
fn anchorDir() !std.testing.TmpDir {
    var dir = std.testing.tmpDir(.{});
    errdefer dir.cleanup();
    const values =
        \\const items = @array.generate 2 (fn (index: U32) => if @u32.eq index 0 then 40 else 2)
        \\const alias = items
        \\const twin = @array.generate 2 (fn (index: U32) => if @u32.eq index 0 then 40 else 2)
    ;
    const main =
        \\import * as values from "./values"
        \\type Bundle read is data = #Bundle { read: read }
        \\const bundle = do:
        \\  let items = values.items
        \\  let alias = values.alias
        \\  let twin = values.twin
        \\  let read = fn extra => (items, alias, twin)
        \\  return #Bundle { read: read }
        \\entry const schema: U32 = 7
        \\entry const answer = fn (index: U32) => do:
        \\  let (first, second, third) = bundle.read ()
        \\  return @u32.add (@array.get first index) (@u32.add (@array.get second index) (@array.get third index))
        \\entry const direct = fn (index: U32) => @array.get values.items index
    ;
    inline for (.{ .{ "prelude.blot", "" }, .{ "values.blot", values }, .{ "main.blot", main } }) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    return dir;
}
fn cutoffScenario(allocator: Allocator, after: *const Fixture, old: *const capture.Capture, expected: []const u8) !void {
    var result = try after.emit(allocator, .{ .previous = old, .retain_artifacts = true });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expect(result.refinements.body_cutoff_hits > 0);
}
test "refinement early cutoff consumes fresh call proofs across runtime body edits" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const main =
        \\import * as values from "./values"
        \\const unused = fn (value: U32) => @u32.sub value 1
        \\entry const warm = fn (value: U32) => values.adjust value
        \\entry const answer = fn (value: U32) => @u32.add (values.adjust value) 40
        \\entry const folded: U32 = values.adjust 20
    ;
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = "" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = main });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "values.blot", .data = "const adjust = fn (value: U32) => @u32.add value 1\n" });
    var before = try Fixture.project(&dir);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    for ([_][]const u8{
        "const adjust = fn (value: U32) => @u32.add value 2\n",
        "const adjust = fn (value: U32) => @u32.sub value 2\n",
    }) |source| {
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "values.blot", .data = source });
        var after = try Fixture.project(&dir);
        defer after.deinit();
        var fresh = try after.emit(a, .{});
        defer fresh.deinit(a);
        var retained = try after.emit(a, .{ .previous = &initial.capture.?, .retain_artifacts = true });
        defer retained.deinit(a);
        try successful(&fresh);
        try successful(&retained);
        try std.testing.expectEqualSlices(u8, fresh.bytes, retained.bytes);
        try std.testing.expectEqual(fresh.constant_steps, retained.constant_steps);
        try std.testing.expect(!std.mem.eql(u8, initial.bytes, retained.bytes));
        try std.testing.expect(retained.refinements.body_cutoff_hits > 0);
        if (std.mem.find(u8, source, "@u32.sub") != null)
            try @import("allocation_failures.zig").checkAllAllocationFailures(a, cutoffScenario, .{ &after, &initial.capture.?, fresh.bytes });
    }
}
fn capturedArrays(session: *const eval.Session, root: u32) []const u32 {
    const read = session.valueChildren(session.valueChildren(root)[0])[0];
    return session.valueChildren(read);
}
test "source template anchors complete dependency graphs and preserves bidirectional global aliases" {
    var dir = try anchorDir();
    defer dir.cleanup();
    var before = try Fixture.project(&dir);
    defer before.deinit();
    var after = try Fixture.project(&dir);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const pools = &initial.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const fresh = try g.evaluator.richValue(after.target("bundle"));
    const actual = try a.dupe(u32, capturedArrays(&g.evaluator, fresh));
    defer a.free(actual);
    try std.testing.expectEqual(@as(usize, 3), actual.len);
    try std.testing.expectEqual(actual[0], actual[1]);
    try std.testing.expect(actual[0] != actual[2]);
    const old_count = g.evaluator.values.items.len;
    const imported = try plan.materializeWithGlobalAnchors(&g, after.entry);
    try std.testing.expectEqualSlices(u32, actual, capturedArrays(&g.evaluator, imported));
    try std.testing.expect(g.evaluator.values.items.len > old_count);
    try sameValue(&pools.evaluator, plan.root, &g.evaluator, imported);
}
test "source template declines conflicting global alias graphs before value or slot publication" {
    var dir = try anchorDir();
    defer dir.cleanup();
    var before = try Fixture.project(&dir);
    defer before.deinit();
    var after = try Fixture.project(&dir);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const pools = &initial.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    const old_read = pools.evaluator.children[pools.evaluator.values[pools.evaluator.children[pools.evaluator.values[plan.root].start]].start];
    const old_arrays = pools.evaluator.children[pools.evaluator.values[old_read].start..][0..3];
    const Fault = enum { split_alias, merge_distinct, unready, bits };
    for ([_]Fault{ .split_alias, .merge_distinct, .unready, .bits }) |fault| {
        var g = try Generator.init(&after);
        defer g.deinit();
        const fresh = try g.evaluator.richValue(after.target("bundle"));
        const actual = capturedArrays(&g.evaluator, fresh);
        var changed = false;
        for (pools.modules) |pin| {
            if (pin.unit == after.entry) continue;
            for (pin.module.bodies[1..]) |body| {
                const index = pools.binding_offsets[pin.unit - 1] + body.binding;
                const old = pools.slots[index];
                if (old.state != 2 or old.value != old_arrays[if (fault == .merge_distinct) 2 else 0] or changed) continue;
                const current = &g.evaluator.slots[g.evaluator.binding_offsets[pin.unit - 1] + body.binding];
                switch (fault) {
                    .split_alias => current.value = actual[2],
                    .merge_distinct => current.value = actual[0],
                    .unready => current.state = .unseen,
                    .bits => g.evaluator.values.items[g.evaluator.valueChildren(current.value)[0]].bits = 41,
                }
                changed = true;
            }
        }
        try std.testing.expect(changed);
        const counts = .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.field_names.items.len };
        const slots = artifacts.stamp(g.evaluator.slots);
        try std.testing.expectError(error.Declined, plan.materializeWithGlobalAnchors(&g, after.entry));
        const now = .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.field_names.items.len };
        inline for (counts, now) |left, right| try std.testing.expectEqual(left, right);
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
    }
}
fn anchorOom(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, gate: *const gate_api.Gate) !void {
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    _ = try g.evaluator.richValue(fixture.target("bundle"));
    var plan = try inspect(allocator, old, gate, fixture.target("bundle"));
    defer plan.deinit(allocator);
    const counts = .{ g.evaluator.values.items.len, g.evaluator.value_evidence.items.len, g.evaluator.value_records.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.demands.items.len, g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count() };
    const slots = artifacts.stamp(g.evaluator.slots);
    _ = plan.materializeWithGlobalAnchors(&g, fixture.entry) catch |err| {
        const now = .{ g.evaluator.values.items.len, g.evaluator.value_evidence.items.len, g.evaluator.value_records.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.demands.items.len, g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count() };
        inline for (counts, now) |left, right| try std.testing.expectEqual(left, right);
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        return err;
    };
}
test "source template anchor comparison and complete graph import recover every allocation failure" {
    var dir = try anchorDir();
    defer dir.cleanup();
    var before = try Fixture.project(&dir);
    defer before.deinit();
    var after = try Fixture.project(&dir);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    // SafeAllocator bucket occupancy changes resize success between runs; the
    // repository adapter makes every growth allocation explicitly injectable.
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, anchorOom, .{ &after, &initial.capture.?, &gate });
}
test "source template absent headers survive destruction of the complete old source and artifact owner" {
    var before = try Fixture.init(unsolved_source);
    var before_live = true;
    defer if (before_live) before.deinit();
    var after = try Fixture.init(unsolved_source);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    var initial_live = true;
    defer if (initial_live) initial.deinit(a);
    try successful(&initial);
    var gate = try gate_api.Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view());
    var gate_live = true;
    defer if (gate_live) gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    var plan_live = true;
    defer if (plan_live) plan.deinit(a);
    try std.testing.expect(plan.stats.template_holes > 0);
    var g = try Generator.init(&after);
    defer g.deinit();
    const imported = try plan.materialize(&g);
    try std.testing.expectEqual(@as(u32, 0), g.evaluator.valueEvidence(imported));
    plan.deinit(a);
    plan_live = false;
    gate.deinit();
    gate_live = false;
    initial.deinit(a);
    initial_live = false;
    before.deinit();
    before_live = false;
    const target = after.target("bundle");
    g.evaluator.slots[g.evaluator.binding_offsets[target.unit - 1] + target.binding] = .{ .state = .complete, .value = imported };
    try std.testing.expectEqual(eval.Value{ .scalar = .u32, .bits = 42 }, try g.evaluator.value(after.target("answer")));
}

test "completed specialization query replays concrete captured callback without skipping ordinary constant fuel" {
    const source =
        \\const factory = fn number => fn extra => number
        \\const callback = factory 42
        \\entry const schema: U32 = 7
        \\entry const answer = fn (extra: U32) -> U32 => callback extra
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    try std.testing.expect(initial.capture.?.metadata.specialization_receipts.items.len > 0);
    var after = try Fixture.init(source);
    defer after.deinit();
    editSchema(&after);
    var fresh = try backend.compileWithIdentity(a, after.units, after.entry, after.names.view());
    defer fresh.deinit(a);
    try successful(&fresh);
    var imported = try backend.compileWithOptions(a, after.units, after.entry, .{ .identity = after.names.view(), .retain_artifacts = true, .previous = &initial.capture.? });
    defer imported.deinit(a);
    try successful(&imported);
    std.debug.print("query fixture initial={d}, complete={d}, reused={d}, reasons={any}\n", .{ initial.completed_queries.recorded, initial.completed_queries.complete_records, imported.completed_queries.reused, imported.completed_queries.reasons });
    try std.testing.expect(imported.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, fresh.bytes, imported.bytes);
    try std.testing.expectEqual(fresh.constant_steps, imported.constant_steps);
}

const query_source =
    \\const factory = fn number => fn extra => number
    \\const callback = factory 42
    \\entry const schema: U32 = 7
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\const run_value: U32 = callback 0
;

const independent_query_source = query_source ++
    \\
    \\const factor: U32 = 5
    \\const checked = fn (number: U32) -> U32 => @u32.add number factor
    \\const floating = fn (number: F32) -> F32 => number
    \\const listed = fn (items: List U32) -> List U32 => items
    \\const arrayed = fn (items: Array U32) -> Array U32 => items
    \\type CallablePayload is data = #CallablePayload (U32 -> U32)
;

fn independentQueryRead(old: *capture.Capture, target_: core.BindingRef, present: bool) !void {
    // Add a source-call premise to a real successful query. The ordinary
    // inference engine must establish it; the cached result grants no proof.
    const record = &old.metadata.specialization_receipts.items[0];
    const reads = try a.dupe(@import("specialization_receipt.zig").CallRead, &.{.{
        .unit = target_.unit,
        .binding = target_.binding,
        .evidence = record.expected,
        .present = present,
    }});
    a.free(record.call_reads);
    record.call_reads = reads;
}

fn independentQueryAttempt(fixture: *const Fixture, old: *const capture.Capture, target_name: []const u8, enabled: bool, accepted: bool, incoming: bool) !void {
    const queries = @import("completed_specialization_query.zig");
    var g = try Generator.init(fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    // Exercise the positive scalar-input path as well as ordinary absent reads.
    _ = try g.evaluator.richValue(fixture.target("factor"));
    const input = try g.evaluator.richValue(fixture.target("callback"));
    const expected = try queryExpected(&g, old, old.metadata.specialization_receipts.items[0].expected);
    const target_ = fixture.target(target_name);
    const key: eval.CallProofKey = .{ .target = .{ .unit = target_.unit - 1, .binding = target_.binding }, .evidence = expected };
    if (incoming) try g.evaluator.validated_calls.put(a, key, {});
    var state = try queries.State.init(a, old, fixture.units, fixture.names.view());
    defer state.deinit();
    state.recover_call_proofs = enabled;
    state.semantic_workers = 2;
    const values_before = g.evaluator.values.items.len;
    const calls_before = g.evaluator.validated_calls.count();
    const slots = artifacts.stamp(g.evaluator.slots);
    const steps = g.evaluator.steps;
    const selected = try state.lookup(&g, input, expected);
    try std.testing.expectEqual(accepted, selected != null);
    try std.testing.expectEqual(steps, g.evaluator.steps);
    try std.testing.expect(g.evaluator.diagnostic == null);
    try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
    if (accepted) {
        try std.testing.expect(g.evaluator.validated_calls.contains(key));
        try std.testing.expectEqual(@as(usize, 1), state.independent_calls.items.len);
        try std.testing.expect(state.stats.independent_rechecked == 1);
        var saw_scalar = false;
        for (state.independent_calls.items[0].scalar_reads) |read| {
            if (std.meta.eql(read.target, fixture.target("factor"))) {
                try std.testing.expectEqual(@as(u32, 3), read.evidence);
                try std.testing.expectEqual(eval.Value{ .scalar = .u32, .bits = 5 }, read.value.?);
                saw_scalar = true;
            }
        }
        try std.testing.expect(saw_scalar);
        g.evaluator.slots[g.evaluator.binding_offsets[0] + fixture.target("callback").binding].value = selected.?;
        try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(fixture.target("run_value"))).bits);
    } else {
        try std.testing.expectEqual(calls_before, g.evaluator.validated_calls.count());
        try std.testing.expectEqual(values_before, g.evaluator.values.items.len);
        try std.testing.expectEqual(@as(usize, 0), state.independent_calls.items.len);
    }
}

test "independent call proof uses exact scalar inputs and preserves negative reads and declined publication" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(independent_query_source);
    defer after.deinit();
    editSchema(&after);
    try independentQueryRead(&old.capture.?, before.target("checked"), true);
    try independentQueryAttempt(&after, &old.capture.?, "checked", false, false, false);
    try independentQueryAttempt(&after, &old.capture.?, "checked", true, true, false);
    // A later catalog mismatch must discard the successfully checked proof.
    try plainQueryFact(&old.capture.?, &.{.{ .key = plainQueryKey(&before, "CallablePayload"), .plain = true }});
    try independentQueryAttempt(&after, &old.capture.?, "checked", true, false, false);
    try plainQueryFact(&old.capture.?, &.{});
    try independentQueryRead(&old.capture.?, before.target("checked"), false);
    try independentQueryAttempt(&after, &old.capture.?, "checked", true, false, true);
}

test "independent call proof rejects wrong scalar and distinct collection arrows without changing the current evaluator" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(independent_query_source);
    defer after.deinit();
    editSchema(&after);
    for ([_][]const u8{ "floating", "listed", "arrayed" }) |name| {
        try independentQueryRead(&old.capture.?, before.target(name), true);
        try independentQueryAttempt(&after, &old.capture.?, name, true, false, false);
    }
}

fn parallelProofScenario(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, workers: u8) !void {
    const parallel = @import("semantic_parallel.zig");
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    _ = try g.evaluator.richValue(fixture.target("factor"));
    var state = try @import("completed_specialization_query.zig").State.init(allocator, old, fixture.units, fixture.names.view());
    defer state.deinit();
    const original = old.metadata.specialization_receipts.items[0].expected;
    const maps = try state.pairedImporter();
    const actual = (try maps.importEvidence(&g, original)).?;
    var requests: [4]parallel.Request = undefined;
    for (&requests, 0..) |*request, index| {
        const target_ = fixture.target(if (index == 2) "floating" else "checked");
        request.* = .{ .index = index, .read = .{ .unit = target_.unit, .binding = target_.binding, .evidence = original, .present = true }, .actual = actual };
    }
    const slots = artifacts.stamp(g.evaluator.slots);
    const values = artifacts.stamp(g.evaluator.values.items);
    const steps = g.evaluator.steps;
    const calls = g.evaluator.validated_calls.count();
    try state.completed_worker_proofs.ensureUnusedCapacity(allocator, requests.len);
    var batch = try parallel.run(allocator, std.testing.io, &state, &g, &requests, workers);
    defer batch.deinit();
    batch.retainSuccesses(&state.completed_worker_proofs, &state.worker_proof_words, g.evaluator.options.max_children);
    for (requests, 0..) |request, index| {
        var recovered = try batch.take(index, &state.stats);
        defer if (recovered) |*record| record.deinit(allocator);
        try std.testing.expectEqual(index != 2, recovered != null);
        if (recovered) |record| {
            try std.testing.expectEqual(request.actual, record.evidence);
            try std.testing.expectEqualDeep(fixture.target("checked"), record.target);
        }
    }
    try std.testing.expectEqual(slots, artifacts.stamp(g.evaluator.slots));
    try std.testing.expectEqual(values, artifacts.stamp(g.evaluator.values.items));
    try std.testing.expectEqual(steps, g.evaluator.steps);
    try std.testing.expectEqual(calls, g.evaluator.validated_calls.count());
    try std.testing.expect(g.evaluator.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 3), state.stats.independent_rechecked);
    try std.testing.expectEqual(@as(usize, 1), state.stats.independent_declined);
    try std.testing.expectEqual(@as(usize, 3), state.completed_worker_proofs.items.len);
    // A sibling's later failure does not erase any owned complete certificate.
    batch.slots[2].failed = true;
    try std.testing.expectError(error.OutOfMemory, batch.take(2, &state.stats));
    var reused = (try @import("independent_call_proof.zig").acquire(&state, &g, requests[0].read, requests[0].actual)).?;
    defer reused.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), state.stats.independent_reused);
    try std.testing.expectEqualDeep(fixture.target("checked"), reused.target);
}

test "private semantic artifact admission declines non positional Core source units" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var current = try Fixture.init(independent_query_source);
    defer current.deinit();
    current.units[0].unit = 4;
    var gate = try @import("principal_reuse_gate.zig").Gate.init(a, &old.capture.?.metadata.pools.?, current.units, current.names.view());
    defer gate.deinit();
    try std.testing.expect(!gate.enabled);
    try std.testing.expect(!gate.admits(.{ .unit = 4, .binding = current.target("checked").binding }));
}

test "independent semantic workers retain deterministic unpublished judgments and join through allocation failures" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var current = try Fixture.init(independent_query_source);
    defer current.deinit();
    editSchema(&current);
    for ([_]u8{ 1, 2, 4 }) |workers| try parallelProofScenario(a, &current, &old.capture.?, workers);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, parallelProofScenario, .{ &current, &old.capture.?, @as(u8, 1) });
}

test "independent call proof preserves List versus Array nominal identity and required effects" {
    const source = independent_query_source ++
        \\
        \\data Left = #Left U32
        \\data Right = #Right U32
        \\const left = fn (item: Left) -> Left => item
        \\type Read a is effect = { get: Unit -> a }
        \\const requested = fn () -> U32 => Read.get ()
    ;
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    for (0..7) |case| {
        var session = try eval.Session.init(a, fixture.units);
        defer session.deinit();
        var parameter: u32 = 1;
        var result: u32 = 3;
        const name: []const u8 = switch (case) {
            0, 1 => "listed",
            2, 3 => "arrayed",
            4, 5 => "left",
            else => "requested",
        };
        if (case < 4) {
            parameter = try session.evidence.intern(if (case % 2 == 0) .list else .array, 3, 0, &.{});
            result = parameter;
        } else if (case < 6) {
            const identity_ = for (fixture.units[0].nominals) |nominal| {
                if (std.mem.eql(u8, fixture.units[0].name(nominal.diagnostic_name), if (case == 4) "Left" else "Right")) break nominal.identity;
            } else unreachable;
            parameter = try session.evidence.intern(.nominal, 1, identity_.decl, &.{});
            result = parameter;
        }
        const expected = try session.evidence.intern(.function, parameter, result, &.{});
        const accepted = session.recheckCallProof(fixture.target(name), expected) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Declined, error.RequestUnwind => false,
        };
        try std.testing.expectEqual(case == 0 or case == 3 or case == 4, accepted);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
    }
}

test "independent call proof every failed allocation preserves query maps values slots and retry" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(independent_query_source);
    defer after.deinit();
    editSchema(&after);
    try independentQueryRead(&old.capture.?, before.target("checked"), true);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, queryAllocationFailure, .{ &after, &old.capture.? });
    try independentQueryAttempt(&after, &old.capture.?, "checked", true, true, false);
}

test "independent call proof retained dependencies survive semantic owner remapping and reject changed producers" {
    var before = try Fixture.init(independent_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    try independentQueryRead(&old.capture.?, before.target("checked"), true);
    var after = try Fixture.init(independent_query_source);
    defer after.deinit();
    editSchema(&after);
    var checked = try after.emit(a, .{ .retain_artifacts = true, .policy = .{ .semantic_workers = 2 }, .previous = &old.capture.?, .evidence_noise = true });
    defer checked.deinit(a);
    try successful(&checked);
    try std.testing.expect(checked.completed_queries.independent_rechecked > 0);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    try successful(&fresh);
    try std.testing.expectEqualSlices(u8, fresh.bytes, checked.bytes);
    try std.testing.expectEqual(fresh.constant_steps, checked.constant_steps);
    var third = try Fixture.init(independent_query_source);
    defer third.deinit();
    var reused = try third.emit(a, .{ .retain_artifacts = true, .policy = .{ .semantic_workers = 2 }, .previous = &checked.capture.? });
    defer reused.deinit(a);
    try successful(&reused);
    try std.testing.expect(reused.completed_queries.independent_reused > 0);
    var third_fresh = try third.emit(a, .{});
    defer third_fresh.deinit(a);
    try std.testing.expectEqualSlices(u8, third_fresh.bytes, reused.bytes);
    try std.testing.expectEqual(third_fresh.constant_steps, reused.constant_steps);
    const body = third.units[0].body(third.target("factor").binding).?;
    third.units[0].nodes[body.root].a = 6;
    var changed = try third.emit(a, .{ .retain_artifacts = true, .policy = .{ .semantic_workers = 2 }, .previous = &reused.capture.? });
    defer changed.deinit(a);
    try successful(&changed);
    try std.testing.expectEqual(@as(usize, 0), changed.completed_queries.independent_reused);
    var changed_fresh = try third.emit(a, .{});
    defer changed_fresh.deinit(a);
    try std.testing.expectEqualSlices(u8, changed_fresh.bytes, changed.bytes);
    try std.testing.expectEqual(changed_fresh.constant_steps, changed.constant_steps);
}

const plain_query_source =
    \\type PlainPayload is data = #PlainPayload { xs: List U32, ys: Array U32 }
    \\type CallablePayload is data = #CallablePayload (U32 -> U32)
++ "\n" ++ query_source;

fn plainQueryKey(fixture: *const Fixture, name: []const u8) u64 {
    for (fixture.units[0].nominals) |nominal| {
        if (std.mem.eql(u8, fixture.units[0].name(nominal.diagnostic_name), name))
            return (@as(u64, 1) << 32) | nominal.identity.decl;
    }
    unreachable;
}

fn plainQueryFact(old: *capture.Capture, facts: []const @import("specialization_receipt.zig").PlainFact) !void {
    // Strengthen a real successful query with an independently justified
    // catalog premise. This isolates publication/rollback from inference order.
    const record = &old.metadata.specialization_receipts.items[0];
    const owned = try a.dupe(@import("specialization_receipt.zig").PlainFact, facts);
    a.free(record.plain_facts);
    record.plain_facts = owned;
}

const PlainAttempt = enum { recover, reference, known_false, decline };
fn plainQueryAttempt(fixture: *const Fixture, old: *const capture.Capture, mode: PlainAttempt) !void {
    var g = try Generator.init(fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    const input = try g.evaluator.richValue(fixture.target("callback"));
    const expected = try queryExpected(&g, old, old.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, old, fixture.units, fixture.names.view());
    defer state.deinit();
    state.revalidate_plain_facts = mode != .reference;
    const key = plainQueryKey(fixture, "PlainPayload");
    if (mode == .known_false) try g.evaluator.plain_nominals.put(a, key, false);
    const prior = g.evaluator.plain_nominals.count();
    const selected = try state.lookup(&g, input, expected);
    if (mode == .recover) {
        try std.testing.expect(selected != null);
        try std.testing.expectEqual(@as(usize, 1), state.stats.plain_revalidated);
        try std.testing.expectEqual(@as(?bool, true), g.evaluator.plain_nominals.get(key));
        g.evaluator.slots[g.evaluator.binding_offsets[0] + fixture.target("callback").binding].value = selected.?;
        try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(fixture.target("run_value"))).bits);
    } else {
        try std.testing.expect(selected == null);
        try std.testing.expectEqual(prior, g.evaluator.plain_nominals.count());
        try std.testing.expectEqual(@as(?bool, if (mode == .known_false) false else null), g.evaluator.plain_nominals.get(key));
    }
}

test "plain catalog query recovery preserves negative reads conflicting facts and atomic declined publication" {
    var before = try Fixture.init(plain_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(plain_query_source);
    defer after.deinit();
    editSchema(&after);
    const key = plainQueryKey(&before, "PlainPayload");
    const callback = plainQueryKey(&before, "CallablePayload");
    try plainQueryFact(&old.capture.?, &.{.{ .key = key, .plain = true }});
    try plainQueryAttempt(&after, &old.capture.?, .reference);
    try plainQueryAttempt(&after, &old.capture.?, .known_false);
    try plainQueryAttempt(&after, &old.capture.?, .recover);
    try plainQueryFact(&old.capture.?, &.{ .{ .key = key, .plain = true }, .{ .key = callback, .plain = true } });
    try plainQueryAttempt(&after, &old.capture.?, .decline);
    try plainQueryFact(&old.capture.?, &.{.{ .key = callback, .plain = false }});
    try plainQueryAttempt(&after, &old.capture.?, .decline);
    try plainQueryFact(&old.capture.?, &.{ .{ .key = key, .plain = true }, .{ .key = key, .plain = false, .present = false } });
    try plainQueryAttempt(&after, &old.capture.?, .decline);
}

test "plain catalog query recovery cleans every allocation failure without publishing staged facts" {
    var before = try Fixture.init(plain_query_source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    try plainQueryFact(&old.capture.?, &.{.{ .key = plainQueryKey(&before, "PlainPayload"), .plain = true }});
    var after = try Fixture.init(plain_query_source);
    defer after.deinit();
    editSchema(&after);
    try queryAllocationFailure(a, &after, &old.capture.?);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, queryAllocationFailure, .{ &after, &old.capture.? });
}
fn queryExpected(g: *Generator, old: *const capture.Capture, value: u32) !u32 {
    var import = try @import("artifact_import.zig").Importer.init(g.allocator, &old.metadata.pools.?, g.evaluator.units, old.metadata.pools.?.identity.?.view(), g.evaluator.units.len);
    defer import.deinit();
    return (try import.importEvidence(g, value)) orelse error.Declined;
}

const source_row_query =
    \\type Read a is effect = { get: Unit -> a }
    \\const factory = fn action => fn value => action value
    \\const callback = factory (fn () => Read.get ())
    \\entry const schema: U32 = 7
    \\entry const answer = fn () -> U32 => @effect.reader Read.get 0 (fn () => 42) callback
    \\const evaluated: U32 = answer ()
;

test "semantic catalog imports nominal evidence while executable layout remains rejected" {
    const source =
        \\data Box a = #Box a
        \\entry const schema = fn () -> U32 => 7
        \\const boxed = #Box 42
        \\entry const answer = fn (value: U32) => do:
        \\  let #Box fixed = boxed
        \\  return @u32.add value fixed
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source);
    defer after.deinit();
    editSchema(&after);
    const pools = &old.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    try std.testing.expect(gate.enabled and !gate.structural_units[0]);
    var maps = (try @import("artifact_import.zig").Importer.initCheckedQuery(a, pools, after.units, &gate)).?;
    defer maps.deinit();
    var g = try Generator.init(&after);
    defer g.deinit();
    var imported: usize = 0;
    for (pools.evaluator.evidence.nodes, 0..) |node, id| if (node.tag == .nominal) {
        const current = (try maps.importEvidence(&g, @intCast(id))) orelse return error.ExpectedSemanticImport;
        try std.testing.expectEqual(evidence.Tag.nominal, g.evaluator.evidence.node(current).tag);
        imported += 1;
    };
    try std.testing.expect(imported > 0);
    // Emission captured physical nominal layouts for the boxed value.
    // Their executable owner is still changed, despite equal type catalogs.
    var declined: usize = 0;
    for (pools.layouts.nodes, 0..) |node, id| if (node.tag == .nominal) {
        try std.testing.expect(try maps.importLayout(&g, @intCast(id)) == null);
        declined += 1;
    };
    try std.testing.expect(declined > 0);
}
test "source declared effect query preserves fresh bytes and fuel across edits and remapped owners" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    try successful(&fresh);
    var pure = try after.emit(a, .{ .retain_artifacts = true, .previous = &old.capture.? });
    defer pure.deinit(a);
    try successful(&pure);
    var reused = try after.emit(a, .{ .evidence_noise = true, .retain_artifacts = true, .previous = &old.capture.? });
    defer reused.deinit(a);
    try successful(&reused);
    std.debug.print("source rows records={d} pure={d} reused={d} reasons={any}\n", .{ old.completed_queries.recorded, pure.completed_queries.reused, reused.completed_queries.reused, reused.completed_queries.reasons });
    try std.testing.expect(reused.completed_queries.reused > 0);
    try std.testing.expectEqual(pure.completed_queries.reused, reused.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, pure.bytes);
    try std.testing.expectEqual(fresh.constant_steps, pure.constant_steps);
    try std.testing.expectEqualSlices(u8, fresh.bytes, reused.bytes);
    try std.testing.expectEqual(fresh.constant_steps, reused.constant_steps);
    var third = try Fixture.init(source_row_query);
    defer third.deinit();
    var reverted_fresh = try third.emit(a, .{});
    defer reverted_fresh.deinit(a);
    try successful(&reverted_fresh);
    var reverted = try third.emit(a, .{ .retain_artifacts = true, .previous = &reused.capture.? });
    defer reverted.deinit(a);
    try successful(&reverted);
    try std.testing.expect(reverted.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, reverted_fresh.bytes, reverted.bytes);
    try std.testing.expectEqual(reverted_fresh.constant_steps, reverted.constant_steps);
}
fn queryAllocationFailure(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture) !void {
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    const input = try g.evaluator.richValue(fixture.target("callback"));
    const expected = try queryExpected(&g, old, old.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(allocator, old, fixture.units, fixture.names.view());
    defer state.deinit();
    const sizes = .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.typed_views.count(), g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count(), g.evaluator.plain_nominals.count(), g.evaluator.specialization_receipts.items.len };
    const slots = artifacts.stamp(g.evaluator.slots);
    const selected = state.lookup(&g, input, expected) catch |err| {
        try std.testing.expectEqual(sizes, .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.typed_views.count(), g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count(), g.evaluator.plain_nominals.count(), g.evaluator.specialization_receipts.items.len });
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        return err;
    };
    try std.testing.expect(selected != null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.reused);
    const ordinary = old.metadata.specialization_receipts.items[0];
    try std.testing.expectEqual(ordinary.values_added, g.evaluator.values.items.len - sizes[0]);
    try std.testing.expectEqual(ordinary.children_added, g.evaluator.children.items.len - sizes[1]);
    g.evaluator.slots[g.evaluator.binding_offsets[0] + fixture.target("callback").binding].value = selected.?;
    try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(fixture.target("run_value"))).bits);
}
test "completed specialization query every allocation failure preserves all publication maps and slots" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, queryAllocationFailure, .{ &after, &initial.capture.? });
}
test "completed specialization query changed concrete captures and low quotas explicitly retain ordinary inference" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &initial.capture.?, initial.capture.?.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, &initial.capture.?, after.units, after.names.view());
    defer state.deinit();
    g.evaluator.options.max_values = 8;
    try std.testing.expect((try state.lookup(&g, input, expected)) == null);
    g.evaluator.options.max_values = 1_000_000;
    const child = g.evaluator.valueChildren(input)[0];
    g.evaluator.values.items[child].bits = 2;
    try std.testing.expect((try state.lookup(&g, input, expected)) == null);
    try std.testing.expect(state.stats.reasons[@backingInt(@import("completed_specialization_query.zig").Reason.input)] > 0);
    const fresh_selected = try g.evaluator.specializeClosure(input, expected);
    g.evaluator.slots[g.evaluator.binding_offsets[0] + after.target("callback").binding].value = fresh_selected;
    try std.testing.expectEqual(@as(u32, 2), (try g.evaluator.value(after.target("run_value"))).bits);
}

test "completed specialization query repeated fresh owners carry remapped receipts without changing output or quotas" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var second = try Fixture.init(query_source);
    defer second.deinit();
    editSchema(&second);
    var transported = try backend.compileWithOptions(a, second.units, second.entry, .{ .identity = second.names.view(), .retain_artifacts = true, .previous = &old.capture.? });
    defer transported.deinit(a);
    try successful(&transported);
    try std.testing.expectEqual(@as(usize, 1), transported.completed_queries.reused);
    try std.testing.expectEqual(@as(usize, 1), transported.capture.?.metadata.specialization_receipts.items.len);
    var third = try Fixture.init(query_source);
    defer third.deinit();
    var fresh = try backend.compileWithIdentity(a, third.units, third.entry, third.names.view());
    defer fresh.deinit(a);
    try successful(&fresh);
    var reverted = try backend.compileWithOptions(a, third.units, third.entry, .{ .identity = third.names.view(), .retain_artifacts = true, .previous = &transported.capture.? });
    defer reverted.deinit(a);
    try successful(&reverted);
    try std.testing.expectEqual(@as(usize, 1), reverted.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, reverted.bytes);
    try std.testing.expectEqual(fresh.constant_steps, reverted.constant_steps);
    const first_receipt = old.capture.?.metadata.specialization_receipts.items[0];
    const third_receipt = reverted.capture.?.metadata.specialization_receipts.items[0];
    try std.testing.expectEqual(first_receipt.values_added, third_receipt.values_added);
    try std.testing.expectEqual(first_receipt.children_added, third_receipt.children_added);
}
test "completed specialization query exact current expected type and cache-state reads remain authoritative" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &old.capture.?, old.capture.?.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    defer state.deinit();
    const wrong = try g.evaluator.evidence.intern(.function, 3, 4, &.{});
    try std.testing.expect((try state.lookup(&g, input, wrong)) == null);
    try std.testing.expectError(error.Declined, g.evaluator.specializeClosure(input, wrong));
    try std.testing.expectEqual(eval.Code.type_mismatch, g.evaluator.diagnostic.?.code);
    g.evaluator.diagnostic = null;
    const changed = &old.capture.?.metadata.specialization_receipts.items[0];
    const saved_depth = changed.depth;
    changed.depth += 1;
    try std.testing.expect((try state.lookup(&g, input, expected)) == null);
    changed.depth = saved_depth;
    const saved_complete = changed.complete;
    changed.complete = false;
    try std.testing.expect((try state.lookup(&g, input, expected)) == null);
    changed.complete = saved_complete;
    try std.testing.expect((try state.lookup(&g, input, expected)) != null);
}

test "completed specialization query declines foreign allocator and same-pointer shorter owner before access" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &old.capture.?, old.capture.?.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    defer state.deinit();
    const before_values = g.evaluator.values.items.len;
    const before_children = g.evaluator.children.items.len;
    const owner = g.evaluator.units;
    g.evaluator.units = owner[0..0];
    const prefix_result = state.lookup(&g, input, expected);
    g.evaluator.units = owner;
    try std.testing.expect((try prefix_result) == null);
    const allocator = state.allocator;
    state.allocator = std.heap.smp_allocator;
    const allocator_result = state.lookup(&g, input, expected);
    state.allocator = allocator;
    try std.testing.expect((try allocator_result) == null);
    try std.testing.expect((try state.lookup(&g, std.math.maxInt(u32), expected)) == null);
    try std.testing.expect((try state.lookup(&g, input, 3)) == null);
    try std.testing.expectEqual(before_values, g.evaluator.values.items.len);
    try std.testing.expectEqual(before_children, g.evaluator.children.items.len);
    try std.testing.expect((try state.lookup(&g, input, expected)) != null);
}

test "completed specialization query selected values and remapped receipt survive complete old owner destruction" {
    var before = try Fixture.init(query_source);
    var before_live = true;
    defer if (before_live) before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    var old_live = true;
    defer if (old_live) old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &old.capture.?, old.capture.?.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    var state_live = true;
    defer if (state_live) state.deinit();
    const selected = (try state.lookup(&g, input, expected)).?;
    try std.testing.expectEqual(@as(usize, 1), g.evaluator.specialization_receipts.items.len);
    state.deinit();
    state_live = false;
    old.deinit(a);
    old_live = false;
    before.deinit();
    before_live = false;
    g.evaluator.slots[g.evaluator.binding_offsets[0] + after.target("callback").binding].value = selected;
    try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(after.target("run_value"))).bits);
    try std.testing.expectEqual(selected, g.evaluator.specialization_receipts.items[0].selected);
}

const paired_query_source =
    \\const factory = fn number => fn extra => number
    \\const left = factory 42
    \\const right = factory 2
    \\entry const schema: U32 = 7
    \\entry const answer_left = fn (extra: U32) -> U32 => left extra
    \\entry const answer_right = fn (extra: U32) -> U32 => right extra
    \\const run_left: U32 = left 0
    \\const run_right: U32 = right 0
;

fn pairedQueryFailure(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture) !void {
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    const left = try g.evaluator.richValue(fixture.target("left"));
    const right = try g.evaluator.richValue(fixture.target("right"));
    const expected = try queryExpected(&g, old, old.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(allocator, old, fixture.units, fixture.names.view());
    defer state.deinit();
    const left_selected = (try state.lookup(&g, left, expected)).?;
    const sizes = .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.typed_views.count(), g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count(), g.evaluator.plain_nominals.count(), g.evaluator.specialization_receipts.items.len };
    const slots = artifacts.stamp(g.evaluator.slots);
    const right_selected = state.lookup(&g, right, expected) catch |err| {
        try std.testing.expectEqual(sizes, .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.typed_views.count(), g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count(), g.evaluator.plain_nominals.count(), g.evaluator.specialization_receipts.items.len });
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        return err;
    };
    try std.testing.expect(right_selected != null);
    try std.testing.expectEqual(@as(usize, 2), state.stats.reused);
    try std.testing.expectEqual(@as(usize, 1), state.stats.owner_importers);
    try std.testing.expect(state.stats.plan_cache_hits > 0);
    var buckets = state.buckets.valueIterator();
    const ordered = buckets.next().?.items;
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, ordered);
    try std.testing.expect(buckets.next() == null);
    g.evaluator.slots[g.evaluator.binding_offsets[0] + fixture.target("left").binding].value = left_selected;
    g.evaluator.slots[g.evaluator.binding_offsets[0] + fixture.target("right").binding].value = right_selected.?;
    try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(fixture.target("run_left"))).bits);
    try std.testing.expectEqual(@as(u32, 2), (try g.evaluator.value(fixture.target("run_right"))).bits);
}

test "completed specialization query ordered bucket and warmed plan distinguish same-source concrete captures under every allocation failure" {
    var before = try Fixture.init(paired_query_source);
    defer before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    try std.testing.expectEqual(@as(usize, 2), old.capture.?.metadata.specialization_receipts.items.len);
    var after = try Fixture.init(paired_query_source);
    defer after.deinit();
    editSchema(&after);
    try pairedQueryFailure(a, &after, &old.capture.?);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, pairedQueryFailure, .{ &after, &old.capture.? });
}

test "completed specialization query importer cannot cross a live Generator Session owner" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var old = try backend.compileWithOptions(a, before.units, before.entry, .{ .identity = before.names.view(), .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &old.capture.?, old.capture.?.metadata.specialization_receipts.items[0].expected);
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    defer state.deinit();
    try std.testing.expect((try state.lookup(&g, input, expected)) != null);
    var foreign = try Generator.init(&after);
    defer foreign.deinit();
    foreign.evaluator.options.trace_runtime_dependencies = true;
    const other_input = try foreign.evaluator.richValue(after.target("callback"));
    const other_expected = try queryExpected(&foreign, &old.capture.?, old.capture.?.metadata.specialization_receipts.items[0].expected);
    const sizes = .{ foreign.evaluator.values.items.len, foreign.evaluator.children.items.len, foreign.evaluator.specialized_closures.count(), foreign.evaluator.typed_views.count() };
    try std.testing.expect((try state.lookup(&foreign, other_input, other_expected)) == null);
    try std.testing.expectEqual(sizes, .{ foreign.evaluator.values.items.len, foreign.evaluator.children.items.len, foreign.evaluator.specialized_closures.count(), foreign.evaluator.typed_views.count() });
    try std.testing.expectEqual(@as(usize, 1), state.stats.owner_importers);
    const fresh = try foreign.evaluator.specializeClosure(other_input, other_expected);
    foreign.evaluator.slots[foreign.evaluator.binding_offsets[0] + after.target("callback").binding].value = fresh;
    try std.testing.expectEqual(@as(u32, 42), (try foreign.evaluator.value(after.target("run_value"))).bits);
}

fn sourceRowNoise(g: *Generator) !void {
    const words: [64]u32 = @splat(4);
    for (1..words.len + 1) |count| _ = try g.evaluator.evidence.intern(.product, 0, 0, words[0..count]);
    for (0..7) |index| {
        const label = try g.evaluator.evidence.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = @intCast(9000 + index) }, &.{4});
        _ = try g.evaluator.evidence.effects.internRow(&.{label});
    }
}
fn sourceRowExpected(g: *Generator, old: *const capture.Capture, input: u32, names: identity.View) !u32 {
    const current = g.evaluator.closureInfo(input);
    const snapshot = &old.metadata.pools.?.evaluator;
    for (old.metadata.specialization_receipts.items) |record| {
        const prior = snapshot.closures[snapshot.values[record.input].bits];
        if (prior.unit != current.unit or prior.identity != current.identity or prior.origin != current.origin or prior.applied != current.applied) continue;
        const before = snapshot.evidence.view().node(record.expected);
        try std.testing.expect(before.tag == .function and before.c != 0);
        var gate = try gate_api.Gate.init(g.allocator, &old.metadata.pools.?, g.evaluator.units, names);
        defer gate.deinit();
        var maps = try @import("artifact_import.zig").Importer.init(g.allocator, &old.metadata.pools.?, g.evaluator.units, old.metadata.pools.?.identity.?.view(), g.evaluator.units.len);
        defer maps.deinit();
        for (maps.stable, gate.structural_units) |*stable, exact| stable.* = exact;
        const actual = (try maps.importEvidence(g, record.expected)) orelse return error.Declined;
        const after = g.evaluator.evidence.node(actual);
        try sameSourceRows(snapshot.evidence.view(), before.c, g.evaluator.evidence.view(), after.c);
        try std.testing.expect(before.c != after.c);
        return actual;
    }
    return error.MissingEffectfulQuery;
}
fn sameSourceRows(before: evidence.View, old: u32, after: evidence.View, current: u32) !void {
    const left = before.effects.rowLabels(old);
    const right = after.effects.rowLabels(current);
    try std.testing.expect(left.len > 0);
    try std.testing.expectEqual(left.len, right.len);
    for (left, right) |prior, actual| {
        try std.testing.expectEqual(before.effects.operation(prior).identity, after.effects.operation(actual).identity);
        const old_args = before.effects.operationArguments(prior);
        const new_args = after.effects.operationArguments(actual);
        try std.testing.expectEqual(old_args.len, new_args.len);
        for (old_args, new_args) |argument, imported| try sameType(before, argument, after, imported);
        try std.testing.expect(before.effects.operation(prior).identity.unit != std.math.maxInt(u32));
    }
}
fn sourceRowPublicationSizes(g: *const Generator) [12]usize {
    return .{ g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.closures.items.len, g.evaluator.type_mappings.items.len, g.evaluator.row_mappings.items.len, g.evaluator.record_layouts.items.len, g.evaluator.field_names.items.len, g.evaluator.typed_views.count(), g.evaluator.specialized_closures.count(), g.evaluator.validated_calls.count(), g.evaluator.plain_nominals.count(), g.evaluator.specialization_receipts.items.len };
}
fn sourceRowOom(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture) !void {
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    try sourceRowNoise(&g);
    const input = try g.evaluator.richValue(fixture.target("callback"));
    const expected = try sourceRowExpected(&g, old, input, fixture.names.view());
    var state = try @import("completed_specialization_query.zig").State.init(allocator, old, fixture.units, fixture.names.view());
    defer state.deinit();
    const sizes = sourceRowPublicationSizes(&g);
    const slots = artifacts.stamp(g.evaluator.slots);
    const selected = state.lookup(&g, input, expected) catch |err| {
        try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        return err;
    };
    try std.testing.expect(selected != null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.reused);
    const selected_node = g.evaluator.evidence.node(g.evaluator.valueEvidence(selected.?));
    try std.testing.expectEqual(expected, g.evaluator.valueEvidence(selected.?));
    try std.testing.expect(selected_node.c != 0);
    const old_record = old.metadata.specialization_receipts.items[0];
    try std.testing.expectEqual(old_record.values_added, g.evaluator.values.items.len - sizes[0]);
    try std.testing.expectEqual(old_record.children_added, g.evaluator.children.items.len - sizes[1]);
    try std.testing.expectEqual(@as(usize, 1), g.evaluator.specialization_receipts.items.len);
}
test "source declared effect query every allocation failure preserves publications slots and exact growth with current row noise" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    try sourceRowOom(a, &after, &old.capture.?);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceRowOom, .{ &after, &old.capture.? });
}

test "source declared effect query frozen row policy declines changes and semantic operation arguments stay distinct" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    try sourceRowNoise(&g);
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try sourceRowExpected(&g, &old.capture.?, input, after.names.view());
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    defer state.deinit();
    const function = g.evaluator.evidence.node(expected);
    const effects = g.evaluator.evidence.effects.view();
    const label = effects.rowLabels(function.c)[0];
    const operation = effects.operation(label).identity;
    try std.testing.expectEqualSlices(u32, &.{3}, effects.operationArguments(label));
    const wrong_label = try g.evaluator.evidence.effects.internOperation(operation, &.{4});
    const wrong_row = try g.evaluator.evidence.effects.internRow(&.{wrong_label});
    const wrong = try g.evaluator.evidence.internWithEffects(.function, function.a, function.b, wrong_row, &.{});
    const initial_sizes = sourceRowPublicationSizes(&g);
    try std.testing.expect((try state.lookup(&g, input, wrong)) == null);
    try std.testing.expectEqual(initial_sizes, sourceRowPublicationSizes(&g));
    try std.testing.expect(state.stats.reasons[@backingInt(@import("completed_specialization_query.zig").Reason.expected)] > 0);
    try std.testing.expect((try state.lookup(&g, input, expected)) != null);
    const sizes = sourceRowPublicationSizes(&g);
    try std.testing.expect((try state.lookup(&g, input, expected)) == null);
    try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
}

test "source declared effect query nonempty row and receipt survive destruction of every old owner" {
    var before = try Fixture.init(source_row_query);
    var before_live = true;
    defer if (before_live) before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    var old_live = true;
    defer if (old_live) old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    try sourceRowNoise(&g);
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try sourceRowExpected(&g, &old.capture.?, input, after.names.view());
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    var state_live = true;
    defer if (state_live) state.deinit();
    const selected = (try state.lookup(&g, input, expected)).?;
    try std.testing.expectEqual(@as(usize, 1), g.evaluator.specialization_receipts.items.len);
    state.deinit();
    state_live = false;
    old.deinit(a);
    old_live = false;
    before.deinit();
    before_live = false;
    try std.testing.expectEqual(expected, g.evaluator.valueEvidence(selected));
    const node = g.evaluator.evidence.node(expected);
    const labels = g.evaluator.evidence.effects.view().rowLabels(node.c);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    try std.testing.expectEqualSlices(u32, &.{3}, g.evaluator.evidence.effects.view().operationArguments(labels[0]));
    try std.testing.expectEqual(selected, g.evaluator.specialization_receipts.items[0].selected);
    g.evaluator.slots[g.evaluator.binding_offsets[after.entry - 1] + after.target("callback").binding].value = selected;
    // The current source's effect reader executes the imported callback.
    try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(after.target("evaluated"))).bits);
}

fn rowRoot(old: *const capture.Capture) !u32 {
    const snapshot = &old.metadata.pools.?.evaluator;
    for (old.metadata.specialization_receipts.items) |record| if (snapshot.evidence.view().node(record.expected).c != 0) return record.selected;
    return error.MissingEffectfulQuery;
}
fn appendedSnapshotType(snapshot: *evidence.Snapshot, node: evidence.Node) !u32 {
    const next = try a.alloc(evidence.Node, snapshot.nodes.len + 1);
    @memcpy(next[0..snapshot.nodes.len], snapshot.nodes);
    const id: u32 = @intCast(snapshot.nodes.len);
    next[id] = node;
    a.free(snapshot.nodes);
    snapshot.nodes = next;
    return id;
}
fn expectRowDomain(old: *const capture.Capture, gate: *const gate_api.Gate, root: u32) !void {
    const found = try graph.Plan.inspectRootsWithRows(a, &old.metadata.pools.?, gate, &.{root}, .source_declared);
    try std.testing.expect(found.plan == null);
    try std.testing.expectEqual(graph.Reason.domain, found.reason);
    try std.testing.expect(found.stats.unsupported_evidence > 0);
}
test "source declared effect graph rejects generated labels and provider State operation arguments" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var gate = try gate_api.Gate.init(a, &old.capture.?.metadata.pools.?, after.units, after.names.view());
    defer gate.deinit();
    const root = try rowRoot(&old.capture.?);
    const snapshot = &old.capture.?.metadata.pools.?.evaluator.evidence;
    const row = snapshot.nodes[old.capture.?.metadata.pools.?.evaluator.value_evidence[root]].c;
    const label = snapshot.effects.view().rowLabels(row)[0];
    const operation = &snapshot.effects.operations[label];
    const saved_identity = operation.identity;
    operation.identity = @import("types.zig").builtin_state_read;
    try expectRowDomain(&old.capture.?, &gate, root);
    operation.identity = .{ .unit = 0, .decl = 2 };
    try expectRowDomain(&old.capture.?, &gate, root);
    operation.identity = .{ .unit = 0, .decl = 1 };
    // Foreign's reserved marker admits no semantic type arguments.
    try expectRowDomain(&old.capture.?, &gate, root);
    operation.identity = .{ .unit = saved_identity.unit, .decl = std.math.maxInt(u32) - 1 };
    try expectRowDomain(&old.capture.?, &gate, root);
    operation.identity = saved_identity;
    const argument = &snapshot.effects.arguments[operation.arguments.start];
    const saved_argument = argument.*;
    const function = old.capture.?.metadata.pools.?.evaluator.value_evidence[root];
    // Closed headers with provider/State domains are valid semantic node kinds,
    // but cannot authorize this source-only graph transport.
    argument.* = try appendedSnapshotType(snapshot, .{ .tag = .provider, .a = label, .b = function });
    try expectRowDomain(&old.capture.?, &gate, root);
    argument.* = try appendedSnapshotType(snapshot, .{ .tag = .state_provider, .a = label, .b = label, .c = 3 });
    try expectRowDomain(&old.capture.?, &gate, root);
    argument.* = saved_argument;
    const restored = try graph.Plan.inspectRootsWithRows(a, &old.capture.?.metadata.pools.?, &gate, &.{root}, .source_declared);
    var plan = restored.plan orelse return error.ExpectedPlan;
    defer plan.deinit(a);
}

test "source declared effect query structurally remaps a nominal operation argument through current type and row prefix noise" {
    const source =
        \\type Payload is data = #Payload { value: U32 }
        \\type Read a is effect = { get: Unit -> a }
        \\const factory = fn action => fn value => action value
        \\const callback = factory (fn () => Read.get ())
        \\entry const schema: U32 = 7
        \\entry const answer = fn () -> U32 => do:
        \\  let payload = @effect.reader Read.get (#Payload { value: 0 }) (fn () => #Payload { value: 42 }) callback
        \\  return payload.value
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    var after = try Fixture.init(source);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    try successful(&fresh);
    var reused = try after.emit(a, .{ .evidence_noise = true, .retain_artifacts = true, .previous = &old.capture.? });
    defer reused.deinit(a);
    try successful(&reused);
    try std.testing.expect(reused.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, fresh.bytes, reused.bytes);
    try std.testing.expectEqual(fresh.constant_steps, reused.constant_steps);
    const old_view = old.capture.?.metadata.pools.?.evaluator.evidence.view();
    const new_view = reused.capture.?.metadata.pools.?.evaluator.evidence.view();
    var remapped: usize = 0;
    for (old.capture.?.metadata.specialization_receipts.items) |record| {
        const expected = old_view.node(record.expected);
        if (expected.c == 0) continue;
        const old_label = old_view.effects.rowLabels(expected.c)[0];
        const old_argument = old_view.effects.operationArguments(old_label)[0];
        try std.testing.expectEqual(evidence.Tag.nominal, old_view.node(old_argument).tag);
        for (new_view.effects.operations, 0..) |operation, label| {
            if (!std.meta.eql(operation.identity, old_view.effects.operation(old_label).identity)) continue;
            const arguments = new_view.effects.operationArguments(@intCast(label));
            if (arguments.len != 1 or new_view.node(arguments[0]).tag != .nominal) continue;
            try sameType(old_view, old_argument, new_view, arguments[0]);
            remapped += 1;
        }
    }
    try std.testing.expect(remapped > 0);
    // The compiler's evidence_noise changes operation labels only. This fresh
    // ordinary Session deliberately prefixes both type and row pools as well.
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    try sourceRowNoise(&g);
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try sourceRowExpected(&g, &old.capture.?, input, after.names.view());
    const new_row = g.evaluator.evidence.node(expected).c;
    const new_label = g.evaluator.evidence.effects.view().rowLabels(new_row)[0];
    const argument = g.evaluator.evidence.effects.view().operationArguments(new_label)[0];
    try std.testing.expect(argument >= old_view.nodes.len);
    var state = try @import("completed_specialization_query.zig").State.init(a, &old.capture.?, after.units, after.names.view());
    defer state.deinit();
    try std.testing.expect((try state.lookup(&g, input, expected)) != null);
}

// Scratch is an execution optimization only. These laws use the same admitted
// graph and import receipts while exercising cleanup and fixed live owners.
test "query graph scratch clears declined alias candidates and rejects changed live owners" {
    var dir = try anchorDir();
    defer dir.cleanup();
    var before = try Fixture.project(&dir);
    defer before.deinit();
    var after = try Fixture.project(&dir);
    defer after.deinit();
    editSchema(&after);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const pools = &initial.capture.?.metadata.pools.?;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &initial.capture.?, &gate, after.target("bundle"));
    defer plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    const fresh = try g.evaluator.richValue(after.target("bundle"));
    const current_read = g.evaluator.valueChildren(g.evaluator.valueChildren(fresh)[0])[0];
    const capture_start = g.evaluator.valueInfo(current_read).start;
    const original = try a.dupe(u32, capturedArrays(&g.evaluator, fresh));
    defer a.free(original);
    var maps = try @import("artifact_import.zig").Importer.init(a, pools, after.units, after.names.view(), after.units.len);
    defer maps.deinit();
    for (maps.stable, gate.structural_units) |*stable, structural| stable.* = structural;
    var scratch: graph.QueryScratch = .{ .allocator = a };
    defer scratch.deinit();
    var anchors = try scratch.begin(&plan, &g);
    try std.testing.expect(try plan.matchIntoWithScratch(&g, &maps, plan.root, fresh, anchors, &scratch));
    const initialized = scratch.stats.initialized_slots;
    const sizes = sourceRowPublicationSizes(&g);
    const slots = artifacts.stamp(g.evaluator.slots);
    const scalar = g.evaluator.valueChildren(original[0])[0];
    const original_bits = g.evaluator.values.items[scalar].bits;
    for (0..3) |fault| {
        anchors = try scratch.begin(&plan, &g);
        switch (fault) {
            0 => g.evaluator.children.items[capture_start + 1] = original[2],
            1 => g.evaluator.children.items[capture_start + 2] = original[0],
            2 => g.evaluator.values.items[scalar].bits = original_bits + 1,
            else => unreachable,
        }
        try std.testing.expect(!try plan.matchIntoWithScratch(&g, &maps, plan.root, fresh, anchors, &scratch));
        for (anchors) |value| try std.testing.expectEqual(@as(u32, 0), value);
        try std.testing.expectEqual(@as(usize, 0), scratch.inverse_ids.items.len);
        try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        @memcpy(g.evaluator.children.items[capture_start..][0..3], original);
        g.evaluator.values.items[scalar].bits = original_bits;
        // Retry without begin: failure itself must clear its candidates.
        try std.testing.expect(try plan.matchIntoWithScratch(&g, &maps, plan.root, fresh, anchors, &scratch));
        try std.testing.expectEqual(initialized, scratch.stats.initialized_slots);
        try std.testing.expectEqual(plan.order.len, scratch.anchor_ids.items.len);
    }
    var foreign = try Generator.init(&after);
    defer foreign.deinit();
    try std.testing.expectError(error.Declined, scratch.begin(&plan, &foreign));
    var moved = scratch;
    try std.testing.expectError(error.Declined, moved.begin(&plan, &g));
    var other_gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer other_gate.deinit();
    var other_plan = plan;
    other_plan.gate = &other_gate;
    try std.testing.expectError(error.Declined, scratch.begin(&other_plan, &g));
    other_plan = plan;
    other_plan.row_policy = .source_declared;
    try std.testing.expectError(error.Declined, scratch.begin(&other_plan, &g));
    try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
    try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
}

const scratch_span_source =
    \\const first = @array.generate 2 (fn (index: U32) => if @u32.eq index 0 then 40 else 2)
    \\const second = @array.generate 2 (fn (index: U32) => if @u32.eq index 0 then 2 else 40)
    \\const bundle = (first, second)
    \\entry const schema: U32 = 7
    \\entry const answer = fn (index: U32) => do:
    \\  let (left, right) = bundle
    \\  return @u32.add (@array.get left index) (@array.get right index)
;
fn scratchSharedSpanFailure(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, retry_failure: ?*std.testing.FailingAllocator) !void {
    const pools = &old.metadata.pools.?;
    var gate = try gate_api.Gate.init(allocator, pools, fixture.units, fixture.names.view());
    defer gate.deinit();
    var plan = try inspect(allocator, old, &gate, fixture.target("bundle"));
    defer plan.deinit(allocator);
    var g = try Generator.initAt(allocator, fixture);
    defer g.deinit();
    var maps = try @import("artifact_import.zig").Importer.init(allocator, pools, fixture.units, fixture.names.view(), fixture.units.len);
    defer maps.deinit();
    var scratch: graph.QueryScratch = .{ .allocator = allocator };
    defer scratch.deinit();
    const sizes = sourceRowPublicationSizes(&g);
    const slots = artifacts.stamp(g.evaluator.slots);
    var anchors = try scratch.begin(&plan, &g);
    // Two arrays share their entire old child span; the product has a distinct
    // two-child span. A deliberately wrong growth receipt warms and declines.
    const wrong: graph.Plan.QueryStorage = .{ .values_before = 0, .values_added = plan.order.len, .children_added = 5 };
    if (plan.materializeReceiptWithScratch(&g, &maps, anchors, wrong, &scratch)) |_| {
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.OutOfMemory => {
            try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
            try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
            return err;
        },
        error.Declined => {},
    }
    try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
    try std.testing.expectEqual(@as(usize, 0), scratch.child_ids.items.len);
    anchors = try scratch.begin(&plan, &g);
    const exact: graph.Plan.QueryStorage = .{ .values_before = 0, .values_added = plan.order.len, .children_added = 4 };
    if (retry_failure) |failure| {
        failure.fail_index = failure.alloc_index;
        failure.resize_fail_index = failure.resize_index;
        try std.testing.expectError(error.OutOfMemory, plan.materializeReceiptWithScratch(&g, &maps, anchors, exact, &scratch));
        try std.testing.expect(failure.has_induced_failure);
        try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        try std.testing.expectEqual(@as(usize, 0), scratch.child_ids.items.len);
        for (anchors) |value| try std.testing.expectEqual(@as(u32, 0), value);
        failure.fail_index = std.math.maxInt(usize);
        failure.resize_fail_index = std.math.maxInt(usize);
        // Retry in the same bound buffers, without a begin/reset operation.
    }
    const mapped = plan.materializeReceiptWithScratch(&g, &maps, anchors, exact, &scratch) catch |err| {
        try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        try std.testing.expectEqual(@as(usize, 0), scratch.child_ids.items.len);
        return err;
    };
    try std.testing.expectEqual(plan.order.len, g.evaluator.values.items.len - sizes[0]);
    try std.testing.expectEqual(@as(usize, 4), g.evaluator.children.items.len - sizes[1]);
    const root = mapped[plan.root];
    const arrays = g.evaluator.valueChildren(root);
    try std.testing.expectEqual(@as(usize, 2), arrays.len);
    try std.testing.expect(arrays[0] != arrays[1]);
    try std.testing.expectEqual(g.evaluator.valueInfo(arrays[0]).start, g.evaluator.valueInfo(arrays[1]).start);
    try sameValue(&pools.evaluator, plan.root, &g.evaluator, root);
    try std.testing.expectEqual(@as(usize, 0), scratch.child_ids.items.len);
}

test "query graph scratch warmed child positions preserve exact shared spans under every allocation failure" {
    var before = try Fixture.init(scratch_span_source);
    defer before.deinit();
    var after = try Fixture.init(scratch_span_source);
    defer after.deinit();
    editSchema(&after);
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    // Prepare a valid trusted-format graph before constructing any Plan.
    const pools = &old.capture.?.metadata.pools.?;
    const target = before.target("bundle");
    const root = pools.slots[pools.binding_offsets[0] + target.binding].value;
    const children = pools.evaluator.children[pools.evaluator.values[root].start..][0..2];
    pools.evaluator.values[children[1]].start = pools.evaluator.values[children[0]].start;
    try scratchSharedSpanFailure(a, &after, &old.capture.?, null);
    var retry_failure = std.testing.FailingAllocator.init(a, .{});
    try scratchSharedSpanFailure(retry_failure.allocator(), &after, &old.capture.?, &retry_failure);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scratchSharedSpanFailure, .{ &after, &old.capture.?, null });
}

test "query graph scratch partial old child overlap declines without publication and can retry" {
    var before = try Fixture.init(scratch_span_source);
    defer before.deinit();
    var after = try Fixture.init(scratch_span_source);
    defer after.deinit();
    editSchema(&after);
    var old = try before.emit(a, .{ .retain_artifacts = true });
    defer old.deinit(a);
    try successful(&old);
    const pools = &old.capture.?.metadata.pools.?;
    const target = before.target("bundle");
    const root = pools.slots[pools.binding_offsets[0] + target.binding].value;
    const children = pools.evaluator.children[pools.evaluator.values[root].start..][0..2];
    pools.evaluator.values[children[1]].start = pools.evaluator.values[children[0]].start + 1;
    var gate = try gate_api.Gate.init(a, pools, after.units, after.names.view());
    defer gate.deinit();
    var plan = try inspect(a, &old.capture.?, &gate, target);
    defer plan.deinit(a);
    var g = try Generator.init(&after);
    defer g.deinit();
    var maps = try @import("artifact_import.zig").Importer.init(a, pools, after.units, after.names.view(), after.units.len);
    defer maps.deinit();
    var scratch: graph.QueryScratch = .{ .allocator = a };
    defer scratch.deinit();
    const sizes = sourceRowPublicationSizes(&g);
    const slots = artifacts.stamp(g.evaluator.slots);
    const storage: graph.Plan.QueryStorage = .{ .values_before = 0, .values_added = plan.order.len, .children_added = 5 };
    for (0..2) |_| {
        const anchors = try scratch.begin(&plan, &g);
        try std.testing.expectError(error.Declined, plan.materializeReceiptWithScratch(&g, &maps, anchors, storage, &scratch));
        try std.testing.expectEqual(sizes, sourceRowPublicationSizes(&g));
        try std.testing.expectEqualSlices(u8, &slots, &artifacts.stamp(g.evaluator.slots));
        try std.testing.expectEqual(@as(usize, 0), scratch.child_ids.items.len);
        for (scratch.children.items) |position| try std.testing.expectEqual(std.math.maxInt(u32), position);
    }
}

fn gatePilotOptions(old: *const capture.Capture) backend.CompileOptions {
    return .{ .retain_artifacts = true, .previous = old };
}

test "shared query gate backend uses one clone and matches fresh output" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    try successful(&fresh);
    var on = try after.emit(a, gatePilotOptions(&initial.capture.?));
    defer on.deinit(a);
    try successful(&on);
    try std.testing.expectEqualSlices(u8, fresh.bytes, on.bytes);
    try std.testing.expectEqual(fresh.constant_steps, on.constant_steps);
    try std.testing.expect(on.completed_queries.reused > 0);
    try std.testing.expectEqual(@as(usize, 1), on.completed_queries.shared_gates);
    try std.testing.expectEqual(@as(usize, 0), on.completed_queries.gate_fresh);
    try std.testing.expect(on.completed_queries.shared_gate_bytes > 0);
}

test "shared query gate new compile freshly detects changed Core at the same owner address" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    {
        var first = try after.emit(a, gatePilotOptions(&initial.capture.?));
        defer first.deinit(a);
        try successful(&first);
        try std.testing.expect(first.completed_queries.reused > 0);
    }
    const same_owner = after.units.ptr;
    var edits: usize = 0;
    for (after.units[0].nodes) |*node| if (node.tag == .constant and node.a == 42) {
        node.a = 43;
        edits += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), edits);
    try std.testing.expect(after.units.ptr == same_owner);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var changed = try after.emit(a, gatePilotOptions(&initial.capture.?));
    defer changed.deinit(a);
    try successful(&fresh);
    try successful(&changed);
    try std.testing.expectEqual(@as(usize, 1), changed.completed_queries.shared_gates);
    try std.testing.expectEqual(@as(usize, 0), changed.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqual(fresh.constant_steps, changed.constant_steps);
}

test "shared query gate keeps query Plans owned after principal teardown and declines changed live owners" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var g = try Generator.init(&after);
    defer g.deinit();
    g.evaluator.options.trace_runtime_dependencies = true;
    g.evaluator.retain_specialization_receipts = true;
    const input = try g.evaluator.richValue(after.target("callback"));
    const expected = try queryExpected(&g, &initial.capture.?, initial.capture.?.metadata.specialization_receipts.items[0].expected);
    var principal = try @import("principal_evidence_reuse.zig").State.init(a, &initial.capture.?, after.units, after.names.view(), null);
    const cloned = (@import("shared_query_gate.zig").share(a, &initial.capture.?.metadata.pools.?, after.units, &principal.gate)) orelse return error.ExpectedClone;
    var state: @import("completed_specialization_query.zig").State = .{ .allocator = a, .old = &initial.capture.?, .gate = cloned, .graph_scratch = .{ .allocator = a } };
    defer state.deinit();
    principal.deinit();
    const selected = (try state.lookup(&g, input, expected)) orelse return error.ExpectedHit;
    try std.testing.expectEqual(@as(usize, 1), state.stats.reused);
    var moved = state; // Borrowed copy only; original retains destruction.
    try std.testing.expect(try moved.lookup(&g, input, expected) == null);
    var another = try Generator.init(&after);
    defer another.deinit();
    const other_input = try another.evaluator.richValue(after.target("callback"));
    const other_expected = try queryExpected(&another, &initial.capture.?, initial.capture.?.metadata.specialization_receipts.items[0].expected);
    try std.testing.expect(try state.lookup(&another, other_input, other_expected) == null);
    g.evaluator.slots[g.evaluator.binding_offsets[0] + after.target("callback").binding].value = selected;
    try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(after.target("run_value"))).bits);
}

fn gateBackendFailure(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, expected: []const u8, fuel: usize) !void {
    var result = try fixture.emit(allocator, gatePilotOptions(old));
    defer result.deinit(allocator);
    try successful(&result);
    try std.testing.expectEqual(@as(usize, 1), result.completed_queries.shared_gates);
    try std.testing.expectEqual(@as(usize, 0), result.completed_queries.gate_fresh);
    try std.testing.expect(result.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(fuel, result.constant_steps);
}

test "shared query gate backend releases every allocation failure without changing previous artifacts" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    const old_values = artifacts.stamp(initial.capture.?.metadata.pools.?.evaluator.values);
    const old_slots = artifacts.stamp(initial.capture.?.metadata.pools.?.slots);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, gateBackendFailure, .{ &after, &initial.capture.?, fresh.bytes, fresh.constant_steps });
    try std.testing.expectEqualSlices(u8, &old_values, &artifacts.stamp(initial.capture.?.metadata.pools.?.evaluator.values));
    try std.testing.expectEqualSlices(u8, &old_slots, &artifacts.stamp(initial.capture.?.metadata.pools.?.slots));
}

test "checked query importer backend preserves rows and exact work" {
    var before = try Fixture.init(source_row_query);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var after = try Fixture.init(source_row_query);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    try successful(&fresh);
    var on = try after.emit(a, gatePilotOptions(&initial.capture.?));
    defer on.deinit(a);
    try successful(&on);
    try std.testing.expectEqualSlices(u8, fresh.bytes, on.bytes);
    try std.testing.expectEqual(fresh.constant_steps, on.constant_steps);
    try std.testing.expect(on.completed_queries.reused > 0);
    try std.testing.expectEqual(@as(usize, 1), on.completed_queries.prepared_importers);
    try std.testing.expectEqual(@as(usize, 0), on.completed_queries.fresh_importers);
}

test "checked query importer new compile detects body mutation and live State owners and options remain bound" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    {
        var g = try Generator.init(&after);
        defer g.deinit();
        g.evaluator.options.trace_runtime_dependencies = true;
        g.evaluator.retain_specialization_receipts = true;
        const input = try g.evaluator.richValue(after.target("callback"));
        const expected = try queryExpected(&g, &initial.capture.?, initial.capture.?.metadata.specialization_receipts.items[0].expected);
        var state = try @import("completed_specialization_query.zig").State.init(a, &initial.capture.?, after.units, after.names.view());
        defer state.deinit();
        const selected = (try state.lookup(&g, input, expected)) orelse return error.ExpectedHit;
        try std.testing.expectEqual(@as(usize, 1), state.stats.prepared_importers);
        var moved = state; // Borrowed copy; original alone destroys owned state.
        try std.testing.expect(try moved.lookup(&g, input, expected) == null);
        var another = try Generator.init(&after);
        defer another.deinit();
        const other_input = try another.evaluator.richValue(after.target("callback"));
        const other_expected = try queryExpected(&another, &initial.capture.?, initial.capture.?.metadata.specialization_receipts.items[0].expected);
        try std.testing.expect(try state.lookup(&another, other_input, other_expected) == null);
        try std.testing.expect(try state.lookup(&g, input, expected) == null);
        g.evaluator.options.max_steps = 1;
        try std.testing.expect(try state.lookup(&g, input, expected) == null);
        g.evaluator.options.max_steps = (eval.Options{}).max_steps;
        g.evaluator.slots[g.evaluator.binding_offsets[0] + after.target("callback").binding].value = selected;
        try std.testing.expectEqual(@as(u32, 42), (try g.evaluator.value(after.target("run_value"))).bits);
    }
    const same_owner = after.units.ptr;
    var edits: usize = 0;
    for (after.units[0].nodes) |*node| if (node.tag == .constant and node.a == 42) {
        node.a = 43;
        edits += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), edits);
    try std.testing.expect(after.units.ptr == same_owner);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var changed = try after.emit(a, gatePilotOptions(&initial.capture.?));
    defer changed.deinit(a);
    try successful(&fresh);
    try successful(&changed);
    try std.testing.expectEqual(@as(usize, 0), changed.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqual(fresh.constant_steps, changed.constant_steps);
}

fn preparedQueryBackendFailure(allocator: Allocator, fixture: *const Fixture, old: *const capture.Capture, expected: []const u8, work: usize) !void {
    var result = try fixture.emit(allocator, gatePilotOptions(old));
    defer result.deinit(allocator);
    try successful(&result);
    try std.testing.expectEqual(@as(usize, 1), result.completed_queries.prepared_importers);
    try std.testing.expectEqual(@as(usize, 0), result.completed_queries.fresh_importers);
    try std.testing.expect(result.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(work, result.constant_steps);
}

test "checked query importer backend keeps previous values slots and query memo publication atomic under every OOM" {
    var before = try Fixture.init(query_source);
    defer before.deinit();
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    var after = try Fixture.init(query_source);
    defer after.deinit();
    editSchema(&after);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    const old_values = artifacts.stamp(initial.capture.?.metadata.pools.?.evaluator.values);
    const old_slots = artifacts.stamp(initial.capture.?.metadata.pools.?.slots);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, preparedQueryBackendFailure, .{ &after, &initial.capture.?, fresh.bytes, fresh.constant_steps });
    try std.testing.expectEqualSlices(u8, &old_values, &artifacts.stamp(initial.capture.?.metadata.pools.?.evaluator.values));
    try std.testing.expectEqualSlices(u8, &old_slots, &artifacts.stamp(initial.capture.?.metadata.pools.?.slots));
}
