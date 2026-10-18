//! Expose small straight-line allocation producers to scalar replacement.
//! This consumes the complete direct callee body, already part of optimized
//! body reuse identity. No source names or collection-specific calls participate.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const A = std.mem.Allocator;

/// Callee facts each call instruction asks for: an adapter's returned
/// parameter and whether the callee is an admitted producer or a framed
/// callee. They read only the callee's source body and module facts, which
/// stay fixed while one pipeline session optimizes, so each is computed once
/// per callee. Workers share the slots; every writer of a slot computes the
/// same bits.
pub const Facts = struct {
    slots: []std.atomic.Value(u32) = &.{},
    const returned_known: u32 = 1 << 0;
    const returned_shift = 1;
    const returned_mask: u32 = 0x7f << returned_shift;
    const admitted_known: u32 = 1 << 8;
    const admitted_bit: u32 = 1 << 9;
    const framed_known: u32 = 1 << 10;
    const framed_bit: u32 = 1 << 11;
    pub fn init(a: A, module: *const wasm.Module) A.Error!Facts {
        const slots = try a.alloc(std.atomic.Value(u32), module.functions.items.len);
        @memset(slots, .init(0));
        return .{ .slots = slots };
    }
    pub fn deinit(self: *Facts, a: A) void {
        a.free(self.slots);
        self.* = .{};
    }
    fn returned(self: *const Facts, module: *const wasm.Module, id: u32) ?u32 {
        if (id >= self.slots.len) return returnedParameter(module, id);
        const bits = self.slots[id].load(.monotonic);
        if (bits & returned_known != 0) {
            const encoded = (bits & returned_mask) >> returned_shift;
            return if (encoded == 0) null else encoded - 1;
        }
        const value = returnedParameter(module, id);
        const encoded: u32 = if (value) |parameter| parameter + 1 else 0;
        _ = self.slots[id].fetchOr(returned_known | (encoded << returned_shift), .monotonic);
        return value;
    }
    fn admits(self: *const Facts, module: *const wasm.Module, id: u32) bool {
        if (id >= self.slots.len) return admitted(module, &module.functions.items[id]);
        const bits = self.slots[id].load(.monotonic);
        if (bits & admitted_known != 0) return bits & admitted_bit != 0;
        const value = admitted(module, &module.functions.items[id]);
        _ = self.slots[id].fetchOr(admitted_known | (if (value) admitted_bit else 0), .monotonic);
        return value;
    }
    fn frames(self: *const Facts, module: *const wasm.Module, id: u32) bool {
        if (id >= self.slots.len) return framed(module, id);
        const bits = self.slots[id].load(.monotonic);
        if (bits & framed_known != 0) return bits & framed_bit != 0;
        const value = framed(module, id);
        _ = self.slots[id].fetchOr(framed_known | (if (value) framed_bit else 0), .monotonic);
        return value;
    }
};

