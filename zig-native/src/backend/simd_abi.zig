//! Four-lane values across direct calls. A private function whose parameter
//! or result holds an F32x4/U32x4 value gets a worker that passes that value
//! as v128, and every direct call in the assembled view calls the worker.
//! The worker stores each v128 parameter into a fresh scalar-only box and
//! loads its returned box once; the caller loads argument lanes and boxes a
//! v128 result the same way. Scalar replacement then keeps the lanes in v128
//! locals on both sides wherever those boxes do not escape. The original
//! function keeps its boxed ABI for tables, exports and helper callers.
//!
//! The proof is a type fact, never a name. Values moving between locals,
//! block results, direct arguments and parameters, and returns and direct
//! results share one checked type. A class read or written whole by a v128
//! access at offset zero is a four-lane SIMD product: only four-lane
//! operations emit those accesses. Arithmetic addresses, plain constants,
//! host and helper results, erased parameters and allocations of any other
//! shape make the whole class ineligible.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const cohort = @import("cohort_candidate.zig");
const A = std.mem.Allocator;
const none = std.math.maxInt(u32);

pub const View = cohort.Extension;

const Classes = struct {
    parent: std.ArrayList(u32) = .empty,
    flags: std.ArrayList(u8) = .empty,
    /// Read or written whole by a v128 access at offset zero.
    const whole: u8 = 1;
    /// Holds a value that cannot be a four-lane product.
    const mixed: u8 = 2;
    fn deinit(self: *Classes, a: A) void {
        self.parent.deinit(a);
        self.flags.deinit(a);
    }
    fn add(self: *Classes, a: A, count: usize) !void {
        const first = self.parent.items.len;
        try self.parent.ensureUnusedCapacity(a, count);
        try self.flags.ensureUnusedCapacity(a, count);
        for (0..count) |offset| self.parent.appendAssumeCapacity(@intCast(first + offset));
        self.flags.appendNTimesAssumeCapacity(0, count);
    }
    fn root(self: *Classes, initial: u32) u32 {
        var id = initial;
        while (self.parent.items[id] != id) id = self.parent.items[id];
        var next = initial;
        while (next != id) {
            const parent = self.parent.items[next];
            self.parent.items[next] = id;
            next = parent;
        }
        return id;
    }
    fn mark(self: *Classes, id: u32, flag: u8) void {
        self.flags.items[self.root(id)] |= flag;
    }
    fn flow(self: *Classes, destination: u32, value: Value) void {
        if (value.mixed) self.mark(destination, mixed);
        if (value.class == none) return;
        const left = self.root(destination);
        const right = self.root(value.class);
        if (left == right) return;
        self.parent.items[right] = left;
        self.flags.items[left] |= self.flags.items[right];
    }
    fn vector(self: *Classes, id: u32) bool {
        return self.flags.items[self.root(id)] == whole;
    }
};

/// An operand: the class it shares a checked type with, or a value that can
/// never be a four-lane product.
const Value = struct { class: u32 = none, mixed: bool = false };
const Control = struct { height: usize, class: u32 };

