const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

const source =
    \\data Cell value = #Cell value
    \\const read = fn witness => @state.get witness
    \\const answer = fn () => do:
    \\  let (_, #Cell result) = @state.run (#Cell 42) (fn () =>
    \\    read (fn ignored -> Cell U32 => @panic "witness must never be invoked"))
    \\  return result
    \\entry const unsigned = answer ()
    \\entry const floating = do:
    \\  let (_, #Cell result) = @state.run (#Cell 1.25) (fn () =>
    \\    read (fn ignored -> Cell F32 => @panic "floating witness called"))
    \\  return result
    \\entry const runtime = fn () => answer ()
;

fn lower(allocator: std.mem.Allocator) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn evaluationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for (module.bodies) |body| {
        if (!body.exported) continue;
        const value = try session.richValue(.{ .unit = 1, .binding = body.binding });
        if (body.is_function) {
            const steps = session.steps;
            const original = session.closureInfo(value);
            const proof = try session.inferClosure(value);
            try std.testing.expectEqual(steps, session.steps);
            try std.testing.expectEqualDeep(original, session.closureInfo(value));
            const signature = session.evidenceView().node(session.valueEvidence(proof));
            try std.testing.expectEqual(.function, signature.tag);
            try std.testing.expectEqual(types.unit, signature.a);
            try std.testing.expectEqual(types.u32_type, signature.b);
            try std.testing.expectEqual(@as(u32, 0), signature.c);
        } else {
            const scalar = session.valueScalar(value).?;
            if (std.mem.eql(u8, module.name(body.export_name), "unsigned")) {
                try std.testing.expectEqual(.u32, scalar.scalar);
                try std.testing.expectEqual(@as(u32, 42), scalar.bits);
            } else {
                try std.testing.expectEqual(.f32, scalar.scalar);
                try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.25))), scalar.bits);
            }
        }
    }
    try std.testing.expect(session.diagnostic == null);
}

fn emissionScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "builtin State preserves typed witnesses and immutable evidence under allocation failures" {
    var module = try lower(a);
    defer module.deinit(a);
    const original_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original_types);
    const original_operations = try a.dupe(core.OperationValue, module.operation_values);
    defer a.free(original_operations);
    for (module.operation_values) |operation| {
        try std.testing.expect(std.meta.eql(operation.identity, types.builtin_state_read) or std.meta.eql(operation.identity, types.builtin_state_write));
        if (operation.witness == 0) continue;
        try std.testing.expectEqual(core.Tag.reference, module.node(operation.witness).tag);
        try std.testing.expect(operation.witness_result != 0);
    }
    try evaluationScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evaluationScenario, .{&module});
    try emissionScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emissionScenario, .{&module});
    try std.testing.expectEqualDeep(original_types, module.types.nodes);
    try std.testing.expectEqualDeep(original_operations, module.operation_values);
}

fn frontendScenario(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator);
    defer module.deinit(allocator);
}

test "builtin State frontend releases owned operation templates and witness predicates on failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, frontendScenario, .{});
}
