//! Storage runtime of the direct backend: an owner table of (base, length,
//! capacity, generation) entries addressed by (slot, generation) handles.
//! Fixed arrays and closure environments live on a bump stack, growable
//! storage in a power-of-two heap, application pools in a persistent region.
//! A scope releases the owners it opened by bumping their generations, so a
//! stale handle traps instead of reading reused storage.
const std = @import("std");
const W = @import("writer.zig");
const A = std.mem.Allocator;

pub const entry_bytes: u32 = 16;
pub const entry_base: u32 = 0;
pub const entry_length: u32 = 4;
pub const entry_capacity: u32 = 8;
pub const entry_generation: u32 = 12;
/// Capacity flags: growth authority removed; storage owned by the heap.
pub const frozen_flag: u32 = 0x8000_0000;
pub const heap_flag: u32 = 0x4000_0000;
pub const capacity_mask: u32 = 0x3fff_ffff;

pub const Budgets = struct {
    owners: u32 = 65536,
    persistent: u32 = 4 << 20,
    stack: u32 = 8 << 20,
    heap: u32 = 32 << 20,
    transport: u32 = 2 << 20,
};
pub const Layout = struct {
    free_lists: u32 = 512,
    owner_table: u32 = 1024,
    owner_capacity: u32,
    persistent_base: u32,
    persistent_end: u32,
    stack_base: u32,
    stack_end: u32,
    heap_base: u32,
    heap_end: u32,
    transport_base: u32,
    transport_end: u32,
    total: u32,
    pub fn init(budgets: Budgets) Layout {
        const owner_table: u32 = 1024;
        const persistent_base = owner_table + budgets.owners * entry_bytes;
        const stack_base = persistent_base + budgets.persistent;
        const heap_base = stack_base + budgets.stack;
        const transport_base = heap_base + budgets.heap;
        const total = transport_base + budgets.transport;
        return .{ .owner_capacity = budgets.owners, .persistent_base = persistent_base, .persistent_end = stack_base, .stack_base = stack_base, .stack_end = heap_base, .heap_base = heap_base, .heap_end = transport_base, .transport_base = transport_base, .transport_end = total, .total = total };
    }
};

pub const Runtime = struct {
    layout: Layout,
    owner_top: u32,
    persistent_bottom: u32,
    stack_pointer: u32,
    heap_top: u32,
    persistent_top: u32,
    transport_top: u32,
    open: u32,
    open_persistent: u32,
    release: u32,
    check: u32,
    stack: u32,
    heap_alloc: u32,
    heap_free: u32,
    address: u32,
    length: u32,
    push: u32,
    pop: u32,
    truncate: u32,
    freeze: u32,
    create: u32,
    copy: u32,
    persist: u32,
    allocate: u32,
    reset: u32,
    packet_length: u32,
};

