const std = @import("std");
const wasm = @import("wasm.zig");
const retained = @import("optimized_bodies.zig");

fn drainPresence(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    module.public_arena = true;
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.setParameterRoles(function, @import("runtime_ir.zig").packParameterRoles(&.{.scalar}));
    const ir = @import("runtime_ir.zig");
    try module.emitSlice(function, &.{
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 0 }) },
        .{ .op = .local_get },
        .{ .op = .local_set },
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 1 }) },
        .{ .op = .local_get },
    });
    try module.exportFunction(function, "run", .u32, .u32);
    const cleanup = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar);
    try module.setParameterRoles(cleanup, ir.packParameterRoles(&.{ .scalar, .scalar, .scalar }));
    try module.exportResourceAdapter(cleanup, "blot:resource_cleanup/0");
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    const before = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(before);
    try std.testing.expect(old.roots);
    _ = try module.importFunction("blot:resource/2", "drain", &.{}, .none);
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    const replay = try module.assembleWithOptions(.{ .previous = &old, .current = &current });
    defer a.free(replay);
    try std.testing.expect(current.roots);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, replay);
    var drains: usize = 0;
    for (current.entries.items[function].output.?.instructions.items) |inst| if (inst.op == .call_import and inst.operand == module.resourceDrainImport().?) {
        drains += 1;
    };
    try std.testing.expect(drains != 0);
    const imports = module.imports.items;
    module.imports.items = imports[0..0];
    defer module.imports.items = imports;
    const reverted = try module.assembleWithOptions(.{ .previous = &current });
    defer a.free(reverted);
    const reverted_fresh = try module.assemble();
    defer a.free(reverted_fresh);
    try std.testing.expectEqualSlices(u8, reverted_fresh, reverted);
}
test "optimizer reuse observes newly installed resource cleanup drain through OOM" {
    try drainPresence(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, drainPresence, .{});
}

fn assemble(a: std.mem.Allocator, module: *const wasm.Module, old: ?*const retained.Capture, current: *retained.Capture, stats: *retained.Stats) ![]u8 {
    _ = a;
    return module.assembleWithOptions(.{ .previous = old, .current = current, .stats = stats });
}

test "optimized bodies survive unrelated edits and keep immutable owned results" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second }) |id| try module.emitSlice(id, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try assemble(a, &module, null, &old, &stats);
    defer a.free(before);
    try std.testing.expectEqual(@as(usize, 2), stats.optimized);
    try std.testing.expect(old.queries_complete);
    try std.testing.expectEqual(@as(usize, 2), old.queries.records.items.len);
    module.functions.items[second].instructions.items[1].operand = 2;
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    stats = .{};
    const edited = try assemble(a, &module, &old, &current, &stats);
    defer a.free(edited);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expectEqual(@as(usize, 1), stats.reused);
    try std.testing.expectEqual(@as(usize, 1), stats.optimized);
    module.functions.items[second].instructions.items[1].operand = 1;
    var reverted: retained.Capture = .{ .allocator = a };
    defer reverted.deinit();
    stats = .{};
    const original = try assemble(a, &module, &old, &reverted, &stats);
    defer a.free(original);
    try std.testing.expectEqualSlices(u8, before, original);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
}

test "executable optimizer queries decline unsealed and saturated results without changing fresh bytes" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .local_get });
    const fresh = try module.assemble();
    defer a.free(fresh);
    for (0..3) |limit| {
        var old: retained.Capture = .{ .allocator = a };
        defer old.deinit();
        switch (limit) {
            0 => old.queries.limits.records = 0,
            1 => old.queries.limits.owned_bytes = 0,
            2 => old.queries.limits.retained_capacity = 0,
            else => unreachable,
        }
        const before = try module.assembleWithOptions(.{ .current = &old });
        defer a.free(before);
        try std.testing.expectEqualSlices(u8, fresh, before);
        try std.testing.expect(!old.queries_complete);
        try std.testing.expectEqual(@as(usize, 0), old.queries.records.items.len);
        var current: retained.Capture = .{ .allocator = a };
        defer current.deinit();
        var stats: retained.Stats = .{};
        const next = try module.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
        defer a.free(next);
        try std.testing.expectEqualSlices(u8, fresh, next);
        try std.testing.expectEqual(@as(usize, 0), stats.reused);
        try std.testing.expectEqual(@as(usize, 1), stats.optimized);
        // Entries are mandatory optimizer input owners; a caller must not
        // mistake these complete-looking bytes for published query records.
        old.queries_complete = false;
        var matcher = try retained.Matcher.init(a, &old, &current);
        defer matcher.deinit();
        try std.testing.expect(!matcher.matches(id));
    }
}