const Scan = struct {
    a: A,
    module: *const w.Module,
    helpers: []const bool,
    bases: []const u32,
    classes: Classes = .{},
    /// Direct calls from scanned callers.
    calls: []u32,
    /// The body branches to its own label, which a worker cannot convert.
    exits: []bool,
    stack: std.ArrayList(Value) = .empty,
    controls: std.ArrayList(Control) = .empty,
    arguments: std.ArrayList(Value) = .empty,

    fn deinit(self: *Scan) void {
        self.classes.deinit(self.a);
        self.stack.deinit(self.a);
        self.controls.deinit(self.a);
        self.arguments.deinit(self.a);
    }
    fn result(self: *const Scan, id: u32) u32 {
        const body = &self.module.functions.items[id];
        return self.bases[id] + @as(u32, @intCast(body.parameters.len + body.locals.items.len));
    }
    fn floor(self: *const Scan) usize {
        return if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].height;
    }
    fn pop(self: *Scan) Value {
        return if (self.stack.items.len > self.floor()) self.stack.pop().? else .{};
    }
    fn push(self: *Scan, value: Value) !void {
        try self.stack.append(self.a, value);
    }
    fn discard(self: *Scan) void {
        self.stack.shrinkRetainingCapacity(self.floor());
    }
    fn lane(self: *Scan, address: Value, offset: u32) void {
        if (address.class != none and (offset >= 16 or offset % 4 != 0)) self.classes.mark(address.class, Classes.mixed);
    }
    fn whole(self: *Scan, address: Value, offset: u32) void {
        if (address.class != none) self.classes.mark(address.class, if (offset == 0) Classes.whole else Classes.mixed);
    }
    fn function(self: *Scan, id: u32) !void {
        const module = self.module;
        const body = &module.functions.items[id];
        const instructions = body.instructions.items;
        const base = self.bases[id];
        self.stack.clearRetainingCapacity();
        self.controls.clearRetainingCapacity();
        for (instructions, 0..) |inst, at| switch (inst.op) {
            .local_get => try self.push(.{ .class = base + inst.operand }),
            .local_set, .local_tee => {
                self.classes.flow(base + inst.operand, self.pop());
                if (inst.op == .local_tee) try self.push(.{ .class = base + inst.operand });
            },
            // Only a relocated static address can be a constant product.
            .i32_const => try self.push(.{ .mixed = inst.table_reference or ir.staticConstructor(instructions, at) != null or !ir.hasImmortalReference(instructions, at) }),
            .global_get => try self.push(.{}),
            // A four-lane product is only ever read or written in its own
            // sixteen bytes, lane by lane or whole at offset zero.
            .i32_load, .f32_load => {
                self.lane(self.pop(), inst.operand);
                try self.push(.{ .mixed = inst.op == .f32_load });
            },
            .i32_store, .f32_store => {
                _ = self.pop();
                self.lane(self.pop(), inst.operand);
            },
            .v128_load => {
                self.whole(self.pop(), inst.operand);
                try self.push(.{});
            },
            .v128_store => {
                _ = self.pop();
                self.whole(self.pop(), inst.operand);
            },
            .call => try self.call(instructions, at),
            .call_indirect, .call_import => {
                const signature = ir.call(module, inst);
                if (inst.op == .call_indirect) _ = self.pop();
                for (0..signature.parameters.len) |_| _ = self.pop();
                // A closure result keeps its checked type; a host value never
                // is a compiler box.
                if (signature.result != .none) try self.push(.{ .mixed = inst.op == .call_import });
            },
            .block, .loop, .if_ => {
                if (inst.op == .if_) _ = self.pop();
                var class: u32 = none;
                if (inst.operand != 0 and inst.operand != @backingInt(w.ValueType.none)) {
                    class = @intCast(self.classes.parent.items.len);
                    try self.classes.add(self.a, 1);
                    if (inst.op == .loop) self.classes.mark(class, Classes.mixed);
                }
                try self.controls.append(self.a, .{ .height = self.stack.items.len, .class = class });
            },
            .else_, .end => {
                if (self.controls.items.len == 0) {
                    self.exits[id] = true;
                    return;
                }
                const control = self.controls.items[self.controls.items.len - 1];
                if (control.class != none and self.stack.items.len > control.height) self.classes.flow(control.class, self.pop());
                self.discard();
                if (inst.op == .end) {
                    _ = self.controls.pop();
                    if (control.class != none) try self.push(.{ .class = control.class });
                }
            },
            .br, .br_if => {
                if (inst.op == .br_if) _ = self.pop();
                if (inst.operand >= self.controls.items.len) {
                    self.exits[id] = true;
                } else {
                    const target = self.controls.items[self.controls.items.len - 1 - inst.operand];
                    if (target.class != none and self.stack.items.len > self.floor()) self.classes.flow(target.class, self.stack.items[self.stack.items.len - 1]);
                }
                if (inst.op == .br) self.discard();
            },
            .return_ => {
                if (body.result != .none) self.classes.flow(self.result(id), self.pop());
                self.discard();
            },
            .unreachable_ => self.discard(),
            .drop => _ = self.pop(),
            else => {
                const contract = ir.contract(module, body, inst);
                for (0..contract.arity) |_| _ = self.pop();
                if (contract.result != .none) try self.push(.{ .mixed = contract.result == .i32 });
            },
        };
        if (self.controls.items.len != 0) {
            self.exits[id] = true;
            return;
        }
        if (body.result != .none) self.classes.flow(self.result(id), self.pop());
    }
    fn call(self: *Scan, instructions: []const ir.Instruction, at: usize) !void {
        const module = self.module;
        const callee = instructions[at].operand;
        const target = &module.functions.items[callee];
        const arena = module.arena.?;
        if (arena.isAllocation(callee)) {
            for (0..target.parameters.len) |_| _ = self.pop();
            // A four-lane product is a fresh sixteen-byte scalar-only box.
            const size = if (at != 0 and instructions[at - 1].op == .i32_const and !instructions[at - 1].table_reference) instructions[at - 1].operand else 0;
            var scalar = callee == arena.allocate_scalar;
            if (!scalar) {
                const roles = ir.allocationAnnotations(instructions, at);
                scalar = roles.len != 0;
                for (0..4) |word| scalar = scalar and ir.Ownership.wordRole(roles, word) == .scalar;
            }
            return self.push(.{ .mixed = size != 16 or !scalar });
        }
        self.arguments.clearRetainingCapacity();
        try self.arguments.appendNTimes(self.a, .{}, target.parameters.len);
        var index = target.parameters.len;
        while (index != 0) {
            index -= 1;
            self.arguments.items[index] = self.pop();
        }
        const source = !self.helpers[callee];
        if (source) {
            self.calls[callee] +|= 1;
            for (self.arguments.items, 0..) |argument, parameter| if (reference(target, parameter)) self.classes.flow(self.bases[callee] + @as(u32, @intCast(parameter)), argument);
        }
        if (target.result == .none) return;
        if (source and target.result == .i32 and target.result_role == .reference) return self.push(.{ .class = self.result(callee) });
        try self.push(.{ .mixed = target.result == .i32 });
    }
};

