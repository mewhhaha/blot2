//! Lean Wasm module writer. Function bodies are encoded straight to bytes by
//! the emitter; this owner only lays out sections around them.
const std = @import("std");
const A = std.mem.Allocator;

pub const ValType = enum(u8) { i32 = 0x7f, i64 = 0x7e, f32 = 0x7d, f64 = 0x7c, v128 = 0x7b, funcref = 0x70, externref = 0x6f };

/// Opcodes used by the direct backend.
pub const Op = enum(u8) {
    unreachable_ = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    if_ = 0x04,
    else_ = 0x05,
    end = 0x0b,
    br = 0x0c,
    br_if = 0x0d,
    br_table = 0x0e,
    return_ = 0x0f,
    call = 0x10,
    call_indirect = 0x11,
    drop = 0x1a,
    select = 0x1b,
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,
    global_get = 0x23,
    global_set = 0x24,
    table_get = 0x25,
    table_set = 0x26,
    i32_load = 0x28,
    f32_load = 0x2a,
    i32_load8_u = 0x2d,
    i32_store = 0x36,
    f32_store = 0x38,
    i32_store8 = 0x3a,
    memory_size = 0x3f,
    i32_const = 0x41,
    f32_const = 0x43,
    i32_eqz = 0x45,
    i32_eq = 0x46,
    i32_ne = 0x47,
    i32_lt_s = 0x48,
    i32_lt_u = 0x49,
    i32_gt_s = 0x4a,
    i32_gt_u = 0x4b,
    i32_le_s = 0x4c,
    i32_le_u = 0x4d,
    i32_ge_s = 0x4e,
    i32_ge_u = 0x4f,
    f32_eq = 0x5b,
    f32_ne = 0x5c,
    f32_lt = 0x5d,
    f32_gt = 0x5e,
    f32_le = 0x5f,
    f32_ge = 0x60,
    i32_clz = 0x67,
    i32_add = 0x6a,
    i32_sub = 0x6b,
    i32_mul = 0x6c,
    i32_div_s = 0x6d,
    i32_div_u = 0x6e,
    i32_rem_s = 0x6f,
    i32_rem_u = 0x70,
    i32_and = 0x71,
    i32_or = 0x72,
    i32_xor = 0x73,
    i32_shl = 0x74,
    i32_shr_s = 0x75,
    i32_shr_u = 0x76,
    f32_abs = 0x8b,
    f32_neg = 0x8c,
    f32_ceil = 0x8d,
    f32_floor = 0x8e,
    f32_trunc = 0x8f,
    f32_nearest = 0x90,
    f32_sqrt = 0x91,
    f32_add = 0x92,
    f32_sub = 0x93,
    f32_mul = 0x94,
    f32_div = 0x95,
    f32_min = 0x96,
    f32_max = 0x97,
    f32_convert_i32_s = 0xb2,
    f32_convert_i32_u = 0xb3,
    i32_reinterpret_f32 = 0xbc,
    f32_reinterpret_i32 = 0xbe,
    prefix_fc = 0xfc,
    prefix_fd = 0xfd,
};

pub const Bytes = struct {
    list: std.ArrayList(u8) = .empty,
    pub fn deinit(self: *Bytes, a: A) void {
        self.list.deinit(a);
    }
    pub fn byte(self: *Bytes, a: A, value: u8) A.Error!void {
        try self.list.append(a, value);
    }
    pub fn raw(self: *Bytes, a: A, value: []const u8) A.Error!void {
        try self.list.appendSlice(a, value);
    }
    pub fn uleb(self: *Bytes, a: A, value: u64) A.Error!void {
        var rest = value;
        while (true) {
            const low: u8 = @intCast(rest & 0x7f);
            rest >>= 7;
            if (rest == 0) return self.byte(a, low);
            try self.byte(a, low | 0x80);
        }
    }
    pub fn sleb(self: *Bytes, a: A, value: i64) A.Error!void {
        var rest = value;
        while (true) {
            const low: u8 = @intCast(rest & 0x7f);
            rest >>= 7;
            const done = (rest == 0 and low & 0x40 == 0) or (rest == -1 and low & 0x40 != 0);
            if (done) return self.byte(a, low);
            try self.byte(a, low | 0x80);
        }
    }
    pub fn name(self: *Bytes, a: A, value: []const u8) A.Error!void {
        try self.uleb(a, value.len);
        try self.raw(a, value);
    }
    pub fn items(self: *const Bytes) []const u8 {
        return self.list.items;
    }
};

