//! Interned concrete representation evidence, separate from inference history.
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const wasm = @import("wasm.zig");
const evidence = @import("../eval/type_evidence.zig");
const code_expectation = @import("../reuse/code_expectation.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const word: Id = 3;
pub const erased: Id = 6;
/// Unknown effects are representation-only facts, distinct from closed empty.
pub const capability_layout_decl: u32 = 7;
pub const unknown_row: u32 = std.math.maxInt(u32);
pub const Tag = enum(u8) { invalid, unit, boolean, u32, f32, never, product, record, nominal, array, list, cursor, function, demand, type_constructor, resolver, erased, provider, state_provider, erased_proof, existential, opened, universal, scoped, owning, associated };
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Mapping = struct { variable: types.Id, layout: Id, instance: types.NominalIdentity = .{ .unit = 0, .decl = 0 } };
pub fn mappedInstance(original: types.NominalIdentity, mappings: []const Mapping) types.NominalIdentity {
    if (original.unit != 0 or original.decl == 0) return original;
    for (mappings) |mapping| if (mapping.variable == original.decl and mapping.instance.decl != 0) return mapping.instance;
    return original;
}
pub const UniversalDictionaries = struct { owner: Id, start: u32, len: u32 };
pub const RowMapping = struct { variable: u32, row: evidence.Effects.Id };
pub const Error = Allocator.Error || error{ UnresolvedType, LayoutLimit, TypeMismatch };
/// Layouts of closed source types: types that name no variable, binder,
/// projection, scoped capability or open row, so no substitution, row fact or
/// enclosing quantifier changes their layout. Only the units it was given are
/// memoized, by their position, for as long as they live.
pub const ClosedLayouts = struct {
    units: []const core.Module = &.{},
    /// Per unit, per type: 0 unknown, 1 closed, 2 open.
    kinds: std.ArrayList([]u8) = .empty,
    layouts: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    const closed_kind: u8 = 1;
    const open_kind: u8 = 2;
    pub fn deinit(self: *ClosedLayouts, a: Allocator) void {
        for (self.kinds.items) |kinds| a.free(kinds);
        self.kinds.deinit(a);
        self.layouts.deinit(a);
        self.* = .{};
    }
    /// The memo key of `ty` when `module` is one of the memoized units and
    /// the type is closed.
    fn key(self: *ClosedLayouts, a: Allocator, module: *const core.Module, ty: types.Id) Allocator.Error!?u64 {
        if (self.units.len == 0) return null;
        const first = @intFromPtr(self.units.ptr);
        const address = @intFromPtr(module);
        if (address < first or address >= first + self.units.len * @sizeOf(core.Module)) return null;
        const offset = address - first;
        if (offset % @sizeOf(core.Module) != 0) return null;
        const unit = offset / @sizeOf(core.Module);
        if (ty >= module.types.nodes.len) return null;
        if (self.kinds.items.len == 0) {
            try self.kinds.ensureTotalCapacityPrecise(a, self.units.len);
            self.kinds.appendNTimesAssumeCapacity(&.{}, self.units.len);
        }
        if (self.kinds.items[unit].len != module.types.nodes.len) {
            const kinds = try a.alloc(u8, module.types.nodes.len);
            @memset(kinds, 0);
            a.free(self.kinds.items[unit]);
            self.kinds.items[unit] = kinds;
        }
        if (!closedType(module, self.kinds.items[unit], ty, 0)) return null;
        return (@as(u64, unit) << 32) | ty;
    }
    /// Substitutions only name variables, binders and projections, never a
    /// closed type, so a memoized layout never skips one. Checked in safe
    /// builds.
    fn checkSubstitutions(self: *ClosedLayouts, module: *const core.Module, mappings: []const Mapping) void {
        const unit = (@intFromPtr(module) - @intFromPtr(self.units.ptr)) / @sizeOf(core.Module);
        for (mappings) |mapping| {
            if (mapping.variable >= module.types.nodes.len) continue;
            std.debug.assert(!closedType(module, self.kinds.items[unit], mapping.variable, 0));
        }
    }
    fn closedType(module: *const core.Module, kinds: []u8, ty: types.Id, depth: usize) bool {
        if (kinds[ty] != 0) return kinds[ty] == closed_kind;
        if (depth >= 1024) return false;
        const n = module.types.node(ty);
        const closed = switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never, .erased_proof, .type_constructor => true,
            .array, .list, .cursor, .resolver, .usage => closedType(module, kinds, n.a, depth + 1),
            .function => closedType(module, kinds, n.a, depth + 1) and closedType(module, kinds, n.b, depth + 1) and module.types.row(n.c).tail == .closed and module.types.rowLabels(n.c).len == 0,
            .product, .nominal => blk: {
                const children_ = if (n.tag == .nominal) module.types.nominalArguments(n) else module.types.list(.{ .start = n.a, .len = n.b });
                for (children_) |child| if (!closedType(module, kinds, child, depth + 1)) break :blk false;
                break :blk true;
            },
            .record => blk: {
                for (0..n.b) |index| if (!closedType(module, kinds, module.types.recordField(n, index).ty, depth + 1)) break :blk false;
                break :blk true;
            },
            else => false,
        };
        kinds[ty] = if (closed) closed_kind else open_kind;
        return closed;
    }
};
pub const Store = struct {
    /// Memoizes closed type layouts of these units (see ClosedLayouts).
    closed: ClosedLayouts = .{},
    opaque_sources: []const core.Module = &.{},
    record_names: @import("../check/record_order.zig").Names = .{},
    allocator: Allocator,
    effects: evidence.Effects.Store,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(u32) = .empty,
    universal_dictionaries: std.ArrayList(UniversalDictionaries) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    solver_owners: std.ArrayList([]const types.Id) = .empty,
    type_owners: std.ArrayList(types.Id) = .empty,
    pub fn init(allocator: Allocator) Error!Store {
        var self: Store = .{ .allocator = allocator, .effects = .{ .allocator = allocator } };
        errdefer self.deinit();
        self.effects = evidence.Effects.Store.init(allocator) catch |err| return effectError(err);
        try self.nodes.appendSlice(allocator, &.{ .{ .tag = .invalid }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never }, .{ .tag = .erased } });
        try self.next.appendNTimes(allocator, 0, self.nodes.items.len);
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.closed.deinit(self.allocator);
        self.record_names.deinit(self.allocator);
        self.effects.deinit();
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.universal_dictionaries.deinit(self.allocator);
        self.next.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.solver_owners.deinit(self.allocator);
        self.type_owners.deinit(self.allocator);
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
            .universal, .existential => self.extra.items[n.c..][0..n.b],
            else => &.{},
        };
    }
    pub fn dictionaryRecord(self: *const Store, owner: Id) ?UniversalDictionaries {
        var low: usize = 0;
        var high = self.universal_dictionaries.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const record = self.universal_dictionaries.items[middle];
            if (record.owner < owner) low = middle + 1 else high = middle;
        }
        if (low == self.universal_dictionaries.items.len or self.universal_dictionaries.items[low].owner != owner) return null;
        return self.universal_dictionaries.items[low];
    }
    pub fn hasDictionaryABI(self: *const Store, owner: Id) bool {
        return self.dictionaryRecord(owner) != null;
    }
    pub fn dictionarySlots(self: *const Store, owner: Id) []const Id {
        const record = self.dictionaryRecord(owner) orelse return &.{};
        return self.extra.items[record.start..][0..record.len];
    }
    /// Physical slots supplement an independently owned semantic quantifier.
    /// Zero marks a type member; an empty vector still selects the evidence ABI.
    pub fn internAssociated(self: *Store, goal: u32, member: u32, scope: u32) Error!Id {
        if (goal >= 4096 or member == 0 or scope >= 128) return error.TypeMismatch;
        return self.internFields(.associated, goal, member, scope, &.{});
    }
    pub fn internUniversalWithDictionaries(self: *Store, body: Id, binders: []const Id, slots: []const Id) Error!Id {
        if (slots.len > 65536) return error.LayoutLimit;
        _ = try self.intern(.universal, body, @intCast(binders.len), binders);
        for (slots) |slot| {
            if (slot == 0) continue;
            if (slot >= self.nodes.items.len or self.node(slot).tag != .function) return error.TypeMismatch;
        }
        return self.internFieldsWithDictionaries(.universal, body, @intCast(binders.len), 0, binders, slots);
    }
    /// Ownership comes from the selected physical graph, including generic
    /// substitutions. Shared nodes are visited once; no second schema is built.
    pub fn hasOwners(self: *const Store, root: Id) error{LayoutLimit}!bool {
        var nodes: [4096]Id = undefined;
        var count: usize = 1;
        var cursor: usize = 0;
        nodes[0] = root;
        while (cursor < count) : (cursor += 1) {
            const id = nodes[cursor];
            if (id >= self.nodes.items.len) return error.LayoutLimit;
            const n = self.node(id);
            if (n.tag == .owning) return true;
            const direct = [_]Id{ n.a, n.b, n.c };
            const children_: []const Id = switch (n.tag) {
                .array, .list, .cursor, .resolver, .demand, .provider, .scoped, .universal, .existential => direct[0..1],
                .function => direct[0..2],
                .state_provider => &direct,
                .product, .nominal, .record => self.children(id),
                else => &.{},
            };
            for (children_, 0..) |child, index| {
                if (n.tag == .record and index % 2 == 0) continue;
                var known = false;
                for (nodes[0..count]) |prior| if (prior == child) {
                    known = true;
                    break;
                };
                if (known) continue;
                if (count == nodes.len) return error.LayoutLimit;
                nodes[count] = child;
                count += 1;
            }
        }
        return false;
    }
    /// Reconcile two physical views of one type. Holes add no facts; known
    /// heads, storage slots and effect rows must still agree.
    pub fn mergePartial(self: *Store, left: Id, right: Id) Error!Id {
        var budget: usize = 1_000_000;
        return self.mergePartialDepth(left, right, 0, &budget);
    }
    fn mergePartialDepth(self: *Store, left: Id, right: Id, depth: usize, budget: *usize) Error!Id {
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        if (left == right or right == erased) return left;
        if (left == erased) return right;
        const a = self.node(left);
        const b = self.node(right);
        if (a.tag != b.tag) return error.TypeMismatch;
        switch (a.tag) {
            .owning => {
                if (a.b != b.b) return error.TypeMismatch;
                return self.intern(.owning, try self.mergePartialDepth(a.a, b.a, depth + 1, budget), a.b, &.{});
            },
            .universal, .existential => {
                if (a.b != b.b or !std.mem.eql(Id, self.children(left), self.children(right))) return error.TypeMismatch;
                if (self.hasDictionaryABI(left) != self.hasDictionaryABI(right)) return error.TypeMismatch;
                if (!std.mem.eql(Id, self.dictionarySlots(left), self.dictionarySlots(right))) return error.TypeMismatch;
                const body = try self.mergePartialDepth(a.a, b.a, depth + 1, budget);
                if (self.hasDictionaryABI(left)) return self.internUniversalWithDictionaries(body, self.children(left), self.dictionarySlots(left));
                return self.intern(a.tag, body, a.b, self.children(left));
            },
            .array, .list, .cursor, .resolver => return self.intern(a.tag, try self.mergePartialDepth(a.a, b.a, depth + 1, budget), 0, &.{}),
            .function, .demand, .provider => {
                var row = a.c;
                if (row == unknown_row) row = b.c;
                if (b.c != unknown_row and row != b.c) return error.TypeMismatch;
                const input = try self.mergePartialDepth(a.a, b.a, depth + 1, budget);
                var output: Id = 0;
                if (a.tag == .function) output = try self.mergePartialDepth(a.b, b.b, depth + 1, budget);
                return self.internWithEffects(a.tag, input, output, row, &.{});
            },
            .state_provider => return self.internStateProvider(try self.mergePartialDepth(a.a, b.a, depth + 1, budget), try self.mergePartialDepth(a.b, b.b, depth + 1, budget), try self.mergePartialDepth(a.c, b.c, depth + 1, budget)),
            .product, .record, .nominal => {
                if (a.tag == .nominal and (a.a != b.a or a.b != b.b)) return error.TypeMismatch;
                const count = self.children(left).len;
                if (count != self.children(right).len) return error.TypeMismatch;
                var buffer: [256]u8 align(@alignOf(u32)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(scratch.allocator());
                for (0..count) |index| {
                    const first = self.children(left)[index];
                    const second = self.children(right)[index];
                    var value = first;
                    if (a.tag == .record and index % 2 == 0) {
                        if (first != second) return error.TypeMismatch;
                    } else value = try self.mergePartialDepth(first, second, depth + 1, budget);
                    try values.append(scratch.allocator(), value);
                }
                if (a.tag == .nominal) return self.intern(.nominal, a.a, a.b, values.items);
                return self.intern(a.tag, 0, 0, values.items);
            },
            else => return error.TypeMismatch,
        }
    }
    pub fn machine(self: *const Store, id: Id) wasm.ValueType {
        if (self.scalar(id)) |value| return value.machine();
        return .i32;
    }
    pub fn listInput(self: *const Store, id: Id) bool {
        const n = self.node(id);
        return n.tag == .list or (n.tag == .cursor and self.node(n.a).tag == .list);
    }
    /// The complete environment fits one inert machine word. Unknown,
    /// reference-bearing, floating and authority layouts retain heap storage.
    pub fn scalarEnvironment(self: *const Store, captures: Id) bool {
        if (self.node(captures).tag != .product) return false;
        const fields = self.children(captures);
        if (fields.len != 1) return false;
        const selected = self.scalar(fields[0]) orelse return false;
        return selected != .f32;
    }
    pub fn scalar(self: *const Store, id: Id) ?wasm.Scalar {
        return self.scalarDepth(id, 0);
    }
    fn scalarDepth(self: *const Store, id: Id, depth: usize) ?wasm.Scalar {
        if (depth >= 128) return null;
        if (self.node(id).tag == .nominal) return self.opaqueScalar(id, depth + 1);
        return switch (self.node(id).tag) {
            .unit => .unit,
            .boolean => .bool,
            .u32 => .u32,
            .f32 => .f32,
            else => null,
        };
    }
    fn opaqueScalar(self: *const Store, id: Id, depth: usize) ?wasm.Scalar {
        const node_ = self.node(id);
        if (node_.a == 0 or node_.a > self.opaque_sources.len) return null;
        for (self.opaque_sources[node_.a - 1].nominals) |nominal| {
            if (!nominal.is_opaque or nominal.identity.decl != node_.b) continue;
            switch (nominal.storage.kind) {
                .unit => return .unit,
                .boolean => return .bool,
                .u32 => return .u32,
                .f32 => return .f32,
                .parameter => {
                    const arguments = self.children(id);
                    if (nominal.storage.parameter >= arguments.len) return null;
                    var ordinal: u32 = 0;
                    var remaining: usize = 1_000_000;
                    const module = &self.opaque_sources[node_.a - 1];
                    const selected = self.opaqueParameter(module, module.types.list(nominal.parameters)[nominal.storage.parameter], arguments[nominal.storage.parameter], nominal.storage.selector, &ordinal, depth + 1, &remaining) orelse return null;
                    return self.scalarDepth(selected, depth + 1);
                },
                .reference, .unknown => return null,
            }
        }
        return null;
    }
    fn opaqueParameter(self: *const Store, module: *const core.Module, parameter: types.Id, actual: Id, target: u32, ordinal: *u32, depth: usize, remaining: *usize) ?Id {
        if (depth >= 128 or remaining.* == 0) return null;
        remaining.* -= 1;
        const node_ = module.types.node(parameter);
        if (node_.tag == .variable) {
            const selected = ordinal.*;
            ordinal.* += 1;
            if (selected == target) return actual;
            return null;
        }
        const argument = self.node(actual);
        if (node_.tag == .product and argument.tag == .product and node_.b == argument.b) {
            for (module.types.list(.{ .start = node_.a, .len = node_.b }), self.children(actual)) |child, supplied| {
                if (self.opaqueParameter(module, child, supplied, target, ordinal, depth + 1, remaining)) |found| return found;
            }
        } else if (node_.tag == .record and argument.tag == .record) {
            for (0..node_.b) |index| {
                const field = module.types.recordField(node_, index);
                const children_ = self.children(actual);
                for (0..children_.len / 2) |slot| {
                    if (children_[slot * 2] != field.name) continue;
                    if (self.opaqueParameter(module, field.ty, children_[slot * 2 + 1], target, ordinal, depth + 1, remaining)) |found| return found;
                    break;
                }
            }
        }
        return null;
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
        if (tag == .opened and (a >= 128 or b >= 128 or row > 2 or values.len != 0)) return error.TypeMismatch;
        if (tag == .existential or tag == .universal) {
            if (a == 0 or a >= self.nodes.items.len or b == 0 or b > 128 or row != 0) return error.TypeMismatch;
            if (values.len == 0) {
                var binders: [128]Id = undefined;
                for (binders[0..b], 0..) |*binder, ordinal| binder.* = try self.intern(.opened, @intCast(ordinal), 0, &.{});
                return self.internWithEffects(tag, a, b, row, binders[0..b]);
            }
            if (values.len != b) return error.TypeMismatch;
            for (values, 0..) |binder, ordinal| {
                if (binder >= self.nodes.items.len) return error.TypeMismatch;
                const leaf = self.node(binder);
                if (leaf.tag != .opened or leaf.a != ordinal or leaf.b != 0 or leaf.c > 2 or (tag == .existential and leaf.c != 0)) return error.TypeMismatch;
            }
        }
        if (tag == .nominal and a != 0 and a <= self.opaque_sources.len) {
            for (self.opaque_sources[a - 1].nominals) |nominal| {
                if (nominal.identity.decl == b and nominal.is_opaque and nominal.storage.kind == .unknown) return error.UnresolvedType;
            }
        }
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
            fn less(names: *const @import("../check/record_order.zig").Names, left: @This(), right: @This()) bool {
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
        return self.internFieldsWithDictionaries(tag, a, b, row, values, null);
    }
    fn internFieldsWithDictionaries(self: *Store, tag: Tag, a: u32, b: u32, row: u32, values: []const u32, slots: ?[]const Id) Error!Id {
        if (tag == .nominal and a == @import("../check/task_types.zig").handle.unit and b == @import("../check/task_types.zig").handle.decl) return self.intern(.product, 0, 0, &.{ types.u32_type, types.u32_type });
        if (tag == .nominal and @import("../check/typed_staging.zig").isIdentity(a, b)) return error.UnresolvedType;
        if (tag != .state_provider and tag != .scoped and tag != .opened and tag != .associated and ((row != unknown_row and row >= self.effects.rows.items.len) or (row != 0 and tag != .function and tag != .demand and tag != .provider))) return error.TypeMismatch;
        if (tag == .owning and (a == 0 or a >= self.nodes.items.len or row != 0 or values.len != 0 or (b != @backingInt(types.UsageKind.unique) and b != @backingInt(@import("../check/types.zig").UsageKind.shared)))) return error.TypeMismatch;
        if (tag == .scoped and (a == 0 or a >= self.nodes.items.len or self.node(a).tag != .nominal or b == 0 or row == 0 or values.len != 0)) return error.TypeMismatch;
        if (tag == .state_provider and (a == 0 or b == 0 or row == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len or row >= self.nodes.items.len or values.len != 0)) return error.TypeMismatch;
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&a));
        hash.update(std.mem.asBytes(&b));
        hash.update(std.mem.asBytes(&row));
        hash.update(std.mem.sliceAsBytes(values));
        if (tag == .universal) {
            const dictionary_abi = slots != null;
            hash.update(std.mem.asBytes(&dictionary_abi));
            if (slots) |members| hash.update(std.mem.sliceAsBytes(members));
        }
        const fingerprint = hash.final();
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate]) {
            const n = self.node(candidate);
            const same = n.tag == tag and switch (tag) {
                .product, .record => std.mem.eql(u32, self.children(candidate), values),
                .nominal, .universal, .existential => n.a == a and n.b == b and std.mem.eql(u32, self.children(candidate), values),
                else => n.a == a and n.b == b and n.c == row,
            };
            if (!same) continue;
            if (tag == .universal) {
                if (self.hasDictionaryABI(candidate) != (slots != null)) continue;
                if (slots) |members| if (!std.mem.eql(Id, members, self.dictionarySlots(candidate))) continue;
            }
            return candidate;
        }
        if (self.nodes.items.len == std.math.maxInt(u32) or values.len >= std.math.maxInt(u32) or self.extra.items.len > std.math.maxInt(u32) - values.len - 1) return error.LayoutLimit;
        const slot_count = if (slots) |members| members.len else 0;
        if (self.extra.items.len + values.len + 1 > std.math.maxInt(u32) - slot_count) return error.LayoutLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        try self.extra.ensureUnusedCapacity(self.allocator, values.len + 1 + slot_count);
        if (slots != null) try self.universal_dictionaries.ensureUnusedCapacity(self.allocator, 1);
        var n: Node = .{ .tag = tag, .a = a, .b = b, .c = row };
        switch (tag) {
            .product, .record => {
                n.a = @intCast(self.extra.items.len);
                n.b = @intCast(if (tag == .record) values.len / 2 else values.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .universal, .existential => {
                n.c = @intCast(self.extra.items.len);
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
        if (slots) |members| {
            self.universal_dictionaries.appendAssumeCapacity(.{ .owner = id, .start = @intCast(self.extra.items.len), .len = @intCast(members.len) });
            self.extra.appendSliceAssumeCapacity(members);
        }
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
    /// Copy physical shapes out of one solved live region. Open semantic rows
    /// remain unknown, and unresolved types remain erased. No solver IDs or
    /// mutable substitution histories are retained in the representation store.
    pub fn fromSolver(self: *Store, source: *types.Store, ty: types.Id) Error!Id {
        var budget: usize = 1_000_000;
        return self.fromSolverDepth(source, ty, 0, &budget);
    }
    fn fromSolverDepth(self: *Store, source: *types.Store, ty: types.Id, depth: usize, budget: *usize) Error!Id {
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        const root = source.resolve(ty, 0) catch |err| return solverError(err);
        const n = source.node(root);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => return root,
            .variable => return erased,
            .usage => {
                const payload = try self.fromSolverDepth(source, n.a, depth + 1, budget);
                if (n.b == @backingInt(types.UsageKind.unique) or n.b == @backingInt(@import("../check/types.zig").UsageKind.shared)) return self.intern(.owning, payload, n.b, &.{});
                return payload;
            },
            .forall, .existential => {
                if (n.c == 0 or n.c > 128) return error.LayoutLimit;
                const owned = try self.allocator.dupe(types.Id, source.list(.{ .start = n.b, .len = n.c }));
                defer self.allocator.free(owned);
                var binders: [128]Id = undefined;
                for (owned, binders[0..n.c], 0..) |formal, *binder, ordinal| {
                    const leaf = source.node(formal);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    binder.* = try self.internWithEffects(.opened, @intCast(ordinal), 0, leaf.b, &.{});
                }
                if (self.solver_owners.items.len >= 128) return error.LayoutLimit;
                try self.solver_owners.append(self.allocator, owned);
                defer _ = self.solver_owners.pop();
                var tag: Tag = .existential;
                if (n.tag == .forall) tag = .universal;
                return self.intern(tag, try self.fromSolverDepth(source, n.a, depth + 1, budget), n.c, binders[0..n.c]);
            },
            .bound => {
                if (n.a >= 128 or n.b > 2 or n.c != 0) return error.UnresolvedType;
                var index = self.solver_owners.items.len;
                while (index != 0) {
                    index -= 1;
                    const owner = self.solver_owners.items[index];
                    if (n.a >= owner.len or owner[n.a] != root) continue;
                    return self.internWithEffects(.opened, n.a, @intCast(self.solver_owners.items.len - 1 - index), n.b, &.{});
                }
                return self.internWithEffects(.opened, n.a, 0, n.b, &.{});
            },
            .instance_version, .rigid, .absent, .projection, .instance_selection => return error.UnresolvedType,
            .erased_proof => return self.intern(.erased_proof, 0, 0, &.{}),
            .scoped => return self.intern(.nominal, std.math.maxInt(u32), capability_layout_decl, &.{}),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .array, .list, .cursor, .resolver => return self.intern(switch (n.tag) {
                .array => .array,
                .list => .list,
                .cursor => .cursor,
                else => .resolver,
            }, try self.fromSolverDepth(source, n.a, depth + 1, budget), 0, &.{}),
            .function, .demand, .provider => return self.internWithEffects(switch (n.tag) {
                .function => .function,
                .demand => .demand,
                else => .provider,
            }, try self.fromSolverDepth(source, n.a, depth + 1, budget), if (n.tag == .function) try self.fromSolverDepth(source, n.b, depth + 1, budget) else 0, try self.fromSolverRow(source, n.c, depth + 1, budget), &.{}),
            .state_provider => return self.internStateProvider(try self.fromSolverDepth(source, n.a, depth + 1, budget), try self.fromSolverDepth(source, n.b, depth + 1, budget), try self.fromSolverDepth(source, n.c, depth + 1, budget)),
            .product, .record, .nominal => {
                if (n.tag == .nominal and n.a == @import("../check/task_types.zig").handle.unit and n.b == @import("../check/task_types.zig").handle.decl) return self.intern(.product, 0, 0, &.{ types.u32_type, types.u32_type });
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(allocator);
                if (n.tag == .record) {
                    for (0..n.b) |i| {
                        const field = source.recordField(n, i);
                        try values.append(allocator, field.name);
                        try values.append(allocator, try self.fromSolverDepth(source, field.ty, depth + 1, budget));
                    }
                    return self.internRecord(values.items);
                }
                const children_ = try allocator.dupe(types.Id, if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b }));
                defer allocator.free(children_);
                for (children_) |child| try values.append(allocator, try self.fromSolverDepth(source, child, depth + 1, budget));
                return self.intern(if (n.tag == .product) .product else .nominal, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    fn fromSolverRow(self: *Store, source: *types.Store, row: types.Effects.Id, depth: usize, budget: *usize) Error!u32 {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const temporary = scratch.allocator();
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        const root = source.resolveEffects(row, 0) catch |err| return solverError(err);
        const tail = source.row(root).tail;
        if (tail != .closed and tail != .formal) return unknown_row;
        var formal: Id = 0;
        if (tail == .formal) {
            formal = try self.fromSolverDepth(source, tail.formal, depth + 1, budget);
            if (self.node(formal).tag != .opened or self.node(formal).c != 1) return error.TypeMismatch;
        }
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(temporary);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(temporary);
        const source_labels = try temporary.dupe(types.Effects.Label, source.rowLabels(root));
        defer temporary.free(source_labels);
        for (source_labels) |label| {
            arguments.clearRetainingCapacity();
            const source_arguments = try temporary.dupe(types.Id, source.operationArguments(label));
            defer temporary.free(source_arguments);
            const identity = source.operation(label).identity;
            for (source_arguments) |argument| try arguments.append(temporary, try self.fromSolverDepth(source, argument, depth + 1, budget));
            try labels.append(temporary, self.effects.internOperationInstance(identity, arguments.items, types.selectionAtom(source, source.operation(label).instance)) catch |err| return effectError(err));
        }
        return self.effects.internRowWithFormal(labels.items, formal) catch |err| return effectError(err);
    }
    fn solverError(err: types.Error) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.TypeMismatch => error.TypeMismatch,
            else => error.LayoutLimit,
        };
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
        return self.toEvidenceDepth(target, id, 0, &budget, 0);
    }
    fn toEvidenceDepth(self: *const Store, target: *evidence.Store, id: Id, depth: usize, budget: *usize, bound_arity: u32) evidence.Error!evidence.Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (id == 0 or id >= self.nodes.items.len) return error.UnresolvedType;
        const n = self.node(id);
        if (n.tag == .nominal and n.a == std.math.maxInt(u32) and n.b == capability_layout_decl) return error.UnresolvedType;
        switch (n.tag) {
            .invalid, .erased, .associated => return error.UnresolvedType,
            .opened => {
                if (n.b == 0 and n.a >= bound_arity) return error.UnresolvedType;
                if (n.b >= 128) return error.UnresolvedType;
                return target.internWithEffects(.bound, n.a, n.c, n.b, &.{});
            },
            .universal, .existential => {
                if (self.hasDictionaryABI(id)) return error.UnresolvedType;
                var binders: [128]evidence.Id = undefined;
                for (self.children(id), binders[0..n.b]) |formal, *binder| binder.* = try self.toEvidenceDepth(target, formal, depth + 1, budget, n.b);
                var tag: evidence.Tag = .existential;
                if (n.tag == .universal) tag = .forall;
                return target.intern(tag, try self.toEvidenceDepth(target, n.a, depth + 1, budget, n.b), n.b, binders[0..n.b]);
            },
            .erased_proof => return target.intern(.erased_proof, 0, 0, &.{}),
            .unit, .boolean, .u32, .f32, .never => return id,
            .owning => return target.intern(.usage, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), n.b, &.{}),
            .array => return target.intern(.array, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, &.{}),
            .list => return target.intern(.list, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, &.{}),
            .cursor => return target.intern(.cursor, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, &.{}),
            .demand => return target.internWithEffects(.demand, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, try self.toEvidenceRow(target, n.c, depth + 1, budget, bound_arity), &.{}),
            .type_constructor => return target.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return target.intern(.resolver, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, &.{}),
            .scoped => return target.internWithEffects(.scoped, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), n.b, n.c, &.{}),
            .provider => return target.internWithEffects(.provider, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), 0, try self.toEvidenceRow(target, n.c, depth + 1, budget, bound_arity), &.{}),
            .state_provider => return target.internStateProvider(try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), try self.toEvidenceDepth(target, n.b, depth + 1, budget, bound_arity), try self.toEvidenceDepth(target, n.c, depth + 1, budget, bound_arity)),
            .function => return target.internWithEffects(.function, try self.toEvidenceDepth(target, n.a, depth + 1, budget, bound_arity), try self.toEvidenceDepth(target, n.b, depth + 1, budget, bound_arity), try self.toEvidenceRow(target, n.c, depth + 1, budget, bound_arity), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, target.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(u32) = .empty;
                defer values.deinit(allocator);
                for (self.children(id), 0..) |child, index| {
                    try values.append(allocator, if (n.tag == .record and index % 2 == 0) child else try self.toEvidenceDepth(target, child, depth + 1, budget, bound_arity));
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
        if (n.tag == .nominal and n.a == std.math.maxInt(u32) and n.b == capability_layout_decl) return 0;
        switch (n.tag) {
            // Partial machine expectations cannot identify a semantic member.
            .associated => return 0,
            .universal, .existential => {
                if (self.hasDictionaryABI(id)) return error.UnresolvedType;
                var binders: [128]code_expectation.Id = undefined;
                for (self.children(id), binders[0..n.b]) |formal, *binder| binder.* = try self.toExpectationDepth(target, formal, depth + 1, budget);
                var tag: code_expectation.Tag = .existential;
                if (n.tag == .universal) tag = .forall;
                return self.internExpectation(target, tag, try self.toExpectationDepth(target, n.a, depth + 1, budget), n.b, binders[0..n.b]);
            },
            .scoped => return 0,
            .owning => return self.internExpectation(target, .usage, try self.toExpectationDepth(target, n.a, depth + 1, budget), n.b, &.{}),
            .opened => return target.internBound(n.a, n.c, n.b) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.LayoutLimit,
            .invalid => return error.UnresolvedType,
            .erased => return 0,
            .erased_proof => return self.internExpectation(target, .erased_proof, 0, 0, &.{}),
            .unit, .boolean, .u32, .f32, .never => return id,
            .array => return self.internExpectation(target, .array, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .list => return self.internExpectation(target, .list, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
            .cursor => return self.internExpectation(target, .cursor, try self.toExpectationDepth(target, n.a, depth + 1, budget), 0, &.{}),
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
            .projection => {
                const descriptor = view.projection(id);
                return self.internAssociated(descriptor.goal, descriptor.member, descriptor.scope);
            },
            .forall, .existential => {
                var binders: [128]Id = undefined;
                if (n.b == 0 or n.b > binders.len) return error.TypeMismatch;
                for (view.children(id), binders[0..n.b]) |formal, *binder| binder.* = try self.fromEvidenceDepth(view, formal, depth + 1, budget);
                var tag: Tag = .existential;
                if (n.tag == .forall) tag = .universal;
                return self.intern(tag, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), n.b, binders[0..n.b]);
            },
            .bound => return self.internWithEffects(.opened, n.a, n.c, n.b, &.{}),
            .usage => {
                const payload = try self.fromEvidenceDepth(view, n.a, depth + 1, budget);
                if (n.b == @backingInt(types.UsageKind.unique) or n.b == @backingInt(@import("../check/types.zig").UsageKind.shared)) return self.intern(.owning, payload, n.b, &.{});
                return payload;
            },
            .erased_proof => return self.intern(.erased_proof, 0, 0, &.{}),
            .absent => return error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => return id,
            .array => return self.intern(.array, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .list => return self.intern(.list, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .cursor => return self.intern(.cursor, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return self.intern(.resolver, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), 0, &.{}),
            .scoped => return self.intern(.nominal, std.math.maxInt(u32), capability_layout_decl, &.{}),
            .provider => return self.internWithEffects(.provider, try self.fromEvidenceToken(view, n.a, depth + 1, budget), 0, try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .state_provider => return self.internStateProvider(try self.fromEvidenceToken(view, n.a, depth + 1, budget), try self.fromEvidenceToken(view, n.b, depth + 1, budget), try self.fromEvidenceDepth(view, n.c, depth + 1, budget)),
            .function => return self.internWithEffects(.function, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), try self.fromEvidenceDepth(view, n.b, depth + 1, budget), try self.fromEvidenceRow(view, n.c, depth + 1, budget), &.{}),
            .product, .record, .nominal => {
                if (n.tag == .nominal and n.a == @import("../check/task_types.zig").handle.unit and n.b == @import("../check/task_types.zig").handle.decl) return self.intern(.product, 0, 0, &.{ types.u32_type, types.u32_type });
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
    fn fromEvidenceToken(self: *Store, view: evidence.View, ty: evidence.Id, depth: usize, budget: *usize) Error!Id {
        const n = view.node(ty);
        if (n.tag != .scoped) return self.fromEvidenceDepth(view, ty, depth, budget);
        return self.internWithEffects(.scoped, try self.fromEvidenceDepth(view, n.a, depth + 1, budget), n.b, n.c, &.{});
    }
    fn fromTypeToken(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!Id {
        const n = module.types.node(ty);
        if (n.tag != .scoped) return self.fromTypeDepth(module, ty, mappings, rows, depth, allow_erased);
        const instance = types.selectionAtom(module.types, mappedInstance(.{ .unit = n.b, .decl = n.c }, mappings));
        if (instance.unit == 0 or instance.decl == 0) return error.UnresolvedType;
        return self.internWithEffects(.scoped, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), instance.unit, instance.decl, &.{});
    }
    fn fromTypeDepth(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!Id {
        if (depth >= 1024) return error.LayoutLimit;
        for (mappings) |mapping| if (mapping.variable == ty) return mapping.layout;
        // A closed type's layout ignores the substitutions and the erasure
        // policy; only the first derivation of each one walks it.
        const key = try self.closed.key(self.allocator, module, ty) orelse return self.fromTypeNode(module, ty, mappings, rows, depth, allow_erased);
        if (comptime @import("builtin").mode.runtimeSafety()) self.closed.checkSubstitutions(module, mappings);
        if (self.closed.layouts.get(key)) |cached| return cached;
        const result = try self.fromTypeNode(module, ty, mappings, rows, depth, allow_erased);
        try self.closed.layouts.put(self.allocator, key, result);
        return result;
    }
    fn fromTypeNode(self: *Store, module: *const core.Module, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!Id {
        const n = module.types.node(ty);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => return ty,
            .variable => return if (allow_erased) erased else error.UnresolvedType,
            .usage => {
                const payload = try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased);
                if (n.b == @backingInt(types.UsageKind.unique) or n.b == @backingInt(@import("../check/types.zig").UsageKind.shared)) return self.intern(.owning, payload, n.b, &.{});
                return payload;
            },
            .bound => return error.UnresolvedType,
            .forall, .existential => {
                if (n.c == 0 or n.c > 128 or depth >= 128) return error.LayoutLimit;
                if (self.type_owners.items.len >= 128) return error.LayoutLimit;
                try self.type_owners.append(self.allocator, ty);
                defer _ = self.type_owners.pop();
                var owned: std.ArrayList(Mapping) = .empty;
                defer owned.deinit(self.allocator);
                for (module.types.list(.{ .start = n.b, .len = n.c }), 0..) |binder, ordinal| {
                    const leaf = module.types.node(binder);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    try owned.append(self.allocator, .{ .variable = binder, .layout = try self.internWithEffects(.opened, @intCast(ordinal), 0, leaf.b, &.{}) });
                }
                for (mappings) |mapping| {
                    var outer = mapping;
                    const representation = self.node(mapping.layout);
                    if (representation.tag == .opened) {
                        if (representation.b >= 127) return error.LayoutLimit;
                        outer.layout = try self.internWithEffects(.opened, representation.a, representation.b + 1, representation.c, &.{});
                    }
                    try owned.append(self.allocator, outer);
                }
                var tag: Tag = .existential;
                if (n.tag == .forall) tag = .universal;
                var binders: [128]Id = undefined;
                for (owned.items[0..n.c], binders[0..n.c]) |mapping, *binder| binder.* = mapping.layout;
                return self.intern(tag, try self.fromTypeDepth(module, n.a, owned.items, rows, depth + 1, allow_erased), n.c, binders[0..n.c]);
            },
            .projection => {
                const arguments = module.types.nominalArguments(n);
                var scope = self.type_owners.items.len;
                while (scope != 0) {
                    scope -= 1;
                    const owner = self.type_owners.items[scope];
                    for (module.types.quantifierGoals(owner), 0..) |goal, ordinal| {
                        if (goal.kind != .contract or goal.identity.unit != n.a or goal.identity.decl != n.b) continue;
                        const tuple = module.types.node(goal.ty);
                        if (tuple.tag != .product or tuple.b != arguments.len) continue;
                        var matches = true;
                        for (module.types.list(.{ .start = tuple.a, .len = tuple.b }), arguments) |expected, actual| {
                            if (!(@import("../check/rank_equal.zig").equal(&module.types, expected, actual, true) catch return error.LayoutLimit)) matches = false;
                        }
                        if (!matches) continue;
                        const member_name = module.types.projectionMember(n);
                        for (module.contracts) |contract| {
                            if (contract.identity.unit != n.a or contract.identity.decl != n.b) continue;
                            if (contract.members.start > module.contract_members.len or contract.members.len > module.contract_members.len - contract.members.start) return error.UnresolvedType;
                            for (module.contract_members[contract.members.start..][0..contract.members.len]) |member| {
                                if (member.name == member_name and member.kind != .value) return self.internAssociated(@intCast(ordinal), member_name, @intCast(self.type_owners.items.len - 1 - scope));
                            }
                        }
                        return error.UnresolvedType;
                    }
                }
                return error.UnresolvedType;
            },
            .instance_version, .rigid, .absent, .instance_selection => return error.UnresolvedType,
            .erased_proof => return self.intern(.erased_proof, 0, 0, &.{}),
            .scoped => return self.intern(.nominal, std.math.maxInt(u32), capability_layout_decl, &.{}),
            .array => return self.intern(.array, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .list => return self.intern(.list, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .cursor => return self.intern(.cursor, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .resolver => return self.intern(.resolver, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), 0, &.{}),
            .provider => return self.internWithEffects(.provider, try self.fromTypeToken(module, n.a, mappings, rows, depth + 1, allow_erased), 0, try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .state_provider => return self.internStateProvider(try self.fromTypeToken(module, n.a, mappings, rows, depth + 1, allow_erased), try self.fromTypeToken(module, n.b, mappings, rows, depth + 1, allow_erased), try self.fromTypeDepth(module, n.c, mappings, rows, depth + 1, allow_erased)),
            .function => return self.internWithEffects(.function, try self.fromTypeDepth(module, n.a, mappings, rows, depth + 1, allow_erased), try self.fromTypeDepth(module, n.b, mappings, rows, depth + 1, allow_erased), try self.fromTypeRow(module, n.c, mappings, rows, depth + 1, allow_erased), &.{}),
            .product, .record, .nominal => {
                if (n.tag == .nominal and n.a == @import("../check/task_types.zig").handle.unit and n.b == @import("../check/task_types.zig").handle.decl) return self.intern(.product, 0, 0, &.{ types.u32_type, types.u32_type });
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
        return self.toEvidenceRow(target, row, 0, &budget, 0);
    }
    pub fn rowFromEvidence(self: *Store, view: evidence.View, row: evidence.Effects.Id) Error!evidence.Effects.Id {
        var budget: usize = 1_000_000;
        return self.fromEvidenceRow(view, row, 0, &budget);
    }
    fn toEvidenceRow(self: *const Store, target: *evidence.Store, row: evidence.Effects.Id, depth: usize, budget: *usize, bound_arity: u32) evidence.Error!evidence.Effects.Id {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, target.allocator);
        const temporary = scratch.allocator();
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        if (row == unknown_row) return error.UnresolvedType;
        budget.* -= 1;
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(temporary);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(temporary);
        for (self.effects.view().rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (self.effects.view().operationArguments(label)) |argument| try arguments.append(temporary, try self.toEvidenceDepth(target, argument, depth + 1, budget, bound_arity));
            try labels.append(temporary, try target.effects.internOperationInstance(self.effects.view().operation(label).identity, arguments.items, self.effects.view().operation(label).instance));
        }
        const old_formal = self.effects.rows.items[row].formal;
        var formal: evidence.Id = 0;
        if (old_formal != 0) formal = try self.toEvidenceDepth(target, old_formal, depth + 1, budget, bound_arity);
        return target.effects.internRowWithFormal(labels.items, formal);
    }
    fn fromEvidenceRow(self: *Store, view: evidence.View, row: evidence.Effects.Id, depth: usize, budget: *usize) Error!evidence.Effects.Id {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const temporary = scratch.allocator();
        if (row >= view.effects.rows.len) return error.UnresolvedType;
        if (depth >= 1024 or budget.* == 0) return error.LayoutLimit;
        budget.* -= 1;
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(temporary);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(temporary);
        for (view.effects.rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (view.effects.operationArguments(label)) |argument| try arguments.append(temporary, try self.fromEvidenceDepth(view, argument, depth + 1, budget));
            const mapped = self.effects.internOperationInstance(view.effects.operation(label).identity, arguments.items, view.effects.operation(label).instance) catch |err| return effectError(err);
            try labels.append(temporary, mapped);
        }
        const old_formal = view.effects.rows[row].formal;
        var formal: Id = 0;
        if (old_formal != 0) formal = try self.fromEvidenceDepth(view, old_formal, depth + 1, budget);
        return self.effects.internRowWithFormal(labels.items, formal) catch |err| return effectError(err);
    }
    fn fromTypeRow(self: *Store, module: *const core.Module, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, allow_erased: bool) Error!evidence.Effects.Id {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const temporary = scratch.allocator();
        if (depth >= 1024) return error.LayoutLimit;
        const tail = module.types.row(row).tail;
        var suffix: evidence.Effects.Id = 0;
        var formal: Id = 0;
        switch (tail) {
            .closed => {},
            .formal => |binder| {
                const key = types.formalRowKey(binder) catch return error.UnresolvedType;
                var replaced = false;
                for (rows) |mapping| if (mapping.variable == key) {
                    if (mapping.row == unknown_row) return if (allow_erased) unknown_row else error.UnresolvedType;
                    if (mapping.row >= self.effects.rows.items.len) return error.TypeMismatch;
                    suffix = mapping.row;
                    replaced = true;
                    break;
                };
                if (!replaced) {
                    formal = try self.fromTypeDepth(module, binder, mappings, rows, depth + 1, allow_erased);
                    const leaf = self.node(formal);
                    if (leaf.tag != .opened or leaf.c != 1) return error.TypeMismatch;
                }
            },
            .parameter => return if (allow_erased) unknown_row else error.UnresolvedType,
            .variable => |variable| {
                var found = false;
                for (rows) |mapping| if (mapping.variable == variable) {
                    if (mapping.row == unknown_row) return if (allow_erased) unknown_row else error.UnresolvedType;
                    if (mapping.row >= self.effects.rows.items.len) return error.TypeMismatch;
                    suffix = mapping.row;
                    found = true;
                    break;
                };
                if (!found) return if (allow_erased) unknown_row else error.UnresolvedType;
            },
        }
        var labels: std.ArrayList(u32) = .empty;
        defer labels.deinit(temporary);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(temporary);
        for (module.types.rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (module.types.operationArguments(label)) |argument| try arguments.append(temporary, try self.fromTypeDepth(module, argument, mappings, rows, depth + 1, allow_erased));
            const mapped = self.effects.internOperationInstance(module.types.operation(label).identity, arguments.items, types.selectionAtom(module.types, mappedInstance(module.types.operation(label).instance, mappings))) catch |err| return effectError(err);
            try labels.append(temporary, mapped);
        }
        try labels.appendSlice(temporary, self.effects.view().rowLabels(suffix));
        if (suffix != 0) formal = self.effects.rows.items[suffix].formal;
        return self.effects.internRowWithFormal(labels.items, formal) catch |err| return effectError(err);
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
    // Exceed local row-conversion scratch, then use the retained result after
    // that scratch is gone. Repeated labels keep order and multiplicity.
    const wide_labels: [129]u32 = @splat(operation);
    const wide_row = try semantic.effects.internRow(&wide_labels);
    const wide_layout = try layouts.rowFromEvidence(semantic.view(), wide_row);
    try std.testing.expectEqual(@as(usize, wide_labels.len), layouts.effects.view().rowLabels(wide_layout).len);
    try std.testing.expectEqual(wide_row, try layouts.rowToEvidence(&semantic, wide_layout));
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectLayoutScenario, .{});
}

fn solverLayoutScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    var source_alive = true;
    defer if (source_alive) source.deinit();
    var layouts = try Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    const result = try source.fresh();
    const tail = try source.freshEffects();
    const phantom = try source.nominal(.{ .unit = 3, .decl = 9 }, &.{types.f32_type});
    const operation = try source.internOperation(.{ .unit = 2, .decl = 8 }, &.{phantom});
    const open = source.effects.row(&.{ operation, operation }, source.row(tail).tail) catch |err| return types.effectError(err);
    const callback = try source.functionWithEffects(types.u32_type, result, open);
    const shape = try source.record(&.{ .{ .name = 99, .ty = callback }, .{ .name = 7, .ty = try source.array(result) } });
    const point = source.mark();
    const initial = try layouts.fromSolver(&source, shape);
    const initial_callback = layouts.children(initial)[3];
    try std.testing.expectEqual(erased, layouts.node(initial_callback).b);
    try std.testing.expectEqual(unknown_row, layouts.node(initial_callback).c);
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, initial));

    try source.unify(result, types.f32_type);
    try source.unifyEffects(tail, 0);
    const closed = try layouts.fromSolver(&source, shape);
    const closed_callback = layouts.children(closed)[3];
    try std.testing.expectEqual(types.f32_type, layouts.node(closed_callback).b);
    const labels = layouts.effects.view().rowLabels(layouts.node(closed_callback).c);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(types.NominalIdentity{ .unit = 2, .decl = 8 }, layouts.effects.view().operation(labels[0]).identity);
    const argument = layouts.effects.view().operationArguments(labels[0])[0];
    try std.testing.expectEqualSlices(u32, &.{types.f32_type}, layouts.children(argument));
    const closed_evidence = try layouts.toEvidence(&semantic, closed);
    try std.testing.expectEqual(closed, try layouts.mergePartial(initial, closed));
    try std.testing.expectEqual(closed, try layouts.mergePartial(closed, initial));
    const pure_callback = try layouts.internWithEffects(.function, layouts.node(closed_callback).a, layouts.node(closed_callback).b, 0, &.{});
    try std.testing.expectError(error.TypeMismatch, layouts.mergePartial(closed_callback, pure_callback));

    source.rollback(point);
    try std.testing.expectEqual(initial, try layouts.fromSolver(&source, shape));
    try source.unify(result, types.u32_type);
    try source.unifyEffects(tail, 0);
    const different = try layouts.fromSolver(&source, shape);
    try std.testing.expect(closed != different);
    try std.testing.expectError(error.TypeMismatch, layouts.mergePartial(closed, different));
    source.deinit();
    source_alive = false;
    // The region can disappear and recycle every numeric solver ID; copied
    // shapes remain owned, and open effects never become a pure certificate.
    try std.testing.expectEqual(closed_evidence, try layouts.toEvidence(&semantic, closed));
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, initial));
    try std.testing.expectEqual(types.u32_type, layouts.node(layouts.children(different)[3]).b);
}
test "solved representation projection owns partial shapes without certifying open effects" {
    try solverLayoutScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, solverLayoutScenario, .{});
}

fn scopedDescriptorCarrierLaw(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const family = try source.nominal(.{ .unit = 3, .decl = 5 }, &.{types.u32_type});
    const formal = try source.capabilityParameter(family);
    const owner = source.node(formal).c;
    const descriptor = try source.nominal(.{ .unit = 3, .decl = 11 }, &.{types.u32_type});
    const operation = try source.scoped(descriptor, .{ .unit = 0, .decl = owner });
    const provider = try source.provider(operation, 0);
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    const actual_family = try semantic.intern(.nominal, 3, 5, &.{types.u32_type});
    const actual_owner = try semantic.internWithEffects(.scoped, actual_family, 3, 71, &.{});
    var mappings: std.ArrayList(evidence.Mapping) = .empty;
    defer mappings.deinit(allocator);
    try mappings.append(allocator, .{ .variable = owner, .evidence = actual_owner });
    const projected = try semantic.project(&source, provider, mappings.items);
    const scoped = semantic.node(semantic.node(projected).a);
    try std.testing.expectEqual(evidence.Tag.scoped, scoped.tag);
    try std.testing.expectEqual(@as(u32, 71), scoped.c);
    try std.testing.expectEqual(@as(u32, 11), semantic.node(scoped.a).b);
    var rows: std.ArrayList(evidence.RowMapping) = .empty;
    defer rows.deinit(allocator);
    // A family and its operation share one owner, not one descriptor shape.
    try std.testing.expect(try semantic.matchWithRows(&source, provider, projected, &mappings, &rows));
    const wrong_operation = try semantic.internWithEffects(.scoped, scoped.a, 3, 72, &.{});
    const wrong_provider = try semantic.internWithEffects(.provider, wrong_operation, 0, 0, &.{});
    try std.testing.expect(!try semantic.matchWithRows(&source, provider, wrong_provider, &mappings, &rows));
    var physical = try Store.init(allocator);
    defer physical.deinit();
    const shape = try physical.fromEvidence(semantic.view(), projected);
    const token = physical.node(physical.node(shape).a);
    try std.testing.expectEqual(Tag.scoped, token.tag);
    try std.testing.expectEqual(@as(u32, 71), token.c);
    try std.testing.expectEqual(projected, try physical.toEvidence(&semantic, shape));
    const standalone = try physical.fromEvidence(semantic.view(), actual_owner);
    try std.testing.expectError(error.UnresolvedType, physical.toEvidence(&semantic, standalone));
    var copied = try evidence.Store.init(allocator);
    defer copied.deinit();
    var importer: @import("../eval/semantic_evidence_import.zig").Importer = .{ .allocator = allocator, .source = semantic.view(), .destination = &copied, .max_depth = 128 };
    defer importer.deinit();
    const transferred = try importer.ty(projected, 0);
    try std.testing.expectEqual(scoped.c, copied.node(copied.node(transferred).a).c);
    var inference = try types.Store.init(allocator);
    defer inference.deinit();
    var closed: @import("../eval/closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = copied.view(), .destination = &inference };
    defer closed.deinit();
    const imported = try closed.ty(transferred, 0);
    const imported_owner = inference.node(inference.node(imported).a);
    try std.testing.expectEqual(types.Tag.scoped, imported_owner.tag);
    try std.testing.expectEqual(@as(u32, 71), imported_owner.c);
}
test "scoped descriptor carriers retain exact owners independently from operation shapes through OOM" {
    try scopedDescriptorCarrierLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedDescriptorCarrierLaw, .{});
}

fn invocationDescriptorLaw(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const family = try source.nominal(.{ .unit = 3, .decl = 5 }, &.{types.u32_type});
    const left = try source.scoped(family, .{ .unit = 3, .decl = 11 });
    const right = try source.scoped(family, .{ .unit = 3, .decl = 12 });
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    var physical = try Store.init(allocator);
    defer physical.deinit();
    var previous: types.Id = 0;
    var prior_evidence: evidence.Id = 0;
    for ([_]u32{ 41, 42, 41 }) |point| {
        const version = try source.instanceVersion(.{ .unit = 7, .decl = point }, 0);
        const selected = try source.instanceSelection(.{ .unit = 3, .decl = 19 }, &.{ left, right, version });
        const scope = try source.scoped(family, .{ .unit = 0, .decl = selected });
        const token = try source.provider(scope, 0);
        const projected = try semantic.project(&source, token, &.{});
        const shape = try physical.fromEvidence(semantic.view(), projected);
        try std.testing.expectEqual(projected, try physical.toEvidence(&semantic, shape));
        const actual = semantic.node(semantic.node(projected).a);
        try std.testing.expectEqual(@as(u32, 7), actual.b);
        try std.testing.expectEqual(@as(u32, 0x40000000 | (point << 4)), actual.c);
        const operation = try source.internScopedOperation(.{ .unit = 3, .decl = 7 }, .{ .unit = 0, .decl = selected }, &.{types.u32_type});
        const row = try source.effects.row(&.{operation}, .closed);
        const callable = try source.functionWithEffects(types.unit, types.u32_type, row);
        const arrow = try semantic.project(&source, callable, &.{});
        const labels = semantic.effects.view().rowLabels(semantic.node(arrow).c);
        try std.testing.expectEqual(@as(usize, 1), labels.len);
        try std.testing.expectEqual(types.NominalIdentity{ .unit = actual.b, .decl = actual.c }, semantic.effects.view().operation(labels[0]).instance);
        var mappings: std.ArrayList(evidence.Mapping) = .empty;
        defer mappings.deinit(allocator);
        var rows: std.ArrayList(evidence.RowMapping) = .empty;
        defer rows.deinit(allocator);
        try std.testing.expect(try semantic.matchWithRows(&source, callable, arrow, &mappings, &rows));
        if (previous != 0) {
            try std.testing.expectError(error.TypeMismatch, source.unify(previous, scope));
            try std.testing.expect(projected != prior_evidence);
        }
        previous = scope;
        prior_evidence = projected;
    }
}
test "invocation descriptor versions remain distinct in semantic and physical owners through OOM" {
    try invocationDescriptorLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, invocationDescriptorLaw, .{});
}

test "owning layout preserves qualifiers across semantic and code projection without scalar ABI erasure" {
    var source = try types.Store.init(std.testing.allocator);
    defer source.deinit();
    var physical = try Store.init(std.testing.allocator);
    defer physical.deinit();
    var semantic = try evidence.Store.init(std.testing.allocator);
    defer semantic.deinit();
    var expected = try code_expectation.Store.init(std.testing.allocator);
    defer expected.deinit();
    const unique = try source.usage(types.f32_type, .unique, 0);
    const shared = try source.usage(types.f32_type, .shared, 0);
    const unique_layout = try physical.fromSolver(&source, unique);
    const shared_layout = try physical.fromSolver(&source, shared);
    try std.testing.expectEqual(Tag.owning, physical.node(unique_layout).tag);
    try std.testing.expectEqual(wasm.ValueType.i32, physical.machine(unique_layout));
    try std.testing.expect(physical.abi(unique_layout) == null);
    try std.testing.expect(physical.scalar(unique_layout) == null);
    try std.testing.expect(unique_layout != shared_layout);
    try std.testing.expectError(error.TypeMismatch, physical.mergePartial(unique_layout, shared_layout));
    const projected = try physical.toEvidence(&semantic, unique_layout);
    try std.testing.expectEqual(evidence.Tag.usage, semantic.view().node(projected).tag);
    try std.testing.expectEqual(@backingInt(types.UsageKind.unique), semantic.view().node(projected).b);
    try std.testing.expectEqual(unique_layout, try physical.fromEvidence(semantic.view(), projected));
    const code = try physical.toCodeExpectation(&expected, unique_layout);
    try std.testing.expectEqual(code_expectation.Tag.usage, expected.view().node(code).tag);
}

test "selected owning layout discovery preserves generic substitutions and visits shared graphs once" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    var ordinary: Id = 3;
    for (0..100) |_| ordinary = try store.intern(.product, 0, 0, &.{ ordinary, ordinary });
    try std.testing.expect(!try store.hasOwners(ordinary));
    const owner = try store.intern(.owning, 3, @backingInt(@import("../check/types.zig").UsageKind.shared), &.{});
    const wrapped = try store.intern(.record, 0, 0, &.{ 0, owner });
    try std.testing.expect(try store.hasOwners(wrapped));
    const arrow = try store.intern(.function, owner, 3, &.{});
    try std.testing.expect(try store.hasOwners(arrow));
}

test "selected owning layout discovery bounds unique nodes before queueing wide repeated fields" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    var fields: [4097]Id = undefined;
    @memset(&fields, 3);
    const product = try store.intern(.product, 0, 0, &fields);
    var record_fields: [4097 * 2]Id = undefined;
    for (0..4097) |index| {
        record_fields[index * 2] = @intCast(index);
        record_fields[index * 2 + 1] = 3;
    }
    const record = try store.intern(.record, 0, 0, &record_fields);
    const owner = try store.intern(.owning, 3, @backingInt(types.UsageKind.shared), &.{});
    record_fields[record_fields.len - 1] = owner;
    const owned_record = try store.intern(.record, 0, 0, &record_fields);
    var refusing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const allocator = store.allocator;
    store.allocator = refusing.allocator();
    defer store.allocator = allocator;
    try std.testing.expect(!try store.hasOwners(product));
    try std.testing.expect(!try store.hasOwners(record));
    try std.testing.expect(try store.hasOwners(owned_record));
    try std.testing.expect(!refusing.has_induced_failure);
}

test "selected owning layout discovery follows admitted quantified payload carriers" {
    var source = try types.Store.init(std.testing.allocator);
    defer source.deinit();
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const binder = try source.boundType(0, 0);
    const owner = try source.usage(3, .unique, 0);
    for ([_]types.Tag{ .forall, .existential }) |tag| {
        const plain = try source.quantified(tag, 3, &.{binder});
        const plain_layout = try store.fromSolver(&source, plain);
        try std.testing.expect(!try store.hasOwners(plain_layout));
        const owned = try source.quantified(tag, owner, &.{binder});
        const owned_layout = try store.fromSolver(&source, owned);
        const wrapped = try store.intern(.function, 3, owned_layout, &.{});
        try std.testing.expect(try store.hasOwners(wrapped));
    }
}

test "selected owning layout discovery retains the unique node limit and rejects invalid edges" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    var plain: Id = 3;
    for (0..4095) |_| plain = try store.intern(.array, plain, 0, &.{});
    try std.testing.expect(!try store.hasOwners(plain));
    plain = try store.intern(.array, plain, 0, &.{});
    try std.testing.expectError(error.LayoutLimit, store.hasOwners(plain));
    try std.testing.expectError(error.LayoutLimit, store.hasOwners(std.math.maxInt(Id)));
    const invalid = try store.intern(.array, std.math.maxInt(Id), 0, &.{});
    try std.testing.expectError(error.LayoutLimit, store.hasOwners(invalid));
}