// A complete local/control proof identifies representation-only adapters. It
// follows the executed branch, including constructor-pattern return blocks,
// rather than recognizing a source spelling or guessing from the signature.
fn returnedParameter(module: *const wasm.Module, id: u32) ?u32 {
    if (id >= module.functions.items.len or module.runtimeHelper(id) or module.start == id) return null;
    const body = &module.functions.items[id];
    if (body.entry or body.result == .none or body.codeLength() > 256 or body.parameters.len == 0 or body.parameters.len > 64 or body.locals.items.len > 64 - body.parameters.len) return null;
    const count = body.parameters.len + body.locals.items.len;
    var locals: [64]?u32 = @splat(null);
    for (0..body.parameters.len) |at| locals[at] = @intCast(at);
    const Control = struct { position: usize, height: usize, result: bool };
    var controls: [32]Control = undefined;
    var depth: usize = 0;
    var stack: [128]u32 = undefined;
    var height: usize = 0;
    var at: usize = 0;
    while (at < body.instructions.items.len) : (at += 1) {
        const inst = body.instructions.items[at];
        switch (inst.op) {
            .local_get => {
                if (inst.operand >= count or height == stack.len) return null;
                stack[height] = locals[inst.operand] orelse return null;
                height += 1;
            },
            .local_set, .local_tee => {
                if (inst.operand >= count or height == 0) return null;
                locals[inst.operand] = stack[height - 1];
                if (inst.op == .local_set) height -= 1;
            },
            .drop => {
                if (height == 0) return null;
                height -= 1;
            },
            .block => {
                if (depth == controls.len) return null;
                controls[depth] = .{ .position = at, .height = height, .result = inst.operand != 0 and inst.operand != @backingInt(ir.ValueType.none) };
                depth += 1;
            },
            .end => {
                if (depth == 0) return null;
                depth -= 1;
                if (height != controls[depth].height + @intFromBool(controls[depth].result)) return null;
            },
            .br => {
                if (inst.operand > depth) return null;
                if (inst.operand == depth) break;
                const target = depth - inst.operand - 1;
                const frame = controls[target];
                if (height < frame.height + @intFromBool(frame.result)) return null;
                if (frame.result) stack[frame.height] = stack[height - 1];
                height = frame.height + @intFromBool(frame.result);
                var nesting: usize = 1;
                var end = frame.position + 1;
                while (end < body.instructions.items.len) : (end += 1) {
                    switch (body.instructions.items[end].op) {
                        .block, .loop, .if_ => nesting += 1,
                        .end => {
                            nesting -= 1;
                            if (nesting == 0) break;
                        },
                        else => {},
                    }
                }
                if (nesting != 0) return null;
                depth = target;
                at = end;
            },
            .return_ => break,
            .nop => {},
            .ownership => {
                const annotation: ir.Ownership = @bitCast(inst.operand);
                if (annotation.kind != .scope or (annotation.chunk != 0 and annotation.chunk != 1)) return null;
            },
            else => return null,
        }
    }
    if (height != 1) return null;
    const result = stack[0];
    if (result >= body.parameters.len or body.parameters[result] != body.result or result == body.provider_parameter) return null;
    const role = body.parameterRole(result);
    if (role == .unknown or role != body.result_role) return null;
    return result;
}

fn eraseAdapters(a: A, module: *const wasm.Module, source: *const ir.Function, facts: *const Facts) A.Error!?ir.Body {
    var selected = false;
    for (source.instructions.items) |inst| if (inst.op == .call and facts.returned(module, inst.operand) != null) {
        selected = true;
        break;
    };
    if (!selected) return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    try result.instructions.ensureTotalCapacity(a, source.instructions.items.len);
    for (source.instructions.items) |inst| {
        var parameter: ?u32 = null;
        if (inst.op == .call) parameter = facts.returned(module, inst.operand);
        if (parameter) |returned| {
            const callee = &module.functions.items[inst.operand];
            for (returned + 1..callee.parameters.len) |_| try dropArgument(a, &result);
            if (returned != 0) {
                const local: u32 = @intCast(source.parameters.len + result.locals.items.len);
                try result.locals.append(a, callee.result);
                try result.emit(a, .local_set, local);
                for (0..returned) |_| try result.emit(a, .drop, 0);
                try result.emit(a, .local_get, local);
            }
        } else try result.instructions.append(a, inst);
    }
    return result;
}

fn dropArgument(a: A, result: *ir.Body) A.Error!void {
    if (result.instructions.items.len != 0) switch (result.instructions.items[result.instructions.items.len - 1].op) {
        .local_get, .i32_const, .f32_const => {
            result.instructions.items.len -= 1;
            return;
        },
        else => {},
    };
    try result.emit(a, .drop, 0);
}

fn adapterScenario(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const adapter = try module.addTypedFunction(&.{ .i32, .f32, .i32 }, .f32, .scalar);
    try module.setParameterRoles(adapter, ir.packParameterRoles(&.{ .scalar, .scalar, .reference }));
    const local = try module.addLocal(adapter, .f32);
    try module.emitSlice(adapter, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = local }, .{ .op = .block, .operand = @backingInt(ir.ValueType.f32) }, .{ .op = .block, .operand = @backingInt(ir.ValueType.none) }, .{ .op = .local_get, .operand = local }, .{ .op = .br, .operand = 1 }, .{ .op = .end }, .{ .op = .unreachable_ }, .{ .op = .end } });
    const caller = try module.addTypedFunction(&.{ .i32, .f32, .i32 }, .f32, .scalar);
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .local_get, .operand = 2 }, .{ .op = .call, .operand = adapter } });
    const source = &module.functions.items[caller];
    var result = (try run(a, &module, source)).?;
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), result.locals.items.len);
    try std.testing.expectEqualSlices(ir.Instruction, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 3 }, .{ .op = .drop }, .{ .op = .local_get, .operand = 3 } }, result.instructions.items);
    try std.testing.expectEqual(@as(usize, 4), source.instructions.items.len);
    // A role, provider or observable instruction edit revokes the exact proof.
    const body = &module.functions.items[adapter];
    body.result_role = .reference;
    try std.testing.expect((try run(a, &module, source)) == null);
    body.result_role = .scalar;
    body.provider_parameter = 1;
    try std.testing.expect((try run(a, &module, source)) == null);
    body.provider_parameter = ir.no_provider;
    const saved = body.instructions.items[0];
    for ([_]ir.Op{ .call_import, .global_get, .global_set, .i32_load, .i32_div_u, .resource_retire, .unreachable_, .if_, .loop }) |op| {
        body.instructions.items[0] = .{ .op = op };
        try std.testing.expect((try run(a, &module, source)) == null);
    }
    body.instructions.items[0] = saved;
    body.entry = true;
    try std.testing.expect((try run(a, &module, source)) == null);
}

