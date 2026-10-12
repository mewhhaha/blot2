//! Function roots lower after typed publication and lifetime release. A single
//! result block makes explicit returns and branches to the function share one
//! epilogue. Root operations remain guarded until whole-module admission.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const w = @import("wasm.zig");
const A = std.mem.Allocator;

// A thin direct forwarder acquires exactly the source callee's result marker.
// That marker already belongs to its caller when this wrapper has no frame.
// The sole discard exit consumes it explicitly; no ancestor-root assumption
// or borrowed-result ownership omission participates in this proof.
const Forward = struct { call: usize, discard: ?usize = null };
fn forwarded(module: *const w.Module, source: *const ir.Function) ?Forward {
    if (source.result != .i32 or source.result_role != .reference) return null;
    for (source.instructions.items, 0..) |inst, at| switch (inst.op) {
        .local_get, .i32_const, .f32_const, .i32_load, .f32_load => {},
        .call => {
            if (module.runtimeHelper(inst.operand)) return null;
            const callee = &module.functions.items[inst.operand];
            if (callee.entry or callee.result != .i32 or callee.result_role != .reference) return null;
            const tail = source.instructions.items[at + 1 ..];
            if (tail.len == 0 or (tail.len == 1 and tail[0].op == .return_)) return .{ .call = at };
            if (tail.len != 5 or tail[0].op != .global_get or tail[1].op != .if_ or tail[1].operand != 0 or tail[2].op != .i32_const or tail[2].operand != 0 or tail[2].table_reference or tail[3].op != .return_ or tail[4].op != .end) return null;
            const guard = module.globals.items[tail[0].operand];
            if (guard.scalar.role() != .scalar or guard.scalar.machine() != .i32) return null;
            return .{ .call = at, .discard = at + 4 };
        },
        else => return null,
    };
    return null;
}

fn acquires(module: *const w.Module, inst: ir.Instruction) bool {
    switch (inst.op) {
        .call_import, .call_indirect => return true,
        .call => {
            const arena = module.arena.?;
            inline for (.{ "retain", "release", "release_lease", "decrement", "retire", "free", "recycle", "store_word", "copy_words", "cycle_enqueue", "cycle_unlink", "cycle_visit", "cycle_collect", "cycle_safe", "mark", "collect", "reset" }) |field| {
                if (inst.operand == @field(arena, field)) return false;
            }
            return true;
        },
        .ownership => {
            const fact: ir.Ownership = @bitCast(inst.operand);
            return fact.kind == .call_result or (fact.kind == .scope and fact.chunk != 14);
        },
        else => return false,
    }
}
// Every owning operation must be conditional. Unbounded control nesting and
// unconditional acquisitions retain the ordinary eager frame.
fn conditional(module: *const w.Module, source: *const ir.Function) bool {
    var controls: [128]bool = undefined;
    var depth: usize = 0;
    var branches: usize = 0;
    var found = false;
    for (source.instructions.items) |inst| {
        if (acquires(module, inst)) {
            if (branches == 0) return false;
            found = true;
        }
        switch (inst.op) {
            .block, .loop, .if_ => {
                if (depth == controls.len) return false;
                controls[depth] = inst.op == .if_;
                branches += @intFromBool(controls[depth]);
                depth += 1;
            },
            .end => {
                if (depth == 0) return false;
                depth -= 1;
                branches -= @intFromBool(controls[depth]);
            },
            else => {},
        }
    }
    return found and depth == 0;
}

