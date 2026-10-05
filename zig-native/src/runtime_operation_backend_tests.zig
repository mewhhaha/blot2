const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

const provider_source =
    \\effect Read: Unit -> F32
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const reader = @effect.provider Read (fn () => 1.75)
    \\const state = @effect.state (State.get F32) (State.set F32) 1.75
    \\entry const folded = do reader:
    \\  return Read ()
    \\entry const callback = fn () => do reader:
    \\  return Read ()
    \\entry const answer = fn (value: F32) => do:
    \\  let dynamic = @effect.provider Read (fn () => value)
    \\  let local = @effect.state (State.get F32) (State.set F32) value
    \\  let (next, old) = do state:
    \\    use old <- State.get F32 ()
    \\    use State.set F32 (@f32.add old value)
    \\    return old
    \\  let (_, selected) = do local:
    \\    return State.get F32 ()
    \\  let read = do dynamic:
    \\    return Read ()
    \\  return @f32.add (@f32.add next old) (@f32.add selected read)
;

fn emit(allocator: std.mem.Allocator, module: *const core.Module, noisy: bool) !void {
    var result = try backend.compileWithEvidenceNoise(allocator, &.{module.*}, 1, noisy);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

test "provider State Requests Foreign captures and suspended runtime paths ignore unrelated semantic labels after frontend teardown" {
    const sources = [_][]const u8{
        provider_source,
        @embedFile("request-fixtures/f32-foreign-nested.blot"),
        @embedFile("request-fixtures/suspended.blot"),
        @embedFile("request-fixtures/nested-owner.blot"),
        @embedFile("request-fixtures/template-wrapped-reuse.blot"),
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const types_before = try a.dupe(types.Node, module.types.nodes);
        defer a.free(types_before);
        const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
        defer a.free(labels);
        var plain = try backend.compile(a, &.{module}, 1);
        defer plain.deinit(a);
        var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
        defer noisy.deinit(a);
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), plain.diagnostic);
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), noisy.diagnostic);
        try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
        try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(types_before, module.types.nodes);
        try std.testing.expectEqualDeep(rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
    }
}

test "runtime operation instruction and constant-provider relocation release every failed allocation without changing frozen Core" {
    var module = try lower(a, provider_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
    defer a.free(labels);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, true });
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
    try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
}

test "runtime operation separation preserves opaque effect reflection as a compile-only capability" {
    const source =
        \\const read = fn () => 42
        \\const requirements = @effect.of read
        \\const count = fn effects => @effect.count effects
        \\entry const run = fn () => count requirements
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    var plain = try backend.compile(a, &.{module}, 1);
    defer plain.deinit(a);
    var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
    defer noisy.deinit(a);
    try std.testing.expectEqual(backend.Code.backend_const_only, plain.diagnostic.?.code);
    try std.testing.expectEqualDeep(plain.diagnostic, noisy.diagnostic);
    try std.testing.expectEqual(@as(usize, 0), plain.bytes.len);
    try std.testing.expectEqual(@as(usize, 0), noisy.bytes.len);
}

test "runtime operation relocation preserves supported semantic reflection membership and descriptor equality" {
    const source =
        \\type Signal a is effect = { ping: Unit -> U32 }
        \\const read = fn () => do:
        \\  use Signal.ping U32 ()
        \\  use Signal.ping U32 ()
        \\  return Signal.ping F32 ()
        \\const effects = @effect.of read
        \\entry const total = @effect.count effects
        \\entry const present = @effect.has effects (Signal.ping F32)
        \\entry const absent = @effect.has effects (Signal.ping Bool)
        \\entry const same = @effect.same (@effect.descriptor (Signal.ping U32)) (@effect.descriptor (Signal.ping U32))
        \\entry const different = @effect.same (@effect.descriptor (Signal.ping U32)) (@effect.descriptor (Signal.ping F32))
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    var plain = try backend.compile(a, &.{module}, 1);
    defer plain.deinit(a);
    var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
    defer noisy.deinit(a);
    try std.testing.expect(plain.diagnostic == null and noisy.diagnostic == null);
    try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
    try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
}

fn emitProject(allocator: std.mem.Allocator, module: *const core.Module, names: @import("runtime_identity.zig").View) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .identity = names, .evidence_noise = true });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.bytes.len > 8);
}

test "project emission requires complete actual owners and independently solves noisy evidence without changing frozen Core" {
    var module = try lower(a, provider_source);
    defer module.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var names = try @import("runtime_identity.zig").Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/provider.blot" }}, 1);
    defer names.deinit(a);
    var plain = try backend.compileWithIdentity(a, &.{module}, 1, names.view());
    defer plain.deinit(a);
    var noisy = try backend.compileWithOptions(a, &.{module}, 1, .{ .identity = names.view(), .evidence_noise = true });
    defer noisy.deinit(a);
    try std.testing.expect(plain.diagnostic == null and noisy.diagnostic == null);
    try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
    try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitProject, .{ &module, names.view() });
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
    var unowned = module;
    unowned.unit = 0;
    try std.testing.expectError(error.InvalidFunctionReference, backend.compileWithIdentity(a, &.{unowned}, 1, names.view()));
    try std.testing.expectError(error.InvalidFunctionReference, backend.compileWithIdentity(a, &.{ module, module }, 1, names.view()));
}
