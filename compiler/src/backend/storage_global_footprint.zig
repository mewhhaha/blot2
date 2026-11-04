//! Conservative source reachability for implicit initialized global owners.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const dependencies = @import("../reuse/declaration_dependencies.zig");
const Allocator = std.mem.Allocator;
const Node = struct { unit: u32, root: core.Id, start: u32 = 0, len: u32 = 0 };
const Edges = struct { nodes: []const Node = &.{}, slots: []const usize = &.{}, all: bool = false };
const Targets = std.ArrayList(core.BindingRef);
const limit = 100_000;

pub const Index = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    units: []const core.Module,
    unit_indices: std.AutoHashMapUnmanaged(u32, usize) = .empty,
    globals: std.AutoHashMapUnmanaged(core.BindingRef, usize) = .empty,
    names: std.StringHashMapUnmanaged(Targets) = .empty,
    operators: std.AutoHashMapUnmanaged(T.Operator, Targets) = .empty,
    unknown_names: bool = false,
    direct: std.AutoHashMapUnmanaged(Node, Edges) = .empty,
    completed: std.AutoHashMapUnmanaged(Node, []const usize) = .empty,
    all: []const usize = &.{},

    pub fn init(a: Allocator, units: []const core.Module, globals: []const core.BindingRef) Allocator.Error!Index {
        var self: Index = .{ .allocator = a, .arena = .init(a), .units = units };
        errdefer self.deinit();
        if (globals.len == 0) return self;
        const arena = self.arena.allocator();
        const all = try arena.alloc(usize, globals.len);
        for (all, 0..) |*slot, i| slot.* = i;
        self.all = all;
        for (globals, 0..) |target, slot| try self.globals.put(a, target, slot);
        for (units, 0..) |*owner, i| {
            try self.unit_indices.put(a, owner.unit, i);
            for (owner.associated) |candidate| {
                var target = candidate.target;
                if (target.unit == 0) target.unit = owner.unit;
                if (candidate.member != 0) {
                    if (owner.fieldSpelling(candidate.member)) |name| {
                        const entry = try self.names.getOrPut(a, name);
                        if (!entry.found_existing) entry.value_ptr.* = .empty;
                        try entry.value_ptr.append(arena, target);
                    } else self.unknown_names = true;
                }
                if (candidate.operator != .none) {
                    const entry = try self.operators.getOrPut(a, candidate.operator);
                    if (!entry.found_existing) entry.value_ptr.* = .empty;
                    try entry.value_ptr.append(arena, target);
                }
            }
        }
        return self;
    }
    pub fn deinit(self: *Index) void {
        self.unit_indices.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.operators.deinit(self.allocator);
        self.direct.deinit(self.allocator);
        self.completed.deinit(self.allocator);
        self.arena.deinit();
        self.* = undefined;
    }
    fn module(self: *const Index, unit: u32) ?*const core.Module {
        return &self.units[self.unit_indices.get(unit) orelse return null];
    }
    fn key(unit: u32, root: core.Id, scheme: T.Scheme) Node {
        return .{ .unit = unit, .root = root, .start = scheme.obligations.start, .len = scheme.obligations.len };
    }
    fn reference(self: *Index, source: u32, target_: core.BindingRef, nodes: *std.AutoHashMapUnmanaged(Node, void), slots_: *std.AutoHashMapUnmanaged(usize, void)) (Allocator.Error || error{CoreLimit})!void {
        var target = target_;
        if (target.unit == 0) target.unit = source;
        var remaining: usize = limit;
        while (remaining != 0) : (remaining -= 1) {
            if (self.globals.get(target)) |slot| {
                try slots_.put(self.allocator, slot, {});
                return;
            }
            const owner = self.module(target.unit) orelse return error.CoreLimit;
            if (target.binding == 0 or target.binding >= owner.bindings.len) return error.CoreLimit;
            const binding = owner.binding(target.binding);
            if (binding.kind == .external) {
                target = binding.target;
                if (target.unit == 0) target.unit = owner.unit;
                continue;
            }
            if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= owner.bodies.len) return error.CoreLimit;
            const body = owner.body(target.binding).?;
            try nodes.put(self.allocator, key(owner.unit, body.root, body.scheme), {});
            return;
        }
        return error.CoreLimit;
    }
    fn scan(self: *Index, node: Node) (Allocator.Error || error{CoreLimit})!Edges {
        const owner = self.module(node.unit) orelse return error.CoreLimit;
        if (node.root >= owner.nodes.len) return error.CoreLimit;
        if (node.start > owner.obligations.len or node.len > owner.obligations.len - node.start) return error.CoreLimit;
        var expression = try dependencies.expression(self.allocator, owner, node.root);
        defer expression.deinit(self.allocator);
        if (expression.runtime_metadata != 0) return error.CoreLimit;
        const members = try dependencies.selectionMembers(self.allocator, owner, .{ .root = node.root, .scheme = .{ .obligations = .{ .start = node.start, .len = node.len } } });
        defer self.allocator.free(members);
        var nodes: std.AutoHashMapUnmanaged(Node, void) = .empty;
        defer nodes.deinit(self.allocator);
        var slots_: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer slots_.deinit(self.allocator);
        for (expression.references) |target| try self.reference(owner.unit, target, &nodes, &slots_);
        for (members) |member| {
            if (member.name != 0) {
                const name = owner.fieldSpelling(member.name) orelse return error.CoreLimit;
                if (self.unknown_names) return error.CoreLimit;
                if (self.names.get(name)) |targets| for (targets.items) |target| try self.reference(owner.unit, target, &nodes, &slots_);
            }
            if (member.operator != .none) {
                if (self.operators.get(member.operator)) |targets| for (targets.items) |target| try self.reference(owner.unit, target, &nodes, &slots_);
            }
            if (nodes.count() > limit) return error.CoreLimit;
        }
        const child_nodes = try self.arena.allocator().alloc(Node, nodes.count());
        var child_iterator = nodes.keyIterator();
        for (child_nodes) |*child| child.* = child_iterator.next().?.*;
        const global_slots = try self.arena.allocator().alloc(usize, slots_.count());
        var slot_iterator = slots_.keyIterator();
        for (global_slots) |*slot| slot.* = slot_iterator.next().?.*;
        return .{ .nodes = child_nodes, .slots = global_slots };
    }
    fn edges(self: *Index, node: Node) Allocator.Error!Edges {
        if (self.direct.get(node)) |value| return value;
        const value = self.scan(node) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.CoreLimit => Edges{ .all = true },
        };
        try self.direct.put(self.allocator, node, value);
        return value;
    }
    pub fn slots(self: *Index, unit: u32, root: core.Id, scheme: T.Scheme) Allocator.Error![]const usize {
        if (self.all.len == 0) return self.all;
        const query = key(unit, root, scheme);
        if (self.completed.get(query)) |value| return value;
        var pending: std.ArrayList(Node) = .empty;
        defer pending.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(Node, void) = .empty;
        defer seen.deinit(self.allocator);
        const selected = try self.allocator.alloc(bool, self.all.len);
        defer self.allocator.free(selected);
        @memset(selected, false);
        try pending.append(self.allocator, query);
        var remaining: usize = limit;
        while (pending.pop()) |node| {
            if (seen.contains(node)) continue;
            if (remaining == 0) {
                try self.completed.put(self.allocator, query, self.all);
                return self.all;
            }
            remaining -= 1;
            try seen.put(self.allocator, node, {});
            if (self.completed.get(node)) |value| {
                for (value) |slot| selected[slot] = true;
                continue;
            }
            const value = try self.edges(node);
            if (value.all) {
                try self.completed.put(self.allocator, query, self.all);
                return self.all;
            }
            for (value.slots) |slot| selected[slot] = true;
            if (value.nodes.len > limit or pending.items.len > limit - value.nodes.len) {
                try self.completed.put(self.allocator, query, self.all);
                return self.all;
            }
            try pending.appendSlice(self.allocator, value.nodes);
        }
        var count: usize = 0;
        for (selected) |present| count += @intFromBool(present);
        const result = try self.arena.allocator().alloc(usize, count);
        var next: usize = 0;
        for (selected, 0..) |present, slot| if (present) {
            result[next] = slot;
            next += 1;
        };
        // Only the complete root is published; cycles never expose partial SCCs.
        try self.completed.put(self.allocator, query, result);
        return result;
    }
};