/// A checked reference word other than the provider head.
fn reference(body: *const w.Function, parameter: usize) bool {
    return parameter < 32 and body.parameters[parameter] == .i32 and body.parameterRole(parameter) == .reference and parameter != body.provider_parameter;
}

const Plan = struct {
    worker: u32 = none,
    /// Parameters passed as v128.
    vectors: u32 = 0,
    /// The result returns as v128.
    result: bool = false,
    fn vector(self: Plan, parameter: usize) bool {
        return parameter < 32 and self.vectors & (@as(u32, 1) << @intCast(parameter)) != 0;
    }
};

/// Prepares the assembled view, or null when no direct call passes a proved
/// four-lane value. The source module is never modified.
pub fn prepare(a: A, source: *const w.Module) (A.Error || error{ModuleTooLarge})!?View {
    if (source.arena == null) return null;
    var vectors = false;
    for (source.functions.items) |body| for (body.instructions.items) |inst| {
        if (inst.op == .v128_load or inst.op == .v128_store) {
            vectors = true;
            break;
        }
    };
    if (!vectors) return null;
    const count = source.functions.items.len;
    const helpers = try a.alloc(bool, count);
    defer a.free(helpers);
    for (helpers, 0..) |*helper, id| helper.* = source.runtimeHelper(id);
    const bases = try a.alloc(u32, count);
    defer a.free(bases);
    var classes: usize = 0;
    for (source.functions.items, bases) |body, *base| {
        if (classes > std.math.maxInt(u32) / 2) return null;
        base.* = @intCast(classes);
        classes += body.parameters.len + body.locals.items.len + 1;
    }
    const calls = try a.alloc(u32, count);
    defer a.free(calls);
    @memset(calls, 0);
    const exits = try a.alloc(bool, count);
    defer a.free(exits);
    @memset(exits, false);
    var scan: Scan = .{ .a = a, .module = source, .helpers = helpers, .bases = bases, .calls = calls, .exits = exits };
    defer scan.deinit();
    try scan.classes.add(a, classes);
    for (0..count) |id| if (!helpers[id]) try scan.function(@intCast(id));

    const plans = try a.alloc(Plan, count);
    defer a.free(plans);
    @memset(plans, .{});
    var any = false;
    for (source.functions.items, plans, 0..) |*body, *plan, id| {
        if (helpers[id] or exits[id] or calls[id] == 0 or !private(source, @intCast(id))) continue;
        for (0..body.parameters.len) |parameter| if (reference(body, parameter) and scan.classes.vector(bases[id] + @as(u32, @intCast(parameter)))) {
            plan.vectors |= @as(u32, 1) << @intCast(parameter);
        };
        plan.result = body.result == .i32 and body.result_role == .reference and scan.classes.vector(scan.result(@intCast(id)));
        if (plan.vectors == 0 and !plan.result) continue;
        // Callees the inline pass expands or erases at their calls keep
        // that cheaper path.
        if (@import("wasm_inline.zig").expands(source, @intCast(id))) {
            plan.* = .{};
            continue;
        }
        any = true;
    }
    if (!any) return null;
    // Boxes and spilled arguments keep every frame far below the local
    // limits the later passes admit.
    for (source.functions.items, plans, 0..) |*body, plan, id| {
        if (helpers[id]) continue;
        var added: usize = if (plan.vectors != 0 or plan.result) 33 else 0;
        for (body.instructions.items) |inst| if (inst.op == .call) {
            const callee = plans[inst.operand];
            if (callee.vectors != 0 or callee.result) added += 34;
        };
        if (added == 0) continue;
        const frame = std.math.add(usize, body.parameters.len, body.locals.items.len) catch return null;
        if (frame >= 4096 or added >= 4096 - frame) return null;
    }
    return try rewrite(a, source, helpers, plans);
}

