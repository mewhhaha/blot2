//! Flat symbolic function bodies, assembled deterministically into Wasm.
//! Function handles are semantic instance IDs until final assembly.
const std = @import("std");
const arena_runtime = @import("arena_runtime.zig");
const artifact = @import("artifact_emitter.zig");
const Allocator = std.mem.Allocator;

pub const ValueType = enum(u8) { i32 = 0x7f, f32 = 0x7d, externref = 0x6f, none = 0x40 };
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
};
pub const Instruction = struct { op: Op, operand: u32 = 0 };
pub const Signature = struct { parameters: []ValueType, result: ValueType };
pub const Function = struct {
    parameters: []ValueType,
    result: ValueType,
    signature: u32,
    locals: std.ArrayList(ValueType) = .empty,
    instructions: std.ArrayList(Instruction) = .empty,
    fn deinit(self: *Function, allocator: Allocator) void {
        self.locals.deinit(allocator);
        self.instructions.deinit(allocator);
    }
};
const Global = struct { scalar: Scalar, bits: u32, mutable: bool = false };
const Import = struct { module: []u8, name: []u8, signature: u32 };
pub const Callback = struct { parameter: Scalar, result: Scalar };
const Export = struct { name: []u8, index: u32, parameter: Scalar, result: Scalar, global: bool, callback: ?Callback = null };
pub const Arena = struct { allocate: u32, reset: u32, mark: u32, collect: u32, heap: u32, base: u32, static_end: u32 };
/// Handles are indexes into an externref table, never encoded host pointers.
/// Callers retain a cursor mark and release only handles owned by that scope.
pub const HostReferences = struct { retain: u32, release: u32, cursor: u32 };
fn isArray(scalar: Scalar) bool {
    return scalar == .array_u32 or scalar == .array_f32;
}
fn callbackName(scalar: Scalar) ?[]const u8 {
    return switch (scalar) {
        .unit => "unit",
        .u32 => "u32",
        .bool => "bool",
        .f32 => "f32",
        .array_u32 => "array_u32",
        .array_f32 => "array_f32",
        .pointer => null,
    };
}

