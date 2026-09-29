//! Compact immutable type/effect IR, independent of the generated compiler.
//! IDs survive array growth. Interning compares full keys, not just hashes.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Type = enum(u32) { _ };
pub const Row = enum(u32) { _ };
pub const Symbol = enum(u32) { _ };
pub const Name = enum(u32) { _ };
pub const Span = struct { start: u32, len: u32 };
pub const Nominal = struct { module: Symbol, declaration: Symbol };
pub const Tag = enum(u32) {
    unit,
    u32_type,
    boolean,
    never,
    f32_type,
    effect_descriptor,
    effect_set,
    variable,
    parameter,
    free,
    array,
    product,
    applied,
    function,
    provider,
    state_provider,
};
pub const TailTag = enum(u32) { closed, variable, parameter, free };
pub const Tail = struct {
    tag: TailTag,
    a: u32 = 0,
    b: u32 = 0,
    pub fn indexed(tag: TailTag, variable: u64) Tail {
        std.debug.assert(tag == .variable or tag == .parameter);
        return .{ .tag = tag, .a = @truncate(variable), .b = @intCast(variable >> 32) };
    }
    pub fn index(self: Tail) u64 {
        return @as(u64, self.a) | (@as(u64, self.b) << 32);
    }
};
pub const EffectRow = struct { labels: Span, tail: Tail };
/// 16 bytes per type node; split payload words retain all Nat48 identity bits.
pub const Node = struct {
    tag: Tag,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
    pub fn index(self: Node) u64 {
        return @as(u64, self.a) | (@as(u64, self.b) << 32);
    }
    pub fn children(self: Node) ?Span {
        return switch (self.tag) {
            .product => .{ .start = self.a, .len = self.b },
            .applied => .{ .start = self.b, .len = self.c },
            else => null,
        };
    }
};
comptime {
    std.debug.assert(@sizeOf(Node) == 16);
}
/// Cached traversal facts cost eight bytes per interned node. They permit
/// constant-time no-op checks without hiding the original complexity bound.
const Facts = packed struct(u64) {
    minimum_fuel: u61 = 1,
    variables: bool = false,
    parameters: bool = false,
    free_names: bool = false,
    fn merge(self: *Facts, other: Facts) void {
        self.variables = self.variables or other.variables;
        self.parameters = self.parameters or other.parameters;
        self.free_names = self.free_names or other.free_names;
    }
    fn affected(self: Facts, op: Operation) bool {
        return switch (op) {
            .resolve => self.variables,
            .rewrite => |rep| switch (rep) {
                .variable, .rename_variables, .parameterize_variables => self.variables,
                .parameter, .fresh_parameters => self.parameters,
                .free, .relocate => self.free_names,
            },
        };
    }
};
pub const Error = error{ OutOfMemory, IRTooLarge, InvalidType, TypeComplexity, ChronologyBound, KindMismatch };
pub const Version = struct { position: u64, replacement: Type };
pub const RowVersion = struct { position: u64, replacement: Row };
pub const Bindings = struct {
    data: *anyopaque,
    identity: u64,
    count: u64,
    value: *const fn (*anyopaque, u64, u64) Error!?Version,
    row: *const fn (*anyopaque, u64, u64) Error!?RowVersion,
};
pub const Mapping = struct { data: *anyopaque, find: *const fn (*anyopaque, u64) ?u64 };
pub const Replacement = union(enum) {
    variable: struct { index: u64, value: Type },
    parameter: struct { index: u64, value: Type },
    fresh_parameters: Mapping,
    free: struct { scope: Symbol, name: Symbol, value: Type },
    relocate: Symbol,
    rename_variables: Mapping,
    parameterize_variables: Mapping,
};
pub const Operation = union(enum) { resolve: Bindings, rewrite: Replacement };
pub const Input = union(enum) { one: Type, many: Span };
const Visit = struct { ty: Type, fuel: u64, cursor: u64, links: u64 };
const Work = union(enum) {
    visit: Visit,
    many: struct { span: Span, fuel: u64, cursor: u64, links: u64 },
    finish: struct { visit: Visit, start: usize },
    remember: Visit,
    check: bool,
};
const NodeContext = struct {
    extra: []const u32,
    pub fn hash(self: @This(), node: Node) u64 {
        var h = std.hash.Wyhash.init(0);
        std.hash.autoHash(&h, node.tag);
        if (node.children()) |s| {
            if (node.tag == .applied) std.hash.autoHash(&h, node.a);
            h.update(std.mem.sliceAsBytes(self.extra[s.start..][0..s.len]));
        } else {
            std.hash.autoHash(&h, node.a);
            std.hash.autoHash(&h, node.b);
            std.hash.autoHash(&h, node.c);
        }
        return h.final();
    }
    pub fn eql(self: @This(), a: Node, b: Node) bool {
        if (a.tag != b.tag) return false;
        if (a.children()) |x| {
            const y = b.children().?;
            return (a.tag != .applied or a.a == b.a) and
                std.mem.eql(u32, self.extra[x.start..][0..x.len], self.extra[y.start..][0..y.len]);
        }
        return a.a == b.a and a.b == b.b and a.c == b.c;
    }
};
const RowContext = struct {
    extra: []const u32,
    pub fn hash(self: @This(), row: EffectRow) u64 {
        var h = std.hash.Wyhash.init(0);
        std.hash.autoHash(&h, row.tail);
        h.update(std.mem.sliceAsBytes(self.extra[row.labels.start..][0..row.labels.len]));
        return h.final();
    }
    pub fn eql(self: @This(), a: EffectRow, b: EffectRow) bool {
        return std.meta.eql(a.tail, b.tail) and std.mem.eql(u32, self.extra[a.labels.start..][0..a.labels.len], self.extra[b.labels.start..][0..b.labels.len]);
    }
};