/// A function only source code calls directly: no public, start, adapter or
/// region-scoped identity, and a frame small enough for added locals.
fn private(module: *const w.Module, id: u32) bool {
    const body = &module.functions.items[id];
    if (body.entry or (module.start != null and module.start.? == id) or body.parameters.len > 32) return false;
    if (body.parameters.len + body.locals.items.len >= 4096) return false;
    if (module.resourceAdapterFunction(id) or module.taskAdapterFunction(id)) return false;
    if (@import("../runtime/region_runtime.zig").scope(module, id) != null) return false;
    // Late region and cohort owners stay with their original identity.
    for (body.instructions.items) |inst| if (inst.op == .call) {
        if (module.cohorts) |cohorts| if (inst.operand == cohorts.begin or inst.operand == cohorts.allocate or inst.operand == cohorts.retire_members) return false;
        if (module.regions) |regions| if (regions.runtime.contains(inst.operand)) return false;
    };
    return true;
}

fn rewrite(a: A, source: *const w.Module, helpers: []const bool, plans: []Plan) (A.Error || error{ModuleTooLarge})!View {
    var view = try cohort.detached(a, source);
    errdefer view.deinit();
    const module = &view.module;
    // A function referenced only by rewritten direct calls needs no body.
    const kept = try a.alloc(bool, source.functions.items.len);
    defer a.free(kept);
    @memset(kept, false);
    for (source.exports.items) |item| if (!item.global and item.index < kept.len) {
        kept[item.index] = true;
    };
    if (source.start) |start| kept[start] = true;
    for (source.table_functions.items) |target| if (target < kept.len) {
        kept[target] = true;
    };
    for (source.functions.items, 0..) |body, id| for (body.instructions.items) |inst| {
        if (inst.op == .i32_const and inst.table_reference and inst.operand < kept.len) kept[inst.operand] = true;
        if (inst.op == .call and helpers[id] and inst.operand < kept.len) kept[inst.operand] = true;
    };
    // Workers first: appending functions moves the function array.
    for (source.functions.items, plans) |*body, *plan| {
        if (plan.vectors == 0 and !plan.result) continue;
        var parameters: [32]w.ValueType = undefined;
        @memcpy(parameters[0..body.parameters.len], body.parameters);
        var roles = body.parameter_roles;
        for (0..body.parameters.len) |parameter| if (plan.vector(parameter)) {
            parameters[parameter] = .v128;
            roles &= ~(@as(u64, 3) << @intCast(parameter * 2));
            roles |= @as(u64, @backingInt(ir.Role.scalar)) << @intCast(parameter * 2);
        };
        const signature = try module.internType(parameters[0..body.parameters.len], if (plan.result) .v128 else body.result);
        plan.worker = try module.addTypedFunctionForSignature(signature, if (plan.result) .scalar else body.result_role);
        const worker = &module.functions.items[plan.worker];
        worker.parameter_roles = roles;
        worker.provider_parameter = body.provider_parameter;
    }
    for (source.functions.items, plans) |*body, plan| {
        if (plan.worker == none) continue;
        var output = try transform(a, source, body, plan, plans);
        errdefer output.deinit(a);
        const worker = &module.functions.items[plan.worker];
        worker.locals = output.locals;
        worker.instructions = output.instructions;
        worker.annotations = annotations(output.instructions.items);
    }
    for (source.functions.items, plans, 0..) |*body, plan, id| {
        if (helpers[id]) continue;
        const target = &module.functions.items[id];
        if (plan.worker != none and !kept[id]) {
            // Unreachable from the table, exports and helpers: keep only a
            // trapping body, since every call now enters the worker.
            var instructions: std.ArrayList(ir.Instruction) = .empty;
            errdefer instructions.deinit(a);
            try instructions.append(a, .{ .op = .unreachable_ });
            target.locals = .empty;
            target.instructions = instructions;
            target.annotations = 0;
            view.owned[id] = true;
            continue;
        }
        var calls = false;
        for (body.instructions.items) |inst| if (inst.op == .call and plans[inst.operand].worker != none) {
            calls = true;
            break;
        };
        if (!calls) continue;
        var output = try transform(a, source, body, .{}, plans);
        errdefer output.deinit(a);
        target.locals = output.locals;
        target.instructions = output.instructions;
        target.annotations = annotations(output.instructions.items);
        view.owned[id] = true;
    }
    return view;
}

