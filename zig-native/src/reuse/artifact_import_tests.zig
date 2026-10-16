const std = @import("std");
const importer = @import("artifact_import.zig");
const artifacts = @import("code_artifacts.zig");
const core = @import("../check/core.zig");
const eval = @import("../eval/core_eval.zig");
const layout = @import("../backend/layout.zig");
const substitutions = @import("substitution_keys.zig");
const runtime_identity = @import("../backend/runtime_identity.zig");
const runtime_operations = @import("../backend/runtime_operations.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
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
    representations: @import("../backend/backend_representations.zig").State,
    planning: @import("../backend/backend_plan.zig").State,
    allocator: Allocator,
    persistent_outputs: bool = false,
    evaluator: eval.Session,
    fn init(fixture: *const Fixture) !Generator {
        return initAt(a, fixture);
    }
    fn initAt(allocator: Allocator, fixture: *const Fixture) !Generator {
        var evaluator = try eval.Session.init(allocator, fixture.units);
        errdefer evaluator.deinit();
        return .{ .allocator = allocator, .evaluator = evaluator, .representations = .fromStore(allocator, try layout.Store.init(allocator)), .planning = .{ .runtime_operations = runtime_operations.Store.initProject(allocator, fixture.names.view()) } };
    }
    fn deinit(self: *Generator) void {
        self.planning.deinit(self.allocator);
        self.representations.deinit(self.allocator);
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
    const physical = try g.representations.store.intern(.record, 0, 0, &.{ fixture.right, 4, fixture.left, 3 });
    const semantic = try g.evaluator.storage.evidence.intern(.record, 0, 0, &.{ fixture.left, 3, fixture.right, 4 });
    const operation = try g.representations.store.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{physical});
    const latent = try g.representations.store.effects.internRow(&.{ operation, operation });
    const callback = try g.representations.store.internWithEffects(.function, 3, 4, latent, &.{});
    const unknown_callback = try g.representations.store.internWithEffects(.function, 3, 4, layout.unknown_row, &.{});
    const first_state = try g.representations.store.intern(.nominal, 1, nominalDecl(&fixture.units[0]), &.{physical});
    const second_state = try g.representations.store.intern(.nominal, 2, nominalDecl(&fixture.units[1]), &.{physical});
    const first_read = try g.representations.store.intern(.nominal, std.math.maxInt(u32), 1, &.{first_state});
    const first_write = try g.representations.store.intern(.nominal, std.math.maxInt(u32), 2, &.{first_state});
    const state_provider = try g.representations.store.internStateProvider(first_read, first_write, first_state);
    const captures = try g.representations.store.intern(.product, 0, 0, &.{ state_provider, callback });
    const owner = &fixture.units[0];
    const parameter = owner.bodyParameters(&owner.bodies[1])[0].binding;
    const variable: u32 = owner.bindings[parameter].ty;
    const mappings = try g.evaluator.storage.evidence.intern(.record, 0, 0, &.{ variable, semantic });
    const semantic_op = try g.evaluator.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(owner) }, &.{semantic});
    const semantic_row = try g.evaluator.storage.evidence.effects.internRow(&.{semantic_op});
    const runtime_operation = try g.planning.runtime_operations.intern(g.evaluator.storage.evidence.view(), semantic_op);
    const rows = if (owner.types.effects.variable_count != 0) try g.representations.row_keys.intern(&.{.{ .variable = 0, .value = semantic_row }}) else 0;
    const inner: artifacts.CapturedTemplate = .{ .unit = 2, .node = fixture.units[1].bodies[1].root, .captures = captures, .templates = 0, .has_environment = true };
    try g.planning.template_catalog.append(a, inner);
    try g.planning.template_instances.put(a, inner, 1);
    const templates = try g.representations.template_keys.intern(&.{.{ .variable = parameter, .value = 1 }});
    const outer: artifacts.CapturedTemplate = .{ .unit = 1, .node = owner.bodies[1].root, .captures = captures, .templates = templates, .has_environment = true, .evidence = mappings, .rows = rows };
    try g.planning.template_catalog.append(a, outer);
    try g.planning.template_instances.put(a, outer, 2);
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
    const layouts = try a.dupe(layout.Node, g.representations.store.nodes.items);
    errdefer a.free(layouts);
    const extra = try a.dupe(u32, g.representations.store.extra.items);
    errdefer a.free(extra);
    var effects = try g.representations.store.effects.copyOwned(a);
    errdefer effects.deinit(a);
    var evaluator = try g.evaluator.copySnapshot(a);
    errdefer evaluator.deinit(a);
    const rows = try copySubstitutions(&g.representations.row_keys);
    errdefer {
        a.free(rows.entries);
        a.free(rows.spans);
    }
    const templates = try copySubstitutions(&g.representations.template_keys);
    errdefer {
        a.free(templates.entries);
        a.free(templates.spans);
    }
    const captures = try a.dupe(artifacts.CapturedTemplate, g.planning.template_catalog.items);
    errdefer a.free(captures);
    const fields = try a.alloc(artifacts.FieldLocation, g.evaluator.field_locations.count());
    errdefer a.free(fields);
    var locations = g.evaluator.field_locations.iterator();
    var i: usize = 0;
    while (locations.next()) |entry| : (i += 1) fields[i] = .{ .family = entry.key_ptr.family, .tag = entry.key_ptr.tag, .name = entry.key_ptr.name, .field = entry.value_ptr.field, .len = entry.value_ptr.len };
    var names = try copyNames(fixture.names.view());
    errdefer names.deinit(a);
    const operations = try a.alloc(artifacts.Operation, g.planning.runtime_operations.entries.items.len);
    var operation_count: usize = 0;
    errdefer {
        for (operations[0..operation_count]) |operation| a.free(operation.key);
        a.free(operations);
    }
    for (g.planning.runtime_operations.entries.items, operations) |source, *destination| {
        destination.* = .{ .key = try a.dupe(u8, source.key), .foreign = source.foreign, .runtime = source.runtime };
        operation_count += 1;
    }
    return .{
        .project_identity = true,
        .identity = names,
        .modules = modules,
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
        try std.testing.expectEqual(layout.Tag.function, g.representations.store.node(prior).tag);
        try std.testing.expectEqual(@as(u32, 3), g.representations.store.node(prior).a);
        try std.testing.expectEqual(@as(u32, 3), g.representations.store.node(prior).b);
        try std.testing.expectEqual(old_stamp, artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra, old.templates.entries, old.captures }));
        return err;
    };
    _ = attempt;
    try std.testing.expectEqual(layout.Tag.function, g.representations.store.node(prior).tag);
    try std.testing.expectEqual(old_stamp, artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra, old.templates.entries, old.captures }));
}
fn performImports(imports: *importer.Importer, inputs: Inputs, fixture: *const Fixture, g: *Generator) !void {
    try std.testing.expect(imports.stable[0] and imports.stable[1]);
    try std.testing.expect(!imports.stable[2]);
    const physical = try required("physical", try imports.importLayout(g, inputs.physical));
    try std.testing.expectEqualSlices(u32, &.{ fixture.right, 4, fixture.left, 3 }, g.representations.store.children(physical));
    const semantic = try required("semantic", try imports.importEvidence(g, inputs.semantic));
    // Semantic ordering follows the CURRENT symbol namespace, unlike physical slots.
    try std.testing.expectEqualSlices(u32, &.{ fixture.left, 3, fixture.right, 4 }, g.evaluator.storage.evidence.children(semantic));
    const first = try required("first_state", try imports.importLayout(g, inputs.first_state));
    const second = try required("second_state", try imports.importLayout(g, inputs.second_state));
    try std.testing.expect(first != second);
    try std.testing.expectEqual(@as(u32, 2), g.representations.store.node(first).a);
    try std.testing.expectEqual(@as(u32, 1), g.representations.store.node(second).a);
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
    const outer = g.planning.template_catalog.items[result - 1];
    try std.testing.expectEqual(@as(u32, 2), outer.unit);
    const nested = g.representations.template_keys.get(outer.templates)[0].value;
    try std.testing.expectEqual(@as(u32, 1), g.planning.template_catalog.items[nested - 1].unit);
    try std.testing.expect(outer.has_environment and g.planning.template_catalog.items[nested - 1].has_environment);
    const callback = g.representations.store.node(request.closure.ty);
    const labels = g.representations.store.effects.view().rowLabels(callback.c);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(@as(u32, 2), g.representations.store.effects.view().operation(labels[0]).identity.unit);
    const operation_request: artifacts.Request = .{ .operation = .{ .operation = inputs.operation, .ty = inputs.callback } };
    try std.testing.expectEqual(@as(usize, 0), g.planning.runtime_operations.entries.items.len);
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(g, operation_request));
    try std.testing.expectEqual(@as(usize, 0), g.planning.runtime_operations.entries.items.len);
    const foreign = try g.evaluator.storage.evidence.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    _ = try g.planning.runtime_operations.intern(g.evaluator.storage.evidence.view(), foreign);
    const actual_operation = try g.evaluator.storage.evidence.effects.internOperation(.{ .unit = 2, .decl = effectDecl(imports.old.modules[0].module) }, &.{semantic});
    const runtime_operation = try g.planning.runtime_operations.intern(g.evaluator.storage.evidence.view(), actual_operation);
    try std.testing.expect(runtime_operation != inputs.operation);
    const count = g.planning.runtime_operations.entries.items.len;
    const matched = (try imports.importRequest(g, operation_request)).?;
    try std.testing.expectEqual(runtime_operation, matched.operation.operation);
    try std.testing.expectEqual(count, g.planning.runtime_operations.entries.items.len);
    try std.testing.expect(try imports.matches(g, operation_request, matched));
    try std.testing.expectEqual(count, g.planning.runtime_operations.entries.items.len);
    const unknown = try required("unknown_row", try imports.importLayout(g, inputs.unknown_callback));
    try std.testing.expectEqual(layout.unknown_row, g.representations.store.node(unknown).c);
    try std.testing.expect(unknown != request.closure.ty);
    var unknown_request = inputs.request;
    unknown_request.closure.ty = inputs.unknown_callback;
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(g, unknown_request));
    const closed = try g.representations.store.intern(.function, 3, 4, &.{});
    try std.testing.expectEqual(@as(u32, 0), g.representations.store.node(closed).c);
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
    const prior = try current.representations.store.intern(.function, 3, 3, &.{});
    _ = try current.evaluator.storage.evidence.intern(.array, 4, 0, &.{});
    const junk: artifacts.CapturedTemplate = .{ .unit = 1, .node = current_fixture.units[0].bodies[1].root, .captures = try current.representations.store.intern(.product, 0, 0, &.{}), .templates = 0, .has_environment = false };
    try current.planning.template_catalog.append(a, junk);
    try current.planning.template_instances.put(a, junk, 1);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, oomImports, .{ &pools, inputs, &fixture });
}