fn sortedUniversalLayouts(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const a = try source.boundType(0, 0);
    const row = try source.boundType(1, 1);
    const callback = try source.functionWithEffects(a, a, try source.rowType(row));
    const root = try source.quantified(.forall, try source.function(callback, callback), &.{ a, row });
    const module: core.Module = .{ .types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .operations = source.operations.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items } }, .nodes = &.{}, .spans = &.{}, .extra = &.{}, .bindings = &.{}, .bodies = &.{}, .parameters = &.{}, .references = &.{}, .calls = &.{}, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 };
    var layouts = try Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    var partial = try code_expectation.Store.init(allocator);
    defer partial.deinit();
    const projected = try semantic.project(&source, root, &.{});
    const physical = try layouts.fromType(&module, root, &.{});
    try std.testing.expectEqual(physical, try layouts.fromSolver(&source, root));
    try std.testing.expectEqual(physical, try layouts.fromEvidence(semantic.view(), projected));
    try std.testing.expectEqual(projected, try layouts.toEvidence(&semantic, physical));
    const expectation = try layouts.toCodeExpectation(&partial, physical);
    try std.testing.expectEqual(@as(u32, 1), partial.view().node(partial.view().children(expectation)[1]).b);
    const body = layouts.node(physical).a;
    const arrow = layouts.node(body).a;
    const formal = layouts.effects.rows.items[layouts.node(arrow).c].formal;
    try std.testing.expectEqual(@as(u32, 1), layouts.node(formal).c);
    const erased_tail = try layouts.intern(.function, layouts.node(arrow).a, layouts.node(arrow).b, &.{});
    try std.testing.expect(erased_tail != arrow);
    const data_only = try layouts.intern(.universal, layouts.node(physical).a, 2, &.{});
    try std.testing.expect(data_only != physical);
    try std.testing.expectError(error.TypeMismatch, layouts.toEvidence(&semantic, data_only));
    const inner = try source.boundType(0, 1);
    const inner_body = try source.functionWithEffects(a, a, try source.rowType(row));
    const nested = try source.quantified(.forall, inner_body, &.{inner});
    const outer = try source.quantified(.forall, try source.function(a, nested), &.{ a, row });
    const nested_recipe = try semantic.project(&source, outer, &.{});
    try std.testing.expectEqual(nested_recipe, try layouts.toEvidence(&semantic, try layouts.fromSolver(&source, outer)));
    // The same captured outer row stays at lexical depth one under the inner
    // quantifier; ordinal zero of the inner scope cannot substitute for it.
    const nested_shape = try layouts.fromEvidence(semantic.view(), nested_recipe);
    try std.testing.expectEqual(nested_recipe, try layouts.toEvidence(&semantic, nested_shape));
}

