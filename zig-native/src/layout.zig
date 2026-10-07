//! Interned concrete representation evidence, separate from inference history.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const wasm = @import("wasm.zig");
const evidence = @import("type_evidence.zig");
const code_expectation = @import("code_expectation.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const erased: Id = 6;
/// Unknown effects are representation-only facts, distinct from closed empty.
pub const unknown_row: u32 = std.math.maxInt(u32);
pub const Tag = enum(u8) { invalid, unit, boolean, u32, f32, never, product, record, nominal, array, list, function, demand, type_constructor, resolver, erased, provider, state_provider };
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Mapping = struct { variable: types.Id, layout: Id };
pub const RowMapping = struct { variable: u32, row: evidence.Effects.Id };
pub const Error = Allocator.Error || error{ UnresolvedType, LayoutLimit, TypeMismatch };
pub const Store = struct {
    record_names: @import("record_order.zig").Names = .{},
    allocator: Allocator,
    effects: evidence.Effects.Store,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(u32) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    pub fn init(allocator: Allocator) Error!Store {
        var self: Store = .{ .allocator = allocator, .effects = .{ .allocator = allocator } };
        errdefer self.deinit();
        self.effects = evidence.Effects.Store.init(allocator) catch |err| return effectError(err);
        try self.nodes.appendSlice(allocator, &.{ .{ .tag = .invalid }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never }, .{ .tag = .erased } });
        try self.next.appendNTimes(allocator, 0, self.nodes.items.len);
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.record_names.deinit(self.allocator);
        self.effects.deinit();
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.next.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
    }
    pub fn node(self: *const Store, id: Id) Node {
        return self.nodes.items[id];
    }
    pub fn children(self: *const Store, id: Id) []const Id {
        const n = self.node(id);
        return switch (n.tag) {
            .product => self.extra.items[n.a..][0..n.b],
            .record => self.extra.items[n.a..][0 .. n.b * 2],
            .nominal => self.extra.items[n.c + 1 ..][0..self.extra.items[n.c]],
            else => &.{},
        };
    }
    pub fn machine(self: *const Store, id: Id) wasm.ValueType {
        return if (self.node(id).tag == .f32) .f32 else .i32;
    }
    pub fn scalar(self: *const Store, id: Id) ?wasm.Scalar {
        return switch (self.node(id).tag) {
            .unit => .unit,
            .boolean => .bool,
            .u32 => .u32,
            .f32 => .f32,
            else => null,
        };
    }
    pub fn abi(self: *const Store, id: Id) ?wasm.Scalar {
        if (self.scalar(id)) |value| return value;
        const n = self.node(id);
        if (n.tag != .array) return null;
        return switch (self.node(n.a).tag) {
            .u32 => .array_u32,
            .f32 => .array_f32,
            else => null,
        };
    }
    pub fn intern(self: *Store, tag: Tag, a: u32, b: u32, values: []const u32) Error!Id {
        return self.internWithEffects(tag, a, b, 0, values);
    }
    pub fn internWithEffects(self: *Store, tag: Tag, a: u32, b: u32, row: evidence.Effects.Id, values: []const u32) Error!Id {
        return self.internFields(tag, a, b, row, values);
    }
    pub fn internStateProvider(self: *Store, read: Id, write: Id, state: Id) Error!Id {
        return self.internFields(.state_provider, read, write, state, &.{});
    }
    /// Executable structural records share one layout regardless of field
    /// spelling order. Raw intern remains available for imported physical views.
    pub fn internRecord(self: *Store, values: []const u32) Error!Id {
        if (values.len % 2 != 0) return error.TypeMismatch;
        var ordered = true;
        var offset: usize = 2;
        while (offset < values.len) : (offset += 2) if (!self.record_names.less(values[offset - 2], values[offset])) {
            ordered = false;
            break;
        };
        if (ordered) return self.intern(.record, 0, 0, values);
        var buffer: [256]u8 align(@alignOf(u32)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const Field = struct {
            name: u32,
            ty: u32,
            fn less(names: *const @import("record_order.zig").Names, left: @This(), right: @This()) bool {
                return names.less(left.name, right.name);
            }
        };
        const fields = try scratch.allocator().alloc(Field, values.len / 2);
        defer scratch.allocator().free(fields);
        for (fields, 0..) |*field, index| field.* = .{ .name = values[index * 2], .ty = values[index * 2 + 1] };
        std.mem.sortUnstable(Field, fields, &self.record_names, Field.less);
        for (fields[1..], fields[0 .. fields.len - 1]) |field, prior| if (field.name == prior.name) return error.TypeMismatch;
        const words: []const u32 = @as([*]const u32, @ptrCast(fields.ptr))[0..values.len];
        return self.intern(.record, 0, 0, words);
    }
    fn internFields(self: *Store, tag: Tag, a: u32, b: u32, row: u32, values: []const u32) Error!Id {
        if (tag != .state_provider and ((row != unknown_row and row >= self.effects.rows.items.len) or (row != 0 and tag != .function and tag != .demand and tag != .provider))) return error.TypeMismatch;
        if (tag == .state_provider and (a == 0 or b == 0 or row == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len or row >= self.nodes.items.len or values.len != 0)) return error.TypeMismatch;
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&a));
        hash.update(std.mem.asBytes(&b));
        hash.update(std.mem.asBytes(&row));
        hash.update(std.mem.sliceAsBytes(values));
        const fingerprint = hash.final();
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate]) {
            const n = self.node(candidate);
            const same = n.tag == tag and switch (tag) {
                .product, .record => std.mem.eql(u32, self.children(candidate), values),
                .nominal => n.a == a and n.b == b and std.mem.eql(u32, self.children(candidate), values),
                else => n.a == a and n.b == b and n.c == row,
            };
            if (same) return candidate;
        }
        if (self.nodes.items.len == std.math.maxInt(u32) or values.len >= std.math.maxInt(u32) or self.extra.items.len > std.math.maxInt(u32) - values.len - 1) return error.LayoutLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        try self.extra.ensureUnusedCapacity(self.allocator, values.len + 1);
        var n: Node = .{ .tag = tag, .a = a, .b = b, .c = row };
        switch (tag) {
            .product, .record => {
                n.a = @intCast(self.extra.items.len);
                n.b = @intCast(if (tag == .record) values.len / 2 else values.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .nominal => {
                n.c = @intCast(self.extra.items.len);
                self.extra.appendAssumeCapacity(@intCast(values.len));
                self.extra.appendSliceAssumeCapacity(values);
            },
            else => {},
        }
        const id: Id = @intCast(self.nodes.items.len);
        self.nodes.appendAssumeCapacity(n);
        self.next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
    pub fn fromType(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping) Error!Id {
        return self.fromTypeDepth(module, ty, mappings, &.{}, 0, false);
    }
    /// Representation-only admission preserves unresolved semantic variables.
    pub fn fromTypePartial(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping) Error!Id {
        return self.fromTypeDepth(module, ty, mappings, &.{}, 0, true);
    }
    pub fn fromTypeWithRows(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, partial: bool) Error!Id {
        return self.fromTypeDepth(module, ty, mappings, rows, 0, partial);
    }
    pub fn rowFromType(self: *Store, module: *const core.Module, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, partial: bool) Error!evidence.Effects.Id {
        return self.fromTypeRow(module, row, mappings, rows, 0, partial);
    }
    /// Semantic record fields have canonical name order. Callers serializing an
    /// existing record must reorder its source slots to this layout by name.
    pub fn fromEvidence(self: *Store, view: evidence.View, id: evidence.Id) Error!Id {
        var budget: usize = 1_000_000;
        return self.fromEvidenceDepth(view, id, 0, &budget);
    }
    pub fn toEvidence(self: *const Store, target: *evidence.Store, id: Id) evidence.Error!evidence.Id {
        var budget: usize = 1_000_000;
        return self.toEvidenceDepth(target, id, 0, &budget);
    }
    fn toEvidenceDepth(self: *const Store, target: *evidence.Store, id: Id, depth: usize, budget: *usize) evidence.Error!evidence.Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (id == 0 or id >= self.nodes.items.len) return error.UnresolvedType;
        const n = self.node(id);
        switch (n.tag) {
            .invalid, .erased => return error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => return id,
            .array => return target.intern(.array, try self.toEvidenceDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .list => return target.intern(.list, try self.toEvidenceDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .demand => return target.internWithEffects(.demand, try self.toEvidenceDepth(target, n.a, depth + 1, budget), 0, try self.toEvidenceRow(target, n.c, depth + 1, budget), &.{}),
            .type_constructor => return target.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return target.intern(.resolver, try self.toEvidenceDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .provider => return target.internWithEffects(.provider, try self.toEvidenceDepth(target, n.a, depth + 1, budget), 0, try self.toEvidenceRow(target, n.c, depth + 1, budget), &.{}),
            .state_provider => return target.internStateProvider(try self.toEvidenceDepth(target, n.a, depth + 1, budget), try self.toEvidenceDepth(target, n.b, depth + 1, budget), try self.toEvidenceDepth(target, n.c, depth + 1, budget)),
            .function => return target.internWithEffects(.function, try self.toEvidenceDepth(target, n.a, depth + 1, budget), try self.toEvidenceDepth(target, n.b, depth + 1, budget), try self.toEvidenceRow(target, n.c, depth + 1, budget), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, target.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(allocator);
                for (self.children(id), 0..) |child, index| {
                    try values.append(allocator, if (n.tag == .record and index % 2 == 0) child else try self.toEvidenceDepth(target, child, depth + 1, budget));
                }
                return target.intern(if (n.tag == .product) .product else if (n.tag == .record) .record else .nominal, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    /// Partial code shapes have their own owner and cannot be semantic evidence.
    pub fn toCodeExpectation(self: *const Store, target: *code_expectation.Store, id: Id) Error!code_expectation.Id {
        var budget: usize = 1_000_000;
        return self.toExpectationDepth(target, id, 0, &budget);
    }
    fn internExpectation(self: *const Store, target: *code_expectation.Store, tag: code_expectation.Tag, a: u32, b: u32, values: []const u32) Error!code_expectation.Id {
        _ = self;
        return target.intern(tag, a, b, values) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.LayoutLimit;
    }
    fn toExpectationDepth(self: *const Store, target: *code_expectation.Store, id: Id, depth: usize, budget: *usize) Error!code_expectation.Id {
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        if (id == 0 or id >= self.nodes.items.len) return error.UnresolvedType;
        const n = self.node(id);
        switch (n.tag) {
            .invalid => return error.UnresolvedType,
            .erased => return 0,
            .unit, .boolean, .u32, .f32, .never => return id,
            .array => return self.internExpectation(target, .array, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .list => return self.internExpectation(target, .list, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .demand => return self.internExpectation(target, .demand, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .type_constructor => return self.internExpectation(target, .type_constructor, n.a, n.b, &.{}),
            .resolver => return self.internExpectation(target, .resolver, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .provider => return self.internExpectation(target, .provider, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .state_provider => return target.internStateProvider(try self.toExpectationDepth(target, n.a, depth + 1, budget), try self.toExpectationDepth(target, n.b, depth + 1, budget), try self.toExpectationDepth(target, n.c, depth + 1, budget)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.LayoutLimit,
            .function => return self.internExpectation(target, .function, try self.toExpectationDepth(target, n.a, depth + 1, budget), try self.toExpectationDepth(target, n.b, depth + 1, budget), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, target.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(allocator);
                for (self.children(id), 0..) |child, index| {
                    try values.append(allocator, if (n.tag == .record and index % 2 == 0) child else try self.toExpectationDepth(target, child, depth + 1, budget));
                }
                return self.internExpectation(target, if (n.tag == .product) .product else if (n.tag == .record) .record else .nominal, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    fn fromEvidenceDepth(self: *Store, view: evidence.View, id: evidence.Id, depth: usize, budget: *usize) Error!Id {
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        if (id == 0 or id >= view.nodes.len) return error.UnresolvedType;
        const n = view.node(id);
        switch (n.tag) {
            .absent => return error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => return id,
            .array => return self.intern(.array, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .list => return self.intern(.list, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return self.intern(.resolver, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .provider => return self.internWithEffects(.provider, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .state_provider => return self.internStateProvider(try self.fromEvidenceDepth(view, n.a, depth + 1, budget), try self.fromEvidenceDepth(view, n.b, depth + 1, budget), try self.fromEvidenceDepth(view, n.c, depth + 1, budget)),
            .function => return self.internWithEffects(.function, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), try self.fromEvidenceDepth(view, n.b, depth + 1, budget), try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(allocator);
                for (view.children(id), 0..) |child, index| {
                    try values.append(allocator, if (n.tag == .record and index % 2 == 0) child else try self.fromEvidenceDepth(view, child, depth + 1, budget));
                }
                if (n.tag == .record) return self.internRecord(values.items);
                return self.intern(if (n.tag == .product) .product else .nominal, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    fn fromTypeDepth(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!Id {
        if (depth >= 1024) return error.LayoutLimit;
        for (mappings) |mapping| if (mapping.variable == ty) return mapping.layout;
        const n = module.types.node(ty);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => return ty,
            .variable => return if (allow_erased) erased else error.UnresolvedType,
            .absent => return error.UnresolvedType,
            .array => return self.intern(.array, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .list => return self.intern(.list, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return self.intern(.resolver, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .provider => return self.internWithEffects(.provider, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .state_provider => return self.internStateProvider(try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), try self.fromTypeDepth(module, n.b, mappings, rows, depth + 1, allow_erased), try self.fromTypeDepth(module, n.c, mappings, rows, depth + 1, allow_erased)),
            .function => return self.internWithEffects(.function, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), try self.fromTypeDepth(module, n.b, mappings, rows, depth + 1, allow_erased), try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
                const allocator = scratch.allocator();
                var values = try std.ArrayList(u32).initCapacity(allocator, 32);
                defer values.deinit(allocator);
                if (n.tag == .record) {
                    for (0..n.b) |i| {
                        const field = module.types.recordField(n, i);
                        try values.append(allocator, field.name);
                        try values.append(allocator, try self.fromTypeDepth(module, field.ty, mappings, rows, depth + 1, allow_erased));
                    }
                } else {
                    const children_ = if (n.tag == .nominal) module.types.nominalArguments(n) else module.types.list(.{ .start = n.a, .len = n.b });
                    for (children_) |child| try values.append(allocator, try self.fromTypeDepth(module, child, mappings, rows, depth + 1, allow_erased));
                }
                if (n.tag == .record) return self.internRecord(values.items);
                return self.intern(if (n.tag == .product) .product else .nominal, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    fn effectError(err: evidence.Effects.Error) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.TypeMismatch => error.TypeMismatch,
            error.EvidenceLimit => error.LayoutLimit,
        };
    }
    pub fn rowToEvidence(self: *const Store, target: *evidence.Store, row: evidence.Effects.Id) evidence.Error!evidence.Effects.Id {
        var budget: usize = 1_000_000;
        return self.toEvidenceRow(target, row, 0, &budget);
    }
    pub fn rowFromEvidence(self: *Store, view: evidence.View, row: evidence.Effects.Id) Error!evidence.Effects.Id {
        var budget: usize = 1_000_000;
        return self.fromEvidenceRow(view, row, 0, &budget);
    }
    fn toEvidenceRow(self: *const Store, target: *evidence.Store, row: evidence.Effects.Id, depth: usize, budget: *usize) evidence.Error!evidence.Effects.Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        if (row == unknown_row) return error.UnresolvedType;
        budget.* -= 1;
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(target.allocator);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(target.allocator);
        for (self.effects.view().rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (self.effects.view().operationArguments(label)) |argument| try arguments.append(target.allocator, try self.toEvidenceDepth(target, argument, depth + 1, budget));
            try labels.append(target.allocator, try target.effects.internOperation(self.effects.view().operation(label).identity, arguments.items));
        }
        return target.effects.internRow(labels.items);
    }
    fn fromEvidenceRow(self: *Store, view: evidence.View, row: evidence.Effects.Id, depth: usize, budget: *usize) Error!evidence.Effects.Id {
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(self.allocator);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(self.allocator);
        for (view.effects.rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (view.effects.operationArguments(label)) |argument| try arguments.append(self.allocator, try self.fromEvidenceDepth(view, argument, depth + 1, budget));
            const mapped = self.effects.internOperation(view.effects.operation(label).identity, arguments.items) catch |err| return effectError(err);
            try labels.append(self.allocator, mapped);
        }
        return self.effects.internRow(labels.items) catch |err| return effectError(err);
    }
    fn fromTypeRow(self: *Store, module: *const core.Module, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!evidence.Effects.Id {
        if (depth >= 1024) return error.LayoutLimit;
        const tail = module.types.row(row).tail;
        var suffix: evidence.Effects.Id = 0;
        switch (tail) {
            .closed => {},
            .parameter => return if (allow_erased) unknown_row else error.UnresolvedType,
            .variable => |variable| {
                var found = false;
                for (rows) |mapping| if (mapping.variable == variable) {
                    if (mapping.row >= self.effects.rows.items.len) return error.TypeMismatch;
                    suffix = mapping.row;
                    found = true;
                    break;
                };
                if (!found) return if (allow_erased) unknown_row else error.UnresolvedType;
            },
        }
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(self.allocator);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(self.allocator);
        for (module.types.rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (module.types.operationArguments(label)) |argument| try arguments.append(self.allocator, try self.fromTypeDepth(module, argument, mappings, rows, depth + 1, allow_erased));
            const mapped = self.effects.internOperation(module.types.operation(label).identity, arguments.items) catch |err| return effectError(err);
            try labels.append(self.allocator, mapped);
        }
        try labels.appendSlice(self.allocator, self.effects.view().rowLabels(suffix));
        return self.effects.internRow(labels.items) catch |err| return effectError(err);
    }
};

test "semantic projection ignores record slots but preserves phantom identity" {
    const allocator = std.testing.allocator;
    var layouts = try Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    const first = try layouts.intern(.record, 0, 0, &.{ 100, types.u32_type, 10, types.f32_type });
    const reordered = try layouts.intern(.record, 0, 0, &.{ 10, types.f32_type, 100, types.u32_type });
    try std.testing.expect(first != reordered);
    try std.testing.expectEqual(try layouts.toEvidence(&semantic, first), try layouts.toEvidence(&semantic, reordered));
    const integer = try layouts.intern(.nominal, 1, 42, &.{types.u32_type});
    const float = try layouts.intern(.nominal, 1, 42, &.{types.f32_type});
    const imported = try layouts.intern(.nominal, 2, 42, &.{types.u32_type});
    try std.testing.expect(try layouts.toEvidence(&semantic, integer) != try layouts.toEvidence(&semantic, float));
    try std.testing.expect(try layouts.toEvidence(&semantic, integer) != try layouts.toEvidence(&semantic, imported));
    const restored = try layouts.fromEvidence(semantic.view(), try layouts.toEvidence(&semantic, first));
    try std.testing.expectEqual(reordered, restored);
}

test "erased code representations never become concrete semantic evidence" {
    var layouts = try Store.init(std.testing.allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(std.testing.allocator);
    defer semantic.deinit();
    var partial = try code_expectation.Store.init(std.testing.allocator);
    defer partial.deinit();
    const nominal = try layouts.intern(.nominal, 1, 42, &.{erased});
    const function = try layouts.intern(.function, erased, nominal, &.{});
    try std.testing.expectEqual(wasm.ValueType.i32, layouts.machine(erased));
    try std.testing.expectEqual(@as(?wasm.Scalar, null), layouts.abi(erased));
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, nominal));
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, function));
    const expected = try layouts.toCodeExpectation(&partial, function);
    try std.testing.expectEqual(@as(u32, 0), partial.view().node(expected).a);
    try std.testing.expectEqualSlices(u32, &.{0}, partial.view().children(partial.view().node(expected).b));
    try std.testing.expectEqual(@as(usize, 6), semantic.nodes.items.len);
}

test "unresolved latent effects retain representation without asserting purity" {
    var layouts = try Store.init(std.testing.allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(std.testing.allocator);
    defer semantic.deinit();
    var partial = try code_expectation.Store.init(std.testing.allocator);
    defer partial.deinit();
    const demand = try layouts.internWithEffects(.demand, types.u32_type, 0, unknown_row, &.{});
    const function = try layouts.internWithEffects(.function, types.unit, demand, unknown_row, &.{});
    const pure_demand = try layouts.intern(.demand, types.u32_type, 0, &.{});
    try std.testing.expect(demand != pure_demand);
    try std.testing.expectEqual(wasm.ValueType.i32, layouts.machine(demand));
    try std.testing.expectEqual(@as(?wasm.Scalar, null), layouts.abi(demand));
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, demand));
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, function));
    try std.testing.expectError(error.UnresolvedType, layouts.rowToEvidence(&semantic, unknown_row));
    const expectation = try layouts.toCodeExpectation(&partial, function);
    try std.testing.expectEqual(code_expectation.Tag.function, partial.view().node(expectation).tag);
    try std.testing.expectEqual(code_expectation.Tag.demand, partial.view().node(partial.view().node(expectation).b).tag);
    try std.testing.expectEqual(@as(usize, 6), semantic.nodes.items.len);
}

fn effectLayoutScenario(allocator: Allocator) !void {
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    const phantom = try semantic.intern(.nominal, 3, 9, &.{types.f32_type});
    const operation = try semantic.effects.internOperation(.{ .unit = 2, .decl = 8 }, &.{phantom});
    const row = try semantic.effects.internRow(&.{ operation, operation });
    const demand = try semantic.internWithEffects(.demand, types.u32_type, 0, row, &.{});
    const function = try semantic.internWithEffects(.function, demand, types.u32_type, row, &.{});
    var layouts = try Store.init(allocator);
    defer layouts.deinit();
    _ = try layouts.intern(.record, 0, 0, &.{ 100, types.boolean });
    const layout = try layouts.fromEvidence(semantic.view(), function);
    try std.testing.expectEqual(layouts.node(layout).c, layouts.node(layouts.node(layout).a).c);
    try std.testing.expect(layout != try layouts.intern(.function, layouts.node(layout).a, types.u32_type, &.{}));
    try std.testing.expectEqual(function, try layouts.toEvidence(&semantic, layout));
    const mapped_operation = layouts.effects.view().rowLabels(layouts.node(layout).c)[0];
    const mapped_argument = layouts.effects.view().operationArguments(mapped_operation)[0];
    try std.testing.expectEqualSlices(u32, &.{types.f32_type}, layouts.children(mapped_argument));
    var partial = try code_expectation.Store.init(allocator);
    defer partial.deinit();
    const expectation = try layouts.toCodeExpectation(&partial, layout);
    // Representation expectations omit effects intentionally; their importer
    // supplies a fresh row rather than constraining source semantics to pure.
    try std.testing.expectEqual(@as(u32, 0), partial.view().node(expectation).c);
    const read_type = try semantic.intern(.nominal, 2, 8, &.{phantom});
    const write_type = try semantic.intern(.nominal, 2, 10, &.{phantom});
    const provider = try semantic.internWithEffects(.provider, read_type, 0, row, &.{});
    const provider_layout = try layouts.fromEvidence(semantic.view(), provider);
    try std.testing.expectEqual(provider, try layouts.toEvidence(&semantic, provider_layout));
    try std.testing.expect(provider_layout != try layouts.intern(.provider, layouts.node(provider_layout).a, 0, &.{}));
    const state = try semantic.internStateProvider(read_type, write_type, phantom);
    const state_layout = try layouts.fromEvidence(semantic.view(), state);
    try std.testing.expectEqual(state, try layouts.toEvidence(&semantic, state_layout));
    const state_expectation = try layouts.toCodeExpectation(&partial, state_layout);
    try std.testing.expectEqual(code_expectation.Tag.nominal, partial.view().node(partial.view().node(state_expectation).c).tag);
    try std.testing.expectEqual(@as(?wasm.Scalar, null), layouts.abi(state_layout));
    const unresolved_provider = try layouts.internWithEffects(.provider, layouts.node(provider_layout).a, 0, unknown_row, &.{});
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, unresolved_provider));
}
test "layout cache identity and semantic conversion preserve exact closed effect rows" {
    try effectLayoutScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectLayoutScenario, .{});
}
