//! Persistent AVL sequence of right-sized leaves. Edits detach only a shared
//! spine; exclusively owned nodes update in place. Cloning a branch freezes
//! its children, so either version can subsequently be consumed independently.
//! Every pointer is an allocation base and spare leaf words are zero for GC.
const std = @import("std");
const wasm = @import("wasm.zig");
const Error = std.mem.Allocator.Error || error{ModuleTooLarge};
pub const Runtime = struct {
    new: u32,
    address: u32,
    copy: u32,
    push: u32,
    set: u32,
    from_array: u32,
    to_array: u32,
    chunk_new: u32,
    edit: u32,
    branch: u32,
    own: u32,
    insert: u32,
    replace: u32,
    refresh: u32,
    rotate_left: u32,
    rotate_right: u32,
    balance: u32,
    concat: u32,
    slice: u32,
    join: u32,
    cut: u32,
};
// Descriptor: length, root, cached leaf, cached base, scalar-elements, immutable.
// Node: descriptor token (base + 1, zero if shared), height, length, capacity.
// Tokens are not GC pointers: sharing never retains an obsolete descriptor.
// Leaves store elements after the header; branches store left/right pointers.
pub const header = 16;
pub const capacity = 248; // Leaf + arena headers fit exactly in 1024 bytes.
const descriptor_bytes = 24;
const limit = 0x10000000;
const Local = struct { id: u32 };