pub const Store = struct {
    allocator: Allocator,
    nodes: std.ArrayList(Node) = .empty,
    facts: std.ArrayList(Facts) = .empty,
    rows: std.ArrayList(EffectRow) = .empty,
    names: std.ArrayList(Nominal) = .empty,
    symbols: std.ArrayList([]const u8) = .empty,
    extra: std.ArrayList(u32) = .empty,
    node_index: std.HashMapUnmanaged(Node, Type, NodeContext, 80) = .empty,
    row_index: std.HashMapUnmanaged(EffectRow, Row, RowContext, 80) = .empty,
    name_index: std.AutoHashMapUnmanaged(Nominal, Name) = .empty,
    symbol_index: std.StringHashMapUnmanaged(Symbol) = .empty,
    resolved: std.AutoHashMapUnmanaged(Visit, Type) = .empty,
    snapshot: ?u64 = null,
    snapshot_count: u64 = 0,
    work: std.ArrayList(Work) = .empty,
    results: std.ArrayList(Type) = .empty,
    row_labels: std.ArrayList(u32) = .empty,
    visits: usize = 0,
    cache_hits: usize = 0,

    pub fn init(allocator: Allocator) Store {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Store) void {
        self.node_index.deinit(self.allocator);
        self.row_index.deinit(self.allocator);
        self.name_index.deinit(self.allocator);
        self.symbol_index.deinit(self.allocator);
        self.resolved.deinit(self.allocator);
        self.work.deinit(self.allocator);
        self.results.deinit(self.allocator);
        self.row_labels.deinit(self.allocator);
        for (self.symbols.items) |bytes| self.allocator.free(bytes);
        self.symbols.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.facts.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.* = undefined;
    }
    fn index(n: usize) Error!u32 {
        return std.math.cast(u32, n) orelse error.IRTooLarge;
    }
    pub fn node(self: *const Store, ty: Type) Node {
        return self.nodes.items[@intFromEnum(ty)];
    }
    pub fn row(self: *const Store, id: Row) EffectRow {
        return self.rows.items[@intFromEnum(id)];
    }
    pub fn items(self: *const Store, s: Span) []const u32 {
        return self.extra.items[s.start..][0..s.len];
    }
    pub fn symbol(self: *Store, bytes: []const u8) Error!Symbol {
        if (self.symbol_index.get(bytes)) |id| return id;
        const id: Symbol = @enumFromInt(try index(self.symbols.items.len));
        try self.symbols.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(owned);
        try self.symbol_index.put(self.allocator, owned, id);
        self.symbols.appendAssumeCapacity(owned);
        return id;
    }
    pub fn name(self: *Store, nominal: Nominal) Error!Name {
        const id: Name = @enumFromInt(try index(self.names.items.len));
        try self.names.ensureUnusedCapacity(self.allocator, 1);
        const entry = try self.name_index.getOrPut(self.allocator, nominal);
        if (entry.found_existing) return entry.value_ptr.*;
        entry.value_ptr.* = id;
        self.names.appendAssumeCapacity(nominal);
        return id;
    }
    fn rowFacts(self: *const Store, id: u32) Facts {
        return switch (self.rows.items[id].tail.tag) {
            .closed => .{},
            .variable => .{ .variables = true },
            .parameter => .{ .parameters = true },
            .free => .{ .free_names = true },
        };
    }
    fn nodeFacts(self: *const Store, n: Node) Facts {
        var f: Facts = .{};
        switch (n.tag) {
            .variable => f.variables = true,
            .parameter => f.parameters = true,
            .free => f.free_names = true,
            .array, .state_provider => {
                f = self.facts.items[if (n.tag == .array) n.a else n.c];
                f.minimum_fuel += 1;
            },
            .function => {
                f = self.facts.items[n.a];
                const b = self.facts.items[n.b];
                f.merge(b);
                f.merge(self.rowFacts(n.c));
                f.minimum_fuel = 1 + @max(f.minimum_fuel, b.minimum_fuel);
            },
            .provider => f = self.rowFacts(n.b),
            .product, .applied => {
                const span_value = n.children().?;
                // The parent, each list cell, and the empty list tail consume
                // fuel. An element sees the suffix-specific remaining budget.
                f.minimum_fuel = @as(u61, span_value.len) + 2;
                for (self.items(span_value), 0..) |child, i| {
                    const c = self.facts.items[child];
                    f.merge(c);
                    f.minimum_fuel = @max(f.minimum_fuel, c.minimum_fuel + @as(u61, @intCast(i)) + 2);
                }
            },
            else => {},
        }
        return f;
    }
    pub fn intern(self: *Store, n: Node) Error!Type {
        const id: Type = @enumFromInt(try index(self.nodes.items.len));
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.facts.ensureUnusedCapacity(self.allocator, 1);
        const entry = try self.node_index.getOrPutContext(self.allocator, n, .{ .extra = self.extra.items });
        if (entry.found_existing) return entry.value_ptr.*;
        entry.value_ptr.* = id;
        self.nodes.appendAssumeCapacity(n);
        self.facts.appendAssumeCapacity(self.nodeFacts(n));
        return id;
    }
    pub fn span(self: *Store, comptime T: type, values: []const T) Error!Span {
        const start = try index(self.extra.items.len);
        const len = try index(values.len);
        _ = std.math.add(u32, start, len) catch return error.IRTooLarge;
        comptime std.debug.assert(@sizeOf(T) == @sizeOf(u32));
        // A row rewrite may append a range already stored in extra. Preserve
        // its offset across growth instead of allocating a temporary copy.
        const base = @intFromPtr(self.extra.items.ptr);
        const address = @intFromPtr(values.ptr);
        const offset: ?usize = if (values.len > 0 and address >= base and
            address - base <= self.extra.items.len * @sizeOf(u32) and
            values.len <= (self.extra.items.len * @sizeOf(u32) - (address - base)) / @sizeOf(u32))
            (address - base) / @sizeOf(u32)
        else
            null;
        try self.extra.ensureUnusedCapacity(self.allocator, values.len);
        if (offset) |i| {
            self.extra.appendSliceAssumeCapacity(self.extra.items[i..][0..values.len]);
        } else {
            for (values) |v| self.extra.appendAssumeCapacity(if (T == u32) v else @intFromEnum(v));
        }
        return .{ .start = start, .len = len };
    }
    pub fn listType(self: *Store, tag: Tag, identity: Name, values: []const Type) Error!Type {
        std.debug.assert(tag == .applied or tag == .product);
        const old_len = self.extra.items.len;
        errdefer self.extra.shrinkRetainingCapacity(old_len);
        const s = try self.span(Type, values);
        const n: Node = if (tag == .product) .{ .tag = tag, .a = s.start, .b = s.len } else .{ .tag = tag, .a = @intFromEnum(identity), .b = s.start, .c = s.len };
        const old_count = self.nodes.items.len;
        const id = try self.intern(n);
        if (old_count == self.nodes.items.len) self.extra.shrinkRetainingCapacity(old_len);
        return id;
    }
    pub fn effect(self: *Store, labels: []const u32, tail: Tail) Error!Row {
        const id: Row = @enumFromInt(try index(self.rows.items.len));
        const old_len = self.extra.items.len;
        errdefer self.extra.shrinkRetainingCapacity(old_len);
        const n: EffectRow = .{ .labels = try self.span(u32, labels), .tail = tail };
        try self.rows.ensureUnusedCapacity(self.allocator, 1);
        const entry = try self.row_index.getOrPutContext(self.allocator, n, .{ .extra = self.extra.items });
        if (entry.found_existing) {
            self.extra.shrinkRetainingCapacity(old_len);
            return entry.value_ptr.*;
        }
        entry.value_ptr.* = id;
        self.rows.appendAssumeCapacity(n);
        return id;
    }
    pub fn indexed(self: *Store, tag: Tag, variable: u64) Error!Type {
        std.debug.assert(tag == .variable or tag == .parameter);
        return self.intern(.{ .tag = tag, .a = @truncate(variable), .b = @intCast(variable >> 32) });
    }
    fn relocate(self: *Store, scope: u32, suffix: Symbol) Error!u32 {
        const bytes = try std.mem.concat(self.allocator, u8, &.{ self.symbols.items[scope], self.symbols.items[@intFromEnum(suffix)] });
        defer self.allocator.free(bytes);
        return @intFromEnum(try self.symbol(bytes));
    }
    fn replacedLeaf(self: *Store, ty: Type, replacement: Replacement) Error!Type {
        const n = self.node(ty);
        switch (replacement) {
            .variable => |v| {
                if (n.tag == .variable and n.index() == v.index) return v.value;
            },
            .parameter => |v| {
                if (n.tag == .parameter and n.index() == v.index) return v.value;
            },
            .free => |v| {
                if (n.tag == .free and n.a == @intFromEnum(v.scope) and n.b == @intFromEnum(v.name)) return v.value;
            },
            .fresh_parameters => |m| {
                if (n.tag == .parameter) {
                    if (m.find(m.data, n.index())) |v| return self.indexed(.variable, v);
                }
            },
            .rename_variables, .parameterize_variables => |m| {
                if (n.tag == .variable) {
                    if (m.find(m.data, n.index())) |v| return self.indexed(if (replacement == .rename_variables) .variable else .parameter, v);
                }
            },
            .relocate => |s| {
                if (n.tag == .free) return self.intern(.{ .tag = .free, .a = try self.relocate(n.a, s), .b = n.b });
            },
        }
        return ty;
    }
    fn tailFromType(self: *Store, ty: Type) Error!Tail {
        const n = self.node(ty);
        return switch (n.tag) {
            .variable => Tail.indexed(.variable, n.index()),
            .parameter => Tail.indexed(.parameter, n.index()),
            else => error.KindMismatch,
        };
    }
    fn replacedTail(self: *Store, t: Tail, replacement: Replacement) Error!Tail {
        switch (replacement) {
            .variable => |v| {
                if (t.tag == .variable and t.index() == v.index) return self.tailFromType(v.value);
            },
            .parameter => |v| {
                if (t.tag == .parameter and t.index() == v.index) return self.tailFromType(v.value);
            },
            .free => |v| {
                if (t.tag == .free and t.a == @intFromEnum(v.scope) and t.b == @intFromEnum(v.name)) return self.tailFromType(v.value);
            },
            .fresh_parameters => |m| {
                if (t.tag == .parameter) {
                    if (m.find(m.data, t.index())) |v| return Tail.indexed(.variable, v);
                }
            },
            .rename_variables, .parameterize_variables => |m| {
                if (t.tag == .variable) {
                    if (m.find(m.data, t.index())) |v| return Tail.indexed(if (replacement == .rename_variables) .variable else .parameter, v);
                }
            },
            .relocate => |s| {
                if (t.tag == .free) return .{ .tag = .free, .a = try self.relocate(t.a, s), .b = t.b };
            },
        }
        return t;
    }
    pub fn rewriteRow(self: *Store, id: Row, replacement: Replacement) Error!Row {
        const n = self.row(id);
        const tail = try self.replacedTail(n.tail, replacement);
        if (std.meta.eql(n.tail, tail)) return id;
        return self.effect(self.items(n.labels), tail);
    }
    pub fn resolveRow(self: *Store, id: Row, bindings: Bindings, start: u64) Error!Row {
        var current = id;
        var cursor = start;
        var links = bindings.count;
        const labels = &self.row_labels;
        labels.clearRetainingCapacity();
        var changed = false;
        while (links != 0) : (links -= 1) {
            const n = self.row(current);
            if (n.tail.tag != .variable) break;
            const version = try bindings.row(bindings.data, n.tail.index(), cursor) orelse break;
            try labels.appendSlice(self.allocator, self.items(n.labels));
            current = version.replacement;
            cursor = (version.position + 1) & 0xffffffffffff;
            changed = true;
        }
        if (!changed) return id;
        const last = self.row(current);
        try labels.appendSlice(self.allocator, self.items(last.labels));
        return self.effect(labels.items, last.tail);
    }
    fn transformedRow(self: *Store, id: Row, op: Operation, cursor: u64) Error!Row {
        return switch (op) {
            .resolve => |b| self.resolveRow(id, b, cursor),
            .rewrite => |v| self.rewriteRow(id, v),
        };
    }
    fn remember(self: *Store, key: Visit, result: Type) Error!void {
        try self.resolved.put(self.allocator, key, result);
    }
    fn finish(self: *Store, v: Visit, start: usize, op: Operation) Error!void {
        var n = self.node(v.ty);
        const children = self.results.items[start..];
        switch (n.tag) {
            .array => n.a = @intFromEnum(children[0]),
            .state_provider => n.c = @intFromEnum(children[0]),
            .function => {
                n.a = @intFromEnum(children[0]);
                n.b = @intFromEnum(children[1]);
                n.c = @intFromEnum(try self.transformedRow(@enumFromInt(n.c), op, v.cursor));
            },
            .provider => n.b = @intFromEnum(try self.transformedRow(@enumFromInt(n.b), op, v.cursor)),
            .product, .applied => {
                const result = try self.listType(n.tag, @enumFromInt(n.a), children);
                self.results.shrinkRetainingCapacity(start);
                try self.results.append(self.allocator, result);
                try self.remember(v, result);
                return;
            },
            else => return error.InvalidType,
        }
        const result = try self.intern(n);
        self.results.shrinkRetainingCapacity(start);
        try self.results.append(self.allocator, result);
        try self.remember(v, result);
    }
    /// Iterative traversal with exact depth AND list-width fuel. The memo key
    /// includes cursor, links and fuel, preserving chronological suffixes.
    /// The returned slice is scratch storage until the next transform.
    pub fn transform(self: *Store, input: Input, fuel: u64, op: Operation) Error![]const Type {
        self.work.clearRetainingCapacity();
        self.results.clearRetainingCapacity();
        self.visits = 0;
        self.cache_hits = 0;
        var links: u64 = 0;
        if (op == .resolve) {
            const b = op.resolve;
            links = b.count;
            if (self.snapshot != b.identity or self.snapshot_count != b.count or self.resolved.count() > 131072) {
                self.resolved.clearRetainingCapacity();
                self.snapshot = b.identity;
                self.snapshot_count = b.count;
            }
        }
        if (op == .rewrite) {
            self.resolved.clearRetainingCapacity();
            self.snapshot = null;
        }
        switch (input) {
            .one => |ty| try self.work.append(self.allocator, .{ .visit = .{ .ty = ty, .fuel = fuel, .cursor = 0, .links = links } }),
            .many => |s| try self.work.append(self.allocator, .{ .many = .{ .span = s, .fuel = fuel, .cursor = 0, .links = links } }),
        }
        while (self.work.pop()) |work| switch (work) {
            .check => |ok| {
                if (!ok) return error.TypeComplexity;
            },
            .remember => |v| try self.remember(v, self.results.items[self.results.items.len - 1]),
            .finish => |f| try self.finish(f.visit, f.start, op),
            .many => |m| {
                if (op == .resolve and m.cursor >= op.resolve.count) {
                    for (self.items(m.span)) |id| try self.results.append(self.allocator, @enumFromInt(id));
                    continue;
                }
                if (m.fuel == 0) return error.TypeComplexity;
                try self.work.append(self.allocator, .{ .check = m.fuel > m.span.len });
                var i: usize = m.span.len;
                while (i > 0) {
                    i -= 1;
                    try self.work.append(self.allocator, .{ .visit = .{
                        .ty = @enumFromInt(self.extra.items[m.span.start + i]),
                        .fuel = m.fuel -| (i + 1),
                        .links = m.links,
                        .cursor = m.cursor,
                    } });
                }
            },
            .visit => |v| {
                if (op == .resolve and v.cursor >= op.resolve.count) {
                    try self.results.append(self.allocator, v.ty);
                    continue;
                }
                if (v.fuel == 0) return error.TypeComplexity;
                const facts = self.facts.items[@intFromEnum(v.ty)];
                if (!facts.affected(op)) {
                    if (v.fuel < facts.minimum_fuel) return error.TypeComplexity;
                    self.visits += 1;
                    try self.results.append(self.allocator, v.ty);
                    continue;
                }
                {
                    if (self.resolved.get(v)) |hit| {
                        self.cache_hits += 1;
                        try self.results.append(self.allocator, hit);
                        continue;
                    }
                }
                self.visits += 1;
                const n = self.node(v.ty);
                if (op == .resolve and n.tag == .variable) {
                    if (v.links == 0) return error.ChronologyBound;
                    if (try op.resolve.value(op.resolve.data, n.index(), v.cursor)) |version| {
                        try self.work.append(self.allocator, .{ .remember = v });
                        try self.work.append(self.allocator, .{ .visit = .{
                            .ty = version.replacement,
                            .fuel = v.fuel,
                            .links = v.links - 1,
                            .cursor = (version.position + 1) & 0xffffffffffff,
                        } });
                        continue;
                    }
                }
                switch (n.tag) {
                    .function, .array, .state_provider, .provider, .applied, .product => {
                        try self.work.append(self.allocator, .{ .finish = .{ .visit = v, .start = self.results.items.len } });
                        if (n.children()) |s| {
                            try self.work.append(self.allocator, .{ .many = .{ .span = s, .fuel = v.fuel - 1, .links = v.links, .cursor = v.cursor } });
                        } else if (n.tag != .provider) {
                            if (n.tag == .function) try self.work.append(self.allocator, .{ .visit = .{
                                .ty = @enumFromInt(n.b),
                                .fuel = v.fuel - 1,
                                .links = v.links,
                                .cursor = v.cursor,
                            } });
                            try self.work.append(self.allocator, .{ .visit = .{
                                .ty = @enumFromInt(if (n.tag == .state_provider) n.c else n.a),
                                .fuel = v.fuel - 1,
                                .links = v.links,
                                .cursor = v.cursor,
                            } });
                        }
                    },
                    else => {
                        const result = if (op == .rewrite) try self.replacedLeaf(v.ty, op.rewrite) else v.ty;
                        try self.results.append(self.allocator, result);
                        try self.remember(v, result);
                    },
                }
            },
        };
        return self.results.items;
    }
};

