const std = @import("std");
const ir = @import("runtime_ir.zig");
const w = @import("wasm.zig");
const roots = @import("../runtime/root_runtime.zig");
const production = @import("runtime_flags.zig");
const Facts = production.Facts;
const Iterator = production.Iterator;

fn expectLowered(facts: Facts, input: []const ir.Instruction, expected: []const ir.Instruction) !void {
    var iterator: Iterator = .{ .facts = facts, .instructions = input };
    for (expected) |inst| try std.testing.expectEqualDeep(inst, iterator.next().?);
    try std.testing.expect(iterator.next() == null);
}
test "immutable ownership lowering preserves result blocks and nested branch depths" {
    var module = w.Module.init(std.testing.allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    const facts: Facts = .{ .module = &module, .root_mode = roots.enabled | roots.complete, .rc_admitted = true };
    const input = [_]ir.Instruction{
        .{ .op = .block, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .i32_const, .operand = 42 },
        .{ .op = .br, .operand = 1 },
        .{ .op = .else_ },
        .{ .op = .i32_const },
        .{ .op = .end },
        .{ .op = .end },
    };
    try expectLowered(facts, &input, &.{ input[0], .{ .op = .block, .operand = input[2].operand }, input[3], input[4], input[7], input[8] });
    try expectLowered(facts, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .i32_const, .operand = roots.complete },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .block },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .else_ },
        .{ .op = .i32_const, .operand = 42 },
        .{ .op = .end },
    }, &.{ .{ .op = .block, .operand = @backingInt(ir.ValueType.i32) }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .end } });
    module.globals.items[arena.root_enabled].mutable = true;
    try std.testing.expect(!facts.complete());
    try expectLowered(facts, &input, &input);
}

test "production helper catalog contains no scanner identity" {
    inline for (@typeInfo(w.Arena).@"struct".field_names) |name| {
        try std.testing.expect(!std.mem.eql(u8, name, "mark"));
        try std.testing.expect(!std.mem.eql(u8, name, "collect"));
        try std.testing.expect(!std.mem.eql(u8, name, "root_mark"));
    }
    inline for (@typeInfo(@import("../reuse/artifact_emitter.zig").FunctionRole).@"enum".field_names) |name| {
        try std.testing.expect(!std.mem.eql(u8, name, "arena_mark"));
        try std.testing.expect(!std.mem.eql(u8, name, "arena_collect"));
        try std.testing.expect(!std.mem.eql(u8, name, "arena_root_mark"));
    }
}

test "late incomplete admission reuses symbolic guards across retained and portable replay" {
    const a = std.testing.allocator;
    const bodies = @import("optimized_bodies.zig");
    const portable = @import("../reuse/optimized_archive.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const guarded = try module.addTypedFunction(&.{}, .none, .scalar);
    try module.emitSlice(guarded, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .i32_const, .operand = roots.complete },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .i32_const },
        .{ .op = .drop },
        .{ .op = .end },
    });
    const owning = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(owning, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = arena.allocate_scalar } });
    var before: bodies.Capture = .{ .allocator = a };
    defer before.deinit();
    const initial = try module.assembleWithOptions(.{ .current = &before });
    defer a.free(initial);
    try std.testing.expect(before.roots and before.needs_roots);
    const compiler: [32]u8 = @splat(35);
    const archived = try portable.encode(a, compiler, &before);
    defer a.free(archived);
    var checkpoint = try portable.decode(a, compiler, archived);
    defer checkpoint.deinit();
    // Raw allocation changes final admission without changing frame demand.
    const raw = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(raw, ir.packParameterRoles(&.{.scalar}));
    try module.emitSlice(raw, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate } });
    const fresh = try module.assemble();
    defer a.free(fresh);
    const marker = (std.mem.findLast(u8, fresh, "blot:ownership") orelse return error.TestExpectedRootManifest) + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 1, 0 }, fresh[marker..][0..2]);
    for ([_]*const bodies.Capture{ &before, &checkpoint }) |previous| {
        var current: bodies.Capture = .{ .allocator = a };
        defer current.deinit();
        const retained = try module.assembleWithOptions(.{ .previous = previous, .current = &current });
        defer a.free(retained);
        try std.testing.expectEqualSlices(u8, fresh, retained);
        try std.testing.expect(current.roots and current.needs_roots);
        var matcher = try bodies.Matcher.init(a, previous, &current);
        defer matcher.deinit();
        try std.testing.expect(matcher.matches(guarded));
        const output = current.entries.items[guarded].output;
        var instructions: []const ir.Instruction = module.functions.items[guarded].instructions.items;
        if (output) |body| instructions = body.instructions.items;
        var symbolic = false;
        for (instructions) |inst| if (inst.op == .global_get and inst.operand == arena.root_enabled) {
            symbolic = true;
        };
        try std.testing.expect(symbolic);
    }
}

