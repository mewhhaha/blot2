//! Exact affine bit transforms for a checked, fixed-trip, single-U32 carry.
//! The caller retains source ownership checks and authorizes only this liveout.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const absent = std.math.maxInt(u32);

pub const Word = struct {
    valid: bool = false,
    constant: u32 = 0,
    columns: [32]u32 = @splat(0),

    pub fn literal(bits: u32) Word {
        return .{ .valid = true, .constant = bits };
    }
    pub fn input() Word {
        var result = literal(0);
        for (&result.columns, 0..) |*column, bit| column.* = @as(u32, 1) << @intCast(bit);
        return result;
    }
    pub fn evaluate(self: Word, value: u32) u32 {
        var result = self.constant;
        for (self.columns, 0..) |column, bit| if (value & (@as(u32, 1) << @intCast(bit)) != 0) {
            result ^= column;
        };
        return result;
    }
    fn known(self: Word) ?u32 {
        if (!self.valid) return null;
        for (self.columns) |column| if (column != 0) return null;
        return self.constant;
    }
    fn xor(left: Word, right: Word) Word {
        if (!left.valid or !right.valid) return .{};
        var result = literal(left.constant ^ right.constant);
        for (&result.columns, left.columns, right.columns) |*column, a, b| column.* = a ^ b;
        return result;
    }
    fn mask(self: Word, bits: u32) Word {
        var result = self;
        result.constant &= bits;
        for (&result.columns) |*column| column.* &= bits;
        return result;
    }
    fn shift(self: Word, amount: u32, left: bool) Word {
        const bits: u5 = @truncate(amount);
        var result = self;
        if (left) result.constant <<= bits else result.constant >>= bits;
        for (&result.columns) |*column| {
            if (left) column.* <<= bits else column.* >>= bits;
        }
        return result;
    }
    fn condition(self: Word) ?Word {
        if (!self.valid) return null;
        if (self.known()) |value| return literal(@intFromBool(value != 0));
        var mask_ = self.constant;
        for (self.columns) |column| mask_ |= column;
        if (!std.math.isPowerOfTwo(mask_)) return null;
        return self.shift(@ctz(mask_), false);
    }
    fn choose(condition_: Word, yes: Word, no: Word) Word {
        if (condition_.known()) |bits| {
            if (bits != 0) return yes;
            return no;
        }
        if (std.meta.eql(yes, no)) return yes;
        if (!yes.valid or !no.valid) return .{};
        if (!std.mem.eql(u32, &yes.columns, &no.columns)) return .{};
        const condition_bits = condition_.condition() orelse return .{};
        const difference = yes.constant ^ no.constant;
        var result = no;
        result.constant ^= (0 -% condition_bits.constant) & difference;
        for (&result.columns, condition_bits.columns) |*column, bit| column.* ^= (0 -% bit) & difference;
        return result;
    }
    pub fn repeat(self: Word, count: u32) Word {
        var result = input();
        for (0..count) |_| {
            var next = literal(self.evaluate(result.constant));
            for (&next.columns, result.columns) |*column, old| column.* = self.evaluate(old) ^ self.constant;
            result = next;
        }
        return result;
    }
};

const State = struct {
    const Slot = struct { id: u32, value: Word };
    slots: [96]Slot = undefined,
    len: usize = 0,
    stack: [64]Word = undefined,
    height: usize = 0,
    forbidden: u32 = absent,
    flow: enum { normal, branch, return_ } = .normal,
    label: u32 = 0,

    fn get(self: *const State, id: u32) Word {
        for (self.slots[0..self.len]) |slot| if (slot.id == id) return slot.value;
        return .{};
    }
    fn set(self: *State, id: u32, value: Word) bool {
        for (self.slots[0..self.len]) |*slot| if (slot.id == id) {
            slot.value = value;
            return true;
        };
        if (self.len == self.slots.len) return false;
        self.slots[self.len] = .{ .id = id, .value = value };
        self.len += 1;
        return true;
    }
    fn push(self: *State, value: Word) bool {
        if (self.height == self.stack.len) return false;
        self.stack[self.height] = value;
        self.height += 1;
        return true;
    }
    fn pop(self: *State) ?Word {
        if (self.height == 0) return null;
        self.height -= 1;
        return self.stack[self.height];
    }
};