test "artifact operation matching qualifies phantom owners without publishing runtime symbols" {
    var fixture = try Fixture.init(false);
    defer fixture.deinit();
    var producer = try Generator.init(&fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &fixture);
    producer.planning.runtime_operations.deinit();
    producer.planning.runtime_operations = runtime_operations.Store.initProject(a, fixture.names.view());
    const fresh_argument = try producer.evaluator.storage.evidence.intern(.nominal, 3, 1, &.{3});
    const stable_label = try producer.evaluator.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{3});
    const fresh_label = try producer.evaluator.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = effectDecl(&fixture.units[0]) }, &.{fresh_argument});
    const stable_id = try producer.planning.runtime_operations.intern(producer.evaluator.storage.evidence.view(), stable_label);
    const fresh_id = try producer.planning.runtime_operations.intern(producer.evaluator.storage.evidence.view(), fresh_label);
    var pools = try capture(&producer, &fixture);
    defer pools.deinit(a);
    var consumer = try Generator.init(&fixture);
    defer consumer.deinit();
    consumer.planning.runtime_operations.deinit();
    consumer.planning.runtime_operations = runtime_operations.Store.initProject(a, fixture.names.view());
    for (pools.operations) |operation| _ = try consumer.planning.runtime_operations.internSymbol(operation.key, operation.foreign);
    const before = artifacts.stamp(consumer.planning.runtime_operations.entries.items);
    var imports = try importer.Importer.init(a, &pools, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    const stable = (try imports.importRequest(&consumer, .{ .operation = .{ .operation = stable_id, .ty = inputs.callback } })).?;
    try std.testing.expectEqual(stable_id, stable.operation.operation);
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&consumer, .{ .operation = .{ .operation = fresh_id, .ty = inputs.callback } }));
    try std.testing.expectEqual(before, artifacts.stamp(consumer.planning.runtime_operations.entries.items));
}
fn oomImports(allocator: Allocator, pools: *const artifacts.Pools, inputs: Inputs, fixture: *const Fixture) !void {
    var current = try Generator.initAt(allocator, fixture);
    defer current.deinit();
    const prior = try current.representations.store.intern(.function, 3, 3, &.{});
    const old_stamp = artifacts.stamp(.{ pools.layouts.nodes, pools.layouts.extra, pools.captures, pools.templates.entries });
    assertImports(allocator, pools, inputs, fixture, &current, prior) catch |err| {
        try std.testing.expectEqual(layout.Tag.function, current.representations.store.node(prior).tag);
        try std.testing.expectEqual(@as(u32, 3), current.representations.store.node(prior).b);
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
        const retained = generator.planning.template_catalog.items[prior - 1];
        try std.testing.expectEqual(@as(?u32, null), try changed_imports.importResultTemplate(&generator, inputs.result_template));
        try std.testing.expectEqual(retained, generator.planning.template_catalog.items[prior - 1]);
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

test "artifact demand cell descriptors reject forged ordinary callable source without mutating retained facts" {
    var fixture = try Fixture.init(false);
    defer fixture.deinit();
    var producer = try Generator.init(&fixture);
    defer producer.deinit();
    _ = try buildInputs(&producer, &fixture);
    var pools = try capture(&producer, &fixture);
    defer pools.deinit(a);
    pools.captures[0].demand_cell = true;
    try std.testing.expect(fixture.units[1].node(pools.captures[0].node).tag != .suspend_);
    const before = artifacts.stamp(pools.captures);
    var consumer = try Generator.init(&fixture);
    defer consumer.deinit();
    var imports = try importer.Importer.init(a, &pools, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    try std.testing.expectEqual(@as(?u32, null), try imports.importResultTemplate(&consumer, 1));
    try std.testing.expectEqual(before, artifacts.stamp(pools.captures));
    try std.testing.expectEqual(@as(usize, 0), consumer.planning.template_catalog.items.len);
}

fn callableEndpointImport(allocator: Allocator, old: *const artifacts.Pools, inputs: Inputs, fixture: *const Fixture) !void {
    var current = try Generator.initAt(allocator, fixture);
    defer current.deinit();
    // Occupy the old numeric IDs with different current layouts. The endpoint
    // must relocate its graph and producer identities, never reuse that index.
    for (1..65) |width| {
        const fields: [64]u32 = @splat(3);
        _ = try current.representations.store.intern(.product, 0, 0, fields[0..width]);
    }
    var imports = try importer.Importer.init(allocator, old, fixture.units, fixture.names.view(), 2);
    defer imports.deinit();
    const stamp = artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra });
    try std.testing.expectEqual(@as(?u32, null), try imports.importCallableLayout(&current, inputs.callback, inputs.unknown_callback));
    try std.testing.expectEqual(@as(?u32, null), try imports.importCallableLayout(&current, 3, null));
    try std.testing.expectEqual(@as(?u32, null), try imports.importCallableLayout(&current, std.math.maxInt(u32), null));
    try std.testing.expectEqual(@as(?usize, null), imports.generator_owner);
    const actual = (try imports.importCallableLayout(&current, inputs.callback, inputs.callback)).?;
    try std.testing.expect(actual != inputs.callback);
    const callable = current.representations.store.node(actual);
    try std.testing.expectEqual(layout.Tag.function, callable.tag);
    try std.testing.expectEqual(@as(u32, 3), callable.a);
    try std.testing.expectEqual(@as(u32, 4), callable.b);
    const operations_ = current.representations.store.effects.view().rowLabels(callable.c);
    try std.testing.expectEqual(@as(usize, 2), operations_.len);
    try std.testing.expectEqual(operations_[0], operations_[1]);
    try std.testing.expectEqual(@as(u32, 2), current.representations.store.effects.view().operation(operations_[0]).identity.unit);
    try std.testing.expectEqual(stamp, artifacts.stamp(.{ old.layouts.nodes, old.layouts.extra }));
}
test "callable endpoint layouts relocate owned type graphs and reject mismatches scalars and edited producers through OOM" {
    var producer_fixture = try Fixture.init(false);
    defer producer_fixture.deinit();
    var producer = try Generator.init(&producer_fixture);
    defer producer.deinit();
    const inputs = try buildInputs(&producer, &producer_fixture);
    var pools = try capture(&producer, &producer_fixture);
    defer pools.deinit(a);
    var consumer_fixture = try Fixture.init(true);
    defer consumer_fixture.deinit();
    try callableEndpointImport(a, &pools, inputs, &consumer_fixture);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callableEndpointImport, .{ &pools, inputs, &consumer_fixture });
    var changed = false;
    for (consumer_fixture.units[1].nodes) |*node| if (node.tag == .constant and node.a == @as(u32, @bitCast(@as(f32, 1.0)))) {
        node.a = @bitCast(@as(f32, 2.0));
        changed = true;
        break;
    };
    try std.testing.expect(changed);
    var consumer = try Generator.init(&consumer_fixture);
    defer consumer.deinit();
    var imports = try importer.Importer.init(a, &pools, consumer_fixture.units, consumer_fixture.names.view(), 2);
    defer imports.deinit();
    try std.testing.expectEqual(@as(?u32, null), try imports.importCallableLayout(&consumer, inputs.callback, inputs.callback));
}

