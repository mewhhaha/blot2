const std = @import("std");
const importer = @import("artifact_import.zig");
const artifacts = @import("code_artifacts.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const layout = @import("layout.zig");
const substitutions = @import("substitution_keys.zig");
const runtime_identity = @import("runtime_identity.zig");
const runtime_operations = @import("runtime_operations.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const Allocator = std.mem.Allocator;
const a = std.testing.allocator;

const Fixture = struct {
    units: []core.Module,
    names: runtime_identity.Metadata,
    right: u32,
    left: u32,
    fn init(reordered: bool) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        if (reordered) {
            _ = try pool.intern(a, "left");
            _ = try pool.intern(a, "right");
            _ = try pool.intern(a, "unrelated");
        } else {
            _ = try pool.intern(a, "right");
            _ = try pool.intern(a, "left");
        }
        const units = try a.alloc(core.Module, 3);
        errdefer a.free(units);
        var count: usize = 0;
        errdefer for (units[0..count]) |*unit| unit.deinit(a);
        for (units, 0..) |*unit, i| {
            unit.* = try lower(&pool, @intCast(i + 1), if (i == 2)
                "entry const answer = fn () => 43\n"
            else
                "type Cell is data = #Cell { right: F32, left: U32 }\neffect Read: Unit -> F32\nconst factory = fn value => do:\n  return fn extra => @f32.add value extra\nconst read = fn () => Read ()\nentry const answer = fn (value: F32) => @f32.add value 1.0\n");
            count += 1;
        }
        const names = try runtime_identity.Metadata.capture(a, &pool, &.{
            .{ .unit = 1, .path = if (reordered) "/artifact-import/b.blot" else "/artifact-import/a.blot" },
            .{ .unit = 2, .path = if (reordered) "/artifact-import/a.blot" else "/artifact-import/b.blot" },
            .{ .unit = 3, .path = "/artifact-import/main.blot" },
        }, 3);
        return .{ .units = units, .names = names, .right = try pool.intern(a, "right"), .left = try pool.intern(a, "left") };
    }
    fn deinit(self: *Fixture) void {
        self.names.deinit(a);
        for (self.units) |*unit| unit.deinit(a);
        a.free(self.units);
    }
};
fn lower(pool: *symbols.Pool, unit: u32, source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, pool, &.{}, &.{}, unit, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, pool, &checked);
    module.unit = unit;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
const Generator = struct {
    allocator: Allocator,
    evaluator: eval.Session,
    layouts: layout.Store,
    row_keys: substitutions.Store,
    template_keys: substitutions.Store,
    template_catalog: std.ArrayList(artifacts.CapturedTemplate) = .empty,
    template_instances: std.AutoHashMapUnmanaged(artifacts.CapturedTemplate, u32) = .empty,
    runtime_operations: runtime_operations.Store,
    fn init(fixture: *const Fixture) !Generator {
        return initAt(a, fixture);
    }
    fn initAt(allocator: Allocator, fixture: *const Fixture) !Generator {
        var evaluator = try eval.Session.init(allocator, fixture.units);
        errdefer evaluator.deinit();
        return .{ .allocator = allocator, .evaluator = evaluator, .layouts = try layout.Store.init(allocator), .row_keys = substitutions.Store.init(allocator), .template_keys = substitutions.Store.init(allocator), .runtime_operations = runtime_operations.Store.initProject(allocator, fixture.names.view()) };
    }
    fn deinit(self: *Generator) void {
        self.template_instances.deinit(self.allocator);
        self.template_catalog.deinit(self.allocator);
        self.runtime_operations.deinit();
        self.row_keys.deinit();
        self.template_keys.deinit();
        self.layouts.deinit();
        self.evaluator.deinit();
    }
};
const Inputs = struct {
    physical: u32,
    semantic: u32,
    callback: u32,
    unknown_callback: u32,
    first_state: u32,
    second_state: u32,
    request: artifacts.Request,
    result_template: u32,
    operation: u32,
};
fn buildInputs(g: *Generator, fixture: *const Fixture) !Inputs {
    const physical = try g.layouts.intern(.record, 0, 0, &.{ fixture.right, 4, fixture.left, 3 });
    const semantic = try g.evaluator.evidence.intern(.record, 0, 0, &.{ fixture.left, 3, fixture.right, 4 });
    const operation = try g.layouts.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{physical});
    const latent = try g.layouts.effects.internRow(&.{ operation, operation });
    const callback = try g.layouts.internWithEffects(.function, 3, 4, latent, &.{});
    const unknown_callback = try g.layouts.internWithEffects(.function, 3, 4, layout.unknown_row, &.{});
    const first_state = try g.layouts.intern(.nominal, 1, nominalDecl(&fixture.units[0]), &.{physical});
    const second_state = try g.layouts.intern(.nominal, 2, nominalDecl(&fixture.units[1]), &.{physical});
    const first_read = try g.layouts.intern(.nominal, std.math.maxInt(u32), 1, &.{first_state});
    const first_write = try g.layouts.intern(.nominal, std.math.maxInt(u32), 2, &.{first_state});
    const state_provider = try g.layouts.internStateProvider(first_read, first_write, first_state);
    const captures = try g.layouts.intern(.product, 0, 0, &.{ state_provider, callback });
    const owner = &fixture.units[0];
    const parameter = owner.bodyParameters(&owner.bodies[1])[0].binding;
    const variable: u32 = owner.bindings[parameter].ty;
    const mappings = try g.evaluator.evidence.intern(.record, 0, 0, &.{ variable, semantic });
    const semantic_op = try g.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(owner) }, &.{semantic});
    const semantic_row = try g.evaluator.evidence.effects.internRow(&.{semantic_op});
    const runtime_operation = try g.runtime_operations.intern(g.evaluator.evidence.view(), semantic_op);
    const rows = if (owner.types.effects.variable_count != 0) try g.row_keys.intern(&.{.{ .variable = 0, .value = semantic_row }}) else 0;
    const inner: artifacts.CapturedTemplate = .{ .unit = 2, .node = fixture.units[1].bodies[1].root, .captures = captures, .templates = 0, .has_environment = true };
    try g.template_catalog.append(a, inner);
    try g.template_instances.put(a, inner, 1);
    const templates = try g.template_keys.intern(&.{.{ .variable = parameter, .value = 1 }});
    const outer: artifacts.CapturedTemplate = .{ .unit = 1, .node = owner.bodies[1].root, .captures = captures, .templates = templates, .has_environment = true, .evidence = mappings, .rows = rows };
    try g.template_catalog.append(a, outer);
    try g.template_instances.put(a, outer, 2);
    return .{ .physical = physical, .semantic = semantic, .callback = callback, .unknown_callback = unknown_callback, .first_state = first_state, .second_state = second_state, .request = .{ .closure = .{ .unit = 1, .catalog = 0, .ty = callback, .captures = captures, .templates = templates, .evidence = mappings, .rows = rows, .parameter_template = 2, .template_result = true } }, .result_template = 2, .operation = runtime_operation };
}
fn copySubstitutions(store: *const substitutions.Store) !artifacts.Substitutions {
    const entries = try a.dupe(substitutions.Entry, store.entries.items);
    errdefer a.free(entries);
    const spans = try a.alloc(artifacts.Span, store.spans.items.len);
    for (store.spans.items, spans) |source, *dest| dest.* = .{ .start = source.start, .len = source.len };
    return .{ .entries = entries, .spans = spans };
}
fn effectDecl(module: *const core.Module) u32 {
    for (module.types.operations) |operation| if (operation.identity.unit == module.unit and operation.identity.decl != 0) return operation.identity.decl;
    unreachable;
}
fn nominalDecl(module: *const core.Module) u32 {
    for (module.nominals) |nominal| if (nominal.identity.decl != 0) return nominal.identity.decl;
    unreachable;
}
fn capture(g: *const Generator, fixture: *const Fixture) !artifacts.Pools {
    const modules = try a.alloc(artifacts.ModulePin, fixture.units.len);
    var count: usize = 0;
    errdefer {
        for (modules[0..count]) |pin| a.free(pin.canonical_path);
        a.free(modules);
    }
    for (fixture.units, modules, 0..) |*unit, *pin, i| {
        pin.* = .{ .unit = @intCast(i + 1), .module = unit, .canonical_path = try a.dupe(u8, fixture.names.view().owner(@intCast(i + 1)).?), .stamp = artifacts.stamp(unit.*) };
        count += 1;
    }
    const layouts = try a.dupe(layout.Node, g.layouts.nodes.items);
    errdefer a.free(layouts);
    const extra = try a.dupe(u32, g.layouts.extra.items);
    errdefer a.free(extra);
    var effects = try g.layouts.effects.copyOwned(a);
    errdefer effects.deinit(a);
    var evaluator = try g.evaluator.copySnapshot(a);
    errdefer evaluator.deinit(a);
    const rows = try copySubstitutions(&g.row_keys);
    errdefer {
        a.free(rows.entries);
        a.free(rows.spans);
    }
    const templates = try copySubstitutions(&g.template_keys);
    errdefer {
        a.free(templates.entries);
        a.free(templates.spans);
    }
    const captures = try a.dupe(artifacts.CapturedTemplate, g.template_catalog.items);
    errdefer a.free(captures);
    const fields = try a.alloc(artifacts.FieldLocation, g.evaluator.field_locations.count());
    errdefer a.free(fields);
    var locations = g.evaluator.field_locations.iterator();
    var i: usize = 0;
    while (locations.next()) |entry| : (i += 1) fields[i] = .{ .family = entry.key_ptr.family, .tag = entry.key_ptr.tag, .name = entry.key_ptr.name, .field = entry.value_ptr.field, .len = entry.value_ptr.len };
    var names = try copyNames(fixture.names.view());
    errdefer names.deinit(a);
    const operations = try a.alloc(artifacts.Operation, g.runtime_operations.entries.items.len);
    var operation_count: usize = 0;
    errdefer {
        for (operations[0..operation_count]) |operation| a.free(operation.key);
        a.free(operations);
    }
    for (g.runtime_operations.entries.items, operations) |source, *destination| {
        destination.* = .{ .key = try a.dupe(u8, source.key), .foreign = source.foreign, .runtime = source.runtime };
        operation_count += 1;
    }
    return .{
        .project_identity = true,
        .identity = names,
        .modules = modules,
        .bodies = &.{},
        .layouts = .{ .nodes = layouts, .extra = extra, .effects = effects },
        .evaluator = evaluator,
        .rows = rows,
        .templates = templates,
        .captures = captures,
        .field_locations = fields,
        .field_locations_stamp = artifacts.stamp(fields),
        .operations = operations,
        .operation_relocations = &.{},
        .operations_finalized = false,
        .functions = &.{},
        .serialized = &.{},
        .runtime_globals = &.{},
        .runtime_order = &.{},
        .binding_offsets = &.{},
        .node_offsets = &.{},
        .slots = &.{},
        .visited_nodes = &.{},
        .provider_frames = &.{},
        .provider_cells = &.{},
        .request_cells = &.{},
        .request_handlers = &.{},
        .break_values = &.{},
        .array_proofs = &.{},
        .discard_proofs = &.{},
        .evaluator_steps = 0,
        .evaluator_demanded = 0,
        .evaluator_traced_bodies = 0,
        .evaluator_traced_nodes = 0,
    };
}
fn copyNames(view: runtime_identity.View) !runtime_identity.Metadata {
    const bytes = try a.dupe(u8, view.bytes);
    errdefer a.free(bytes);
    const names = try a.dupe(@typeInfo(@TypeOf(view.symbols)).pointer.child, view.symbols);
    errdefer a.free(names);
    return .{ .bytes = bytes, .symbols = names, .owners = try a.dupe(@typeInfo(@TypeOf(view.owners)).pointer.child, view.owners) };
}
fn assertImports(allocator: Allocator, old: *const artifacts.Pools, inputs: Inputs, fixture: *const Fixture, g: *Generator, prior: u32) !void {
    const old_stamp = artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra, old.templates.entries, old.captures });
    var imports = try importer.Importer.init(allocator, old, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    const attempt = performImports(&imports, inputs, fixture, g) catch |err| {
        try std.testing.expectEqual(layout.Tag.function, g.layouts.node(prior).tag);
        try std.testing.expectEqual(@as(u32, 3), g.layouts.node(prior).a);
        try std.testing.expectEqual(@as(u32, 3), g.layouts.node(prior).b);
        try std.testing.expectEqual(old_stamp, artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra, old.templates.entries, old.captures }));
        return err;
    };
    _ = attempt;
    try std.testing.expectEqual(layout.Tag.function, g.layouts.node(prior).tag);
    try std.testing.expectEqual(old_stamp, artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra, old.templates.entries, old.captures }));
}
fn performImports(imports: *importer.Importer, inputs: Inputs, fixture: *const Fixture, g: *Generator) !void {
    try std.testing.expect(imports.stable[0] and imports.stable[1]);
    try std.testing.expect(!imports.stable[2]);
    const physical = try required("physical", try imports.importLayout(g, inputs.physical));
    try std.testing.expectEqualSlices(u32, &.{ fixture.right, 4, fixture.left, 3 }, g.layouts.children(physical));
    const semantic = try required("semantic", try imports.importEvidence(g, inputs.semantic));
    // Semantic ordering follows the CURRENT symbol namespace, unlike physical slots.
    try std.testing.expectEqualSlices(u32, &.{ fixture.left, 3, fixture.right, 4 }, g.evaluator.evidence.children(semantic));
    const first = try required("first_state", try imports.importLayout(g, inputs.first_state));
    const second = try required("second_state", try imports.importLayout(g, inputs.second_state));
    try std.testing.expect(first != second);
    try std.testing.expectEqual(@as(u32, 2), g.layouts.node(first).a);
    try std.testing.expectEqual(@as(u32, 1), g.layouts.node(second).a);
    const maybe_request = try imports.importRequest(g, inputs.request);
    if (maybe_request == null) std.debug.print("missing closure request\n", .{});
    try std.testing.expect(maybe_request != null);
    const request = maybe_request.?;
    try std.testing.expectEqual(@as(u32, 2), request.closure.unit);
    try std.testing.expect(try imports.matches(g, inputs.request, request));
    var other = request;
    other.closure.template_result = false;
    try std.testing.expect(!try imports.matches(g, inputs.request, other));
    const result = try required("result_template", try imports.importResultTemplate(g, inputs.result_template));
    const outer = g.template_catalog.items[result - 1];
    try std.testing.expectEqual(@as(u32, 2), outer.unit);
    const nested = g.template_keys.get(outer.templates)[0].value;
    try std.testing.expectEqual(@as(u32, 1), g.template_catalog.items[nested - 1].unit);
    try std.testing.expect(outer.has_environment and g.template_catalog.items[nested - 1].has_environment);
    const callback = g.layouts.node(request.closure.ty);
    const labels = g.layouts.effects.view().rowLabels(callback.c);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(@as(u32, 2), g.layouts.effects.view().operation(labels[0]).identity.unit);
    const operation_request: artifacts.Request = .{ .operation = .{ .operation = inputs.operation, .ty = inputs.callback } };
    try std.testing.expectEqual(@as(usize, 0), g.runtime_operations.entries.items.len);
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(g, operation_request));
    try std.testing.expectEqual(@as(usize, 0), g.runtime_operations.entries.items.len);
    const foreign = try g.evaluator.evidence.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    _ = try g.runtime_operations.intern(g.evaluator.evidence.view(), foreign);
    const actual_operation = try g.evaluator.evidence.effects.internOperation(.{ .unit = 2, .decl = effectDecl(imports.old.modules[0].module) }, &.{semantic});
    const runtime_operation = try g.runtime_operations.intern(g.evaluator.evidence.view(), actual_operation);
    try std.testing.expect(runtime_operation != inputs.operation);
    const count = g.runtime_operations.entries.items.len;
    const matched = (try imports.importRequest(g, operation_request)).?;
    try std.testing.expectEqual(runtime_operation, matched.operation.operation);
    try std.testing.expectEqual(count, g.runtime_operations.entries.items.len);
    try std.testing.expect(try imports.matches(g, operation_request, matched));
    try std.testing.expectEqual(count, g.runtime_operations.entries.items.len);
    const unknown = try required("unknown_row", try imports.importLayout(g, inputs.unknown_callback));
    try std.testing.expectEqual(layout.unknown_row, g.layouts.node(unknown).c);
    try std.testing.expect(unknown != request.closure.ty);
    var unknown_request = inputs.request;
    unknown_request.closure.ty = inputs.unknown_callback;
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(g, unknown_request));
    const closed = try g.layouts.intern(.function, 3, 4, &.{});
    try std.testing.expectEqual(@as(u32, 0), g.layouts.node(closed).c);
    try std.testing.expect(closed != unknown);
    try std.testing.expectEqual(@as(?u32, layout.erased), try imports.importLayout(g, layout.erased));
    var erased_request = inputs.request;
    erased_request.closure.captures = layout.erased;
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(g, erased_request));
    const old_owner = imports.old.modules[0].module;
    const binding = old_owner.bodyParameters(&old_owner.bodies[1])[0].binding;
    var job: artifacts.Job = .{
        .parent = 0,
        .request = inputs.request,
        .state = .complete,
        .solved = true,
        .mappings = @constCast(&[_]layout.Mapping{.{ .variable = old_owner.bindings[binding].ty, .layout = inputs.physical }}),
        .templates = @constCast(&[_]substitutions.Entry{.{ .variable = binding, .value = inputs.result_template }}),
    };
    var solved = (try imports.importSolved(g, &job)).?;
    defer solved.deinit(imports.allocator);
    try std.testing.expectEqual(physical, solved.mappings[0].layout);
    try std.testing.expectEqual(result, solved.templates[0].value);
    job.state = .reserved;
    try std.testing.expectEqual(@as(?importer.Solved, null), try imports.importSolved(g, &job));
}
fn required(role: []const u8, value: ?u32) !u32 {
    if (value == null) std.debug.print("missing {s}\n", .{role});
    try std.testing.expect(value != null);
    return value.?;
}
test "artifact import maps producer and symbol namespaces and distinct State captures after generator teardown" {
    var old_fixture = try Fixture.init(false);
    defer old_fixture.deinit();
    var old_generator = try Generator.init(&old_fixture);
    var old_alive = true;
    defer if (old_alive) old_generator.deinit();
    const inputs = try buildInputs(&old_generator, &old_fixture);
    var pools = try capture(&old_generator, &old_fixture);
    defer pools.deinit(a);
    old_generator.deinit();
    old_alive = false;
    var current_fixture = try Fixture.init(true);
    defer current_fixture.deinit();
    var current = try Generator.init(&current_fixture);
    defer current.deinit();
    const prior = try current.layouts.intern(.function, 3, 3, &.{});
    _ = try current.evaluator.evidence.intern(.array, 4, 0, &.{});
    const junk: artifacts.CapturedTemplate = .{ .unit = 1, .node = current_fixture.units[0].bodies[1].root, .captures = try current.layouts.intern(.product, 0, 0, &.{}), .templates = 0, .has_environment = false };
    try current.template_catalog.append(a, junk);
    try current.template_instances.put(a, junk, 1);
    try assertImports(a, &pools, inputs, &current_fixture, &current, prior);
}
test "artifact import allocation failures preserve the old capture and every earlier current success" {
    var old_fixture = try Fixture.init(false);
    defer old_fixture.deinit();
    var old_generator = try Generator.init(&old_fixture);
    defer old_generator.deinit();
    const inputs = try buildInputs(&old_generator, &old_fixture);
    var pools = try capture(&old_generator, &old_fixture);
    defer pools.deinit(a);
    var fixture = try Fixture.init(true);
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, oomImports, .{ &pools, inputs, &fixture });
}

