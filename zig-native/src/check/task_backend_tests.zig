const std = @import("std");
const core = @import("core.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;
fn lower(source: []const u8) !core.Module {
    return lowerUnit(source, 1);
}
fn lowerUnit(source: []const u8, unit: u32) !core.Module {
    var tokens = try @import("../parse/lexer.zig").lex(a, source);
    defer tokens.deinit(a);
    var pool: @import("../parse/symbols.zig").Pool = .{};
    defer pool.deinit(a);
    var syntax = try @import("../parse/parser.zig").parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try @import("check.zig").checkModule(a, &syntax, &pool, &.{}, &.{}, unit);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("task backend fixture {s}\n", .{@tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    return module;
}
fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8 and result.capture != null);
}
test "task scope wrapper authority requires its exact callback body" {
    var module = try lower(
        \\const scope = func body => return @task.scope body
        \\const relay = func body => return scope body
        \\entry const answer = func () => return relay (func group => return do:
        \\  let pending = @task.spawn group (func () => return 42)
        \\  break @task.join pending)
    );
    defer module.deinit(a);
    var wrappers: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .scope_task) continue;
        wrappers += 1;
        const body = module.bodies[binding.body_id];
        try std.testing.expect(@import("task_core.zig").scopeWrapper(&module, body.root));
        const before = module.nodes[body.root];
        module.nodes[body.root].c = @backingInt(@import("task_types.zig").Op.join);
        try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
        module.nodes[body.root] = before;
    }
    try std.testing.expectEqual(@as(usize, 1), wrappers);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
test "spawn helper partial calls retain actual capture ownership and reject forged contracts through OOM" {
    var module = try lower(
        \\const launch = func group => return func action => return @task.spawn group action
        \\const alias = launch
        \\entry const answer = func (owner: unique U32) => return @task.scope (func group => return do:
        \\  let here = alias group
        \\  let renamed = here
        \\  let pending = renamed (func () => return owner)
        \\  let result = |pending|
        \\  break @usage.borrow result (func loan => return @usage.read loan))
    );
    defer module.deinit(a);
    var wrappers: usize = 0;
    for (module.bindings, 0..) |binding, index| {
        if (binding.capability_flow != .spawn_task) continue;
        wrappers += 1;
        try @import("task_core.zig").spawnWrapper(&module, @intCast(index), &.{});
        const body = module.bodies[binding.body_id];
        if (!body.is_function) continue;
        const before = module.nodes[body.root];
        module.nodes[body.root].c = @backingInt(@import("task_types.zig").Op.join);
        try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
        module.nodes[body.root] = before;
    }
    try std.testing.expectEqual(@as(usize, 2), wrappers);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
test "task collect validates every result field before emission through allocation failures" {
    var module = try lower(
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let left = @task.spawn group (func () => return 20)
        \\  let right = @task.spawn group (func () => return 1.5)
        \\  let (first, second) = |(left, right)|
        \\  break @f32.add (@u32.to_f32 first) second)
    );
    defer module.deinit(a);
    var found = false;
    for (module.nodes) |node| {
        if (node.tag != .task or node.c != @backingInt(@import("task_types.zig").Op.collect)) continue;
        found = true;
        const result = module.types.node(node.ty);
        const before = module.types.extra[result.a];
        module.types.extra[result.a] = @import("types.zig").f32_type;
        try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validate(&module));
        module.types.extra[result.a] = before;
    }
    try std.testing.expect(found);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
test "generic tuple receive preserves a complete task lifetime graph" {
    var module = try lower(
        \\const await = func source => return |source|
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let first = @task.spawn group (func () => return 20)
        \\  let second = @task.spawn group (func () => return 22)
        \\  let (left, right) = await (first, second)
        \\  break @u32.add left right)
    );
    defer module.deinit(a);
    const entry = for (module.bodies) |body| {
        if (body.exported) break body.binding;
    } else return error.MissingEntry;
    var graph = try @import("capability_lifetimes.zig").analyze(a, &module, &.{&module}, .{ .binding = entry });
    defer graph.deinit(a);
    try std.testing.expect(graph.complete);
    try std.testing.expect(graph.boundaries.len != 0);
}
test "structured task backend owns replay retained helpers and every failed allocation" {
    var module = try lower(
        \\entry const answer = func (owner: unique U32) => return do:
        \\  let result = @task.scope (func group => return @task.join (@task.spawn group (func () => return owner)))
        \\  break @usage.borrow result (func loan => return @usage.read loan)
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}
test "portable task capture proof checks actual named call contracts without reference children" {
    var module = try lower(
        \\const ordinary = func (host: Unit -> U32 ! {Foreign}) => return host ()
        \\const helper = func (host: Unit -> U32 ! {Foreign}) => return ordinary host
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return 42)))
    );
    defer module.deinit(a);
    var foreign_call: core.Id = 0;
    var thunk: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .call and module.types.rowLabels(module.types.node(module.call(@intCast(id)).callee_type).c).len != 0) foreign_call = @intCast(id);
        if (node.tag == .task and node.c == @backingInt(@import("task_types.zig").Op.spawn)) thunk = module.children(@intCast(id))[1];
    }
    try std.testing.expect(foreign_call != 0 and thunk != 0);
    module.closures[module.node(thunk).a].body = foreign_call;
    try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}