pub const Module = struct {
    allocator: Allocator,
    artifacts: ?*artifact.Recorder = null,
    functions: std.ArrayList(Function) = .empty,
    signatures: std.ArrayList(Signature) = .empty,
    imports: std.ArrayList(Import) = .empty,
    globals: std.ArrayList(Global) = .empty,
    exports: std.ArrayList(Export) = .empty,
    data: std.ArrayList(u8) = .empty,
    arena: ?Arena = null,
    lists: ?@import("list_runtime.zig").Runtime = null,
    host_references: ?HostReferences = null,
    public_arena: bool = false,
    indirect: bool = false,
    start: ?u32 = null,
    pub fn init(allocator: Allocator) Module {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Module) void {
        for (self.functions.items) |*function| function.deinit(self.allocator);
        for (self.signatures.items) |signature| self.allocator.free(signature.parameters);
        for (self.imports.items) |item| {
            self.allocator.free(item.module);
            self.allocator.free(item.name);
        }
        for (self.exports.items) |item| self.allocator.free(item.name);
        self.functions.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.exports.deinit(self.allocator);
        self.data.deinit(self.allocator);
    }
    pub fn internType(self: *Module, parameters: []const ValueType, result: ValueType) !u32 {
        for (self.signatures.items, 0..) |signature, index| {
            if (signature.result == result and std.mem.eql(ValueType, signature.parameters, parameters)) {
                try self.demandResource(.signature, @intCast(index), true);
                return @intCast(index);
            }
        }
        if (self.signatures.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const owned = try self.allocator.dupe(ValueType, parameters);
        errdefer self.allocator.free(owned);
        const id: u32 = @intCast(self.signatures.items.len);
        if (self.artifacts) |journal| try journal.signature(id, parameters, result);
        try self.demandResource(.signature, id, false);
        try self.signatures.append(self.allocator, .{ .parameters = owned, .result = result });
        return id;
    }
    pub fn addFunction(self: *Module, parameters: []const ValueType, result: ValueType) !u32 {
        const signature = try self.internType(parameters, result);
        return self.addFunctionForSignature(signature);
    }
    pub fn addFunctionForSignature(self: *Module, signature: u32) !u32 {
        std.debug.assert(signature < self.signatures.items.len);
        if (self.functions.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.functions.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .function = .{ .id = id, .signature = signature } });
        try self.demandResource(.function, id, false);
        try self.functions.append(self.allocator, .{ .parameters = self.signatures.items[signature].parameters, .result = self.signatures.items[signature].result, .signature = signature });
        return id;
    }
    pub fn importFunction(self: *Module, namespace: []const u8, name: []const u8, parameters: []const ValueType, result: ValueType) !u32 {
        const signature = try self.internType(parameters, result);
        for (self.imports.items, 0..) |item, index| if (std.mem.eql(u8, item.module, namespace) and std.mem.eql(u8, item.name, name)) {
            if (item.signature != signature) return error.InvalidFunctionReference;
            try self.demandResource(.import_, @intCast(index), true);
            return @intCast(index);
        };
        if (self.imports.items.len >= std.math.maxInt(u32)) return error.ModuleTooLarge;
        const owned_namespace = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(owned_namespace);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const index: u32 = @intCast(self.imports.items.len);
        if (self.artifacts) |journal| try journal.importFunction(index, namespace, name, signature);
        try self.demandResource(.import_, index, false);
        try self.imports.append(self.allocator, .{ .module = owned_namespace, .name = owned_name, .signature = signature });
        return index;
    }
    pub fn addLocal(self: *Module, id: u32, ty: ValueType) !u32 {
        const function = &self.functions.items[id];
        const index: u32 = @intCast(function.parameters.len + function.locals.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .local = .{ .function = id, .ty = ty } });
        try function.locals.append(self.allocator, ty);
        return index;
    }
    pub fn emit(self: *Module, id: u32, instruction: Instruction) !void {
        const role: artifact.Role = switch (instruction.op) {
            .call => .function,
            .call_import => .import_,
            .call_indirect => .signature,
            .global_get, .global_set => .global,
            .host_ref_get, .host_ref_set, .host_ref_size, .host_ref_grow => .host_table,
            else => .literal,
        };
        return self.emitReference(id, instruction, role);
    }
    pub fn emitReference(self: *Module, id: u32, instruction: Instruction, role: artifact.Role) !void {
        if (self.artifacts) |journal| try journal.append(.{ .instruction = .{ .function = id, .op = instruction.op, .operand = .{ .role = role, .value = instruction.operand } } });
        try self.functions.items[id].instructions.append(self.allocator, instruction);
        if (instruction.op == .call_indirect) self.indirect = true;
    }
    pub fn emitSlice(self: *Module, id: u32, instructions: []const Instruction) !void {
        for (instructions) |instruction| try self.emit(id, instruction);
    }
    pub fn demandResource(self: *Module, kind: artifact.ResourceKind, id: u32, hit: bool) !void {
        if (self.artifacts) |journal| try journal.append(.{ .demand = .{ .kind = kind, .id = id, .hit = hit } });
    }
    pub fn dataReference(self: *Module, address: u32, operand: artifact.Operand) !void {
        if (self.artifacts) |journal| try journal.append(.{ .data_word = .{ .address = address, .operand = operand } });
    }
    pub fn setStart(self: *Module, id: u32) !void {
        if (self.artifacts) |journal| try journal.append(.{ .start = id });
        self.start = id;
    }
    fn publicArena(self: *Module) !void {
        if (!self.public_arena) {
            if (self.artifacts) |journal| try journal.append(.public_arena);
            self.public_arena = true;
        }
    }
    pub fn addGlobal(self: *Module, scalar: Scalar, bits: u32, mutable: bool) !u32 {
        if (self.globals.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.globals.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .global = .{ .id = id, .scalar = scalar, .bits = .{ .value = bits }, .mutable = mutable } });
        try self.demandResource(.global, id, false);
        try self.globals.append(self.allocator, .{ .scalar = scalar, .bits = bits, .mutable = mutable });
        return id;
    }
    pub fn ensureHostReferences(self: *Module) !HostReferences {
        if (self.host_references) |references| {
            try self.demandResource(.host_references, 0, true);
            return references;
        }
        const cursor = try self.addGlobal(.u32, 0, true);
        const retain = try self.addFunction(&.{.externref}, .i32);
        const slot = try self.addLocal(retain, .i32);
        for ([_]Instruction{
            .{ .op = .global_get, .operand = cursor },              .{ .op = .local_tee, .operand = slot },
            .{ .op = .host_ref_size },                              .{ .op = .i32_eq },
            .{ .op = .if_ },                                        .{ .op = .host_ref_null },
            .{ .op = .i32_const, .operand = 1 },                    .{ .op = .host_ref_grow },
            .{ .op = .i32_const, .operand = std.math.maxInt(u32) }, .{ .op = .i32_eq },
            .{ .op = .if_ },                                        .{ .op = .unreachable_ },
            .{ .op = .end },                                        .{ .op = .end },
            .{ .op = .local_get, .operand = slot },                 .{ .op = .local_get, .operand = 0 },
            .{ .op = .host_ref_set },                               .{ .op = .local_get, .operand = slot },
            .{ .op = .i32_const, .operand = 1 },                    .{ .op = .i32_add },
            .{ .op = .global_set, .operand = cursor },              .{ .op = .local_get, .operand = slot },
        }) |instruction| try self.emit(retain, instruction);
        const release = try self.addFunction(&.{.i32}, .none);
        const current = try self.addLocal(release, .i32);
        for ([_]Instruction{
            .{ .op = .local_get, .operand = 0 },       .{ .op = .global_get, .operand = cursor },
            .{ .op = .i32_gt_u },                      .{ .op = .if_ },
            .{ .op = .unreachable_ },                  .{ .op = .end },
            .{ .op = .local_get, .operand = 0 },       .{ .op = .local_set, .operand = current },
            .{ .op = .block },                         .{ .op = .loop },
            .{ .op = .local_get, .operand = current }, .{ .op = .global_get, .operand = cursor },
            .{ .op = .i32_ge_u },                      .{ .op = .br_if, .operand = 1 },
            .{ .op = .local_get, .operand = current }, .{ .op = .host_ref_null },
            .{ .op = .host_ref_set },                  .{ .op = .local_get, .operand = current },
            .{ .op = .i32_const, .operand = 1 },       .{ .op = .i32_add },
            .{ .op = .local_set, .operand = current }, .{ .op = .br },
            .{ .op = .end },                           .{ .op = .end },
            .{ .op = .local_get, .operand = 0 },       .{ .op = .global_set, .operand = cursor },
        }) |instruction| try self.emit(release, instruction);
        const references: HostReferences = .{ .retain = retain, .release = release, .cursor = cursor };
        if (self.artifacts) |journal| try journal.append(.{ .host_references = references });
        self.host_references = references;
        try self.demandResource(.host_references, 0, false);
        return references;
    }
    pub fn dataWords(self: *Module, words: []const u32) !u32 {
        _ = try self.ensureArena();
        if (words.len > (std.math.maxInt(u32) - self.data.items.len) / 4) return error.ModuleTooLarge;
        const address: u32 = @intCast(self.data.items.len);
        try self.data.ensureUnusedCapacity(self.allocator, words.len * 4);
        for (words) |word| {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, word, .little);
            self.data.appendSliceAssumeCapacity(&bytes);
        }
        try self.finishStaticData(address);
        return address;
    }
    /// Reuse the module's single arena domain and append relocatable payloads
    /// above its existing static resources. Metadata is never copied twice.
    pub fn staticBytes(self: *Module, bytes: []const u8) !u32 {
        _ = try self.ensureArena();
        if (bytes.len % 4 != 0) return error.InvalidFunctionReference;
        if (bytes.len > std.math.maxInt(u32) - self.data.items.len) return error.ModuleTooLarge;
        const address: u32 = @intCast(self.data.items.len);
        try self.data.appendSlice(self.allocator, bytes);
        try self.finishStaticData(address);
        return address;
    }
    fn finishStaticData(self: *Module, address: u32) !void {
        if (self.artifacts) |journal| try journal.data(address, self.data.items[address..]);
        try self.demandResource(.static_data, address, false);
        const end: u32 = @intCast(self.data.items.len);
        if (self.artifacts) |journal| for ([_]u32{ self.arena.?.heap, self.arena.?.base, self.arena.?.static_end }) |id| try journal.append(.{ .global_bits = .{ .id = id, .bits = .{ .role = .static_address, .value = end } } });
        self.globals.items[self.arena.?.heap].bits = end;
        self.globals.items[self.arena.?.base].bits = end;
        self.globals.items[self.arena.?.static_end].bits = end;
    }
    /// Static data and mutable arena metadata have disjoint storage. Dynamic
    /// blocks begin above static data and 64 KiB; payload addresses stay stable.
    pub fn ensureArena(self: *Module) (Allocator.Error || error{ModuleTooLarge})!Arena {
        if (self.arena) |arena| {
            try self.demandResource(.arena, 0, true);
            return arena;
        }
        try self.data.appendNTimes(self.allocator, 0, 256);
        if (self.artifacts) |journal| try journal.data(0, self.data.items);
        const heap = try self.addGlobal(.u32, 256, true);
        const base = try self.addGlobal(.u32, 256, true);
        const static_end = try self.addGlobal(.u32, 256, false);
        const allocate = try self.addFunction(&.{.i32}, .i32);
        const reset = try self.addFunction(&.{.i32}, .i32);
        const mark = try self.addFunction(&.{ .i32, .i32, .i32 }, .i32);
        const collect = try self.addFunction(&.{ .i32, .i32, .i32 }, .i32);
        const arena: Arena = .{ .heap = heap, .base = base, .static_end = static_end, .allocate = allocate, .reset = reset, .mark = mark, .collect = collect };
        try arena_runtime.emit(self, arena);
        // Reset discards post-base blocks and every free-list link into them.
        // Pre-base runtime initializers remain in the physical block chain.
        try self.emitSlice(reset, &.{
            .{ .op = .global_get, .operand = base }, .{ .op = .global_set, .operand = heap },
            .{ .op = .i32_const, .operand = 32 },    .{ .op = .i32_const },
            .{ .op = .i32_const, .operand = 132 },   .{ .op = .memory_fill },
            .{ .op = .i32_const, .operand = 12 },    .{ .op = .i32_const },
            .{ .op = .i32_store },                   .{ .op = .i32_const, .operand = 4 },
            .{ .op = .i32_load },                    .{ .op = .global_get, .operand = base },
            .{ .op = .i32_ge_u },                    .{ .op = .if_ },
            .{ .op = .i32_const, .operand = 4 },     .{ .op = .i32_const },
            .{ .op = .i32_store },                   .{ .op = .end },
            .{ .op = .i32_const },
        });
        if (self.artifacts) |journal| try journal.append(.{ .arena = arena });
        self.arena = arena;
        try self.demandResource(.arena, 0, false);
        return arena;
    }
    pub fn ensureLists(self: *Module) (Allocator.Error || error{ModuleTooLarge})!@import("list_runtime.zig").Runtime {
        if (self.lists) |runtime| {
            try self.demandResource(.lists, 0, true);
            return runtime;
        }
        const arena = try self.ensureArena();
        const runtime = try @import("list_runtime.zig").emit(self, arena);
        if (self.artifacts) |journal| try journal.append(.{ .lists = runtime });
        self.lists = runtime;
        try self.demandResource(.lists, 0, false);
        return runtime;
    }
    pub fn exportFunction(self: *Module, id: u32, name: []const u8, parameter: Scalar, result: Scalar) !void {
        if (parameter == .array_u32 or parameter == .array_f32 or result == .array_u32 or result == .array_f32) {
            _ = try self.ensureArena();
            try self.publicArena();
        }
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = parameter, .result = result, .global = false }));
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = parameter, .result = result, .global = false });
    }
    pub fn importHostCallback(self: *Module, callback: Callback) !u32 {
        const parameter = callbackName(callback.parameter) orelse return error.InvalidFunctionReference;
        const result = callbackName(callback.result) orelse return error.InvalidFunctionReference;
        const name = try self.allocator.print("call_{s}_{s}", .{ parameter, result });
        defer self.allocator.free(name);
        return self.importFunction("blot:host/1", name, &.{ .externref, callback.parameter.machine() }, callback.result.machine());
    }
    pub fn exportCallbackFunction(self: *Module, id: u32, name: []const u8, callback: Callback, result: Scalar) !void {
        if (callbackName(callback.parameter) == null or callbackName(callback.result) == null or callbackName(result) == null) return error.InvalidFunctionReference;
        if (isArray(callback.parameter) or isArray(callback.result) or isArray(result)) {
            _ = try self.ensureArena();
            try self.publicArena();
        }
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = .unit, .result = result, .global = false, .callback = callback }));
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = .unit, .result = result, .global = false, .callback = callback });
    }
    pub fn exportConstant(self: *Module, name: []const u8, scalar: Scalar, bits: u32) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.globals.ensureUnusedCapacity(self.allocator, 1);
        try self.exports.ensureUnusedCapacity(self.allocator, 1);
        const id: u32 = @intCast(self.globals.items.len);
        if (self.artifacts) |journal| {
            try journal.append(.{ .global = .{ .id = id, .scalar = scalar, .bits = .{ .role = if (scalar == .pointer or scalar == .array_u32 or scalar == .array_f32) .static_address else .literal, .value = bits }, .mutable = false } });
            try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = Scalar.unit, .result = scalar, .global = true, .callback = @as(?Callback, null) }));
        }
        self.globals.appendAssumeCapacity(.{ .scalar = scalar, .bits = bits });
        self.exports.appendAssumeCapacity(.{ .name = owned, .index = id, .parameter = .unit, .result = scalar, .global = true });
    }
    pub fn exportGlobal(self: *Module, id: u32, name: []const u8) !void {
        if (id >= self.globals.items.len) return error.InvalidGlobalReference;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = .unit, .result = self.globals.items[id].scalar, .global = true }));
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = .unit, .result = self.globals.items[id].scalar, .global = true });
    }
    pub fn assemble(self: *const Module) ![]u8 {
        var output = Bytes.init(self.allocator);
        defer output.deinit();
        try output.raw(&.{ 0, 97, 115, 109, 1, 0, 0, 0 });
        var payload = Bytes.init(self.allocator);
        defer payload.deinit();

        try payload.uleb(@intCast(self.signatures.items.len));
        for (self.signatures.items) |function| {
            try payload.byte(0x60);
            try payload.uleb(@intCast(function.parameters.len));
            for (function.parameters) |ty| try payload.byte(@backingInt(ty));
            try payload.byte(if (function.result == .none) 0 else 1);
            if (function.result != .none) try payload.byte(@backingInt(function.result));
        }
        if (self.signatures.items.len != 0) try output.section(1, payload.items());
        payload.clear();
        if (self.functions.items.len > std.math.maxInt(u32) - self.imports.items.len) return error.ModuleTooLarge;
        const import_count: u32 = @intCast(self.imports.items.len);
        if (import_count != 0) {
            try payload.uleb(import_count);
            for (self.imports.items) |item| {
                try payload.name(item.module);
                try payload.name(item.name);
                try payload.byte(0);
                try payload.uleb(item.signature);
            }
            try output.section(2, payload.items());
            payload.clear();
        }
        try payload.uleb(@intCast(self.functions.items.len));
        for (self.functions.items) |function| try payload.uleb(function.signature);
        if (self.functions.items.len != 0) try output.section(3, payload.items());
        payload.clear();
        if (self.indirect or self.host_references != null) {
            try payload.uleb(if (self.host_references != null) 2 else 1);
            try payload.byte(0x70); // funcref
            try payload.byte(0); // minimum only
            try payload.uleb(if (self.indirect) @intCast(self.functions.items.len) else 0);
            if (self.host_references != null) {
                try payload.byte(0x6f); // externref, separate from callable handles
                try payload.byte(0); // minimum only
                try payload.uleb(0);
            }
            try output.section(4, payload.items());
            payload.clear();
        }
        if (self.arena != null) {
            try payload.uleb(1);
            try payload.byte(1); // bounded Wasm32 memory
            const pages: u32 = @intCast(@max(1, (self.data.items.len + 65535) / 65536));
            try payload.uleb(pages);
            try payload.uleb(65536);
            try output.section(5, payload.items());
            payload.clear();
        }
        if (self.globals.items.len != 0) {
            try payload.uleb(@intCast(self.globals.items.len));
            for (self.globals.items) |global| {
                try payload.byte(@backingInt(global.scalar.machine()));
                try payload.byte(@intFromBool(global.mutable));
                try encodeInstruction(&payload, .{ .op = if (global.scalar == .f32) .f32_const else .i32_const, .operand = global.bits }, self.functions.items.len, self.globals.items.len, self.signatures.items.len, import_count);
                try payload.byte(0x0b);
            }
            try output.section(6, payload.items());
            payload.clear();
        }
        try payload.uleb(@intCast(self.exports.items.len + @as(usize, if (self.public_arena) 3 else 0)));
        for (self.exports.items) |item| {
            try payload.name(item.name);
            try payload.byte(if (item.global) 3 else 0);
            try payload.uleb(if (item.global) item.index else item.index + import_count);
        }
        if (self.public_arena) {
            try payload.name("blot:memory");
            try payload.byte(2);
            try payload.uleb(0);
            try payload.name("blot:allocate");
            try payload.byte(0);
            try payload.uleb(self.arena.?.allocate + import_count);
            try payload.name("blot:reset");
            try payload.byte(0);
            try payload.uleb(self.arena.?.reset + import_count);
        }
        try output.section(7, payload.items());
        payload.clear();
        if (self.start) |start| {
            if (start >= self.functions.items.len or self.functions.items[start].parameters.len != 0 or self.functions.items[start].result != .none) return error.InvalidFunctionReference;
            try payload.uleb(start + import_count);
            try output.section(8, payload.items());
            payload.clear();
        }
        if (self.indirect) {
            try payload.uleb(1);
            try payload.byte(0); // active segment at table zero
            try payload.raw(&.{ 0x41, 0, 0x0b });
            try payload.uleb(@intCast(self.functions.items.len));
            for (0..self.functions.items.len) |id| try payload.uleb(@as(u32, @intCast(id)) + import_count);
            try output.section(9, payload.items());
            payload.clear();
        }
        if (self.functions.items.len != 0) {
            try payload.uleb(@intCast(self.functions.items.len));
            var body = Bytes.init(self.allocator);
            defer body.deinit();
            for (self.functions.items) |function| {
                body.clear();
                try body.uleb(@intCast(function.locals.items.len));
                for (function.locals.items) |local| {
                    try body.byte(1);
                    try body.byte(@backingInt(local));
                }
                for (function.instructions.items) |instruction| try encodeInstruction(&body, instruction, self.functions.items.len, self.globals.items.len, self.signatures.items.len, import_count);
                try body.byte(0x0b);
                try payload.uleb(@intCast(body.items().len));
                try payload.raw(body.items());
            }
            try output.section(10, payload.items());
            payload.clear();
        }
        if (self.arena != null and self.data.items.len != 0) {
            try payload.uleb(1); // one active data segment at memory zero
            try payload.byte(0);
            try payload.byte(0x41);
            try payload.byte(0);
            try payload.byte(0x0b);
            try payload.uleb(@intCast(self.data.items.len));
            try payload.raw(self.data.items);
            try output.section(11, payload.items());
            payload.clear();
        }
        try payload.name("blot:abi");
        try payload.byte(2);
        var function_count: u32 = 0;
        for (self.exports.items) |item| if (!item.global) {
            function_count += 1;
        };
        try payload.uleb(function_count);
        for (self.exports.items) |item| if (!item.global) {
            try payload.name(item.name);
            if (item.callback) |callback| {
                try payload.byte(4);
                try payload.byte(@backingInt(callback.parameter));
                try payload.byte(@backingInt(callback.result));
            } else try payload.byte(@backingInt(item.parameter));
            try payload.byte(@backingInt(item.result));
        };
        var constant_count: u32 = 0;
        for (self.exports.items) |item| if (item.global) {
            constant_count += 1;
        };
        try payload.uleb(constant_count);
        for (self.exports.items) |item| if (item.global) {
            try payload.name(item.name);
            try payload.byte(@backingInt(item.result));
        };
        try output.section(0, payload.items());
        return output.buffer.toOwnedSlice(self.allocator);
    }
};

