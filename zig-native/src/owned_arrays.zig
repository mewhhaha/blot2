//! Immutable Core versions prove exclusive ownership at an array update.
const std = @import("std");
const core = @import("core.zig");
const edit_call = @import("collection_edit_call.zig");
const State = struct {
    first: core.BindingId = 0,
    second: core.BindingId = 0,
    consume: core.Id = 0,
    consumers: u32 = 0,
    last_read: core.Id = 0,
    escaped: bool = false,
    origin: bool = false,
    transfer: bool = false,
    owned: bool = false,
    anchored: bool = false,
};
pub const Proof = struct {
    updates: []bool = &.{},
    pub fn deinit(self: *Proof, allocator: std.mem.Allocator) void {
        allocator.free(self.updates);
        self.* = .{};
    }
    pub fn admits(self: *const Proof, id: core.Id) bool {
        return id < self.updates.len and self.updates[id];
    }
    pub fn init(allocator: std.mem.Allocator, units: []const core.Module, unit_id: u32) !Proof {
        const module = &units[unit_id - 1];
        var has_candidate = false;
        for (module.nodes, 0..) |node, i| {
            if ((node.tag == .update or node.tag == .array_op or node.tag == .call) and receiver(units, unit_id, @intCast(i)) != null) {
                has_candidate = true;
                break;
            }
        }
        if (!has_candidate) return .{};
        var result: Proof = .{ .updates = try allocator.alloc(bool, module.nodes.len) };
        errdefer result.deinit(allocator);
        @memset(result.updates, false);
        const states = try allocator.alloc(State, module.bindings.len);
        defer allocator.free(states);
        @memset(states, .{});
        const read_refs = try allocator.alloc(bool, module.nodes.len);
        defer allocator.free(read_refs);
        @memset(read_refs, false);
        const consumed_refs = try allocator.alloc(bool, module.nodes.len);
        defer allocator.free(consumed_refs);
        @memset(consumed_refs, false);
        for (module.bindings, 0..) |binding, i| {
            if (binding.kind == .local and binding.initializer != 0 and fresh(units, unit_id, binding.initializer, 0)) states[i].origin = true;
        }
        for (module.nodes, 0..) |node, i| {
            const id: core.Id = @intCast(i);
            switch (node.tag) {
                .update => if (receiver(units, unit_id, id)) |binding| {
                    consume(&states[binding], id);
                    consumed_refs[module.updateInfo(id).root] = true;
                },
                .array_op => if (receiver(units, unit_id, id)) |binding| {
                    consume(&states[binding], id);
                    consumed_refs[module.children(id)[0]] = true;
                } else if (module.arrayOperation(id) == .length or module.arrayOperation(id) == .get) {
                    const operands = module.children(id);
                    if (operands.len != 0 and module.node(operands[0]).tag == .reference) read_refs[operands[0]] = true;
                },
                .call => if (receiver(units, unit_id, id)) |binding| {
                    const edit = edit_call.analyze(units, unit_id, id).?;
                    consume(&states[binding], id);
                    consumed_refs[edit.receiver] = true;
                },
                .bind => if (node.b != 0 and module.node(node.b).tag == .reference) {
                    const ref = module.reference(node.b);
                    if (ref.unit == 0 and ref.binding != 0 and module.binding(ref.binding).kind == .local) {
                        consume(&states[ref.binding], id);
                        consumed_refs[node.b] = true;
                        states[node.a].transfer = true;
                        states[node.a].first = ref.binding;
                        states[node.a].second = ref.binding;
                    }
                },
                .closure, .suspend_ => for (module.extra[module.closures[node.a].captures.start..][0..module.closures[node.a].captures.len]) |binding| {
                    states[binding].escaped = true;
                },
                .loop => {
                    const info = module.loopInfo(id);
                    for (module.loopCarries(id)) |carry| {
                        consume(&states[carry.incoming], id);
                        consume(&states[carry.backedge], info.body);
                        states[carry.iteration].transfer = true;
                        states[carry.iteration].first = carry.incoming;
                        states[carry.iteration].second = carry.backedge;
                        states[carry.outgoing].transfer = true;
                        states[carry.outgoing].first = carry.incoming;
                        states[carry.outgoing].second = carry.backedge;
                        if (info.kind == .forever or info.can_exit) {
                            states[carry.iteration].escaped = true;
                            states[carry.outgoing].escaped = true;
                        }
                    }
                },
                else => {},
            }
        }
        for (module.merges) |merge| {
            // Keeping the incoming value in an untaken arm is not a second
            // simultaneous consumer. The competing update must belong to
            // the opposite arm; later reads and escapes still reject reuse.
            const branch = branchBodies(module, merge.node);
            if (merge.then_binding == merge.else_binding or branch == null or !consumedInside(module, branch.?.otherwise, states[merge.then_binding].consume, 0))
                consume(&states[merge.then_binding], merge.node);
            if (merge.else_binding != merge.then_binding and
                (branch == null or !consumedInside(module, branch.?.then, states[merge.else_binding].consume, 0)))
                consume(&states[merge.else_binding], merge.node);
            states[merge.result].transfer = true;
            states[merge.result].first = merge.then_binding;
            states[merge.result].second = merge.else_binding;
        }
        // Core emits a consuming update after its indices and replacement.
        // A loop reserves its ID before bounds/body, and its final suite ID
        // follows the backedge. These ordering bounds exclude later reads;
        // direct iterator inputs remain escaping borrows.
        for (module.nodes, 0..) |node, i| {
            if (node.tag != .reference) continue;
            const ref = module.reference(@intCast(i));
            if (ref.unit != 0 or ref.binding == 0 or module.binding(ref.binding).kind != .local) continue;
            if (consumed_refs[i]) continue;
            if (read_refs[i]) states[ref.binding].last_read = @max(states[ref.binding].last_read, @as(core.Id, @intCast(i))) else states[ref.binding].escaped = true;
        }
        for (states) |*state| {
            state.owned = (state.origin or state.transfer) and !state.escaped and state.consumers == 1 and state.last_read < state.consume;
            state.anchored = state.origin;
        }
        // Backedges form cycles. First exclude every unsafe predecessor;
        // then require a fresh allocation on each admitted component.
        var changed = true;
        while (changed) {
            changed = false;
            for (states) |*state| {
                if (!state.transfer) continue;
                if (state.owned and (!states[state.first].owned or !states[state.second].owned)) {
                    state.owned = false;
                    changed = true;
                }
                if (!state.anchored and (states[state.first].anchored or states[state.second].anchored)) {
                    state.anchored = true;
                    changed = true;
                }
            }
        }
        for (module.nodes, 0..) |node, i| {
            if (node.tag == .update or node.tag == .array_op or node.tag == .call) if (receiver(units, unit_id, @intCast(i))) |binding| {
                result.updates[i] = states[binding].owned and states[binding].anchored;
            };
        }
        return result;
    }
};
fn consume(state: *State, id: core.Id) void {
    state.consumers += 1;
    state.consume = id;
}
const BranchBodies = struct { then: core.Id, otherwise: core.Id };
fn branchBodies(module: *const core.Module, id: core.Id) ?BranchBodies {
    const node = module.node(id);
    if (node.tag == .if_stmt) return .{ .then = node.b, .otherwise = node.c };
    // `if let` lowers to a two-arm statement match. Its fallback preserves
    // the incoming version just like an ordinary conditional's untaken arm.
    if (node.tag != .match or !module.matchInfo(id).statement) return null;
    const arms = module.matchArms(id);
    if (arms.len != 2 or arms[0].guard != 0 or arms[1].guard != 0) return null;
    return .{ .then = arms[0].body, .otherwise = arms[1].body };
}
fn consumedInside(module: *const core.Module, root: core.Id, consumer: core.Id, depth: usize) bool {
    if (root == 0 or consumer == 0 or depth >= 64) return false;
    if (root == consumer) return true;
    const node = module.node(root);
    return switch (node.tag) {
        .block, .suite => blk: {
            for (module.children(root)) |child| if (consumedInside(module, child, consumer, depth + 1)) break :blk true;
            break :blk false;
        },
        .bind => consumedInside(module, node.b, consumer, depth + 1),
        .if_stmt, .match => if (branchBodies(module, root)) |branch|
            consumedInside(module, branch.then, consumer, depth + 1) or consumedInside(module, branch.otherwise, consumer, depth + 1)
        else
            false,
        else => false,
    };
}
fn receiver(units: []const core.Module, unit_id: u32, id: core.Id) ?core.BindingId {
    const module = &units[unit_id - 1];
    const root = if (module.node(id).tag == .array_op) blk: {
        const op = module.arrayOperation(id);
        if (op != .append and op != .prepend) return null;
        break :blk module.children(id)[0];
    } else if (module.node(id).tag == .call) blk: {
        const plan = edit_call.analyze(units, unit_id, id) orelse return null;
        break :blk plan.receiver;
    } else blk: {
        const selectors = module.updateSelectors(id);
        if (selectors.len != 1 or selectors[0].kind != .index) return null;
        break :blk module.updateInfo(id).root;
    };
    if (module.node(root).tag != .reference) return null;
    const ref = module.reference(root);
    if (ref.unit != 0 or ref.binding == 0 or module.binding(ref.binding).kind != .local) return null;
    return ref.binding;
}
fn fresh(units: []const core.Module, unit_id: u32, id: core.Id, depth: usize) bool {
    if (depth >= 32) return false;
    const module = &units[unit_id - 1];
    const node = module.node(id);
    return switch (node.tag) {
        .array => true,
        .block => blk: {
            const statements = module.children(id);
            if (statements.len == 0) break :blk false;
            // Spread construction captures operands with lets before its
            // final allocation. No earlier control flow may return an alias.
            for (statements[0 .. statements.len - 1]) |statement_| if (module.node(statement_).tag != .bind) break :blk false;
            const result = module.node(statements[statements.len - 1]);
            break :blk result.tag == .return_ and fresh(units, unit_id, result.a, depth + 1);
        },
        .array_op => switch (module.arrayOperation(id)) {
            .fill, .generate, .set, .append, .prepend, .convert => true,
            else => false,
        },
        .update => module.updateSelectors(id).len == 1 and module.updateSelectors(id)[0].kind == .index,
        .call => blk: {
            // The same wrapper proof follows aliases and certifies the
            // returned collection as a fresh or exclusively transferred value.
            if (edit_call.analyze(units, unit_id, id) != null) break :blk true;
            const call = module.call(id);
            const target_unit = if (call.target.unit == 0) unit_id else call.target.unit;
            const target = &units[target_unit - 1];
            const body = target.body(call.target.binding) orelse break :blk false;
            if (!body.is_function or target.bodyParameters(body).len != call.arguments.len) break :blk false;
            // Only direct allocation wrappers are certified. A returned local,
            // block, callback or state value can have another observer.
            const root = target.node(body.root);
            if (root.tag != .array and root.tag != .array_op and root.tag != .call) break :blk false;
            break :blk fresh(units, target_unit, body.root, depth + 1);
        },
        else => false,
    };
}
