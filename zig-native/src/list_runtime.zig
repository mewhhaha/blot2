//! Dense doubly linked chunks for traversal-oriented lists.
//! A descriptor owns its whole chain. Shared edits copy the visible values;
//! proven exclusive edits reuse the descriptor and end chunks. Static values
//! are always copied before mutation. Exact base pointers and zeroed spare
//! slots let Blot's tracing collector reclaim chains, including their cycles.
const std = @import("std");
const wasm = @import("wasm.zig");
const Error = std.mem.Allocator.Error || error{ModuleTooLarge};
pub const Runtime = struct { new: u32, address: u32, copy: u32, push: u32, set: u32, from_array: u32, to_array: u32, chunk_new: u32, edit: u32 };
// Descriptor: length, first, last, cached chunk, cached base, immutable flag.
// Chunk: next, previous, start, count, then 256 payload words.
pub const header = 16;
pub const capacity = 256;
pub const chunk_bytes = header + capacity * 4;
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
        .new = try function(module, 1, .i32),
        .address = try function(module, 2, .i32),
        .copy = try function(module, 2, .i32),
        .push = try function(module, 4, .i32),
        .set = try function(module, 4, .i32),
        .from_array = try function(module, 1, .i32),
        .to_array = try function(module, 1, .i32),
        .chunk_new = try function(module, 2, .i32),
        .edit = try function(module, 2, .i32),
    };
    try emitChunk(code(module, r.chunk_new), arena);
    try emitNew(code(module, r.new), r, arena);
    try emitAddress(code(module, r.address));
    try emitCopy(code(module, r.copy), r);
    try emitEdit(code(module, r.edit), r);
    try emitPush(code(module, r.push), r);
    try emitSet(code(module, r.set), r);
    try emitConversion(code(module, r.from_array), r, arena, true);
    try emitConversion(code(module, r.to_array), r, arena, false);
    return r;
}
fn emitChunk(c: Code, arena: wasm.Arena) Error!void {
    const start: Local = .{ .id = 0 };
    const count: Local = .{ .id = 1 };
    const chunk = try c.temp();
    try c.set(chunk, .{ .call, arena.allocate, chunk_bytes });
    try c.zero(chunk, chunk_bytes);
    try c.store(chunk, 8, start);
    try c.store(chunk, 12, count);
    try c.value(chunk);
}
fn emitNew(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const count: Local = .{ .id = 0 };
    const result = try c.temp();
    const remaining = try c.temp();
    const previous = try c.temp();
    const chunk = try c.temp();
    const take = try c.temp();
    try c.trap(.{ .i32_gt_u, count, limit });
    try c.set(result, .{ .call, arena.allocate, descriptor_bytes });
    try c.zero(result, descriptor_bytes);
    try c.store(result, 0, count);
    try c.set(remaining, count);
    try c.loop(remaining);
    try c.set(take, remaining);
    try c.when(.{ .i32_gt_u, take, capacity });
    try c.set(take, capacity);
    try c.end();
    try c.set(chunk, .{ .call, r.chunk_new, 0, take });
    try c.store(chunk, 4, previous);
    try c.when(previous);
    try c.store(previous, 0, chunk);
    try c.op(.else_, 0);
    try c.store(result, 4, chunk);
    try c.end();
    try c.set(previous, chunk);
    try c.set(remaining, .{ .i32_sub, remaining, take });
    try c.again();
    try c.store(result, 8, previous);
    try c.value(result);
}
// Internal address lookup supports construction and iteration, not source
// indexing. The cached span makes a monotone traversal linear in its length.
fn emitAddress(c: Code) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const chunk = try c.temp();
    const base = try c.temp();
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, 0 } });
    try c.set(chunk, .{ .load, sequence, 12 });
    try c.set(base, .{ .load, sequence, 16 });
    try c.when(.{ .i32_eqz, chunk });
    try c.set(chunk, .{ .load, sequence, 4 });
    try c.set(base, 0);
    try c.end();
    try c.when(.{ .i32_lt_u, index, base });
    try c.when(.{ .i32_lt_u, index, .{ .i32_sub, base, index } });
    try c.set(chunk, .{ .load, sequence, 4 });
    try c.set(base, 0);
    try c.end();
    try c.op(.else_, 0);
    try c.when(.{ .i32_lt_u, .{ .i32_sub, .{ .load, sequence, 0 }, index }, .{ .i32_sub, index, base } });
    try c.set(chunk, .{ .load, sequence, 8 });
    try c.set(base, .{ .i32_sub, .{ .load, sequence, 0 }, .{ .load, chunk, 12 } });
    try c.end();
    try c.end();
    try c.loop(.{ .i32_lt_u, index, base });
    try c.set(chunk, .{ .load, chunk, 4 });
    try c.set(base, .{ .i32_sub, base, .{ .load, chunk, 12 } });
    try c.again();
    try c.loop(.{ .i32_ge_u, index, .{ .i32_add, base, .{ .load, chunk, 12 } } });
    try c.set(base, .{ .i32_add, base, .{ .load, chunk, 12 } });
    try c.set(chunk, .{ .load, chunk, 0 });
    try c.again();
    try c.store(sequence, 12, chunk);
    try c.store(sequence, 16, base);
    try c.value(.{ .cell, chunk, .{ .i32_add, .{ .load, chunk, 8 }, .{ .i32_sub, index, base } }, header });
}
fn emitCopy(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const count: Local = .{ .id = 1 };
    const result = try c.temp();
    const index = try c.temp();
    try c.trap(.{ .i32_gt_u, .{ .load, sequence, 0 }, count });
    try c.set(result, .{ .call, r.new, count });
    try c.loop(.{ .i32_lt_u, index, .{ .load, sequence, 0 } });
    try c.store(.{ .call, r.address, result, index }, 0, .{ .load, .{ .call, r.address, sequence, index }, 0 });
    try c.next(index);
    try c.again();
    try c.value(result);
}
fn emitEdit(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const owned: Local = .{ .id = 1 };
    try c.when(.{ .i32_and, owned, .{ .i32_eqz, .{ .load, sequence, 20 } } });
    try c.ret(sequence);
    try c.end();
    try c.value(.{ .call, r.copy, sequence, .{ .load, sequence, 0 } });
}
fn finishPush(c: Code, sequence: Local) Error!void {
    try c.store(sequence, 0, .{ .i32_add, .{ .load, sequence, 0 }, 1 });
    // Topology or positions may have changed. Do not retain a borrowed cursor.
    try c.store(sequence, 12, 0);
    try c.store(sequence, 16, 0);
    try c.ret(sequence);
}
fn emitPush(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const value: Local = .{ .id = 1 };
    const front: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    const chunk = try c.temp();
    const start = try c.temp();
    const count = try c.temp();
    const added = try c.temp();
    try c.trap(.{ .i32_ge_u, .{ .load, sequence, 0 }, limit });
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    try c.when(front);
    inline for (.{ true, false }) |prepend| {
        const end_offset = if (prepend) 4 else 8;
        try c.set(chunk, .{ .load, sequence, end_offset });
        try c.when(chunk);
        try c.set(start, .{ .load, chunk, 8 });
        try c.set(count, .{ .load, chunk, 12 });
        try c.when(.{ .i32_lt_u, count, capacity });
        if (prepend) {
            try c.when(.{ .i32_eqz, start });
            try c.set(start, .{ .i32_sub, capacity, count });
            try c.copy(.{ .cell, chunk, start, header }, .{ .i32_add, chunk, header }, .{ .i32_mul, count, 4 });
            try c.zero(.{ .i32_add, chunk, header }, .{ .i32_mul, start, 4 });
            try c.end();
            try c.set(start, .{ .i32_sub, start, 1 });
            try c.store(.{ .cell, chunk, start, header }, 0, value);
        } else {
            try c.when(.{ .i32_eq, .{ .i32_add, start, count }, capacity });
            try c.copy(.{ .i32_add, chunk, header }, .{ .cell, chunk, start, header }, .{ .i32_mul, count, 4 });
            try c.zero(.{ .cell, chunk, count, header }, .{ .i32_mul, .{ .i32_sub, capacity, count }, 4 });
            try c.set(start, 0);
            try c.end();
            try c.store(.{ .cell, chunk, .{ .i32_add, start, count }, header }, 0, value);
        }
        try c.store(chunk, 8, start);
        try c.store(chunk, 12, .{ .i32_add, count, 1 });
        try finishPush(c, sequence);
        try c.end();
        try c.end();
        try c.set(added, .{ .call, r.chunk_new, if (prepend) capacity - 1 else 0, 1 });
        try c.store(.{ .cell, added, if (prepend) capacity - 1 else 0, header }, 0, value);
        try c.store(added, if (prepend) 0 else 4, chunk);
        try c.when(chunk);
        try c.store(chunk, if (prepend) 4 else 0, added);
        try c.op(.else_, 0);
        try c.store(sequence, if (prepend) 8 else 4, added);
        try c.end();
        try c.store(sequence, end_offset, added);
        try finishPush(c, sequence);
        if (prepend) try c.op(.else_, 0);
    }
    try c.end();
    try c.op(.unreachable_, 0);
}
// Only compiler-private construction/update lowering uses this helper.
fn emitSet(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const value: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, 0 } });
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    try c.store(.{ .call, r.address, sequence, index }, 0, value);
    try c.value(sequence);
}
fn emitConversion(c: Code, r: Runtime, arena: wasm.Arena, to_list: bool) Error!void {
    const source: Local = .{ .id = 0 };
    const result = try c.temp();
    const count = try c.temp();
    const index = try c.temp();
    try c.set(count, .{ .load, source, 0 });
    if (to_list) {
        try c.set(result, .{ .call, r.new, count });
    } else {
        try c.set(result, .{ .call, arena.allocate, .{ .cell, 4, count, 0 } });
        try c.store(result, 0, count);
    }
    try c.loop(.{ .i32_lt_u, index, count });
    if (to_list) {
        try c.store(.{ .call, r.address, result, index }, 0, .{ .load, .{ .cell, source, index, 4 }, 0 });
    } else {
        try c.store(.{ .cell, result, index, 4 }, 0, .{ .load, .{ .call, r.address, source, index }, 0 });
    }
    try c.next(index);
    try c.again();
    try c.value(result);
}
// Static chains have the same layout. Every link and value pointer is recorded
// for retained code/data relocation; forward links are known from chunk size.
pub fn staticChunk(module: *wasm.Module, words: []const u32, previous: u32, more: bool) Error!u32 {
    std.debug.assert(words.len > 0 and words.len <= capacity);
    _ = try module.ensureArena();
    const start: u32 = @intCast(module.data.items.len);
    if (start > std.math.maxInt(u32) - chunk_bytes) return error.ModuleTooLarge;
    var buffer: [4 + capacity]u32 = @splat(0);
    buffer[0] = if (more) start + chunk_bytes else 0;
    buffer[1] = previous;
    buffer[3] = @intCast(words.len);
    @memcpy(buffer[4..][0..words.len], words);
    const address = try module.dataWords(&buffer);
    if (more) try module.dataReference(address, .{ .role = .static_address, .value = buffer[0] });
    if (previous != 0) try module.dataReference(address + 4, .{ .role = .static_address, .value = previous });
    return address;
}
pub fn staticDescriptor(module: *wasm.Module, length: u32, first: u32, last: u32) Error!u32 {
    const address = try module.dataWords(&.{ length, first, last, 0, 0, 1 });
    if (first != 0) try module.dataReference(address + 4, .{ .role = .static_address, .value = first });
    if (last != 0) try module.dataReference(address + 8, .{ .role = .static_address, .value = last });
    return address;
}