test "executable optimizer queries preserve every source owner before physical sharing" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    for (0..3) |_| {
        const id = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        try module.setParameterRoles(id, @import("runtime_ir.zig").packParameterRoles(&.{.scalar}));
        try module.emit(id, .{ .op = .local_get });
    }
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var shared_stats: retained.Stats = .{};
    const bytes = try module.assembleWithOptions(.{ .current = &old, .share_machine_code = true, .stats = &shared_stats });
    defer a.free(bytes);
    try std.testing.expect(old.queries_complete);
    try std.testing.expectEqual(@as(usize, 2), shared_stats.shared);
    // Sharing changes final machine indexes. Each source function still owns
    // its independently prepared output and executable query proof.
    try std.testing.expectEqual(@as(usize, 3), old.queries.records.items.len);
    for (old.queries.records.items, 0..) |record, ordinal| {
        try std.testing.expectEqual(@as(u32, @intCast(ordinal)), record.value.function);
        try std.testing.expect(record.value.ready);
        try std.testing.expect(old.entries.items[ordinal].output_ready);
    }
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    const next = try module.assembleWithOptions(.{ .previous = &old, .current = &current, .share_machine_code = false });
    defer a.free(next);
    const fresh = try module.assembleWithOptions(.{ .share_machine_code = false });
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, next);
    try std.testing.expectEqual(@as(usize, 3), current.queries.records.items.len);
    const fingerprint = current.queries.records.items[0].key.local_fingerprint;
    var newest = current.queries.candidates(fingerprint, .newest_first);
    var oldest = current.queries.candidates(fingerprint, .oldest_first);
    for (0..3) |ordinal| {
        try std.testing.expectEqual(@as(u32, @intCast(2 - ordinal)), current.queries.records.items[newest.next().?].value.function);
        try std.testing.expectEqual(@as(u32, @intCast(ordinal)), current.queries.records.items[oldest.next().?].value.function);
    }
    try std.testing.expect(newest.next() == null and oldest.next() == null);
    // An edit to one formerly shared source revokes its own output proof.
    try module.emitSlice(1, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var edited: retained.Capture = .{ .allocator = a };
    defer edited.deinit();
    var edited_stats: retained.Stats = .{};
    const changed = try module.assembleWithOptions(.{ .previous = &old, .current = &edited, .share_machine_code = true, .stats = &edited_stats });
    defer a.free(changed);
    const changed_fresh = try module.assembleWithOptions(.{ .share_machine_code = true });
    defer a.free(changed_fresh);
    try std.testing.expectEqualSlices(u8, changed_fresh, changed);
    try std.testing.expect(!std.mem.eql(u8, bytes, changed));
    try std.testing.expectEqual(@as(usize, 2), edited_stats.reused);
    try std.testing.expectEqual(@as(usize, 1), edited_stats.optimized);
    try std.testing.expectEqual(@as(usize, 1), edited_stats.shared);
    try std.testing.expectEqual(@as(usize, 3), edited.queries.records.items.len);
}

test "unchanged callers invalidate when transitive ownership facts change" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const escaped = try module.addGlobal(.pointer, 0, true);
    const read = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .i32_load } });
    const middle = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(middle, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = read } });
    const caller = try module.addFunction(&.{}, .i32);
    const object = try module.addLocal(caller, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = middle } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try assemble(a, &module, null, &old, &stats);
    defer a.free(before);
    try std.testing.expect(old.output(caller) != null);
    module.functions.items[read].instructions.clearRetainingCapacity();
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .global_set, .operand = escaped }, .{ .op = .local_get }, .{ .op = .i32_load } });
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    stats = .{};
    const edited = try assemble(a, &module, &old, &current, &stats);
    defer a.free(edited);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expect(current.output(caller) == null);
    var matches = try retained.Matcher.init(a, &old, &current);
    defer matches.deinit();
    try std.testing.expect(!matches.matches(caller));
    try std.testing.expect(stats.reused > 0);
}

fn failureScenario(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .local_get });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const first = try assemble(a, &module, null, &old, &stats);
    defer a.free(first);
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    const next = try assemble(a, &module, &old, &current, &stats);
    defer a.free(next);
    try std.testing.expectEqualSlices(u8, first, next);
}
test "optimized input and output publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, failureScenario, .{});
}

