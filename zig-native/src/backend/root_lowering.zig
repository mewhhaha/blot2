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
// These getters read a caller-owned graph and have no operation that can
// acquire, retire, suspend or publish an owner. Their checked result role
// distinguishes a reference field from an i32 scalar field. The returned
// reference still gets its own caller slot; only the empty callee frame goes.
fn getter(module: *const w.Module, source: *const ir.Function) bool {
    if (source.result != .i32 or source.result_role != .reference or source.parameters.len > 64 or source.locals.items.len > 64 - source.parameters.len) return false;
    var locals: [64]bool = @splat(false);
    for (source.parameters, 0..) |machine, index| locals[index] = machine == .i32 and source.parameterRole(index) == .reference;
    var stack: [64]bool = undefined;
    var height: usize = 0;
    var at: usize = 0;
    while (at < source.instructions.items.len) : (at += 1) {
        const inst = source.instructions.items[at];
        // The exact request guard can only return the null reference. It
        // changes no owner; every surviving return reaches publication below.
        if (inst.op == .global_get and source.instructions.items.len - at >= 5 and inst.operand < module.globals.items.len) {
            const tail = source.instructions.items[at + 1 ..][0..4];
            const global = module.globals.items[inst.operand];
            if (global.scalar.role() == .scalar and global.scalar.machine() == .i32 and tail[0].op == .if_ and tail[0].operand == 0 and
                tail[1].op == .i32_const and tail[1].operand == 0 and !tail[1].table_reference and tail[2].op == .return_ and tail[3].op == .end)
            {
                at += 4;
                continue;
            }
        }
        switch (inst.op) {
            .local_get => {
                if (inst.operand >= source.parameters.len + source.locals.items.len or height == stack.len) return false;
                stack[height] = locals[inst.operand];
                height += 1;
            },
            .i32_const => {
                if (height == stack.len) return false;
                stack[height] = !inst.table_reference and inst.operand < module.globals.items[module.arena.?.static_end].bits;
                height += 1;
            },
            .local_set, .local_tee => {
                if (height == 0 or inst.operand >= source.parameters.len + source.locals.items.len) return false;
                locals[inst.operand] = stack[height - 1];
                if (inst.op == .local_set) height -= 1;
            },
            .i32_load => if (height == 0 or !stack[height - 1]) return false,
            .drop => {
                if (height == 0) return false;
                height -= 1;
            },
            .ownership => {
                const fact: ir.Ownership = @bitCast(inst.operand);
                if (fact.kind == .scope or fact.kind == .call_result) return false;
            },
            .return_ => if (at + 1 != source.instructions.items.len) return false,
            .nop => {},
            else => return false,
        }
    }
    return height == 1 and stack[0];
}
fn forwarded(module: *const w.Module, source: *const ir.Function) ?Forward {
    if (source.result != .i32 or source.result_role != .reference) return null;
    var stack: [64]ir.ValueType = undefined;
    var height: usize = 0;
    for (source.instructions.items, 0..) |inst, at| switch (inst.op) {
        .local_get => {
            if (inst.operand >= source.parameters.len + source.locals.items.len or height == stack.len) return null;
            stack[height] = if (inst.operand < source.parameters.len) source.parameters[inst.operand] else source.locals.items[inst.operand - source.parameters.len];
            height += 1;
        },
        .local_set, .local_tee => {
            if (height == 0 or inst.operand >= source.parameters.len + source.locals.items.len) return null;
            const machine = if (inst.operand < source.parameters.len) source.parameters[inst.operand] else source.locals.items[inst.operand - source.parameters.len];
            if (stack[height - 1] != machine) return null;
            if (inst.op == .local_set) height -= 1;
        },
        .i32_const, .f32_const => {
            if (height == stack.len) return null;
            stack[height] = if (inst.op == .f32_const) .f32 else .i32;
            height += 1;
        },
        .i32_load, .f32_load => {
            if (height == 0 or stack[height - 1] != .i32) return null;
            stack[height - 1] = if (inst.op == .f32_load) .f32 else .i32;
        },
        .ownership => if (!ir.hasImmortalReference(source.instructions.items, at + 1)) return null,
        .call => {
            if (inst.operand >= module.functions.items.len) return null;
            if (module.runtimeHelper(inst.operand)) return null;
            const callee = &module.functions.items[inst.operand];
            if (callee.entry or callee.result != .i32 or callee.result_role != .reference) return null;
            if (height != callee.parameters.len or !std.mem.eql(ir.ValueType, stack[0..height], callee.parameters)) return null;
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
            inline for (.{ "retain", "release", "release_lease", "decrement", "retire", "free", "recycle", "store_word", "copy_words", "cycle_enqueue", "cycle_unlink", "cycle_visit", "cycle_collect", "cycle_safe", "reset" }) |field| {
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

fn pureProjection(source: *const ir.Function) bool {
    if ((source.result != .i32 and source.result != .f32) or (source.result_role != .reference and source.result_role != .scalar)) return false;
    for (source.instructions.items) |inst| switch (inst.op) {
        .local_get, .local_set, .local_tee, .i32_const, .i32_load, .f32_load, .i32_eq, .i32_eqz, .drop, .block, .loop, .if_, .else_, .end, .br, .br_if, .unreachable_, .nop => {},
        .ownership => {
            const marker: ir.Ownership = @bitCast(inst.operand);
            if (marker.kind == .scope or marker.kind == .call_result) return false;
        },
        else => return false,
    };
    return true;
}
pub fn run(a: A, module: *const w.Module, source: *const ir.Function, framed: bool, entry: bool, start: bool) A.Error!?ir.Body {
    return runBorrowed(a, module, source, framed, entry, start, false);
}
// A completed provider catalog supplies a pure State field projection. Its
// caller slot remains published by the ordinary borrowed-result epilogue.
pub fn runBorrowed(a: A, module: *const w.Module, source: *const ir.Function, framed: bool, entry: bool, start: bool, provider_borrow: bool) A.Error!?ir.Body {
    return runScoped(a, module, source, framed, entry, start, provider_borrow, null);
}
pub fn runScoped(a: A, module: *const w.Module, source: *const ir.Function, framed: bool, entry: bool, start: bool, provider_borrow: bool, owner: ?u32) A.Error!?ir.Body {
    const arena = module.arena orelse return null;
    const forward = if (framed and !entry and !start) forwarded(module, source) else null;
    const borrowed = framed and !entry and !start and ((provider_borrow and pureProjection(source)) or getter(module, source));
    const frame = framed and forward == null and !borrowed;
    const lazy = frame and !entry and !start and conditional(module, source);
    var changes = framed;
    for (source.instructions.items) |inst| if (inst.op == .call and inst.operand == arena.allocate_typed) {
        changes = true;
        break;
    };
    if (!changes) return null;
    const empty = try @import("empty_root_scopes.zig").prove(a, module, source);
    defer if (empty) |actions| a.free(actions);
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    try out.instructions.ensureTotalCapacity(a, source.instructions.items.len);
    const result: u32 = @intCast(source.parameters.len + out.locals.items.len);
    const automatic = result + @intFromBool(source.result != .none);
    const array_parameter = entry and source.parameters.len != 0 and source.parameterRole(0) == .reference;
    if (((frame or borrowed) and source.result != .none) or (forward != null and forward.?.discard != null)) try out.locals.append(a, source.result);
    if (entry) try out.locals.append(a, .i32);
    // The externally entered, first public call can use its invocation frame.
    // Plain-object destruction stays before leave; host result copying happens
    // while that exact frame is live. Resource return safepoints stay distinct.
    const coalesced = entry and module.resourceCount() == 0;
    const invocation: u32 = @intCast(source.parameters.len + out.locals.items.len);
    if (coalesced) try out.locals.append(a, .i32);
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
            if (coalesced) {
                try out.emit(a, .global_get, arena.root_external);
                try out.emit(a, .global_get, arena.root_started);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .global_get, arena.root_frame);
                try out.emit(a, .global_get, arena.root_active);
                try out.emit(a, .i32_const, ~@as(u32, 3));
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .i32_eq, 0);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .local_set, invocation);
            }
            try out.emit(a, .i32_const, 1);
            try out.emit(a, .global_set, arena.root_started);
        }
        if (!lazy) {
            if (coalesced) {
                try out.emit(a, .local_get, invocation);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .if_, 0);
            }
            try out.emit(a, .call, arena.root_open);
            try out.emit(a, .drop, 0);
            if (coalesced) try out.emit(a, .end, 0);
        }
        try out.emit(a, .end, 0);
        try out.emit(a, .block, if (source.result == .none) 0 else @backingInt(source.result));
    }
    if (borrowed) try out.emit(a, .block, @backingInt(source.result));
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
                if (empty) |actions| switch (actions[at]) {
                    .open => continue,
                    .close => {
                        // An empty close still has the original collector safe
                        // point, after restoring the same enclosing frame.
                        try out.emit(a, .global_get, arena.root_enabled);
                        try out.emit(a, .if_, 0);
                        try out.emit(a, .global_get, arena.cycle_head);
                        try out.emit(a, .if_, 0);
                        try out.emit(a, .i32_const, 0);
                        try out.emit(a, .call, arena.cycle_safe);
                        try out.emit(a, .end, 0);
                        try out.emit(a, .end, 0);
                        continue;
                    },
                    .keep => {},
                };
                try out.emit(a, .global_get, arena.root_enabled);
                try out.emit(a, .if_, 0);
                switch (scope.chunk) {
                    0 => {
                        try out.emit(a, .call, arena.root_open);
                        try out.emit(a, .drop, 0);
                    },
                    1, 2 => {
                        if (scope.chunk == 2) try out.emit(a, .local_get, scope.roles) else try out.emit(a, .i32_const, 0);
                        if (owner != null and scope.chunk == 2) {
                            try out.emit(a, .local_get, owner.?);
                            try out.emit(a, .call, module.regions.?.runtime.close);
                        } else try out.emit(a, .call, arena.root_close);
                    },
                    3 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_set, scope.roles);
                    },
                    4 => {
                        try out.emit(a, .local_get, scope.roles & 8191);
                        try out.emit(a, .local_get, scope.roles >> 13);
                        if (owner) |parameter| {
                            try out.emit(a, .local_get, parameter);
                            try out.emit(a, .call, module.regions.?.runtime.store);
                        } else try out.emit(a, .call, arena.root_store);
                    },
                    6 => {
                        try out.emit(a, .local_get, scope.roles);
                        if (owner) |parameter| {
                            try out.emit(a, .local_get, parameter);
                            try out.emit(a, .call, module.regions.?.runtime.force);
                        } else try out.emit(a, .call, arena.root_force);
                    },
                    5 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_get, scope.roles);
                        if (owner) |parameter| {
                            try out.emit(a, .local_get, parameter);
                            try out.emit(a, .call, module.regions.?.runtime.store);
                        } else try out.emit(a, .call, arena.root_store);
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
            .return_ => if (frame or borrowed) {
                inst.op = .br;
                inst.operand = depth;
            },
            .call => if (inst.operand == arena.allocate_typed) {
                inst.operand = arena.root_allocate;
            } else if (inst.operand == arena.allocate_shaped) {
                inst.operand = arena.root_allocate_shaped;
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
        if (coalesced) {
            try out.emit(a, .local_get, invocation);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .if_, 0);
        }
        if (source.result_role == .reference) try out.emit(a, .local_get, result) else try out.emit(a, .i32_const, 0);
        if (owner != null and source.result_role == .reference) {
            try out.emit(a, .local_get, owner.?);
            try out.emit(a, .call, module.regions.?.runtime.close);
        } else try out.emit(a, .call, arena.root_close);
        if (coalesced) try out.emit(a, .end, 0);
        if (lazy) {
            try out.emit(a, .else_, 0);
            if (source.result_role == .reference) {
                try out.emit(a, .local_get, result);
                try out.emit(a, .global_get, arena.static_end);
                try out.emit(a, .i32_ge_u, 0);
                try out.emit(a, .if_, 0);
                try out.emit(a, .call, arena.root_reserve);
                try out.emit(a, .local_get, result);
                if (owner) |parameter| {
                    try out.emit(a, .local_get, parameter);
                    try out.emit(a, .call, module.regions.?.runtime.store);
                } else try out.emit(a, .call, arena.root_store);
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
    if (borrowed) {
        try out.emit(a, .end, 0);
        try out.emit(a, .local_set, result);
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        if (source.result_role == .reference) {
            try out.emit(a, .local_get, result);
            try out.emit(a, .global_get, arena.static_end);
            try out.emit(a, .i32_ge_u, 0);
            try out.emit(a, .if_, 0);
            try out.emit(a, .call, arena.root_reserve);
            try out.emit(a, .local_get, result);
            if (owner) |parameter| {
                try out.emit(a, .local_get, parameter);
                try out.emit(a, .call, module.regions.?.runtime.store);
            } else try out.emit(a, .call, arena.root_store);
            try out.emit(a, .end, 0);
        }
        // The former close safe point follows publication, with the same
        // caller frame and live result owner even if it collects a cycle.
        try out.emit(a, .global_get, arena.cycle_head);
        try out.emit(a, .if_, 0);
        try out.emit(a, .i32_const, 0);
        try out.emit(a, .call, arena.cycle_safe);
        try out.emit(a, .end, 0);
        try out.emit(a, .end, 0);
        try out.emit(a, .local_get, result);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}

fn emptyLexical(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const value = try module.addLocal(function, .i32);
    const open: ir.Instruction = .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 0 }) };
    const close: ir.Instruction = .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 1 }) };
    try module.emitSlice(function, &.{ open, .{ .op = .local_get }, .{ .op = .i32_load }, .{ .op = .local_set, .operand = value }, close, .{ .op = .local_get, .operand = value } });
    const source = &module.functions.items[function];
    const original = try a.dupe(ir.Instruction, source.instructions.items);
    defer a.free(original);
    var output = (try run(a, &module, source, true, true, false)).?;
    defer output.deinit(a);
    var opens: usize = 0;
    var closes: usize = 0;
    var safe: usize = 0;
    for (output.instructions.items) |inst| if (inst.op == .call) {
        if (inst.operand == arena.root_open) opens += 1;
        if (inst.operand == arena.root_close) closes += 1;
        if (inst.operand == arena.cycle_safe) safe += 1;
    };
    // Only the lexical empty frame goes. The public function still establishes
    // its invocation frame; the original close collector boundary survives.
    try std.testing.expectEqual(@as(usize, 1), opens);
    try std.testing.expectEqual(@as(usize, 1), closes);
    try std.testing.expectEqual(@as(usize, 1), safe);
    try std.testing.expectEqualSlices(ir.Instruction, original, source.instructions.items);
}
test "empty lexical lowering retains public entry authority and collector boundaries through OOM" {
    try emptyLexical(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, emptyLexical, .{});
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
    const archive = @import("../reuse/optimized_archive.zig");
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, forwarding, .{});
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
    const archive = @import("../reuse/optimized_archive.zig");
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, conditionalOwnership, .{});
}

