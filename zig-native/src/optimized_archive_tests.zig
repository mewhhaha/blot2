const std = @import("std");
const wasm = @import("wasm.zig");
const bodies = @import("optimized_bodies.zig");
const archive = @import("optimized_archive.zig");
const compiler: [32]u8 = @splat(17);

fn module(a: std.mem.Allocator) !wasm.Module {
    var result = wasm.Module.init(a);
    errdefer result.deinit();
    for (0..2) |id| {
        _ = try result.addFunction(&.{.i32}, .i32);
        try result.emitSlice(@intCast(id), &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = @intCast(id) }, .{ .op = .i32_add } });
    }
    return result;
}
fn scenario(a: std.mem.Allocator) !void {
    var original = try module(a);
    defer original.deinit();
    const saved = blk: {
        var old: bodies.Capture = .{ .allocator = a };
        defer old.deinit();
        const first = try original.assembleWithOptions(.{ .current = &old });
        errdefer a.free(first);
        break :blk .{ .wasm = first, .archive = try archive.encode(a, compiler, &old) };
    };
    const first = saved.wasm;
    defer a.free(first);
    var loaded = blk: {
        defer a.free(saved.archive);
        break :blk try archive.decode(a, compiler, saved.archive);
    };
    defer loaded.deinit();
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const reused = try original.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, first, reused);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
    original.functions.items[0].instructions.items[1].operand = 99;
    var changed: bodies.Capture = .{ .allocator = a };
    defer changed.deinit();
    stats = .{};
    const edited = try original.assembleWithOptions(.{ .previous = &loaded, .current = &changed, .stats = &stats });
    defer a.free(edited);
    const fresh = try original.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expectEqual(@as(usize, 1), stats.reused);
}
test "portable optimizer captures outlive producers and preserve exact per-body admission through failures" {
    try scenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}

fn symbolicModule(a: std.mem.Allocator, shifted: bool) !wasm.Module {
    var result = wasm.Module.init(a);
    errdefer result.deinit();
    if (shifted) {
        const extra = try result.addFunction(&.{.f32}, .f32);
        try result.emit(extra, .{ .op = .local_get });
        _ = try result.importFunction("other", "unused", &.{}, .none);
        _ = try result.addGlobal(.f32, 0x3f800000, false);
    }
    const imported = try result.importFunction("host", "identity", &.{.i32}, .i32);
    const global = try result.addGlobal(.u32, 7, false);
    const target = try result.addFunction(&.{.i32}, .i32);
    try result.emit(target, .{ .op = .local_get });
    const caller = try result.addFunction(&.{.i32}, .i32);
    try result.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .call_import, .operand = imported }, .{ .op = .global_get, .operand = global }, .{ .op = .i32_add } });
    try result.emitReference(caller, .{ .op = .i32_const, .operand = target }, .table_function);
    try result.emit(caller, .{ .op = .call_indirect, .operand = result.functions.items[target].signature });
    return result;
}
fn symbolicArchiveBytes(a: std.mem.Allocator) ![]u8 {
    var original = try symbolicModule(a, false);
    defer original.deinit();
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    a.free(try original.assembleWithOptions(.{ .current = &capture }));
    return archive.encode(a, compiler, &capture);
}
fn symbolicArchiveScenario(a: std.mem.Allocator) !void {
    // Both the producing module and archive bytes die before relocation.
    var loaded = blk: {
        const bytes = try symbolicArchiveBytes(a);
        defer a.free(bytes);
        break :blk try archive.decode(a, compiler, bytes);
    };
    defer loaded.deinit();
    try std.testing.expectEqualStrings("host", loaded.imports.items[0].module);
    try std.testing.expectEqualStrings("identity", loaded.imports.items[0].name);
    try std.testing.expect(loaded.entries.items[1].source.instructions.items[4].table_reference);
    var moved = try symbolicModule(a, true);
    defer moved.deinit();
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const reused = try moved.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(reused);
    const fresh = try moved.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, reused);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
}
test "portable optimizer captures own symbolic imports globals and table references through relocation failures" {
    try symbolicArchiveScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicArchiveScenario, .{});
}
test "portable optimizer captures reject stale compilers corrupt bytes and truncated owners" {
    const a = std.testing.allocator;
    var original = try module(a);
    defer original.deinit();
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    const wasm_bytes = try original.assembleWithOptions(.{ .current = &capture });
    defer a.free(wasm_bytes);
    const bytes = try archive.encode(a, compiler, &capture);
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(18), bytes));
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes[0 .. bytes.len - 1]));
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes));
}

const format = @import("dependency_format.zig");
const ir = @import("runtime_ir.zig");
const portable = @import("portable_query.zig");
const Body = archive.Body;