test "representation adapters erase only exact argument return paths and preserve effects through OOM" {
    try adapterScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, adapterScenario, .{});
}

/// The inline pass expands or erases every direct call to this callee.
pub fn expands(module: *const wasm.Module, id: u32) bool {
    return returnedParameter(module, id) != null or admitted(module, &module.functions.items[id]) or framed(module, id);
}

fn admitted(module: *const wasm.Module, body: *const ir.Function) bool {
    const arena = module.arena orelse return false;
    if (body.result != .i32 or body.codeLength() > 96 or body.codeLength() == 0) return false;
    if (body.parameters.len > 64 or body.locals.items.len > 64 - body.parameters.len) return false;
    const count = body.parameters.len + body.locals.items.len;
    var defined: [64]bool = @splat(false);
    @memset(defined[0..body.parameters.len], true);
    var allocations: usize = 0;
    for (body.instructions.items, 0..) |inst, i| switch (inst.op) {
        .local_get => if (inst.operand >= count or !defined[inst.operand]) {
            // A fresh call zeroes its locals. Do not reuse a loop's old value.
            return false;
        },
        .local_set, .local_tee => {
            if (inst.operand >= count) return false;
            defined[inst.operand] = true;
        },
        .ownership => {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind != .scope) continue;
            switch (scope.chunk) {
                2, 5, 6 => if (scope.roles >= count or !defined[scope.roles]) return false,
                3 => {
                    if (scope.roles >= count) return false;
                    defined[scope.roles] = true;
                },
                4 => {
                    const slot = scope.roles & 8191;
                    const value = scope.roles >> 13;
                    if (slot >= count or value >= count or !defined[slot] or !defined[value]) return false;
                },
                else => {},
            }
        },
        .call => {
            if (inst.operand == arena.mark_acyclic) continue;
            if (!arena.isAllocation(inst.operand) or i == 0) return false;
            const size = body.instructions.items[i - 1];
            if (size.table_reference or size.op != .i32_const or size.operand == 0 or size.operand > 64 or size.operand % 4 != 0) return false;
            allocations += 1;
        },
        .i32_const, .f32_const, .i32_load, .f32_load, .i32_store, .f32_store, .drop => {},
        else => {
            // Scalar arithmetic/conversions can trap, but execute at exactly
            // the original call position. Control, host and global operations
            // stay in their original functions.
            const contract = ir.contract(module, body, inst);
            if (contract.effect != .pure) return false;
        },
    };
    return allocations != 0 and allocations <= 4;
}