pub const Signature = struct { params: []const ValType, results: []const ValType };
const SignatureContext = struct {
    pub fn hash(_: @This(), key: Signature) u64 {
        var state = std.hash.Wyhash.init(0);
        state.update(std.mem.sliceAsBytes(key.params));
        state.update(&.{0xff});
        state.update(std.mem.sliceAsBytes(key.results));
        return state.final();
    }
    pub fn eql(_: @This(), left: Signature, right: Signature) bool {
        return std.mem.eql(ValType, left.params, right.params) and std.mem.eql(ValType, left.results, right.results);
    }
};

pub const Import = struct { module: []const u8, name: []const u8, signature: u32 };
pub const Global = struct { ty: ValType, mutable: bool, init: u32 };
pub const ExportKind = enum(u8) { function = 0, table = 1, memory = 2, global = 3 };
pub const Export = struct { name: []const u8, kind: ExportKind, index: u32 };
/// A defined function: its signature and complete encoded body (locals + code).
pub const Function = struct { signature: u32, body: []const u8 = &.{} };

pub const Module = struct {
    allocator: A,
    arena: std.heap.ArenaAllocator,
    signatures: std.ArrayList(Signature) = .empty,
    signature_index: std.HashMapUnmanaged(Signature, u32, SignatureContext, 80) = .empty,
    imports: std.ArrayList(Import) = .empty,
    functions: std.ArrayList(Function) = .empty,
    globals: std.ArrayList(Global) = .empty,
    exports: std.ArrayList(Export) = .empty,
    /// Function indices (import-relative) stored in table 0, slot = position.
    table: std.ArrayList(u32) = .empty,
    /// Externref slots for host callbacks (table 1); zero when unused.
    host_slots: u32 = 0,
    memory_pages: ?u32 = null,
    data_offset: u32 = 0,
    data: std.ArrayList(u8) = .empty,
    customs: std.ArrayList(struct { name: []const u8, payload: []const u8 }) = .empty,

    pub fn init(allocator: A) Module {
        return .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: *Module) void {
        const a = self.allocator;
        self.signatures.deinit(a);
        self.signature_index.deinit(a);
        self.imports.deinit(a);
        self.functions.deinit(a);
        self.globals.deinit(a);
        self.exports.deinit(a);
        self.table.deinit(a);
        self.data.deinit(a);
        self.customs.deinit(a);
        self.arena.deinit();
    }
    pub fn signature(self: *Module, params: []const ValType, results: []const ValType) A.Error!u32 {
        const key: Signature = .{ .params = params, .results = results };
        if (self.signature_index.getContext(key, .{})) |found| return found;
        const owned: Signature = .{ .params = try self.arena.allocator().dupe(ValType, params), .results = try self.arena.allocator().dupe(ValType, results) };
        const id: u32 = @intCast(self.signatures.items.len);
        try self.signatures.append(self.allocator, owned);
        try self.signature_index.putContext(self.allocator, owned, id, .{});
        return id;
    }
    /// Imports precede defined functions in the index space; add them first.
    pub fn importFunction(self: *Module, module: []const u8, name: []const u8, signature_id: u32) A.Error!u32 {
        std.debug.assert(self.functions.items.len == 0);
        const id: u32 = @intCast(self.imports.items.len);
        try self.imports.append(self.allocator, .{ .module = module, .name = try self.arena.allocator().dupe(u8, name), .signature = signature_id });
        return id;
    }
    /// Reserves a defined function; its body is supplied later.
    pub fn addFunction(self: *Module, signature_id: u32) A.Error!u32 {
        const id: u32 = @intCast(self.imports.items.len + self.functions.items.len);
        try self.functions.append(self.allocator, .{ .signature = signature_id });
        return id;
    }
    pub fn setBody(self: *Module, function: u32, body: []const u8) A.Error!void {
        const slot = &self.functions.items[function - self.imports.items.len];
        slot.body = try self.arena.allocator().dupe(u8, body);
    }
    pub fn addGlobal(self: *Module, ty: ValType, mutable: bool, init_value: u32) A.Error!u32 {
        const id: u32 = @intCast(self.globals.items.len);
        try self.globals.append(self.allocator, .{ .ty = ty, .mutable = mutable, .init = init_value });
        return id;
    }
    pub fn exportItem(self: *Module, name: []const u8, kind: ExportKind, index: u32) A.Error!void {
        try self.exports.append(self.allocator, .{ .name = try self.arena.allocator().dupe(u8, name), .kind = kind, .index = index });
    }
    pub fn tableSlot(self: *Module, function: u32) A.Error!u32 {
        const slot: u32 = @intCast(self.table.items.len);
        try self.table.append(self.allocator, function);
        return slot;
    }
    pub fn custom(self: *Module, name: []const u8, payload: []const u8) A.Error!void {
        try self.customs.append(self.allocator, .{ .name = name, .payload = try self.arena.allocator().dupe(u8, payload) });
    }

    pub fn assemble(self: *Module, a: A) A.Error![]u8 {
        var out: Bytes = .{};
        errdefer out.deinit(a);
        var payload: Bytes = .{};
        defer payload.deinit(a);
        try out.raw(a, &.{ 0, 'a', 's', 'm', 1, 0, 0, 0 });
        // 1: types
        try payload.uleb(a, self.signatures.items.len);
        for (self.signatures.items) |sig| {
            try payload.byte(a, 0x60);
            try payload.uleb(a, sig.params.len);
            for (sig.params) |ty| try payload.byte(a, @backingInt(ty));
            try payload.uleb(a, sig.results.len);
            for (sig.results) |ty| try payload.byte(a, @backingInt(ty));
        }
        try section(a, &out, 1, &payload);
        // 2: imports
        if (self.imports.items.len != 0) {
            try payload.uleb(a, self.imports.items.len);
            for (self.imports.items) |item| {
                try payload.name(a, item.module);
                try payload.name(a, item.name);
                try payload.byte(a, 0);
                try payload.uleb(a, item.signature);
            }
            try section(a, &out, 2, &payload);
        }
        // 3: functions
        try payload.uleb(a, self.functions.items.len);
        for (self.functions.items) |function| try payload.uleb(a, function.signature);
        try section(a, &out, 3, &payload);
        // 4: tables (0: closures, 1: host callbacks)
        if (self.table.items.len != 0 or self.host_slots != 0) {
            try payload.uleb(a, 2);
            try payload.byte(a, @backingInt(ValType.funcref));
            try payload.byte(a, 1);
            try payload.uleb(a, self.table.items.len);
            try payload.uleb(a, self.table.items.len);
            try payload.byte(a, @backingInt(ValType.externref));
            try payload.byte(a, 1);
            try payload.uleb(a, self.host_slots);
            try payload.uleb(a, self.host_slots);
            try section(a, &out, 4, &payload);
        }
        // 5: memory (fixed size)
        if (self.memory_pages) |pages| {
            try payload.uleb(a, 1);
            try payload.byte(a, 1);
            try payload.uleb(a, pages);
            try payload.uleb(a, pages);
            try section(a, &out, 5, &payload);
        }
        // 6: globals
        if (self.globals.items.len != 0) {
            try payload.uleb(a, self.globals.items.len);
            for (self.globals.items) |global| {
                try payload.byte(a, @backingInt(global.ty));
                try payload.byte(a, @intFromBool(global.mutable));
                switch (global.ty) {
                    .f32 => {
                        try payload.byte(a, @backingInt(Op.f32_const));
                        try payload.raw(a, std.mem.asBytes(&global.init));
                    },
                    else => {
                        try payload.byte(a, @backingInt(Op.i32_const));
                        try payload.sleb(a, @as(i32, @bitCast(global.init)));
                    },
                }
                try payload.byte(a, @backingInt(Op.end));
            }
            try section(a, &out, 6, &payload);
        }
        // 7: exports
        try payload.uleb(a, self.exports.items.len);
        for (self.exports.items) |item| {
            try payload.name(a, item.name);
            try payload.byte(a, @backingInt(item.kind));
            try payload.uleb(a, item.index);
        }
        try section(a, &out, 7, &payload);
        // 9: elements (table 0, offset 0, function indices)
        if (self.table.items.len != 0) {
            try payload.uleb(a, 1);
            try payload.byte(a, 0);
            try payload.byte(a, @backingInt(Op.i32_const));
            try payload.sleb(a, 0);
            try payload.byte(a, @backingInt(Op.end));
            try payload.uleb(a, self.table.items.len);
            for (self.table.items) |function| try payload.uleb(a, function);
            try section(a, &out, 9, &payload);
        }
        // 10: code
        try payload.uleb(a, self.functions.items.len);
        for (self.functions.items) |function| {
            try payload.uleb(a, function.body.len);
            try payload.raw(a, function.body);
        }
        try section(a, &out, 10, &payload);
        // 11: data
        if (self.data.items.len != 0) {
            try payload.uleb(a, 1);
            try payload.byte(a, 0);
            try payload.byte(a, @backingInt(Op.i32_const));
            try payload.sleb(a, @as(i32, @bitCast(self.data_offset)));
            try payload.byte(a, @backingInt(Op.end));
            try payload.uleb(a, self.data.items.len);
            try payload.raw(a, self.data.items);
            try section(a, &out, 11, &payload);
        }
        for (self.customs.items) |item| {
            try payload.name(a, item.name);
            try payload.raw(a, item.payload);
            try section(a, &out, 0, &payload);
        }
        return out.list.toOwnedSlice(a);
    }
};

fn section(a: A, out: *Bytes, id: u8, payload: *Bytes) A.Error!void {
    try out.byte(a, id);
    try out.uleb(a, payload.list.items.len);
    try out.raw(a, payload.list.items);
    payload.list.clearRetainingCapacity();
}
