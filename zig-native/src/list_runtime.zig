//! Persistent AVL sequence of right-sized leaves. Edits detach only a shared
//! spine; exclusively owned nodes update in place. Cloning a branch freezes
//! its children, so either version can subsequently be consumed independently.
//! Every pointer is an allocation base and spare leaf words are zero for GC.
const std = @import("std");
const wasm = @import("wasm.zig");
const heap = @import("runtime_layout.zig");
const Error = std.mem.Allocator.Error || error{ ModuleTooLarge, InvalidGlobalReference };
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
    directory: u32,
    leaf_count: u32,
    write_leaves: u32,
};
// Descriptor: length, root, cached leaf/base, scalar row width, immutable,
// aligned leaf limit and scalar leaf-directory reference.
// Node: descriptor token (base + 1, zero if shared), height, length, capacity.
// Tokens are not GC pointers: sharing never retains an obsolete descriptor.
// Leaves store elements after the header; branches store left/right pointers.
pub const header = @sizeOf(heap.ListNode);
pub const capacity = (1024 - @sizeOf(heap.ArenaHeader) - header) / 4;
pub fn leafLimit(words: u32) u32 {
    std.debug.assert(words >= 1 and words <= 16);
    return capacity / words * words;
}
const d = struct {
    const length = heap.offset(heap.ListDescriptor, "length");
    const root = heap.offset(heap.ListDescriptor, "root");
    const cached_leaf = heap.offset(heap.ListDescriptor, "cached_leaf");
    const cached_base = heap.offset(heap.ListDescriptor, "cached_base");
    const scalar_elements = heap.offset(heap.ListDescriptor, "scalar_elements");
    const immutable = heap.offset(heap.ListDescriptor, "immutable");
    const leaf_limit = heap.offset(heap.ListDescriptor, "leaf_limit");
    const directory = heap.offset(heap.ListDescriptor, "directory");
};
const n = struct {
    const owner_token = heap.offset(heap.ListBranch, "owner_token");
    const height = heap.offset(heap.ListBranch, "height");
    const length = heap.offset(heap.ListBranch, "length");
    const capacity = heap.offset(heap.ListBranch, "capacity");
    const left = heap.offset(heap.ListBranch, "left");
    const right = heap.offset(heap.ListBranch, "right");
};
const descriptor_bytes = @sizeOf(heap.ListDescriptor);
const limit = 0x10000000;
const Local = @import("runtime_code.zig").Local;
const Code = @import("runtime_code.zig").Code;

