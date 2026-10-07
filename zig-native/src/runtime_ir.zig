//! Compact typed stack IR, before Wasm encoding. Bodies own typed parameters
//! and locals; opcodes have exhaustive operand/result/effect contracts. Dynamic
//! calls resolve their signatures against the module, never a guessed arity.
//! An i32 word is not proof of a heap reference. Allocation and field ownership
//! require provenance in the lifetime analysis or an explicit heap layout.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const ValueType = enum(u8) { i32 = 0x7f, f32 = 0x7d, v128 = 0x7b, externref = 0x6f, none = 0x40 };
pub const Scalar = enum(u8) {
    unit = 0,
    u32 = 1,
    bool = 2,
    f32 = 3,
    array_u32 = 5,
    array_f32 = 6,
    pointer = 7,
    pub fn machine(self: Scalar) ValueType {
        return if (self == .f32) .f32 else .i32;
    }
};
pub const Op = enum(u8) {
    unreachable_,
    nop,
    block,
    loop,
    if_,
    else_,
    end,
    br,
    br_if,
    return_,
    call,
    call_import,
    call_indirect,
    host_ref_get,
    host_ref_set,
    host_ref_size,
    host_ref_grow,
    host_ref_null,
    host_ref_is_null,
    drop,
    local_get,
    local_set,
    local_tee,
    global_get,
    global_set,
    i32_load,
    f32_load,
    i32_store,
    f32_store,
    memory_size,
    memory_grow,
    memory_copy,
    memory_fill,
    i32_reinterpret_f32,
    f32_reinterpret_i32,
    i32_const,
    f32_const,
    i32_eqz,
    i32_eq,
    i32_ne,
    i32_lt_u,
    i32_gt_u,
    i32_le_u,
    i32_ge_u,
    f32_eq,
    f32_ne,
    f32_lt,
    f32_gt,
    f32_le,
    f32_ge,
    i32_add,
    i32_sub,
    i32_mul,
    i32_div_u,
    i32_rem_u,
    i32_and,
    i32_or,
    i32_xor,
    i32_shl,
    i32_shr_u,
    i32_clz,
    i32_ctz,
    f32_abs,
    f32_neg,
    f32_ceil,
    f32_floor,
    f32_trunc,
    f32_sqrt,
    f32_add,
    f32_sub,
    f32_mul,
    f32_div,
    f32_min,
    f32_max,
    i32_trunc_sat_f32_u,
    f32_convert_i32_u,
    v128_load,
    v128_store,
    i32x4_splat,
    f32x4_splat,
    i32x4_replace_lane,
    i32x4_extract_lane,
    f32x4_extract_lane,
    i32x4_add,
    i32x4_sub,
    i32x4_mul,
    v128_and,
    v128_or,
    v128_xor,
    f32x4_abs,
    f32x4_neg,
    f32x4_ceil,
    f32x4_floor,
    f32x4_trunc,
    f32x4_sqrt,
    f32x4_add,
    f32x4_sub,
    f32x4_mul,
    f32x4_div,
    f32x4_convert_i32x4_u,
    i32x4_trunc_sat_f32x4_u,
};
pub const FunctionId = enum(u32) { _ };
pub const LocalId = enum(u32) { _ };
pub const SignatureId = enum(u32) { _ };
pub const Instruction = struct {
    op: Op,
    operand: u32 = 0,

    pub fn callee(self: Instruction) FunctionId {
        std.debug.assert(self.op == .call);
        return @fromBackingInt(@intCast(self.operand));
    }
    pub fn local(self: Instruction) LocalId {
        std.debug.assert(self.op == .local_get or self.op == .local_set or self.op == .local_tee);
        return @fromBackingInt(@intCast(self.operand));
    }
    pub fn signature(self: Instruction) SignatureId {
        std.debug.assert(self.op == .call_indirect);
        return @fromBackingInt(@intCast(self.operand));
    }
};
pub const Signature = struct { parameters: []ValueType, result: ValueType };
pub const Function = struct {
    parameters: []ValueType,
    result: ValueType,
    signature: u32,
    locals: std.ArrayList(ValueType) = .empty,
    instructions: std.ArrayList(Instruction) = .empty,
    pub fn deinit(self: *Function, allocator: Allocator) void {
        self.locals.deinit(allocator);
        self.instructions.deinit(allocator);
    }
};