// Calls, locals, a global, a typed `if`/`else` and a branch out of a block.
fn structured(a: std.mem.Allocator) !wasm.Module {
    var result = wasm.Module.init(a);
    errdefer result.deinit();
    const global = try result.addGlobal(.u32, 7, true);
    const callee = try result.addFunction(&.{.i32}, .i32);
    try result.emitSlice(callee, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    const caller = try result.addFunction(&.{.i32}, .i32);
    const local = try result.addLocal(caller, .i32);
    try result.emitSlice(caller, &.{
        .{ .op = .block },
        .{ .op = .local_get },
        .{ .op = .call, .operand = callee },
        .{ .op = .local_set, .operand = local },
        .{ .op = .local_get, .operand = local },
        .{ .op = .br_if, .operand = 0 },
        .{ .op = .end },
        .{ .op = .local_get, .operand = local },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .global_get, .operand = global },
        .{ .op = .else_ },
        .{ .op = .local_get, .operand = local },
        .{ .op = .end },
    });
    return result;
}
fn structuredBytes(a: std.mem.Allocator) !struct { wasm: []u8, archive: []u8 } {
    var original = try structured(a);
    defer original.deinit();
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try original.assembleWithOptions(.{ .current = &capture });
    errdefer a.free(bytes);
    try std.testing.expect(capture.queries_complete);
    try std.testing.expectEqual(@as(usize, 2), capture.queries.records.items.len);
    return .{ .wasm = bytes, .archive = try archive.encode(a, compiler, &capture) };
}
fn rejects(expected: anyerror, snapshot: archive.Snapshot) !void {
    const a = std.testing.allocator;
    const bytes = try format.encode(a, archive.wireKey(compiler), snapshot);
    defer a.free(bytes);
    try std.testing.expectError(expected, archive.decode(a, compiler, bytes));
}

test "portable optimizer query records rebuild the exact sealed index from validated payloads" {
    const a = std.testing.allocator;
    const saved = try structuredBytes(a);
    defer a.free(saved.wasm);
    defer a.free(saved.archive);
    var original = try structured(a);
    defer original.deinit();
    var produced: bodies.Capture = .{ .allocator = a };
    defer produced.deinit();
    a.free(try original.assembleWithOptions(.{ .current = &produced }));
    var loaded = try archive.decode(a, compiler, saved.archive);
    defer loaded.deinit();
    try std.testing.expect(loaded.queries_complete);
    try std.testing.expectEqual(produced.queries.records.items.len, loaded.queries.records.items.len);
    for (produced.queries.records.items, loaded.queries.records.items) |left, right| {
        try std.testing.expectEqualDeep(left.key, right.key);
        try std.testing.expectEqualDeep(left.value, right.value);
        try std.testing.expectEqualSlices(u32, left.dependencies.callees, right.dependencies.callees);
        try std.testing.expectEqualDeep(left.dependencies.parameters, right.dependencies.parameters);
        try std.testing.expectEqual(left.dependencies.invalidates, right.dependencies.invalidates);
        try std.testing.expectEqual(left.dependencies.owned_result_bytes, right.dependencies.owned_result_bytes);
    }
    // The checked-in call edge is an exact dependency of the caller's record.
    try std.testing.expectEqualSlices(u32, &.{0}, loaded.queries.records.items[1].dependencies.callees);
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const reused = try original.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(reused);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
    try std.testing.expectEqualSlices(u8, saved.wasm, reused);
}