fn lowerTest(a: Allocator, source: []const u8, unit: u32) !core.Module {
    const lexer = @import("../parse/lexer.zig");
    const parser = @import("../parse/parser.zig");
    const symbols = @import("../parse/symbols.zig");
    const check = @import("../check/check.zig");
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, unit, .{ .builtin_catalog = false });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    result.unit = unit;
    return result;
}
fn bodyNamed(m: *const core.Module, name: []const u8) core.Body {
    for (m.bodies[1..]) |body| if (std.mem.eql(u8, m.name(body.declaration_name), name)) return body;
    unreachable;
}
fn cycleProof(a: Allocator, units: []const core.Module, globals: []const core.BindingRef) !void {
    var index = try Index.init(a, units, globals);
    defer index.deinit();
    const read = bodyNamed(&units[0], "read");
    try std.testing.expectEqualSlices(usize, &.{0}, try index.slots(1, read.root, read.scheme));
    const left = bodyNamed(&units[0], "left_cycle");
    const right = bodyNamed(&units[0], "right_cycle");
    const first = try index.slots(1, left.root, left.scheme);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, first);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, try index.slots(1, right.root, right.scheme));
    try std.testing.expectEqual(first.ptr, (try index.slots(1, left.root, left.scheme)).ptr);
}
test "global footprints stop at owner initializers and cache complete recursive closures through OOM" {
    const a = std.testing.allocator;
    var m = try lowerTest(a,
        \\const left: Array U32 = #[1]
        \\const right: Array U32 = #[left[0]]
        \\const read = func (): U32 => return right[0]
        \\const left_cycle = func (flag: Bool): U32 => return do:
        \\  if flag:
        \\    return right_cycle false
        \\  return read ()
        \\const right_cycle = func (flag: Bool): U32 => return do:
        \\  if flag:
        \\    return left_cycle false
        \\  return left[0]
    , 1);
    defer m.deinit(a);
    const globals = [_]core.BindingRef{ .{ .unit = 1, .binding = bodyNamed(&m, "right").binding }, .{ .unit = 1, .binding = bodyNamed(&m, "left").binding } };
    try cycleProof(a, &.{m}, &globals);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, cycleProof, .{ @as([]const core.Module, &.{m}), @as([]const core.BindingRef, &globals) });
}
test "global footprints overapproximate associated spellings across units and receiver identities" {
    const a = std.testing.allocator;
    var first = try lowerTest(a,
        \\type Box is data = $Box
        \\const left: Array U32 = #[1]
        \\const unused: Array U32 = #[3]
        \\const Box.read = func (_: Box): U32 => return left[0]
        \\const choose = func (value: Box): U32 => return value.read
    , 1);
    defer first.deinit(a);
    var second = try lowerTest(a,
        \\type Other is data = $Other
        \\const padding = 0
        \\const right: Array U32 = #[2]
        \\const Other.read = func (_: Other): U32 => return right[0]
    , 2);
    defer second.deinit(a);
    const globals = [_]core.BindingRef{ .{ .unit = 1, .binding = bodyNamed(&first, "left").binding }, .{ .unit = 2, .binding = bodyNamed(&second, "right").binding }, .{ .unit = 1, .binding = bodyNamed(&first, "unused").binding } };
    var index = try Index.init(a, &.{ first, second }, &globals);
    defer index.deinit();
    try std.testing.expect(!index.unknown_names);
    const choose = bodyNamed(&first, "choose");
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, try index.slots(1, choose.root, choose.scheme));
}
test "global footprints distinguish obligation roots and conservatively retain unknown metadata" {
    const a = std.testing.allocator;
    var m = try lowerTest(a,
        \\const pool: Array U32 = #[1]
        \\const plain = func (): U32 => return 7
    , 1);
    defer m.deinit(a);
    a.free(m.obligations);
    m.obligations = try a.dupe(core.Obligation, &.{.{ .ty = 0, .kind = .field, .name = std.math.maxInt(u32), .span = .{ .start = 0, .end = 0 } }});
    const globals = [_]core.BindingRef{.{ .unit = 1, .binding = bodyNamed(&m, "pool").binding }};
    var index = try Index.init(a, &.{m}, &globals);
    defer index.deinit();
    const plain = bodyNamed(&m, "plain");
    try std.testing.expectEqualSlices(usize, &.{}, try index.slots(1, plain.root, plain.scheme));
    try std.testing.expectEqualSlices(usize, &.{0}, try index.slots(1, plain.root, .{ .obligations = .{ .len = 1 } }));
    try std.testing.expectEqualSlices(usize, &.{0}, try index.slots(999, plain.root, .{}));
    var empty = try Index.init(a, &.{m}, &.{});
    defer empty.deinit();
    try std.testing.expectEqualSlices(usize, &.{}, try empty.slots(999, std.math.maxInt(u32), .{}));
}
