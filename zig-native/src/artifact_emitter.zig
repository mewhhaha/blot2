//! Owned emission journal. Handles are typed, and are resolved by a new module.
//! This module never evaluates source and never stores an encoded Wasm module.
const std = @import("std");
const wasm = @import("wasm.zig");
const Allocator = std.mem.Allocator;
pub const Span = struct { start: u32, len: u32 };
pub const Role = enum { literal, function, import_, signature, global, table_function, static_address, operation, host_table };
pub const Operand = struct { role: Role = .literal, value: u32 = 0 };
pub const ResourceKind = enum { function, import_, signature, global, arena, host_references, static_data, operation, lists };
pub const Event = union(enum) {
    demand: struct { kind: ResourceKind, id: u32, hit: bool },
    operation_symbol: struct { id: u32, key: Span, foreign: bool },
    signature: struct { id: u32, parameters: Span, result: wasm.ValueType },
    function: struct { id: u32, signature: u32 },
    import_: struct { id: u32, module: Span, name: Span, signature: u32 },
    local: struct { function: u32, ty: wasm.ValueType },
    instruction: struct { function: u32, op: wasm.Op, operand: Operand },
    global: struct { id: u32, scalar: wasm.Scalar, bits: Operand, mutable: bool },
    global_bits: struct { id: u32, bits: Operand },
    data: struct { address: u32, bytes: Span },
    data_word: struct { address: u32, operand: Operand },
    arena: wasm.Arena,
    host_references: wasm.HostReferences,
    lists: @import("list_runtime.zig").Runtime,
    export_: struct { name: Span, index: u32, parameter: wasm.Scalar, result: wasm.Scalar, global: bool, callback: ?wasm.Callback },
    public_arena: void,
    start: u32,
};
pub const Record = struct { sequence: u64, owner: u32, event: Event };
pub const SymbolicInstruction = struct { op: wasm.Op, operand: Operand };
pub const FunctionRole = enum { job, arena_allocate, arena_reset, arena_mark, arena_collect, host_retain, host_release, output_export, runtime_initializer, module_start, unknown, list_new, list_address, list_copy, list_push, list_set, list_from_array, list_to_array, list_chunk_new, list_edit, static_closure };
pub const FunctionArtifact = struct { owner: u32, resource_owner: u32, role: FunctionRole, signature: u32, creation_sequence: u64, locals: Span, instructions: Span };
const Operation = struct { key: Span, foreign: bool };
pub const Recorder = struct {
    allocator: Allocator,
    owner: ?*const u32 = null,
    clock: ?*u64 = null,
    local_clock: u64 = 0,
    records: std.ArrayList(Record) = .empty,
    bytes: std.ArrayList(u8) = .empty,
    parameters: std.ArrayList(wasm.ValueType) = .empty,
    operations: std.ArrayList(Operation) = .empty,
    functions: []FunctionArtifact = &.{},
    locals: []wasm.ValueType = &.{},
    instructions: []SymbolicInstruction = &.{},
    sealed: bool = false,
    pub fn init(allocator: Allocator) Recorder {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Recorder) void {
        self.records.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
        self.parameters.deinit(self.allocator);
        self.operations.deinit(self.allocator);
        self.allocator.free(self.functions);
        self.allocator.free(self.locals);
        self.allocator.free(self.instructions);
        self.* = undefined;
    }
    pub fn append(self: *Recorder, event: Event) Allocator.Error!void {
        std.debug.assert(!self.sealed);
        try self.records.ensureUnusedCapacity(self.allocator, 1);
        const clock = self.clock orelse &self.local_clock;
        const sequence = clock.*;
        clock.* += 1;
        self.records.appendAssumeCapacity(.{ .sequence = sequence, .owner = if (self.owner) |owner| owner.* else 0, .event = event });
    }
    pub fn raw(self: *Recorder, value: []const u8) Allocator.Error!Span {
        const span: Span = .{ .start = @intCast(self.bytes.items.len), .len = @intCast(value.len) };
        try self.bytes.appendSlice(self.allocator, value);
        return span;
    }
    pub fn signature(self: *Recorder, id: u32, parameters: []const wasm.ValueType, result: wasm.ValueType) Allocator.Error!void {
        const mark = self.parameters.items.len;
        errdefer self.parameters.shrinkRetainingCapacity(mark);
        const span: Span = .{ .start = @intCast(mark), .len = @intCast(parameters.len) };
        try self.parameters.appendSlice(self.allocator, parameters);
        try self.append(.{ .signature = .{ .id = id, .parameters = span, .result = result } });
    }
    pub fn importFunction(self: *Recorder, id: u32, namespace: []const u8, name: []const u8, signature_: u32) Allocator.Error!void {
        const mark = self.bytes.items.len;
        errdefer self.bytes.shrinkRetainingCapacity(mark);
        const namespace_span = try self.raw(namespace);
        const name_span = try self.raw(name);
        try self.append(.{ .import_ = .{ .id = id, .module = namespace_span, .name = name_span, .signature = signature_ } });
    }
    pub fn data(self: *Recorder, address: u32, value: []const u8) Allocator.Error!void {
        const mark = self.bytes.items.len;
        errdefer self.bytes.shrinkRetainingCapacity(mark);
        try self.append(.{ .data = .{ .address = address, .bytes = try self.raw(value) } });
    }
    pub fn exportItem(self: *Recorder, item: anytype) Allocator.Error!void {
        const mark = self.bytes.items.len;
        errdefer self.bytes.shrinkRetainingCapacity(mark);
        try self.append(.{ .export_ = .{ .name = try self.raw(item.name), .index = item.index, .parameter = item.parameter, .result = item.result, .global = item.global, .callback = item.callback } });
    }
    pub fn captureOperations(self: *Recorder, entries: anytype) Allocator.Error!void {
        std.debug.assert(self.operations.items.len == 0);
        for (entries) |entry| {
            const mark = self.bytes.items.len;
            errdefer self.bytes.shrinkRetainingCapacity(mark);
            const key = try self.raw(entry.key);
            try self.operations.append(self.allocator, .{ .key = key, .foreign = entry.foreign });
        }
    }
    pub fn operationSymbol(self: *Recorder, id: u32, key: []const u8, foreign: bool) Allocator.Error!void {
        const mark = self.bytes.items.len;
        errdefer self.bytes.shrinkRetainingCapacity(mark);
        try self.append(.{ .operation_symbol = .{ .id = id, .key = try self.raw(key), .foreign = foreign } });
    }
    fn slice(self: *const Recorder, span: Span) []const u8 {
        return self.bytes.items[span.start..][0..span.len];
    }
    pub fn seal(self: *Recorder) void {
        self.owner = null;
        self.clock = null;
        self.sealed = true;
    }
    /// Successful jobs publish range-backed complete bodies, independently of
    /// the chronological replay stream. No slice points into the old module.
    pub fn freezeFunctions(self: *Recorder, function_owners: []const u32) Allocator.Error!void {
        std.debug.assert(self.sealed and self.functions.len == 0);
        var count: usize = 0;
        var local_count: usize = 0;
        var instruction_count: usize = 0;
        for (self.records.items) |record| switch (record.event) {
            .function => count += 1,
            .local => local_count += 1,
            .instruction => instruction_count += 1,
            else => {},
        };
        const functions = try self.allocator.alloc(FunctionArtifact, count);
        errdefer self.allocator.free(functions);
        @memset(functions, .{ .owner = 0, .resource_owner = 0, .role = .unknown, .signature = 0, .creation_sequence = 0, .locals = .{ .start = 0, .len = 0 }, .instructions = .{ .start = 0, .len = 0 } });
        const locals = try self.allocator.alloc(wasm.ValueType, local_count);
        errdefer self.allocator.free(locals);
        const instructions = try self.allocator.alloc(SymbolicInstruction, instruction_count);
        errdefer self.allocator.free(instructions);
        for (self.records.items) |record| switch (record.event) {
            .function => |item| {
                const function = &functions[item.id];
                function.owner = if (item.id < function_owners.len) function_owners[item.id] else 0;
                function.resource_owner = record.owner;
                function.role = if (function.owner != 0) .job else .unknown;
                function.signature = item.signature;
                function.creation_sequence = record.sequence;
            },
            .local => |item| functions[item.function].locals.len += 1,
            .instruction => |item| functions[item.function].instructions.len += 1,
            else => {},
        };
        for (self.records.items) |record| switch (record.event) {
            .arena => |arena| {
                functions[arena.allocate].role = .arena_allocate;
                functions[arena.reset].role = .arena_reset;
                functions[arena.mark].role = .arena_mark;
                functions[arena.collect].role = .arena_collect;
            },
            .host_references => |references| {
                functions[references.retain].role = .host_retain;
                functions[references.release].role = .host_release;
            },
            .lists => |runtime| {
                inline for (@typeInfo(@TypeOf(runtime)).@"struct".field_names) |field|
                    functions[@field(runtime, field)].role = @field(FunctionRole, "list_" ++ field);
            },
            .start => |id| functions[id].role = .module_start,
            .export_ => |item| if (!item.global and functions[item.index].owner == 0) {
                functions[item.index].role = .output_export;
            },
            else => {},
        };
        var local_offset: u32 = 0;
        var instruction_offset: u32 = 0;
        for (functions) |*function| {
            function.locals.start = local_offset;
            function.instructions.start = instruction_offset;
            local_offset += function.locals.len;
            instruction_offset += function.instructions.len;
            function.locals.len = 0;
            function.instructions.len = 0;
        }
        for (self.records.items) |record| switch (record.event) {
            .local => |item| {
                const span = &functions[item.function].locals;
                locals[span.start + span.len] = item.ty;
                span.len += 1;
            },
            .instruction => |item| {
                const span = &functions[item.function].instructions;
                instructions[span.start + span.len] = .{ .op = item.op, .operand = item.operand };
                span.len += 1;
            },
            else => {},
        };
        // Publication is the final, infallible step. Release the previous
        // empty owners explicitly before assigning the completed arrays.
        self.allocator.free(self.functions);
        self.allocator.free(self.locals);
        self.allocator.free(self.instructions);
        self.functions = functions;
        self.locals = locals;
        self.instructions = instructions;
    }
    pub fn materialize(self: *const Recorder, allocator: Allocator) !wasm.Module {
        var module = wasm.Module.init(allocator);
        errdefer module.deinit();
        try self.replayInto(&module);
        return module;
    }
    /// Prefix resources exercise true relocation; exact replay uses an empty module.
    pub fn replayInto(self: *const Recorder, module: *wasm.Module) !void {
        if (!self.sealed or module.artifacts != null) return error.InvalidArtifact;
        // Arena metadata lives at fixed addresses. Complete fresh-module replay
        // is admitted; composing an independently populated arena is not yet.
        if (module.data.items.len != 0 or module.arena != null or module.host_references != null) return error.UnsupportedArenaComposition;
        var replay = Replay.init(module.allocator, self);
        defer replay.deinit();
        try replay.prepareOperations();
        for (self.records.items) |record| switch (record.event) {
            .demand, .operation_symbol => {},
            .signature => |item| {
                const actual = try module.internType(self.parameters.items[item.parameters.start..][0..item.parameters.len], item.result);
                try replay.put(&replay.signatures, item.id, actual);
            },
            .function => |item| {
                const signature_ = module.signatures.items[try replay.get(replay.signatures.items, item.signature)];
                const actual = try module.addFunction(signature_.parameters, signature_.result);
                try replay.put(&replay.functions, item.id, actual);
            },
            .import_ => |item| {
                const signature_ = module.signatures.items[try replay.get(replay.signatures.items, item.signature)];
                const actual = try module.importFunction(self.slice(item.module), self.slice(item.name), signature_.parameters, signature_.result);
                try replay.put(&replay.imports, item.id, actual);
            },
            .local => |item| {
                _ = try module.addLocal(try replay.get(replay.functions.items, item.function), item.ty);
            },
            .instruction => |item| try module.emit(try replay.get(replay.functions.items, item.function), .{ .op = item.op, .operand = try replay.resolve(item.operand) }),
            .global => |item| {
                const actual = try module.addGlobal(item.scalar, try replay.resolve(item.bits), item.mutable);
                try replay.put(&replay.globals, item.id, actual);
            },
            .global_bits => |item| module.globals.items[try replay.get(replay.globals.items, item.id)].bits = try replay.resolve(item.bits),
            .data => |item| {
                const address: u32 = @intCast(module.data.items.len);
                try module.data.appendSlice(module.allocator, self.slice(item.bytes));
                try replay.data.append(replay.allocator, .{ .original = item.address, .actual = address, .len = item.bytes.len });
            },
            .data_word => |item| {
                const address = try replay.address(item.address);
                if (address > module.data.items.len or 4 > module.data.items.len - address) return error.InvalidArtifact;
                std.mem.writeInt(u32, module.data.items[address..][0..4], try replay.resolve(item.operand), .little);
            },
            .arena => |item| module.arena = .{ .allocate = try replay.get(replay.functions.items, item.allocate), .reset = try replay.get(replay.functions.items, item.reset), .mark = try replay.get(replay.functions.items, item.mark), .collect = try replay.get(replay.functions.items, item.collect), .heap = try replay.get(replay.globals.items, item.heap), .base = try replay.get(replay.globals.items, item.base), .static_end = try replay.get(replay.globals.items, item.static_end) },
            .host_references => |item| module.host_references = .{ .retain = try replay.get(replay.functions.items, item.retain), .release = try replay.get(replay.functions.items, item.release), .cursor = try replay.get(replay.globals.items, item.cursor) },
            .lists => |item| {
                var runtime: @TypeOf(item) = undefined;
                inline for (@typeInfo(@TypeOf(item)).@"struct".field_names) |field|
                    @field(runtime, field) = try replay.get(replay.functions.items, @field(item, field));
                module.lists = runtime;
            },
            .export_ => |item| {
                const name = try module.allocator.dupe(u8, self.slice(item.name));
                errdefer module.allocator.free(name);
                try module.exports.append(module.allocator, .{ .name = name, .index = try replay.get(if (item.global) replay.globals.items else replay.functions.items, item.index), .parameter = item.parameter, .result = item.result, .global = item.global, .callback = item.callback });
            },
            .public_arena => module.public_arena = true,
            .start => |id| module.start = try replay.get(replay.functions.items, id),
        };
    }
};
const Replay = struct {
    allocator: Allocator,
    journal: *const Recorder,
    functions: std.ArrayList(u32) = .empty,
    signatures: std.ArrayList(u32) = .empty,
    imports: std.ArrayList(u32) = .empty,
    globals: std.ArrayList(u32) = .empty,
    operations: std.ArrayList(u32) = .empty,
    data: std.ArrayList(struct { original: u32, actual: u32, len: u32 }) = .empty,
    fn init(allocator: Allocator, journal: *const Recorder) Replay {
        return .{ .allocator = allocator, .journal = journal };
    }
    fn deinit(self: *Replay) void {
        self.functions.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.operations.deinit(self.allocator);
        self.data.deinit(self.allocator);
    }
    fn put(self: *Replay, map: *std.ArrayList(u32), original: u32, actual: u32) Allocator.Error!void {
        if (original >= map.items.len) try map.appendNTimes(self.allocator, std.math.maxInt(u32), original + 1 - map.items.len);
        std.debug.assert(map.items[original] == std.math.maxInt(u32));
        map.items[original] = actual;
    }
    fn get(_: *const Replay, map: []const u32, original: u32) !u32 {
        if (original >= map.len or map[original] == std.math.maxInt(u32)) return error.InvalidArtifact;
        return map[original];
    }
    fn address(self: *const Replay, original: u32) !u32 {
        if (original == 0) return 0;
        for (self.data.items) |item| if (original >= item.original and original - item.original < item.len) return item.actual + original - item.original;
        // A one-past-end arena base is an explicit relocation too.
        for (self.data.items) |item| if (original == item.original + item.len) return item.actual + item.len;
        return error.InvalidArtifact;
    }
    fn prepareOperations(self: *Replay) !void {
        const ordered = try self.allocator.alloc(u32, self.journal.operations.items.len);
        defer self.allocator.free(ordered);
        for (ordered, 0..) |*id, index| id.* = @intCast(index);
        std.mem.sort(u32, ordered, self.journal, struct {
            fn less(journal: *const Recorder, a: u32, b: u32) bool {
                return std.mem.order(u8, journal.slice(journal.operations.items[a].key), journal.slice(journal.operations.items[b].key)) == .lt;
            }
        }.less);
        try self.operations.appendNTimes(self.allocator, 0, ordered.len + 1);
        var next: u32 = 2;
        for (ordered) |id| {
            const foreign = self.journal.operations.items[id].foreign;
            self.operations.items[id + 1] = if (foreign) 1 else next;
            if (!foreign) next += 1;
        }
    }
    fn resolve(self: *const Replay, operand: Operand) !u32 {
        return switch (operand.role) {
            .literal, .host_table => operand.value,
            .function, .table_function => self.get(self.functions.items, operand.value),
            .import_ => self.get(self.imports.items, operand.value),
            .signature => self.get(self.signatures.items, operand.value),
            .global => self.get(self.globals.items, operand.value),
            .static_address => self.address(operand.value),
            .operation => if (operand.value == 0 or operand.value >= self.operations.items.len) error.InvalidArtifact else self.operations.items[operand.value],
        };
    }
};