// A bounded private scalar-result source callee may expose an environment
// projection while retaining its exact eager journal boundary. An unconditional
// reference producer proves that later passes cannot classify this as borrowed;
// unconditional checked allocation also rejects the lazy-frame-only case.
fn framed(module: *const wasm.Module, id: u32) bool {
    if (id >= module.functions.items.len or module.runtimeHelper(id) or (module.start != null and id == module.start.?)) return false;
    const body = &module.functions.items[id];
    if (body.entry or body.result_role != .scalar or (body.result != .i32 and body.result != .f32) or body.codeLength() == 0 or body.codeLength() > 256) return false;
    if (body.parameters.len > 64 or body.locals.items.len > 64 - body.parameters.len) return false;
    const count = body.parameters.len + body.locals.items.len;
    for (body.parameters, 0..) |machine, at| if ((machine != .i32 and machine != .f32) or body.parameterRole(at) == .unknown or body.parameterRole(at) == .value) return false;
    for (body.locals.items) |machine| if (machine != .i32 and machine != .f32) return false;
    const Control = struct { conditional: bool, entry: u64, alternate: ?u64 = null };
    var controls: [64]Control = undefined;
    var defined: u64 = 0;
    for (0..body.parameters.len) |at| defined |= @as(u64, 1) << @intCast(at);
    const parameters = defined;
    var depth: usize = 0;
    var branches: usize = 0;
    var expanded = body.codeLength();
    var locals = count + 1;
    var allocation = false;
    var reference = false;
    for (body.instructions.items, 0..) |inst, at| switch (inst.op) {
        .block, .loop, .if_ => {
            if (depth == controls.len) return false;
            controls[depth] = .{ .conditional = inst.op == .if_, .entry = defined };
            branches += @intFromBool(controls[depth].conditional);
            depth += 1;
        },
        .end => {
            if (depth == 0) return false;
            depth -= 1;
            branches -= @intFromBool(controls[depth].conditional);
            const current = defined;
            defined = controls[depth].entry;
            if (controls[depth].alternate) |alternate| defined |= current & alternate;
        },
        .else_ => {
            if (depth == 0 or !controls[depth - 1].conditional or controls[depth - 1].alternate != null) return false;
            controls[depth - 1].alternate = defined;
            defined = controls[depth - 1].entry;
        },
        .br, .br_if => {
            if (inst.operand > depth) return false;
            if (inst.op == .br) defined = parameters;
        },
        .return_, .unreachable_ => defined = parameters,
        .local_get => {
            if (inst.operand >= count or defined & (@as(u64, 1) << @intCast(inst.operand)) == 0) return false;
        },
        .local_set, .local_tee => {
            if (inst.operand < body.parameters.len or inst.operand >= count) return false;
            defined |= @as(u64, 1) << @intCast(inst.operand);
        },
        .call => {
            if (inst.operand >= module.functions.items.len) return false;
            const target = &module.functions.items[inst.operand];
            if (admitted(module, target)) {
                expanded += target.codeLength() + target.parameters.len;
                locals += target.parameters.len + target.locals.items.len;
                if (expanded > 256 or locals > 128) return false;
            }
            if (branches != 0) continue;
            const arena = module.arena.?;
            if (arena.isAllocation(inst.operand) and at != 0 and ir.allocationAnnotations(body.instructions.items, at).len != 0) allocation = true;
            if (module.cohorts) |cohorts| if (inst.operand == cohorts.allocate and at >= 3) {
                const arguments = body.instructions.items[at - 3 .. at];
                if (arguments[0].op == .i32_const and arguments[0].operand != 0 and arguments[1].op == .i32_const and arguments[2].op == .local_get and ir.allocationAnnotations(body.instructions.items, at - 2).len != 0) allocation = true;
            };
            if (module.regions) |regions| if (inst.operand == regions.runtime.member_at and at >= 4) {
                const arguments = body.instructions.items[at - 4 .. at];
                if (arguments[0].op == .i32_const and arguments[1].op == .drop and arguments[2].op == .local_get and arguments[2].operand == body.provider_parameter and arguments[3].op == .i32_const and ir.allocationAnnotations(body.instructions.items, at - 3).len != 0) {
                    for (regions.plan.members) |member| if (arguments[3].operand == member.offset and arguments[0].operand == member.bytes) {
                        allocation = true;
                    };
                }
            };
            if (!module.runtimeHelper(inst.operand) and target.result_role == .reference and !admitted(module, target)) reference = true;
        },
        .call_indirect => {
            if (inst.operand >= module.signatures.items.len) return false;
            if (ir.indirectResult(body.instructions.items, at) == .unknown) return false;
            if (branches == 0 and ir.indirectResult(body.instructions.items, at) == .reference) reference = true;
        },
        .ownership => {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind != .scope) continue;
            // Owner-aware publications need the callee's proved provider.
            // A scalar framed inline may proceed only without those records.
            if (@import("../runtime/region_runtime.zig").scope(module, id) != null and scope.chunk != 0 and scope.chunk != 1) return false;
            switch (scope.chunk) {
                2, 5, 6 => if (scope.roles >= count or defined & (@as(u64, 1) << @intCast(scope.roles)) == 0) return false,
                3 => {
                    if (scope.roles >= count) return false;
                    defined |= @as(u64, 1) << @intCast(scope.roles);
                },
                4 => {
                    const slot = scope.roles & 8191;
                    const value = scope.roles >> 13;
                    if (slot >= count or value >= count or defined & (@as(u64, 1) << @intCast(slot)) == 0 or defined & (@as(u64, 1) << @intCast(value)) == 0) return false;
                },
                0, 1 => {},
                else => return false,
            }
        },
        .call_import => return false,
        else => {},
    };
    return depth == 0 and allocation and reference;
}
fn framedLocals(module: *const wasm.Module, body: *const ir.Function, facts: *const Facts) usize {
    var count = body.parameters.len + body.locals.items.len + 1;
    for (body.instructions.items) |inst| if (inst.op == .call) {
        const callee = &module.functions.items[inst.operand];
        if (facts.admits(module, inst.operand)) count += callee.parameters.len + callee.locals.items.len;
    };
    return count;
}
fn emitFramed(a: A, module: *const wasm.Module, out: *ir.Body, body: *const ir.Function, base: u32, parameters: usize, facts: *const Facts) !void {
    const result: u32 = @intCast(base + body.parameters.len + body.locals.items.len);
    try out.locals.append(a, body.result);
    // Every read is dominated by a parameter or a write in this activation.
    // Zeroing owner locals would create extra writes and erase allocation
    // provenance; a callee needing implicit zero initialization declines.
    try out.emit(a, .ownership, @bitCast(ir.Ownership{ .kind = .scope }));
    try out.emit(a, .block, @backingInt(body.result));
    var depth: u32 = 0;
    for (body.instructions.items) |instruction| {
        var copy = instruction;
        if (copy.op == .local_get or copy.op == .local_set or copy.op == .local_tee) copy.operand += base;
        if (copy.op == .ownership) copy.operand = @bitCast(@as(ir.Ownership, @bitCast(copy.operand)).relocated(base));
        if (copy.op == .return_) {
            copy.op = .br;
            copy.operand = depth;
        }
        if (copy.op == .call and facts.admits(module, copy.operand)) {
            const producer = &module.functions.items[copy.operand];
            const nested: u32 = @intCast(parameters + out.locals.items.len);
            try out.locals.appendSlice(a, producer.parameters);
            try out.locals.appendSlice(a, producer.locals.items);
            var parameter = producer.parameters.len;
            while (parameter != 0) {
                parameter -= 1;
                try out.emit(a, .local_set, nested + @as(u32, @intCast(parameter)));
            }
            for (producer.instructions.items) |inst| {
                var projected = inst;
                if (projected.op == .local_get or projected.op == .local_set or projected.op == .local_tee) projected.operand += nested;
                if (projected.op == .ownership) projected.operand = @bitCast(@as(ir.Ownership, @bitCast(projected.operand)).relocated(nested));
                try out.instructions.append(a, projected);
            }
            continue;
        }
        try out.instructions.append(a, copy);
        switch (instruction.op) {
            .block, .loop, .if_ => depth += 1,
            .end => depth -= 1,
            else => {},
        }
    }
    try out.emit(a, .end, 0);
    try out.emit(a, .local_set, result);
    try out.emit(a, .ownership, @bitCast(ir.Ownership{ .kind = .scope, .chunk = 1 }));
    try out.emit(a, .local_get, result);
}

