//! Private SSA identities for unchanged physical aggregate transport.
//! Indexing updates retain their root value; guest heap writes still execute.
const std = @import("std");
const core = @import("../check/core.zig");
const Position = struct { loop: core.Id, ordinal: usize };
const Exit = struct { node: core.Id, next: ?usize };
const Hypothesis = struct { iteration: core.BindingId, anchor: core.BindingId };
const Query = struct { remaining: usize = 100_000, hypothesis: ?Hypothesis = null };

pub const Index = struct {
    allocator: std.mem.Allocator,
    module: *const core.Module,
    merges: std.AutoHashMapUnmanaged(core.BindingId, usize) = .empty,
    positions: std.AutoHashMapUnmanaged(core.BindingId, Position) = .empty,
    first_exit: std.AutoHashMapUnmanaged(core.Id, usize) = .empty,
    exits: std.ArrayList(Exit) = .empty,
    // Only independently completed carry proofs are published here. A query
    // under an iteration hypothesis never publishes canonical binding results.
    remaining: usize = 1_000_000,
    active: usize = 0,
    lane_remaining: usize = 1_000_000,
    states: std.AutoHashMapUnmanaged(core.BindingId, enum { building, changed, invariant }) = .empty,

    pub fn create(arena: *std.heap.ArenaAllocator, module: *const core.Module) !?*Index {
        const allocator = arena.allocator();
        if (module.nodes.len > 1_000_000 or module.bindings.len > 100_000 or module.merges.len > 100_000) return null;
        // This index and every partial buffer belong to the compilation arena.
        // zig-analyzer: disable-next-line unreleased-allocation
        const result = try allocator.create(Index);
        result.* = .{ .allocator = allocator, .module = module };
        for (module.merges, 0..) |merge, ordinal| try result.merges.put(allocator, merge.result, ordinal);
        for (module.nodes, 0..) |node, ordinal| {
            const id: core.Id = @intCast(ordinal);
            if (node.tag == .loop) for (module.loopCarries(id), 0..) |carry, position| {
                try result.positions.put(allocator, carry.outgoing, .{ .loop = id, .ordinal = position });
            };
            if (node.tag == .break_) {
                try result.exits.append(allocator, .{ .node = id, .next = result.first_exit.get(node.a) });
                try result.first_exit.put(allocator, node.a, result.exits.items.len - 1);
            }
        }
        return result;
    }
    fn charge(self: *Index, query: *Query, depth: usize) bool {
        if (query.remaining == 0 or self.remaining == 0 or depth > 128) return false;
        query.remaining -= 1;
        self.remaining -= 1;
        return true;
    }
    fn expression(self: *Index, id: core.Id, query: *Query, depth: usize) std.mem.Allocator.Error!?core.BindingId {
        if (!self.charge(query, depth) or id == 0) return null;
        const node = self.module.node(id);
        if (node.tag != .reference) return null;
        const reference = self.module.reference(id);
        if (reference.unit != 0 and reference.unit != self.module.unit) return null;
        const kind = self.module.binding(reference.binding).kind;
        if (kind != .local and kind != .parameter) return null;
        return self.binding(reference.binding, query, depth + 1);
    }
    fn binding(self: *Index, id: core.BindingId, query: *Query, depth: usize) std.mem.Allocator.Error!?core.BindingId {
        if (!self.charge(query, depth)) return null;
        if (query.hypothesis) |hypothesis| if (id == hypothesis.iteration) return hypothesis.anchor;
        const source = self.module.binding(id);
        if (source.kind == .parameter) return id;
        if (source.kind != .local) return null;
        if (source.initializer != 0) {
            const node = self.module.node(source.initializer);
            if (node.tag == .reference) return self.expression(source.initializer, query, depth + 1);
            if (node.tag == .update) for (self.module.updateSelectors(source.initializer)) |selector| {
                if (selector.kind == .index) return self.expression(self.module.updateInfo(source.initializer).root, query, depth + 1);
            };
            return id;
        }
        if (self.merges.get(id)) |ordinal| {
            const merge = self.module.merges[ordinal];
            const left = try self.binding(merge.then_binding, query, depth + 1) orelse return null;
            const right = try self.binding(merge.else_binding, query, depth + 1) orelse return null;
            if (left == right) return left;
            return id;
        }
        if (self.positions.get(id)) |position| {
            const carry = self.module.loopCarries(position.loop)[position.ordinal];
            if (self.states.get(carry.iteration)) |state| if (state == .building) return null;
            if (try self.invariant(position.loop, position.ordinal)) return self.binding(carry.incoming, query, depth + 1);
        }
        return id;
    }
    const Lane = struct { binding: core.BindingId, field: []const u8 };
    const LaneQuery = struct { remaining: usize = 100_000, iteration: core.BindingId = 0, anchor: ?Lane = null };
    fn laneCharge(self: *Index, query: *LaneQuery, depth: usize) bool {
        if (query.remaining == 0 or self.lane_remaining == 0 or depth > 128) return false;
        query.remaining -= 1;
        self.lane_remaining -= 1;
        return true;
    }
    fn sameLane(left: Lane, right: Lane) bool {
        return left.binding == right.binding and std.mem.eql(u8, left.field, right.field);
    }
    fn laneExpression(self: *Index, id: core.Id, field: []const u8, query: *LaneQuery, depth: usize) std.mem.Allocator.Error!?Lane {
        if (!self.laneCharge(query, depth) or id == 0) return null;
        const node = self.module.node(id);
        if (node.tag == .reference) {
            const ref = self.module.reference(id);
            if (ref.unit != 0 and ref.unit != self.module.unit) return null;
            return self.laneBinding(ref.binding, field, query, depth + 1);
        }
        if (node.tag == .record_merge) {
            const right = self.module.types.node(self.module.typeOf(node.b));
            if (right.tag != .record) return null;
            for (0..right.b) |ordinal| {
                const name = self.module.fieldSpelling(self.module.types.recordField(right, ordinal).name) orelse return null;
                if (std.mem.eql(u8, name, field)) return self.laneExpression(node.b, field, query, depth + 1);
            }
            return self.laneExpression(node.a, field, query, depth + 1);
        }
        if (node.tag == .update) {
            const selectors = self.module.updateSelectors(id);
            // Indexed writes change the selected payload, not any descriptor
            // or enclosing inline record. Match whole-value canonicalization.
            for (selectors) |selector| if (selector.kind == .index) return self.laneExpression(self.module.updateInfo(id).root, field, query, depth + 1);
            var projection_id: u32 = undefined;
            if (selectors.len != 0) {
                if (selectors[0].kind != .field) return null;
                projection_id = selectors[0].projection;
            } else {
                const path = self.module.updatePath(id);
                if (path.len == 0) return null;
                projection_id = path[0];
            }
            const projection = self.module.projection(projection_id);
            const source = self.module.types.node(projection.source_type);
            if (source.tag != .record) return null;
            const name = self.module.fieldSpelling(projection.field) orelse return null;
            if (std.mem.eql(u8, name, field)) return null;
            return self.laneExpression(self.module.updateInfo(id).root, field, query, depth + 1);
        }
        return null;
    }
    fn laneBinding(self: *Index, id: core.BindingId, field: []const u8, query: *LaneQuery, depth: usize) std.mem.Allocator.Error!?Lane {
        if (!self.laneCharge(query, depth)) return null;
        if (id == query.iteration) return query.anchor;
        const source = self.module.binding(id);
        if (source.kind == .parameter) return .{ .binding = id, .field = field };
        if (source.kind != .local) return null;
        if (source.initializer != 0) {
            const node = self.module.node(source.initializer);
            if (node.tag == .reference or node.tag == .record_merge or node.tag == .update) return self.laneExpression(source.initializer, field, query, depth + 1);
            return .{ .binding = id, .field = field };
        }
        if (self.merges.get(id)) |ordinal| {
            const merge = self.module.merges[ordinal];
            const left = try self.laneBinding(merge.then_binding, field, query, depth + 1) orelse return null;
            const right = try self.laneBinding(merge.else_binding, field, query, depth + 1) orelse return null;
            if (sameLane(left, right)) return left;
            return null;
        }
        return .{ .binding = id, .field = field };
    }
    // Exact immutable-Core projection identities, including every explicit
    // continue and break edge. No type-footprint or remaining-use heuristic.
    pub fn invariantField(self: *Index, loop: core.Id, ordinal: usize, field: []const u8) std.mem.Allocator.Error!bool {
        const carry = self.module.loopCarries(loop)[ordinal];
        var incoming_query: LaneQuery = .{};
        const anchor = try self.laneBinding(carry.incoming, field, &incoming_query, 0) orelse return false;
        var query: LaneQuery = .{ .iteration = carry.iteration, .anchor = anchor };
        const backedge = try self.laneBinding(carry.backedge, field, &query, 0) orelse return false;
        if (!sameLane(backedge, anchor)) return false;
        var cursor = self.first_exit.get(loop);
        while (cursor) |position| {
            const exit = self.exits.items[position];
            if (!self.laneCharge(&query, 0)) return false;
            const args = self.module.breakValues(exit.node);
            if (ordinal >= args.len) return false;
            const lane = try self.laneExpression(args[ordinal], field, &query, 0) orelse return false;
            if (!sameLane(lane, anchor)) return false;
            cursor = exit.next;
        }
        return true;
    }
    pub fn canonical(self: *Index, id: core.BindingId) std.mem.Allocator.Error!?core.BindingId {
        var query: Query = .{};
        return self.binding(id, &query, 0);
    }
    pub fn invariant(self: *Index, loop: core.Id, ordinal: usize) std.mem.Allocator.Error!bool {
        const carry = self.module.loopCarries(loop)[ordinal];
        if (self.states.get(carry.iteration)) |state| return state == .invariant;
        if (self.active >= 64) return false;
        self.active += 1;
        defer self.active -= 1;
        try self.states.put(self.allocator, carry.iteration, .building);
        errdefer _ = self.states.remove(carry.iteration);
        const result = try self.prove(loop, ordinal);
        self.states.getPtr(carry.iteration).?.* = .changed;
        if (result) self.states.getPtr(carry.iteration).?.* = .invariant;
        return result;
    }
    fn prove(self: *Index, loop: core.Id, ordinal: usize) std.mem.Allocator.Error!bool {
        const carry = self.module.loopCarries(loop)[ordinal];
        var incoming_query: Query = .{};
        const anchor = try self.binding(carry.incoming, &incoming_query, 0) orelse return false;
        var query: Query = .{ .hypothesis = .{ .iteration = carry.iteration, .anchor = anchor } };
        const backedge = try self.binding(carry.backedge, &query, 0) orelse return false;
        if (backedge != anchor) return false;
        var cursor = self.first_exit.get(loop);
        while (cursor) |position| {
            const exit = self.exits.items[position];
            if (!self.charge(&query, 0)) return false;
            const args = self.module.breakValues(exit.node);
            if (ordinal >= args.len) return false;
            const value = try self.expression(args[ordinal], &query, 0) orelse return false;
            if (value != anchor) return false;
            cursor = exit.next;
        }
        return true;
    }
};