test "type nodes are compact and ordered lists are structurally interned" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.indexed(.variable, 0xffffffffffff);
    const b = try store.intern(.{ .tag = .boolean });
    const first = try store.listType(.product, @enumFromInt(0), &.{ a, b });
    _ = try store.listType(.product, @enumFromInt(0), &.{ b, a });
    try std.testing.expectEqual(first, try store.listType(.product, @enumFromInt(0), &.{ a, b }));
    try std.testing.expectEqual(@as(u64, 0xffffffffffff), store.node(a).index());
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Node));
}

test "rewrite is stack bounded and does not revisit inserted replacements" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.indexed(.variable, 1);
    var deep = a;
    for (0..4000) |_| deep = try store.intern(.{ .tag = .array, .a = @intFromEnum(deep) });
    const result = (try store.transform(.{ .one = deep }, 4001, .{ .rewrite = .{ .variable = .{ .index = 1, .value = deep } } }))[0];
    var cursor = result;
    for (0..4000) |_| cursor = @enumFromInt(store.node(cursor).a);
    try std.testing.expectEqual(deep, cursor);
    try std.testing.expectError(error.TypeComplexity, store.transform(.{ .one = deep }, 4000, .{ .rewrite = .{ .variable = .{ .index = 7, .value = a } } }));
}

