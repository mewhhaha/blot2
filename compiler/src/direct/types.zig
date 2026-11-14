//! Concrete types of one direct compilation, hash-consed across all units, so
//! type equality is handle equality and each layout is computed once.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const storage_types = @import("../check/storage_types.zig");
const W = @import("writer.zig");
const A = std.mem.Allocator;

pub const Ty = u32;
pub const unit: Ty = 0;
pub const boolean: Ty = 1;
pub const u32_: Ty = 2;
pub const f32_: Ty = 3;
pub const never: Ty = 4;

pub const Tag = enum(u8) { unit, boolean, u32, f32, never, tuple, record, nominal, function, array, list, cursor, grow, resize, ref, view, link, provider, state_provider };
/// tuple/record: a = extra start, b = count (records store name/type pairs in
/// spelling order); nominal: a = extra start ([unit, decl, arguments...]), b =
/// argument count; function: a = parameter, b = result; containers: a = element.
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0 };
pub const Field = struct { name: u32, ty: Ty };

pub const VarKey = struct { unit: u32, ty: T.Id };
/// Bindings of Core type variables (by unit and type node) to concrete types.
pub const Env = std.AutoHashMapUnmanaged(VarKey, Ty);
pub const Error = A.Error || error{Unsupported};

/// The constructors of one concrete nominal type, in declaration order.
pub const Variants = struct { tags: []const u32, payloads: []const Ty };

const Words = struct {
    words: []const u32,
    pub fn hash(self: @This(), key: core.List) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.words[key.start..][0..key.len]));
    }
    pub fn eql(self: @This(), left: core.List, right: core.List) bool {
        return std.mem.eql(u32, self.words[left.start..][0..left.len], self.words[right.start..][0..right.len]);
    }
    const Adapter = struct {
        words: []const u32,
        pub fn hash(_: @This(), key: []const u32) u64 {
            return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(key));
        }
        pub fn eql(self: @This(), key: []const u32, other: core.List) bool {
            return std.mem.eql(u32, key, self.words[other.start..][0..other.len]);
        }
    };
};