fn movedFunctions(a_: std.mem.Allocator, inserted: bool, changed: bool) !wasm.Module {
    var module = wasm.Module.init(a_);
    errdefer module.deinit();
    const arena = try module.ensureArena();
    if (inserted) {
        const extra = try module.addFunction(&.{}, .i32);
        try module.emit(extra, .{ .op = .i32_const, .operand = 123 });
    }
    const read = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .i32_load } });
    if (changed) try module.emitSlice(read, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    const middle = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(middle, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = read } });
    const caller = try module.addFunction(&.{}, .i32);
    const object = try module.addLocal(caller, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = middle } });
    const recursive = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(recursive, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = recursive } });
    return module;
}
fn relocationScenario(a_: std.mem.Allocator) !void {
    var module = try movedFunctions(a_, false, false);
    defer module.deinit();
    var old: retained.Capture = .{ .allocator = a_ };
    defer old.deinit();
    const before = try module.assembleWithOptions(.{ .current = &old });
    defer a_.free(before);
    for ([_]bool{ false, true }) |changed| {
        var moved = try movedFunctions(a_, true, changed);
        defer moved.deinit();
        var current: retained.Capture = .{ .allocator = a_ };
        defer current.deinit();
        var stats: retained.Stats = .{};
        const reused = try moved.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
        defer a_.free(reused);
        const fresh = try moved.assemble();
        defer a_.free(fresh);
        try std.testing.expectEqualSlices(u8, fresh, reused);
        if (!changed) try std.testing.expectEqual(module.functions.items.len, stats.reused);
        const caller = moved.functions.items.len - 2;
        var matcher = try retained.Matcher.init(a_, &old, &current);
        defer matcher.deinit();
        try std.testing.expectEqual(!changed, matcher.matches(caller));
        try std.testing.expect(matcher.matches(moved.functions.items.len - 1));
    }
}
test "optimized body relocation preserves recursive calls cleanup and transitive changes" {
    try relocationScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, relocationScenario, .{});
}

test "development tier keeps lifetime cleanup and rejects optimized body captures from another tier" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const id = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(id, .i32);
    try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    const optimized = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(optimized);
    var dev: retained.Capture = .{ .allocator = a };
    defer dev.deinit();
    var stats: retained.Stats = .{};
    const development = try module.assembleWithOptions(.{ .tier = .development, .previous = &old, .current = &dev, .stats = &stats });
    defer a.free(development);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
    try std.testing.expectEqual(.development, dev.tier);
    try std.testing.expectEqual(.development, stats.tier);
    const body = dev.output(id) orelse return error.TestUnexpectedResult;
    try std.testing.expect(for (body.instructions.items) |inst| {
        if (inst.op == .call and inst.operand == arena.recycle) break true;
    } else false);
    var next: retained.Capture = .{ .allocator = a };
    defer next.deinit();
    stats = .{};
    const reused = try module.assembleWithOptions(.{ .tier = .development, .previous = &dev, .current = &next, .stats = &stats });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, development, reused);
    try std.testing.expectEqual(module.functions.items.len, stats.reused);
    var restored: retained.Capture = .{ .allocator = a };
    defer restored.deinit();
    stats = .{};
    const back = try module.assembleWithOptions(.{ .previous = &next, .current = &restored, .stats = &stats });
    defer a.free(back);
    try std.testing.expectEqualSlices(u8, optimized, back);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
}

