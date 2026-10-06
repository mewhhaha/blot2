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
    deep: bool = false,
    deep_source: core.BindingId = 0,
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
            if ((node.tag == .update or node.tag == .array_op or (node.tag == .call or node.tag == .apply)) and receiver(units, unit_id, @intCast(i)) != null) {
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
            if (binding.kind == .local and binding.initializer != 0 and fresh(units, unit_id, binding.initializer, 0)) {
                states[i].origin = true;
                states[i].deep = freshTree(units, unit_id, binding.initializer, 0);
                if (module.node(binding.initializer).tag == .update) {
                    if (receiver(units, unit_id, binding.initializer)) |source| {
                        states[i].deep = freshTree(units, unit_id, module.updateInfo(binding.initializer).value, 0);
                        states[i].deep_source = source;
                    }
                }
            }
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
                    if (operands.len != 0 and module.node(operands[0]).tag == .reference) {
                        read_refs[operands[0]] = true;
                        // Reading an element can expose an inner allocation.
                        // The outer array may still be consumed, but nested
                        // mutation must preserve the extracted value.
                        const ref = module.reference(operands[0]);
                        if (ref.unit == 0 and ref.binding != 0 and module.arrayOperation(id) == .get and !scalarType(module, node.ty)) states[ref.binding].deep = false;
                    }
                },
                .call, .apply => if (receiver(units, unit_id, id)) |binding| {
                    const edit = edit_call.analyze(units, unit_id, id).?;
                    consume(&states[binding], id);
                    consumed_refs[edit.receiver] = true;
                },
                .pattern_bind => {
                    const plan = edit_call.analyze(units, unit_id, node.b) orelse continue;
                    const success = plan.success orelse continue;
                    const p = module.pattern(node.a);
                    if (p.tag != .constructor or p.b == 0 or (module.constructor(p.a).tag != units[plan.target.unit - 1].constructor(success).tag or !std.meta.eql(module.constructor(p.a).identity, units[plan.target.unit - 1].constructor(success).identity))) continue;
                    const child = module.pattern(p.b);
                    if (child.tag != .bind) continue;
                    states[child.a].origin = true;
                    states[child.a].deep = scalarType(module, module.types.node(child.ty).a);
                },
                .bind => if (node.b != 0 and module.node(node.b).tag == .reference) {
                    const ref = module.reference(node.b);
                    if (ref.unit == 0 and ref.binding != 0 and module.binding(ref.binding).kind == .local) {
                        consume(&states[ref.binding], id);
                        consumed_refs[node.b] = true;
                        states[node.a].deep = true;
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
                        states[carry.iteration].deep = true;
                        states[carry.outgoing].deep = true;
                        states[carry.iteration].transfer = true;
                        states[carry.iteration].first = carry.incoming;
                        states[carry.iteration].second = carry.backedge;
                        states[carry.outgoing].transfer = true;
                        states[carry.outgoing].first = carry.incoming;
                        states[carry.outgoing].second = carry.backedge;
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
            states[merge.result].deep = true;
            states[merge.result].transfer = true;
            states[merge.result].first = merge.then_binding;
            states[merge.result].second = merge.else_binding;
        }
        // A terminal edge is an alternative to later uses inside its target,
        // not a simultaneous alias. Break predecessors also constrain ownership
        // of the loop result; they need not equal the normal backedge.
        var exit_edges: std.ArrayList(struct { result: core.BindingId, source: core.BindingId }) = .empty;
        defer exit_edges.deinit(allocator);
        for (module.nodes, 0..) |node, i| {
            const exit_id: core.Id = @intCast(i);
            if (node.tag != .break_ and node.tag != .return_) continue;
            const refs = if (node.tag == .break_) module.breakValues(exit_id) else &.{node.a};
            for (refs, 0..) |value, index| {
                if (module.node(value).tag != .reference) continue;
                const ref = module.reference(value);
                if (ref.unit != 0 or ref.binding == 0 or module.binding(ref.binding).kind != .local) continue;
                const state = &states[ref.binding];
                if (node.tag == .break_) {
                    if (module.node(node.a).tag != .loop) continue;
                    const carry = module.loopCarries(node.a)[index];
                    try exit_edges.append(allocator, .{ .result = carry.outgoing, .source = ref.binding });
                    if (state.consumers == 0) {
                        consume(state, exit_id);
                        consumed_refs[value] = true;
                        continue;
                    }
                }
                if (excludesLater(module, exit_id, state.consume)) consumed_refs[value] = true;
            }
        }
        for (module.nodes) |node| {
            if (node.tag != .pattern_bind or node.c == 0) continue;
            const plan = edit_call.analyze(units, unit_id, node.b) orelse continue;
            const success = plan.success orelse continue;
            const p = module.pattern(node.a);
            if (p.tag != .constructor or p.b == 0 or module.pattern(p.b).tag != .bind or (module.constructor(p.a).tag != units[plan.target.unit - 1].constructor(success).tag or !std.meta.eql(module.constructor(p.a).identity, units[plan.target.unit - 1].constructor(success).identity))) continue;
            const binding = receiver(units, unit_id, node.b) orelse continue;
            if (states[binding].consume != node.b or states[binding].consumers != 1) continue;
            // In this arm the guarded edit never executed. Observing the input
            // here does not alias the successful successor.
            for (module.nodes, 0..) |use, j| {
                if (use.tag != .reference) continue;
                const ref = module.reference(@intCast(j));
                if (ref.unit == 0 and ref.binding == binding and consumedInside(module, node.c, @intCast(j), 0)) consumed_refs[j] = true;
            }
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
            for (exit_edges.items) |edge| {
                if (states[edge.result].owned and !states[edge.source].owned) {
                    states[edge.result].owned = false;
                    changed = true;
                }
                if (states[edge.result].deep and !states[edge.source].deep) {
                    states[edge.result].deep = false;
                    changed = true;
                }
            }
            for (states) |*state| {
                if (state.deep_source != 0 and state.deep and (!states[state.deep_source].deep or !states[state.deep_source].owned)) {
                    state.deep = false;
                    changed = true;
                }
                if (!state.transfer) continue;
                if (state.deep and (!states[state.first].deep or !states[state.second].deep)) {
                    state.deep = false;
                    changed = true;
                }
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
            if (node.tag == .update or node.tag == .array_op or (node.tag == .call or node.tag == .apply)) if (receiver(units, unit_id, @intCast(i))) |binding| {
                const nested = node.tag == .update and (module.updateSelectors(@intCast(i)).len > 1 or module.updateSelectors(@intCast(i)).len == 0 or module.updateSelectors(@intCast(i))[0].kind == .field);
                result.updates[i] = states[binding].owned and states[binding].anchored and (!nested or states[binding].deep);
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
        .return_ => consumedInside(module, node.a, consumer, depth + 1),
        .loop => consumedInside(module, module.loopInfo(root).body, consumer, depth + 1),
        .if_stmt, .match => if (branchBodies(module, root)) |branch|
            consumedInside(module, branch.then, consumer, depth + 1) or consumedInside(module, branch.otherwise, consumer, depth + 1)
        else
            false,
        else => false,
    };
}
fn excludesLater(module: *const core.Module, exit_id: core.Id, consumer: core.Id) bool {
    if (consumer <= exit_id) return false;
    const exit_ = module.node(exit_id);
    const target = if (exit_.tag == .break_) module.loopInfo(exit_.a).body else exit_.b;
    return consumedInside(module, target, consumer, 0);
}
fn receiver(units: []const core.Module, unit_id: u32, id: core.Id) ?core.BindingId {
    const module = &units[unit_id - 1];
    const root = if (module.node(id).tag == .array_op) blk: {
        const op = module.arrayOperation(id);
        if (op != .set and op != .append and op != .prepend) return null;
        break :blk module.children(id)[0];
    } else if ((module.node(id).tag == .call or module.node(id).tag == .apply)) blk: {
        const plan = edit_call.analyze(units, unit_id, id) orelse return null;
        break :blk plan.receiver;
    } else blk: {
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
        .array, .record, .product, .construct => true,
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
        .update => true,
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

// Deep reuse requires independent ownership of every nested container. An array
// of repeated pointers (fill) and aggregate fields borrowed from another local
// deliberately fail this proof, even if their outer allocation is fresh.
fn scalarType(module: *const core.Module, ty: @import("types.zig").Id) bool {
    return switch (module.types.node(ty).tag) {
        .unit, .boolean, .u32, .f32 => true,
        else => false,
    };
}
fn freshTree(units: []const core.Module, unit: u32, id: core.Id, depth: usize) bool {
    if (depth >= 32) return false;
    const module = &units[unit - 1];
    const n = module.node(id);
    if (scalarType(module, n.ty)) return true;
    switch (n.tag) {
        .construct => return n.b == 0 or freshTree(units, unit, n.b, depth + 1),
        .record, .product, .array => {
            for (module.children(id)) |child| if (!freshTree(units, unit, child, depth + 1)) return false;
            return true;
        },
        .array_op, .call => {
            const ty = module.types.node(n.ty);
            return (ty.tag == .array or ty.tag == .list) and scalarType(module, ty.a) and fresh(units, unit, id, depth + 1);
        },
        else => return false,
    }
}