/// Mutable output of one pass; retained input bodies stay immutable.
pub const Body = struct {
    locals: std.ArrayList(ValueType) = .empty,
    instructions: std.ArrayList(Instruction) = .empty,
    pub fn emit(self: *Body, a: Allocator, op: Op, operand: u32) Allocator.Error!void {
        try self.instructions.append(a, .{ .op = op, .operand = operand });
    }
    pub fn deinit(self: *Body, a: Allocator) void {
        self.locals.deinit(a);
        self.instructions.deinit(a);
    }
};

pub const Effect = enum { pure, local, global, read, write, memory, host, call, control, trap };
pub const Contract = struct {
    inputs: [3]ValueType = .{ .none, .none, .none },
    arity: usize = 0,
    result: ValueType = .none,
    effect: Effect = .pure,
    bytes: u8 = 0,
    may_trap: bool = false,
};
fn signature(comptime inputs: []const ValueType, result: ValueType, effect: Effect) Contract {
    var value: Contract = .{ .arity = inputs.len, .result = result, .effect = effect };
    for (inputs, 0..) |ty, i| value.inputs[i] = ty;
    return value;
}
fn memory(value: ValueType, store: bool) Contract {
    return .{ .inputs = .{ .i32, if (store) value else .none, .none }, .arity = if (store) 2 else 1, .result = if (store) .none else value, .effect = if (store) .write else .read, .bytes = if (value == .v128) 16 else 4, .may_trap = true };
}
/// Exhaustive: adding an opcode requires a type and effect contract here.
/// Calls, locals, globals and control payloads are refined by `contract`.
pub fn fixed(op: Op) Contract {
    return switch (op) {
        .unreachable_ => .{ .effect = .trap, .may_trap = true },
        .nop => .{},
        .block, .loop, .else_, .end, .br, .return_ => .{ .effect = .control },
        .if_, .br_if => signature(&.{.i32}, .none, .control),
        .call, .call_import, .call_indirect => .{ .effect = .call, .may_trap = true },
        .local_get, .global_get => .{ .effect = if (op == .local_get) .local else .global },
        .local_set, .local_tee, .global_set => .{ .arity = 1, .effect = if (op == .global_set) .global else .local },
        .drop => .{ .arity = 1 },
        .host_ref_get => .{ .inputs = .{ .i32, .none, .none }, .arity = 1, .result = .externref, .effect = .host, .may_trap = true },
        .host_ref_set => .{ .inputs = .{ .i32, .externref, .none }, .arity = 2, .effect = .host, .may_trap = true },
        .host_ref_grow => signature(&.{ .externref, .i32 }, .i32, .host),
        .host_ref_size => signature(&.{}, .i32, .host),
        .host_ref_null => signature(&.{}, .externref, .pure),
        .host_ref_is_null => signature(&.{.externref}, .i32, .pure),
        .i32_load => memory(.i32, false),
        .f32_load => memory(.f32, false),
        .v128_load => memory(.v128, false),
        .i32_store => memory(.i32, true),
        .f32_store => memory(.f32, true),
        .v128_store => memory(.v128, true),
        .memory_size => signature(&.{}, .i32, .memory),
        .memory_grow => signature(&.{.i32}, .i32, .memory),
        .memory_copy, .memory_fill => .{ .inputs = .{ .i32, .i32, .i32 }, .arity = 3, .effect = .write, .may_trap = true },
        .i32_const => signature(&.{}, .i32, .pure),
        .f32_const => signature(&.{}, .f32, .pure),
        .i32_eqz, .i32_clz, .i32_ctz => signature(&.{.i32}, .i32, .pure),
        .i32_eq, .i32_ne, .i32_lt_u, .i32_gt_u, .i32_le_u, .i32_ge_u, .i32_add, .i32_sub, .i32_mul, .i32_and, .i32_or, .i32_xor, .i32_shl, .i32_shr_u => signature(&.{ .i32, .i32 }, .i32, .pure),
        .i32_div_u, .i32_rem_u => .{ .inputs = .{ .i32, .i32, .none }, .arity = 2, .result = .i32, .may_trap = true },
        .f32_eq, .f32_ne, .f32_lt, .f32_gt, .f32_le, .f32_ge => signature(&.{ .f32, .f32 }, .i32, .pure),
        .f32_add, .f32_sub, .f32_mul, .f32_div, .f32_min, .f32_max => signature(&.{ .f32, .f32 }, .f32, .pure),
        .f32_abs, .f32_neg, .f32_ceil, .f32_floor, .f32_trunc, .f32_sqrt => signature(&.{.f32}, .f32, .pure),
        .i32_reinterpret_f32, .i32_trunc_sat_f32_u => signature(&.{.f32}, .i32, .pure),
        .f32_reinterpret_i32, .f32_convert_i32_u => signature(&.{.i32}, .f32, .pure),
        .i32x4_splat => signature(&.{.i32}, .v128, .pure),
        .f32x4_splat => signature(&.{.f32}, .v128, .pure),
        .i32x4_replace_lane => signature(&.{ .v128, .i32 }, .v128, .pure),
        .i32x4_extract_lane => signature(&.{.v128}, .i32, .pure),
        .f32x4_extract_lane => signature(&.{.v128}, .f32, .pure),
        .i32x4_add, .i32x4_sub, .i32x4_mul, .v128_and, .v128_or, .v128_xor, .f32x4_add, .f32x4_sub, .f32x4_mul, .f32x4_div => signature(&.{ .v128, .v128 }, .v128, .pure),
        .f32x4_abs, .f32x4_neg, .f32x4_ceil, .f32x4_floor, .f32x4_trunc, .f32x4_sqrt, .f32x4_convert_i32x4_u, .i32x4_trunc_sat_f32x4_u => signature(&.{.v128}, .v128, .pure),
    };
}