fn binary(op: ir.Op, left: Word, right: Word) ?Word {
    switch (op) {
        .i32_xor => return left.xor(right),
        .i32_and => {
            if (right.known()) |mask| return left.mask(mask);
            if (left.known()) |mask| return right.mask(mask);
        },
        .i32_or => {
            if (right.known()) |mask| return left.mask(~mask).xor(Word.literal(mask));
            if (left.known()) |mask| return right.mask(~mask).xor(Word.literal(mask));
        },
        .i32_shl, .i32_shr_u => if (right.known()) |amount| return left.shift(amount, op == .i32_shl),
        .i32_eq, .i32_ne => {
            var condition = left.xor(right).condition() orelse return null;
            if (op == .i32_eq) condition = condition.xor(Word.literal(1));
            return condition;
        },
        .i32_sub => if (left.known() == 0) {
            const condition = right.condition() orelse return null;
            if (!std.meta.eql(condition, right)) return null;
            return Word.choose(condition, Word.literal(std.math.maxInt(u32)), Word.literal(0));
        },
        else => {},
    }
    return null;
}

const Limits = struct { instructions: usize = 1_024 };

pub fn canonicalLoop(code: []const ir.Instruction, body_start: usize, body_end: usize, iterator: u32, end: u32) bool {
    const prefix = [_]ir.Instruction{ .{ .op = .block }, .{ .op = .loop }, .{ .op = .local_get, .operand = iterator }, .{ .op = .local_get, .operand = end }, .{ .op = .i32_ge_u }, .{ .op = .br_if, .operand = 1 } };
    const suffix = [_]ir.Instruction{ .{ .op = .local_get, .operand = iterator }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add }, .{ .op = .local_set, .operand = iterator }, .{ .op = .br }, .{ .op = .end }, .{ .op = .end } };
    if (body_start > body_end or body_end > code.len) return false;
    return shellSame(code[0..body_start], &prefix) and shellSame(code[body_end..], &suffix);
}
fn shellSame(actual: []const ir.Instruction, expected: []const ir.Instruction) bool {
    var at: usize = 0;
    for (actual) |inst| {
        if (inst.table_reference or inst.table_kind != .unknown) return false;
        // Source scope cleanup preserves coordinates by erasing unused marks.
        if (inst.op == .nop) continue;
        if (at == expected.len or inst.op != expected[at].op or inst.operand != expected[at].operand) return false;
        at += 1;
    }
    return at == expected.len;
}