pub fn run(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?ir.Body {
    var facts = try Facts.init(a, module);
    defer facts.deinit(a);
    return runWithFacts(a, module, source, &facts);
}
/// `run` with callee facts shared by every body of one pipeline session.
pub fn runWithFacts(a: A, module: *const wasm.Module, source: *const ir.Function, facts: *const Facts) A.Error!?ir.Body {
    var adapters = try eraseAdapters(a, module, source, facts);
    errdefer if (adapters) |*body| body.deinit(a);
    var view = source.*;
    if (adapters) |body| {
        view.locals = body.locals;
        view.instructions = body.instructions;
    }
    if (try inlineAllocations(a, module, &view, facts)) |result| {
        if (adapters) |*body| body.deinit(a);
        return result;
    }
    return adapters;
}

fn inlineAllocations(a: A, module: *const wasm.Module, source: *const ir.Function, facts: *const Facts) A.Error!?ir.Body {
    if (module.arena == null or ir.codeLength(source.instructions.items) > 4096) return null;
    var selected = false;
    for (source.instructions.items) |inst| if (inst.op == .call and (facts.admits(module, inst.operand) or facts.frames(module, inst.operand))) {
        selected = true;
        break;
    };
    if (!selected) return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    try result.instructions.ensureTotalCapacity(a, source.instructions.items.len);
    // Ownership annotations are copied but are not code for this budget.
    var code: usize = 0;
    for (source.instructions.items) |inst| {
        if (inst.op == .call and code < 4096 and (facts.admits(module, inst.operand) or facts.frames(module, inst.operand)) and source.parameters.len + result.locals.items.len + framedLocals(module, &module.functions.items[inst.operand], facts) < 8192) {
            const callee = &module.functions.items[inst.operand];
            const base: u32 = @intCast(source.parameters.len + result.locals.items.len);
            try result.locals.appendSlice(a, callee.parameters);
            try result.locals.appendSlice(a, callee.locals.items);
            var parameter = callee.parameters.len;
            while (parameter != 0) {
                parameter -= 1;
                try result.instructions.append(a, .{ .op = .local_set, .operand = base + @as(u32, @intCast(parameter)) });
            }
            code += callee.parameters.len + callee.codeLength();
            if (facts.frames(module, inst.operand)) {
                try emitFramed(a, module, &result, callee, base, source.parameters.len, facts);
                continue;
            }
            for (callee.instructions.items) |instruction| {
                var copy = instruction;
                if (copy.op == .local_get or copy.op == .local_set or copy.op == .local_tee) copy.operand += base;
                if (copy.op == .ownership) copy.operand = @bitCast(@as(ir.Ownership, @bitCast(copy.operand)).relocated(base));
                try result.instructions.append(a, copy);
            }
        } else {
            code += @intFromBool(inst.op != .ownership);
            try result.instructions.append(a, inst);
        }
    }
    return result;
}

fn ownership(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addFunction(&.{.i32}, .i32);
    const row = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },   .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = row },
        .{ .op = .local_get, .operand = row }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store },
        .{ .op = .local_get, .operand = row },
    });
    const consumer = try module.addFunction(&.{.i32}, .i32);
    const captured = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .local_get, .operand = 0 },        .{ .op = .call, .operand = producer }, .{ .op = .local_set, .operand = captured },
        .{ .op = .local_get, .operand = captured }, .{ .op = .i32_load },
    });
    const before = module.functions.items[consumer].instructions.items.len;
    var inline_body = (try run(a, &module, &module.functions.items[consumer])).?;
    defer inline_body.deinit(a);
    var view = module.functions.items[consumer];
    view.locals = inline_body.locals;
    view.instructions = inline_body.instructions;
    var scalar = (try @import("wasm_sroa.zig").run(a, &module, &view)).?;
    defer scalar.deinit(a);
    for (scalar.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqual(before, module.functions.items[consumer].instructions.items.len);
    // Even a straight-line body must preserve fresh-call local initialization.
    module.functions.items[producer].instructions.items[0] = .{ .op = .local_get, .operand = row };
    try std.testing.expect((try run(a, &module, &module.functions.items[consumer])) == null);
}
test "allocation producer inlining preserves owners and fresh local initialization" {
    try ownership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}