pub const Bytes = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8) = .empty,
    pub fn init(allocator: Allocator) Bytes {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Bytes) void {
        self.buffer.deinit(self.allocator);
    }
    pub fn items(self: *const Bytes) []const u8 {
        return self.buffer.items;
    }
    pub fn clear(self: *Bytes) void {
        self.buffer.clearRetainingCapacity();
    }
    pub fn byte(self: *Bytes, value: u8) !void {
        try self.buffer.append(self.allocator, value);
    }
    pub fn raw(self: *Bytes, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }
    pub fn name(self: *Bytes, bytes: []const u8) !void {
        if (bytes.len > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.uleb(@intCast(bytes.len));
        try self.raw(bytes);
    }
    pub fn uleb(self: *Bytes, value: u32) !void {
        var remaining = value;
        while (true) {
            const low: u8 = @truncate(remaining & 127);
            remaining >>= 7;
            try self.byte(low | @as(u8, if (remaining != 0) 128 else 0));
            if (remaining == 0) return;
        }
    }
    pub fn sleb(self: *Bytes, value: i32) !void {
        var remaining = value;
        while (true) {
            const low: u8 = @truncate(@as(u32, @bitCast(remaining)) & 127);
            remaining >>= 7;
            const done = (remaining == 0 and low & 64 == 0) or (remaining == -1 and low & 64 != 0);
            try self.byte(low | @as(u8, if (done) 0 else 128));
            if (done) return;
        }
    }
    pub fn section(self: *Bytes, id: u8, payload: []const u8) !void {
        try self.byte(id);
        if (payload.len > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.uleb(@intCast(payload.len));
        try self.raw(payload);
    }
};
fn encodeInstruction(bytes: *Bytes, inst: Instruction, functions: usize, globals: usize, signatures: usize, imports: u32) !void {
    const code: u8 = switch (inst.op) {
        .unreachable_ => 0x00,
        .nop => 0x01,
        .block => 0x02,
        .loop => 0x03,
        .if_ => 0x04,
        .else_ => 0x05,
        .end => 0x0b,
        .br => 0x0c,
        .br_if => 0x0d,
        .return_ => 0x0f,
        .call, .call_import => 0x10,
        .call_indirect => 0x11,
        .host_ref_get => 0x25,
        .host_ref_set => 0x26,
        .host_ref_size, .host_ref_grow => 0xfc,
        .host_ref_null => 0xd0,
        .host_ref_is_null => 0xd1,
        .drop => 0x1a,
        .local_get => 0x20,
        .local_set => 0x21,
        .local_tee => 0x22,
        .global_get => 0x23,
        .global_set => 0x24,
        .i32_load => 0x28,
        .f32_load => 0x2a,
        .i32_store => 0x36,
        .f32_store => 0x38,
        .memory_size => 0x3f,
        .memory_grow => 0x40,
        .memory_copy, .memory_fill => 0xfc,
        .i32_reinterpret_f32 => 0xbc,
        .f32_reinterpret_i32 => 0xbe,
        .i32_const => 0x41,
        .f32_const => 0x43,
        .i32_eqz => 0x45,
        .i32_eq => 0x46,
        .i32_ne => 0x47,
        .i32_lt_u => 0x49,
        .i32_gt_u => 0x4b,
        .i32_le_u => 0x4d,
        .i32_ge_u => 0x4f,
        .f32_eq => 0x5b,
        .f32_ne => 0x5c,
        .f32_lt => 0x5d,
        .f32_gt => 0x5e,
        .f32_le => 0x5f,
        .f32_ge => 0x60,
        .i32_add => 0x6a,
        .i32_sub => 0x6b,
        .i32_mul => 0x6c,
        .i32_div_u => 0x6e,
        .i32_rem_u => 0x70,
        .i32_and => 0x71,
        .i32_or => 0x72,
        .i32_xor => 0x73,
        .i32_shl => 0x74,
        .i32_shr_u => 0x76,
        .i32_clz => 0x67,
        .i32_ctz => 0x68,
        .f32_abs => 0x8b,
        .f32_neg => 0x8c,
        .f32_ceil => 0x8d,
        .f32_floor => 0x8e,
        .f32_trunc => 0x8f,
        .f32_sqrt => 0x91,
        .f32_add => 0x92,
        .f32_sub => 0x93,
        .f32_mul => 0x94,
        .f32_div => 0x95,
        .f32_min => 0x96,
        .f32_max => 0x97,
        .f32_convert_i32_u => 0xb3,
        .i32_trunc_sat_f32_u => 0xfc,
    };
    try bytes.byte(code);
    switch (inst.op) {
        .block, .loop, .if_ => try bytes.byte(if (inst.operand == 0) 0x40 else @intCast(inst.operand)),
        .br, .br_if, .local_get, .local_set, .local_tee => try bytes.uleb(inst.operand),
        .call => {
            if (inst.operand >= functions) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand + imports);
        },
        .call_import => {
            if (inst.operand >= imports) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand);
        },
        .call_indirect => {
            if (inst.operand >= signatures) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand);
            try bytes.byte(0);
        },
        .global_get, .global_set => {
            if (inst.operand >= globals) return error.InvalidGlobalReference;
            try bytes.uleb(inst.operand);
        },
        .i32_const => try bytes.sleb(@bitCast(inst.operand)),
        .f32_const => {
            var raw: [4]u8 = undefined;
            std.mem.writeInt(u32, &raw, inst.operand, .little);
            try bytes.raw(&raw);
        },
        .i32_trunc_sat_f32_u => try bytes.byte(1),
        .i32_load, .f32_load, .i32_store, .f32_store => {
            try bytes.uleb(2);
            try bytes.uleb(inst.operand);
        },
        .memory_size, .memory_grow => try bytes.byte(0),
        .memory_copy => try bytes.raw(&.{ 10, 0, 0 }),
        .memory_fill => try bytes.raw(&.{ 11, 0 }),
        .host_ref_get, .host_ref_set => try bytes.uleb(1),
        .host_ref_size => try bytes.raw(&.{ 16, 1 }),
        .host_ref_grow => try bytes.raw(&.{ 15, 1 }),
        .host_ref_null => try bytes.byte(0x6f),
        else => {},
    }
}