fn interpret(module: *const wasm.Module, code: []const ir.Instruction, state: *State, limits: *Limits, depth: usize) bool {
    if (depth >= 12) return false;
    var at: usize = 0;
    while (at < code.len) : (at += 1) {
        if (limits.instructions == 0) return false;
        limits.instructions -= 1;
        const inst = code[at];
        if (inst.table_reference or inst.table_kind != .unknown) return false;
        switch (inst.op) {
            .nop => {},
            .i32_const => if (!state.push(Word.literal(inst.operand))) return false,
            .local_get => {
                if (inst.operand == state.forbidden or !state.push(state.get(inst.operand))) return false;
            },
            .local_set, .local_tee => {
                const value = state.pop() orelse return false;
                if (inst.operand == state.forbidden or !state.set(inst.operand, value)) return false;
                if (inst.op == .local_tee and !state.push(value)) return false;
            },
            .drop => _ = state.pop() orelse return false,
            .block, .if_ => {
                var end = at + 1;
                var nested: usize = 0;
                var alternate: ?usize = null;
                while (end < code.len) : (end += 1) switch (code[end].op) {
                    .block, .if_ => nested += 1,
                    .else_ => if (nested == 0) {
                        if (inst.op != .if_ or alternate != null) return false;
                        alternate = end;
                    },
                    .end => {
                        if (nested == 0) break;
                        nested -= 1;
                    },
                    else => {},
                };
                if (end == code.len) return false;
                if (inst.op == .block) {
                    if (!interpret(module, code[at + 1 .. end], state, limits, depth + 1)) return false;
                } else {
                    const condition = (state.pop() orelse return false).condition() orelse return false;
                    var yes = state.*;
                    var no = state.*;
                    if (!interpret(module, code[at + 1 .. alternate orelse end], &yes, limits, depth + 1)) return false;
                    if (alternate) |other| if (!interpret(module, code[other + 1 .. end], &no, limits, depth + 1)) return false;
                    if (yes.flow != no.flow or yes.label != no.label or yes.height != no.height) return false;
                    state.flow = yes.flow;
                    state.label = yes.label;
                    for (yes.slots[0..yes.len]) |slot| if (!state.set(slot.id, Word.choose(condition, slot.value, no.get(slot.id)))) return false;
                    for (no.slots[0..no.len]) |slot| if (!state.set(slot.id, Word.choose(condition, yes.get(slot.id), slot.value))) return false;
                    state.height = yes.height;
                    for (state.stack[0..state.height], yes.stack[0..yes.height], no.stack[0..no.height]) |*value, a, b| value.* = Word.choose(condition, a, b);
                }
                at = end;
                if (state.flow == .branch) {
                    if (state.label != 0) {
                        state.label -= 1;
                        return true;
                    }
                    state.flow = .normal;
                } else if (state.flow == .return_) return true;
            },
            .br => {
                state.flow = .branch;
                state.label = inst.operand;
                return true;
            },
            .return_ => {
                state.flow = .return_;
                return true;
            },
            .call => {
                if (inst.operand >= module.functions.items.len or module.runtimeHelper(inst.operand)) return false;
                const callee = &module.functions.items[inst.operand];
                if (callee.entry or callee.result != .i32 or callee.result_role != .scalar or callee.instructions.items.len > 128 or callee.parameters.len + callee.locals.items.len > 32 or callee.parameters.len > state.height) return false;
                for (callee.parameters) |machine| if (machine != .i32) return false;
                for (callee.locals.items) |machine| if (machine != .i32) return false;
                var child: State = .{};
                const first = state.height - callee.parameters.len;
                for (state.stack[first..state.height], 0..) |value, index| if (!child.set(@intCast(index), value)) return false;
                state.height = first;
                for (callee.locals.items, callee.parameters.len..) |_, index| if (!child.set(@intCast(index), Word.literal(0))) return false;
                if (!interpret(module, callee.instructions.items, &child, limits, depth + 1) or child.flow == .branch or child.height != 1 or !state.push(child.stack[0])) return false;
            },
            .i32_eqz => {
                const value = (state.pop() orelse return false).condition() orelse return false;
                if (!state.push(value.xor(Word.literal(1)))) return false;
            },
            else => {
                const right = state.pop() orelse return false;
                const left = state.pop() orelse return false;
                const value = binary(inst.op, left, right) orelse return false;
                if (!state.push(value)) return false;
            },
        }
    }
    return true;
}

/// Only the source emitter can authorize the single observable carry. All
/// other writes must belong to lexical loop temporaries; iteration is unused.
pub fn analyze(module: *const wasm.Module, code: []const ir.Instruction, carry: u32, iterator: u32, count: u32) ?Word {
    if (count == 0 or count > 8 or code.len > 256) return null;
    var state: State = .{ .forbidden = iterator };
    if (!state.set(carry, Word.input())) return null;
    var limits: Limits = .{};
    if (!interpret(module, code, &state, &limits, 0) or state.flow != .normal or state.height != 0) return null;
    const result = state.get(carry);
    if (!result.valid) return null;
    return result.repeat(count);
}

pub fn analyzeLoop(module: *const wasm.Module, code: []const ir.Instruction, carry: u32, iterator: u32, end: u32, count: u32) ?Word {
    if (carry == end or iterator == end) return null;
    for (code) |inst| if ((inst.op == .local_set or inst.op == .local_tee) and inst.operand == end) return null;
    return analyze(module, code, carry, iterator, count);
}