pub const Types = struct {
    allocator: A,
    arena: std.heap.ArenaAllocator,
    units: []const core.Module,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(u32) = .empty,
    keys: std.ArrayList(core.List) = .empty,
    encodings: std.ArrayList(u32) = .empty,
    index: std.HashMapUnmanaged(core.List, Ty, Words, 80) = .empty,
    names: std.StringHashMapUnmanaged(u32) = .empty,
    spellings: std.ArrayList([]const u8) = .empty,
    layouts: std.ArrayList(?[]const W.ValType) = .empty,
    variant_cache: std.AutoHashMapUnmanaged(Ty, Variants) = .empty,
    /// Lowered closed Core types; open ones depend on an environment.
    closed: std.AutoHashMapUnmanaged(VarKey, Ty) = .empty,
    nominal_positions: std.AutoHashMapUnmanaged(T.NominalIdentity, u32) = .empty,
    in_layout: std.AutoHashMapUnmanaged(Ty, void) = .empty,
    /// The Core type that last failed to lower, for diagnostics.
    failure: ?VarKey = null,
    holes: bool = false,
    /// What an unbound variable lowers to while `holes` is set.
    hole_fill: Ty = never,
    failure_reason: []const u8 = "",

    pub fn init(allocator: A, units: []const core.Module) Error!Types {
        var self: Types = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .units = units };
        errdefer self.deinit();
        inline for (.{ Tag.unit, Tag.boolean, Tag.u32, Tag.f32, Tag.never }) |tag| _ = try self.intern(tag, &.{});
        return self;
    }
    pub fn deinit(self: *Types) void {
        const a = self.allocator;
        self.nodes.deinit(a);
        self.extra.deinit(a);
        self.keys.deinit(a);
        self.encodings.deinit(a);
        self.index.deinit(a);
        self.names.deinit(a);
        self.spellings.deinit(a);
        self.layouts.deinit(a);
        self.variant_cache.deinit(a);
        self.closed.deinit(a);
        self.nominal_positions.deinit(a);
        self.in_layout.deinit(a);
        self.arena.deinit();
    }
    pub fn node(self: *const Types, ty: Ty) Node {
        return self.nodes.items[ty];
    }
    pub fn list(self: *const Types, start: u32, len: u32) []const u32 {
        return self.extra.items[start..][0..len];
    }
    pub fn tupleItems(self: *const Types, ty: Ty) []const Ty {
        const n = self.node(ty);
        std.debug.assert(n.tag == .tuple);
        return self.list(n.a, n.b);
    }
    pub fn recordField(self: *const Types, ty: Ty, index: usize) Field {
        const n = self.node(ty);
        std.debug.assert(n.tag == .record);
        return .{ .name = self.extra.items[n.a + index * 2], .ty = self.extra.items[n.a + index * 2 + 1] };
    }
    pub fn nominalIdentity(self: *const Types, ty: Ty) T.NominalIdentity {
        const n = self.node(ty);
        std.debug.assert(n.tag == .nominal);
        return .{ .unit = self.extra.items[n.a], .decl = self.extra.items[n.a + 1] };
    }
    pub fn nominalArguments(self: *const Types, ty: Ty) []const Ty {
        const n = self.node(ty);
        std.debug.assert(n.tag == .nominal);
        return self.list(n.a + 2, n.b);
    }
    /// Units are numbered from one in compilation order.
    pub fn module(self: *const Types, unit_id: u32) ?*const core.Module {
        if (unit_id == 0 or unit_id > self.units.len) return null;
        return &self.units[unit_id - 1];
    }

    pub fn intern(self: *Types, tag: Tag, payload: []const u32) Error!Ty {
        const a = self.allocator;
        var small: [16]u32 = undefined;
        const encoding = if (payload.len < small.len) small[0 .. payload.len + 1] else try self.arena.allocator().alloc(u32, payload.len + 1);
        encoding[0] = @backingInt(tag);
        @memcpy(encoding[1..], payload);
        if (self.index.getAdapted(encoding, Words.Adapter{ .words = self.encodings.items })) |found| return found;
        const span: core.List = .{ .start = @intCast(self.encodings.items.len), .len = @intCast(encoding.len) };
        try self.encodings.appendSlice(a, encoding);
        const id: Ty = @intCast(self.nodes.items.len);
        const start: u32 = @intCast(self.extra.items.len);
        const arity: ?usize = switch (tag) {
            .function => 2,
            .array, .list, .cursor, .grow, .resize, .ref, .view, .link, .provider => 1,
            .state_provider => 3,
            .nominal => null,
            else => null,
        };
        if (arity) |count| if (payload.len != count) return error.Unsupported;
        if (tag == .nominal and payload.len < 2) return error.Unsupported;
        const value: Node = switch (tag) {
            .unit, .boolean, .u32, .f32, .never => .{ .tag = tag },
            .tuple, .state_provider => .{ .tag = tag, .a = start, .b = @intCast(payload.len) },
            .record => .{ .tag = tag, .a = start, .b = @intCast(payload.len / 2) },
            .nominal => .{ .tag = tag, .a = start, .b = @intCast(payload.len - 2) },
            .function => if (payload.len == 2) .{ .tag = tag, .a = payload[0], .b = payload[1] } else unreachable,
            .array, .list, .cursor, .grow, .resize, .ref, .view, .link, .provider => if (payload.len == 1) .{ .tag = tag, .a = payload[0] } else unreachable,
        };
        if (tag == .tuple or tag == .record or tag == .nominal or tag == .state_provider) try self.extra.appendSlice(a, payload);
        try self.nodes.append(a, value);
        try self.keys.append(a, span);
        try self.layouts.append(a, null);
        try self.index.putContext(a, span, id, .{ .words = self.encodings.items });
        return id;
    }
    pub fn function(self: *Types, parameter: Ty, result: Ty) Error!Ty {
        return self.intern(.function, &.{ parameter, result });
    }
    pub fn tuple(self: *Types, items: []const Ty) Error!Ty {
        if (items.len == 0) return unit;
        return self.intern(.tuple, items);
    }
    /// Field order is the UTF-8 spelling order, independent of source order.
    pub fn record(self: *Types, fields: []Field) Error!Ty {
        std.mem.sort(Field, fields, self, struct {
            fn less(types: *Types, left: Field, right: Field) bool {
                return std.mem.order(u8, types.spellings.items[left.name], types.spellings.items[right.name]) == .lt;
            }
        }.less);
        const payload = try self.allocator.alloc(u32, std.math.mul(usize, fields.len, 2) catch return error.OutOfMemory);
        defer self.allocator.free(payload);
        for (fields, 0..) |field, index| {
            payload[index * 2] = field.name;
            payload[index * 2 + 1] = field.ty;
        }
        return self.intern(.record, payload);
    }
    pub fn fieldName(self: *Types, spelling: []const u8) Error!u32 {
        if (self.names.get(spelling)) |found| return found;
        const owned = try self.arena.allocator().dupe(u8, spelling);
        const id: u32 = @intCast(self.spellings.items.len);
        try self.spellings.append(self.allocator, owned);
        try self.names.put(self.allocator, owned, id);
        return id;
    }
    pub fn findField(self: *const Types, ty: Ty, name: u32) ?usize {
        const n = self.node(ty);
        if (n.tag != .record) return null;
        for (0..n.b) |index| if (self.recordField(ty, index).name == name) return index;
        return null;
    }

    fn fail(self: *Types, m: *const core.Module, ty: T.Id, reason: []const u8) error{Unsupported} {
        self.failure = .{ .unit = m.unit, .ty = ty };
        self.failure_reason = reason;
        return error.Unsupported;
    }

    /// Lowers a Core type under `env`, which binds the type variables of the
    /// instance being compiled.
    pub fn lower(self: *Types, m: *const core.Module, ty: T.Id, env: *const Env) Error!Ty {
        var open = false;
        return self.lowerInner(m, ty, env, &open, 0);
    }
    /// Like lower, but unbound variables become `never` holes, which
    /// `match` skips: an expected type known only in part.
    pub fn lowerHoles(self: *Types, m: *const core.Module, ty: T.Id, env: *const Env) Error!Ty {
        return self.lowerFilled(m, ty, env, never);
    }
    /// Like lowerHoles, with `fill` in place of each unbound variable.
    pub fn lowerFilled(self: *Types, m: *const core.Module, ty: T.Id, env: *const Env, fill: Ty) Error!Ty {
        self.holes = true;
        self.hole_fill = fill;
        defer {
            self.holes = false;
            self.hole_fill = never;
        }
        var open = false;
        return self.lowerInner(m, ty, env, &open, 0);
    }
    fn lowerInner(self: *Types, m: *const core.Module, ty: T.Id, env: *const Env, open: *bool, depth: usize) Error!Ty {
        switch (ty) {
            T.unit => return unit,
            T.boolean => return boolean,
            T.u32_type => return u32_,
            T.f32_type => return f32_,
            T.never => return never,
            else => {},
        }
        if (depth > 256) return self.fail(m, ty, "type nesting exceeds 256");
        const key: VarKey = .{ .unit = m.unit, .ty = ty };
        if (self.closed.get(key)) |hit| return hit;
        var child_open = false;
        const n = m.types.node(ty);
        const result: Ty = switch (n.tag) {
            .variable, .bound => blk: {
                child_open = true;
                break :blk env.get(key) orelse (if (self.holes) self.hole_fill else return self.fail(m, ty, "unresolved type variable"));
            },
            .usage, .forall => try self.lowerInner(m, n.a, env, &child_open, depth + 1),
            .function => try self.function(try self.lowerInner(m, n.a, env, &child_open, depth + 1), try self.lowerInner(m, n.b, env, &child_open, depth + 1)),
            .product => blk: {
                const children = m.types.list(.{ .start = n.a, .len = n.b });
                const items = try self.allocator.alloc(Ty, children.len);
                defer self.allocator.free(items);
                for (children, items) |child, *item| item.* = try self.lowerInner(m, child, env, &child_open, depth + 1);
                break :blk try self.tuple(items);
            },
            .record => blk: {
                const fields = try self.allocator.alloc(Field, n.b);
                defer self.allocator.free(fields);
                for (fields, 0..) |*field, index| {
                    const source = m.types.recordField(n, index);
                    const spelling = m.fieldSpelling(source.name) orelse return self.fail(m, ty, "record field without a spelling");
                    field.* = .{ .name = try self.fieldName(spelling), .ty = try self.lowerInner(m, source.ty, env, &child_open, depth + 1) };
                }
                break :blk try self.record(fields);
            },
            .nominal => blk: {
                const arguments = m.types.nominalArguments(n);
                if (storage_types.identity(n.a, n.b)) |kind| {
                    if (arguments.len != 1) return self.fail(m, ty, "storage type arity");
                    const element = try self.lowerInner(m, arguments[0], env, &child_open, depth + 1);
                    const tag: Tag = switch (kind) {
                        .grow => .grow,
                        .resize => .resize,
                        .ref => .ref,
                        .view => .view,
                        .link => .link,
                    };
                    break :blk try self.intern(tag, &.{element});
                }
                if (n.a == std.math.maxInt(u32)) return self.fail(m, ty, "compiler-owned nominal type");
                const payload = try self.allocator.alloc(u32, arguments.len + 2);
                defer self.allocator.free(payload);
                payload[0] = n.a;
                payload[1] = n.b;
                for (arguments, payload[2..]) |argument, *slot| slot.* = try self.lowerInner(m, argument, env, &child_open, depth + 1);
                break :blk try self.intern(.nominal, payload);
            },
            .provider => try self.intern(.provider, &.{try self.operation(m, n.a, env, &child_open, depth + 1)}),
            .state_provider => try self.intern(.state_provider, &.{
                try self.operation(m, n.a, env, &child_open, depth + 1),
                try self.operation(m, n.b, env, &child_open, depth + 1),
                try self.lowerInner(m, n.c, env, &child_open, depth + 1),
            }),
            .array, .list, .cursor => blk: {
                const element = try self.lowerInner(m, n.a, env, &child_open, depth + 1);
                break :blk try self.intern(switch (n.tag) {
                    .array => .array,
                    .list => .list,
                    else => .cursor,
                }, &.{element});
            },
            else => return self.fail(m, ty, @tagName(n.tag)),
        };
        if (child_open) open.* = true else try self.closed.put(self.allocator, key, result);
        return result;
    }

    /// An effect operation's nominal type: only an identity, so compiler-owned
    /// operations (the builtin State family) lower like declared ones.
    fn operation(self: *Types, m: *const core.Module, ty: T.Id, env: *const Env, open: *bool, depth: usize) Error!Ty {
        const n = m.types.node(ty);
        if (n.tag != .nominal) return self.lowerInner(m, ty, env, open, depth);
        const arguments = m.types.nominalArguments(n);
        const payload = try self.allocator.alloc(u32, arguments.len + 2);
        defer self.allocator.free(payload);
        payload[0] = n.a;
        payload[1] = n.b;
        for (arguments, payload[2..]) |argument, *slot| slot.* = try self.lowerInner(m, argument, env, open, depth + 1);
        return self.intern(.nominal, payload);
    }
    /// Binds the variables of `pattern` (a Core type of `m`) so that it
    /// lowers to `actual`. Already bound variables keep their binding.
    pub fn match(self: *Types, m: *const core.Module, pattern: T.Id, actual: Ty, env: *Env) Error!void {
        return self.matchInner(m, pattern, actual, env, 0);
    }
    fn matchInner(self: *Types, m: *const core.Module, pattern: T.Id, actual: Ty, env: *Env, depth: usize) Error!void {
        if (pattern <= T.never or depth > 256) return;
        const n = m.types.node(pattern);
        const have = self.node(actual);
        switch (n.tag) {
            .variable, .bound => {
                if (actual == never) return; // a hole in a partly known type
                const entry = try env.getOrPut(self.allocator, .{ .unit = m.unit, .ty = pattern });
                if (!entry.found_existing) entry.value_ptr.* = actual;
            },
            .usage, .forall => try self.matchInner(m, n.a, actual, env, depth + 1),
            .function => if (have.tag == .function) {
                try self.matchInner(m, n.a, have.a, env, depth + 1);
                try self.matchInner(m, n.b, have.b, env, depth + 1);
            },
            .product => if (have.tag == .tuple and have.b == n.b) {
                for (m.types.list(.{ .start = n.a, .len = n.b }), self.list(have.a, have.b)) |child, item| try self.matchInner(m, child, item, env, depth + 1);
            },
            .record => if (have.tag == .record) {
                for (0..n.b) |index| {
                    const source = m.types.recordField(n, index);
                    const spelling = m.fieldSpelling(source.name) orelse continue;
                    const name = self.names.get(spelling) orelse continue;
                    const position = self.findField(actual, name) orelse continue;
                    try self.matchInner(m, source.ty, self.recordField(actual, position).ty, env, depth + 1);
                }
            },
            .nominal => {
                const arguments = m.types.nominalArguments(n);
                if (storage_types.identity(n.a, n.b) != null) {
                    if (arguments.len == 1 and isContainer(have.tag)) try self.matchInner(m, arguments[0], have.a, env, depth + 1);
                } else if (have.tag == .nominal) {
                    const identity = self.nominalIdentity(actual);
                    if (identity.unit != n.a or identity.decl != n.b) return;
                    const items = self.nominalArguments(actual);
                    if (items.len != arguments.len) return;
                    for (arguments, items) |argument, item| try self.matchInner(m, argument, item, env, depth + 1);
                }
            },
            .array, .list, .cursor => if (isContainer(have.tag)) try self.matchInner(m, n.a, have.a, env, depth + 1),
            .provider => if (have.tag == .provider) try self.matchInner(m, n.a, have.a, env, depth + 1),
            .state_provider => if (have.tag == .state_provider) {
                for ([_]T.Id{ n.a, n.b, n.c }, self.list(have.a, have.b)) |child, item| try self.matchInner(m, child, item, env, depth + 1);
            },
            else => {},
        }
    }

    /// The constructors of a concrete nominal type and their payload types.
    pub fn variants(self: *Types, ty: Ty) Error!Variants {
        if (self.variant_cache.get(ty)) |hit| return hit;
        if (self.node(ty).tag != .nominal) {
            self.failure_reason = "constructor of a non-nominal type";
            return error.Unsupported;
        }
        const identity = self.nominalIdentity(ty);
        const owner = self.module(identity.unit) orelse return error.Unsupported;
        const ordinal = try self.nominalOrdinal(owner, identity);
        const constructors = owner.nominalConstructors(ordinal);
        const tags = try self.arena.allocator().alloc(u32, constructors.len);
        const payloads = try self.arena.allocator().alloc(Ty, constructors.len);
        for (constructors, tags, payloads) |constructor_id, *tag, *payload| {
            const constructor = owner.constructor(constructor_id);
            tag.* = constructor.tag;
            const signature = owner.types.node(constructor.scheme.root);
            const result = if (signature.tag == .function) signature.b else constructor.scheme.root;
            var env: Env = .empty;
            defer env.deinit(self.allocator);
            try self.match(owner, result, ty, &env);
            // A hole argument (a type no use determines) leaves holes.
            const holed = std.mem.findScalar(Ty, self.nominalArguments(ty), never) != null;
            payload.* = if (constructor.payload == 0) unit else if (holed) try self.lowerHoles(owner, constructor.payload, &env) else try self.lower(owner, constructor.payload, &env);
        }
        const value: Variants = .{ .tags = tags, .payloads = payloads };
        try self.variant_cache.put(self.allocator, ty, value);
        return value;
    }
    pub fn nominalOrdinal(self: *Types, owner: *const core.Module, identity: T.NominalIdentity) Error!u32 {
        if (self.nominal_positions.get(identity)) |hit| return hit;
        for (owner.nominals, 0..) |nominal, ordinal| {
            if (nominal.identity.unit == identity.unit and nominal.identity.decl == identity.decl) {
                try self.nominal_positions.put(self.allocator, identity, @intCast(ordinal));
                return @intCast(ordinal);
            }
        }
        return error.Unsupported;
    }

    /// Values wider than this many words are passed and held as a pointer
    /// to an immutable copy (decision 5: one fixed layout per type).
    pub const box_words = 16;
    /// Whether values of `ty` are boxed: a pointer to their flat words.
    pub fn boxed(self: *Types, ty: Ty) Error!bool {
        const tag = self.node(ty).tag;
        if (tag != .tuple and tag != .record and tag != .nominal) return false;
        return (try self.flat(ty)).len > box_words;
    }
    /// A value's register words: its flat words, or one pointer if boxed.
    pub fn layout(self: *Types, ty: Ty) Error![]const W.ValType {
        if (try self.boxed(ty)) return &.{.i32};
        return self.flat(ty);
    }
    /// Bytes of a value's flat form in memory.
    pub fn flatBytes(self: *Types, ty: Ty) Error!u32 {
        var bytes: u32 = 0;
        for (try self.flat(ty)) |kind| bytes += if (kind == .v128) 16 else 4;
        return bytes;
    }
    /// The flattened machine words of a value of type `ty`: nested values
    /// inline, as stored in memory.
    pub fn flat(self: *Types, ty: Ty) Error![]const W.ValType {
        if (self.layouts.items[ty]) |hit| return hit;
        if (self.in_layout.contains(ty)) {
            self.failure_reason = "recursive data type needs an indirection";
            return error.Unsupported;
        }
        try self.in_layout.put(self.allocator, ty, {});
        defer _ = self.in_layout.remove(ty);
        var words: std.ArrayList(W.ValType) = .empty;
        defer words.deinit(self.allocator);
        const n = self.node(ty);
        switch (n.tag) {
            .unit, .never => {},
            .boolean, .u32 => try words.append(self.allocator, .i32),
            .f32 => try words.append(self.allocator, .f32),
            .tuple => for (self.list(n.a, n.b)) |item| try words.appendSlice(self.allocator, try self.flat(item)),
            .record => for (0..n.b) |index| try words.appendSlice(self.allocator, try self.flat(self.recordField(ty, index).ty)),
            // A provider is its implementation closure; a state provider is
            // its initial state.
            .function, .provider => try words.appendSlice(self.allocator, &.{ .i32, .i32 }),
            .state_provider => try words.appendSlice(self.allocator, try self.flat(self.list(n.a, n.b)[2])),
            .nominal => {
                const cases = try self.variants(ty);
                if (cases.payloads.len == 1) {
                    try words.appendSlice(self.allocator, try self.flat(cases.payloads[0]));
                } else if (cases.payloads.len > 1) {
                    try words.append(self.allocator, .i32);
                    const payload_layouts = try self.allocator.alloc([]const W.ValType, cases.payloads.len);
                    defer self.allocator.free(payload_layouts);
                    var width: usize = 0;
                    for (cases.payloads, payload_layouts) |payload, *slot| {
                        slot.* = try self.flat(payload);
                        width = @max(width, slot.len);
                    }
                    for (0..width) |position| {
                        var all_f32 = true;
                        var any_v128 = false;
                        for (payload_layouts) |payload| if (position < payload.len) {
                            if (payload[position] != .f32) all_f32 = false;
                            if (payload[position] == .v128) any_v128 = true;
                        };
                        if (any_v128) {
                            self.failure_reason = "SIMD payload in a sum type";
                            return error.Unsupported;
                        }
                        try words.append(self.allocator, if (all_f32) .f32 else .i32);
                    }
                }
            },
            // Owner handles: (slot, generation); views add (start, length),
            // element references and links add an index.
            .array, .list, .grow, .resize => try words.appendSlice(self.allocator, &.{ .i32, .i32 }),
            .view => try words.appendSlice(self.allocator, &.{ .i32, .i32, .i32, .i32 }),
            .ref, .link => try words.appendSlice(self.allocator, &.{ .i32, .i32, .i32 }),
            .cursor => try words.appendSlice(self.allocator, &.{ .i32, .i32, .i32, .i32 }),
        }
        const owned = try self.arena.allocator().dupe(W.ValType, words.items);
        self.layouts.items[ty] = owned;
        return owned;
    }
};

fn isContainer(tag: Tag) bool {
    return switch (tag) {
        .array, .list, .cursor, .grow, .resize, .ref, .view, .link => true,
        else => false,
    };
}