pub fn run(a: A, module: *const w.Module, source: *const ir.Function, framed: bool, entry: bool, start: bool) A.Error!?ir.Body {
    const arena = module.arena orelse return null;
    const forward = if (framed and !entry and !start) forwarded(module, source) else null;
    const frame = framed and forward == null;
    const lazy = frame and !entry and !start and conditional(module, source);
    var changes = framed;
    for (source.instructions.items) |inst| if (inst.op == .call and inst.operand == arena.allocate_typed) {
        changes = true;
        break;
    };
    if (!changes) return null;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    const result: u32 = @intCast(source.parameters.len + out.locals.items.len);
    const automatic = result + @intFromBool(source.result != .none);
    const array_parameter = entry and source.parameters.len != 0 and source.parameterRole(0) == .reference;
    if ((frame and source.result != .none) or (forward != null and forward.?.discard != null)) try out.locals.append(a, source.result);
    if (entry) try out.locals.append(a, .i32);
    const publication: u32 = @intCast(source.parameters.len + out.locals.items.len);
    var global_stores = false;
    for (source.instructions.items) |inst| {
        if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and inst.operand != arena.root_globals) global_stores = true;
    }
    if (global_stores) try out.locals.append(a, .i32);
    const activated: u32 = @intCast(source.parameters.len + out.locals.items.len);
    if (lazy) try out.locals.append(a, .i32);
    if (start) {
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        try out.emit(a, .i32_const, @intCast((module.globals.items.len + module.static_fields.items.len) * 4));
        try out.emit(a, .i32_const, std.math.maxInt(u32));
        try out.emit(a, .call, arena.root_allocate);
        try out.emit(a, .global_set, arena.root_globals);
        try out.emit(a, .end, 0);
    }
    if (frame) {
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        if (entry) {
            // Raw scalar callers retain their existing trap-recovery behavior.
            // ABI-aware callers enter externally and own exceptional cleanup.
            if (!array_parameter) {
                try out.emit(a, .global_get, arena.root_active);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .global_get, arena.root_external);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .global_get, arena.root_started);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .if_, 0);
                try out.emit(a, .i32_const, 1);
                try out.emit(a, .call, arena.root_leave);
                try out.emit(a, .end, 0);
            }
            try out.emit(a, .global_get, arena.root_active);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .if_, 0);
            try out.emit(a, .call, arena.root_enter);
            try out.emit(a, .i32_const, 0);
            try out.emit(a, .global_set, arena.root_external);
            try out.emit(a, .end, 0);
            try out.emit(a, .global_get, arena.root_external);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .local_set, automatic);
            try out.emit(a, .i32_const, 1);
            try out.emit(a, .global_set, arena.root_started);
        }
        if (!lazy) {
            try out.emit(a, .call, arena.root_open);
            try out.emit(a, .drop, 0);
        }
        try out.emit(a, .end, 0);
        try out.emit(a, .block, if (source.result == .none) 0 else @backingInt(source.result));
    }
    var depth: u32 = 0;
    for (source.instructions.items, 0..) |instruction, at| {
        var inst = instruction;
        var activate = lazy and acquires(module, inst);
        if (inst.op == .call_indirect and at != 0 and source.instructions.items[at - 1].op == .ownership) {
            const fact: ir.Ownership = @bitCast(source.instructions.items[at - 1].operand);
            if (fact.kind == .call_result) activate = false;
        }
        if (activate) {
            try out.emit(a, .global_get, arena.root_enabled);
            try out.emit(a, .if_, 0);
            try out.emit(a, .local_get, activated);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .if_, 0);
            try out.emit(a, .call, arena.root_open);
            try out.emit(a, .local_set, activated);
            try out.emit(a, .end, 0);
            try out.emit(a, .end, 0);
        }
        if (forward) |proof| if (proof.discard != null and at == proof.discard.?) {
            try out.emit(a, .global_get, arena.root_enabled);
            try out.emit(a, .if_, 0);
            try out.emit(a, .local_get, result);
            try out.emit(a, .global_get, arena.static_end);
            try out.emit(a, .i32_ge_u, 0);
            try out.emit(a, .if_, 0);
            try out.emit(a, .call, arena.root_pop);
            try out.emit(a, .drop, 0);
            try out.emit(a, .end, 0);
            try out.emit(a, .end, 0);
        };
        if (inst.op == .ownership) {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind == .scope) {
                if (scope.chunk == 14) continue;
                try out.emit(a, .global_get, arena.root_enabled);
                try out.emit(a, .if_, 0);
                switch (scope.chunk) {
                    0 => {
                        try out.emit(a, .call, arena.root_open);
                        try out.emit(a, .drop, 0);
                    },
                    1, 2 => {
                        if (scope.chunk == 2) try out.emit(a, .local_get, scope.roles) else try out.emit(a, .i32_const, 0);
                        try out.emit(a, .call, arena.root_close);
                    },
                    3 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_set, scope.roles);
                    },
                    4 => {
                        try out.emit(a, .local_get, scope.roles & 8191);
                        try out.emit(a, .local_get, scope.roles >> 13);
                        try out.emit(a, .call, arena.root_store);
                    },
                    6 => {
                        try out.emit(a, .local_get, scope.roles);
                        try out.emit(a, .call, arena.root_force);
                    },
                    5 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_get, scope.roles);
                        try out.emit(a, .call, arena.root_store);
                    },
                    else => unreachable,
                }
                try out.emit(a, .end, 0);
                continue;
            }
        }
        if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and inst.operand != arena.root_globals) {
            try out.emit(a, .local_tee, publication);
            try out.emit(a, .global_get, arena.root_enabled);
            try out.emit(a, .if_, 0);
            try out.emit(a, .global_get, arena.root_globals);
            try out.emit(a, .global_get, arena.root_globals);
            try out.emit(a, .i32_const, inst.operand * 4);
            try out.emit(a, .i32_add, 0);
            try out.emit(a, .local_get, publication);
            try out.emit(a, .call, arena.store_word);
            try out.emit(a, .end, 0);
        }
        switch (inst.op) {
            .block, .loop, .if_ => depth += 1,
            .end => depth -= 1,
            .return_ => if (frame) {
                inst.op = .br;
                inst.operand = depth;
            },
            .call => if (inst.operand == arena.allocate_typed) {
                inst.operand = arena.root_allocate;
            },
            else => {},
        }
        try out.instructions.append(a, inst);
        if (forward) |proof| if (proof.discard != null and at == proof.call) try out.emit(a, .local_tee, result);
    }
    if (frame) {
        try out.emit(a, .end, 0);
        if (source.result != .none) try out.emit(a, .local_set, result);
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        if (lazy) {
            try out.emit(a, .local_get, activated);
            try out.emit(a, .if_, 0);
        }
        if (source.result_role == .reference) try out.emit(a, .local_get, result) else try out.emit(a, .i32_const, 0);
        try out.emit(a, .call, arena.root_close);
        if (lazy) {
            try out.emit(a, .else_, 0);
            if (source.result_role == .reference) {
                try out.emit(a, .local_get, result);
                try out.emit(a, .global_get, arena.static_end);
                try out.emit(a, .i32_ge_u, 0);
                try out.emit(a, .if_, 0);
                try out.emit(a, .call, arena.root_reserve);
                try out.emit(a, .local_get, result);
                try out.emit(a, .call, arena.root_store);
                try out.emit(a, .end, 0);
            }
            try out.emit(a, .global_get, arena.cycle_head);
            try out.emit(a, .if_, 0);
            try out.emit(a, .i32_const, 0);
            try out.emit(a, .call, arena.cycle_safe);
            try out.emit(a, .end, 0);
            try out.emit(a, .end, 0);
        }
        if (entry and !array_parameter and source.result_role != .reference) {
            try out.emit(a, .local_get, automatic);
            try out.emit(a, .if_, 0);
            try out.emit(a, .i32_const, 0);
            try out.emit(a, .call, arena.root_leave);
            try out.emit(a, .end, 0);
        }
        try out.emit(a, .end, 0);
        if (source.result != .none) try out.emit(a, .local_get, result);
    }
    return out;
}