test "artifact operation matching qualifies phantom owners without publishing runtime symbols" {
    var fixture = try Fixture.init(false);
    defer fixture.deinit();
    var producer = try Generator.init(&fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    producer.runtime_operations.deinit();
    producer.runtime_operations = runtime_operations.Store.initProject(a, fixture.names.view());
    const fresh_argument = try producer.evaluator.evidence.intern(.nominal, 3, 1, &.{3});
    const stable_label = try producer.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{3});
    const fresh_label = try producer.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{fresh_argument});
    const stable_id = try producer.runtime_operations.intern(producer.evaluator.evidence.view(), stable_label);
    const fresh_id = try producer.runtime_operations.intern(producer.evaluator.evidence.view(), fresh_label);
    var pools = try capture(&producer, &fixture);
    defer pools.deinit(a);
    var consumer = try Generator.init(&fixture);
    defer consumer.deinit();
    consumer.runtime_operations.deinit();
    consumer.runtime_operations = runtime_operations.Store.initProject(a, fixture.names.view());
    for (pools.operations) |operation| _ = try consumer.runtime_operations.internSymbol(operation.key, operation.foreign);
    const before = artifacts.stamp(consumer.runtime_operations.entries.items);
    var imports = try importer.Importer.init(a, &pools, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    const stable = (try imports.importRequest(&consumer, .{ .operation = .{ .operation = stable_id, .ty = inputs.callback } })).?;
    try std.testing.expectEqual(stable_id, stable.operation.operation);
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&consumer, .{ .operation = .{ .operation = fresh_id, .ty = inputs.callback } }));
    try std.testing.expectEqual(before, artifacts.stamp(consumer.runtime_operations.entries.items));
}
fn oomImports(allocator: Allocator, pools: *const artifacts.Pools, inputs: Inputs, fixture: *const Fixture) !void {
    var current = try Generator.initAt(allocator, fixture);
    defer current.deinit();
    const prior = try current.layouts.intern(.function, 3, 3, &.{});
    const old_stamp = artifacts.stamp(.{ pools.layouts.nodes, pools.layouts.extra, pools.captures, pools.templates.entries });
    assertImports(allocator, pools, inputs, fixture, &current, prior) catch |err| {
        try std.testing.expectEqual(layout.Tag.function, current.layouts.node(prior).tag);
        try std.testing.expectEqual(@as(u32, 3), current.layouts.node(prior).b);
        try std.testing.expectEqual(old_stamp, artifacts.stamp(.{ pools.layouts.nodes, pools.layouts.extra, pools.captures, pools.templates.entries }));
        return err;
    };
}