fn annotations(instructions: []const ir.Instruction) u32 {
    var count: u32 = 0;
    for (instructions) |inst| count += @intFromBool(inst.op == .ownership);
    return count;
}

/// The body with direct calls entering workers; for a worker (`own` names
/// its plan), parameters box on entry and the result box loads at exits.
fn transform(a: A, module: *const w.Module, body: *const w.Function, own: Plan, plans: []const Plan) A.Error!ir.Body {
    const instructions = body.instructions.items;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, body.locals.items);
    try out.instructions.ensureTotalCapacity(a, instructions.len + 16);
    const parameters = body.parameters.len;
    // Reads and writes of a v128 parameter use its box address instead.
    const boxes = try a.alloc(u32, parameters);
    defer a.free(boxes);
    for (boxes, 0..) |*box, parameter| {
        box.* = @intCast(parameter);
        if (own.vector(parameter)) box.* = try local(a, &out, parameters, .i32);
    }
    var returned: u32 = none;
    if (own.result) returned = try local(a, &out, parameters, .i32);
    for (0..parameters) |parameter| if (own.vector(parameter)) try emitBox(a, &out, module, @intCast(parameter), boxes[parameter]);
    // Arguments pushed by a plain run before a rewritten call load their
    // lanes in place; any other argument sequence spills to locals first.
    const loads = try a.alloc(bool, instructions.len);
    defer a.free(loads);
    @memset(loads, false);
    const spills = try a.alloc(bool, instructions.len);
    defer a.free(spills);
    @memset(spills, false);
    for (instructions, 0..) |inst, at| {
        if (inst.op != .call or plans[inst.operand].worker == none) continue;
        const plan = plans[inst.operand];
        const count = module.functions.items[inst.operand].parameters.len;
        var positions: [32]usize = undefined;
        var found: usize = 0;
        var cursor = at;
        while (found < count and cursor != 0) {
            cursor -= 1;
            switch (instructions[cursor].op) {
                .ownership => {},
                .local_get, .i32_const, .f32_const => {
                    positions[count - 1 - found] = cursor;
                    found += 1;
                },
                else => break,
            }
        }
        if (found != count) {
            spills[at] = true;
            continue;
        }
        for (positions[0..count], 0..) |position, parameter| if (plan.vector(parameter)) {
            loads[position] = true;
        };
    }
    for (instructions, 0..) |inst, at| {
        var copy = inst;
        switch (copy.op) {
            .local_get, .local_set, .local_tee, .resource_retire => if (copy.operand < parameters) {
                copy.operand = boxes[copy.operand];
            },
            .ownership => copy.operand = remapped(copy.operand, boxes),
            else => {},
        }
        if (copy.op == .call and plans[copy.operand].worker != none) {
            try emitCall(a, &out, module, parameters, copy.operand, plans[copy.operand], spills[at]);
        } else if (copy.op == .return_ and own.result) {
            try emitUnbox(a, &out, returned);
            try out.instructions.append(a, copy);
        } else try out.instructions.append(a, copy);
        if (loads[at]) try out.emit(a, .v128_load, 0);
    }
    if (own.result) {
        var last: ?ir.Op = null;
        for (instructions) |inst| if (inst.op != .ownership) {
            last = inst.op;
        };
        if (last == null or (last.? != .return_ and last.? != .unreachable_)) try emitUnbox(a, &out, returned);
    }
    return out;
}