test "wide counted shapes lower immutable parser demand independently of mutable ownership flags" {
    var module = w.Module.init(std.testing.allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.rc_enabled].mutable = true;
    const facts: Facts = .{ .module = &module, .root_mode = 0, .rc_admitted = false };
    const input = [_]ir.Instruction{
        .{ .op = .wide_layouts },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .i32_const, .operand = 42 },
        .{ .op = .else_ },
        .{ .op = .i32_const, .operand = 17 },
        .{ .op = .end },
    };
    try expectLowered(facts, &input, &.{ .{ .op = .block, .operand = input[1].operand }, input[4], input[5] });
    module.globals.items[arena.rc_enabled].bits = @import("../runtime/shared_rc.zig").shaped_mode;
    try expectLowered(facts, &input, &.{ .{ .op = .block, .operand = input[1].operand }, input[2], input[5] });
    try std.testing.expect(!facts.complete());
    try expectLowered(facts, &.{.{ .op = .wide_layouts }}, &.{.{ .op = .i32_const, .operand = 1 }});
}

fn tracingScenario(allocator: std.mem.Allocator) !void {
    var module = w.Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    const count = module.functions.items.len;
    // No raw assembly side effect materializes an implicit scanner.
    const plain = try module.assemble();
    defer allocator.free(plain);
    try std.testing.expectEqual(count, module.functions.items.len);
    const before = try allocator.dupe(ir.Instruction, module.functions.items[arena.allocate].instructions.items);
    defer allocator.free(before);
    const tracing = try @import("../runtime/fixture_tracing.zig").install(&module);
    try std.testing.expectEqual(count + 3, module.functions.items.len);
    try std.testing.expectError(error.InvalidFunctionReference, module.assembleCheckedWithOptions(.{}));
    for ([_]u32{ tracing.mark, tracing.collect, tracing.root_mark }) |id| {
        try std.testing.expect(module.functions.items[id].instructions.items.len > 0);
    }
    try std.testing.expect(module.functions.items[arena.allocate].instructions.items.len > before.len);
    const fixture = try module.assembleWithOptions(.{ .share_machine_code = true });
    defer allocator.free(fixture);
}
test "reference scanning requires explicit fixture construction" {
    try tracingScenario(std.testing.allocator);
}
test "fixture-only scanner construction releases every allocation on OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, tracingScenario, .{});
}

fn checkedProductionScenario(allocator: std.mem.Allocator) !void {
    var module = w.Module.init(allocator);
    defer module.deinit();
    const scalar = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emit(scalar, .{ .op = .i32_const, .operand = 7 });
    const empty = try module.assembleCheckedWithOptions(.{});
    defer allocator.free(empty);
    const arena = try module.ensureArena();
    const complete = try module.assembleCheckedWithOptions(.{});
    defer allocator.free(complete);
    const marker = std.mem.findLast(u8, complete, "blot:ownership").? + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, complete[marker..][0..3]);
    const raw = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(raw, ir.packParameterRoles(&.{.scalar}));
    try module.emitSlice(raw, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate } });
    const source = try allocator.dupe(ir.Instruction, module.functions.items[raw].instructions.items);
    defer allocator.free(source);
    var rejection: w.OwnershipFailure = .{};
    if (module.assembleCheckedWithOptions(.{ .rejection = &rejection })) |unexpected| {
        allocator.free(unexpected);
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try std.testing.expectEqual(error.IncompleteOwnership, err);
    }
    try std.testing.expectEqual(w.OwnershipFallback.unproven_body, rejection.fallback);
    try std.testing.expectEqual(@as(?u32, raw), rejection.function);
    try std.testing.expectEqualSlices(ir.Instruction, source, module.functions.items[raw].instructions.items);
    // Private fixtures retain their deliberately unproved/raw contract.
    const partial = try module.assemble();
    defer allocator.free(partial);
    const partial_marker = std.mem.findLast(u8, partial, "blot:ownership").? + "blot:ownership".len;
    try std.testing.expectEqual(@as(u8, @backingInt(w.OwnershipFallback.unproven_body)), partial[partial_marker + 2]);
}
test "checked production emits no scanners and rejects unproved graphs without changing source" {
    try checkedProductionScenario(std.testing.allocator);
}
test "checked production admission and rejection release every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkedProductionScenario, .{});
}

