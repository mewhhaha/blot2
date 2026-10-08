const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const metadata = @import("code_artifacts.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var syntax = try parser.parse(a, source, lexed.tokens.items, &names);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &syntax, &names, &checked);
    errdefer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    result.unit = 1;
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

const collection_source =
    \\const frozen = @list.generate 513 (fn index => index)
    \\entry const build = fn (count: U32) => do:
    \\  let xs = [value | value <- @array.generate count (fn i => i)]
    \\  xs := [(@array.from_list frozen)[512], ...self, 42]
    \\  let array = @array.from_list xs
    \\  array[0] := 40
    \\  return array
;

test "local refinement and closed source sharing preserve exact Wasm staging and effects across fresh and retained builds" {
    var hits: usize = 0;
    for ([_][]const u8{ partition_source, provider_source, collection_source, @embedFile("request-fixtures/template-wrapped-reuse.blot"), @embedFile("request-fixtures/f32-foreign-nested.blot") }) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        var fresh = try backend.compileWithOptions(a, &.{module}, 1, .{});
        defer fresh.deinit(a);
        var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
        defer retained.deinit(a);
        try std.testing.expect(fresh.diagnostic == null and retained.diagnostic == null);
        try std.testing.expectEqualSlices(u8, fresh.bytes, retained.bytes);
        try std.testing.expectEqual(fresh.constant_steps, retained.constant_steps);
        try std.testing.expectEqual(fresh.code_instances, retained.code_instances);
        try std.testing.expect(fresh.capture == null and retained.capture != null);
        hits += fresh.refinements.local_hits + retained.refinements.local_hits;
    }
    try std.testing.expect(hits > 0);
}

const partition_source =
    \\const plus = fn (value: U32) => @u32.add value 1
    \\const twice = fn (value: U32) => @u32.add (plus value) (plus value)
    \\const recurse = fn (value: U32) -> U32 => if @u32.eq value 0 then twice value else recurse (@u32.sub value 1)
    \\entry const folded: U32 where { type_rep U32 } = @u32.add (twice 20) (recurse 3)
    \\entry const answer = fn (value: U32) => @u32.add (twice value) (recurse value)
;
fn partitionScenario(allocator: std.mem.Allocator, module: *const core.Module, expected: []const u8) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .retain_artifacts = true, .policy = .{ .split_closed_calls = true } });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.optimization.split_accepted > 0);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}
test "closed call partitions preserve recursive components staged evaluation effects and allocation failure" {
    for ([_][]const u8{ partition_source, provider_source, collection_source, @embedFile("request-fixtures/template-wrapped-reuse.blot"), @embedFile("request-fixtures/f32-foreign-nested.blot") }, 0..) |source, index| {
        var module = try lower(source);
        defer module.deinit(a);
        var reference = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
        defer reference.deinit(a);
        var split = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .policy = .{ .split_closed_calls = true } });
        defer split.deinit(a);
        try std.testing.expectEqualDeep(reference.diagnostic, split.diagnostic);
        try std.testing.expectEqualSlices(u8, reference.bytes, split.bytes);
        try std.testing.expectEqual(reference.constant_steps, split.constant_steps);
        try std.testing.expectEqual(reference.code_instances, split.code_instances);
        if (index == 0) {
            try std.testing.expect(split.optimization.split_accepted > 0);
            try @import("allocation_failures.zig").checkAllAllocationFailures(a, partitionScenario, .{ &module, reference.bytes });
        }
    }
}

test "Gate A backend reconstructs solved captures providers State Demand Foreign and result templates after all mutable owners die" {
    for ([_][]const u8{ provider_source, collection_source, @embedFile("request-fixtures/f32-foreign-nested.blot"), @embedFile("request-fixtures/suspended.blot"), @embedFile("request-fixtures/nested-owner.blot"), @embedFile("request-fixtures/template-wrapped-reuse.blot") }) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        const before = metadata.stamp(module);
        var reference = try backend.compileWithOptions(a, &.{module}, 1, .{});
        defer reference.deinit(a);
        var reconstructed = try backend.compileWithOptions(a, &.{module}, 1, .{ .artifact_replay = true });
        defer reconstructed.deinit(a);
        try std.testing.expect(reference.diagnostic == null and reconstructed.diagnostic == null);
        try std.testing.expectEqualSlices(u8, reference.bytes, reconstructed.bytes);
        try std.testing.expectEqual(reference.constant_steps, reconstructed.constant_steps);
        try std.testing.expectEqual(reference.code_instances, reconstructed.code_instances);
        const summary = reconstructed.artifacts.?;
        try std.testing.expectEqual(reference.emitted_functions, summary.functions);
        try std.testing.expectEqual(reference.code_instances + reference.callable_wrappers, summary.jobs);
        try std.testing.expectEqual(@as(usize, 1), summary.pinned_modules);
        try std.testing.expectEqualSlices(u8, &before, &metadata.stamp(module));
    }
}