/// A helper body under construction: parameters, then temporaries.
const H = struct {
    a: A,
    code: W.Bytes = .{},
    locals: std.ArrayList(W.ValType) = .empty,
    parameters: u32,
    fn init(a: A, parameters: u32) A.Error!H {
        var h: H = .{ .a = a, .parameters = parameters };
        for (0..parameters) |_| try h.locals.append(a, .i32);
        return h;
    }
    fn deinit(self: *H) void {
        self.code.deinit(self.a);
        self.locals.deinit(self.a);
    }
    fn temp(self: *H) A.Error!u32 {
        const id: u32 = @intCast(self.locals.items.len);
        try self.locals.append(self.a, .i32);
        return id;
    }
    fn op(self: *H, value: W.Op) A.Error!void {
        try self.code.byte(self.a, @backingInt(value));
    }
    fn idx(self: *H, value: W.Op, index: u32) A.Error!void {
        try self.op(value);
        try self.code.uleb(self.a, index);
    }
    fn get(self: *H, local: u32) A.Error!void {
        try self.idx(.local_get, local);
    }
    fn set(self: *H, local: u32) A.Error!void {
        try self.idx(.local_set, local);
    }
    fn tee(self: *H, local: u32) A.Error!void {
        try self.idx(.local_tee, local);
    }
    fn gget(self: *H, global: u32) A.Error!void {
        try self.idx(.global_get, global);
    }
    fn gset(self: *H, global: u32) A.Error!void {
        try self.idx(.global_set, global);
    }
    fn k(self: *H, value: u32) A.Error!void {
        try self.op(.i32_const);
        try self.code.sleb(self.a, @as(i32, @bitCast(value)));
    }
    fn load(self: *H, offset: u32) A.Error!void {
        try self.op(.i32_load);
        try self.code.uleb(self.a, 2);
        try self.code.uleb(self.a, offset);
    }
    fn store(self: *H, offset: u32) A.Error!void {
        try self.op(.i32_store);
        try self.code.uleb(self.a, 2);
        try self.code.uleb(self.a, offset);
    }
    /// Traps when the i32 on the stack is nonzero.
    fn trapIf(self: *H) A.Error!void {
        try self.op(.if_);
        try self.code.byte(self.a, 0x40);
        try self.op(.unreachable_);
        try self.op(.end);
    }
    fn open(self: *H, kind: W.Op) A.Error!void {
        try self.op(kind);
        try self.code.byte(self.a, 0x40);
    }
    fn call(self: *H, function: u32) A.Error!void {
        try self.idx(.call, function);
    }
    fn memoryCopy(self: *H) A.Error!void {
        try self.op(.prefix_fc);
        try self.code.uleb(self.a, 10);
        try self.code.byte(self.a, 0);
        try self.code.byte(self.a, 0);
    }
    fn memoryFill(self: *H) A.Error!void {
        try self.op(.prefix_fc);
        try self.code.uleb(self.a, 11);
        try self.code.byte(self.a, 0);
    }
    fn finish(self: *H, module: *W.Module, function: u32) A.Error!void {
        try self.op(.end);
        var out: W.Bytes = .{};
        defer out.deinit(self.a);
        const declared = self.locals.items.len - self.parameters;
        if (declared == 0) try out.uleb(self.a, 0) else {
            try out.uleb(self.a, 1);
            try out.uleb(self.a, declared);
            try out.byte(self.a, @backingInt(W.ValType.i32));
        }
        try out.raw(self.a, self.code.items());
        try module.setBody(function, out.items());
    }
};

fn sig(module: *W.Module, comptime params: usize, comptime results: usize) A.Error!u32 {
    return module.signature(&@as([params]W.ValType, @splat(.i32)), &@as([results]W.ValType, @splat(.i32)));
}