fn local(a: A, out: *ir.Body, parameters: usize, ty: w.ValueType) A.Error!u32 {
    const id: u32 = @intCast(parameters + out.locals.items.len);
    try out.locals.append(a, ty);
    return id;
}

/// Annotation operands naming a parameter local follow its box.
fn remapped(operand: u32, boxes: []const u32) u32 {
    var fact: ir.Ownership = @bitCast(operand);
    const map = struct {
        fn follow(id: u32, table: []const u32) u32 {
            return if (id < table.len) table[id] else id;
        }
    };
    if (fact.kind == .rest and fact.chunk == 8) {
        fact.roles = @intCast(map.follow(fact.roles, boxes));
    } else if (fact.kind == .scope) switch (fact.chunk) {
        2, 3, 5, 6 => fact.roles = @intCast(map.follow(fact.roles, boxes)),
        4 => fact.roles = @intCast(map.follow(fact.roles & 8191, boxes) | (map.follow(fact.roles >> 13, boxes) << 13)),
        else => {},
    };
    return @bitCast(fact);
}

/// A fresh scalar-only box holding the v128 in `lanes`, exactly as the
/// emitter builds a four-lane result; the address stays in `box`.
fn emitBox(a: A, out: *ir.Body, module: *const w.Module, lanes: u32, box: u32) A.Error!void {
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    try out.instructions.appendSlice(a, ir.annotations(&.{}, .scalar, &buffer));
    try out.emit(a, .i32_const, 16);
    try out.emit(a, .call, module.arena.?.allocate_scalar);
    try out.emit(a, .local_set, box);
    try out.emit(a, .local_get, box);
    try out.emit(a, .local_get, lanes);
    try out.emit(a, .v128_store, 0);
}

/// Replaces the returned box address on top of the stack with its lanes.
fn emitUnbox(a: A, out: *ir.Body, returned: u32) A.Error!void {
    try out.emit(a, .local_set, returned);
    try out.emit(a, .local_get, returned);
    try out.emit(a, .v128_load, 0);
}