test "signed LEB preserves unsigned scalar bits and boundaries" {
    var bytes = Bytes.init(std.testing.allocator);
    defer bytes.deinit();
    try bytes.sleb(-1);
    try std.testing.expectEqualSlices(u8, &.{0x7f}, bytes.items());
    bytes.clear();
    try bytes.sleb(64);
    try std.testing.expectEqualSlices(u8, &.{ 0xc0, 0x00 }, bytes.items());
    bytes.clear();
    try bytes.sleb(std.math.minInt(i32));
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x80, 0x80, 0x80, 0x78 }, bytes.items());
}
test "flat symbolic scalar module owns output independently" {
    const allocator = std.testing.allocator;
    var module = Module.init(allocator);
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .i32_const, .operand = 42 });
    try module.exportFunction(id, "answer", .unit, .u32);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    module.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "blot:abi") != null);
}
test "backend reports stale symbolic function references" {
    var module = Module.init(std.testing.allocator);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .call, .operand = 10 });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
}

fn hostReferenceOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    const references = try module.ensureHostReferences();
    const reused = try module.ensureHostReferences();
    try std.testing.expectEqual(references, reused);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
}
test "scoped host reference storage owns every allocation" {
    try hostReferenceOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, hostReferenceOwnership, .{});
}

fn arenaOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    try std.testing.expectEqual(arena, try module.ensureArena());
    _ = try module.dataWords(&.{ 0, 65552, 42 });
    try module.exportFunction(arena.allocate, "allocate", .u32, .u32);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "allocate") != null);
}
test "arena allocation collection and static roots release every failed compiler allocation" {
    try arenaOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, arenaOwnership, .{});
}