fn semanticSiteImports(allocator: Allocator, pools: *const artifacts.Pools, current: *const Fixture, site: @import("../backend/wasm.zig").Module.SemanticSite, edited: core.Id, other_root: core.Id) !void {
    var imports = try importer.Importer.init(allocator, pools, current.units, current.names.view(), 0);
    defer imports.deinit();
    var generator = try Generator.initAt(allocator, current);
    defer generator.deinit();
    try std.testing.expect((try imports.importSemanticSite(&generator, site)) != null);
    try std.testing.expect((try imports.importSemanticSite(&generator, site)) != null);
    try std.testing.expectEqual(@as(usize, 1), imports.expression_nodes.count());
    for (0..7) |mutation| {
        var wrong = site;
        switch (mutation) {
            0 => wrong.node = 0,
            1 => wrong.root = 0,
            2 => wrong.node = @intCast(current.units[0].nodes.len),
            3 => wrong.node = edited,
            4 => wrong.root = other_root,
            5 => wrong.mappings = @intCast(pools.evaluator.evidence.nodes.len),
            6 => wrong.rows = @intCast(pools.rows.spans.len + 1),
            else => unreachable,
        }
        try std.testing.expect((try imports.importSemanticSite(&generator, wrong)) == null);
    }
    try std.testing.expect((try imports.importSemanticSite(&generator, site)) != null);
}