test "portable optimizer archives reject forged ordinals control structure and record sets" {
    const a = std.testing.allocator;
    const saved = try structuredBytes(a);
    defer a.free(saved.wasm);
    defer a.free(saved.archive);
    var owner = try format.decode(archive.Snapshot, a, saved.archive, archive.wireKey(compiler));
    defer format.deinit(a, &owner);
    // Re-encoding the unchanged decoded payload is accepted.
    {
        const bytes = try format.encode(a, archive.wireKey(compiler), owner);
        defer a.free(bytes);
        var accepted = try archive.decode(a, compiler, bytes);
        accepted.deinit();
    }
    const caller = owner.entries[1].source.body.instructions;
    const Edit = struct { at: usize, inst: ir.Instruction };
    const body_edits = [_]Edit{
        .{ .at = 2, .inst = .{ .op = .call, .operand = 2 } }, // function past the capture
        .{ .at = 3, .inst = .{ .op = .local_set, .operand = 2 } }, // local past params+locals
        .{ .at = 9, .inst = .{ .op = .global_get, .operand = 1 } }, // global past the capture
        .{ .at = 9, .inst = .{ .op = .call_import, .operand = 0 } }, // no imports
        .{ .at = 9, .inst = .{ .op = .call_indirect, .operand = 9 } }, // signature past the capture
        .{ .at = 8, .inst = .{ .op = .if_, .operand = 300 } }, // block type is not a value type
        .{ .at = 5, .inst = .{ .op = .br_if, .operand = 2 } }, // label past the open frames
        .{ .at = 6, .inst = .{ .op = .nop } }, // block never closes
        .{ .at = 0, .inst = .{ .op = .nop } }, // an extra end
        .{ .at = 8, .inst = .{ .op = .block } }, // else inside a block
        .{ .at = 9, .inst = .{ .op = .i32x4_extract_lane, .operand = 4 } },
        .{ .at = 9, .inst = .{ .op = .i32_const, .operand = 2, .table_reference = true } },
        .{ .at = 9, .inst = .{ .op = .local_get, .table_reference = true } },
    };
    for (body_edits) |edit| {
        const before = caller[edit.at];
        defer caller[edit.at] = before;
        caller[edit.at] = edit.inst;
        try rejects(error.InvalidArtifact, owner);
    }
    // Outputs are validated against the same capture before any reuse.
    {
        var forged = [_]ir.Instruction{.{ .op = .local_get, .operand = 1 }};
        const before = owner.entries[0].output;
        defer owner.entries[0].output = before;
        owner.entries[0].output = Body{ .locals = &.{}, .instructions = &forged };
        try rejects(error.InvalidArtifact, owner);
        forged[0] = .{ .op = .call, .operand = 5 };
        try rejects(error.InvalidArtifact, owner);
    }
    {
        const before = owner.arena;
        defer owner.arena = before;
        var invalid_arena = std.mem.zeroes(wasm.Arena);
        invalid_arena.collect = 2;
        owner.arena = invalid_arena;
        try rejects(error.InvalidArtifact, owner);
    }
    const records = owner.queries.records;
    try std.testing.expectEqual(@as(usize, 2), records.len);
    const Shape = struct { records: []const archive.Record, sealed: bool = true };
    const swapped = [_]archive.Record{ records[1], records[0] };
    const repeated = [_]archive.Record{ records[0], records[0], records[1] };
    for ([_]Shape{
        .{ .records = &swapped },
        .{ .records = &repeated },
        .{ .records = records[0..1] },
        .{ .records = records[1..] },
        .{ .records = records, .sealed = false },
    }) |shape| {
        var copy = owner;
        copy.queries.records = @constCast(shape.records);
        copy.sealed = shape.sealed;
        try rejects(error.InvalidArtifact, copy);
    }
    {
        var forged = records[1];
        var callees = [_]u32{1};
        forged.dependencies.callees = &callees;
        var copy = owner;
        var shape = [_]archive.Record{ records[0], forged };
        copy.queries.records = &shape;
        try rejects(error.InvalidArtifact, copy);
        shape[1] = records[1];
        shape[1].key.tier = .development;
        try rejects(error.InvalidArtifact, copy);
        shape[1] = records[1];
        shape[1].result.function = 0;
        try rejects(error.InvalidArtifact, copy);
        shape[1] = records[1];
        shape[1].dependencies.invalidates = !records[1].dependencies.invalidates;
        try rejects(error.InvalidArtifact, copy);
    }
    {
        var copy = owner;
        copy.queries.header.version += 1;
        try rejects(error.UnsupportedVersion, copy);
        copy.queries.header = portable.header(.principal_complete_proof);
        try rejects(error.SchemaMismatch, copy);
    }
}

test "portable optimizer archives keep unsealed tables unsealed and decline their reuse" {
    const a = std.testing.allocator;
    const saved = try structuredBytes(a);
    defer a.free(saved.wasm);
    defer a.free(saved.archive);
    var owner = try format.decode(archive.Snapshot, a, saved.archive, archive.wireKey(compiler));
    defer format.deinit(a, &owner);
    var copy = owner;
    copy.sealed = false;
    copy.queries.records = &.{};
    const bytes = try format.encode(a, archive.wireKey(compiler), copy);
    defer a.free(bytes);
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(!loaded.queries_complete);
    try std.testing.expectEqual(@as(usize, 0), loaded.queries.records.items.len);
    var original = try structured(a);
    defer original.deinit();
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const rebuilt = try original.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(rebuilt);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
    try std.testing.expectEqualSlices(u8, saved.wasm, rebuilt);
    // A saturated producer table also persists no records.
    var saturated: bodies.Capture = .{ .allocator = a };
    defer saturated.deinit();
    saturated.queries.limits.records = 1;
    a.free(try original.assembleWithOptions(.{ .current = &saturated }));
    try std.testing.expect(!saturated.queries_complete);
    const unsealed = try archive.encode(a, compiler, &saturated);
    defer a.free(unsealed);
    var reloaded = try archive.decode(a, compiler, unsealed);
    defer reloaded.deinit();
    try std.testing.expect(!reloaded.queries_complete);
    try std.testing.expectEqual(@as(usize, 0), reloaded.queries.records.items.len);
}

