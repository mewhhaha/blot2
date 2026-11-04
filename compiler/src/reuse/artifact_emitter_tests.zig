const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const artifact = @import("artifact_emitter.zig");
const operations = @import("../backend/runtime_operations.zig");
const evidence = @import("../eval/type_evidence.zig");
const failures = @import("../allocation_failures.zig");

fn instructionRuns(allocator: std.mem.Allocator) !void {
    var journal = artifact.Recorder.init(allocator);
    defer journal.deinit();
    var clock: u64 = 20;
    var owner: u32 = 7;
    journal.clock = &clock;
    journal.owner = &owner;
    try journal.appendInstruction(0, .i32_const, .{ .value = 1 });
    try journal.appendInstruction(0, .i32_const, .{ .value = 2 });
    try journal.appendInstruction(0, .i32_add, .{});
    // A metadata event shares the clock but not the emission stream.
    clock += 1;
    try journal.appendInstruction(0, .drop, .{});
    owner = 8;
    try journal.appendInstruction(0, .i32_const, .{ .value = 42 });
    try journal.append(.{ .demand = .{ .kind = .signature, .id = 0, .hit = true } });
    try journal.appendInstruction(0, .drop, .{});
    try std.testing.expectEqual(@as(usize, 5), journal.records.items.len);
    try std.testing.expectEqual(@as(u32, 3), journal.records.items[0].event.instruction_run.instructions.len);
    try std.testing.expectEqual(@as(u64, 24), journal.records.items[1].sequence);
    try std.testing.expectEqual(@as(u32, 8), journal.records.items[2].owner);
    try std.testing.expectEqual(@as(u64, 28), clock);
    const first = journal.instructionRun(journal.records.items[0].event.instruction_run.instructions).?;
    try std.testing.expectEqual(@as(usize, 3), first.len);
    try std.testing.expectEqual(wasm.Op.i32_add, first[2].op);
    try std.testing.expect(journal.instructionRun(.{ .start = 6, .len = 1 }) == null);
    try std.testing.expect(journal.instructionRun(.{ .start = std.math.maxInt(u32), .len = 1 }) == null);
}

test "instruction journal runs preserve owner clock and resource boundaries through OOM" {
    try instructionRuns(std.testing.allocator);
    try failures.checkAllAllocationFailures(std.testing.allocator, instructionRuns, .{});
}