/// Emits the globals and helpers. Call before any other function is added
/// only if imports are already declared (imports precede functions).
pub fn emit(a: A, module: *W.Module, budgets: Budgets) A.Error!Runtime {
    const layout = Layout.init(budgets);
    var r: Runtime = .{
        .layout = layout,
        .owner_top = try module.addGlobal(.i32, true, 1),
        .persistent_bottom = try module.addGlobal(.i32, true, layout.owner_capacity),
        .stack_pointer = try module.addGlobal(.i32, true, layout.stack_base),
        .heap_top = try module.addGlobal(.i32, true, layout.heap_base),
        .persistent_top = try module.addGlobal(.i32, true, layout.persistent_base),
        .transport_top = try module.addGlobal(.i32, true, layout.transport_base),
        .open = try module.addFunction(try sig(module, 3, 2)),
        .open_persistent = try module.addFunction(try sig(module, 3, 2)),
        .release = try module.addFunction(try sig(module, 1, 0)),
        .check = try module.addFunction(try sig(module, 2, 1)),
        .stack = try module.addFunction(try sig(module, 1, 1)),
        .heap_alloc = try module.addFunction(try sig(module, 1, 2)),
        .heap_free = try module.addFunction(try sig(module, 2, 0)),
        .address = try module.addFunction(try sig(module, 4, 1)),
        .length = try module.addFunction(try sig(module, 2, 1)),
        .push = try module.addFunction(try sig(module, 3, 1)),
        .pop = try module.addFunction(try sig(module, 3, 1)),
        .truncate = try module.addFunction(try sig(module, 3, 0)),
        .freeze = try module.addFunction(try sig(module, 2, 0)),
        .create = try module.addFunction(try sig(module, 3, 2)),
        .copy = try module.addFunction(try sig(module, 4, 2)),
        .persist = try module.addFunction(try sig(module, 4, 2)),
        .allocate = try module.addFunction(try sig(module, 1, 1)),
        .reset = try module.addFunction(try sig(module, 1, 1)),
        .packet_length = try module.addFunction(try sig(module, 1, 1)),
    };
    const ot = layout.owner_table;
    // open(base, length, capacity) -> (slot, generation)
    inline for (.{ .{ r.open, false }, .{ r.open_persistent, true } }) |item| {
        var h = try H.init(a, 3);
        defer h.deinit();
        const slot = try h.temp();
        const entry = try h.temp();
        if (item[1]) {
            try h.gget(r.persistent_bottom);
            try h.k(1);
            try h.op(.i32_sub);
            try h.tee(slot);
            try h.gset(r.persistent_bottom);
            try h.get(slot);
            try h.gget(r.owner_top);
            try h.op(.i32_lt_u);
            try h.trapIf();
        } else {
            try h.gget(r.owner_top);
            try h.tee(slot);
            try h.gget(r.persistent_bottom);
            try h.op(.i32_ge_u);
            try h.trapIf();
            try h.get(slot);
            try h.k(1);
            try h.op(.i32_add);
            try h.gset(r.owner_top);
        }
        try h.get(slot);
        try h.k(entry_bytes);
        try h.op(.i32_mul);
        try h.k(ot);
        try h.op(.i32_add);
        try h.set(entry);
        inline for (.{ .{ 0, entry_base }, .{ 1, entry_length }, .{ 2, entry_capacity } }) |field| {
            try h.get(entry);
            try h.get(field[0]);
            try h.store(field[1]);
        }
        try h.get(slot);
        try h.get(entry);
        try h.load(entry_generation);
        try h.finish(module, item[0]);
    }
    // heap_free(address, size): push onto the size class's free list.
    {
        var h = try H.init(a, 2);
        defer h.deinit();
        const head = try h.temp();
        try h.k(31);
        try h.get(1);
        try h.op(.i32_clz);
        try h.op(.i32_sub);
        try h.k(4);
        try h.op(.i32_mul);
        try h.k(layout.free_lists);
        try h.op(.i32_add);
        try h.set(head);
        try h.get(0);
        try h.get(head);
        try h.load(0);
        try h.store(0);
        try h.get(head);
        try h.get(0);
        try h.store(0);
        try h.finish(module, r.heap_free);
    }
    // release(mark): every owner opened above mark is invalidated.
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        const entry = try h.temp();
        const capacity = try h.temp();
        try h.open(.block);
        try h.open(.loop);
        try h.gget(r.owner_top);
        try h.get(0);
        try h.op(.i32_le_u);
        try h.idx(.br_if, 1);
        try h.gget(r.owner_top);
        try h.k(1);
        try h.op(.i32_sub);
        try h.gset(r.owner_top);
        try h.gget(r.owner_top);
        try h.k(entry_bytes);
        try h.op(.i32_mul);
        try h.k(ot);
        try h.op(.i32_add);
        try h.tee(entry);
        try h.get(entry);
        try h.load(entry_generation);
        try h.k(1);
        try h.op(.i32_add);
        try h.store(entry_generation);
        try h.get(entry);
        try h.load(entry_capacity);
        try h.tee(capacity);
        try h.k(heap_flag);
        try h.op(.i32_and);
        try h.open(.if_);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(capacity);
        try h.k(capacity_mask);
        try h.op(.i32_and);
        try h.call(r.heap_free);
        try h.op(.end);
        try h.idx(.br, 0);
        try h.op(.end);
        try h.op(.end);
        try h.finish(module, r.release);
    }
    // check(slot, generation) -> entry; slot zero is never an owner.
    {
        var h = try H.init(a, 2);
        defer h.deinit();
        const entry = try h.temp();
        try h.get(0);
        try h.k(layout.owner_capacity);
        try h.op(.i32_ge_u);
        try h.get(0);
        try h.op(.i32_eqz);
        try h.op(.i32_or);
        try h.trapIf();
        try h.get(0);
        try h.k(entry_bytes);
        try h.op(.i32_mul);
        try h.k(ot);
        try h.op(.i32_add);
        try h.tee(entry);
        try h.load(entry_generation);
        try h.get(1);
        try h.op(.i32_ne);
        try h.trapIf();
        try h.get(entry);
        try h.finish(module, r.check);
    }
    // stack(bytes) -> address, 16-byte aligned.
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        const address = try h.temp();
        try h.gget(r.stack_pointer);
        try h.k(15);
        try h.op(.i32_add);
        try h.k(0xffff_fff0);
        try h.op(.i32_and);
        try h.tee(address);
        try h.get(0);
        try h.op(.i32_add);
        try h.gset(r.stack_pointer);
        try h.gget(r.stack_pointer);
        try h.k(layout.stack_end);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.get(address);
        try h.finish(module, r.stack);
    }
    // heap_alloc(bytes) -> (address, size): power-of-two classes from 16 bytes.
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        const class = try h.temp();
        const head = try h.temp();
        const address = try h.temp();
        try h.k(32);
        try h.get(0);
        try h.k(16);
        try h.get(0);
        try h.k(16);
        try h.op(.i32_gt_u);
        try h.op(.select);
        try h.k(1);
        try h.op(.i32_sub);
        try h.op(.i32_clz);
        try h.op(.i32_sub);
        try h.set(class);
        try h.get(class);
        try h.k(4);
        try h.op(.i32_mul);
        try h.k(layout.free_lists);
        try h.op(.i32_add);
        try h.tee(head);
        try h.load(0);
        try h.tee(address);
        try h.open(.if_);
        try h.get(head);
        try h.get(address);
        try h.load(0);
        try h.store(0);
        try h.op(.else_);
        try h.gget(r.heap_top);
        try h.set(address);
        try h.gget(r.heap_top);
        try h.k(1);
        try h.get(class);
        try h.op(.i32_shl);
        try h.op(.i32_add);
        try h.gset(r.heap_top);
        try h.gget(r.heap_top);
        try h.k(layout.heap_end);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.op(.end);
        try h.get(address);
        try h.k(1);
        try h.get(class);
        try h.op(.i32_shl);
        try h.finish(module, r.heap_alloc);
    }
    // address(slot, generation, index, stride) -> element address
    {
        var h = try H.init(a, 4);
        defer h.deinit();
        const entry = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.get(2);
        try h.get(entry);
        try h.load(entry_length);
        try h.op(.i32_ge_u);
        try h.trapIf();
        try h.load(entry_base);
        try h.get(2);
        try h.get(3);
        try h.op(.i32_mul);
        try h.op(.i32_add);
        try h.finish(module, r.address);
    }
    // length(slot, generation)
    {
        var h = try H.init(a, 2);
        defer h.deinit();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.load(entry_length);
        try h.finish(module, r.length);
    }
    // push(slot, generation, stride) -> address of the new last element.
    {
        var h = try H.init(a, 3);
        defer h.deinit();
        const entry = try h.temp();
        const capacity = try h.temp();
        const length = try h.temp();
        const need = try h.temp();
        const fresh = try h.temp();
        const size = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.load(entry_capacity);
        try h.tee(capacity);
        try h.k(frozen_flag);
        try h.op(.i32_and);
        try h.trapIf();
        try h.get(entry);
        try h.load(entry_length);
        try h.tee(length);
        try h.k(1);
        try h.op(.i32_add);
        try h.get(2);
        try h.op(.i32_mul);
        try h.tee(need);
        try h.get(capacity);
        try h.k(capacity_mask);
        try h.op(.i32_and);
        try h.op(.i32_gt_u);
        try h.open(.if_);
        // Grow: at least double, into the heap; free the old heap block.
        try h.get(need);
        try h.get(capacity);
        try h.k(capacity_mask);
        try h.op(.i32_and);
        try h.k(1);
        try h.op(.i32_shl);
        try h.get(need);
        try h.get(capacity);
        try h.k(capacity_mask);
        try h.op(.i32_and);
        try h.k(1);
        try h.op(.i32_shl);
        try h.op(.i32_gt_u);
        try h.op(.select);
        try h.call(r.heap_alloc);
        try h.set(size);
        try h.tee(fresh);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(length);
        try h.get(2);
        try h.op(.i32_mul);
        try h.memoryCopy();
        try h.get(capacity);
        try h.k(heap_flag);
        try h.op(.i32_and);
        try h.open(.if_);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(capacity);
        try h.k(capacity_mask);
        try h.op(.i32_and);
        try h.call(r.heap_free);
        try h.op(.end);
        try h.get(entry);
        try h.get(fresh);
        try h.store(entry_base);
        try h.get(entry);
        try h.get(size);
        try h.k(heap_flag);
        try h.op(.i32_or);
        try h.store(entry_capacity);
        try h.op(.end);
        try h.get(entry);
        try h.get(length);
        try h.k(1);
        try h.op(.i32_add);
        try h.store(entry_length);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(length);
        try h.get(2);
        try h.op(.i32_mul);
        try h.op(.i32_add);
        try h.finish(module, r.push);
    }
    // pop(slot, generation, stride) -> address of the removed element.
    {
        var h = try H.init(a, 3);
        defer h.deinit();
        const entry = try h.temp();
        const length = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.load(entry_capacity);
        try h.k(frozen_flag);
        try h.op(.i32_and);
        try h.trapIf();
        try h.get(entry);
        try h.load(entry_length);
        try h.tee(length);
        try h.op(.i32_eqz);
        try h.trapIf();
        try h.get(entry);
        try h.get(length);
        try h.k(1);
        try h.op(.i32_sub);
        try h.tee(length);
        try h.store(entry_length);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(length);
        try h.get(2);
        try h.op(.i32_mul);
        try h.op(.i32_add);
        try h.finish(module, r.pop);
    }
    // truncate(slot, generation, count)
    {
        var h = try H.init(a, 3);
        defer h.deinit();
        const entry = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.load(entry_capacity);
        try h.k(frozen_flag);
        try h.op(.i32_and);
        try h.trapIf();
        try h.get(2);
        try h.get(entry);
        try h.load(entry_length);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.get(entry);
        try h.get(2);
        try h.store(entry_length);
        try h.finish(module, r.truncate);
    }
    // freeze(slot, generation)
    {
        var h = try H.init(a, 2);
        defer h.deinit();
        const entry = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.get(entry);
        try h.load(entry_capacity);
        try h.k(frozen_flag);
        try h.op(.i32_or);
        try h.store(entry_capacity);
        try h.finish(module, r.freeze);
    }
    // create(length, stride, growable) -> (slot, generation), zeroed.
    {
        var h = try H.init(a, 3);
        defer h.deinit();
        const bytes = try h.temp();
        const address = try h.temp();
        const size = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.op(.i32_mul);
        try h.set(bytes);
        try h.get(2);
        try h.open(.if_);
        try h.get(bytes);
        try h.call(r.heap_alloc);
        try h.set(size);
        try h.set(address);
        try h.get(size);
        try h.k(heap_flag);
        try h.op(.i32_or);
        try h.set(size);
        try h.op(.else_);
        try h.get(bytes);
        try h.call(r.stack);
        try h.set(address);
        try h.get(bytes);
        try h.set(size);
        try h.op(.end);
        try h.get(address);
        try h.k(0);
        try h.get(bytes);
        try h.memoryFill();
        try h.get(address);
        try h.get(0);
        try h.get(size);
        try h.call(r.open);
        try h.finish(module, r.create);
    }
    // copy(slot, generation, stride, growable) -> independent (slot, generation)
    {
        var h = try H.init(a, 4);
        defer h.deinit();
        const entry = try h.temp();
        const slot = try h.temp();
        const generation = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.load(entry_length);
        try h.get(2);
        try h.get(3);
        try h.call(r.create);
        try h.set(generation);
        try h.set(slot);
        try h.get(slot);
        try h.get(generation);
        try h.call(r.check);
        try h.load(entry_base);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(entry);
        try h.load(entry_length);
        try h.get(2);
        try h.op(.i32_mul);
        try h.memoryCopy();
        try h.get(slot);
        try h.get(generation);
        try h.finish(module, r.copy);
    }
    // persist(slot, generation, stride, growable) -> persistent copy.
    {
        var h = try H.init(a, 4);
        defer h.deinit();
        const entry = try h.temp();
        const bytes = try h.temp();
        const address = try h.temp();
        const size = try h.temp();
        try h.get(0);
        try h.get(1);
        try h.call(r.check);
        try h.tee(entry);
        try h.load(entry_length);
        try h.get(2);
        try h.op(.i32_mul);
        try h.set(bytes);
        try h.get(3);
        try h.open(.if_);
        try h.get(bytes);
        try h.call(r.heap_alloc);
        try h.set(size);
        try h.set(address);
        try h.get(size);
        try h.k(heap_flag);
        try h.op(.i32_or);
        try h.set(size);
        try h.op(.else_);
        try h.gget(r.persistent_top);
        try h.k(15);
        try h.op(.i32_add);
        try h.k(0xffff_fff0);
        try h.op(.i32_and);
        try h.tee(address);
        try h.get(bytes);
        try h.op(.i32_add);
        try h.gset(r.persistent_top);
        try h.gget(r.persistent_top);
        try h.k(layout.persistent_end);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.get(bytes);
        try h.set(size);
        try h.op(.end);
        try h.get(address);
        try h.get(entry);
        try h.load(entry_base);
        try h.get(bytes);
        try h.memoryCopy();
        try h.get(address);
        try h.get(entry);
        try h.load(entry_length);
        try h.get(size);
        try h.call(r.open_persistent);
        try h.finish(module, r.persist);
    }
    // Host transport: allocate(bytes) -> zeroed packet address; reset.
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        const address = try h.temp();
        try h.get(0);
        try h.op(.i32_eqz);
        try h.get(0);
        try h.k(3);
        try h.op(.i32_and);
        try h.op(.i32_or);
        try h.trapIf();
        try h.get(0);
        try h.k(layout.transport_end);
        try h.gget(r.transport_top);
        try h.op(.i32_sub);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.gget(r.transport_top);
        try h.tee(address);
        try h.k(0);
        try h.get(0);
        try h.memoryFill();
        try h.get(address);
        try h.get(0);
        try h.op(.i32_add);
        try h.gset(r.transport_top);
        try h.get(address);
        try h.finish(module, r.allocate);
    }
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        try h.k(layout.transport_base);
        try h.gset(r.transport_top);
        try h.k(0);
        try h.finish(module, r.reset);
    }
    // packet_length(address): the checked word count of a host packet.
    {
        var h = try H.init(a, 1);
        defer h.deinit();
        const length = try h.temp();
        try h.get(0);
        try h.k(layout.transport_base);
        try h.op(.i32_lt_u);
        try h.get(0);
        try h.k(3);
        try h.op(.i32_and);
        try h.op(.i32_or);
        try h.get(0);
        try h.k(layout.transport_end - 4);
        try h.op(.i32_gt_u);
        try h.op(.i32_or);
        try h.trapIf();
        try h.get(0);
        try h.load(0);
        try h.tee(length);
        try h.k((layout.transport_end - layout.transport_base) / 4);
        try h.op(.i32_gt_u);
        try h.trapIf();
        try h.get(length);
        try h.finish(module, r.packet_length);
    }
    r.layout = layout;
    module.memory_pages = (layout.total + 0xffff) / 0x10000;
    return r;
}