fn ownership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const source = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(source, &.{
        .{ .op = .i32_const, .operand = 4 },               .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .return_ },
        .{ .op = .i32_const },
    });
    const before = try a.dupe(ir.Instruction, module.functions.items[source].instructions.items);
    defer a.free(before);
    var body = (try run(a, &module, &module.functions.items[source], true, false, false)).?;
    defer body.deinit(a);
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[source].instructions.items);
    for (body.instructions.items) |inst| try std.testing.expect(inst.op != .return_);
    const result = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emitSlice(result, &.{ .{ .op = .call, .operand = source }, .{ .op = .i32_load } });
    try module.exportFunction(result, "run", .unit, .u32);
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .tier = .development, .current = &capture });
    defer a.free(bytes);
    try std.testing.expect(capture.roots);
    const marker = (std.mem.findLast(u8, bytes, "blot:ownership") orelse return error.TestExpectedRootManifest) + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[marker..][0..3]);
    try std.testing.expect(std.mem.find(u8, bytes, "blot:ownership_enter") != null);
}
test "typed function root lowering owns early returns and preserves inputs through OOM" {
    try ownership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}

fn forwarding(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const guard = try module.addGlobal(.bool, 0, true);
    const producer = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    module.functions.items[producer].parameter_roles = ir.packParameterRoles(&.{.scalar});
    const value = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 8 },     .{ .op = .i32_const },               .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .local_set, .operand = value },
        .{ .op = .local_get, .operand = value }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_store },                             .{ .op = .local_get, .operand = value },
        .{ .op = .local_get },                   .{ .op = .i32_store, .operand = 4 }, .{ .op = .local_get, .operand = value },
    });
    const wrapper = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    module.functions.items[wrapper].parameter_roles = ir.packParameterRoles(&.{.scalar});
    try module.emitSlice(wrapper, &.{
        .{ .op = .local_get }, .{ .op = .call, .operand = producer }, .{ .op = .global_get, .operand = guard },
        .{ .op = .if_ },       .{ .op = .i32_const },                 .{ .op = .return_ },
        .{ .op = .end },
    });
    const original = try a.dupe(ir.Instruction, module.functions.items[wrapper].instructions.items);
    defer a.free(original);
    try std.testing.expectEqual(Forward{ .call = 1, .discard = 5 }, forwarded(&module, &module.functions.items[wrapper]).?);
    var body = (try run(a, &module, &module.functions.items[wrapper], true, false, false)).?;
    defer body.deinit(a);
    var discards: usize = 0;
    for (body.instructions.items) |inst| if (inst.op == .call) {
        try std.testing.expect(inst.operand != arena.root_open and inst.operand != arena.root_close);
        if (inst.operand == arena.root_pop) discards += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), discards);
    try std.testing.expectEqualSlices(ir.Instruction, original, module.functions.items[wrapper].instructions.items);
    // Nonforwarding exits, independent owners, mutations and unknown callees
    // must keep the wrapper's own retirement boundary.
    for ([_]ir.Instruction{
        .{ .op = .local_tee },     .{ .op = .call, .operand = producer }, .{ .op = .i32_store },
        .{ .op = .call_indirect }, .{ .op = .call_import },               .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 5 }) },
    }) |replacement| {
        module.functions.items[wrapper].instructions.items[0] = replacement;
        try std.testing.expect(forwarded(&module, &module.functions.items[wrapper]) == null);
    }
    module.functions.items[wrapper].instructions.items[0] = original[0];
    module.functions.items[wrapper].instructions.items[1].operand = arena.root_allocate;
    try std.testing.expect(forwarded(&module, &module.functions.items[wrapper]) == null);
    module.functions.items[wrapper].instructions.items[1] = original[1];
    module.functions.items[producer].entry = true;
    try std.testing.expect(forwarded(&module, &module.functions.items[wrapper]) == null);
    module.functions.items[producer].entry = false;
    module.functions.items[producer].result_role = .unknown;
    try std.testing.expect(forwarded(&module, &module.functions.items[wrapper]) == null);
    module.functions.items[producer].result_role = .reference;
    module.functions.items[wrapper].instructions.items[4].operand = 1;
    try std.testing.expect(forwarded(&module, &module.functions.items[wrapper]) == null);
    module.functions.items[wrapper].instructions.items[4] = original[4];
    const consumer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    module.functions.items[consumer].parameter_roles = ir.packParameterRoles(&.{.scalar});
    try module.emitSlice(consumer, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = wrapper }, .{ .op = .i32_load, .operand = 4 } });
    try module.exportFunction(consumer, "run", .u32, .u32);
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .tier = .development, .current = &capture });
    defer a.free(bytes);
    var retained: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer retained.deinit();
    const reused = try module.assembleWithOptions(.{ .tier = .development, .current = &retained, .previous = &capture });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, bytes, reused);
    const archive = @import("optimized_archive.zig");
    const compiler: [32]u8 = @splat(35);
    const saved = try archive.encode(a, compiler, &capture);
    defer a.free(saved);
    var loaded = try archive.decode(a, compiler, saved);
    defer loaded.deinit();
    var restarted: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer restarted.deinit();
    const replayed = try module.assembleWithOptions(.{ .tier = .development, .current = &restarted, .previous = &loaded });
    defer a.free(replayed);
    try std.testing.expectEqualSlices(u8, bytes, replayed);
    // The source callee's entry fact participates in the exact graph proof.
    // Changing it restores this wrapper's independent frame, including replay.
    module.functions.items[producer].entry = true;
    const changed = try module.assembleWithOptions(.{ .tier = .development });
    defer a.free(changed);
    var after: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer after.deinit();
    const changed_replay = try module.assembleWithOptions(.{ .tier = .development, .current = &after, .previous = &loaded });
    defer a.free(changed_replay);
    try std.testing.expect(!std.mem.eql(u8, bytes, changed));
    try std.testing.expectEqualSlices(u8, changed, changed_replay);
}
test "direct reference forwarders preserve sole result ownership and discard exits through OOM" {
    try forwarding(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, forwarding, .{});
}