fn scenario(allocator: std.mem.Allocator) !void {
    var journal = artifact.Recorder.init(allocator);
    defer journal.deinit();
    var original = wasm.Module.init(allocator);
    var alive = true;
    defer if (alive) original.deinit();
    original.artifacts = &journal;
    var proof = try evidence.Store.init(allocator);
    defer proof.deinit();
    var symbols = operations.Store.init(allocator);
    defer symbols.deinit();
    const label = try proof.effects.internOperation(.{ .unit = 1, .decl = 9 }, &.{});
    const operation = try symbols.intern(proof.view(), label);
    const parent = try original.addFunction(&.{}, .i32);
    const child = try original.addFunction(&.{}, .i32);
    // Ownership facts replay with the function they describe.
    const ir = @import("../backend/runtime_ir.zig");
    const typed = try original.addFunction(&.{ .i32, .f32 }, .none);
    const typed_roles = ir.packParameterRoles(&.{ .reference, .scalar });
    try original.setParameterRoles(typed, typed_roles);
    var annotations: [ir.max_annotations]wasm.Instruction = undefined;
    try original.emitSlice(typed, ir.annotations(&.{.reference}, .unknown, &annotations));
    _ = try original.addLocal(parent, .i32);
    try symbols.emit(&original, child, operation);
    try original.emit(parent, .{ .op = .call, .operand = child });
    const imported = try original.importFunction("fixture", "f", &.{}, .i32);
    try original.emit(parent, .{ .op = .call_import, .operand = imported });
    try original.emit(parent, .{ .op = .drop });
    const signature = try original.internType(&.{.i32}, .i32);
    try original.emit(parent, .{ .op = .i32_const });
    try original.emitReference(parent, .{ .op = .i32_const, .operand = child }, .table_function);
    try original.emit(parent, .{ .op = .call_indirect, .operand = signature });
    try original.emit(parent, .{ .op = .drop });
    const payload = try original.dataWords(&.{42});
    const closure = try original.dataWords(&.{ child, payload, 0 });
    try original.dataReference(closure, .{ .role = .table_function, .value = child });
    try original.dataReference(closure + 4, .{ .role = .static_address, .value = payload });
    try symbols.dataWord(&original, closure + 8, operation);
    try original.emitReference(parent, .{ .op = .i32_const, .operand = closure }, .static_address);
    try original.exportFunction(parent, "parent", .unit, .u32);
    try original.exportConstant("literal", .u32, 8);
    _ = try original.ensureHostReferences();
    try journal.captureOperations(symbols.entries.items);
    try symbols.finish(&original);
    const expected = try original.assemble();
    defer allocator.free(expected);
    const expected_count = original.functions.items.len;
    const expected_data = try allocator.dupe(u8, original.data.items);
    defer allocator.free(expected_data);
    journal.seal();
    try journal.freezeFunctions(&.{});
    original.deinit();
    alive = false;
    var replayed = try journal.materialize(allocator);
    defer replayed.deinit();
    try std.testing.expectEqual(expected_count, replayed.functions.items.len);
    try std.testing.expectEqual(typed_roles, replayed.functions.items[typed].parameter_roles);
    try std.testing.expectEqual(@as(u32, 2), replayed.functions.items[typed].annotations);
    try std.testing.expectEqual(@as(usize, 0), replayed.functions.items[typed].codeLength());
    try std.testing.expectEqualSlices(u8, expected_data, replayed.data.items);
    const actual = try replayed.assemble();
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
    // Relocations use the newly allocated resource handles, not old indexes.
    var shifted = wasm.Module.init(allocator);
    defer shifted.deinit();
    _ = try shifted.addFunction(&.{.f32}, .f32);
    _ = try shifted.importFunction("unrelated", "other", &.{.f32}, .f32);
    _ = try shifted.addGlobal(.u32, 7, false);

    try journal.replayInto(&shifted);
    try std.testing.expectEqual(@as(u32, child + 1), shifted.functions.items[parent + 1].instructions.items[0].operand);
    try std.testing.expectEqual(@as(u32, imported + 1), shifted.functions.items[parent + 1].instructions.items[1].operand);
    try std.testing.expectEqual(@as(u32, closure), shifted.functions.items[parent + 1].instructions.items[7].operand);
    try std.testing.expectEqual(@as(u32, child + 1), std.mem.readInt(u32, shifted.data.items[closure..][0..4], .little));
    try std.testing.expectEqual(@as(u32, payload), std.mem.readInt(u32, shifted.data.items[closure + 4 ..][0..4], .little));
    var unsupported = wasm.Module.init(allocator);
    defer unsupported.deinit();
    _ = try unsupported.dataWords(&.{99});
    try std.testing.expectError(error.UnsupportedArenaComposition, journal.replayInto(&unsupported));
}

test "owned typed emission reconstruction survives original module destruction and shifted resources" {
    try scenario(std.testing.allocator);
}

test "capture and replay allocations leave owners releasable on every failure" {
    try failures.checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}

test "resource adapter replay preserves owned entry classification independently of spelling" {
    const a = std.testing.allocator;
    var journal = artifact.Recorder.init(a);
    defer journal.deinit();
    var original = wasm.Module.init(a);
    defer original.deinit();
    original.artifacts = &journal;
    const private = try original.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar);
    try original.exportResourceAdapter(private, "private_adapter");
    const entry = try original.addTypedFunction(&.{}, .i32, .scalar);
    try original.emit(entry, .{ .op = .i32_const, .operand = 7 });
    try original.exportFunction(entry, "blot:resource_cleanup/0", .unit, .u32);
    journal.seal();
    var replayed = try journal.materialize(a);
    defer replayed.deinit();
    try std.testing.expect(!original.functions.items[private].entry);
    try std.testing.expect(!replayed.functions.items[private].entry);
    try std.testing.expect(original.functions.items[entry].entry);
    try std.testing.expect(replayed.functions.items[entry].entry);
}