fn scopedProducer(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const row = try module.addLocal(producer, .i32);
    const slot = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },   .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = row },
        .{ .op = .local_get, .operand = row }, .{ .op = .local_get },                       .{ .op = .i32_store },
    });
    const scopes = [_]ir.Ownership{
        .{ .kind = .scope, .chunk = 3, .roles = @intCast(slot) },
        .{ .kind = .scope, .chunk = 4, .roles = @intCast(slot + row * 8192) },
        .{ .kind = .scope, .chunk = 5, .roles = @intCast(row) },
    };
    for (scopes) |scope| try module.emit(producer, .{ .op = .ownership, .operand = @bitCast(scope) });
    try module.emitSlice(producer, &.{ .{ .op = .local_get, .operand = row }, .{ .op = .i32_load } });
    const consumer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const untouched = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .i32_const, .operand = 42 }, .{ .op = .local_set, .operand = untouched },
        .{ .op = .local_get },                .{ .op = .call, .operand = producer },
        .{ .op = .drop },                     .{ .op = .local_get, .operand = untouched },
    });
    var body = (try run(a, &module, &module.functions.items[consumer])).?;
    defer body.deinit(a);
    const base: u32 = @intCast(module.functions.items[consumer].parameters.len + module.functions.items[consumer].locals.items.len);
    var scope_index: usize = 0;
    for (body.instructions.items) |inst| if (inst.op == .ownership) {
        try std.testing.expectEqual(scopes[scope_index].relocated(base), @as(ir.Ownership, @bitCast(inst.operand)));
        scope_index += 1;
    };
    try std.testing.expectEqual(scopes.len, scope_index);
    var view = module.functions.items[consumer];
    view.locals = body.locals;
    view.instructions = body.instructions;
    // Publication keeps a heap identity; removing its allocation would leave
    // the scope reading an uninitialized pointer local.
    try std.testing.expect((try @import("wasm_sroa.zig").run(a, &module, &view)) == null);
    var plan = try @import("wasm_lifetimes.zig").analyze(a, &module, &view);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    try std.testing.expectEqual(@as(ir.Ownership, .{ .kind = .scope, .chunk = 2, .roles = @intCast(row + base) }), (ir.Ownership{ .kind = .scope, .chunk = 2, .roles = @intCast(row) }).relocated(base));
}
test "inlined scope locals preserve caller locals and heap identities through OOM" {
    try scopedProducer(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedProducer, .{});
}

