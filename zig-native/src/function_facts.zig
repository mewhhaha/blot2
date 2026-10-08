//! Compile-owned, bounded facts about immutable source functions. Unknown
//! calls, dispatch and captured values stay conservative. These facts guide
//! code generation, never semantic cache validity or principal inference.
const std = @import("std");
const core = @import("core.zig");
pub const small_limit = 8;
pub const Behavior = struct {
    unknown: bool = false,
    effects: bool = false,
    traps: bool = false,
    diverges: bool = false,
    allocates: bool = false,
    pub fn movable(self: Behavior) bool {
        return !self.unknown and !self.effects and !self.traps and !self.diverges and !self.allocates;
    }
    fn merge(self: *Behavior, other: Behavior) void {
        inline for (@typeInfo(Behavior).@"struct".field_names) |field|
            @field(self, field) = @field(self, field) or @field(other, field);
    }
};
pub const Length = union(enum) { unknown, constant: u32, parameter: u8 };
pub const Facts = struct {
    inline_cost: ?u16 = null,
    behavior: Behavior = .{ .unknown = true },
    length: Length = .unknown,
    // Parameters used only as finite traversal sources or intrinsic lengths.
    // No escaping reference, cursor, update, alias, or opaque callee is admitted.
    borrowed_collections: u16 = 0,
};
pub const Stats = struct {
    requested: usize = 0,
    reused: usize = 0,
    analyzed: usize = 0,
    small_collections: usize = 0,
    exact_builders: usize = 0,
    layout_requests: usize = 0,
    layout_reused: usize = 0,
    region_requests: usize = 0,
    evidence_import_requests: usize = 0,
    evidence_import_reused: usize = 0,
    closed_source_imports: usize = 0,
    closed_source_reused: usize = 0,
    split_attempts: usize = 0,
    split_accepted: usize = 0,
    split_declined: usize = 0,
    region_reused: usize = 0,
    region_retained_bytes: usize = 0,
};
pub const Store = struct {
    entries: std.AutoHashMapUnmanaged(core.BindingRef, Facts) = .empty,
    stats: Stats = .{},
    pub fn deinit(self: *Store, a: std.mem.Allocator) void {
        self.entries.deinit(a);
    }
    pub fn get(self: *Store, a: std.mem.Allocator, units: []const core.Module, target: core.BindingRef) !Facts {
        self.stats.requested += 1;
        if (self.entries.get(target)) |facts| {
            self.stats.reused += 1;
            return facts;
        }
        const m = &units[target.unit - 1];
        const body = m.body(target.binding) orelse return .{};
        const cost = @import("inline_body.zig").cost(m, body.root);
        var facts: Facts = .{ .inline_cost = cost };
        if (cost != null) {
            var budget: usize = 256;
            facts.behavior = behavior(m, body.root, &budget);
            const parameters = m.bodyParameters(body);
            const n = m.node(body.root);
            if (n.tag == .array) facts.length = .{ .constant = @intCast(m.children(body.root).len) };
            if (n.tag == .reference) for (parameters, 0..) |p, i| {
                if (i < 16 and local(m, body.root, p.binding)) facts.length = .{ .parameter = @intCast(i) };
            };
            for (parameters, 0..) |p, i| {
                if (i >= 16) break;
                const ty = m.types.node(p.ty).tag;
                if (ty != .array and ty != .list) continue;
                if (privateBinding(m, body.root, p.binding)) facts.borrowed_collections |= @as(u16, 1) << @intCast(i);
            }
        }
        try self.entries.put(a, target, facts);
        self.stats.analyzed += 1;
        return facts;
    }
};
pub fn local(m: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    if (m.node(id).tag != .reference) return false;
    const ref = m.reference(id);
    return (ref.unit == 0 or ref.unit == m.unit) and ref.binding == binding;
}
/// Also used to prove local temporary bindings before selecting scalar storage.
pub fn borrowed(m: *const core.Module, id: core.Id, binding: core.BindingId, allow: bool, budget: *usize) bool {
    if (id == 0) return true;
    if (budget.* == 0) return false;
    budget.* -= 1;
    const n = m.node(id);
    return switch (n.tag) {
        .reference => allow or !local(m, id, binding),
        .constant, .panic, .primitive_function, .constructor_function => true,
        .scalar, .logical, .associated, .apply => borrowed(m, n.a, binding, false, budget) and borrowed(m, n.b, binding, false, budget),
        .project, .return_ => borrowed(m, n.a, binding, false, budget),
        .bind, .construct => borrowed(m, n.b, binding, false, budget),
        .pattern_bind => borrowed(m, n.b, binding, false, budget) and borrowed(m, n.c, binding, false, budget),
        .if_value, .if_stmt => borrowed(m, n.a, binding, false, budget) and borrowed(m, n.b, binding, false, budget) and borrowed(m, n.c, binding, false, budget),
        .loop => blk: {
            const loop = m.loopInfo(id);
            for (m.loopCarries(id)) |carry| if (carry.incoming == binding) break :blk false;
            break :blk borrowed(m, loop.first, binding, loop.kind == .array, budget) and borrowed(m, loop.end, binding, false, budget) and borrowed(m, loop.body, binding, false, budget);
        },
        .array_op => blk: {
            const length = m.arrayOperation(id) == .length;
            for (m.children(id)) |child| if (!borrowed(m, child, binding, length, budget)) break :blk false;
            break :blk true;
        },
        .block, .suite, .array, .product, .record => blk: {
            for (m.children(id)) |child| if (!borrowed(m, child, binding, false, budget)) break :blk false;
            break :blk true;
        },
        .call => blk: {
            for (m.call(id).arguments) |arg| if (!borrowed(m, arg, binding, false, budget)) break :blk false;
            break :blk true;
        },
        // Closures may refer to the binding via their capture lists. A break
        // may export a loop carry. Unsupported constructs decline the proof.
        else => false,
    };
}
pub fn privateBinding(m: *const core.Module, suite: core.Id, binding: core.BindingId) bool {
    // Merges and carries are implicit uses, including edges outside this suite.
    for (m.merges) |merge| if (merge.then_binding == binding or merge.else_binding == binding) return false;
    for (m.loop_carries) |carry| if (carry.incoming == binding or carry.iteration == binding or carry.backedge == binding or carry.outgoing == binding) return false;
    var budget: usize = 256;
    return borrowed(m, suite, binding, false, &budget);
}
pub fn behavior(m: *const core.Module, id: core.Id, budget: *usize) Behavior {
    if (id == 0) return .{};
    if (budget.* == 0) return .{ .unknown = true };
    budget.* -= 1;
    const n = m.node(id);
    var result: Behavior = .{};
    switch (n.tag) {
        .constant, .reference => {},
        .scalar => {
            result = behavior(m, n.a, budget);
            result.merge(behavior(m, n.b, budget));
            if (n.c != 0) result.unknown = true;
            if ((n.op == .div or n.op == .rem) and m.types.node(m.typeOf(n.a)).tag != .f32) result.traps = true;
        },
        .logical => {
            result = behavior(m, n.a, budget);
            result.merge(behavior(m, n.b, budget));
        },
        .if_value, .if_stmt => {
            result = behavior(m, n.a, budget);
            result.merge(behavior(m, n.b, budget));
            result.merge(behavior(m, n.c, budget));
        },
        .return_ => result = behavior(m, n.a, budget),
        .bind => result = behavior(m, n.b, budget),
        .array, .product, .record, .array_op, .block, .suite => {
            for (m.children(id)) |child| result.merge(behavior(m, child, budget));
            if (n.tag == .array or n.tag == .product or n.tag == .record) result.allocates = true;
            if (n.tag == .array_op) switch (m.arrayOperation(id)) {
                .length, .identity, .cursor_has => {},
                .get, .cursor_value => result.traps = true,
                .generate => result = .{ .unknown = true, .allocates = true, .traps = true },
                else => {
                    result.allocates = true;
                    result.traps = true;
                },
            };
        },
        .loop => {
            const loop = m.loopInfo(id);
            result = behavior(m, loop.first, budget);
            result.merge(behavior(m, loop.end, budget));
            result.merge(behavior(m, loop.body, budget));
            result.diverges = result.diverges or loop.kind == .forever;
        },
        .panic => result.traps = true,
        .closure, .suspend_, .constructor_function, .primitive_function => result.allocates = true,
        .construct => {
            result = behavior(m, n.b, budget);
            result.allocates = true;
        },
        .operation_value, .effect_provider, .state_provider, .handle, .request_loop, .request_decision, .force, .resolver_op => result = .{ .unknown = true, .effects = true },
        else => result.unknown = true,
    }
    return result;
}