fn resourceRetirementScenario(allocator: std.mem.Allocator, feature: bool) !void {
    var module = w.Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.rc_enabled].mutable = true;
    module.globals.items[arena.rc_enabled].bits = 1;
    try module.exportFunction(arena.release_lease, "release", .u32, .unit);
    const facts: Facts = .{ .module = &module, .root_mode = 0, .rc_admitted = false };
    const marker = [_]ir.Instruction{.{ .op = .resource_retire }};
    try expectLowered(facts, &marker, &.{});
    _ = try module.importFunction("blot:resource/1", "retire", &.{.i32}, .none);
    _ = try module.importFunction("blot:resource/2", "other", &.{.i32}, .none);
    _ = try module.importFunction("other", "retire", &.{.i32}, .none);
    _ = try module.importFunction("blot:resource/2", "retire", &.{.f32}, .none);
    try expectLowered(facts, &marker, &.{});
    if (feature) {
        const item = module.imports.pop().?;
        allocator.free(item.module);
        allocator.free(item.name);
        const imported = try module.importFunction("blot:resource/2", "retire", &.{.i32}, .none);
        var lowered: Iterator = .{ .facts = facts, .instructions = &marker };
        var count: usize = 0;
        var call_at: usize = 0;
        var clear_at: usize = 0;
        while (lowered.next()) |inst| {
            if (inst.op == .i32_store) {
                try std.testing.expectEqual(@as(u32, 4), inst.operand);
                clear_at = count;
            }
            if (inst.op == .call_import) {
                try std.testing.expectEqual(imported, inst.operand);
                call_at = count;
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 18), count);
        try std.testing.expect(clear_at < call_at);
    }
    const before = try module.assemble();
    defer allocator.free(before);
    if (!feature) {
        const body = &module.functions.items[arena.retire].instructions;
        var removed: usize = 0;
        var at: usize = 0;
        while (at < body.items.len) {
            if (body.items[at].op == .resource_retire) {
                _ = body.orderedRemove(at);
                removed += 1;
            } else at += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), removed);
        const without = try module.assemble();
        defer allocator.free(without);
        try std.testing.expectEqualSlices(u8, before, without);
    }
}

test "resource retirement enables only an exact typed import and ordinary Wasm has zero hook overhead" {
    const controls = [_]struct { parameters: []const ir.ValueType, result: ir.ValueType }{
        .{ .parameters = &.{ .i32, .i32 }, .result = .none },
        .{ .parameters = &.{.i32}, .result = .i32 },
    };
    for (controls) |control| {
        var module = w.Module.init(std.testing.allocator);
        defer module.deinit();
        _ = try module.importFunction("blot:resource/2", "retire", control.parameters, control.result);
        const facts: Facts = .{ .module = &module, .root_mode = 0, .rc_admitted = false };
        try expectLowered(facts, &.{.{ .op = .resource_retire }}, &.{});
    }
    try resourceRetirementScenario(std.testing.allocator, false);
    try resourceRetirementScenario(std.testing.allocator, true);
}

test "resource retirement final lowering and publication release every allocation on OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, resourceRetirementScenario, .{true});
}