fn framedScalarProducer(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const address = try module.dataWords(&.{ 1, 42 });
    const global = try module.addGlobal(.pointer, address, false);
    const reference = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emit(reference, .{ .op = .global_get, .operand = global });
    const callback = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .scalar);
    try module.setParameterRoles(callback, ir.packParameterRoles(&.{ .reference, .scalar, .reference }));
    const value = try module.addLocal(callback, .i32);
    const scalar = try module.addLocal(callback, .i32);
    const untouched = try module.addLocal(callback, .i32);
    var facts: [ir.max_annotations]ir.Instruction = undefined;
    try module.emitSlice(callback, &.{ .{ .op = .call, .operand = reference }, .{ .op = .drop } });
    try module.emitSlice(callback, ir.annotations(&.{.scalar}, .unknown, &facts));
    try module.emitSlice(callback, &.{
        .{ .op = .i32_const, .operand = 4 },     .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = value },
        .{ .op = .local_get, .operand = value }, .{ .op = .local_get, .operand = 1 },         .{ .op = .i32_store },
        .{ .op = .local_get },                   .{ .op = .i32_load },                        .{ .op = .local_set, .operand = scalar },
        .{ .op = .local_get, .operand = 1 },     .{ .op = .if_ },                             .{ .op = .local_get, .operand = scalar },
        .{ .op = .return_ },                     .{ .op = .end },                             .{ .op = .local_get, .operand = scalar },
        .{ .op = .local_get, .operand = value }, .{ .op = .i32_load },                        .{ .op = .i32_add },
    });
    try std.testing.expect(framed(&module, callback));
    const caller = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.setParameterRoles(caller, ir.packParameterRoles(&.{.scalar}));
    const environment = try module.addLocal(caller, .i32);
    try module.emitSlice(caller, ir.annotations(&.{.scalar}, .unknown, &facts));
    try module.emitSlice(caller, &.{
        .{ .op = .i32_const, .operand = 4 },           .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = environment },
        .{ .op = .local_get, .operand = environment }, .{ .op = .i32_const, .operand = 41 },        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = environment }, .{ .op = .local_get },                       .{ .op = .i32_const },
        .{ .op = .call, .operand = callback },
    });
    const before = try a.dupe(ir.Instruction, module.functions.items[callback].instructions.items);
    defer a.free(before);
    var body = (try run(a, &module, &module.functions.items[caller])).?;
    defer body.deinit(a);
    var opens: usize = 0;
    var closes: usize = 0;
    for (body.instructions.items) |inst| {
        try std.testing.expect(inst.op != .return_);
        if (inst.op != .ownership) continue;
        const scope: ir.Ownership = @bitCast(inst.operand);
        if (scope.kind != .scope) continue;
        if (scope.chunk == 0) opens += 1;
        if (scope.chunk == 1) closes += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), opens);
    try std.testing.expectEqual(@as(usize, 1), closes);
    var view = module.functions.items[caller];
    view.locals = body.locals;
    view.instructions = body.instructions;
    var scalar_body = (try @import("wasm_sroa.zig").runWithRoots(a, &module, &view, true)).?;
    defer scalar_body.deinit(a);
    for (scalar_body.instructions.items) |inst| if (inst.op == .call) try std.testing.expect(!arena.isAllocation(inst.operand));
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[callback].instructions.items);
    // Defaults must remain per-call zeroes; a branch-only write cannot stand
    // in for a definite write before a later read in another activation.
    module.functions.items[callback].instructions.items[0] = .{ .op = .local_get, .operand = untouched };
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].instructions.items[0] = before[0];
    try module.emitSlice(callback, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .if_ }, .{ .op = .i32_const, .operand = 17 }, .{ .op = .local_set, .operand = untouched }, .{ .op = .end }, .{ .op = .local_get, .operand = untouched }, .{ .op = .drop } });
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].instructions.shrinkRetainingCapacity(before.len);

    module.functions.items[callback].parameter_roles = ir.packParameterRoles(&.{ .unknown, .scalar, .reference });
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].parameter_roles = ir.packParameterRoles(&.{ .reference, .scalar, .reference });
    module.functions.items[callback].entry = true;
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].entry = false;
    module.functions.items[callback].result_role = .reference;
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].result_role = .scalar;
    module.functions.items[callback].instructions.items[0] = .{ .op = .call_import };
    try std.testing.expect(!framed(&module, callback));
    module.functions.items[callback].instructions.items[0] = before[0];
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleCheckedWithOptions(.{ .tier = .optimized, .current = &capture });
    defer a.free(bytes);
    const reused = try module.assembleCheckedWithOptions(.{ .tier = .optimized, .previous = &capture });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, bytes, reused);
    const archive = @import("../reuse/optimized_archive.zig");
    const saved = try archive.encode(a, @splat(35), &capture);
    defer a.free(saved);
    var loaded = try archive.decode(a, @splat(35), saved);
    defer loaded.deinit();
    const replayed = try module.assembleCheckedWithOptions(.{ .tier = .optimized, .previous = &loaded });
    defer a.free(replayed);
    try std.testing.expectEqualSlices(u8, bytes, replayed);
    // Editing the exact producer facts invalidates the compiled inline path.
    module.functions.items[callback].entry = true;
    const changed = try module.assembleCheckedWithOptions(.{ .tier = .optimized });
    defer a.free(changed);
    const changed_replay = try module.assembleCheckedWithOptions(.{ .tier = .optimized, .previous = &loaded });
    defer a.free(changed_replay);
    try std.testing.expect(!std.mem.eql(u8, bytes, changed));
    try std.testing.expectEqualSlices(u8, changed, changed_replay);
}
test "private scalar callback inlining preserves eager frames early exits default locals and exact producer replay through OOM" {
    try framedScalarProducer(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, framedScalarProducer, .{});
}