const Term = union(enum) { shifted: u5, column: struct { bit: u5, bits: u32 }, literal: u32 };
fn emitTerms(a: std.mem.Allocator, output: *ir.Body, terms: []const Term, carry: u32) std.mem.Allocator.Error!void {
    if (terms.len > 1) {
        const middle = terms.len / 2;
        try emitTerms(a, output, terms[0..middle], carry);
        try emitTerms(a, output, terms[middle..], carry);
        return output.emit(a, .i32_xor, 0);
    }
    switch (terms[0]) {
        .literal => |bits| try output.emit(a, .i32_const, bits),
        .shifted => |bits| {
            try output.emit(a, .local_get, carry);
            if (bits != 0) {
                try output.emit(a, .i32_const, bits);
                try output.emit(a, .i32_shr_u, 0);
            }
        },
        .column => |column| {
            try output.emit(a, .i32_const, 0);
            try output.emit(a, .local_get, carry);
            if (column.bit != 0) {
                try output.emit(a, .i32_const, column.bit);
                try output.emit(a, .i32_shr_u, 0);
            }
            try output.emit(a, .i32_const, 1);
            try output.emit(a, .i32_and, 0);
            try output.emit(a, .i32_sub, 0);
            try output.emit(a, .i32_const, column.bits);
            try output.emit(a, .i32_and, 0);
        },
    }
}

/// Factor a common logical shift, then combine independent corrections with a
/// balanced XOR tree. Large transforms retain the original loop.
pub fn emit(a: std.mem.Allocator, transform: Word, carry: u32) std.mem.Allocator.Error!?ir.Body {
    var best_shift: u32 = 32;
    var best_count: usize = 33;
    for (0..33) |shift| {
        var count: usize = @intFromBool(shift != 32);
        for (transform.columns, 0..) |column, bit| {
            var base: u32 = 0;
            if (shift != 32) base = (@as(u32, 1) << @intCast(bit)) >> @as(u5, @intCast(shift));
            count += @intFromBool(column != base);
        }
        if (count < best_count) {
            best_count = count;
            best_shift = @intCast(shift);
        }
    }
    if (best_count > 16) return null;
    var terms: [34]Term = undefined;
    var count: usize = 0;
    if (transform.constant != 0) {
        terms[count] = .{ .literal = transform.constant };
        count += 1;
    }
    if (best_shift != 32) {
        terms[count] = .{ .shifted = @intCast(best_shift) };
        count += 1;
    }
    for (transform.columns, 0..) |column, bit| {
        var base: u32 = 0;
        if (best_shift != 32) base = (@as(u32, 1) << @intCast(bit)) >> @as(u5, @intCast(best_shift));
        if (column == base) continue;
        terms[count] = .{ .column = .{ .bit = @intCast(bit), .bits = column ^ base } };
        count += 1;
    }
    if (count == 0) {
        terms[0] = .{ .literal = 0 };
        count = 1;
    }
    var output: ir.Body = .{};
    errdefer output.deinit(a);
    try emitTerms(a, &output, terms[0..count], carry);
    try output.emit(a, .local_set, carry);
    return output;
}

fn recurrenceCode(polynomial: u32) [23]ir.Instruction {
    return .{
        .{ .op = .local_get, .operand = 17 }, .{ .op = .i32_const, .operand = 1 },          .{ .op = .i32_and },
        .{ .op = .if_ },                      .{ .op = .local_get, .operand = 17 },         .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_shr_u },                .{ .op = .i32_const, .operand = polynomial }, .{ .op = .i32_xor },
        .{ .op = .local_set, .operand = 18 }, .{ .op = .else_ },                            .{ .op = .local_get, .operand = 17 },
        .{ .op = .i32_const, .operand = 1 },  .{ .op = .i32_shr_u },                        .{ .op = .local_set, .operand = 18 },
        .{ .op = .end },                      .{ .op = .local_get, .operand = 18 },         .{ .op = .local_set, .operand = 17 },
        .{ .op = .nop },                      .{ .op = .nop },                              .{ .op = .nop },
        .{ .op = .nop },                      .{ .op = .nop },
    };
}
fn step(value: u32, polynomial: u32) u32 {
    if (value & 1 != 0) return (value >> 1) ^ polynomial;
    return value >> 1;
}