pub const Call = struct {
    parameters: []const ValueType,
    result: ValueType,
    selector: bool = false,
    ownership: enum { unknown, allocate, allocate_scalar, release, collect } = .unknown,
};
pub fn call(module: *const @import("wasm.zig").Module, inst: Instruction) Call {
    switch (inst.op) {
        .call => {
            const callee = module.functions.items[@backingInt(inst.callee())];
            var result: Call = .{ .parameters = callee.parameters, .result = callee.result };
            if (module.arena) |arena| {
                if (inst.operand == arena.allocate) result.ownership = .allocate;
                if (inst.operand == arena.allocate_scalar) result.ownership = .allocate_scalar;
                if (inst.operand == arena.recycle) result.ownership = .release;
                if (inst.operand == arena.collect or inst.operand == arena.reset) result.ownership = .collect;
            }
            return result;
        },
        .call_import, .call_indirect => {
            const id = if (inst.op == .call_indirect) @backingInt(inst.signature()) else module.imports.items[inst.operand].signature;
            const callee = module.signatures.items[id];
            return .{ .parameters = callee.parameters, .result = callee.result, .selector = inst.op == .call_indirect };
        },
        else => unreachable,
    }
}

pub fn contract(module: *const @import("wasm.zig").Module, function: *const Function, inst: Instruction) Contract {
    var result = fixed(inst.op);
    switch (inst.op) {
        .call, .call_import, .call_indirect => {
            const callee = call(module, inst);
            result.arity = callee.parameters.len + @intFromBool(callee.selector);
            result.result = callee.result;
        },
        .local_get, .local_set, .local_tee => {
            const id = @backingInt(inst.local());
            const ty = if (id < function.parameters.len) function.parameters[id] else function.locals.items[id - function.parameters.len];
            if (inst.op != .local_get) result.inputs[0] = ty;
            if (inst.op != .local_set) result.result = ty;
        },
        .global_get, .global_set => {
            const ty = module.globals.items[inst.operand].scalar.machine();
            if (inst.op == .global_get) result.result = ty else result.inputs[0] = ty;
        },
        .return_ => {
            result.inputs[0] = function.result;
            result.arity = @intFromBool(function.result != .none);
        },
        else => {},
    }
    return result;
}

pub fn lift(op: Op) ?Op {
    return switch (op) {
        .i32_add => .i32x4_add,
        .i32_sub => .i32x4_sub,
        .i32_mul => .i32x4_mul,
        .i32_and => .v128_and,
        .i32_or => .v128_or,
        .i32_xor => .v128_xor,
        .f32_abs => .f32x4_abs,
        .f32_neg => .f32x4_neg,
        .f32_ceil => .f32x4_ceil,
        .f32_floor => .f32x4_floor,
        .f32_trunc => .f32x4_trunc,
        .f32_sqrt => .f32x4_sqrt,
        .f32_add => .f32x4_add,
        .f32_sub => .f32x4_sub,
        .f32_mul => .f32x4_mul,
        .f32_div => .f32x4_div,
        .f32_convert_i32_u => .f32x4_convert_i32x4_u,
        .i32_trunc_sat_f32_u => .i32x4_trunc_sat_f32x4_u,
        else => null,
    };
}