fn movedResources(a: std.mem.Allocator, inserted: bool, changed_import: bool) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    if (inserted) {
        const extra = try module.addFunction(&.{.f32}, .f32);
        try module.emit(extra, .{ .op = .local_get });
        _ = try module.importFunction("other", "unused", &.{}, .none);
        _ = try module.addGlobal(.f32, 0x3f800000, false);
    }
    const arena = try module.ensureArena();
    const global = try module.addGlobal(.u32, 11, false);
    var name: []const u8 = "identity";
    if (changed_import) name = "changed";
    const imported = try module.importFunction("host", name, &.{.i32}, .i32);
    const target = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(target, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 7 }, .{ .op = .i32_add } });
    const caller = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(caller, .i32);
    try module.emitSlice(caller, &.{
        .{ .op = .i32_const, .operand = 8 },          .{ .op = .call, .operand = arena.allocate },
        .{ .op = .local_set, .operand = object },     .{ .op = .local_get, .operand = object },
        .{ .op = .local_get },                        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = object },     .{ .op = .i32_load },
        .{ .op = .call_import, .operand = imported }, .{ .op = .global_get, .operand = global },
        .{ .op = .i32_add },
    });
    try module.emitReference(caller, .{ .op = .i32_const, .operand = target }, .table_function);
    try module.emit(caller, .{ .op = .call_indirect, .operand = module.functions.items[target].signature });
    try module.exportFunction(target, "target", .u32, .u32);
    try module.exportFunction(caller, "caller", .u32, .u32);
    return module;
}
fn symbolicResources(a: std.mem.Allocator) !void {
    var original = try movedResources(a, false, false);
    defer original.deinit();
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    a.free(try original.assembleWithOptions(.{ .current = &old }));
    const original_caller = original.functions.items.len - 1;
    const original_output = old.output(original_caller) orelse return error.TestUnexpectedResult;
    const saved = try a.dupe(wasm.Instruction, original_output.instructions.items);
    defer a.free(saved);
    for ([_]bool{ false, true }) |changed| {
        var moved = try movedResources(a, true, changed);
        defer moved.deinit();
        var current: retained.Capture = .{ .allocator = a };
        defer current.deinit();
        var stats: retained.Stats = .{};
        const reused = try moved.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
        defer a.free(reused);
        const fresh = try moved.assemble();
        defer a.free(fresh);
        try std.testing.expectEqualSlices(u8, fresh, reused);
        var matcher = try retained.Matcher.init(a, &old, &current);
        defer matcher.deinit();
        const caller = moved.functions.items.len - 1;
        try std.testing.expectEqual(!changed, matcher.matches(caller));
        try std.testing.expect(matcher.matches(caller - 1));
        if (!changed) try std.testing.expectEqual(original.functions.items.len, stats.reused);
        for (saved, old.output(original_caller).?.instructions.items) |before, after| try std.testing.expectEqualDeep(before, after);
    }
}
test "symbolic optimized bodies relocate imports signatures globals tables and runtime helpers on owned copies" {
    try symbolicResources(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicResources, .{});
}

test "symbolic reuse survives insertion removal and reordering of unrelated resources" {
    const a = std.testing.allocator;
    // 0: no extra resource; 1: prefix; 2: suffix. The three transitions
    // exercise insertion, reordering and removal without changing exports.
    for (0..3) |phase| {
        var before = try movedResources(a, phase == 1, false);
        defer before.deinit();
        var after = try movedResources(a, phase == 0, false);
        defer after.deinit();
        var suffix: ?*wasm.Module = null;
        if (phase == 1) suffix = &after;
        if (phase == 2) suffix = &before;
        if (suffix) |module| {
            const extra = try module.addFunction(&.{.f32}, .f32);
            try module.emit(extra, .{ .op = .local_get });
            _ = try module.importFunction("other", "unused", &.{}, .none);
            _ = try module.addGlobal(.f32, 0x3f800000, false);
        }
        var old: retained.Capture = .{ .allocator = a };
        defer old.deinit();
        a.free(try before.assembleWithOptions(.{ .current = &old }));
        var current: retained.Capture = .{ .allocator = a };
        defer current.deinit();
        var stats: retained.Stats = .{};
        const reused = try after.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
        defer a.free(reused);
        const fresh = try after.assemble();
        defer a.free(fresh);
        try std.testing.expectEqualSlices(u8, fresh, reused);
        try std.testing.expectEqual(@min(before.functions.items.len, after.functions.items.len), stats.reused);
        var matcher = try retained.Matcher.init(a, &old, &current);
        defer matcher.deinit();
        for (after.exports.items) |exported| try std.testing.expect(matcher.matches(exported.index));
    }
}

