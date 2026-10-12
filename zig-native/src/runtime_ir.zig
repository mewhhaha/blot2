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
    /// Arrays and pointers cross the ABI as heap references.
    pub fn role(self: Scalar) Role {
        return switch (self) {
            .unit, .u32, .bool, .f32 => .scalar,
            .array_u32, .array_f32, .pointer => .reference,
        };
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
    /// Ownership facts from checked layouts (`Ownership`). It has no stack
    /// effect, is never encoded, and is not code for size heuristics.
    ownership,
};
/// What a 32-bit word or parameter may hold, from its checked layout.
pub const Role = enum(u2) {
    /// No layout fact; analyses stay conservative.
    unknown,
    /// Never a heap reference, whatever its machine type.
    scalar,
    /// A heap reference or zero.
    reference,
    /// A word whose layout admits both, such as an erased payload.
    value,
};
/// The operand of `.ownership`. A run of annotations immediately before an
/// allocation's `i32_const size; call allocate` gives the roles of its words:
/// `words` annotations cover `words_per_chunk` words each, chunks 0, 1, ... in
/// order, and a final `rest` annotation, always present, ends the run with the
/// number of explicitly described words and one role for every later word. Anywhere else, for example where a
/// pass removed the allocation, an annotation describes nothing.
pub const Ownership = packed struct(u32) {
    pub const words_per_chunk = 13;
    pub const Kind = enum(u2) { words, rest, scope, call_result };
    kind: Kind,
    chunk: u4 = 0,
    roles: u26 = 0,

    /// Scope operands refer to locals even though they have no machine stack effect.
    pub fn relocated(self: Ownership, base: u32) Ownership {
        var result = self;
        if (self.kind != .scope) return result;
        switch (self.chunk) {
            2, 3, 5, 6 => result.roles = @intCast(self.roles + base),
            4 => result.roles = @intCast((self.roles & 8191) + base + ((self.roles >> 13) + base) * 8192),
            else => {},
        }
        return result;
    }

    pub fn role(self: Ownership, index: usize) Role {
        return @fromBackingInt(@intCast(@as(u2, @truncate(self.roles >> @intCast(index * 2)))));
    }
    /// Words a `rest` annotation's run describes explicitly.
    pub fn explicitWords(self: Ownership) usize {
        return self.roles >> 2;
    }
    /// The role of word `word` in the annotation run `run`, which ends with
    /// its `rest` annotation.
    pub fn wordRole(run: []const Instruction, word: usize) Role {
        if (run.len == 0) return .unknown;
        const terminator: Ownership = @bitCast(run[run.len - 1].operand);
        if (terminator.kind != .rest) return .unknown;
        if (word >= terminator.explicitWords()) return terminator.role(0);
        for (run[0 .. run.len - 1]) |instruction| {
            const annotation: Ownership = @bitCast(instruction.operand);
            const first = @as(usize, annotation.chunk) * words_per_chunk;
            if (annotation.kind == .words and word >= first and word < first + words_per_chunk) return annotation.role(word - first);
        }
        return .unknown;
    }
};
/// A checked indirect result keeps its ownership role before machine lowering.
/// It describes only the immediately following indirect call, never an i32 type.
pub fn callResult(role: Role) Instruction {
    const annotation: Ownership = .{ .kind = .call_result, .roles = @backingInt(role) };
    return .{ .op = .ownership, .operand = @bitCast(annotation) };
}
pub fn indirectResult(instructions: []const Instruction, at: usize) Role {
    if (at == 0 or at >= instructions.len or instructions[at].op != .call_indirect or instructions[at - 1].op != .ownership) return .unknown;
    const annotation: Ownership = @bitCast(instructions[at - 1].operand);
    if (annotation.kind != .call_result or annotation.chunk != 0 or annotation.roles > @backingInt(Role.value)) return .unknown;
    return @fromBackingInt(@as(u2, @intCast(annotation.roles)));
}
/// The most annotations one allocation's run needs.
pub const max_annotations = 17;
/// The annotation run for an allocation whose first words have `words` roles
/// and whose remaining words have `rest`. Words past 16 chunks are unknown.
pub fn annotations(words: []const Role, rest: Role, out: *[max_annotations]Instruction) []Instruction {
    const chunks = (words.len + Ownership.words_per_chunk - 1) / Ownership.words_per_chunk;
    var count: usize = 0;
    for (0..@min(chunks, 16)) |chunk| {
        const slice = words[chunk * Ownership.words_per_chunk ..][0..@min(Ownership.words_per_chunk, words.len - chunk * Ownership.words_per_chunk)];
        var roles: u26 = 0;
        for (slice, 0..) |item, index| roles |= @as(u26, @backingInt(item)) << @intCast(index * 2);
        const operand: Ownership = .{ .kind = .words, .chunk = @intCast(chunk), .roles = roles };
        out[count] = .{ .op = .ownership, .operand = @bitCast(operand) };
        count += 1;
    }
    // Words past 16 chunks are unknown: the run then describes 16 chunks and
    // leaves every later word unknown.
    const explicit: u26 = @intCast(@min(words.len, 16 * Ownership.words_per_chunk));
    const terminator: Ownership = .{ .kind = .rest, .roles = (explicit << 2) | @as(u26, if (chunks > 16) 0 else @backingInt(rest)) };
    out[count] = .{ .op = .ownership, .operand = @bitCast(terminator) };
    return out[0 .. count + 1];
}
/// The annotation run describing the allocation call at `at`: a `rest`
/// annotation immediately before its `i32_const` size, preceded by that run's
/// `words` chunks counting down to chunk 0. Anything else describes nothing.
pub fn allocationAnnotations(instructions: []const Instruction, at: usize) []const Instruction {
    if (at < 2 or instructions[at - 1].op != .i32_const) return &.{};
    const end = at - 1;
    if (instructions[end - 1].op != .ownership or @as(Ownership, @bitCast(instructions[end - 1].operand)).kind != .rest) return &.{};
    var start = end - 1;
    if (start == 0 or instructions[start - 1].op != .ownership) return instructions[start..end];
    const highest: Ownership = @bitCast(instructions[start - 1].operand);
    if (highest.kind != .words) return instructions[start..end];
    var chunk: u4 = highest.chunk;
    while (true) {
        if (start == 0 or instructions[start - 1].op != .ownership) return &.{};
        const annotation: Ownership = @bitCast(instructions[start - 1].operand);
        if (annotation.kind != .words or annotation.chunk != chunk) return &.{};
        start -= 1;
        if (chunk == 0) return instructions[start..end];
        chunk -= 1;
    }
}
/// Instructions that are code, excluding ownership annotations.
pub fn codeLength(instructions: []const Instruction) usize {
    var count: usize = 0;
    for (instructions) |instruction| count += @intFromBool(instruction.op != .ownership);
    return count;
}
pub const FunctionId = enum(u32) { _ };
pub const LocalId = enum(u32) { _ };
pub const SignatureId = enum(u32) { _ };
pub const Instruction = struct {
    op: Op,
    operand: u32 = 0,
    /// A table slot is a symbolic function target, never an integer literal.
    /// This flag occupies existing padding in the eight-byte instruction.
    table_reference: bool = false,

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
    /// Checked language result, independently of the machine result type.
    result_role: Role = .unknown,
    /// Public invocation wrapper, with its own outer ownership frame.
    entry: bool = false,
    signature: u32,
    /// Parameter roles from checked layouts, two bits per parameter (see
    /// `parameterRole`). Zero leaves every parameter unknown.
    parameter_roles: u64 = 0,
    /// Ownership annotations among `instructions`, which are not code.
    annotations: u32 = 0,
    locals: std.ArrayList(ValueType) = .empty,
    instructions: std.ArrayList(Instruction) = .empty,
    pub fn deinit(self: *Function, allocator: Allocator) void {
        self.locals.deinit(allocator);
        self.instructions.deinit(allocator);
    }
    /// Instructions that are code, as size heuristics count them.
    pub fn codeLength(self: *const Function) usize {
        return self.instructions.items.len - self.annotations;
    }
    pub fn parameterRole(self: *const Function, index: usize) Role {
        if (index >= 32) return .unknown;
        return @fromBackingInt(@intCast(@as(u2, @truncate(self.parameter_roles >> @intCast(index * 2)))));
    }
};
/// Packs parameter roles for `Function.parameter_roles`; parameters past the
/// 32nd stay unknown.
pub fn packParameterRoles(roles: []const Role) u64 {
    var result: u64 = 0;
    for (roles[0..@min(roles.len, 32)], 0..) |role, index| result |= @as(u64, @backingInt(role)) << @intCast(index * 2);
    return result;
}

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
        .nop, .ownership => .{},
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
    ownership: enum { unknown, allocate, allocate_scalar, allocate_typed, release, collect } = .unknown,
};
pub fn call(module: *const @import("wasm.zig").Module, inst: Instruction) Call {
    switch (inst.op) {
        .call => {
            const callee = module.functions.items[@backingInt(inst.callee())];
            var result: Call = .{ .parameters = callee.parameters, .result = callee.result };
            if (module.arena) |arena| {
                if (inst.operand == arena.allocate) result.ownership = .allocate;
                if (inst.operand == arena.allocate_scalar) result.ownership = .allocate_scalar;
                if (inst.operand == arena.allocate_typed or inst.operand == arena.root_allocate) result.ownership = .allocate_typed;
                if (inst.operand == arena.recycle) result.ownership = .release;
                if (inst.operand == arena.collect or inst.operand == arena.reset or inst.operand == arena.cycle_collect or inst.operand == arena.cycle_safe) result.ownership = .collect;
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

test "ownership runs describe only the allocation they precede" {
    var buffer: [max_annotations]Instruction = undefined;
    var words: [15]Role = undefined;
    for (&words, 0..) |*role, index| role.* = if (index % 2 == 0) .scalar else .reference;
    const run = annotations(&words, .value, &buffer);
    try std.testing.expectEqual(@as(usize, 3), run.len);
    var body: std.ArrayList(Instruction) = .empty;
    defer body.deinit(std.testing.allocator);
    // An orphaned run, left by a removed allocation, sits directly before
    // the next allocation's own run and must not leak into it.
    var orphan: [max_annotations]Instruction = undefined;
    try body.appendSlice(std.testing.allocator, annotations(&.{ .reference, .reference }, .unknown, &orphan));
    try body.appendSlice(std.testing.allocator, run);
    try body.appendSlice(std.testing.allocator, &.{ .{ .op = .i32_const, .operand = 64 }, .{ .op = .call, .operand = 3 } });
    const found = allocationAnnotations(body.items, body.items.len - 1);
    try std.testing.expectEqual(run.len, found.len);
    for (words, 0..) |role, index| try std.testing.expectEqual(role, Ownership.wordRole(found, index));
    try std.testing.expectEqual(Role.value, Ownership.wordRole(found, 15));
    try std.testing.expectEqual(@as(usize, 2), codeLength(body.items));
    // A run separated from the size by other code describes nothing.
    const separated = [_]Instruction{ run[run.len - 1], .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = 3 } };
    try std.testing.expectEqual(@as(usize, 0), allocationAnnotations(&separated, 3).len);
    // A run missing its first chunk describes nothing.
    const truncated = [_]Instruction{ run[1], run[2], .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = 3 } };
    try std.testing.expectEqual(@as(usize, 0), allocationAnnotations(&truncated, 3).len);
    try std.testing.expectEqual(@as(usize, 3), codeLength(&separated));
    try std.testing.expectEqual(@as(usize, 2), codeLength(&truncated));
}

test "parameter roles pack two bits per parameter" {
    var function: Function = .{ .parameters = &.{}, .result = .none, .signature = 0, .parameter_roles = packParameterRoles(&.{ .reference, .scalar, .value }) };
    try std.testing.expectEqual(Role.reference, function.parameterRole(0));
    try std.testing.expectEqual(Role.scalar, function.parameterRole(1));
    try std.testing.expectEqual(Role.value, function.parameterRole(2));
    try std.testing.expectEqual(Role.unknown, function.parameterRole(3));
    try std.testing.expectEqual(Role.unknown, function.parameterRole(40));
    function.parameter_roles = 0;
    try std.testing.expectEqual(Role.unknown, function.parameterRole(0));
}

test "symbolic table references retain the compact instruction footprint" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Instruction));
}

test "indirect ownership results require an adjacent checked annotation" {
    var instructions = [_]Instruction{ callResult(.scalar), .{ .op = .call_indirect } };
    try std.testing.expectEqual(Role.scalar, indirectResult(&instructions, 1));
    instructions[0] = callResult(.reference);
    try std.testing.expectEqual(Role.reference, indirectResult(&instructions, 1));
    instructions[0] = .{ .op = .nop };
    try std.testing.expectEqual(Role.unknown, indirectResult(&instructions, 1));
    instructions[0] = .{ .op = .ownership, .operand = @bitCast(Ownership{ .kind = .call_result, .chunk = 1, .roles = 1 }) };
    try std.testing.expectEqual(Role.unknown, indirectResult(&instructions, 1));
    try std.testing.expectEqual(Role.unknown, indirectResult(&instructions, 2));
    try std.testing.expectEqual(Role.unknown, indirectResult(&instructions, 0));
    try std.testing.expectEqual(@as(usize, 1), codeLength(&instructions));
}