fn conditionalOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const select = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .reference);
    module.functions.items[select].parameter_roles = ir.packParameterRoles(&.{ .reference, .scalar });
    const value = try module.addLocal(select, .i32);
    try module.emitSlice(select, &.{
        .{ .op = .local_get, .operand = 1 },               .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 8 },               .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .local_set, .operand = value },
        .{ .op = .local_get, .operand = value },           .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_store },                             .{ .op = .local_get, .operand = value },
        .{ .op = .i32_const, .operand = 77 },              .{ .op = .i32_store, .operand = 4 },
        .{ .op = .local_get, .operand = value },           .{ .op = .return_ },
        .{ .op = .end },                                   .{ .op = .local_get },
        .{ .op = .return_ },
    });
    try std.testing.expect(conditional(&module, &module.functions.items[select]));
    const original = try a.dupe(ir.Instruction, module.functions.items[select].instructions.items);
    defer a.free(original);
    var lowered = (try run(a, &module, &module.functions.items[select], true, false, false)).?;
    defer lowered.deinit(a);
    // The allocating branch opens a marker. The early borrowed return instead
    // publishes its own counted result slot; neither route borrows an owner.
    var opens: usize = 0;
    var publications: usize = 0;
    for (lowered.instructions.items) |inst| {
        try std.testing.expect(inst.op != .return_);
        if (inst.op == .call and inst.operand == arena.root_open) opens += 1;
        if (inst.op == .call and inst.operand == arena.root_store) publications += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), opens);
    try std.testing.expectEqual(@as(usize, 1), publications);
    try std.testing.expectEqualSlices(ir.Instruction, original, module.functions.items[select].instructions.items);
    // Unconditional calls and unknown routes keep an eager frame. The helper
    // identity is exact: a no-slot retain cannot stand in for an allocator.
    try std.testing.expect(!acquires(&module, .{ .op = .call, .operand = arena.retain }));
    try std.testing.expect(acquires(&module, .{ .op = .call, .operand = arena.allocate_typed }));
    try std.testing.expect(acquires(&module, .{ .op = .call_import }));
    try std.testing.expect(acquires(&module, .{ .op = .call_indirect }));
    module.functions.items[select].instructions.items[0] = .{ .op = .call, .operand = arena.allocate_typed };
    try std.testing.expect(!conditional(&module, &module.functions.items[select]));
    module.functions.items[select].instructions.items[0] = original[0];
    const consumer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    module.functions.items[consumer].parameter_roles = ir.packParameterRoles(&.{.scalar});
    const input = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .i32_const, .operand = 8 },     .{ .op = .i32_const },               .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .local_set, .operand = input },
        .{ .op = .local_get, .operand = input }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_store },                             .{ .op = .local_get, .operand = input },
        .{ .op = .i32_const, .operand = 41 },    .{ .op = .i32_store, .operand = 4 }, .{ .op = .local_get, .operand = input },           .{ .op = .local_get },
        .{ .op = .call, .operand = select },     .{ .op = .i32_load, .operand = 4 },
    });
    try module.exportFunction(consumer, "run", .u32, .u32);
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .tier = .development, .current = &capture });
    defer a.free(bytes);
    var retained: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer retained.deinit();
    const reused = try module.assembleWithOptions(.{ .tier = .development, .current = &retained, .previous = &capture });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, bytes, reused);
    const archive = @import("optimized_archive.zig");
    const compiler: [32]u8 = @splat(36);
    const saved = try archive.encode(a, compiler, &capture);
    defer a.free(saved);
    var loaded = try archive.decode(a, compiler, saved);
    defer loaded.deinit();
    const restarted = try module.assembleWithOptions(.{ .tier = .development, .previous = &loaded });
    defer a.free(restarted);
    try std.testing.expectEqualSlices(u8, bytes, restarted);
    // Entry admission forces an eager frame, and portable reuse must follow it.
    module.functions.items[select].entry = true;
    const changed = try module.assembleWithOptions(.{ .tier = .development });
    defer a.free(changed);
    const replayed = try module.assembleWithOptions(.{ .tier = .development, .previous = &loaded });
    defer a.free(replayed);
    try std.testing.expect(!std.mem.eql(u8, bytes, changed));
    try std.testing.expectEqualSlices(u8, changed, replayed);
}
test "conditional frames publish borrowed early returns and preserve admission through OOM" {
    try conditionalOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, conditionalOwnership, .{});
}