fn providerInterfaceScenario(allocator: std.mem.Allocator) !void {
    const ir = @import("../backend/runtime_ir.zig");
    const bodies = @import("../backend/optimized_bodies.zig");
    const archive = @import("optimized_archive.zig");
    var journal = artifact.Recorder.init(allocator);
    defer journal.deinit();
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    module.artifacts = &journal;
    const id = try module.addTypedFunction(&.{ .i32, .f32, .i32 }, .i32, .scalar);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{ .reference, .scalar, .reference }));
    try module.setProviderParameter(id, 2);
    try module.emit(id, .{ .op = .i32_const, .operand = 41 });
    var capture: bodies.Capture = .{ .allocator = allocator };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .current = &capture });
    defer allocator.free(bytes);
    try std.testing.expectEqual(@as(u16, 2), capture.entries.items[id].source.provider_parameter);
    journal.seal();
    module.artifacts = null;
    var reconstructed = try journal.materialize(allocator);
    defer reconstructed.deinit();
    try std.testing.expectEqual(@as(u16, 2), reconstructed.functions.items[id].provider_parameter);
    const replay = try reconstructed.assemble();
    defer allocator.free(replay);
    try std.testing.expectEqualSlices(u8, bytes, replay);
    const saved = try archive.encode(allocator, @splat(35), &capture);
    defer allocator.free(saved);
    var loaded = try archive.decode(allocator, @splat(35), saved);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(u16, 2), loaded.entries.items[id].source.provider_parameter);
    try module.setProviderParameter(id, 0);
    var changed: bodies.Capture = .{ .allocator = allocator };
    defer changed.deinit();
    const altered = try module.assembleWithOptions(.{ .previous = &loaded, .current = &changed });
    defer allocator.free(altered);
    var matcher = try bodies.Matcher.init(allocator, &loaded, &changed);
    defer matcher.deinit();
    try std.testing.expect(!matcher.matches(id));
    try std.testing.expectEqual(@as(u16, 0), changed.entries.items[id].source.provider_parameter);
    // A source scalar cannot acquire provider authority in a loaded capture.
    // Input changes cannot rewrite the independently owned earlier facts.
    loaded.entries.items[id].source.provider_parameter = 1;
    const poisoned = try archive.encode(allocator, @splat(35), &loaded);
    defer allocator.free(poisoned);
    var invalid = archive.decode(allocator, @splat(35), poisoned) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    invalid.deinit();
    return error.TestExpectedError;
}
test "checked provider parameters preserve exact source interfaces through emission archive replay and OOM" {
    try providerInterfaceScenario(std.testing.allocator);
    try failures.checkAllAllocationFailures(std.testing.allocator, providerInterfaceScenario, .{});
}

