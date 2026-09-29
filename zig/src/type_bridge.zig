//! Migration boundary: legacy compiler values enter once and leave lazily.
//! All traversal and rebuilding runs on type_ir IDs. Caches are Context-local,
//! never shared between workers or retained after their request arena expires.
const std = @import("std");
const ir = @import("type_ir.zig");
const r = @import("runtime.zig");
const V = r.Value;
const Allocator = std.mem.Allocator;

pub const State = struct {
    store: ir.Store,
    types: std.AutoHashMapUnmanaged(V, ir.Type) = .empty,
    rows: std.AutoHashMapUnmanaged(V, ir.Row) = .empty,
    names: std.AutoHashMapUnmanaged(V, ir.Name) = .empty,
    symbols: std.AutoHashMapUnmanaged(V, ir.Symbol) = .empty,
    type_values: std.ArrayList(V) = .empty,
    row_values: std.ArrayList(V) = .empty,
    name_values: std.ArrayList(V) = .empty,
    symbol_values: std.ArrayList(V) = .empty,
    exported: usize = 0,
    import_pending: std.ArrayList(Import) = .empty,
    import_active: std.AutoHashMapUnmanaged(V, void) = .empty,
    import_children: std.ArrayList(ir.Type) = .empty,
    import_labels: std.ArrayList(u32) = .empty,
    import_bytes: std.ArrayList(u8) = .empty,
    import_list: std.ArrayList(ir.Type) = .empty,
    pub fn init(allocator: Allocator) State {
        return .{ .store = ir.Store.init(allocator) };
    }
    pub fn deinit(self: *State) void {
        const a = self.store.allocator;
        self.types.deinit(a);
        self.rows.deinit(a);
        self.names.deinit(a);
        self.symbols.deinit(a);
        self.type_values.deinit(a);
        self.row_values.deinit(a);
        self.name_values.deinit(a);
        self.symbol_values.deinit(a);
        self.import_pending.deinit(a);
        self.import_active.deinit(a);
        self.import_children.deinit(a);
        self.import_labels.deinit(a);
        self.import_bytes.deinit(a);
        self.import_list.deinit(a);
        self.store.deinit();
    }
    fn grow(self: *State, values: *std.ArrayList(V), n: usize) ir.Error!void {
        if (values.items.len >= n) return;
        const old = values.items.len;
        try values.resize(self.store.allocator, n);
        @memset(values.items[old..], 0);
    }
    fn importSymbol(self: *State, raw: V) ir.Error!ir.Symbol {
        if (self.symbols.get(raw)) |id| return id;
        const bytes = &self.import_bytes;
        bytes.clearRetainingCapacity();
        var cursor = raw;
        while (r.tag(cursor) == .SCon) : (cursor = r.field(cursor, 1)) {
            var encoded: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(@intCast(r.field(cursor, 0) & r.mask), &encoded) catch return error.InvalidType;
            try bytes.appendSlice(self.store.allocator, encoded[0..n]);
        }
        if (r.tag(cursor) != .SNil) return error.InvalidType;
        const id = try self.store.symbol(bytes.items);
        try self.grow(&self.symbol_values, self.store.symbols.items.len);
        try self.symbols.put(self.store.allocator, raw, id);
        self.symbol_values.items[@intFromEnum(id)] = raw;
        return id;
    }
    fn importName(self: *State, raw: V) ir.Error!ir.Name {
        if (self.names.get(raw)) |id| return id;
        if (r.tag(raw) != .model_TypeId) return error.InvalidType;
        const id = try self.store.name(.{ .module = try self.importSymbol(r.field(raw, 0)), .declaration = try self.importSymbol(r.field(raw, 1)) });
        try self.grow(&self.name_values, self.store.names.items.len);
        try self.names.put(self.store.allocator, raw, id);
        self.name_values.items[@intFromEnum(id)] = raw;
        return id;
    }
    pub fn importRow(self: *State, raw: V) ir.Error!ir.Row {
        if (self.rows.get(raw)) |id| return id;
        if (r.tag(raw) != .model_EffectRow) return error.InvalidType;
        const tail = r.field(raw, 1);
        const t: ir.Tail = switch (r.tag(tail)) {
            .model_ClosedRow => .{ .tag = .closed },
            .model_RowVariable => ir.Tail.indexed(.variable, r.toNat(r.field(tail, 0))),
            .model_RowParameter => ir.Tail.indexed(.parameter, r.toNat(r.field(tail, 0))),
            .model_FreeRow => .{ .tag = .free, .a = @intFromEnum(try self.importSymbol(r.field(tail, 0))), .b = @intFromEnum(try self.importSymbol(r.field(tail, 1))) },
            else => return error.InvalidType,
        };
        const labels = &self.import_labels;
        labels.clearRetainingCapacity();
        var cursor = r.field(raw, 0);
        while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) try labels.append(self.store.allocator, @intFromEnum(try self.importName(r.field(cursor, 0))));
        if (r.tag(cursor) != .Nil) return error.InvalidType;
        const id = try self.store.effect(labels.items, t);
        try self.grow(&self.row_values, self.store.rows.items.len);
        try self.rows.put(self.store.allocator, raw, id);
        self.row_values.items[@intFromEnum(id)] = raw;
        return id;
    }
    fn known(self: *State, raw: V) ir.Error!u32 {
        return @intFromEnum(self.types.get(raw) orelse return error.InvalidType);
    }
    const Import = struct { raw: V, finish: bool = false };
    /// Postorder import preserves DAG sharing and does not use the native stack
    /// for nesting. Child IDs are always smaller than a newly inserted parent.
    pub fn importType(self: *State, raw: V) ir.Error!ir.Type {
        if (self.types.get(raw)) |id| return id;
        const a = self.store.allocator;
        const pending = &self.import_pending;
        const active = &self.import_active;
        const children = &self.import_children;
        pending.clearRetainingCapacity();
        active.clearRetainingCapacity();
        children.clearRetainingCapacity();
        try pending.append(a, .{ .raw = raw });
        while (pending.pop()) |work| {
            if (self.types.contains(work.raw)) continue;
            const value = work.raw;
            const tag = r.tag(value);
            if (!work.finish) {
                const entry = try active.getOrPut(a, value);
                if (entry.found_existing) return error.InvalidType;
                try pending.append(a, .{ .raw = value, .finish = true });
                switch (tag) {
                    .model_FunctionTy => {
                        try pending.append(a, .{ .raw = r.field(value, 1) });
                        try pending.append(a, .{ .raw = r.field(value, 0) });
                    },
                    .model_ArrayTy => try pending.append(a, .{ .raw = r.field(value, 0) }),
                    .model_StateProviderTy => try pending.append(a, .{ .raw = r.field(value, 2) }),
                    .model_AppliedTy, .model_ProductTy => {
                        var cursor = r.field(value, if (tag == .model_AppliedTy) 1 else 0);
                        while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) try pending.append(a, .{ .raw = r.field(cursor, 0) });
                        if (r.tag(cursor) != .Nil) return error.InvalidType;
                    },
                    else => {},
                }
                continue;
            }
            _ = active.remove(value);
            var n: ir.Node = undefined;
            const id: ir.Type = switch (tag) {
                .model_VariableTy => try self.store.indexed(.variable, r.toNat(r.field(value, 0))),
                .model_ParameterTy => try self.store.indexed(.parameter, r.toNat(r.field(value, 0))),
                .model_ProductTy, .model_AppliedTy => blk: {
                    children.clearRetainingCapacity();
                    var cursor = r.field(value, if (tag == .model_AppliedTy) 1 else 0);
                    while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) try children.append(a, @enumFromInt(try self.known(r.field(cursor, 0))));
                    const identity: ir.Name = if (tag == .model_AppliedTy) try self.importName(r.field(value, 0)) else @enumFromInt(0);
                    break :blk try self.store.listType(if (tag == .model_AppliedTy) .applied else .product, identity, children.items);
                },
                else => blk: {
                    n = switch (tag) {
                        .model_UnitTy => .{ .tag = .unit },
                        .model_U32Ty => .{ .tag = .u32_type },
                        .model_BoolTy => .{ .tag = .boolean },
                        .model_NeverTy => .{ .tag = .never },
                        .model_F32Ty => .{ .tag = .f32_type },
                        .model_EffectDescriptorTy => .{ .tag = .effect_descriptor },
                        .model_EffectSetTy => .{ .tag = .effect_set },
                        .model_FreeTy => .{ .tag = .free, .a = @intFromEnum(try self.importSymbol(r.field(value, 0))), .b = @intFromEnum(try self.importSymbol(r.field(value, 1))) },
                        .model_ArrayTy => .{ .tag = .array, .a = try self.known(r.field(value, 0)) },
                        .model_FunctionTy => .{ .tag = .function, .a = try self.known(r.field(value, 0)), .b = try self.known(r.field(value, 1)), .c = @intFromEnum(try self.importRow(r.field(value, 2))) },
                        .model_StateProviderTy => .{ .tag = .state_provider, .a = @intFromEnum(try self.importName(r.field(value, 0))), .b = @intFromEnum(try self.importName(r.field(value, 1))), .c = try self.known(r.field(value, 2)) },
                        .model_ProviderTy => .{ .tag = .provider, .a = @intFromEnum(try self.importName(r.field(value, 0))), .b = @intFromEnum(try self.importRow(r.field(value, 1))) },
                        else => return error.InvalidType,
                    };
                    break :blk try self.store.intern(n);
                },
            };
            try self.grow(&self.type_values, self.store.nodes.items.len);
            try self.types.put(a, value, id);
            self.type_values.items[@intFromEnum(id)] = value;
        }
        return self.types.get(raw) orelse error.InvalidType;
    }
    pub fn importList(self: *State, raw: V) ir.Error!ir.Span {
        const values = &self.import_list;
        values.clearRetainingCapacity();
        var cursor = raw;
        while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) try values.append(self.store.allocator, try self.importType(r.field(cursor, 0)));
        if (r.tag(cursor) != .Nil) return error.InvalidType;
        return self.store.span(ir.Type, values.items);
    }
    fn importWork(self: *State, raw: V) ir.Error!ir.Input {
        return switch (r.tag(raw)) {
            .types_OneType => .{ .one = try self.importType(r.field(raw, 0)) },
            .types_ManyTypes => .{ .many = try self.importList(r.field(raw, 0)) },
            else => error.InvalidType,
        };
    }
    fn symbolValue(self: *State, ctx: *r.Context, id: u32) ir.Error!V {
        try self.grow(&self.symbol_values, self.store.symbols.items.len);
        if (self.symbol_values.items[id] == 0) self.symbol_values.items[id] = ctx.string(self.store.symbols.items[id]);
        return self.symbol_values.items[id];
    }
    fn nameValue(self: *State, ctx: *r.Context, id: u32) ir.Error!V {
        try self.grow(&self.name_values, self.store.names.items.len);
        if (self.name_values.items[id] == 0) {
            const n = self.store.names.items[id];
            self.name_values.items[id] = ctx.node(.model_TypeId, &.{ try self.symbolValue(ctx, @intFromEnum(n.module)), try self.symbolValue(ctx, @intFromEnum(n.declaration)) });
        }
        return self.name_values.items[id];
    }
    pub fn rowValue(self: *State, ctx: *r.Context, id: ir.Row) ir.Error!V {
        try self.grow(&self.row_values, self.store.rows.items.len);
        const i = @intFromEnum(id);
        if (self.row_values.items[i] != 0) return self.row_values.items[i];
        const n = self.store.row(id);
        const tail = switch (n.tail.tag) {
            .closed => r.empty(.model_ClosedRow),
            .variable => ctx.node(.model_RowVariable, &.{r.nat(n.tail.index())}),
            .parameter => ctx.node(.model_RowParameter, &.{r.nat(n.tail.index())}),
            .free => ctx.node(.model_FreeRow, &.{ try self.symbolValue(ctx, n.tail.a), try self.symbolValue(ctx, n.tail.b) }),
        };
        var labels = r.empty(.Nil);
        var count: usize = n.labels.len;
        while (count > 0) {
            count -= 1;
            labels = ctx.node(.Cons, &.{ try self.nameValue(ctx, self.store.extra.items[n.labels.start + count]), labels });
        }
        const value = ctx.node(.model_EffectRow, &.{ labels, tail });
        self.row_values.items[i] = value;
        try self.rows.put(self.store.allocator, value, id);
        return value;
    }
    fn childValue(self: *State, id: u32) V {
        const value = self.type_values.items[id];
        std.debug.assert(value != 0);
        return value;
    }
    pub fn typeValue(self: *State, ctx: *r.Context, id: ir.Type) ir.Error!V {
        try self.grow(&self.type_values, self.store.nodes.items.len);
        const target = @intFromEnum(id);
        if (self.type_values.items[target] != 0) return self.type_values.items[target];
        // Nodes are postordered. Each output node is materialized at most once;
        // the watermark avoids rescanning a growing prefix on every export.
        while (self.exported <= target) : (self.exported += 1) {
            const i = self.exported;
            if (self.type_values.items[i] != 0) continue;
            const n = self.store.nodes.items[i];
            const value = switch (n.tag) {
                .unit => r.empty(.model_UnitTy),
                .u32_type => r.empty(.model_U32Ty),
                .boolean => r.empty(.model_BoolTy),
                .never => r.empty(.model_NeverTy),
                .f32_type => r.empty(.model_F32Ty),
                .effect_descriptor => r.empty(.model_EffectDescriptorTy),
                .effect_set => r.empty(.model_EffectSetTy),
                .variable => ctx.node(.model_VariableTy, &.{r.nat(n.index())}),
                .parameter => ctx.node(.model_ParameterTy, &.{r.nat(n.index())}),
                .free => ctx.node(.model_FreeTy, &.{ try self.symbolValue(ctx, n.a), try self.symbolValue(ctx, n.b) }),
                .array => ctx.node(.model_ArrayTy, &.{self.childValue(n.a)}),
                .function => ctx.node(.model_FunctionTy, &.{ self.childValue(n.a), self.childValue(n.b), try self.rowValue(ctx, @enumFromInt(n.c)) }),
                .provider => ctx.node(.model_ProviderTy, &.{ try self.nameValue(ctx, n.a), try self.rowValue(ctx, @enumFromInt(n.b)) }),
                .state_provider => ctx.node(.model_StateProviderTy, &.{ try self.nameValue(ctx, n.a), try self.nameValue(ctx, n.b), self.childValue(n.c) }),
                .applied, .product => blk: {
                    const s = n.children().?;
                    var count: usize = s.len;
                    var values = r.empty(.Nil);
                    while (count > 0) {
                        count -= 1;
                        values = ctx.node(.Cons, &.{ self.childValue(self.store.extra.items[s.start + count]), values });
                    }
                    break :blk if (n.tag == .product) ctx.node(.model_ProductTy, &.{values}) else ctx.node(.model_AppliedTy, &.{ try self.nameValue(ctx, n.a), values });
                },
            };
            self.type_values.items[i] = value;
            try self.types.put(self.store.allocator, value, @enumFromInt(i));
        }
        return self.type_values.items[target];
    }
    fn output(self: *State, ctx: *r.Context, values: []const ir.Type) ir.Error!V {
        var result = r.empty(.Nil);
        var i = values.len;
        while (i > 0) {
            i -= 1;
            result = ctx.node(.Cons, &.{ try self.typeValue(ctx, values[i]), result });
        }
        return ctx.node(.Done, &.{result});
    }
};