// Tuple addresses keep their allocation base; List.address returns a borrow.
fn store(c: Code, address: anytype, offset: u32, value: anytype) Error!void {
    const T = @TypeOf(address);
    const arena = c.module.arena.?;
    if (T != Local and @typeInfo(T) != .int and @typeInfo(T) != .comptime_int and (address[0] == .cell or address[0] == .i32_add)) {
        try c.value(.{ .call, arena.store_word, address[1], .{ .i32_add, address, offset }, value });
    } else {
        try c.value(.{ .call, arena.store_word, address, .{ .i32_add, address, offset }, value });
    }
}
fn copy(c: Code, target: anytype, source: anytype, bytes: anytype) Error!void {
    const T = @TypeOf(target);
    if (T != Local and (target[0] == .cell or target[0] == .i32_add)) {
        try copyInto(c, target[1], target, source, bytes);
    } else try copyInto(c, target, target, source, bytes);
}
fn copyInto(c: Code, parent: anytype, target: anytype, source: anytype, bytes: anytype) Error!void {
    try c.value(.{ .call, c.module.arena.?.copy_words, parent, target, source, bytes });
}
fn code(module: *wasm.Module, index: u32) Code {
    return .{ .module = module, .function = index };
}
fn function(module: *wasm.Module, comptime parameters: usize, result: wasm.ValueType) Error!u32 {
    return module.addFunction(&(@as([parameters]wasm.ValueType, @splat(.i32))), result);
}
pub fn emit(module: *wasm.Module, arena: wasm.Arena) Error!Runtime {
    const r: Runtime = .{
        .new = try function(module, 3, .i32),
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
        .directory = try function(module, 1, .i32),
        .leaf_count = try function(module, 1, .i32),
        .write_leaves = try function(module, 3, .i32),
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
    try emitLeafCount(code(module, r.leaf_count), r);
    try emitWriteLeaves(code(module, r.write_leaves), r);
    try emitDirectory(code(module, r.directory), r, arena);
    return r;
}
fn emitNode(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const count: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const node = try c.temp();
    const bucket = try c.temp();
    const left = try c.temp();
    const split = try c.temp();
    const leaf_limit = try c.temp();
    try c.set(leaf_limit, .{ .load, owner, d.leaf_limit });
    try c.when(.{ .i32_eqz, count });
    try c.ret(0);
    try c.end();
    try c.when(.{ .i32_gt_u, count, leaf_limit });
    // Split by leaf count, not element count, to keep initial leaves dense.
    try c.set(split, .{ .i32_mul, .{ .i32_div_u, .{ .i32_div_u, .{ .i32_sub, .{ .i32_add, count, leaf_limit }, 1 }, leaf_limit }, 2 }, leaf_limit });
    try c.set(left, .{ .call, r.chunk_new, split, owner });
    try c.ret(.{ .call, r.branch, left, .{ .call, r.chunk_new, .{ .i32_sub, count, split }, owner }, owner });
    try c.end();
    try c.set(bucket, 64);
    try c.loop(.{ .i32_lt_u, bucket, .{ .i32_add, @sizeOf(heap.ArenaHeader) + header, .{ .i32_mul, count, 4 } } });
    try c.set(bucket, .{ .i32_mul, bucket, 2 });
    try c.again();
    try c.set(node, .{ .call, arena.allocate_typed, .{ .i32_sub, bucket, @sizeOf(heap.ArenaHeader) }, .{ .i32_mul, .{ .i32_eqz, .{ .load, owner, d.scalar_elements } }, 0xfffffff0 } });
    try c.zero(node, .{ .i32_sub, bucket, @sizeOf(heap.ArenaHeader) });
    try store(c, node, n.owner_token, .{ .i32_add, owner, 1 });
    try store(c, node, n.length, count);
    // Capacity carries the row-aligned bound as well as the physical bucket.
    // Writers need the descriptor limit only when this capacity is full.
    try c.set(bucket, .{ .i32_div_u, .{ .i32_sub, bucket, @sizeOf(heap.ArenaHeader) + header }, 4 });
    try c.when(.{ .i32_gt_u, bucket, leaf_limit });
    try c.set(bucket, leaf_limit);
    try c.end();
    try store(c, node, n.capacity, bucket);
    // Packed constructors already visit leaves in sequence order. Fill their
    // directory here instead of counting and traversing this tree afterward.
    const directory = try c.temp();
    const index = try c.temp();
    try c.set(directory, .{ .load, owner, d.directory });
    try c.when(directory);
    try c.set(index, .{ .load, directory, heap.offset(heap.Array, "length") });
    try store(c, .{ .cell, directory, index, @sizeOf(heap.Array) }, 0, node);
    try store(c, directory, heap.offset(heap.Array, "length"), .{ .i32_add, index, 1 });
    try c.end();
    try c.value(node);
}
// Scalar List trees have only downward private branch/cache edges. The exact
// scalar element proof is preserved by all descriptor constructors and clones;
// reference Lists remain candidates even when their current contents are null.
fn acyclic(c: Code, arena: wasm.Arena, value: Local, scalar_elements: anytype) Error!void {
    try c.when(.{ .global, arena.rc_enabled });
    try c.when(scalar_elements);
    const flags = heap.offset(heap.ArenaHeader, "flags");
    try c.store(.{ .i32_sub, value, @sizeOf(heap.ArenaHeader) }, flags, .{ .i32_or, .{ .load, .{ .i32_sub, value, @sizeOf(heap.ArenaHeader) }, flags }, @import("cycles_runtime.zig").no_cycle });
    try c.end();
    try c.end();
}
fn emitBranch(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const left: Local = .{ .id = 0 };
    const right: Local = .{ .id = 1 };
    const owner: Local = .{ .id = 2 };
    const node = try c.temp();
    try c.set(node, .{ .call, arena.allocate_typed, 24, 0x30 });
    try acyclic(c, arena, node, .{ .load, owner, d.scalar_elements });
    try store(c, node, n.owner_token, .{ .i32_add, owner, 1 });
    try store(c, node, n.capacity, 0);
    try store(c, node, n.left, left);
    try store(c, node, n.right, right);
    try c.value(.{ .call, r.refresh, node });
}
fn emitRefresh(c: Code) Error!void {
    const node: Local = .{ .id = 0 };
    const left = try c.temp();
    const right = try c.temp();
    const height = try c.temp();
    try c.set(left, .{ .load, node, n.left });
    try c.set(right, .{ .load, node, n.right });
    try store(c, node, n.length, .{ .i32_add, .{ .load, left, n.length }, .{ .load, right, n.length } });
    try c.set(height, .{ .load, left, n.height });
    try c.when(.{ .i32_gt_u, .{ .load, right, n.height }, height });
    try c.set(height, .{ .load, right, n.height });
    try c.end();
    try store(c, node, n.height, .{ .i32_add, height, 1 });
    try c.value(node);
}
fn emitOwn(c: Code, arena: wasm.Arena) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const result = try c.temp();
    const bytes = try c.temp();
    try c.when(.{ .i32_eq, .{ .load, node, n.owner_token }, .{ .i32_add, owner, 1 } });
    try c.ret(node);
    try c.end();
    try c.set(bytes, .{ .i32_add, header, .{ .i32_mul, .{ .load, node, n.capacity }, 4 } });
    try c.when(.{ .load, node, n.height });
    try c.set(bytes, 24);
    try store(c, .{ .load, node, n.left }, n.owner_token, 0);
    try store(c, .{ .load, node, n.right }, n.owner_token, 0);
    try c.end();
    const mask = try c.temp();
    try c.set(mask, 0x30);
    try c.when(.{ .i32_eqz, .{ .load, node, n.height } });
    try c.set(mask, .{ .i32_mul, .{ .i32_eqz, .{ .load, owner, d.scalar_elements } }, 0xfffffff0 });
    try c.end();
    try c.set(result, .{ .call, arena.allocate_typed, bytes, mask });
    try acyclic(c, arena, result, .{ .load, owner, d.scalar_elements });
    try copy(c, result, node, bytes);
    try store(c, result, n.owner_token, .{ .i32_add, owner, 1 });
    try c.value(result);
}
fn emitRotate(c: Code, r: Runtime, comptime leftward: bool) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const pivot = try c.temp();
    const side = if (leftward) n.right else n.left;
    const opposite = if (leftward) n.left else n.right;
    try c.set(node, .{ .call, r.own, node, owner });
    try c.set(pivot, .{ .call, r.own, .{ .load, node, side }, owner });
    try @import("root_runtime.zig").retainBorrow(c, c.module.arena.?, pivot);
    try store(c, node, side, .{ .load, pivot, opposite });
    try store(c, pivot, opposite, .{ .call, r.refresh, node });
    try c.value(.{ .call, r.refresh, pivot });
}
fn emitBalance(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const owner: Local = .{ .id = 1 };
    const child = try c.temp();
    try c.set(node, .{ .call, r.refresh, node });
    inline for (.{ true, false }) |left_heavy| {
        const side = if (left_heavy) n.left else n.right;
        const other = if (left_heavy) n.right else n.left;
        try c.when(.{ .i32_gt_u, .{ .load, .{ .load, node, side }, n.height }, .{ .i32_add, .{ .load, .{ .load, node, other }, n.height }, 1 } });
        try c.set(child, .{ .load, node, side });
        try c.when(.{ .i32_lt_u, .{ .load, .{ .load, child, side }, n.height }, .{ .load, .{ .load, child, other }, n.height } });
        try store(c, node, side, .{ .call, if (left_heavy) r.rotate_left else r.rotate_right, child, owner });
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
    try store(c, added, header, value);
    try c.ret(added);
    try c.end();
    try c.when(.{ .i32_eqz, .{ .load, node, n.height } });
    try c.set(count, .{ .load, node, n.length });
    try c.when(.{ .i32_eq, count, .{ .load, node, n.capacity } });
    try c.when(.{ .i32_eq, count, .{ .load, owner, d.leaf_limit } });
    try c.set(added, .{ .call, r.chunk_new, 1, owner });
    try store(c, added, header, value);
    try c.when(front);
    try c.ret(.{ .call, r.branch, added, node, owner });
    try c.end();
    try c.ret(.{ .call, r.branch, node, added, owner });
    try c.end();
    try c.set(added, .{ .call, r.chunk_new, .{ .i32_add, count, 1 }, owner });
    try copy(c, .{ .i32_add, added, header }, .{ .i32_add, node, header }, .{ .i32_mul, count, 4 });
    try c.set(node, added);
    try c.op(.else_, 0);
    try c.when(.{ .i32_ne, .{ .load, node, n.owner_token }, .{ .i32_add, owner, 1 } });
    try c.set(node, .{ .call, r.own, node, owner });
    try c.end();
    try c.end();
    try c.when(front);
    try copy(c, .{ .i32_add, node, header + 4 }, .{ .i32_add, node, header }, .{ .i32_mul, count, 4 });
    try store(c, node, header, value);
    try c.op(.else_, 0);
    try store(c, .{ .cell, node, count, header }, 0, value);
    try c.end();
    try store(c, node, n.length, .{ .i32_add, count, 1 });
    try c.ret(node);
    try c.end();
    try c.when(.{ .i32_ne, .{ .load, node, n.owner_token }, .{ .i32_add, owner, 1 } });
    try c.set(node, .{ .call, r.own, node, owner });
    try c.end();
    try c.when(front);
    inline for (.{ 16, 20 }) |side| {
        try c.set(child_height, .{ .load, .{ .load, node, side }, n.height });
        try c.set(added, .{ .call, r.insert, .{ .load, node, side }, value, front, owner });
        try store(c, node, side, added);
        if (side == 16) try c.op(.else_, 0);
    }
    try c.end();
    // Inserting into an existing leaf does not change subtree height. Update
    // the path counts without recomputing heights or checking rotations.
    try c.when(.{ .i32_eq, .{ .load, added, n.height }, child_height });
    try store(c, node, n.length, .{ .i32_add, .{ .load, node, n.length }, 1 });
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
    try c.when(.{ .i32_eqz, .{ .load, node, n.height } });
    try store(c, .{ .cell, node, index, header }, 0, value);
    try c.ret(node);
    try c.end();
    try c.set(left_count, .{ .load, .{ .load, node, n.left }, n.length });
    try c.when(.{ .i32_lt_u, index, left_count });
    try store(c, node, n.left, .{ .call, r.replace, .{ .load, node, n.left }, index, value, owner });
    try c.op(.else_, 0);
    try store(c, node, n.right, .{ .call, r.replace, .{ .load, node, n.right }, .{ .i32_sub, index, left_count }, value, owner });
    try c.end();
    try c.value(node);
}
fn emitNew(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const count: Local = .{ .id = 0 };
    const row_words: Local = .{ .id = 1 };
    const leaf_limit: Local = .{ .id = 2 };
    const result = try c.temp();
    try c.trap(.{ .i32_gt_u, count, limit });
    try c.trap(.{ .i32_gt_u, row_words, 16 });
    try c.trap(.{ .i32_eqz, leaf_limit });
    try c.trap(.{ .i32_gt_u, leaf_limit, capacity });
    // Empty lists are immutable and carry no per-value state. Reuse one static
    // descriptor, including through conversions and empty slices. Any writer
    // must go through edit(), which detaches immutable descriptors.
    const empty = @import("arena_runtime.zig").empty_list_address;
    const scalar_empty = @import("arena_runtime.zig").empty_scalar_list_address;
    try c.when(.{ .i32_eqz, count });
    for (2..17) |words| {
        const aligned = leafLimit(@intCast(words));
        const address = @import("arena_runtime.zig").empty_rows_address + @as(u32, @intCast(words - 2)) * descriptor_bytes;
        try c.when(.{ .i32_eq, row_words, words });
        try c.when(.{ .i32_eq, leaf_limit, aligned });
        try c.module.emitReference(c.function, .{ .op = .i32_const, .operand = address }, .static_address);
        try c.op(.return_, 0);
        try c.end();
        try c.end();
    }
    try c.when(.{ .i32_eq, leaf_limit, capacity });
    try c.when(row_words);
    try c.module.emitReference(c.function, .{ .op = .i32_const, .operand = scalar_empty }, .static_address);
    try c.op(.return_, 0);
    try c.end();
    try c.module.emitReference(c.function, .{ .op = .i32_const, .operand = empty }, .static_address);
    try c.op(.return_, 0);
    try c.end();
    try c.end();
    try c.set(result, .{ .call, arena.allocate_typed, descriptor_bytes, 134 });
    try c.zero(result, descriptor_bytes);
    try store(c, result, d.length, count);
    // Word four is checked scalar row width: zero denotes references. Leaf
    // flags normalize it to two; no descriptor field or allocation class grows.
    try store(c, result, d.scalar_elements, row_words);
    try c.when(.{ .i32_gt_u, row_words, 1 });
    const leaves = try c.temp();
    const directory = try c.temp();
    try c.set(leaves, .{ .i32_div_u, .{ .i32_sub, .{ .i32_add, count, leaf_limit }, 1 }, leaf_limit });
    try c.when(.{ .i32_gt_u, leaves, 1 });
    try c.set(directory, .{ .call, arena.allocate_typed, .{ .cell, @sizeOf(heap.Array), leaves, 0 }, 0 });
    try store(c, directory, heap.offset(heap.Array, "length"), 0);
    try store(c, result, d.directory, directory);
    try c.end();
    try c.end();
    try store(c, result, d.leaf_limit, leaf_limit);
    try acyclic(c, arena, result, row_words);
    try store(c, result, d.root, .{ .call, r.chunk_new, count, result });
    try c.value(result);
}
// The directory owns scalar addresses, not leaf edges. Its descriptor keeps
// the immutable tree alive; traversal holders also root uncached static cases.
fn emitLeafCount(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    try c.when(.{ .i32_eqz, node });
    try c.ret(0);
    try c.end();
    try c.when(.{ .load, node, n.height });
    try c.ret(.{ .i32_add, .{ .call, r.leaf_count, .{ .load, node, n.left } }, .{ .call, r.leaf_count, .{ .load, node, n.right } } });
    try c.end();
    try c.value(1);
}
fn emitWriteLeaves(c: Code, r: Runtime) Error!void {
    const node: Local = .{ .id = 0 };
    const array: Local = .{ .id = 1 };
    const index: Local = .{ .id = 2 };
    try c.when(.{ .load, node, n.height });
    try c.set(index, .{ .call, r.write_leaves, .{ .load, node, n.left }, array, index });
    try c.ret(.{ .call, r.write_leaves, .{ .load, node, n.right }, array, index });
    try c.end();
    try store(c, .{ .cell, array, index, @sizeOf(heap.Array) }, 0, node);
    try c.value(.{ .i32_add, index, 1 });
}
fn emitDirectory(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const sequence: Local = .{ .id = 0 };
    const array = try c.temp();
    const count = try c.temp();
    try c.set(array, .{ .load, sequence, d.directory });
    try c.when(array);
    try c.ret(array);
    try c.end();
    try c.when(.{ .i32_eqz, .{ .load, sequence, d.root } });
    try c.ret(0);
    try c.end();
    // For one leaf, the descriptor's root word is already a complete
    // one-entry view at the Array payload offset. Return its exact owning
    // allocation; no separate directory or self-owning cache is published.
    comptime std.debug.assert(d.root == @sizeOf(heap.Array));
    try c.when(.{ .i32_eqz, .{ .load, .{ .load, sequence, d.root }, n.height } });
    try c.ret(sequence);
    try c.end();
    try c.set(count, .{ .call, r.leaf_count, .{ .load, sequence, d.root } });
    try c.set(array, .{ .call, arena.allocate_typed, .{ .cell, @sizeOf(heap.Array), count, 0 }, 0 });
    try store(c, array, heap.offset(heap.Array, "length"), count);
    try c.value(.{ .call, r.write_leaves, .{ .load, sequence, d.root }, array, 0 });
    try c.op(.drop, 0);
    // Counted descriptors own this edge. In tracing mode, an older descriptor
    // must not pin unrelated traffic by promoting the whole arena frontier.
    // Its traversal holder owns this uncached directory until the read ends.
    try c.when(.{ .i32_or, .{ .i32_ge_u, sequence, .{ .global, arena.base } }, .{ .global, arena.root_enabled } });
    try store(c, sequence, d.directory, array);
    try c.end();
    try c.value(array);
}
fn emitAddress(c: Code) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const node = try c.temp();
    const base = try c.temp();
    const left = try c.temp();
    const split = try c.temp();
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, d.length } });
    try c.set(node, .{ .load, sequence, d.cached_leaf });
    try c.set(base, .{ .load, sequence, d.cached_base });
    try c.when(node);
    try c.when(.{ .i32_and, .{ .i32_ge_u, index, base }, .{ .i32_lt_u, .{ .i32_sub, index, base }, .{ .load, node, n.length } } });
    try c.ret(.{ .cell, node, .{ .i32_sub, index, base }, header });
    try c.end();
    try c.end();
    try c.set(node, .{ .load, sequence, d.root });
    try c.set(base, 0);
    try c.loop(.{ .load, node, n.height });
    try c.set(left, .{ .load, node, n.left });
    try c.set(split, .{ .i32_add, base, .{ .load, left, n.length } });
    try c.when(.{ .i32_lt_u, index, split });
    try c.set(node, left);
    try c.op(.else_, 0);
    try c.set(node, .{ .load, node, n.right });
    try c.set(base, split);
    try c.end();
    try c.again();
    try store(c, sequence, d.cached_leaf, node);
    try store(c, sequence, d.cached_base, base);
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
    try c.trap(.{ .i32_gt_u, .{ .load, sequence, d.length }, count });
    try c.set(result, .{ .call, r.new, count, .{ .load, sequence, d.scalar_elements }, .{ .load, sequence, d.leaf_limit } });
    try c.loop(.{ .i32_lt_u, index, .{ .load, sequence, d.length } });
    try c.set(from, .{ .call, r.address, sequence, index });
    try c.set(to, .{ .call, r.address, result, index });
    try c.set(span, .{ .i32_sub, .{ .load, .{ .load, sequence, d.cached_leaf }, n.length }, .{ .i32_sub, index, .{ .load, sequence, d.cached_base } } });
    try c.set(available, .{ .i32_sub, .{ .load, .{ .load, result, d.cached_leaf }, n.length }, .{ .i32_sub, index, .{ .load, result, d.cached_base } } });
    try c.when(.{ .i32_lt_u, available, span });
    try c.set(span, available);
    try c.end();
    try copyInto(c, .{ .load, result, d.cached_leaf }, to, from, .{ .i32_mul, span, 4 });
    try c.set(index, .{ .i32_add, index, span });
    try c.again();
    try c.value(result);
}
fn emitEdit(c: Code, arena: wasm.Arena) Error!void {
    const sequence: Local = .{ .id = 0 };
    const owned: Local = .{ .id = 1 };
    const result = try c.temp();
    try c.when(.{ .i32_and, owned, .{ .i32_eqz, .{ .load, sequence, d.immutable } } });
    try c.ret(sequence);
    try c.end();
    try c.set(result, .{ .call, arena.allocate_typed, descriptor_bytes, 134 });
    try copy(c, result, sequence, descriptor_bytes);
    try store(c, result, d.directory, 0);
    try acyclic(c, arena, result, .{ .load, sequence, d.scalar_elements });
    try store(c, result, d.cached_leaf, 0);
    try store(c, result, d.immutable, 0);
    try c.when(.{ .load, sequence, d.root });
    // This write is metadata only: both versions retain identical contents.
    try store(c, .{ .load, sequence, d.root }, n.owner_token, 0);
    try c.end();
    try c.value(result);
}
fn emitPush(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const value: Local = .{ .id = 1 };
    const front: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    try c.trap(.{ .i32_ge_u, .{ .load, sequence, d.length }, limit });
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    // Borrowed leaf bases are valid only while this exact tree is retained.
    try store(c, sequence, d.directory, 0);
    try store(c, sequence, d.root, .{ .call, r.insert, .{ .load, sequence, d.root }, value, front, sequence });
    try store(c, sequence, d.length, .{ .i32_add, .{ .load, sequence, d.length }, 1 });
    try store(c, sequence, d.cached_leaf, 0);
    try c.value(sequence);
}
fn emitSet(c: Code, r: Runtime) Error!void {
    const sequence: Local = .{ .id = 0 };
    const index: Local = .{ .id = 1 };
    const value: Local = .{ .id = 2 };
    const owned: Local = .{ .id = 3 };
    try c.trap(.{ .i32_ge_u, index, .{ .load, sequence, d.length } });
    // Compare stored bits, not language equality: this is also sound for NaNs,
    // signed zero and reference-valued elements. A borrowed no-op may create
    // a second owner of this very descriptor; freeze it before returning it.
    try c.when(.{ .i32_eq, .{ .load, .{ .call, r.address, sequence, index }, 0 }, value });
    try c.when(.{ .i32_eqz, owned });
    try store(c, sequence, d.immutable, 1);
    try c.end();
    try c.ret(sequence);
    try c.end();
    try c.set(sequence, .{ .call, r.edit, sequence, owned });
    // Borrowed leaf bases are valid only while this exact tree is retained.
    try store(c, sequence, d.directory, 0);
    try store(c, sequence, d.root, .{ .call, r.replace, .{ .load, sequence, d.root }, index, value, sequence });
    try store(c, sequence, d.cached_leaf, 0);
    try c.value(sequence);
}
fn emitConversion(c: Code, r: Runtime, arena: wasm.Arena, to_list: bool) Error!void {
    const source: Local = .{ .id = 0 };
    const result = try c.temp();
    const count = try c.temp();
    const index = try c.temp();
    const address = try c.temp();
    const span = try c.temp();
    try c.set(count, .{ .load, source, if (to_list) heap.offset(heap.Array, "length") else d.length });
    if (to_list) {
        // Zero denotes reference words; positive values are the checked number
        // of scalar words per logical Array element. The tree stores words.
        const width: Local = .{ .id = 1 };
        try c.when(.{ .i32_gt_u, width, 1 });
        try c.trap(.{ .i32_gt_u, count, .{ .i32_div_u, limit, width } });
        try c.set(count, .{ .i32_mul, count, width });
        try c.end();
        const leaf_limit = try c.temp();
        try c.set(leaf_limit, capacity);
        try c.when(.{ .i32_gt_u, width, 1 });
        try c.trap(.{ .i32_gt_u, width, 16 });
        try c.set(leaf_limit, .{ .i32_mul, .{ .i32_div_u, capacity, width }, width });
        try c.end();
        try c.set(result, .{ .call, r.new, count, width, leaf_limit });
    } else {
        try c.set(result, .{ .call, arena.allocate_typed, .{ .cell, 4, count, 0 }, .{ .i32_mul, .{ .i32_eqz, .{ .load, source, d.scalar_elements } }, 0xfffffffe } });
        try store(c, result, heap.offset(heap.Array, "length"), count);
    }
    try c.loop(.{ .i32_lt_u, index, count });
    const list = if (to_list) result else source;
    try c.set(address, .{ .call, r.address, list, index });
    try c.set(span, .{ .i32_sub, .{ .load, .{ .load, list, d.cached_leaf }, n.length }, .{ .i32_sub, index, .{ .load, list, d.cached_base } } });
    if (to_list) {
        try copyInto(c, .{ .load, result, d.cached_leaf }, address, .{ .cell, source, index, 4 }, .{ .i32_mul, span, 4 });
    } else {
        try copy(c, .{ .cell, result, index, 4 }, address, .{ .i32_mul, span, 4 });
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
    try store(c, left, n.owner_token, 0);
    try c.end();
    try c.when(right);
    try store(c, right, n.owner_token, 0);
    try c.end();
    try c.when(.{ .i32_eqz, left });
    try c.ret(right);
    try c.end();
    try c.when(.{ .i32_eqz, right });
    try c.ret(left);
    try c.end();
    try c.set(count, .{ .i32_add, .{ .load, left, n.length }, .{ .load, right, n.length } });
    try c.when(.{ .i32_le_u, count, 64 });
    // Both operands need to be leaves; a fragmented small tree is handled by
    // the same structural path instead of unbounded recursive flattening.
    try c.when(.{ .i32_eqz, .{ .i32_or, .{ .load, left, n.height }, .{ .load, right, n.height } } });
    try c.set(node, .{ .call, r.chunk_new, count, owner });
    try copy(c, .{ .i32_add, node, header }, .{ .i32_add, left, header }, .{ .i32_mul, .{ .load, left, n.length }, 4 });
    try copy(c, .{ .cell, node, .{ .load, left, n.length }, header }, .{ .i32_add, right, header }, .{ .i32_mul, .{ .load, right, n.length }, 4 });
    try c.ret(node);
    try c.end();
    try c.end();
    try c.when(.{ .i32_gt_u, .{ .load, left, n.height }, .{ .i32_add, .{ .load, right, n.height }, 1 } });
    try c.set(node, .{ .call, r.own, left, owner });
    try store(c, node, n.right, .{ .call, r.join, .{ .load, node, n.right }, right, owner });
    try c.ret(.{ .call, r.balance, node, owner });
    try c.end();
    try c.when(.{ .i32_gt_u, .{ .load, right, n.height }, .{ .i32_add, .{ .load, left, n.height }, 1 } });
    try c.set(node, .{ .call, r.own, right, owner });
    try store(c, node, n.left, .{ .call, r.join, left, .{ .load, node, n.left }, owner });
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
    try c.when(.{ .i32_eq, count, .{ .load, node, n.length } });
    try store(c, node, n.owner_token, 0);
    try c.ret(node);
    try c.end();
    try c.when(.{ .i32_eqz, .{ .load, node, n.height } });
    try c.set(result, .{ .call, r.chunk_new, count, owner });
    try copy(c, .{ .i32_add, result, header }, .{ .cell, node, start, header }, .{ .i32_mul, count, 4 });
    try c.ret(result);
    try c.end();
    try c.set(left, .{ .load, node, n.left });
    try c.set(split, .{ .load, left, n.length });
    try c.when(.{ .i32_ge_u, start, split });
    try c.ret(.{ .call, r.cut, .{ .load, node, n.right }, .{ .i32_sub, start, split }, count, owner });
    try c.end();
    try c.set(split, .{ .i32_sub, split, start });
    try c.when(.{ .i32_le_u, count, split });
    try c.ret(.{ .call, r.cut, left, start, count, owner });
    try c.end();
    try c.value(.{ .call, r.join, .{ .call, r.cut, left, start, split, owner }, .{ .call, r.cut, .{ .load, node, n.right }, 0, .{ .i32_sub, count, split }, owner }, owner });
}
fn emitConcat(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const left: Local = .{ .id = 0 };
    const right: Local = .{ .id = 1 };
    const count = try c.temp();
    const result = try c.temp();
    try c.set(count, .{ .i32_add, .{ .load, left, d.length }, .{ .load, right, d.length } });
    try c.trap(.{ .i32_gt_u, count, limit });
    try c.when(.{ .i32_eqz, count });
    try c.ret(.{ .call, r.new, 0, .{ .i32_and, .{ .load, left, d.scalar_elements }, .{ .load, right, d.scalar_elements } }, .{ .load, left, d.leaf_limit } });
    try c.end();
    inline for (.{ .{ left, right }, .{ right, left } }) |pair| {
        try c.when(.{ .i32_eqz, .{ .load, pair[0], d.length } });
        try store(c, pair[1], d.immutable, 1);
        try c.ret(pair[1]);
        try c.end();
    }
    try c.set(result, .{ .call, arena.allocate_typed, descriptor_bytes, 134 });
    try c.zero(result, descriptor_bytes);
    try store(c, result, d.scalar_elements, .{ .i32_and, .{ .load, left, d.scalar_elements }, .{ .load, right, d.scalar_elements } });
    try store(c, result, d.leaf_limit, .{ .load, left, d.leaf_limit });
    try acyclic(c, arena, result, .{ .load, result, d.scalar_elements });
    try store(c, result, d.length, count);
    try store(c, result, d.root, .{ .call, r.join, .{ .load, left, d.root }, .{ .load, right, d.root }, result });
    try c.value(result);
}
fn emitSlice(c: Code, r: Runtime, arena: wasm.Arena) Error!void {
    const source: Local = .{ .id = 0 };
    const start: Local = .{ .id = 1 };
    const count: Local = .{ .id = 2 };
    const result = try c.temp();
    try c.trap(.{ .i32_gt_u, start, .{ .load, source, d.length } });
    try c.trap(.{ .i32_gt_u, count, .{ .i32_sub, .{ .load, source, d.length }, start } });
    try c.when(.{ .i32_eqz, count });
    try c.ret(.{ .call, r.new, 0, .{ .load, source, d.scalar_elements }, .{ .load, source, d.leaf_limit } });
    try c.end();
    try c.when(.{ .i32_eq, count, .{ .load, source, d.length } });
    try store(c, source, d.immutable, 1);
    try c.ret(source);
    try c.end();
    try c.set(result, .{ .call, arena.allocate_typed, descriptor_bytes, 134 });
    try c.zero(result, descriptor_bytes);
    try store(c, result, d.scalar_elements, .{ .load, source, d.scalar_elements });
    try store(c, result, d.leaf_limit, .{ .load, source, d.leaf_limit });
    try acyclic(c, arena, result, .{ .load, source, d.scalar_elements });
    try store(c, result, d.length, count);
    try store(c, result, d.root, .{ .call, r.cut, .{ .load, source, d.root }, start, count, result });
    try c.value(result);
}
pub fn staticChunk(module: *wasm.Module, words: []const u32) Error!u32 {
    std.debug.assert(words.len > 0 and words.len <= capacity);
    _ = try module.ensureArena();
    var buffer: [header / 4 + capacity]u32 = @splat(0);
    buffer[n.length / 4] = @intCast(words.len);
    buffer[n.capacity / 4] = @intCast(words.len);
    @memcpy(buffer[header / 4 ..][0..words.len], words);
    const used = std.math.add(usize, header / 4, words.len) catch return error.ModuleTooLarge;
    return module.dataWords(buffer[0..used]);
}
const StaticNode = struct { address: u32, height: u32, count: u32 };
fn staticTree(module: *wasm.Module, leaves: []const u32) Error!StaticNode {
    if (leaves.len == 0) return .{ .address = 0, .height = 0, .count = 0 };
    if (leaves.len == 1) return .{
        .address = leaves[0],
        .height = 0,
        .count = std.mem.readInt(u32, module.data.items[leaves[0] + n.length ..][0..4], .little),
    };
    const left = try staticTree(module, leaves[0 .. leaves.len / 2]);
    const right = try staticTree(module, leaves[leaves.len / 2 ..]);
    const height = @max(left.height, right.height) + 1;
    const address = try module.dataObject(heap.ListBranch{ .owner_token = 0, .height = height, .length = left.count + right.count, .capacity = 0, .left = left.address, .right = right.address });
    try module.dataReference(address + n.left, .{ .role = .static_address, .value = left.address });
    try module.dataReference(address + n.right, .{ .role = .static_address, .value = right.address });
    return .{ .address = address, .height = height, .count = left.count + right.count };
}
pub fn staticDescriptor(module: *wasm.Module, length: u32, leaves: []const u32) Error!u32 {
    return staticDescriptorKind(module, length, leaves, 0, capacity);
}
pub fn staticScalarDescriptor(module: *wasm.Module, length: u32, leaves: []const u32, row_words: u32) Error!u32 {
    return staticDescriptorKind(module, length, leaves, row_words, leafLimit(row_words));
}
fn staticDescriptorKind(module: *wasm.Module, length: u32, leaves: []const u32, row_words: u32, leaf_limit: u32) Error!u32 {
    const root = try staticTree(module, leaves);
    std.debug.assert(root.count == length);
    var directory: u32 = 0;
    if (row_words != 0 and leaves.len > 1) {
        const words = try module.allocator.alloc(u32, leaves.len + 1);
        defer module.allocator.free(words);
        words[0] = @intCast(leaves.len);
        @memcpy(words[1..], leaves);
        directory = try module.dataWords(words);
        for (leaves, 0..) |leaf, index| try module.dataReference(directory + @as(u32, @intCast((index + 1) * 4)), .{ .role = .static_address, .value = leaf });
    }
    const address = try module.dataObject(heap.ListDescriptor{ .length = length, .root = root.address, .cached_leaf = 0, .cached_base = 0, .scalar_elements = row_words, .immutable = 1, .leaf_limit = leaf_limit, .directory = directory });
    try module.staticField(address + d.cached_leaf, .reference);
    try module.staticField(address + d.cached_base, .scalar);
    try module.staticField(address + d.immutable, .scalar);
    try module.staticField(address + d.directory, .reference);
    if (directory != 0) try module.dataReference(address + d.directory, .{ .role = .static_address, .value = directory });
    if (root.address != 0) try module.dataReference(address + d.root, .{ .role = .static_address, .value = root.address });
    return address;
}
