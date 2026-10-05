const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const code_expectation = @import("code_expectation.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

const source =
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\entry const run = fn (limit: U32) -> U32 => do:
    \\  let (state,result) = @effect.run State.get State.set #[0] (fn () => do:
    \\    let index = 0
    \\    for ever:
    \\      if @u32.eq index limit:
    \\        use values <- State.get ()
    \\        return @array.get values 0
    \\      index := @u32.add self 1
    \\      use State.set #[index])
    \\  return @u32.add (@array.get state 0) result
;

fn lower(text: []const u8) !core.Module {
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn scenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var shape = try code_expectation.Store.init(allocator);
    defer shape.deinit();
    const expected = try shape.intern(.function, types.unit, types.u32_type, &.{});
    try std.testing.expectEqual(@as(usize, 1), module.closures.len);
    var proof = try session.closureEvidencePartialFull(1, 0, shape.view(), expected, &.{}, &.{});
    defer proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .operation_value) continue;
        const metadata = module.operationValue(@intCast(id));
        const signature = module.types.node(metadata.signature);
        if (signature.a != types.unit) continue;
        const selected = try session.evidence.projectWithRows(&module.types, metadata.signature, proof.types, proof.rows);
        const result = session.evidence.node(session.evidence.node(selected).b);
        try std.testing.expectEqual(.array, result.tag);
        try std.testing.expectEqual(types.u32_type, result.a);
        try std.testing.expect(session.evidence.view().effects.rowLabels(session.evidence.node(selected).c).len != 0);
        try std.testing.expect(session.diagnostic == null);
        return;
    }
    return error.TestExpectedStateRead;
}

test "closed State operation proof resolves generic array results without evaluating the action" {
    var module = try lower(source);
    defer module.deinit(a);
    const original = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original);
    try scenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{&module});
    try std.testing.expectEqualDeep(original, module.types.nodes);
}

fn append(comptime T: type, owned: *[]T, values: []const T) !void {
    const old_len = owned.len;
    const length = std.math.add(usize, old_len, values.len) catch return error.OutOfMemory;
    owned.* = try a.realloc(owned.*, length);
    @memcpy(owned.*[old_len..], values);
}

fn ambiguousScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var shape = try code_expectation.Store.init(allocator);
    defer shape.deinit();
    const expected = try shape.intern(.function, types.unit, types.unit, &.{});
    const proof = session.closureEvidencePartialFull(1, 0, shape.view(), expected, &.{}, &.{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {
            try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code);
            try std.testing.expectEqual(@as(usize, 0), session.steps);
            return;
        },
    };
    var unexpected = proof;
    defer unexpected.deinit(allocator);
    return error.TestExpectedAmbiguousOperationRejection;
}

test "closed operation rows cannot choose between two compatible generic instances" {
    var module = try lower(
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\entry const run = fn () -> Unit => do:
        \\  let (state,result) = @effect.run State.get State.set #[0] (fn () => do:
        \\    use values <- State.get ()
        \\    return ())
        \\  return ()
    );
    defer module.deinit(a);
    // This semantic-core counterexample adds a second valid operation instance
    // without adding result evidence for the generic invocation. Row membership
    // alone must not select a result type, regardless of candidate ordering.
    var get_index: ?usize = null;
    for (module.operation_values, 0..) |operation, index| {
        const signature = module.types.node(operation.signature);
        const result = module.types.node(signature.b);
        if (signature.a == types.unit and result.tag == .variable) {
            get_index = index;
            break;
        }
    }
    const index = get_index orelse return error.TestExpectedStateRead;
    const metadata = module.operation_values[index];
    const original = module.types.node(metadata.signature);
    const old_labels = try a.dupe(types.Effects.Label, module.types.rowLabels(original.c));
    defer a.free(old_labels);
    const floating_array: types.Id = @intCast(module.types.nodes.len);
    try append(types.Node, &module.types.nodes, &.{.{ .tag = .array, .a = types.f32_type }});
    const argument_start: u32 = @intCast(module.types.extra.len);
    try append(types.Id, &module.types.extra, &.{floating_array});
    const other: types.Effects.Label = @intCast(module.types.operations.len);
    try append(types.Operation, &module.types.operations, &.{.{ .identity = metadata.identity, .arguments = .{ .start = argument_start, .len = 1 } }});
    const start: u32 = @intCast(module.types.effects.labels.len);
    try append(types.Effects.Label, &module.types.effects.labels, old_labels);
    try append(types.Effects.Label, &module.types.effects.labels, &.{other});
    const row: types.Effects.Id = @intCast(module.types.effects.rows.len);
    try append(types.Effects.Row, &module.types.effects.rows, &.{.{ .labels = .{ .start = start, .len = @intCast(old_labels.len + 1) }, .tail = .closed }});
    const signature: types.Id = @intCast(module.types.nodes.len);
    try append(types.Node, &module.types.nodes, &.{.{ .tag = .function, .a = original.a, .b = original.b, .c = row }});
    module.operation_values[index].signature = signature;
    try ambiguousScenario(a, &module);
    std.mem.reverse(types.Effects.Label, module.types.effects.labels[start..]);
    try ambiguousScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ambiguousScenario, .{&module});
}