fn state(ctx: *r.Context) ir.Error!*State {
    if (ctx.type_state) |s| return s;
    const s = try ctx.arena.allocator().create(State);
    s.* = State.init(ctx.arena.child_allocator);
    ctx.type_state = s;
    return s;
}
fn failure(ctx: *r.Context, err: ir.Error) V {
    const diagnostic = switch (err) {
        error.OutOfMemory => @panic("Zig compiler ran out of memory"),
        error.TypeComplexity, error.IRTooLarge => ctx.node(.model_Diagnostic, &.{ r.literal("type_complexity"), r.literal("inference"), r.literal("type traversal exceeded the 65536-node nesting/width limit") }),
        error.ChronologyBound => ctx.node(.model_Diagnostic, &.{ r.literal("internal_error"), r.literal("substitution"), r.literal("indexed substitution exceeded its chronological bound") }),
        error.KindMismatch => ctx.node(.model_Diagnostic, &.{ r.literal("kind_mismatch"), r.literal("inference"), r.literal("an effect row variable cannot be replaced by a value type") }),
        error.InvalidType => ctx.node(.model_Diagnostic, &.{ r.literal("internal_error"), r.literal("inference"), r.literal("type rewrite did not produce exactly one type") }),
    };
    return ctx.node(.Fail, &.{diagnostic});
}
fn lookup(root: V, key: u64) ?V {
    var current = root;
    var remaining: usize = 49;
    while (remaining != 0) : (remaining -= 1) switch (r.tag(current)) {
        .nat_index_Empty => return null,
        .nat_index_Leaf => return if (r.toNat(r.field(current, 0)) == key) r.field(current, 1) else null,
        .nat_index_Branch => {
            const mask = r.toNat(r.field(current, 1));
            if (((key ^ r.toNat(r.field(current, 0))) & ~((mask << 1) - 1)) != 0) return null;
            current = r.field(current, if (key & mask == 0) 2 else 3);
        },
        else => return null,
    };
    return null;
}
const View = struct {
    ctx: *r.Context,
    substitutions: V,
    fn version(self: *@This(), comptime field: usize, variable: u64, cursor: u64) ?V {
        var versions = lookup(r.field(self.substitutions, field), variable) orelse return null;
        var found: ?V = null;
        while (r.tag(versions) == .Cons) : (versions = r.field(versions, 1)) {
            const candidate = r.field(versions, 0);
            if (r.toNat(r.field(candidate, 0)) >= cursor) found = candidate;
        }
        return found;
    }
    fn value(raw: *anyopaque, variable: u64, cursor: u64) ir.Error!?ir.Version {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const v = self.version(1, variable, cursor) orelse return null;
        return .{ .position = r.toNat(r.field(v, 0)), .replacement = try (try state(self.ctx)).importType(r.field(v, 1)) };
    }
    fn row(raw: *anyopaque, variable: u64, cursor: u64) ir.Error!?ir.RowVersion {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const v = self.version(2, variable, cursor) orelse return null;
        return .{ .position = r.toNat(r.field(v, 0)), .replacement = try (try state(self.ctx)).importRow(r.field(v, 1)) };
    }
    fn bindings(self: *@This()) ir.Bindings {
        return .{ .data = self, .identity = self.substitutions, .count = r.toNat(r.field(self.substitutions, 3)), .value = value, .row = row };
    }
};
const MapView = struct {
    root: V,
    fn find(raw: *anyopaque, variable: u64) ?u64 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        return if (lookup(self.root, variable)) |v| r.toNat(v) else null;
    }
    fn mapping(self: *@This()) ir.Mapping {
        return .{ .data = self, .find = find };
    }
};
fn workResult(ctx: *r.Context, substitutions: V, fuel: u64, work: V) ir.Error!V {
    if (r.toNat(r.field(substitutions, 3)) == 0) return ctx.node(.Done, &.{if (r.tag(work) == .types_OneType) ctx.node(.Cons, &.{ r.field(work, 0), r.empty(.Nil) }) else r.field(work, 0)});
    if (fuel == 0) return error.TypeComplexity;
    const s = try state(ctx);
    const input = try s.importWork(work);
    var view: View = .{ .ctx = ctx, .substitutions = substitutions };
    return s.output(ctx, try s.store.transform(input, fuel, .{ .resolve = view.bindings() }));
}
pub fn resolveWork(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 3);
    return workResult(ctx, args[0], r.toNat(args[1]), args[2]) catch |err| failure(ctx, err);
}
fn typeResult(ctx: *r.Context, substitutions: V, ty: V) ir.Error!V {
    if (r.toNat(r.field(substitutions, 3)) == 0) return ctx.node(.Done, &.{ty});
    // Preserve allocation-free ground leaf paths before initializing the IR.
    switch (r.tag(ty)) {
        .model_UnitTy, .model_U32Ty, .model_BoolTy, .model_NeverTy, .model_F32Ty, .model_EffectDescriptorTy, .model_EffectSetTy, .model_ParameterTy, .model_FreeTy => return ctx.node(.Done, &.{ty}),
        else => {},
    }
    const s = try state(ctx);
    const id = try s.importType(ty);
    var view: View = .{ .ctx = ctx, .substitutions = substitutions };
    const result = (try s.store.transform(.{ .one = id }, 65536, .{ .resolve = view.bindings() }))[0];
    return ctx.node(.Done, &.{try s.typeValue(ctx, result)});
}
pub fn resolveType(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 2);
    return typeResult(ctx, args[0], args[1]) catch |err| failure(ctx, err);
}
fn rowResult(ctx: *r.Context, args: []const V) ir.Error!V {
    if (r.toNat(r.field(args[0], 3)) == 0) return args[1];
    const s = try state(ctx);
    const row = try s.importRow(args[1]);
    var view: View = .{ .ctx = ctx, .substitutions = args[0] };
    const result = try s.store.resolveRow(row, view.bindings(), r.toNat(args[2]));
    return s.rowValue(ctx, result);
}
pub fn resolveRowAt(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 3);
    // This internal entry point returns a row, not Result<Row>. Never leak a
    // diagnostic Result into an unchecked row field on an allocation failure.
    return rowResult(ctx, args) catch |err| switch (err) {
        error.OutOfMemory => @panic("Zig compiler ran out of memory"),
        else => @panic("invalid internal type IR row"),
    };
}
fn replacement(s: *State, raw: V, map: *MapView) ir.Error!ir.Replacement {
    return switch (r.tag(raw)) {
        .types_ReplaceVariable => .{ .variable = .{ .index = r.toNat(r.field(raw, 0)), .value = try s.importType(r.field(raw, 1)) } },
        .types_ReplaceParameter => .{ .parameter = .{ .index = r.toNat(r.field(raw, 0)), .value = try s.importType(r.field(raw, 1)) } },
        .types_FreshParameters => blk: {
            map.root = r.field(raw, 0);
            break :blk .{ .fresh_parameters = map.mapping() };
        },
        .types_ReplaceFree => .{ .free = .{ .scope = try s.importSymbol(r.field(raw, 0)), .name = try s.importSymbol(r.field(raw, 1)), .value = try s.importType(r.field(raw, 2)) } },
        .types_RelocateFree => .{ .relocate = try s.importSymbol(r.field(raw, 0)) },
        else => error.InvalidType,
    };
}
fn rewriteResult(ctx: *r.Context, args: []const V, is_renaming: bool) ir.Error!V {
    const fuel = r.toNat(args[0]);
    if (fuel == 0) return error.TypeComplexity;
    const s = try state(ctx);
    var map: MapView = .{ .root = args[2] };
    const op: ir.Replacement = if (!is_renaming) try replacement(s, args[2], &map) else if (r.tag(args[3]) == .types_FreshVariables) .{ .rename_variables = map.mapping() } else .{ .parameterize_variables = map.mapping() };
    const input = try s.importWork(args[1]);
    return s.output(ctx, try s.store.transform(input, fuel, .{ .rewrite = op }));
}
pub fn rewrite(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 3);
    return rewriteResult(ctx, args, false) catch |err| failure(ctx, err);
}
pub fn rename(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len == 4);
    return rewriteResult(ctx, args, true) catch |err| failure(ctx, err);
}