test "portable optimizer preserves checked results without widening machine bodies" {
    const a = std.testing.allocator;
    const MachineFunction = struct { parameters: []ir.ValueType, result: ir.ValueType, signature: u32, parameter_roles: u64, annotations: u32, locals: std.ArrayList(ir.ValueType), instructions: std.ArrayList(ir.Instruction) };
    try std.testing.expectEqual(@sizeOf(MachineFunction), @sizeOf(ir.Function));
    var original = wasm.Module.init(a);
    defer original.deinit();
    const callee = try original.addTypedFunction(&.{}, .i32, .scalar);
    try original.emit(callee, .{ .op = .i32_const });
    const caller = try original.addTypedFunction(&.{}, .i32, .scalar);
    try original.emitSlice(caller, &.{ .{ .op = .call, .operand = callee }, .{ .op = .drop }, .{ .op = .i32_const, .operand = 42 } });
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    const first = try original.assembleWithOptions(.{ .current = &capture });
    defer a.free(first);
    const bytes = try archive.encode(a, compiler, &capture);
    defer a.free(bytes);
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expectEqual(ir.Role.scalar, loaded.entries.items[callee].source.result_role);
    original.functions.items[callee].result_role = .reference;
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const revised = try original.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(revised);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
    const fresh = try original.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, revised);
    try std.testing.expectEqualSlices(u8, first, revised);
}

fn indirectOwner(a: std.mem.Allocator) !struct { module: wasm.Module, caller: u32, annotation: usize } {
    var result = wasm.Module.init(a);
    errdefer result.deinit();
    const arena = try result.ensureArena();
    const owner = try result.addTypedFunction(&.{}, .i32, .reference);
    try result.emitSlice(owner, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed } });
    const target = try result.addTypedFunction(&.{.i32}, .i32, .reference);
    try result.setParameterRoles(target, ir.packParameterRoles(&.{.reference}));
    try result.emit(target, .{ .op = .local_get });
    const caller = try result.addTypedFunction(&.{.i32}, .i32, .scalar);
    try result.setParameterRoles(caller, ir.packParameterRoles(&.{.reference}));
    try result.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = target, .table_reference = true }, ir.callResult(.reference), .{ .op = .call_indirect, .operand = result.functions.items[target].signature }, .{ .op = .i32_load } });
    return .{ .module = result, .caller = caller, .annotation = 2 };
}

test "portable forged scalar indirect facts cannot suppress a fresh owning frame" {
    const a = std.testing.allocator;
    var fixture = try indirectOwner(a);
    defer fixture.module.deinit();
    var captured: bodies.Capture = .{ .allocator = a };
    defer captured.deinit();
    const fresh = try fixture.module.assembleWithOptions(.{ .current = &captured });
    defer a.free(fresh);
    try std.testing.expect(captured.roots);
    const caller = &captured.entries.items[fixture.caller];
    try std.testing.expect(caller.output != null);
    // Forge a scalar fact and the corresponding omitted transformation. Wire
    // structure is valid, but neither can substitute for the fresh checked role.
    caller.source.instructions.items[fixture.annotation] = ir.callResult(.scalar);
    caller.output.?.deinit(a);
    caller.output = null;
    const bytes = try archive.encode(a, compiler, &captured);
    defer a.free(bytes);
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const checked = try fixture.module.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(checked);
    try std.testing.expectEqualSlices(u8, fresh, checked);
    try std.testing.expectEqual(fixture.module.functions.items.len - 1, stats.reused);
    try std.testing.expect(current.entries.items[fixture.caller].output != null);
}

test "portable indirect result annotations reject malformed and orphan facts" {
    const a = std.testing.allocator;
    var fixture = try indirectOwner(a);
    defer fixture.module.deinit();
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    a.free(try fixture.module.assembleWithOptions(.{ .current = &capture }));
    const bytes = try archive.encode(a, compiler, &capture);
    defer a.free(bytes);
    var snapshot = try format.decode(archive.Snapshot, a, bytes, archive.wireKey(compiler));
    defer format.deinit(a, &snapshot);
    const instructions = snapshot.entries[fixture.caller].source.body.instructions;
    instructions[fixture.annotation] = .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .call_result, .chunk = 1, .roles = 1 }) };
    try rejects(error.InvalidArtifact, snapshot);
    instructions[fixture.annotation] = ir.callResult(.reference);
    instructions[fixture.annotation + 1] = .{ .op = .nop };
    try rejects(error.InvalidArtifact, snapshot);
}
