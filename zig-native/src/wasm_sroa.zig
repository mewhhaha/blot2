//! Scalar replacement of small nonescaping allocations in symbolic Wasm.
//! Copies get distinct scalar slots (including loop carries); stores are admitted
//! only into freshly allocated locals before any alias is copied. ABI values,
//! calls, unknown offsets, mutable aliases and GC roots keep ordinary storage.
const std = @import("std");
const w = @import("wasm.zig");
const A = std.mem.Allocator;
const none = std.math.maxInt(u32);
const Value = struct { id: u32 = 0, offset: u32 = 0, constant: ?u32 = null };
const Node = struct { parent: u32, bad: bool = false, size: u32 = 0, allocation: bool = false, first_copy: u32 = none, last_store: u32 = 0, store_mask: u32 = 0, scope: usize = 0, fields: u32 = 0 };
const Event = struct { input: Value = .{}, destination: u32 = 0, field: u32 = 0, allocation: u32 = 0, fresh: bool = false };
const Control = struct { height: usize, result: u32, unreachable_: bool = false, identity: usize = 0 };
pub const Output = struct {
    locals: std.ArrayList(w.ValueType) = .empty,
    instructions: std.ArrayList(w.Instruction) = .empty,
    pub fn deinit(self: *Output, a: A) void {
        self.locals.deinit(a);
        self.instructions.deinit(a);
    }
};
const Analysis = struct {
    a: A,
    nodes: std.ArrayList(Node) = .empty,
    stack: std.ArrayList(Value) = .empty,
    controls: std.ArrayList(Control) = .empty,
    events: []Event,
    constants: []?u32,
    constant_scopes: []?usize,
    defined_scopes: []?usize,
    valid: bool = true,
    fn add(self: *Analysis, bad: bool, size: u32) !u32 {
        const id: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.a, .{ .parent = id, .bad = bad, .size = size });
        return id;
    }
    fn root(self: *Analysis, initial: u32) u32 {
        var id = initial;
        while (self.nodes.items[id].parent != id) id = self.nodes.items[id].parent;
        var next = initial;
        while (next != id) {
            const parent = self.nodes.items[next].parent;
            self.nodes.items[next].parent = id;
            next = parent;
        }
        return id;
    }
    fn escape(self: *Analysis, v: Value) void {
        if (v.id != 0) self.nodes.items[self.root(v.id)].bad = true;
    }
    fn join(self: *Analysis, dst: u32, v: Value) void {
        const target = self.root(dst);
        if (v.id == 0 or v.offset != 0) {
            self.nodes.items[target].bad = true;
            self.escape(v);
            return;
        }
        const source = self.root(v.id);
        if (target == source) return;
        const right = self.nodes.items[source];
        const left = &self.nodes.items[target];
        left.bad = left.bad or right.bad or (left.size != 0 and right.size != 0 and left.size != right.size);
        left.size = @max(left.size, right.size);
        self.nodes.items[source].parent = target;
    }
    fn push(self: *Analysis, v: Value) !void {
        try self.stack.append(self.a, v);
    }
    fn dominates(self: *const Analysis, scope: ?usize) bool {
        const owner = scope orelse return false;
        if (owner == 0) return true;
        for (self.controls.items) |c| if (c.identity == owner) return true;
        return false;
    }
    fn pop(self: *Analysis) Value {
        const floor = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].height;
        return if (self.stack.items.len > floor) self.stack.pop().? else .{};
    }
    fn copy(self: *Analysis, at: usize, dst: u32, v: Value) void {
        self.join(dst, v);
        self.events[at].input = v;
        self.events[at].destination = dst;
        if (v.id != 0) self.nodes.items[v.id].first_copy = @min(self.nodes.items[v.id].first_copy, @as(u32, @intCast(at)));
    }
    fn closeArm(self: *Analysis, at: usize) void {
        const c = self.controls.items[self.controls.items.len - 1];
        if (!c.unreachable_ and c.result != 0) self.copy(at, c.result, self.pop());
        self.stack.shrinkRetainingCapacity(c.height);
    }
    fn dead(self: *Analysis) void {
        if (self.controls.items.len != 0) {
            const c = &self.controls.items[self.controls.items.len - 1];
            c.unreachable_ = true;
            self.stack.shrinkRetainingCapacity(c.height);
        } else self.stack.clearRetainingCapacity();
    }
    fn call(self: *Analysis, parameters: usize, result: w.ValueType) !void {
        for (0..parameters) |_| self.escape(self.pop());
        if (result != .none) try self.push(.{});
    }
    fn scan(self: *Analysis, module: *const w.Module, function: *const w.Function, instructions: []const w.Instruction) !void {
        for (instructions, 0..) |inst, at| {
            switch (inst.op) {
                .i32_const => try self.push(.{ .constant = inst.operand }),
                .f32_const, .global_get, .memory_size, .host_ref_null, .host_ref_size => try self.push(.{}),
                .local_get => {
                    // A constant assignment in one arm does not dominate the
                    // other arm, the enclosing continuation, or an earlier use
                    // (locals start at zero). Keep those reads as ordinary locals.
                    if (!self.dominates(self.defined_scopes[inst.operand])) self.escape(.{ .id = inst.operand + 1 });
                    try self.push(if (self.dominates(self.constant_scopes[inst.operand]) and self.constants[inst.operand] != null) .{ .constant = self.constants[inst.operand].? } else .{ .id = inst.operand + 1 });
                },
                .local_set, .local_tee => {
                    const value = self.pop();
                    if (!self.dominates(self.defined_scopes[inst.operand])) self.defined_scopes[inst.operand] = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    if (self.constants[inst.operand] != null) self.constant_scopes[inst.operand] = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    self.copy(at, inst.operand + 1, value);
                    // Allocation results are always captured immediately by
                    // the emitter; this local owns initialization stores.
                    if (at != 0 and self.events[at - 1].allocation != 0 and value.id == self.events[at - 1].allocation) {
                        // A second allocation site into one local would mix
                        // initialization masks from distinct control paths.
                        if (self.nodes.items[inst.operand + 1].allocation) self.escape(value);
                        self.nodes.items[inst.operand + 1].allocation = true;
                        self.events[at].fresh = true;
                        self.nodes.items[inst.operand + 1].scope = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    }
                    if (inst.op == .local_tee) try self.push(.{ .id = inst.operand + 1 });
                },
                .i32_add => {
                    var right = self.pop();
                    var left = self.pop();
                    if (left.constant != null) std.mem.swap(Value, &left, &right);
                    if (right.constant) |constant| {
                        if (left.constant) |other| try self.push(.{ .constant = other +% constant }) else {
                            left.offset +%= constant;
                            try self.push(left);
                        }
                    } else {
                        self.escape(left);
                        self.escape(right);
                        try self.push(.{});
                    }
                },
                .i32_load, .f32_load => {
                    const address = self.pop();
                    self.events[at].input = address;
                    self.events[at].field = address.offset +% inst.operand;
                    if (address.id != 0) self.nodes.items[address.id].first_copy = @min(self.nodes.items[address.id].first_copy, @as(u32, @intCast(at)));
                    if (address.id == 0 or self.events[at].field >= 64 or self.events[at].field % 4 != 0) self.escape(address);
                    try self.push(.{});
                },
                .i32_store, .f32_store => {
                    self.escape(self.pop()); // An inner object can be removed on a subsequent pass.
                    const address = self.pop();
                    self.events[at].input = address;
                    self.events[at].field = address.offset +% inst.operand;
                    if (address.id != 0) {
                        self.nodes.items[address.id].last_store = @intCast(at);
                        if (self.events[at].field < 64 and self.events[at].field % 4 == 0 and self.nodes.items[address.id].scope == (if (self.controls.items.len == 0) @as(usize, 0) else self.controls.items[self.controls.items.len - 1].identity)) self.nodes.items[address.id].store_mask |= @as(u32, 1) << @intCast(self.events[at].field / 4);
                    }
                    if (address.id == 0 or !self.nodes.items[address.id].allocation or self.events[at].field >= 64 or self.events[at].field % 4 != 0) self.escape(address);
                },
                .call => {
                    const callee = module.functions.items[inst.operand];
                    if (module.arena != null and module.arena.?.isAllocation(inst.operand)) {
                        const size = self.pop();
                        if (size.constant != null and size.constant.? != 0 and size.constant.? <= 64 and size.constant.? % 4 == 0) {
                            const id = try self.add(false, size.constant.?);
                            self.events[at].allocation = id;
                            try self.push(.{ .id = id });
                        } else {
                            self.escape(size);
                            try self.push(.{});
                        }
                    } else try self.call(callee.parameters.len, callee.result);
                },
                .call_indirect => {
                    self.escape(self.pop());
                    const signature = module.signatures.items[inst.operand];
                    try self.call(signature.parameters.len, signature.result);
                },
                .call_import => {
                    const signature = module.signatures.items[module.imports.items[inst.operand].signature];
                    try self.call(signature.parameters.len, signature.result);
                },
                .block, .loop, .if_ => {
                    if (inst.op == .if_) self.escape(self.pop());
                    const result = if (inst.operand != 0 and inst.operand != @backingInt(w.ValueType.none)) try self.add(false, 0) else 0;
                    // Current loop carries use locals. Value-producing Wasm
                    // loops have a different label arity from blocks.
                    if (inst.op == .loop and result != 0) {
                        self.valid = false;
                        return;
                    }
                    try self.controls.append(self.a, .{ .height = self.stack.items.len, .result = result, .identity = at + 1 });
                },
                .else_ => {
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    self.closeArm(at);
                    self.controls.items[self.controls.items.len - 1].unreachable_ = false;
                    self.controls.items[self.controls.items.len - 1].identity = at + 1;
                },
                .end => {
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    self.closeArm(at);
                    const c = self.controls.pop().?;
                    if (c.result != 0) try self.push(.{ .id = c.result });
                },
                .br, .br_if => {
                    if (inst.op == .br_if) self.escape(self.pop());
                    if (inst.operand >= self.controls.items.len) {
                        self.valid = false;
                        return;
                    }
                    const c = self.controls.items[self.controls.items.len - 1 - inst.operand];
                    if (c.result != 0) {
                        if (inst.op == .br_if) { // Keep conditional result transfers boxed.
                            if (self.stack.items.len != 0) self.escape(self.stack.items[self.stack.items.len - 1]);
                            self.nodes.items[self.root(c.result)].bad = true;
                        } else self.copy(at, c.result, self.pop());
                    }
                    if (inst.op == .br) self.dead();
                },
                .return_ => {
                    if (function.result != .none) self.escape(self.pop());
                    self.dead();
                },
                .unreachable_ => self.dead(),
                .drop => {
                    _ = self.pop();
                },
                .global_set, .host_ref_get, .host_ref_is_null, .memory_grow => {
                    self.escape(self.pop());
                    if (inst.op != .global_set) try self.push(.{});
                },
                .host_ref_set => {
                    self.escape(self.pop());
                    self.escape(self.pop());
                },
                .host_ref_grow => {
                    self.escape(self.pop());
                    self.escape(self.pop());
                    try self.push(.{});
                },
                .v128_store => {
                    self.escape(self.pop());
                    self.escape(self.pop());
                },
                .v128_load, .i32x4_splat, .f32x4_splat, .i32x4_extract_lane, .f32x4_extract_lane, .f32x4_abs, .f32x4_neg, .f32x4_ceil, .f32x4_floor, .f32x4_trunc, .f32x4_sqrt, .f32x4_convert_i32x4_u, .i32x4_trunc_sat_f32x4_u => {
                    self.escape(self.pop());
                    try self.push(.{});
                },
                .memory_copy, .memory_fill => {
                    self.escape(self.pop());
                    self.escape(self.pop());
                    self.escape(self.pop());
                },
                .i32_eqz, .i32_clz, .i32_ctz, .f32_abs, .f32_neg, .f32_ceil, .f32_floor, .f32_trunc, .f32_sqrt, .i32_reinterpret_f32, .f32_reinterpret_i32, .i32_trunc_sat_f32_u, .f32_convert_i32_u => {
                    self.escape(self.pop());
                    try self.push(.{});
                },
                .nop => {},
                else => {
                    self.escape(self.pop());
                    self.escape(self.pop());
                    try self.push(.{});
                },
            }
        }
        if (function.result != .none) self.escape(self.pop());
        for (self.nodes.items, 0..) |node, id| if (node.first_copy < node.last_store or (node.allocation and node.store_mask != (@as(u32, 1) << @intCast(self.nodes.items[self.root(@intCast(id))].size / 4)) - 1)) {
            self.nodes.items[self.root(@intCast(id))].bad = true;
        };
        for (self.events) |event| if (event.input.id != 0 and event.destination == 0 and event.allocation == 0) {
            const root_ = self.root(event.input.id);
            if (event.field >= self.nodes.items[root_].size) self.nodes.items[root_].bad = true;
        };
    }
    fn selected(self: *Analysis, id: u32) bool {
        if (id == 0) return false;
        const n = self.nodes.items[self.root(id)];
        return !n.bad and n.size != 0;
    }
};
fn emit(out: *Output, a: A, op: w.Op, operand: u32) !void {
    try out.instructions.append(a, .{ .op = op, .operand = operand });
}
fn copyFields(out: *Output, analysis: *Analysis, event: Event) !void {
    const a = analysis.a;
    const count = analysis.nodes.items[analysis.root(event.destination)].size / 4;
    // All sources precede all stores: a loop/branch may permute aliases.
    for (0..count) |i| try emit(out, a, .local_get, analysis.nodes.items[event.input.id].fields + @as(u32, @intCast(i)));
    var i = count;
    while (i != 0) {
        i -= 1;
        try emit(out, a, .local_set, analysis.nodes.items[event.destination].fields + i);
    }
}
fn pass(a: A, module: *const w.Module, function: *const w.Function, locals: []const w.ValueType, instructions: []const w.Instruction) !?Output {
    const events = try a.alloc(Event, instructions.len);
    defer a.free(events);
    @memset(events, .{});
    const local_count = std.math.add(usize, function.parameters.len, locals.len) catch return error.OutOfMemory;
    const constants = try a.alloc(?u32, local_count);
    defer a.free(constants);
    @memset(constants, null);
    const constant_scopes = try a.alloc(?usize, constants.len);
    defer a.free(constant_scopes);
    @memset(constant_scopes, null);
    const defined_scopes = try a.alloc(?usize, constants.len);
    defer a.free(defined_scopes);
    @memset(defined_scopes, null);
    @memset(defined_scopes[0..function.parameters.len], 0);
    const writes = try a.alloc(bool, constants.len);
    defer a.free(writes);
    @memset(writes, false);
    for (instructions, 0..) |inst, i| if (inst.op == .local_set or inst.op == .local_tee) {
        const value: ?u32 = if (i != 0 and instructions[i - 1].op == .i32_const) instructions[i - 1].operand else null;
        if (!writes[inst.operand]) constants[inst.operand] = value else if (constants[inst.operand] != value) constants[inst.operand] = null;
        writes[inst.operand] = true;
    };
    var analysis: Analysis = .{ .a = a, .events = events, .constants = constants, .constant_scopes = constant_scopes, .defined_scopes = defined_scopes };
    defer analysis.nodes.deinit(a);
    defer analysis.stack.deinit(a);
    defer analysis.controls.deinit(a);
    _ = try analysis.add(true, 0);
    for (0..local_count) |i| _ = try analysis.add(i < function.parameters.len, 0);
    try analysis.scan(module, function, instructions);
    if (!analysis.valid) return null;
    var any = false;
    for (events) |event| if (analysis.selected(event.allocation)) {
        any = true;
        break;
    };
    if (!any) return null;
    var out: Output = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, locals);
    for (0..analysis.nodes.items.len) |id| {
        if (!analysis.selected(@intCast(id))) continue;
        const count = analysis.nodes.items[analysis.root(@intCast(id))].size / 4;
        analysis.nodes.items[id].fields = @intCast(function.parameters.len + out.locals.items.len);
        try out.locals.appendNTimes(a, .i32, count);
    }
    for (instructions, events) |inst, event| {
        if (analysis.selected(event.allocation)) {
            try emit(&out, a, .drop, 0);
            try emit(&out, a, .i32_const, 0);
            continue;
        }
        if (event.destination != 0 and !event.fresh and analysis.selected(event.destination)) try copyFields(&out, &analysis, event);
        if ((inst.op == .i32_load or inst.op == .f32_load) and analysis.selected(event.input.id)) {
            try emit(&out, a, .drop, 0);
            try emit(&out, a, .local_get, analysis.nodes.items[event.input.id].fields + event.field / 4);
            if (inst.op == .f32_load) try emit(&out, a, .f32_reinterpret_i32, 0);
        } else if ((inst.op == .i32_store or inst.op == .f32_store) and analysis.selected(event.input.id)) {
            if (inst.op == .f32_store) try emit(&out, a, .i32_reinterpret_f32, 0);
            try emit(&out, a, .local_set, analysis.nodes.items[event.input.id].fields + event.field / 4);
            try emit(&out, a, .drop, 0);
        } else try out.instructions.append(a, inst);
    }
    return out;
}
pub fn run(a: A, module: *const w.Module, function: *const w.Function) !?Output {
    if (module.arena == null) return null;
    var output: ?Output = null;
    errdefer if (output) |*out| out.deinit(a);
    for (0..4) |_| {
        const locals = if (output) |out| out.locals.items else function.locals.items;
        const instructions = if (output) |out| out.instructions.items else function.instructions.items;
        var allocations: usize = 0;
        for (instructions, 0..) |inst, i| if (inst.op == .call and module.arena.?.isAllocation(inst.operand) and i != 0 and instructions[i - 1].op == .i32_const and instructions[i - 1].operand <= 64) {
            allocations += 1;
        };
        if (allocations == 0) break;
        const next = try pass(a, module, function, locals, instructions) orelse break;
        if (output) |*out| out.deinit(a);
        output = next;
    }
    return output;
}