test "artifact identity collision with identical numeric Core and different spellings cannot certify a body" {
    var original = try Fixture.init(false);
    defer original.deinit();
    var original_generator = try Generator.init(&original);
    defer original_generator.deinit();
    const inputs = try buildInputs(&original_generator, &original);
    var pools = try capture(&original_generator, &original);
    defer pools.deinit(a);
    var current = try Fixture.init(false);
    defer current.deinit();
    try std.testing.expectEqual(artifacts.stamp(original.units[0]), artifacts.stamp(current.units[0]));
    // All numeric Core fields stay identical. Only the namespace interpreting
    // those numbers changes, so accepting raw equality would be incorrect.
    const right = current.names.symbols[current.right];
    current.names.symbols[current.right] = current.names.symbols[current.left];
    current.names.symbols[current.left] = right;
    var generator = try Generator.init(&current);
    defer generator.deinit();
    var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 2);
    defer imports.deinit();
    try std.testing.expect(!imports.stable[0] and !imports.stable[1]);
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&generator, inputs.request));
}

test "artifact imports decline malformed identity fresh producers changed bodies and physical catalog movement" {
    var original = try Fixture.init(false);
    defer original.deinit();
    var old_generator = try Generator.init(&original);
    defer old_generator.deinit();
    const inputs = try buildInputs(&old_generator, &original);
    var pools = try capture(&old_generator, &original);
    defer pools.deinit(a);
    var current = try Fixture.init(true);
    defer current.deinit();
    var generator = try Generator.init(&current);
    defer generator.deinit();
    {
        var absent = try importer.Importer.init(a, &pools, current.units, null, 2);
        defer absent.deinit();
        try std.testing.expect(!absent.enabled);
        try std.testing.expectEqual(@as(?u32, null), try absent.importLayout(&generator, 3));
        var empty_identity = pools.identity.?;
        empty_identity.symbols = &.{};
        var borrowed = pools;
        borrowed.identity = empty_identity;
        var malformed = try importer.Importer.init(a, &borrowed, current.units, current.names.view(), 2);
        defer malformed.deinit();
        try std.testing.expect(!malformed.enabled);
        try std.testing.expectEqual(@as(?artifacts.Request, null), try malformed.importRequest(&generator, inputs.request));
    }
    {
        var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 2);
        defer imports.deinit();
        var fresh = inputs.request;
        fresh.closure.unit = 3;
        try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&generator, fresh));
        const node = current.units[1].bodies[1].root;
        const changed_captures = try a.dupe(artifacts.CapturedTemplate, pools.captures);
        defer a.free(changed_captures);
        changed_captures[inputs.result_template - 1].unit = 3;
        changed_captures[inputs.result_template - 1].node = node;
        var changed = pools;
        changed.captures = changed_captures;
        var changed_imports = try importer.Importer.init(a, &changed, current.units, current.names.view(), 2);
        defer changed_imports.deinit();
        const prior = (try imports.importResultTemplate(&generator, inputs.result_template)).?;
        const retained = generator.template_catalog.items[prior - 1];
        try std.testing.expectEqual(@as(?u32, null), try changed_imports.importResultTemplate(&generator, inputs.result_template));
        try std.testing.expectEqual(retained, generator.template_catalog.items[prior - 1]);
    }
    {
        var fields = generator.evaluator.field_locations.iterator();
        const entry = fields.next().?;
        const saved = entry.value_ptr.*;
        entry.value_ptr.field = (saved.field + 1) % saved.len;
        defer entry.value_ptr.* = saved;
        var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 2);
        defer imports.deinit();
        try std.testing.expect(imports.stable[0] and imports.stable[1]);
        try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&generator, inputs.request));
        try std.testing.expectEqual(@as(?usize, null), imports.generator_owner);
    }
    {
        const old_stamp = artifacts.stamp(current.units[1]);
        var changed = false;
        for (current.units[1].nodes) |*node| if (node.tag == .constant and node.a == @as(u32, @bitCast(@as(f32, 1.0)))) {
            node.a = @bitCast(@as(f32, 2.0));
            changed = true;
            break;
        };
        try std.testing.expect(changed);
        try std.testing.expect(!std.mem.eql(u8, &old_stamp, &artifacts.stamp(current.units[1])));
        var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 2);
        defer imports.deinit();
        try std.testing.expect(!imports.stable[0]);
        try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&generator, inputs.request));
    }
}