// Tuple expressions are expanded while emitting instructions. They create no
// temporary expression graph or allocator traffic in the compiler.
const Code = struct {
    module: *wasm.Module,
    function: u32,
    fn op(c: Code, opcode: wasm.Op, operand: u32) Error!void {
        try c.module.emit(c.function, .{ .op = opcode, .operand = operand });
    }
    fn value(c: Code, x: anytype) Error!void {
        const T = @TypeOf(x);
        if (T == Local) {
            try c.op(.local_get, x.id);
        } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            try c.op(.i32_const, @intCast(x));
        } else switch (x[0]) {
            .global => try c.op(.global_get, x[1]),
            .load => {
                try c.value(x[1]);
                try c.op(.i32_load, x[2]);
            },
            .cell => {
                try c.value(.{ .i32_add, x[1], .{ .i32_mul, x[2], 4 } });
                try c.value(x[3]);
                try c.op(.i32_add, 0);
            },
            .call => {
                inline for (2..x.len) |i| try c.value(x[i]);
                try c.op(.call, x[1]);
            },
            else => {
                inline for (1..x.len) |i| try c.value(x[i]);
                try c.op(x[0], 0);
            },
        }
    }
    fn temp(c: Code) Error!Local {
        return .{ .id = try c.module.addLocal(c.function, .i32) };
    }
    fn set(c: Code, local: Local, x: anytype) Error!void {
        try c.value(x);
        try c.op(.local_set, local.id);
    }
    fn store(c: Code, address: anytype, offset: u32, x: anytype) Error!void {
        try c.value(address);
        try c.value(x);
        try c.op(.i32_store, offset);
    }
    fn copy(c: Code, target: anytype, source: anytype, bytes: anytype) Error!void {
        try c.value(target);
        try c.value(source);
        try c.value(bytes);
        try c.op(.memory_copy, 0);
    }
    fn zero(c: Code, address: anytype, bytes: anytype) Error!void {
        try c.value(address);
        try c.value(0);
        try c.value(bytes);
        try c.op(.memory_fill, 0);
    }
    fn when(c: Code, condition: anytype) Error!void {
        try c.value(condition);
        try c.op(.if_, 0);
    }
    fn end(c: Code) Error!void {
        try c.op(.end, 0);
    }
    fn ret(c: Code, x: anytype) Error!void {
        try c.value(x);
        try c.op(.return_, 0);
    }
    fn trap(c: Code, condition: anytype) Error!void {
        try c.when(condition);
        try c.op(.unreachable_, 0);
        try c.end();
    }
    fn loop(c: Code, condition: anytype) Error!void {
        try c.op(.block, 0);
        try c.op(.loop, 0);
        try c.value(.{ .i32_eqz, condition });
        try c.op(.br_if, 1);
    }
    fn again(c: Code) Error!void {
        try c.op(.br, 0);
        try c.end();
        try c.end();
    }
    fn next(c: Code, local: Local) Error!void {
        try c.set(local, .{ .i32_add, local, 1 });
    }
};
fn code(module: *wasm.Module, index: u32) Code {
    return .{ .module = module, .function = index };
}
fn function(module: *wasm.Module, comptime parameters: usize, result: wasm.ValueType) Error!u32 {
    return module.addFunction(&(@as([parameters]wasm.ValueType, @splat(.i32))), result);
}
pub fn emit(module: *wasm.Module, arena: wasm.Arena) Error!Runtime {
    const r: Runtime = .{
        .new = try function(module, 2, .i32),
        .address = try function(module, 2, .i32),
        .copy = try function(module, 2, .i32),
        .push = try function(module, 4, .i32),
        .set = try function(module, 4, .i32),
        .from_array = try function(module, 2, .i32),
        .to_array = try function(module, 1, .i32),
        .chunk_new = try function(module, 2, .i32),
        .edit = try function(module, 2, .i32),
        .branch = try function(module, 3, .i32),
        .own = try function(module, 2, .i32),
        .insert = try function(module, 4, .i32),
        .replace = try function(module, 4, .i32),
        .refresh = try function(module, 1, .i32),
        .rotate_left = try function(module, 2, .i32),
        .rotate_right = try function(module, 2, .i32),
        .balance = try function(module, 2, .i32),
        .concat = try function(module, 2, .i32),
        .slice = try function(module, 3, .i32),
        .join = try function(module, 3, .i32),
        .cut = try function(module, 4, .i32),
    };
    try emitNode(code(module, r.chunk_new), r, arena);
    try emitBranch(code(module, r.branch), r, arena);
    try emitRefresh(code(module, r.refresh));
    try emitOwn(code(module, r.own), arena);
    try emitRotate(code(module, r.rotate_left), r, true);
    try emitRotate(code(module, r.rotate_right), r, false);
    try emitBalance(code(module, r.balance), r);
    try emitInsert(code(module, r.insert), r);
    try emitReplace(code(module, r.replace), r);
    try emitNew(code(module, r.new), r, arena);
    try emitAddress(code(module, r.address));
    try emitCopy(code(module, r.copy), r);
    try emitEdit(code(module, r.edit), arena);
    try emitPush(code(module, r.push), r);
    try emitSet(code(module, r.set), r);
    try emitConversion(code(module, r.from_array), r, arena, true);
    try emitConversion(code(module, r.to_array), r, arena, false);
    try emitJoin(code(module, r.join), r);
    try emitCut(code(module, r.cut), r);
    try emitConcat(code(module, r.concat), r, arena);
    try emitSlice(code(module, r.slice), r, arena);
    return r;
}
fn emitNode(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const count: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const node = try c.temp();
    const bucket = try c.temp();
    const left = try c.temp();
    const split = try c.temp();
    try c.when(.{ .i32_eqz, count });
    try c.ret(0);
    try c.end();
    try c.when(.{ .i32_gt_u, count, capacity });
    // Split by leaf count, not element count, to keep initial leaves dense.
    try c.set(split, .{ .i32_mul, .{ .i32_div_u, .{ .i32_div_u, .{ .i32_add, count, capacity - 1 }, capacity }, 2 }, capacity });
    try c.set(left, .{ .call, r.chunk_new, split, owner });
    try c.ret(.{ .call, r.branch, left, .{ .call, r.chunk_new, .{ .i32_sub, count, split }, owner }, owner });
    try c.end();
    try c.set(bucket, 64);
    try c.loop(.{ .i32_lt_u, bucket, .{ .i32_add, 32, .{ .i32_mul, count, 4 } } });
    try c.set(bucket, .{ .i32_mul, bucket, 2 });
    try c.again();
    try c.set(node, .{ .call, arena.allocate, .{ .i32_sub, bucket, 16 } });
    try c.store(.{ .i32_sub, node, 8 }, 0, .{ .load, owner, 16 });
    try c.zero(node, .{ .i32_sub, bucket, 16 });
    try c.store(node, 0, .{ .i32_add, owner, 1 });
    try c.store(node, 8, count);
    try c.store(node, 12, .{ .i32_div_u, .{ .i32_sub, bucket, 32 }, 4 });
    try c.value(node);
}
fn emitBranch(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const left: Local = .{ .id = 0 };
    const right: Local = .{ .id = 1 };
    const owner: Local = .{ .id = 2 };
    const node = try c.temp();
    try c.set(node, .{ .call, arena.allocate, 24 });
    try c.store(node, 0, .{ .i32_add, owner, 1 });
    try c.store(node, 12, 0);
    try c.store(node, 16, left);
    try c.store(node, 20, right);
    try c.value(.{ .call, r.refresh, node });
}
fn emitRefresh(c: Code) Error!void {
    const node: Local = .{ .id = 0 };
    const left = try c.temp();
    const right = try c.temp();
    const height = try c.temp();
    try c.set(left, .{ .load, node, 16 });
    try c.set(right, .{ .load, node, 20 });
    try c.store(node, 8, .{ .i32_add, .{ .load, left, 8 }, .{ .load, right, 8 } });
    try c.set(height, .{ .load, left, 4 });
    try c.when(.{ .i32_gt_u, .{ .load, right, 4 }, height });
    try c.set(height, .{ .load, right, 4 });
    try c.end();
    try c.store(node, 4, .{ .i32_add, height, 1 });
    try c.value(node);
}
fn emitOwn(c: Code, arena: wasm.Arena) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const result = try c.temp();
    const bytes = try c.temp();
    try c.when(.{ .i32_eq, .{ .load, node, 0 }, .{ .i32_add, owner, 1 } });
    try c.ret(node);
    try c.end();
    try c.set(bytes, .{ .i32_add, header, .{ .i32_mul, .{ .load, node, 12 }, 4 } });
    try c.when(.{ .load, node, 4 });
    try c.set(bytes, 24);
    try c.store(.{ .load, node, 16 }, 0, 0);
    try c.store(.{ .load, node, 20 }, 0, 0);
    try c.end();
    try c.set(result, .{ .call, arena.allocate, bytes });
    try c.when(.{ .i32_eqz, .{ .load, node, 4 } });
    try c.store(.{ .i32_sub, result, 8 }, 0, .{ .load, owner, 16 });
    try c.end();
    try c.copy(result, node, bytes);
    try c.store(result, 0, .{ .i32_add, owner, 1 });
    try c.value(result);
}
fn emitRotate(c: Code, r: Runtime, comptime leftward: bool) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const pivot = try c.temp();
    const side = if (leftward) 20 else 16;
    const opposite = if (leftward) 16 else 20;
    try c.set(node, .{ .call, r.own, node, owner });
    try c.set(pivot, .{ .call, r.own, .{ .load, node, side }, owner });
    try c.store(node, side, .{ .load, pivot, opposite });
    try c.store(pivot, opposite, .{ .call, r.refresh, node });
    try c.value(.{ .call, r.refresh, pivot });
}
fn emitBalance(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const child = try c.temp();
    try c.set(node, .{ .call, r.refresh, node });
    inline for (.{ true, false }) |left_heavy| {
        const side = if (left_heavy) 16 else 20;
        const other = if (left_heavy) 20 else 16;
        try c.when(.{ .i32_gt_u, .{ .load, .{ .load, node, side }, 4 }, .{ .i32_add, .{ .load, .{ .load, node, other }, 4 }, 1 } });
        try c.set(child, .{ .load, node, side });
        try c.when(.{ .i32_lt_u, .{ .load, .{ .load, child, side }, 4 }, .{ .load, .{ .load, child, other }, 4 } });
        try c.store(node, side, .{ .call, if (left_heavy) r.rotate_left else r.rotate_right, child, owner });
        try c.end();
        try c.ret(.{ .call, if (left_heavy) r.rotate_right else r.rotate_left, node, owner });
        try c.end();
    }
    try c.value(node);
}
fn emitInsert(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const value: Local = .{ .id = 1 };
    const front: Local = .{ .id = 2 };
    const owner: Local = .{ .id = 3 };
    const count = try c.temp();
    const added = try c.temp();
    const child_height = try c.temp();
    try c.when(.{ .i32_eqz, node });
    try c.set(added, .{ .call, r.chunk_new, 1, owner });
    try c.store(added, header, value);
    try c.ret(added);
    try c.end();
    try c.when(.{ .i32_eqz, .{ .load, node, 4 } });
    try c.set(count, .{ .load, node, 8 });
    try c.when(.{ .i32_eq, count, capacity });
    try c.set(added, .{ .call, r.chunk_new, 1, owner });
    try c.store(added, header, value);
    try c.when(front);
    try c.ret(.{ .call, r.branch, added, node, owner });
    try c.end();
    try c.ret(.{ .call, r.branch, node, added, owner });
    try c.end();
    try c.when(.{ .i32_eq, count, .{ .load, node, 12 } });
    try c.set(added, .{ .call, r.chunk_new, .{ .i32_add, count, 1 }, owner });
    try c.copy(.{ .i32_add, added, header }, .{ .i32_add, node, header }, .{ .i32_mul, count, 4 });
    try c.set(node, added);
    try c.op(.else_, 0);
    try c.when(.{ .i32_ne, .{ .load, node, 0 }, .{ .i32_add, owner, 1 } });
    try c.set(node, .{ .call, r.own, node, owner });
    try c.end();
    try c.end();
    try c.when(front);
    try c.copy(.{ .i32_add, node, header + 4 }, .{ .i32_add, node, header }, .{ .i32_mul, count, 4 });
    try c.store(node, header, value);
    try c.op(.else_, 0);
    try c.store(.{ .cell, node, count, header }, 0, value);
    try c.end();
    try c.store(node, 8, .{ .i32_add, count, 1 });
    try c.ret(node);
    try c.end();
    try c.when(.{ .i32_ne, .{ .load, node, 0 }, .{ .i32_add, owner, 1 } });
    try c.set(node, .{ .call, r.own, node, owner });
    try c.end();
    try c.when(front);
    inline for (.{ 16, 20 }) |side| {
        try c.set(child_height, .{ .load, .{ .load, node, side }, 4 });
        try c.set(added, .{ .call, r.insert, .{ .load, node, side }, value, front, owner });
        try c.store(node, side, added);
        if (side == 16) try c.op(.else_, 0);
    }
    try c.end();
    // Inserting into an existing leaf does not change subtree height. Update
    // the path counts without recomputing heights or checking rotations.
    try c.when(.{ .i32_eq, .{ .load, added, 4 }, child_height });
    try c.store(node, 8, .{ .i32_add, .{ .load, node, 8 }, 1 });
    try c.ret(node);
    try c.end();
    try c.value(.{ .call, r.balance, node, owner });
}
fn emitReplace(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const value: Local = .{ .id = 2 };
    const owner: Local = .{ .id = 3 };
    const left_count = try c.temp();
    try c.set(node, .{ .call, r.own, node, owner });
    try c.when(.{ .i32_eqz, .{ .load, node, 4 } });
    try c.store(.{ .cell, node, index, header }, 0, value);
    try c.ret(node);
    try c.end();
    try c.set(left_count, .{ .load, .{ .load, node, 16 }, 8 });
    try c.when(.{ .i32_lt_u, index, left_count });
    try c.store(node, 16, .{ .call, r.replace, .{ .load, node, 16 }, index, value, owner });
    try c.op(.else_, 0);
    try c.store(node, 20, .{ .call, r.replace, .{ .load, node, 20 }, .{ .i32_sub, index, left_count }, value, owner });
    try c.end();
    try c.value(node);
}
fn emitNew(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const count: Local = .{ .id = 0 };
    const scalar_elements: Local = .{ .id = 1 };
    const result = try c.temp();
    try c.trap(.{ .i32_gt_u, count, limit });
    // Empty lists are immutable and carry no per-value state. Reuse one static
    // descriptor, including through conversions and empty slices. Any writer
    // must go through edit(), which detaches immutable descriptors.
    const empty = @import("arena_runtime.zig").empty_list_address;
    const scalar_empty = @import("arena_runtime.zig").empty_scalar_list_address;
    try c.when(.{ .i32_eqz, count });
    try c.when(scalar_elements);
    try c.module.emitReference(c.function, .{ .op = .i32_const, .operand = scalar_empty }, .static_address);
    try c.op(.return_, 0);
    try c.end();
    try c.module.emitReference(c.function, .{ .op = .i32_const, .operand = empty }, .static_address);
    try c.op(.return_, 0);
    try c.end();
    try c.set(result, .{ .call, arena.allocate, descriptor_bytes });
    try c.zero(result, descriptor_bytes);
    try c.store(result, 0, count);
    try c.store(result, 16, .{ .i32_mul, scalar_elements, 2 });
    try c.store(result, 4, .{ .call, r.chunk_new, count, result });
    try c.value(result);
}
fn emitAddress(c: Code) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const node = try c.temp();
    const base = try c.temp();
    const left = try c.temp();
    const split = try c.temp();
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, 0 } });
    try c.set(node, .{ .load, sequence, 8 });
    try c.set(base, .{ .load, sequence, 12 });
    try c.when(node);
    try c.when(.{ .i32_and, .{ .i32_ge_u, index, base }, .{ .i32_lt_u, .{ .i32_sub, index, base }, .{ .load, node, 8 } } });
    try c.ret(.{ .cell, node, .{ .i32_sub, index, base }, header });
    try c.end();
    try c.end();
    try c.set(node, .{ .load, sequence, 4 });
    try c.set(base, 0);
    try c.loop(.{ .load, node, 4 });
    try c.set(left, .{ .load, node, 16 });
    try c.set(split, .{ .i32_add, base, .{ .load, left, 8 } });
    try c.when(.{ .i32_lt_u, index, split });
    try c.set(node, left);
    try c.op(.else_, 0);
    try c.set(node, .{ .load, node, 20 });
    try c.set(base, split);
    try c.end();
    try c.again();
    try c.store(sequence, 8, node);
    try c.store(sequence, 12, base);
    try c.value(.{ .cell, node, .{ .i32_sub, index, base }, header });
}
fn emitCopy(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const count: Local = .{ .id = 1 };
    const result = try c.temp();
    const index = try c.temp();
    const from = try c.temp();
    const to = try c.temp();
    const span = try c.temp();
    const available = try c.temp();
    try c.trap(.{ .i32_gt_u, .{ .load, sequence, 0 }, count });
    try c.set(result, .{ .call, r.new, count, .{ .i32_ne, .{ .load, sequence, 16 }, 0 } });
    try c.loop(.{ .i32_lt_u, index, .{ .load, sequence, 0 } });
    try c.set(from, .{ .call, r.address, sequence, index });
    try c.set(to, .{ .call, r.address, result, index });
    try c.set(span, .{ .i32_sub, .{ .load, .{ .load, sequence, 8 }, 8 }, .{ .i32_sub, index, .{ .load, sequence, 12 } } });
    try c.set(available, .{ .i32_sub, .{ .load, .{ .load, result, 8 }, 8 }, .{ .i32_sub, index, .{ .load, result, 12 } } });
    try c.when(.{ .i32_lt_u, available, span });
    try c.set(span, available);
    try c.end();
    try c.copy(to, from, .{ .i32_mul, span, 4 });
    try c.set(index, .{ .i32_add, index, span });
    try c.again();
    try c.value(result);
}
fn emitEdit(c: Code, arena: wasm.Arena) Error!void {
    const sequence: Local = .{ .id = 0 };
    const owned: Local = .{ .id = 1 };
    const result = try c.temp();
    try c.when(.{ .i32_and, owned, .{ .i32_eqz, .{ .load, sequence, 20 } } });
    try c.ret(sequence);
    try c.end();
    try c.set(result, .{ .call, arena.allocate, descriptor_bytes });
    try c.copy(result, sequence, descriptor_bytes);
    try c.store(result, 8, 0);
    try c.store(result, 20, 0);
    try c.when(.{ .load, sequence, 4 });
    // This write is metadata only: both versions retain identical contents.
    try c.store(.{ .load, sequence, 4 }, 0, 0);
    try c.end();
    try c.value(result);
}
fn emitPush(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const value: Local = .{ .id = 1 };
    const front: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    try c.trap(.{ .i32_ge_u, .{ .load, sequence, 0 }, limit });
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    try c.store(sequence, 4, .{ .call, r.insert, .{ .load, sequence, 4 }, value, front, sequence });
    try c.store(sequence, 0, .{ .i32_add, .{ .load, sequence, 0 }, 1 });
    try c.store(sequence, 8, 0);
    try c.value(sequence);
}
fn emitSet(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const value: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, 0 } });
    // Compare stored bits, not language equality: this is also sound for NaNs,
    // signed zero and reference-valued elements. A borrowed no-op may create
    // a second owner of this very descriptor; freeze it before returning it.
    try c.when(.{ .i32_eq, .{ .load, .{ .call, r.address, sequence, index }, 0 }, value });
    try c.when(.{ .i32_eqz, owned });
    try c.store(sequence, 20, 1);
    try c.end();
    try c.ret(sequence);
    try c.end();
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    try c.store(sequence, 4, .{ .call, r.replace, .{ .load, sequence, 4 }, index, value, sequence });
    try c.store(sequence, 8, 0);
    try c.value(sequence);
}
fn emitConversion(c: Code, r: Runtime, arena: wasm.Arena, to_list: bool) Error!void {
    const source: Local = .{ .id = 0 };
    const result = try c.temp();
    const count = try c.temp();
    const index = try c.temp();
    const address = try c.temp();
    const span = try c.temp();
    try c.set(count, .{ .load, source, 0 });
    if (to_list) {
        try c.set(result, .{ .call, r.new, count, @as(Local, .{ .id = 1 }) });
    } else {
        try c.set(result, .{ .call, arena.allocate, .{ .cell, 4, count, 0 } });
        try c.store(.{ .i32_sub, result, 8 }, 0, .{ .load, source, 16 });
        try c.store(result, 0, count);
    }
    try c.loop(.{ .i32_lt_u, index, count });
    const list = if (to_list) result else source;
    try c.set(address, .{ .call, r.address, list, index });
    try c.set(span, .{ .i32_sub, .{ .load, .{ .load, list, 8 }, 8 }, .{ .i32_sub, index, .{ .load, list, 12 } } });
    if (to_list) {
        try c.copy(address, .{ .cell, source, index, 4 }, .{ .i32_mul, span, 4 });
    } else {
        try c.copy(.{ .cell, result, index, 4 }, address, .{ .i32_mul, span, 4 });
    }
    try c.set(index, .{ .i32_add, index, span });
    try c.again();
    try c.value(result);
}
// Join retains covered subtrees and only rebuilds the taller boundary spine.
// Small adjacent leaves coalesce with bounded copying to avoid tiny packets.
fn emitJoin(c: Code, r: Runtime) Error!void {
    const left: Local = .{ .id = 0 };
    const right: Local = .{ .id = 1 };
    const owner: Local = .{ .id = 2 };
    const node = try c.temp();
    const count = try c.temp();
    try c.when(left);
    try c.store(left, 0, 0);
    try c.end();
    try c.when(right);
    try c.store(right, 0, 0);
    try c.end();
    try c.when(.{ .i32_eqz, left });
    try c.ret(right);
    try c.end();
    try c.when(.{ .i32_eqz, right });
    try c.ret(left);
    try c.end();
    try c.set(count, .{ .i32_add, .{ .load, left, 8 }, .{ .load, right, 8 } });
    try c.when(.{ .i32_le_u, count, 64 });
    // Both operands need to be leaves; a fragmented small tree is handled by
    // the same structural path instead of unbounded recursive flattening.
    try c.when(.{ .i32_eqz, .{ .i32_or, .{ .load, left, 4 }, .{ .load, right, 4 } } });
    try c.set(node, .{ .call, r.chunk_new, count, owner });
    try c.copy(.{ .i32_add, node, header }, .{ .i32_add, left, header }, .{ .i32_mul, .{ .load, left, 8 }, 4 });
    try c.copy(.{ .cell, node, .{ .load, left, 8 }, header }, .{ .i32_add, right, header }, .{ .i32_mul, .{ .load, right, 8 }, 4 });
    try c.ret(node);
    try c.end();
    try c.end();
    try c.when(.{ .i32_gt_u, .{ .load, left, 4 }, .{ .i32_add, .{ .load, right, 4 }, 1 } });
    try c.set(node, .{ .call, r.own, left, owner });
    try c.store(node, 20, .{ .call, r.join, .{ .load, node, 20 }, right, owner });
    try c.ret(.{ .call, r.balance, node, owner });
    try c.end();
    try c.when(.{ .i32_gt_u, .{ .load, right, 4 }, .{ .i32_add, .{ .load, left, 4 }, 1 } });
    try c.set(node, .{ .call, r.own, right, owner });
    try c.store(node, 16, .{ .call, r.join, left, .{ .load, node, 16 }, owner });
    try c.ret(.{ .call, r.balance, node, owner });
    try c.end();
    try c.value(.{ .call, r.branch, left, right, owner });
}
fn emitCut(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const start: Local = .{ .id = 1 };
    const count: Local = .{ .id = 2 };
    const owner: Local = .{ .id = 3 };
    const left = try c.temp();
    const split = try c.temp();
    const result = try c.temp();
    try c.when(.{ .i32_eqz, count });
    try c.ret(0);
    try c.end();
    try c.when(.{ .i32_eq, count, .{ .load, node, 8 } });
    try c.store(node, 0, 0);
    try c.ret(node);
    try c.end();
    try c.when(.{ .i32_eqz, .{ .load, node, 4 } });
    try c.set(result, .{ .call, r.chunk_new, count, owner });
    try c.copy(.{ .i32_add, result, header }, .{ .cell, node, start, header }, .{ .i32_mul, count, 4 });
    try c.ret(result);
    try c.end();
    try c.set(left, .{ .load, node, 16 });
    try c.set(split, .{ .load, left, 8 });
    try c.when(.{ .i32_ge_u, start, split });
    try c.ret(.{ .call, r.cut, .{ .load, node, 20 }, .{ .i32_sub, start, split }, count, owner });
    try c.end();
    try c.set(split, .{ .i32_sub, split, start });
    try c.when(.{ .i32_le_u, count, split });
    try c.ret(.{ .call, r.cut, left, start, count, owner });
    try c.end();
    try c.value(.{ .call, r.join, .{ .call, r.cut, left, start, split, owner }, .{ .call, r.cut, .{ .load, node, 20 }, 0, .{ .i32_sub, count, split }, owner }, owner });
}
fn emitConcat(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const left: Local = .{ .id = 0 };
    const right: Local = .{ .id = 1 };
    const count = try c.temp();
    const result = try c.temp();
    try c.set(count, .{ .i32_add, .{ .load, left, 0 }, .{ .load, right, 0 } });
    try c.trap(.{ .i32_gt_u, count, limit });
    try c.when(.{ .i32_eqz, count });
    try c.ret(.{ .call, r.new, 0, .{ .i32_ne, .{ .i32_and, .{ .load, left, 16 }, .{ .load, right, 16 } }, 0 } });
    try c.end();
    inline for (.{ .{ left, right }, .{ right, left } }) |pair| {
        try c.when(.{ .i32_eqz, .{ .load, pair[0], 0 } });
        try c.store(pair[1], 20, 1);
        try c.ret(pair[1]);
        try c.end();
    }
    try c.set(result, .{ .call, arena.allocate, descriptor_bytes });
    try c.zero(result, descriptor_bytes);
    try c.store(result, 16, .{ .i32_and, .{ .load, left, 16 }, .{ .load, right, 16 } });
    try c.store(result, 0, count);
    try c.store(result, 4, .{ .call, r.join, .{ .load, left, 4 }, .{ .load, right, 4 }, result });
    try c.value(result);
}
fn emitSlice(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const source: Local = .{ .id = 0 };
    const start: Local = .{ .id = 1 };
    const count: Local = .{ .id = 2 };
    const result = try c.temp();
    try c.trap(.{ .i32_gt_u, start, .{ .load, source, 0 } });
    try c.trap(.{ .i32_gt_u, count, .{ .i32_sub, .{ .load, source, 0 }, start } });
    try c.when(.{ .i32_eqz, count });
    try c.ret(.{ .call, r.new, 0, .{ .i32_ne, .{ .load, source, 16 }, 0 } });
    try c.end();
    try c.when(.{ .i32_eq, count, .{ .load, source, 0 } });
    try c.store(source, 20, 1);
    try c.ret(source);
    try c.end();
    try c.set(result, .{ .call, arena.allocate, descriptor_bytes });
    try c.zero(result, descriptor_bytes);
    try c.store(result, 16, .{ .load, source, 16 });
    try c.store(result, 0, count);
    try c.store(result, 4, .{ .call, r.cut, .{ .load, source, 4 }, start, count, result });
    try c.value(result);
}
pub fn staticChunk(module: *wasm.Module, words: []const u32) Error!u32 {
    std.debug.assert(words.len > 0 and words.len <= capacity);
    _ = try module.ensureArena();
    var buffer: [4 + capacity]u32 = @splat(0);
    buffer[2] = @intCast(words.len);
    buffer[3] = @intCast(words.len);
    @memcpy(buffer[4..][0..words.len], words);
    return module.dataWords(buffer[0 .. 4 + words.len]);
}
const StaticNode = struct { address: u32, height: u32, count: u32 };
fn staticTree(module: *wasm.Module, leaves: []const u32) Error!StaticNode {
    if (leaves.len == 0) return .{ .address = 0, .height = 0, .count = 0 };
    if (leaves.len == 1) return .{
        .address = leaves[0],
        .height = 0,
        .count = std.mem.readInt(u32, module.data.items[leaves[0] + 8 ..][0..4], .little),
    };
    const left = try staticTree(module, leaves[0 .. leaves.len / 2]);
    const right = try staticTree(module, leaves[leaves.len / 2 ..]);
    const height = @max(left.height, right.height) + 1;
    const address = try module.dataWords(&.{ 0, height, left.count + right.count, 0, left.address, right.address });
    try module.dataReference(address + 16, .{ .role = .static_address, .value = left.address });
    try module.dataReference(address + 20, .{ .role = .static_address, .value = right.address });
    return .{ .address = address, .height = height, .count = left.count + right.count };
}
pub fn staticDescriptor(module: *wasm.Module, length: u32, leaves: []const u32) Error!u32 {
    const root = try staticTree(module, leaves);
    std.debug.assert(root.count == length);
    const address = try module.dataWords(&.{ length, root.address, 0, 0, 0, 1 });
    if (root.address != 0) try module.dataReference(address + 4, .{ .role = .static_address, .value = root.address });
    return address;
}
