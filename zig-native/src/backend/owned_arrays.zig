//! Immutable Core versions prove exclusive ownership at an array update.
const std = @import("std");
const core = @import("../check/core.zig");
const edit_call = @import("collection_edit_call.zig");
const known_call = @import("known_call.zig");
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
    decisions: []?Decision = &.{},
    pub const Decision = enum { reused, escaped, multiple_consumers, later_read, no_fresh_origin, unanchored, nested_alias, nonexclusive_predecessor };
    pub fn deinit(self: *Proof, allocator: std.mem.Allocator) void {
        allocator.free(self.updates);
        allocator.free(self.decisions);
        self.* = .{};
    }
    pub fn admits(self: *const Proof, id: core.Id) bool {
        return id < self.updates.len and self.updates[id];
    }
    pub fn init(allocator: std.mem.Allocator, units: []const core.Module, unit_id: u32) !Proof {
        return initWithDecisions(allocator, units, unit_id, false);
    }
    pub fn initWithDecisions(allocator: std.mem.Allocator, units: []const core.Module, unit_id: u32, explain: bool) !Proof {
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
        if (explain) {
            result.decisions = try allocator.alloc(?Decision, module.nodes.len);
            @memset(result.decisions, null);
        }
        const states = try allocator.alloc(State, module.bindings.len);
        defer allocator.free(states);
        @memset(states, .{});
        // The node after which a borrowed reference is no longer read; zero
        // marks an escaping use.
        const read_refs = try allocator.alloc(core.Id, module.nodes.len);
        defer allocator.free(read_refs);
        @memset(read_refs, 0);
        var borrows: Borrows = .{ .allocator = allocator, .units = units };
        defer borrows.deinit();
        var closures: std.ArrayList(core.Id) = .empty;
        defer closures.deinit(allocator);
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
                } else if (module.arrayOperation(id) == .length or module.arrayOperation(id) == .get or module.arrayOperation(id) == .simd_load) {
                    const operands = module.children(id);
                    if (operands.len != 0 and module.node(operands[0]).tag == .reference) {
                        // The element is read after the index evaluates, so
                        // an edit inside the index cannot reuse this array.
                        read_refs[operands[0]] = id;
                        // Reading an element can expose an inner allocation.
                        // The outer array may still be consumed, but nested
                        // mutation must preserve the extracted value.
                        const ref = module.reference(operands[0]);
                        const extracted = switch (module.arrayOperation(id)) {
                            .get => !scalarType(module, node.ty),
                            .simd_load => !scalarElements(module, module.typeOf(operands[0])),
                            else => false,
                        };
                        if (ref.unit == 0 and ref.binding != 0 and extracted) states[ref.binding].deep = false;
                    }
                } else if (module.arrayOperation(id) == .generate) {
                    // The generator runs only inside this operation.
                    const operands = module.children(id);
                    if (operands.len == 2 and module.node(operands[1]).tag == .closure) try borrows.until.put(allocator, operands[1], id);
                },
                .call, .apply => if (receiver(units, unit_id, id)) |binding| {
                    const edit = edit_call.analyze(units, unit_id, id).?;
                    consume(&states[binding], id);
                    consumed_refs[edit.receiver] = true;
                } else try borrows.markArguments(unit_id, id, states, read_refs),
                .project => try borrows.markArguments(unit_id, id, states, read_refs),
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
                // A closure's consumer follows it; decide its captures below.
                .closure => try closures.append(allocator, id),
                .suspend_ => for (module.suspensionCaptures(id)) |binding| {
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
        // References by binding, built once a guarded edit needs them.
        var references: ?@import("unit_index.zig").Table(core.Id) = null;
        defer if (references) |*table| table.deinit(allocator);
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
            if (references == null) references = try @import("unit_index.zig").references(allocator, module, unit_id);
            for (references.?.get(binding)) |j| {
                if (module.reference(j).unit == 0 and consumedInside(module, node.c, j, 0)) consumed_refs[j] = true;
            }
        }
        // A closure that a generator or borrowing parameter runs and then
        // drops only borrows the captures its body reads. Every other
        // closure keeps its captures alive.
        for (closures.items) |closure| {
            const until = borrows.until.get(closure) orelse 0;
            for (module.closureCaptures(closure)) |binding| {
                if (until != 0 and module.binding(binding).kind == .local) {
                    if (try borrows.captured(unit_id, closure, binding, until, read_refs)) |use| {
                        if (use == .parts) states[binding].deep = false;
                        continue;
                    }
                }
                states[binding].escaped = true;
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
            if (read_refs[i] != 0) states[ref.binding].last_read = @max(states[ref.binding].last_read, read_refs[i]) else states[ref.binding].escaped = true;
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
                const state = states[binding];
                result.updates[i] = state.owned and state.anchored and (!nested or state.deep);
                if (explain) result.decisions[i] = if (result.updates[i]) .reused else if (state.escaped) .escaped else if (state.consumers > 1) .multiple_consumers else if (state.last_read >= state.consume and state.last_read != 0) .later_read else if (!state.origin and !state.transfer) .no_fresh_origin else if (!state.anchored) .unanchored else if (nested and !state.deep) .nested_alias else .nonexclusive_predecessor;
            };
        }
        return result;
    }
};
fn consume(state: *State, id: core.Id) void {
    state.consumers += 1;
    state.consume = id;
}
/// How a source function uses one parameter. `scalars` and `parts` borrow it:
/// lengths, element reads, finite traversal, calls of a callable parameter,
/// arguments of other borrowing parameters and closures that such a use runs
/// and drops observe it. It cannot reach the result, a surviving closure, a
/// merge, a carry, an effect or a store. `parts` means a read element that is
/// not scalar can reach those places, so nested containers stay shared.
const Use = enum { pending, escapes, scalars, parts };
// Bounds on summary work, not language limits: deeper or larger callees
// simply keep their arguments escaping.
const max_borrow_depth = 8;
const max_borrow_nodes = 1024;
const Borrows = struct {
    allocator: std.mem.Allocator,
    units: []const core.Module,
    cache: std.AutoHashMapUnmanaged(Key, Use) = .empty,
    // Closures a generator or borrowing parameter runs before this node,
    // which drops them.
    until: std.AutoHashMapUnmanaged(core.Id, core.Id) = .empty,
    const Key = struct { unit: u32, binding: core.BindingId, index: u32 };
    const Call = struct {
        arguments: [16]core.Id,
        count: usize,
        callee: union(enum) { named: known_call.Wrapper, local: struct { unit: u32, binding: core.BindingId, closure: core.Id } },
    };
    fn deinit(self: *Borrows) void {
        self.cache.deinit(self.allocator);
        self.until.deinit(self.allocator);
    }
    fn call(self: *const Borrows, unit_id: u32, id: core.Id) ?Call {
        if (known_call.resolve(self.units, unit_id, id)) |resolved| {
            if (known_call.wrapper(self.units, unit_id, resolved)) |callee|
                return .{ .arguments = resolved.arguments, .count = resolved.count, .callee = .{ .named = callee } };
        }
        const module = &self.units[unit_id - 1];
        var reverse: [16]core.Id = undefined;
        var count: usize = 0;
        var root = id;
        while (module.node(root).tag == .apply) {
            if (count == reverse.len) return null;
            reverse[count] = module.node(root).b;
            count += 1;
            root = module.node(root).a;
        }
        if (count == 0 or module.node(root).tag != .reference) return null;
        const reference = module.reference(root);
        if (reference.unit != 0 or reference.binding == 0) return null;
        const binding = module.binding(reference.binding);
        if (binding.kind != .local or binding.initializer == 0 or module.node(binding.initializer).tag != .closure) return null;
        var arguments: [16]core.Id = @splat(0);
        for (0..count) |index| arguments[index] = reverse[count - index - 1];
        return .{ .arguments = arguments, .count = count, .callee = .{ .local = .{ .unit = unit_id, .binding = reference.binding, .closure = binding.initializer } } };
    }
    fn callParameter(self: *Borrows, call_: Call, index: usize, depth: u32) error{OutOfMemory}!Use {
        return switch (call_.callee) {
            .named => |callee| self.parameter(callee, index, depth),
            .local => |callee| self.localParameter(callee.unit, callee.binding, callee.closure, call_.count, index, depth),
        };
    }
    fn localParameter(self: *Borrows, unit: u32, binding: core.BindingId, closure: core.Id, count: usize, index: usize, depth: u32) error{OutOfMemory}!Use {
        if (depth >= max_borrow_depth) return .escapes;
        const module = &self.units[unit - 1];
        var current = closure;
        var selected: core.BindingId = 0;
        for (0..count) |position| {
            if (module.node(current).tag != .closure) return .escapes;
            const info = module.closure(current);
            if (position == index) selected = info.parameter.binding;
            current = info.body;
        }
        // A remaining closure is a partial application whose captured argument
        // can outlive this call. Only a fully applied local value borrows.
        if (selected == 0 or module.node(current).tag == .closure) return .escapes;
        const key: Key = .{ .unit = unit, .binding = binding, .index = @intCast(index) };
        if (self.cache.get(key)) |use| return if (use == .pending) .escapes else use;
        try self.cache.put(self.allocator, key, .pending);
        var walk: Walk = .{ .borrows = self, .unit = unit, .binding = selected, .depth = depth };
        const use: Use = if (!try walk.visit(current)) .escapes else if (walk.parts) .parts else .scalars;
        self.cache.getPtr(key).?.* = use;
        return use;
    }
    /// A saturated direct call borrows each local argument whose parameter
    /// only reads it, and runs a closure argument only before it returns.
    /// Those uses last until the call, after every argument has evaluated.
    fn markArguments(self: *Borrows, unit_id: u32, id: core.Id, states: []State, reads: []core.Id) !void {
        const module = &self.units[unit_id - 1];
        const call_ = self.call(unit_id, id) orelse return;
        for (call_.arguments[0..call_.count], 0..) |argument, index| {
            const tag = module.node(argument).tag;
            if (tag == .closure) {
                if (borrowed(try self.callParameter(call_, index, 0))) try self.until.put(self.allocator, argument, id);
                continue;
            }
            if (tag != .reference) continue;
            const ref = module.reference(argument);
            if (ref.unit != 0 or ref.binding == 0 or module.binding(ref.binding).kind != .local) continue;
            const use = try self.callParameter(call_, index, 0);
            if (!borrowed(use)) continue;
            if (use == .parts) states[ref.binding].deep = false;
            reads[argument] = id;
        }
    }
    /// How a closure that runs before `until` uses one local capture. Each
    /// read in its body then lasts until `until`.
    fn captured(self: *Borrows, unit_id: u32, closure: core.Id, binding: core.BindingId, until: core.Id, reads: []core.Id) !?Use {
        const module = &self.units[unit_id - 1];
        var seen: std.ArrayList(core.Id) = .empty;
        defer seen.deinit(self.allocator);
        var walk: Walk = .{ .borrows = self, .unit = unit_id, .binding = binding, .depth = 0, .seen = &seen };
        if (!try walk.visit(module.closure(closure).body)) return null;
        for (seen.items) |ref| reads[ref] = @max(reads[ref], until);
        return if (walk.parts) .parts else .scalars;
    }
    fn parameter(self: *Borrows, callee: known_call.Wrapper, index: usize, depth: u32) error{OutOfMemory}!Use {
        if (depth >= max_borrow_depth) return .escapes;
        const target = callee.target;
        const key: Key = .{ .unit = target.unit, .binding = target.binding, .index = @intCast(index) };
        // A recursive cycle has no summary yet; it keeps its argument.
        if (self.cache.get(key)) |use| return if (use == .pending) .escapes else use;
        try self.cache.put(self.allocator, key, .pending);
        const source = &self.units[target.unit - 1];
        const body = &callee.body;
        const binding = source.bodyParameters(body)[index].binding;
        var walk: Walk = .{ .borrows = self, .unit = target.unit, .binding = binding, .depth = depth };
        const use: Use = if (binding == 0 or !try walk.visit(body.root)) .escapes else if (walk.parts) .parts else .scalars;
        self.cache.getPtr(key).?.* = use;
        return use;
    }
};
fn borrowed(use: Use) bool {
    return use == .scalars or use == .parts;
}
const Walk = struct {
    borrows: *Borrows,
    unit: u32,
    binding: core.BindingId,
    depth: u32,
    budget: usize = max_borrow_nodes,
    parts: bool = false,
    // Admitted direct references, when the caller extends their reads.
    seen: ?*std.ArrayList(core.Id) = null,
    fn module(self: *const Walk) *const core.Module {
        return &self.borrows.units[self.unit - 1];
    }
    fn direct(self: *const Walk, id: core.Id) bool {
        const m = self.module();
        if (id == 0 or m.node(id).tag != .reference) return false;
        const ref = m.reference(id);
        return (ref.unit == 0 or ref.unit == self.unit) and ref.binding == self.binding;
    }
    fn see(self: *Walk, id: core.Id) !void {
        if (self.seen) |list| try list.append(self.borrows.allocator, id);
    }
    fn captures(self: *const Walk, id: core.Id) bool {
        const m = self.module();
        return m.node(id).tag == .closure and std.mem.findScalar(core.BindingId, m.closureCaptures(id), self.binding) != null;
    }
    fn visitAll(self: *Walk, ids: []const core.Id) error{OutOfMemory}!bool {
        for (ids) |id| if (!try self.visit(id)) return false;
        return true;
    }
    /// Whether `id` evaluates without exposing the parameter itself.
    fn visit(self: *Walk, id: core.Id) error{OutOfMemory}!bool {
        if (id == 0) return true;
        if (self.budget == 0) return false;
        self.budget -= 1;
        const m = self.module();
        const n = m.node(id);
        // A merge or carry can make a later binding the same value. Core
        // attaches merges to statement `if`/`match` nodes and carries to
        // loops, so the walk meets each one that can name the binding.
        if (id < m.merge_ranges.len) for (m.branchMerges(id)) |merge| {
            if (merge.then_binding == self.binding or merge.else_binding == self.binding) return false;
        };
        switch (n.tag) {
            .reference => return !self.direct(id),
            .constant, .panic, .primitive_function, .constructor_function => return true,
            .scalar, .logical, .associated => return try self.visit(n.a) and try self.visit(n.b),
            .return_ => return try self.visit(n.a),
            .bind, .construct => return try self.visit(n.b),
            .pattern_bind => return try self.visit(n.b) and try self.visit(n.c),
            .if_value, .if_stmt => return try self.visit(n.a) and try self.visit(n.b) and try self.visit(n.c),
            .match => {
                if (!try self.visitAll(m.matchInputs(id))) return false;
                for (m.matchArms(id)) |arm| {
                    if (!try self.visit(arm.guard) or !try self.visit(arm.body)) return false;
                }
                return true;
            },
            .block, .suite, .array, .product, .record, .break_ => return try self.visitAll(m.children(id)),
            .loop => {
                for (m.loopCarries(id)) |carry| if (carry.incoming == self.binding or carry.iteration == self.binding or carry.backedge == self.binding or carry.outgoing == self.binding) return false;
                const loop = m.loopInfo(id);
                if (loop.kind == .array and self.direct(loop.first)) {
                    const ty = m.types.node(m.typeOf(loop.first));
                    if ((ty.tag != .array and ty.tag != .list) or !scalarType(m, ty.a)) self.parts = true;
                    try self.see(loop.first);
                } else if (!try self.visit(loop.first)) return false;
                return try self.visit(loop.end) and try self.visit(loop.body);
            },
            .array_op => {
                const op = m.arrayOperation(id);
                for (m.children(id), 0..) |child, index| {
                    // Lengths and element or lane reads observe the array. A
                    // generator runs only inside its operation.
                    const generator = index == 1 and op == .generate;
                    if (self.direct(child) and (generator or (index == 0 and (op == .length or op == .get or op == .simd_load)))) {
                        if ((op == .get and !scalarType(m, n.ty)) or (op == .simd_load and !scalarElements(m, m.typeOf(child)))) self.parts = true;
                        try self.see(child);
                        continue;
                    }
                    if (!try (if (generator and self.captures(child)) self.visit(m.closure(child).body) else self.visit(child))) return false;
                }
                return true;
            },
            // A closure body can name the parameter only through its captures.
            .closure => return !self.captures(id),
            .suspend_ => return std.mem.findScalar(core.BindingId, m.suspensionCaptures(id), self.binding) == null,
            .call, .apply, .project => {
                if (self.borrows.call(self.unit, id)) |call_| {
                    for (call_.arguments[0..call_.count], 0..) |argument, index| {
                        const closure = self.captures(argument);
                        if (!closure and !self.direct(argument)) {
                            if (!try self.visit(argument)) return false;
                            continue;
                        }
                        switch (try self.borrows.callParameter(call_, index, self.depth + 1)) {
                            .scalars => {},
                            .parts => self.parts = true,
                            .pending, .escapes => return false,
                        }
                        if (closure) {
                            if (!try self.visit(m.closure(argument).body)) return false;
                        } else try self.see(argument);
                    }
                    return true;
                }
                // Unknown callees and partial applications keep their
                // operands. Calling a callable parameter only runs it.
                return switch (n.tag) {
                    .call => try self.visitAll(m.call(id).arguments),
                    .apply => if (self.direct(n.a)) blk: {
                        try self.see(n.a);
                        break :blk try self.visit(n.b);
                    } else try self.visit(n.a) and try self.visit(n.b),
                    else => try self.visit(n.a),
                };
            },
            else => return false,
        }
    }
};
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
        if (op != .set and op != .append and op != .prepend and op != .simd_store) return null;
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
            .fill, .generate, .set, .append, .prepend, .convert, .simd_store => true,
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
fn scalarElements(module: *const core.Module, collection: @import("../check/types.zig").Id) bool {
    const ty = module.types.node(collection);
    return (ty.tag == .array or ty.tag == .list) and scalarType(module, ty.a);
}
fn scalarType(module: *const core.Module, ty: @import("../check/types.zig").Id) bool {
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