test "artifact replay preserves codegen tiers and physical sharing without merging semantic jobs" {
    var module = try lower(
        \\const left = fn (value: U32) => @u32.add value 7
        \\const right = fn (value: U32) => @u32.add value 7
        \\entry const answer = fn (value: U32) => @u32.add (left value) (right value)
    );
    defer module.deinit(a);
    const Tier = @import("compilation_tier.zig").Tier;
    for ([_]Tier{ .optimized, .development }) |tier| for ([_]bool{ false, true }) |shared| {
        const policy: @import("execution_policy.zig").Policy = .{ .codegen_tier = tier, .share_machine_code = shared, .codegen_workers = 4 };
        var fresh = try backend.compileWithOptions(a, &.{module}, 1, .{ .io = std.testing.io, .policy = policy });
        defer fresh.deinit(a);
        var replayed = try backend.compileWithOptions(a, &.{module}, 1, .{ .io = std.testing.io, .policy = policy, .artifact_replay = true });
        defer replayed.deinit(a);
        try std.testing.expect(fresh.diagnostic == null and replayed.diagnostic == null);
        try std.testing.expectEqualSlices(u8, fresh.bytes, replayed.bytes);
        try std.testing.expectEqual(fresh.constant_steps, replayed.constant_steps);
        try std.testing.expectEqual(fresh.code_instances, replayed.code_instances);
        try std.testing.expectEqual(tier, replayed.runtime_optimization.tier);
        try std.testing.expectEqual(replayed.emitted_functions + replayed.runtime_optimization.shared, replayed.artifacts.?.functions);
    };
}

fn allocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .artifact_replay = true });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.artifacts != null);
}
test "Gate A complete job capture publication and reconstruction release each failed allocation without mutating pinned Core" {
    var module = try lower("const identity = fn value => value\nentry const answer = fn () => identity 42\n");
    defer module.deinit(a);
    const before = metadata.stamp(module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{&module});
    try std.testing.expectEqualSlices(u8, &before, &metadata.stamp(module));
}

test "retained artifact capture completes runtime storage only after its initializer is emitted" {
    var module = try lower("entry let cell: U32 = 41\nentry const answer = fn () => @u32.add cell 1\n");
    defer module.deinit(a);
    var fresh = try backend.compileWithOptions(a, &.{module}, 1, .{});
    defer fresh.deinit(a);
    var recorded = try backend.compileWithOptions(a, &.{module}, 1, .{ .artifact_replay = true, .retain_artifacts = true });
    defer recorded.deinit(a);
    try std.testing.expect(fresh.diagnostic == null and recorded.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fresh.bytes, recorded.bytes);
    const capture = &recorded.capture.?;
    const pools = &capture.metadata.pools.?;
    try std.testing.expectEqual(@as(usize, 1), pools.runtime_globals.len);
    const global = pools.runtime_globals[0];
    try std.testing.expect(!global.active);
    try std.testing.expect(global.global < capture.metadata.global_jobs.items.len);
    const owner = capture.metadata.global_jobs.items[global.global];
    try std.testing.expect(owner != 0 and owner <= capture.metadata.jobs.items.len);
    const job = capture.metadata.jobs.items[owner - 1];
    try std.testing.expect(job.state == .complete);
    try std.testing.expectEqual(global.global, job.global.?);
    var reconstructed = try capture.emission.materialize(a);
    defer reconstructed.deinit();
    const bytes = try reconstructed.assemble();
    defer a.free(bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, bytes);
}

test "movable retained capture owns complete bodies after compiler and result destruction" {
    var module = try lower(provider_source);
    defer module.deinit(a);
    const units = [_]core.Module{module};
    var compiled = try backend.compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    errdefer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    const expected = try a.dupe(u8, compiled.bytes);
    defer a.free(expected);
    var moved = compiled.capture.?;
    compiled.capture = null;
    compiled.deinit(a);
    defer moved.deinit();
    try std.testing.expect(moved.emission.sealed);
    try std.testing.expect(moved.emission.owner == null and moved.emission.clock == null);
    var reconstructed = try moved.emission.materialize(a);
    defer reconstructed.deinit();
    const actual = try reconstructed.assemble();
    defer a.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
    try std.testing.expect(moved.metadata.pools.?.modules[0].module == &units[0]);
}