fn scalarReplacementOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    const p = try module.addLocal(f, .i32);
    const alias = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate },  .{ .op = .local_set, .operand = p },
        .{ .op = .local_get, .operand = p }, .{ .op = .local_get, .operand = 0 },          .{ .op = .i32_store, .operand = 0 },
        .{ .op = .local_get, .operand = p }, .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .f32_store, .operand = 4 },
        .{ .op = .local_get, .operand = p }, .{ .op = .local_set, .operand = alias },      .{ .op = .local_get, .operand = alias },
        .{ .op = .i32_load, .operand = 0 },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
    defer a.free(before);
    var out = (try run(a, &module, &module.functions.items[f])).?;
    defer out.deinit(a);
    for (out.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
}
test "scalar replacement owns scratch and output through every failed allocation" {
    try scalarReplacementOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scalarReplacementOwnership, .{});
}

test "scalar replacement declines incomplete initialization and stores after an alias escapes" {
    const a = std.testing.allocator;
    for (0..3) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addFunction(&.{.i32}, .i32);
        const p = try module.addLocal(f, .i32);
        const alias = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = p } });
        if (scenario == 0) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_, .operand = 0 } });
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .i32_store, .operand = 0 } });
        if (scenario == 0) try module.emit(f, .{ .op = .end });
        if (scenario == 1) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .local_set, .operand = alias } });
        // Scenario 2 reads a never-initialized field; it must retain arena bytes.
        if (scenario != 2) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .i32_const, .operand = 9 }, .{ .op = .i32_store, .operand = 4 } });
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = if (scenario == 1) alias else p }, .{ .op = .i32_load, .operand = 4 } });
        try std.testing.expect(try run(a, &module, &module.functions.items[f]) == null);
    }
}