test "universal layouts preserve sorted binder and captured row metadata through complete allocation failures" {
    try sortedUniversalLayouts(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sortedUniversalLayouts, .{});
}

fn universalDictionaryLayouts(allocator: Allocator) !void {
    var physical = try Store.init(allocator);
    defer physical.deinit();
    const binder = try physical.intern(.opened, 0, 0, &.{});
    const arrow = try physical.intern(.function, binder, 3, &.{});
    const bare = try physical.intern(.universal, arrow, 1, &.{binder});
    const empty = try physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{});
    const typed = try physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{0});
    const callable = try physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{ 0, arrow });
    const reordered = try physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{ arrow, 0 });
    try std.testing.expect(bare != empty and empty != typed and typed != callable and callable != reordered);
    try std.testing.expectError(error.TypeMismatch, physical.mergePartial(bare, empty));
    try std.testing.expectError(error.TypeMismatch, physical.mergePartial(callable, reordered));
    try std.testing.expect(!physical.hasDictionaryABI(bare));
    try std.testing.expect(physical.hasDictionaryABI(empty));
    try std.testing.expectEqual(callable, try physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{ 0, arrow }));
    try std.testing.expectEqualSlices(Id, &.{binder}, physical.children(callable));
    try std.testing.expectEqualSlices(Id, &.{ 0, arrow }, physical.dictionarySlots(callable));
    try std.testing.expectError(error.TypeMismatch, physical.internUniversalWithDictionaries(arrow, &.{binder}, &.{3}));
    var canonical = try evidence.Store.init(allocator);
    defer canonical.deinit();
    _ = try physical.toEvidence(&canonical, bare);
    try std.testing.expectError(error.UnresolvedType, physical.toEvidence(&canonical, empty));
    try std.testing.expectError(error.UnresolvedType, physical.toEvidence(&canonical, callable));
    var expectation = try code_expectation.Store.init(allocator);
    defer expectation.deinit();
    try std.testing.expectError(error.UnresolvedType, physical.toCodeExpectation(&expectation, callable));
    var snapshot = try @import("../reuse/code_artifacts.zig").Layouts.capture(allocator, &physical);
    defer snapshot.deinit(allocator);
    try std.testing.expect(snapshot.hasDictionaryABI(empty));
    try std.testing.expect(!snapshot.hasDictionaryABI(bare));
    try std.testing.expectEqualSlices(Id, &.{binder}, snapshot.children(callable));
    try std.testing.expectEqualSlices(Id, &.{ 0, arrow }, snapshot.dictionarySlots(callable));
}
test "universal dictionary layouts preserve exact ordered slots and empty ABI through owned snapshots and complete allocation failures" {
    try universalDictionaryLayouts(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, universalDictionaryLayouts, .{});
}