test "semantic sites in unchanged declaration owners survive an unrelated function literal edit" {
    var original = try Fixture.init(false);
    defer original.deinit();
    var old_generator = try Generator.init(&original);
    defer old_generator.deinit();
    _ = try buildInputs(&old_generator, &original);
    const mappings = try old_generator.evaluator.storage.evidence.intern(.record, 0, 0, &.{});
    var pools = try capture(&old_generator, &original);
    defer pools.deinit(a);
    var current = try Fixture.init(false);
    defer current.deinit();
    var edited: core.Id = 0;
    var i = current.units[0].nodes.len;
    while (i > 1) {
        i -= 1;
        const node = &current.units[0].nodes[i];
        if (node.tag == .constant and node.ty == @import("../check/types.zig").f32_type) {
            node.a ^= 1;
            edited = @intCast(i);
            break;
        }
    }
    try std.testing.expect(edited != 0);
    var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 0);
    defer imports.deinit();
    try std.testing.expect(imports.code_gate.?.semantic.enabled);
    try std.testing.expect(!imports.code_gate.?.semantic.structural_units[0]);
    const source = &original.units[0];
    var body: core.Body = undefined;
    for (source.bindings, 0..) |binding, id| {
        if (binding.kind != .global or binding.body_id == 0) continue;
        const candidate = source.body(@intCast(id)).?;
        if (candidate.parameters.len != 1 or source.node(candidate.root).tag != .block) continue;
        body = candidate.*;
        break;
    } else return error.TestExpectedFactory;
    const site: @import("../backend/wasm.zig").Module.SemanticSite = .{ .function = 0, .place = 0, .unit = 1, .node = body.root, .root = body.root, .mappings = mappings, .rows = 0, .kind = .call };
    var other_root: core.Id = 0;
    for (source.bodies[1..]) |candidate| {
        if (candidate.root != body.root) {
            other_root = candidate.root;
            break;
        }
    }
    try std.testing.expect(other_root != 0);
    try semanticSiteImports(a, &pools, &current, site, edited, other_root);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, semanticSiteImports, .{ &pools, &current, site, edited, other_root });
}

test "artifact import rejects forged scalar environment modes on owning capture shapes" {
    var original = try Fixture.init(false);
    defer original.deinit();
    var old = try Generator.init(&original);
    defer old.deinit();
    const inputs = try buildInputs(&old, &original);
    var pools = try capture(&old, &original);
    defer pools.deinit(a);
    var current = try Fixture.init(true);
    defer current.deinit();
    var generator = try Generator.init(&current);
    defer generator.deinit();
    var imports = try importer.Importer.init(a, &pools, current.units, current.names.view(), 2);
    defer imports.deinit();
    var forged = inputs.request;
    forged.closure.scalar_environment = true;
    try std.testing.expectEqual(@as(?artifacts.Request, null), try imports.importRequest(&generator, forged));
    const captures = try a.dupe(artifacts.CapturedTemplate, pools.captures);
    defer a.free(captures);
    captures[inputs.result_template - 1].scalar_environment = true;
    var changed = pools;
    changed.captures = captures;
    var altered = try importer.Importer.init(a, &changed, current.units, current.names.view(), 2);
    defer altered.deinit();
    try std.testing.expectEqual(@as(?u32, null), try altered.importResultTemplate(&generator, inputs.result_template));
}