fn getterOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const read = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(read, ir.packParameterRoles(&.{.reference}));
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .i32_load, .operand = 4 }, .{ .op = .return_ } });
    try std.testing.expect(getter(&module, &module.functions.items[read]));
    var body = (try run(a, &module, &module.functions.items[read], true, false, false)).?;
    defer body.deinit(a);
    var publications: usize = 0;
    for (body.instructions.items) |inst| if (inst.op == .call) {
        try std.testing.expect(inst.operand != arena.root_open and inst.operand != arena.root_close);
        if (inst.operand == arena.root_store) publications += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), publications);
    const guard = try module.addGlobal(.u32, 0, true);
    const guarded = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(guarded, ir.packParameterRoles(&.{.reference}));
    try module.emitSlice(guarded, &.{ .{ .op = .local_get }, .{ .op = .i32_load, .operand = 4 }, .{ .op = .global_get, .operand = guard }, .{ .op = .if_ }, .{ .op = .i32_const }, .{ .op = .return_ }, .{ .op = .end } });
    try std.testing.expect(getter(&module, &module.functions.items[guarded]));
    var guarded_body = (try run(a, &module, &module.functions.items[guarded], true, false, false)).?;
    defer guarded_body.deinit(a);
    for (guarded_body.instructions.items) |inst| try std.testing.expect(inst.op != .return_);
    module.functions.items[guarded].instructions.items[4].operand = 1;
    try std.testing.expect(!getter(&module, &module.functions.items[guarded]));
    module.functions.items[guarded].instructions.items[4].operand = 0;
    // Machine i32 and a forged result annotation do not prove an indirect
    // producer, scalar formal, cleanup scope or any owner-changing operation.
    const original = module.functions.items[read].instructions.items[1];
    for ([_]ir.Instruction{
        .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .call_import },                                                                .{ .op = .call_indirect },
        .{ .op = .i32_store },                             .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 6 }) }, ir.callResult(.reference),
    }) |replacement| {
        module.functions.items[read].instructions.items[1] = replacement;
        try std.testing.expect(!getter(&module, &module.functions.items[read]));
    }
    module.functions.items[read].instructions.items[1] = original;
    module.functions.items[read].result_role = .scalar;
    try std.testing.expect(!getter(&module, &module.functions.items[read]));
    module.functions.items[read].result_role = .reference;
    try module.setParameterRoles(read, ir.packParameterRoles(&.{.scalar}));
    try std.testing.expect(!getter(&module, &module.functions.items[read]));
    try module.setParameterRoles(read, ir.packParameterRoles(&.{.reference}));

    const caller = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.setParameterRoles(caller, ir.packParameterRoles(&.{.reference}));
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = read }, .{ .op = .i32_load } });
    try module.exportFunction(caller, "run", .pointer, .u32);
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .current = &capture });
    defer a.free(bytes);
    var retained: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer retained.deinit();
    const replayed = try module.assembleWithOptions(.{ .current = &retained, .previous = &capture });
    defer a.free(replayed);
    try std.testing.expectEqualSlices(u8, bytes, replayed);
    const archive = @import("../reuse/optimized_archive.zig");
    const compiler: [32]u8 = @splat(35);
    const saved = try archive.encode(a, compiler, &capture);
    defer a.free(saved);
    var loaded = try archive.decode(a, compiler, saved);
    defer loaded.deinit();
    var restarted: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer restarted.deinit();
    const portable_replay = try module.assembleWithOptions(.{ .current = &restarted, .previous = &loaded });
    defer a.free(portable_replay);
    try std.testing.expectEqualSlices(u8, bytes, portable_replay);
    // An otherwise identical producer gains an owning operation. Exact
    // source-body matching must restore its frame, including retained replay.
    module.functions.items[read].instructions.clearRetainingCapacity();
    try module.emitSlice(read, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .drop }, .{ .op = .local_get }, .{ .op = .i32_load, .operand = 4 }, .{ .op = .return_ } });
    try std.testing.expect(!getter(&module, &module.functions.items[read]));
    const fresh = try module.assembleWithOptions(.{});
    defer a.free(fresh);
    var changed: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer changed.deinit();
    const changed_replay = try module.assembleWithOptions(.{ .current = &changed, .previous = &capture });
    defer a.free(changed_replay);
    try std.testing.expect(!std.mem.eql(u8, bytes, fresh));
    try std.testing.expectEqualSlices(u8, fresh, changed_replay);
}
test "checked pure reference getters publish caller roots before owner changes and decline opaque producers through OOM" {
    try getterOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, getterOwnership, .{});
}