test "symbolic positional shortcut checks transitive external facts and introduced cleanup helpers" {
    const a = std.testing.allocator;
    for (0..3) |change| {
        var module = try movedResources(a, false, false);
        defer module.deinit();
        const caller = module.exports.items[1].index;
        const outer = try module.addFunction(&.{.i32}, .i32);
        try module.emitSlice(outer, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = caller } });
        var old: retained.Capture = .{ .allocator = a };
        defer old.deinit();
        a.free(try module.assembleWithOptions(.{ .current = &old }));
        const saved = try a.dupe(wasm.Instruction, old.output(caller).?.instructions.items);
        defer a.free(saved);
        switch (change) {
            0 => module.imports.items[0].name[0] = 'j',
            1 => module.globals.items[module.globals.items.len - 1].bits += 1,
            2 => {
                const recycle = module.arena.?.recycle;
                try std.testing.expect(for (saved) |inst| {
                    if (inst.op == .call and inst.operand == recycle) break true;
                } else false);
                try module.emit(recycle, .{ .op = .nop });
            },
            else => unreachable,
        }
        var current: retained.Capture = .{ .allocator = a };
        defer current.deinit();
        const reused = try module.assembleWithOptions(.{ .previous = &old, .current = &current });
        defer a.free(reused);
        const fresh = try module.assemble();
        defer a.free(fresh);
        try std.testing.expectEqualSlices(u8, fresh, reused);
        var matcher = try retained.Matcher.init(a, &old, &current);
        defer matcher.deinit();
        try std.testing.expect(!matcher.matches(caller));
        if (change != 2) try std.testing.expect(!matcher.matches(outer));
        for (saved, old.output(caller).?.instructions.items) |before, after| try std.testing.expectEqualDeep(before, after);
    }
}

test "symbolic relocation rejects conflicting maps and exhausted proofs" {
    const relocation = @import("runtime_body_relocation.zig");
    const a = std.testing.allocator;
    var walk: relocation.Walk = .{};
    defer walk.deinit(a);
    try std.testing.expect(try walk.add(a, .function, 1, 2));
    try std.testing.expect(!try walk.add(a, .function, 1, 3));
    try std.testing.expect(!try walk.add(a, .function, 3, 2));
    // Equal integer indices in distinct namespaces never alias each other.
    try std.testing.expect(try walk.add(a, .global, 1, 3));
    walk.clear();
    walk.remaining = 1;
    try std.testing.expect(try walk.add(a, .function, 1, 2));
    try std.testing.expect(!try walk.add(a, .function, 1, 2));
    walk.clear();
    try std.testing.expect(!try walk.add(a, .function, 1, 2));
}

fn duplicateTargets(a: std.mem.Allocator, split: bool) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    const first = try module.addFunction(&.{.i32}, .i32);
    try module.emit(first, .{ .op = .local_get });
    var second = first;
    if (split) {
        second = try module.addFunction(&.{.i32}, .i32);
        try module.emit(second, .{ .op = .local_get });
    }
    const caller = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = first }, .{ .op = .call, .operand = second } });
    try module.exportFunction(first, "first", .u32, .u32);
    if (split) try module.exportFunction(second, "second", .u32, .u32);
    try module.exportFunction(caller, "caller", .u32, .u32);
    return module;
}
test "symbolic body graph declines a split target while keeping duplicate public functions separate" {
    const a = std.testing.allocator;
    var original = try duplicateTargets(a, false);
    defer original.deinit();
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    a.free(try original.assembleWithOptions(.{ .current = &old }));
    var split = try duplicateTargets(a, true);
    defer split.deinit();
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: retained.Stats = .{};
    const reused = try split.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
    defer a.free(reused);
    const fresh = try split.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, reused);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
    var matcher = try retained.Matcher.init(a, &old, &current);
    defer matcher.deinit();
    try std.testing.expect(matcher.matches(0) and matcher.matches(1));
    try std.testing.expect(!matcher.matches(2));
}

test "symbolic optimizer inputs include checked parameter roles even when encoded bodies are equal" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .local_get });
    try module.setParameterRoles(id, @import("runtime_ir.zig").packParameterRoles(&.{.scalar}));
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    a.free(try module.assembleWithOptions(.{ .current = &old }));
    try module.setParameterRoles(id, @import("runtime_ir.zig").packParameterRoles(&.{.reference}));
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: retained.Stats = .{};
    const reused = try module.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
    defer a.free(reused);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, reused);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
}

fn checkLongInvalidation(a: std.mem.Allocator, old: *const retained.Capture, current: *const retained.Capture) !void {
    var matcher = try retained.Matcher.init(a, old, current);
    defer matcher.deinit();
    for (0..192) |id| try std.testing.expect(!matcher.matches(id));
    for (192..199) |id| try std.testing.expect(matcher.matches(id));
    try std.testing.expect(matcher.work <= 1_000_000);
    try std.testing.expect(matcher.candidates >= 199);
    try std.testing.expectEqual(@as(u32, 1), old.entries.items[191].source.instructions.items[1].operand);
    try std.testing.expectEqual(@as(u32, 2), current.entries.items[191].source.instructions.items[1].operand);
}