test "affine bit loop composition proves arbitrary polynomials counts bases and emitted masks" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    for ([_]u32{ 0, 1, 2, 0xffffffff, 0x80000000, 0xEDB88320, 0xA24BAED4, 0x12345678 }) |polynomial| {
        const code = recurrenceCode(polynomial);
        for (1..9) |count| {
            const transform = analyze(&module, &code, 17, 99, @intCast(count)) orelse return error.MissingProof;
            var emitted = (try emit(a, transform, 17)) orelse return error.MissingEmission;
            defer emitted.deinit(a);
            const checked = analyze(&module, emitted.instructions.items, 17, 99, 1) orelse return error.MissingEmissionProof;
            try std.testing.expectEqual(transform, checked);
            // Exact affine admission makes these basis checks a proof for all
            // U32 inputs. Mixed inputs additionally guard composition code.
            for (0..32) |bit| {
                const input_ = @as(u32, 1) << @intCast(bit);
                var expected = input_;
                for (0..count) |_| expected = step(expected, polynomial);
                try std.testing.expectEqual(expected, transform.evaluate(input_));
            }
            var seed: u32 = 771923;
            for (0..256) |_| {
                seed = seed *% 1664525 +% 1013904223;
                var expected = seed;
                for (0..count) |_| expected = step(expected, polynomial);
                try std.testing.expectEqual(expected, transform.evaluate(seed));
            }
        }
    }
    const offset_code = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 17 },         .{ .op = .i32_const, .operand = 33 }, .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 0x12345678 }, .{ .op = .i32_xor },                  .{ .op = .local_set, .operand = 17 },
    };
    for (1..9) |count| {
        const transform = analyze(&module, &offset_code, 17, 99, @intCast(count)) orelse return error.MissingProof;
        for ([_]u32{ 0, 1, 0xFFFFFFFF, 0x80000000, 0x12345678 }) |input_| {
            var expected = input_;
            for (0..count) |_| expected = (expected >> 1) ^ 0x12345678;
            try std.testing.expectEqual(expected, transform.evaluate(input_));
        }
    }
}

test "affine bit loops reject nonlinear effects iterator reads exits unknowns and changed helper bodies" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    var code = recurrenceCode(0xEDB88320);
    for ([_]ir.Op{ .i32_add, .i32_mul, .i32_div_u, .i32_load, .i32_store, .global_get, .global_set, .call_import, .call_indirect, .memory_grow, .ownership, .return_ }) |op| {
        code[8].op = op;
        try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    }
    code = recurrenceCode(0xEDB88320);
    code[4].operand = 99;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code[4].operand = 55;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code = recurrenceCode(0xEDB88320);
    try std.testing.expect(analyze(&module, &code, 17, 99, 0) == null);
    try std.testing.expect(analyze(&module, &code, 17, 99, 9) == null);
    const helper = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
    try module.emitSlice(helper, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_xor } });
    code[8] = .{ .op = .call, .operand = helper };
    const before = analyze(&module, &code, 17, 99, 8) orelse return error.MissingProof;
    code[8].table_reference = true;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code[8].table_reference = false;
    code[8].table_kind = .callable;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code[8].table_kind = .unknown;
    module.functions.items[helper].instructions.items[2].op = .i32_add;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    module.functions.items[helper].instructions.items[2].op = .i32_xor;
    try std.testing.expectEqual(before, analyze(&module, &code, 17, 99, 8) orelse return error.MissingProof);
    code[1].operand = 3;
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code = recurrenceCode(0xEDB88320);
    code[8] = .{ .op = .br, .operand = 99 };
    try std.testing.expect(analyze(&module, &code, 17, 99, 8) == null);
    code = recurrenceCode(0xEDB88320);
    code[18] = .{ .op = .i32_const, .operand = 8 };
    code[19] = .{ .op = .local_set, .operand = 98 };
    try std.testing.expect(analyzeLoop(&module, &code, 17, 99, 98, 8) == null);
}

fn emissionAllocation(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const code = recurrenceCode(0x12345678);
    const transform = analyze(&module, &code, 17, 99, 8) orelse return error.MissingProof;
    var output = (try emit(a, transform, 17)) orelse return error.MissingEmission;
    defer output.deinit(a);
    try std.testing.expect(output.instructions.items.len != 0);
    try std.testing.expectEqual(@as(u32, 0x12345678), code[7].operand);
}
test "affine bit emission owns detached output and preserves its source through allocation failure" {
    try emissionAllocation(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, emissionAllocation, .{});
}