fn callableInterfaceScenario(allocator: std.mem.Allocator) !void {
    const ir = @import("../backend/runtime_ir.zig");
    const bodies = @import("../backend/optimized_bodies.zig");
    const archive = @import("optimized_archive.zig");
    var layouts = try @import("../backend/layout.zig").Store.init(allocator);
    defer layouts.deinit();
    const expected = try layouts.intern(.function, 4, 3, &.{});
    const changed_type = try layouts.intern(.function, 3, 3, &.{});
    var journal = artifact.Recorder.init(allocator);
    defer journal.deinit();
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    module.artifacts = &journal;
    const id = try module.addTypedFunction(&.{ .i32, .f32, .i32 }, .i32, .scalar);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{ .reference, .scalar, .reference }));
    try module.setProviderParameter(id, 2);
    try module.setCallableLayout(id, expected);
    try module.emit(id, .{ .op = .local_get });
    try module.emit(id, ir.callableCodeRead(expected));
    try module.emit(id, .{ .op = .i32_load });
    try module.emit(id, .{ .op = .drop });
    try module.emit(id, .{ .op = .i32_const, .operand = 41 });
    var capture_: bodies.Capture = .{ .allocator = allocator };
    defer capture_.deinit();
    const bytes = try module.assembleWithOptions(.{ .current = &capture_ });
    defer allocator.free(bytes);
    try std.testing.expectEqual(expected, capture_.entries.items[id].source.callable_layout);
    journal.seal();
    module.artifacts = null;
    var shifted = wasm.Module.init(allocator);
    defer shifted.deinit();
    _ = try shifted.addFunction(&.{.f32}, .f32);
    try journal.replayInto(&shifted);
    try std.testing.expectEqual(expected, shifted.functions.items[id + 1].callable_layout);
    try std.testing.expectEqual(@as(?u32, expected), ir.callableCodeLayout(shifted.functions.items[id + 1].instructions.items, 2));
    const saved = try archive.encode(allocator, @splat(35), &capture_);
    defer allocator.free(saved);
    var loaded = try archive.decode(allocator, @splat(35), saved);
    defer loaded.deinit();
    try std.testing.expectEqual(expected, loaded.entries.items[id].source.callable_layout);
    try module.setCallableLayout(id, changed_type);
    var changed: bodies.Capture = .{ .allocator = allocator };
    defer changed.deinit();
    const altered = try module.assembleWithOptions(.{ .previous = &loaded, .current = &changed });
    defer allocator.free(altered);
    var matcher = try bodies.Matcher.init(allocator, &loaded, &changed);
    defer matcher.deinit();
    try std.testing.expect(!matcher.matches(id));
    try std.testing.expectEqual(expected, loaded.entries.items[id].source.callable_layout);
    loaded.entries.items[id].source.instructions.items[4].table_kind = .callable;
    const forged_kind = try archive.encode(allocator, @splat(35), &loaded);
    defer allocator.free(forged_kind);
    if (archive.decode(allocator, @splat(35), forged_kind)) |decoded| {
        var unexpected = decoded;
        unexpected.deinit();
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
    }
    loaded.entries.items[id].source.instructions.items[4].table_kind = .unknown;
    loaded.entries.items[id].source.callable_layout = 1 << 26;
    const poisoned = try archive.encode(allocator, @splat(35), &loaded);
    defer allocator.free(poisoned);
    var invalid = archive.decode(allocator, @splat(35), poisoned) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    invalid.deinit();
    return error.TestExpectedError;
}
test "logical callable endpoint metadata survives shifted emission archives and mismatch invalidation through OOM" {
    try callableInterfaceScenario(std.testing.allocator);
    try failures.checkAllAllocationFailures(std.testing.allocator, callableInterfaceScenario, .{});
}

// Native storage narrows the index only after the same role proof as the wire.
test "provider parameter byte preserves role boundary and rejects wide indices before narrowing" {
    const a = std.testing.allocator;
    const ir = @import("../backend/runtime_ir.zig");
    var module = wasm.Module.init(a);
    defer module.deinit();
    const parameters: [256]ir.ValueType = @splat(.i32);
    const id = try module.addTypedFunction(&parameters, .i32, .scalar);
    try module.setParameterRoles(id, ir.packParameterRoles(&@as([32]ir.Role, @splat(.reference))));
    try module.setProviderParameter(id, 31);
    try std.testing.expectEqual(@as(u8, 31), module.functions.items[id].provider_parameter);
    for ([_]u16{ 32, 255, 256, 65534, 65535 }) |index| {
        try std.testing.expectError(error.InvalidFunctionReference, module.setProviderParameter(id, index));
        try std.testing.expectEqual(@as(u8, 31), module.functions.items[id].provider_parameter);
    }
    try module.setProviderParameter(id, ir.no_provider);
    try std.testing.expectEqual(ir.no_provider, module.functions.items[id].provider_parameter);
    try std.testing.expect(module.functions.items[id].validProviderParameter());
}