test "bounded optimizer invalidation retains unrelated bodies across long reverse call chains through OOM" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    for (0..199) |_| _ = try module.addFunction(&.{.i32}, .i32);
    for (0..191) |id| {
        try module.functions.items[id].instructions.appendNTimes(a, .{ .op = .nop }, 64);
        try module.emitSlice(@intCast(id), &.{ .{ .op = .local_get }, .{ .op = .call, .operand = @intCast(id + 1) } });
    }
    for (191..199) |id| try module.emitSlice(@intCast(id), &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = @intCast(id - 190) }, .{ .op = .i32_add } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    const before = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(before);
    try std.testing.expect(old.queries_complete);
    var unchanged: retained.Capture = .{ .allocator = a };
    defer unchanged.deinit();
    var stats: retained.Stats = .{};
    const identical = try assemble(a, &module, &old, &unchanged, &stats);
    defer a.free(identical);
    try std.testing.expectEqualSlices(u8, before, identical);
    try std.testing.expectEqual(@as(usize, 199), stats.reused);
    try std.testing.expectEqual(@as(usize, 0), stats.match_budget_exhausted);
    module.functions.items[191].instructions.items[1].operand = 2;
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    const fresh = try module.assembleWithOptions(.{ .current = &current });
    defer a.free(fresh);
    try checkLongInvalidation(a, &old, &current);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkLongInvalidation, .{ &old, &current });
    var reused: retained.Capture = .{ .allocator = a };
    defer reused.deinit();
    stats = .{};
    const changed = try assemble(a, &module, &old, &reused, &stats);
    defer a.free(changed);
    try std.testing.expectEqualSlices(u8, fresh, changed);
    try std.testing.expectEqual(@as(usize, 7), stats.reused);
    try std.testing.expectEqual(@as(usize, 192), stats.optimized);
    try std.testing.expect(stats.match_work <= 1_000_000);
    module.functions.items[191].instructions.items[1].operand = 1;
    var reverted: retained.Capture = .{ .allocator = a };
    defer reverted.deinit();
    stats = .{};
    const restored = try assemble(a, &module, &current, &reverted, &stats);
    defer a.free(restored);
    try std.testing.expectEqualSlices(u8, before, restored);
    try std.testing.expectEqual(@as(usize, 7), stats.reused);
}

fn fallbackReuse(a: std.mem.Allocator) !void {
    const ir = @import("runtime_ir.zig");
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const field = try module.addTypedFunction(&.{}, .i32, .scalar);
    const object = try module.addLocal(field, .i32);
    var annotations: [ir.max_annotations]ir.Instruction = undefined;
    try module.emitSlice(field, ir.annotations(&.{.reference}, .unknown, &annotations));
    try module.emitSlice(field, &.{
        .{ .op = .i32_const, .operand = 4 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .i32_const },                       .{ .op = .i32_store },
        .{ .op = .i32_const, .operand = 7 },
    });
    const dynamic = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(dynamic, ir.packParameterRoles(&.{.scalar}));
    try module.emitSlice(dynamic, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate } });
    const changed = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.setParameterRoles(changed, ir.packParameterRoles(&.{.scalar}));
    try module.emitSlice(changed, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    const before = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(before);
    try std.testing.expect(!old.roots and old.queries_complete);
    module.functions.items[changed].instructions.items[1].operand = 2;
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: retained.Stats = .{};
    const reused = try assemble(a, &module, &old, &current, &stats);
    defer a.free(reused);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, reused);
    try std.testing.expect(!current.roots and current.queries_complete);
    try std.testing.expectEqual(@as(usize, 1), stats.optimized);
    try std.testing.expectEqual(module.functions.items.len - 1, stats.reused);
    var matcher = try retained.Matcher.init(a, &old, &current);
    defer matcher.deinit();
    try std.testing.expect(matcher.matches(field) and matcher.matches(dynamic) and !matcher.matches(changed));
    var instructions = current.entries.items[dynamic].source.instructions.items;
    if (current.output(dynamic)) |optimized| instructions = optimized.instructions.items;
    var heap = false;
    for (instructions) |inst| if (inst.op == .call and inst.operand == arena.allocate) {
        heap = true;
    };
    try std.testing.expect(heap);
}
test "late ordinary fallback reuses matching plain bodies while retaining owning storage through OOM" {
    try fallbackReuse(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, fallbackReuse, .{});
}