fn importOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    var namespace = "provider".*;
    var name = "execute".*;
    const imported = try module.importFunction(&namespace, &name, &.{ .externref, .i32 }, .i32);
    @memset(&namespace, 'x');
    @memset(&name, 'x');
    const same = try module.importFunction("provider", "execute", &.{ .externref, .i32 }, .i32);
    try std.testing.expectEqual(imported, same);
    const function = try module.addFunction(&.{ .externref, .i32 }, .i32);
    try module.emit(function, .{ .op = .local_get, .operand = 0 });
    try module.emit(function, .{ .op = .local_get, .operand = 1 });
    try module.emit(function, .{ .op = .call_import, .operand = imported });
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "provider") != null);
}
test "imports own names and signatures through mutation and allocation failure" {
    try importOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, importOwnership, .{});
}
test "import signature conflicts and stale references are rejected" {
    var module = Module.init(std.testing.allocator);
    defer module.deinit();
    _ = try module.importFunction("provider", "execute", &.{ .externref, .i32 }, .i32);
    try std.testing.expectError(error.InvalidFunctionReference, module.importFunction("provider", "execute", &.{.i32}, .f32));
    const function = try module.addFunction(&.{.i32}, .i32);
    try module.emit(function, .{ .op = .call_import, .operand = 100 });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
}