test "portable task capture authority encloses the destination rather than only the spawn site" {
    const tasks = @import("task_types.zig");
    var module = try lower(
        \\entry const answer = func () => return @task.scope (func outer => return do:
        \\  let unused = @task.spawn outer (func () => return 1)
        \\  break @task.scope (func inner => return @task.join (@task.spawn inner (func () => return @task.join (@task.spawn inner (func () => return 42))))))
    );
    defer module.deinit(a);
    var outer: core.Id = 0;
    var selected: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .task or node.c != @backingInt(tasks.Op.spawn)) continue;
        const operands = module.children(@intCast(id));
        const body = module.node(module.closure(operands[1]).body);
        if (body.tag == .constant and body.a == 1) outer = operands[0];
        if (body.tag == .task and body.c == @backingInt(tasks.Op.join)) selected = @intCast(id);
    }
    try std.testing.expect(outer != 0 and selected != 0);
    var remaining: usize = 65_536;
    try @import("task_core.zig").validateOperation(&module, selected, &remaining);
    // Keep the selected thunk arrow and handle shape intact. Only retarget the
    // destination group, so its captured inner group is now too short lived.
    module.extra[module.nodes[selected].a] = outer;
    const nominal = module.types.node(module.types.node(module.typeOf(selected)).a);
    module.types.extra[nominal.c + 1] = module.typeOf(outer);
    remaining = 65_536;
    try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validateOperation(&module, selected, &remaining));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}

test "portable task partitions reject overlapping ranges and a forged moved owner version" {
    const tasks = @import("task_types.zig");
    const regions = @import("task_regions.zig");
    var module = try lower(
        \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 2), (2, 4)) (func views => return do:
        \\  let (left, right) = views
        \\  break @task.scope (func group => return @task.join (@task.spawn group (func () => return @task.read left 0))))
    );
    defer module.deinit(a);
    var split: core.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .task and node.c == @backingInt(tasks.Op.split)) {
        split = @intCast(id);
    };
    try std.testing.expect(split != 0);
    _ = try regions.partition(&module, split);
    const operands = module.children(split);
    const range = module.children(operands[1])[0];
    const end = module.children(range)[1];
    const previous = module.nodes[end].a;
    module.nodes[end].a = 3;
    try std.testing.expectError(error.InvalidArtifact, regions.partition(&module, split));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
    module.nodes[end].a = previous;
    _ = try regions.partition(&module, split);
    const product = module.types.node(module.closure(operands[2]).parameter.ty);
    const view = tasks.viewInfo(&module.types, module.types.list(.{ .start = product.a, .len = product.b })[0]).?;
    module.types.nodes[view.version].b +%= 1;
    try std.testing.expectError(error.InvalidArtifact, regions.partition(&module, split));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}

test "portable task selected pure arrow cannot replace an actual named Foreign declaration" {
    var module = try lower(
        \\const ordinary = func (host: Unit -> U32 ! {Foreign}) => return host ()
        \\const helper = func (host: Unit -> U32 ! {Foreign}) => return ordinary host
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return 42)))
    );
    defer module.deinit(a);
    var call: core.Id = 0;
    var thunk: core.Id = 0;
    var unit: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .call) call = @intCast(id);
        if (node.tag == .constant and node.ty == @import("types.zig").unit) unit = @intCast(id);
        if (node.tag == .task and node.c == @backingInt(@import("task_types.zig").Op.spawn)) thunk = module.children(@intCast(id))[1];
    }
    try std.testing.expect(call != 0 and thunk != 0 and unit != 0);
    const pure: @import("types.zig").Id = @intCast(module.types.nodes.len);
    var selected = module.types.node(module.types.node(module.typeOf(thunk)).a);
    selected.c = 0;
    module.types.nodes = try a.realloc(module.types.nodes, module.types.nodes.len + 1);
    module.types.nodes[pure] = selected;
    var remaining: usize = 4096;
    try std.testing.expectEqual(@as(?@import("task_types.zig").CaptureIssue, null), try @import("task_types.zig").captureIssueWithRows(&module.types, pure, false, &remaining, 0, module.types.list(module.closure(thunk).closed_rows)));
    module.calls[module.nodes[call].a].callee_type = pure;
    module.extra[module.nodes[call].b] = unit;
    module.closures[module.node(thunk).a].body = call;
    // No selected arrow or argument now mentions Foreign. The actual target's
    // declared parameter/effects and executable body must still be required.
    try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}