fn sharedFactsScenario(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addFunction(&.{.i32}, .i32);
    const row = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },   .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = row },
        .{ .op = .local_get, .operand = row }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store },
        .{ .op = .local_get, .operand = row },
    });
    const adapter = try module.addTypedFunction(&.{ .i32, .f32 }, .f32, .scalar);
    try module.setParameterRoles(adapter, ir.packParameterRoles(&.{ .scalar, .scalar }));
    try module.emitSlice(adapter, &.{.{ .op = .local_get, .operand = 1 }});
    const consumer = try module.addFunction(&.{.i32}, .i32);
    const captured = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .local_get, .operand = 0 },        .{ .op = .call, .operand = producer }, .{ .op = .local_set, .operand = captured },
        .{ .op = .local_get, .operand = captured }, .{ .op = .i32_load },
    });
    const caller = try module.addTypedFunction(&.{ .i32, .f32 }, .f32, .scalar);
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = adapter } });
    var facts = try Facts.init(a, &module);
    defer facts.deinit(a);
    // Each answer, computed or cached, equals the analysis it replaces.
    for (0..2) |_| for (0..module.functions.items.len) |index| {
        const id: u32 = @intCast(index);
        try std.testing.expectEqual(returnedParameter(&module, id), facts.returned(&module, id));
        try std.testing.expectEqual(admitted(&module, &module.functions.items[id]), facts.admits(&module, id));
        try std.testing.expectEqual(framed(&module, id), facts.frames(&module, id));
    };
    try std.testing.expect(facts.admits(&module, producer));
    try std.testing.expectEqual(@as(?u32, 1), facts.returned(&module, adapter));
    // Bodies optimized with one session's facts equal fresh runs.
    for ([_]u32{ consumer, caller }) |id| {
        var fresh = (try run(a, &module, &module.functions.items[id])).?;
        defer fresh.deinit(a);
        var shared = (try runWithFacts(a, &module, &module.functions.items[id], &facts)).?;
        defer shared.deinit(a);
        try std.testing.expectEqualSlices(ir.ValueType, fresh.locals.items, shared.locals.items);
        try std.testing.expectEqualSlices(ir.Instruction, fresh.instructions.items, shared.instructions.items);
    }
}
test "inlining callee facts shared by a session equal fresh analyses through allocation failure" {
    try sharedFactsScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedFactsScenario, .{});
}