test "shared type graphs are rewritten once per semantic memo key" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const leaf = try store.indexed(.variable, 0);
    const target = try store.intern(.{ .tag = .u32_type });
    const row_id = try store.effect(&.{}, .{ .tag = .closed });
    var root = leaf;
    for (0..40) |_| root = try store.intern(.{ .tag = .function, .a = @intFromEnum(root), .b = @intFromEnum(root), .c = @intFromEnum(row_id) });
    const rewritten = (try store.transform(.{ .one = root }, 100, .{ .rewrite = .{ .variable = .{ .index = 0, .value = target } } }))[0];
    try std.testing.expectEqual(@as(usize, 41), store.visits);
    try std.testing.expectEqual(@as(usize, 40), store.cache_hits);
    var cursor = rewritten;
    for (0..40) |_| {
        const n = store.node(cursor);
        try std.testing.expectEqual(n.a, n.b);
        cursor = @enumFromInt(n.a);
    }
    try std.testing.expectEqual(target, cursor);
}

fn allocationScenario(allocator: Allocator) !void {
    var store = Store.init(allocator);
    defer store.deinit();
    const scope = try store.symbol("scope");
    const label = try store.name(.{ .module = scope, .declaration = try store.symbol("effect") });
    const row_id = try store.effect(&.{ @intFromEnum(label), @intFromEnum(label) }, Tail.indexed(.variable, 3));
    const a = try store.indexed(.variable, 3);
    const b = try store.indexed(.parameter, 42);
    const function = try store.intern(.{ .tag = .function, .a = @intFromEnum(a), .b = @intFromEnum(a), .c = @intFromEnum(row_id) });
    const product = try store.listType(.product, @enumFromInt(0), &.{ function, a });
    _ = try store.transform(.{ .one = product }, 16, .{ .rewrite = .{ .variable = .{ .index = 3, .value = b } } });
}

test "type IR cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "interned row label slices survive backing buffer growth" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const original = try store.effect(&.{ 1, 1, 2 }, .{ .tag = .closed });
    for (0..256) |i| {
        const labels = store.items(store.row(original).labels);
        const next = try store.effect(labels, Tail.indexed(.variable, i));
        try std.testing.expectEqualSlices(u32, &.{ 1, 1, 2 }, store.items(store.row(next).labels));
    }
}

test "ground subtree summaries skip walks but preserve nesting and list fuel" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const leaf = try store.intern(.{ .tag = .u32_type });
    var deep = leaf;
    for (0..4096) |_| deep = try store.intern(.{ .tag = .array, .a = @intFromEnum(deep) });
    const product = try store.listType(.product, @enumFromInt(0), &.{ leaf, deep });
    const op: Operation = .{ .rewrite = .{ .variable = .{ .index = 1, .value = leaf } } };
    try std.testing.expectError(error.TypeComplexity, store.transform(.{ .one = product }, 4099, op));
    try std.testing.expectEqual(product, (try store.transform(.{ .one = product }, 4100, op))[0]);
    try std.testing.expectEqual(@as(usize, 1), store.visits);
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Facts));
}