test "task lexical evidence cannot instantiate an ordinary universal data witness" {
    const T = @import("types.zig");
    var nodes = [_]T.Node{
        .{ .tag = .absent },                                              .{ .tag = .unit },                             .{ .tag = .boolean },
        .{ .tag = .u32 },                                                 .{ .tag = .f32 },                              .{ .tag = .never },
        .{ .tag = .bound, .a = 0, .b = 0, .c = 0 },                       .{ .tag = .function, .a = 6, .b = 6, .c = 0 }, .{ .tag = .forall, .a = 7, .b = 0, .c = 1 },
        .{ .tag = .nominal, .a = std.math.maxInt(u32), .b = 16, .c = 1 }, .{ .tag = .scoped, .a = 9, .b = 1, .c = 1 },   .{ .tag = .function, .a = 10, .b = 10, .c = 0 },
    };
    var extra = [_]T.Id{ 6, 0 };
    var rows = [_]T.Effects.Row{.{}};
    const types: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows } };
    var remaining: usize = 65_536;
    var proof: @import("package_contracts.zig").Principal = .{ .left = &types, .right = &types, .remaining = &remaining };
    const actual_group = nodes[11];
    nodes[11] = .{ .tag = .function, .a = T.u32_type, .b = T.u32_type, .c = 0 };
    try proof.instantiate(8, 11);
    nodes[11] = actual_group;
    try std.testing.expectError(error.InvalidArtifact, proof.instantiate(8, 11));
}

test "task actual call proof terminates on exact cross unit recursive declarations" {
    const source =
        \\const recur = func (value: U32) : U32 => return if @u32.eq value 0 then 42 else recur (@u32.sub value 1)
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return recur 3)))
    ;
    var left = try lowerUnit(source, 1);
    defer left.deinit(a);
    var right = try lowerUnit(source, 2);
    defer right.deinit(a);
    for (left.calls) |*call| call.target.unit = right.unit;
    for (right.calls) |*call| call.target.unit = left.unit;
    const owners = [_]*const core.Module{ &left, &right };
    try @import("frozen_core_validation.zig").validate(a, &left, .{ .units = &owners });
    try @import("frozen_core_validation.zig").validate(a, &right, .{ .units = &owners });
    var remaining: usize = 65_536;
    for (left.nodes, 0..) |node, id| if (node.tag == .task) try @import("task_core.zig").validateOperationContext(&left, &owners, @intCast(id), &remaining);
    // Recursive declarations are proved once per active owner path, rather
    // than repeatedly interpreting their unbounded runtime recursion.
    try std.testing.expect(remaining > 32_768);
}

test "task call proof reconstructs Foreign body after coordinated pure header forgery" {
    const T = @import("types.zig");
    var module = try lower(
        \\const ordinary = func () => return @resource.scope (func () => return 9) (func owner => return ()) (func loan => return @usage.read loan)
        \\const invoke = func () => return ordinary ()
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return 42)))
    );
    defer module.deinit(a);
    var call: core.Id = 0;
    var thunk: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .call) call = @intCast(id);
        if (node.tag == .task and node.c == @backingInt(@import("task_types.zig").Op.spawn)) thunk = module.children(@intCast(id))[1];
    }
    try std.testing.expect(call != 0 and thunk != 0);
    const target = module.call(call).target.binding;
    const body_id = module.bindings[target].body_id;
    var selected = module.types.node(module.call(call).callee_type);
    try std.testing.expect(selected.tag == .function and selected.a == T.unit);
    selected.c = 0;
    const pure: T.Id = @intCast(module.types.nodes.len);
    module.types.nodes = try a.realloc(module.types.nodes, module.types.nodes.len + 1);
    module.types.nodes[pure] = selected;
    module.calls[module.nodes[call].a].callee_type = pure;
    module.bindings[target].ty = pure;
    module.bindings[target].scheme.root = pure;
    module.bodies[body_id].scheme.root = pure;
    module.closures[module.node(thunk).a].body = call;
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validateBounds(&module, .{}));
    try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}

test "task collection generation reconstructs callback bodies despite pure selected claims" {
    var module = try lower(
        \\const hidden = func () => return @resource.scope (func () => return 9) (func owner => return ()) (func loan => return @usage.read loan)
        \\const ordinary = func () => return @array.generate 1 (func (index: U32) => return 42)
        \\entry const answer = func () : Array U32 => return @task.scope (func group => return @task.join (@task.spawn group (func () => return ordinary ())))
    );
    defer module.deinit(a);
    var callback: core.Id = 0;
    var foreign_body: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .resource_scope) foreign_body = @intCast(id);
        if (node.tag == .array_op and module.arrayOperation(@intCast(id)) == .generate) callback = module.children(@intCast(id))[1];
    }
    try std.testing.expect(callback != 0 and foreign_body != 0);
    // Keep every selected/declared arrow pure, including the generator's
    // qualifier. Its actual body now performs an independently owned effect.
    module.closures[module.node(callback).a].body = foreign_body;
    try std.testing.expectError(error.InvalidArtifact, @import("task_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
}