fn emitCall(a: A, out: *ir.Body, module: *const w.Module, parameters: usize, callee: u32, plan: Plan, spill: bool) A.Error!void {
    const target = &module.functions.items[callee];
    if (spill) {
        var temporaries: [32]u32 = undefined;
        var index = target.parameters.len;
        while (index != 0) {
            index -= 1;
            temporaries[index] = try local(a, out, parameters, target.parameters[index]);
            try out.emit(a, .local_set, temporaries[index]);
        }
        for (temporaries[0..target.parameters.len], 0..) |temporary, parameter| {
            try out.emit(a, .local_get, temporary);
            if (plan.vector(parameter)) try out.emit(a, .v128_load, 0);
        }
    }
    try out.emit(a, .call, plan.worker);
    if (!plan.result) return;
    const lanes = try local(a, out, parameters, .v128);
    const box = try local(a, out, parameters, .i32);
    try out.emit(a, .local_set, lanes);
    try emitBox(a, out, module, lanes, box);
    try out.emit(a, .local_get, box);
}

/// 0: a SIMD result passed straight to a lane-reading callee; 1: no v128
/// access proves the type; 2: an erased parameter takes no edge; 3: the
/// argument class also holds an eight-byte allocation; 4: a table reference
/// keeps the boxed original; 5: a computed argument spills; 6: recursion;
/// 7: a read past sixteen bytes cannot be a four-lane product.
fn workerScenario(a: A, scenario: usize) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    const sum = try module.addTypedFunction(&.{ .i32, .i32 }, .f32, .scalar);
    try module.setParameterRoles(sum, ir.packParameterRoles(&.{ if (scenario == 2) .value else .reference, .reference }));
    try module.setProviderParameter(sum, 1);
    try module.emitSlice(sum, &.{ .{ .op = .local_get }, .{ .op = .f32_load }, .{ .op = .local_get }, .{ .op = .f32_load, .operand = 12 }, .{ .op = .f32_add } });
    if (scenario == 6) try module.emitSlice(sum, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = sum }, .{ .op = .f32_add } });
    if (scenario == 7) try module.emitSlice(sum, &.{ .{ .op = .local_get }, .{ .op = .f32_load, .operand = 16 }, .{ .op = .f32_add } });
    if (scenario == 4) try module.table_functions.append(a, sum);
    const make = try module.addTypedFunction(&.{ .f32, .i32 }, .i32, .reference);
    try module.setParameterRoles(make, ir.packParameterRoles(&.{ .scalar, .reference }));
    try module.setProviderParameter(make, 1);
    const box = try module.addLocal(make, .i32);
    try module.emitSlice(make, ir.annotations(&.{}, .scalar, &buffer));
    try module.emitSlice(make, &.{ .{ .op = .i32_const, .operand = 16 }, .{ .op = .call, .operand = arena.allocate_scalar }, .{ .op = .local_set, .operand = box } });
    if (scenario == 1) {
        for (0..4) |lane| try module.emitSlice(make, &.{ .{ .op = .local_get, .operand = box }, .{ .op = .local_get }, .{ .op = .f32_store, .operand = @intCast(lane * 4) } });
    } else try module.emitSlice(make, &.{ .{ .op = .local_get, .operand = box }, .{ .op = .local_get }, .{ .op = .f32x4_splat }, .{ .op = .v128_store } });
    try module.emit(make, .{ .op = .local_get, .operand = box });
    const caller = try module.addTypedFunction(&.{ .f32, .i32 }, .f32, .scalar);
    try module.setParameterRoles(caller, ir.packParameterRoles(&.{ .scalar, .reference }));
    try module.setProviderParameter(caller, 1);
    const lanes = try module.addLocal(caller, .i32);
    if (scenario == 3) {
        try module.emitSlice(caller, ir.annotations(&.{}, .scalar, &buffer));
        try module.emitSlice(caller, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate_scalar }, .{ .op = .local_set, .operand = lanes } });
    }
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = make }, .{ .op = .local_set, .operand = lanes }, .{ .op = .local_get, .operand = lanes } });
    if (scenario == 5) try module.emit(caller, .{ .op = .local_tee, .operand = lanes });
    try module.emitSlice(caller, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = sum } });
    const ids = [_]u32{ sum, make, caller };
    var before: [ids.len][]ir.Instruction = @splat(&.{});
    defer for (before) |copy| a.free(copy);
    for (&before, ids) |*copy, id| copy.* = try a.dupe(ir.Instruction, module.functions.items[id].instructions.items);
    var prepared = try prepare(a, &module);
    defer if (prepared) |*view| view.deinit();
    for (before, ids) |copy, id| try std.testing.expectEqualSlices(ir.Instruction, copy, module.functions.items[id].instructions.items);
    if (scenario == 1 or scenario == 3 or scenario == 7) return std.testing.expect(prepared == null);
    const view = &prepared.?.module;
    const original = module.functions.items.len;
    // Workers follow the original functions in id order.
    const sum_worker: ?u32 = if (scenario == 2) null else @intCast(original);
    const make_worker: u32 = @intCast(original + @intFromBool(sum_worker != null));
    try std.testing.expectEqual(original + 1 + @intFromBool(sum_worker != null), view.functions.items.len);
    try std.testing.expectEqual(w.ValueType.v128, view.functions.items[make_worker].result);
    try std.testing.expectEqual(ir.Role.scalar, view.functions.items[make_worker].result_role);
    try std.testing.expectEqualSlices(w.ValueType, &.{ .f32, .i32 }, view.functions.items[make_worker].parameters);
    const caller_code = view.functions.items[caller].instructions.items;
    var loads: usize = 0;
    var spilled = false;
    for (caller_code, 0..) |inst, at| {
        // No direct call still enters a planned original.
        if (inst.op == .call) try std.testing.expect(inst.operand != make and (inst.operand != sum or sum_worker == null));
        if (inst.op == .v128_load) loads += 1;
        if (inst.op == .local_set and at + 1 < caller_code.len and caller_code[at + 1].op == .local_set) spilled = true;
    }
    try std.testing.expectEqual(@as(usize, @intFromBool(sum_worker != null)), loads);
    try std.testing.expectEqual(scenario == 5, spilled);
    if (sum_worker) |worker| {
        const body = &view.functions.items[worker];
        try std.testing.expectEqualSlices(w.ValueType, &.{ .v128, .i32 }, body.parameters);
        try std.testing.expectEqual(ir.Role.scalar, body.parameterRole(0));
        try std.testing.expectEqual(ir.Role.reference, body.parameterRole(1));
        try std.testing.expectEqual(@as(u8, 1), body.provider_parameter);
        // The worker boxes its lanes once on entry.
        try std.testing.expectEqual(w.Op.v128_store, body.instructions.items[body.annotations + 5].op);
        var recursive = false;
        for (body.instructions.items) |inst| if (inst.op == .call and inst.operand == worker) {
            recursive = true;
        };
        try std.testing.expectEqual(scenario == 6, recursive);
        // A table reference keeps the boxed original; otherwise it traps.
        const kept = view.functions.items[sum].instructions.items;
        if (scenario == 4) try std.testing.expect(kept.len > 1) else try std.testing.expectEqualSlices(ir.Instruction, &.{.{ .op = .unreachable_ }}, kept);
    }
    if (scenario != 0) return;
    // Scalar replacement removes every box on both sides of the calls, and
    // the whole view assembles with complete ownership.
    for ([_]u32{ caller, sum_worker.?, make_worker }) |id| {
        var function = view.functions.items[id];
        var optimized = try @import("wasm_sroa.zig").runWithRoots(a, view, &function, true);
        defer if (optimized) |*body| body.deinit(a);
        const code = if (optimized) |body| body.instructions.items else function.instructions.items;
        for (code) |inst| if (inst.op == .call) try std.testing.expect(!arena.isAllocation(inst.operand));
    }
    const bytes = try view.assembleCheckedWithOptions(.{ .tier = .optimized });
    defer a.free(bytes);
}
fn workerScenarios(a: A) !void {
    for (0..8) |scenario| try workerScenario(a, scenario);
}
test "proved four-lane values cross direct calls as v128 and keep the boxed ABI elsewhere through OOM" {
    try workerScenarios(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, workerScenarios, .{});
}