fn associatedLayouts(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const identity: types.NominalIdentity = .{ .unit = 1, .decl = 37 };
    const binder = try source.boundType(0, 0);
    const argument = try source.sequence(.array, binder);
    const projection_ = try source.projection(identity, 41, &.{argument});
    const goal: types.Obligation = .{ .kind = .contract, .identity = identity, .ty = try source.product(&.{argument}), .source = 0 };
    const nested_binder = try source.boundType(0, 0);
    const nested = try source.quantified(.forall, try source.function(nested_binder, projection_), &.{nested_binder});
    const root = try source.quantifiedWithGoals(.forall, try source.function(argument, nested), &.{binder}, &.{goal});
    const member = [_]core.ContractMember{.{ .contract = identity, .name = 41, .kind = .abstract_type }};
    const declaration = [_]core.Contract{.{ .private = false, .identity = identity, .name = 37, .parameters = .{}, .variables = .{}, .row_variables = .{}, .predicates = .{}, .members = .{ .len = 1 }, .requires_implementation = true }};
    var module: core.Module = undefined;
    module.unit = 1;
    module.types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .quantifier_goals = source.quantifier_goals.items, .quantifier_obligations = source.quantifier_obligations.items };
    module.contracts = @constCast(&declaration);
    module.contract_members = @constCast(&member);
    var layouts = try Store.init(allocator);
    defer layouts.deinit();
    const actual = try layouts.fromType(&module, root, &.{});
    const inner = layouts.node(layouts.node(actual).a).b;
    const associated = layouts.node(layouts.node(inner).a).b;
    try std.testing.expectEqualDeep(Node{ .tag = .associated, .a = 0, .b = 41, .c = 1 }, layouts.node(associated));
    try std.testing.expect(layouts.scalar(associated) == null);
    var expectation = try code_expectation.Store.init(allocator);
    defer expectation.deinit();
    try std.testing.expectEqual(@as(code_expectation.Id, 0), try layouts.toCodeExpectation(&expectation, associated));
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    try std.testing.expectError(error.UnresolvedType, layouts.toEvidence(&semantic, associated));
    const canonical = try semantic.project(&source, root, &.{});
    const copied = try layouts.fromEvidence(semantic.view(), canonical);
    try std.testing.expectEqual(actual, copied);
    module.contract_members = &.{};
    if (layouts.fromType(&module, root, &.{})) |_| return error.TestExpectedError else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.UnresolvedType);
    }
}
test "associated layouts retain lexical goal and member coordinates without deriving semantic authority through complete OOM" {
    try associatedLayouts(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedLayouts, .{});
}
