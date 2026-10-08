//! PRIVATE source-owned unsolved value-template transport boundary. This imports a representation; it
//! does not publish constant slots, callable certificates, or skip source fuel.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const evidence = @import("type_evidence.zig");
const artifacts = @import("code_artifacts.zig");
const admission = @import("principal_reuse_gate.zig");
const importer = @import("artifact_import.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{Declined};

pub const Reason = enum { none, source, slot, bounds, open_evidence, domain, owner, cycle, quota };
pub const RowPolicy = enum { empty_only, source_declared };
pub const Stats = struct {
    values: usize = 0,
    kinds: [@typeInfo(eval.ValueKind).@"enum".field_names.len]usize = @splat(0),
    unsupported_kinds: [@typeInfo(eval.ValueKind).@"enum".field_names.len]usize = @splat(0),
    open_evidence: usize = 0,
    template_holes: usize = 0,
    origins: [@typeInfo(eval.ClosureOrigin).@"enum".field_names.len]usize = @splat(0),
    unsupported_evidence: usize = 0,
    closures: usize = 0,
    children: usize = 0,
    fields: usize = 0,
    type_maps: usize = 0,
    row_maps: usize = 0,
};

fn room(current: usize, added: usize) bool {
    return current <= std.math.maxInt(u32) and added <= std.math.maxInt(u32) - current;
}
fn range(start: usize, len: usize, total: usize) bool {
    return start <= total and len <= total - start;
}
const Checker = struct {
    allocator: Allocator,
    pools: *const artifacts.Pools,
    gate: *const admission.Gate,
    seen: []u8,
    semantic: []u8,
    order: std.ArrayList(eval.ValueId) = .empty,
    stats: Stats = .{},
    reason: Reason = .none,
    row_policy: RowPolicy = .empty_only,
    fn reject(self: *Checker, reason: Reason) void {
        if (self.reason == .none) self.reason = reason;
    }
    fn sourceOwner(self: *const Checker, unit: u32) bool {
        return unit != 0 and unit <= self.pools.modules.len and unit <= self.gate.structural_units.len and self.gate.structural_units[unit - 1];
    }
    fn nominal(self: *const Checker, unit: u32, decl: u32) bool {
        if (!self.gate.admitsCatalog(self.pools, unit) or decl == 0) return false;
        for (self.pools.modules[unit - 1].module.nominals) |item| if (item.identity.decl == decl and (item.identity.unit == 0 or item.identity.unit == unit)) return true;
        return false;
    }
    fn sourceArrows(module: *const core.Module, source: u32, applied: u32) bool {
        var current = source;
        for (0..@as(usize, applied) + 1) |index| {
            if (current == 0 or current >= module.types.nodes.len) return false;
            const node = module.types.nodes[current];
            if (node.tag != .function) return false;
            if (index < applied) current = node.b;
        }
        return true;
    }
    fn nominalShape(self: *const Checker, info: eval.ValueInfo) bool {
        const unit: u32 = @intCast(info.nominal >> 32);
        const decl: u32 = @truncate(info.nominal);
        const module = self.pools.modules[unit - 1].module;
        for (module.constructors) |constructor| {
            if (constructor.nominal >= module.nominals.len) return false;
            const family = module.nominals[constructor.nominal].identity;
            if (family.decl == decl and (family.unit == 0 or family.unit == unit) and constructor.tag == info.bits)
                return info.len == @as(u32, if (constructor.payload == 0) 0 else 1);
        }
        return false;
    }
    fn row(self: *Checker, id: u32, depth: usize) bool {
        if (self.row_policy == .empty_only) return id == 0;
        // These are closed semantic rows used by already inferred callable
        // types. Runtime providers and compiler-generated operations remain
        // outside the graph domain. The immutable source catalog owns each
        // operation declaration; all arguments have the same bounded proof.
        const effects = self.pools.evaluator.evidence.effects.view();
        if (depth >= 128 or id >= effects.rows.len) return false;
        const span = effects.rows[id];
        if (!range(span.start, span.len, effects.labels.len) or (id == 0 and span.len != 0)) return false;
        for (effects.labels[span.start..][0..span.len]) |label| {
            if (label == 0 or label >= effects.operations.len) return false;
            const operation = effects.operations[label];
            const args = operation.arguments;
            if (!range(args.start, args.len, effects.arguments.len)) return false;
            if (operation.identity.unit == 0) {
                if (operation.identity.decl != 1 or args.len != 0) return false;
            } else {
                if (!self.gate.admitsCatalog(self.pools, operation.identity.unit) or operation.identity.decl == 0) return false;
                const module = self.pools.modules[operation.identity.unit - 1].module;
                const declared = catalog: {
                    for (module.types.operations) |item| if (std.meta.eql(item.identity, operation.identity)) break :catalog true;
                    for (module.operation_values) |item| if (std.meta.eql(item.identity, operation.identity)) break :catalog true;
                    break :catalog false;
                };
                if (!declared) return false;
            }
            for (effects.arguments[args.start..][0..args.len]) |argument| if (!self.ty(argument, depth + 1)) return false;
        }
        return true;
    }
    fn ty(self: *Checker, id: u32, depth: usize) bool {
        const view = self.pools.evaluator.evidence.view();
        if (id == 0 or id >= view.nodes.len or depth >= 128) return false;
        if (self.semantic[id] == 2) return true;
        if (self.semantic[id] == 1 or self.semantic[id] == 3) return false;
        self.semantic[id] = 1;
        const n = view.nodes[id];
        const valid = switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => n.a == 0 and n.b == 0 and n.c == 0,
            .function => self.ty(n.a, depth + 1) and self.ty(n.b, depth + 1) and self.row(n.c, depth + 1),
            .array, .list, .cursor => n.b == 0 and n.c == 0 and self.ty(n.a, depth + 1),
            .product, .record => list: {
                if (n.c != 0) break :list false;
                const words: usize = if (n.tag == .record) @as(usize, n.b) * 2 else n.b;
                if (!range(n.a, words, view.extra.len)) break :list false;
                const children = view.extra[n.a..][0..words];
                for (children, 0..) |child, index| {
                    if (n.tag == .record and index % 2 == 0) {
                        if (self.pools.identity == null or child == 0 or child >= self.pools.identity.?.symbols.len) break :list false;
                    } else if (!self.ty(child, depth + 1)) break :list false;
                }
                break :list true;
            },
            .nominal => list: {
                if (!self.nominal(n.a, n.b) or n.c >= view.extra.len) break :list false;
                const count = view.extra[n.c];
                if (!range(@as(usize, n.c) + 1, count, view.extra.len)) break :list false;
                for (view.extra[n.c + 1 ..][0..count]) |child| if (!self.ty(child, depth + 1)) break :list false;
                break :list true;
            },
            .absent, .demand, .type_constructor, .resolver, .provider, .state_provider => false,
        };
        self.semantic[id] = if (valid) 2 else 3;
        return valid;
    }
    fn value(self: *Checker, id: eval.ValueId, depth: usize) Allocator.Error!void {
        const snapshot = &self.pools.evaluator;
        if (id == 0) return;
        if (id >= snapshot.values.len or id >= snapshot.value_evidence.len or id >= snapshot.value_records.len) {
            self.reject(.bounds);
            return;
        }
        if (depth >= 128) {
            self.reject(.quota);
            return;
        }
        if (self.seen[id] == 2) return;
        if (self.seen[id] == 1) {
            self.reject(.cycle);
            return;
        }
        if (self.stats.values >= 65_536) {
            self.reject(.quota);
            return;
        }
        self.seen[id] = 1;
        const info = snapshot.values[id];
        self.stats.values += 1;
        self.stats.kinds[@backingInt(info.kind)] += 1;
        const semantic = snapshot.value_evidence[id];
        if (semantic == 0) {
            self.stats.open_evidence += 1;
            switch (info.kind) {
                .array, .list, .cursor, .product, .record, .nominal, .closure => self.stats.template_holes += 1,
                else => self.reject(.open_evidence),
            }
        } else if (!self.ty(semantic, 0)) {
            self.stats.unsupported_evidence += 1;
            self.reject(.domain);
        }
        if (semantic != 0 and semantic < snapshot.evidence.nodes.len) {
            const shape = snapshot.evidence.nodes[semantic];
            const compatible = switch (info.kind) {
                .scalar => shape.tag == @as(evidence.Tag, switch (info.scalar) {
                    .unit => .unit,
                    .bool => .boolean,
                    .u32 => .u32,
                    .f32 => .f32,
                    else => .absent,
                }),
                .product => shape.tag == .product and shape.b == info.len,
                .array => shape.tag == .array,
                .list => shape.tag == .list,
                .cursor => shape.tag == .cursor and info.len == 1,
                .record => shape.tag == .record and shape.b == info.len,
                .nominal => shape.tag == .nominal and shape.a == @as(u32, @intCast(info.nominal >> 32)) and shape.b == @as(u32, @truncate(info.nominal)),
                .closure => shape.tag == .function,
                else => false,
            };
            if (!compatible) self.reject(.domain);
        }
        if (!range(info.start, info.len, snapshot.children.len)) {
            self.reject(.bounds);
            return;
        }
        self.stats.children += info.len;
        switch (info.kind) {
            .scalar => switch (info.scalar) {
                .unit, .bool, .u32, .f32 => if (info.len != 0) self.reject(.bounds),
                else => self.reject(.domain),
            },
            .array, .list, .product, .record => {},
            .cursor => {
                if (info.len != 1 or snapshot.children[info.start] >= snapshot.values.len) {
                    self.reject(.bounds);
                } else {
                    const source = snapshot.values[snapshot.children[info.start]];
                    if ((source.kind != .array and source.kind != .list) or info.bits > source.len) self.reject(.bounds);
                }
            },
            .nominal => {
                if (!self.nominal(@intCast(info.nominal >> 32), @truncate(info.nominal))) {
                    self.reject(.owner);
                } else if (!self.nominalShape(info)) self.reject(.bounds);
            },
            .closure => {
                self.stats.closures += 1;
                if (info.bits >= snapshot.closures.len) {
                    self.reject(.bounds);
                } else {
                    const meta = snapshot.closures[info.bits];
                    if (!self.sourceOwner(meta.unit)) {
                        self.reject(.owner);
                    } else {
                        const module = self.pools.modules[meta.unit - 1].module;
                        self.stats.origins[@backingInt(meta.origin)] += 1;
                        switch (meta.origin) {
                            .named => {
                                if (!self.gate.admits(.{ .unit = meta.unit, .binding = meta.identity })) {
                                    self.reject(.source);
                                } else if (module.body(meta.identity)) |definition| {
                                    if (!definition.is_function or info.len != meta.applied or meta.applied >= definition.parameters.len or !sourceArrows(module, module.binding(meta.identity).ty, meta.applied)) self.reject(.bounds);
                                } else self.reject(.source);
                            },
                            .anonymous => {
                                if (meta.identity >= module.closures.len) {
                                    self.reject(.bounds);
                                } else {
                                    const template = module.closures[meta.identity];
                                    if (meta.applied != 0 or info.len != template.captures.len) self.reject(.bounds);
                                    if (template.qualifier != 0) {
                                        if (template.qualifier >= module.bindings.len) {
                                            self.reject(.bounds);
                                        } else {
                                            const binding = module.bindings[template.qualifier];
                                            if (binding.kind == .global) {
                                                if (!self.gate.admits(.{ .unit = meta.unit, .binding = template.qualifier })) self.reject(.source);
                                            } else if (binding.kind == .local) {
                                                if (binding.initializer == 0 or binding.initializer >= module.nodes.len or module.nodes[binding.initializer].tag != .closure or module.nodes[binding.initializer].a != meta.identity) self.reject(.source);
                                            } else self.reject(.source);
                                        }
                                    }
                                }
                            },
                            .constructor => {
                                if (meta.identity >= module.constructors.len) {
                                    self.reject(.bounds);
                                } else {
                                    const constructor = module.constructors[meta.identity];
                                    if (constructor.payload == 0 or meta.applied != 0 or info.len != 0 or !sourceArrows(module, constructor.scheme.root, 0)) self.reject(.bounds);
                                }
                            },
                            // Native source currently requires literal intrinsics
                            // at their exact arity; no firstclass primitive proof
                            // is established by this bounded representation gate.
                            .primitive => self.reject(.domain),
                            .operation => self.reject(.domain),
                        }
                        if (meta.ty != 0 and meta.ty >= module.types.nodes.len) self.reject(.bounds);
                        if (!range(meta.mappings.start, meta.mappings.len, snapshot.type_mappings.len) or !range(meta.row_mappings.start, meta.row_mappings.len, snapshot.row_mappings.len)) {
                            self.reject(.bounds);
                        } else {
                            self.stats.type_maps += meta.mappings.len;
                            self.stats.row_maps += meta.row_mappings.len;
                            for (snapshot.type_mappings[meta.mappings.start..][0..meta.mappings.len], 0..) |mapping, index| {
                                if (mapping.variable == 0 or mapping.variable >= module.types.nodes.len or module.types.nodes[mapping.variable].tag != .variable or !self.ty(mapping.evidence, 0)) self.reject(.bounds);
                                for (snapshot.type_mappings[meta.mappings.start..][0..index]) |prior| if (prior.variable == mapping.variable) self.reject(.bounds);
                            }
                            for (snapshot.row_mappings[meta.row_mappings.start..][0..meta.row_mappings.len], 0..) |mapping, index| {
                                if (mapping.variable >= module.types.effects.variable_count or !self.row(mapping.evidence, 0)) self.reject(.bounds);
                                for (snapshot.row_mappings[meta.row_mappings.start..][0..index]) |prior| if (prior.variable == mapping.variable) self.reject(.bounds);
                            }
                        }
                    }
                }
            },
            else => {
                self.stats.unsupported_kinds[@backingInt(info.kind)] += 1;
                self.reject(.domain);
            },
        }
        const record = snapshot.value_records[id];
        if ((info.kind == .record) != (record != 0)) self.reject(.bounds);
        if (record != 0) {
            if (record >= snapshot.record_layouts.len) {
                self.reject(.bounds);
            } else {
                const names = snapshot.record_layouts[record];
                if (!range(names.start, names.len, snapshot.field_names.len) or names.len != info.len) self.reject(.bounds) else {
                    self.stats.fields += names.len;
                    for (snapshot.field_names[names.start..][0..names.len]) |name| if (name == 0 or self.pools.identity == null or name >= self.pools.identity.?.symbols.len) self.reject(.bounds);
                }
            }
        }
        for (snapshot.children[info.start..][0..info.len]) |child| try self.value(child, depth + 1);
        self.seen[id] = 2;
        try self.order.append(self.allocator, id);
    }
};

pub const ScratchStats = struct {
    match_calls: usize = 0,
    materializations: usize = 0,
    initialized_slots: usize = 0,
    plan_positions: usize = 0,
    inverse_positions: usize = 0,
    anchor_resets: usize = 0,
    child_positions: usize = 0,
    baseline_match_index_entries: usize = 0,
    baseline_material_index_entries: usize = 0,
};
/// PRIVATE scratch for one fixed query State, old Pools and live consumer.
/// Only owned index buffers survive a call; no Session slice is retained.
/// Sparse cleanup runs on success, decline and OOM before another attempt.
pub const QueryScratch = struct {
    allocator: Allocator,
    owner: ?usize = null,
    generator: ?usize = null,
    session: ?usize = null,
    pools: ?*const artifacts.Pools = null,
    gate: ?*const admission.Gate = null,
    policy: ?RowPolicy = null,
    stats: ScratchStats = .{},
    anchors: std.ArrayList(u32) = .empty,
    anchor_ids: std.ArrayList(u32) = .empty,
    positions: std.ArrayList(usize) = .empty,
    candidate: std.ArrayList(u32) = .empty,
    inverse: std.ArrayList(u32) = .empty,
    inverse_ids: std.ArrayList(u32) = .empty,
    semantic: std.ArrayList(u32) = .empty,
    types: std.ArrayList(evidence.Mapping) = .empty,
    rows: std.ArrayList(evidence.RowMapping) = .empty,
    children: std.ArrayList(u32) = .empty,
    child_ids: std.ArrayList(u32) = .empty,
    append_children: std.ArrayList(bool) = .empty,
    pub fn deinit(self: *QueryScratch) void {
        self.anchors.deinit(self.allocator);
        self.anchor_ids.deinit(self.allocator);
        self.positions.deinit(self.allocator);
        self.candidate.deinit(self.allocator);
        self.inverse.deinit(self.allocator);
        self.inverse_ids.deinit(self.allocator);
        self.semantic.deinit(self.allocator);
        self.types.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.children.deinit(self.allocator);
        self.child_ids.deinit(self.allocator);
        self.append_children.deinit(self.allocator);
        self.* = undefined;
    }
    fn bind(self: *QueryScratch, plan: *const Plan, g: anytype) Error!void {
        if (self.allocator.ptr != g.evaluator.allocator.ptr or self.allocator.vtable != g.evaluator.allocator.vtable or g.evaluator.units.ptr != plan.gate.units.ptr or g.evaluator.units.len != plan.gate.units.len) return error.Declined;
        if (self.owner) |owner| {
            if (owner != @intFromPtr(self) or self.generator.? != @intFromPtr(g) or self.session.? != @intFromPtr(&g.evaluator) or self.pools.? != plan.pools or self.gate.? != plan.gate or self.policy.? != plan.row_policy) return error.Declined;
        } else {
            self.owner = @intFromPtr(self);
            self.generator = @intFromPtr(g);
            self.session = @intFromPtr(&g.evaluator);
            self.pools = plan.pools;
            self.gate = plan.gate;
            self.policy = plan.row_policy;
        }
    }
    fn grow(self: *QueryScratch, comptime T: type, buffer: *std.ArrayList(T), length: usize, initial: T) Allocator.Error!void {
        const before = buffer.items.len;
        try buffer.resize(self.allocator, length);
        if (length > before) {
            @memset(buffer.items[before..], initial);
            self.stats.initialized_slots += length - before;
        }
    }
    /// The returned anchors are borrowed until the next candidate or deinit.
    pub fn begin(self: *QueryScratch, plan: *const Plan, g: anytype) Error![]u32 {
        try self.bind(plan, g);
        for (self.anchor_ids.items) |id| self.anchors.items[id] = 0;
        self.stats.anchor_resets += self.anchor_ids.items.len;
        self.anchor_ids.clearRetainingCapacity();
        try self.grow(u32, &self.anchors, plan.pools.evaluator.values.len, 0);
        return self.anchors.items;
    }
    fn finishMatch(self: *QueryScratch, order: []const u32) void {
        for (order) |id| {
            self.positions.items[id] = std.math.maxInt(usize);
            self.candidate.items[id] = 0;
        }
        for (self.inverse_ids.items) |id| self.inverse.items[id] = 0;
        self.stats.inverse_positions += self.inverse_ids.items.len;
        self.inverse_ids.clearRetainingCapacity();
    }
    fn finishChildren(self: *QueryScratch, order: []const u32) void {
        for (self.child_ids.items) |id| self.children.items[id] = std.math.maxInt(u32);
        self.stats.child_positions += self.child_ids.items.len;
        self.child_ids.clearRetainingCapacity();
        for (order) |id| self.append_children.items[id] = false;
    }
};

pub const Inspection = struct { reason: Reason, stats: Stats, plan: ?Plan };
pub const Plan = struct {
    /// Old pools/Core and the checked Gate remain immutable and live through
    /// import. This plan owns only its postorder, not a portable dependency key.
    pools: *const artifacts.Pools,
    gate: *const admission.Gate,
    root: eval.ValueId,
    order: []eval.ValueId,
    stats: Stats,
    row_policy: RowPolicy = .empty_only,
    pub fn deinit(self: *Plan, a: Allocator) void {
        a.free(self.order);
        self.* = undefined;
    }
    pub fn inspect(a: Allocator, pools: *const artifacts.Pools, gate: *const admission.Gate, target: core.BindingRef) Allocator.Error!Inspection {
        if (gate.source_pools == null or gate.source_pools.? != pools) return .{ .reason = .owner, .stats = .{}, .plan = null };
        if (!gate.admits(target) or target.unit > pools.modules.len or target.unit > pools.binding_offsets.len) return .{ .reason = .source, .stats = .{}, .plan = null };
        const module = pools.modules[target.unit - 1].module;
        const body = module.body(target.binding) orelse return .{ .reason = .source, .stats = .{}, .plan = null };
        if (body.runtime or body.is_function) return .{ .reason = .source, .stats = .{}, .plan = null };
        const slot_index = std.math.add(usize, pools.binding_offsets[target.unit - 1], target.binding) catch return .{ .reason = .bounds, .stats = .{}, .plan = null };
        if (slot_index >= pools.slots.len or pools.slots[slot_index].state != 2) return .{ .reason = .slot, .stats = .{}, .plan = null };
        const root = pools.slots[slot_index].value;
        return inspectRoots(a, pools, gate, &.{root});
    }
    /// PRIVATE exact-query graphs, without constant-slot or body-proof claims.
    pub fn inspectRoots(a: Allocator, pools: *const artifacts.Pools, gate: *const admission.Gate, roots: []const u32) Allocator.Error!Inspection {
        return inspectRootsWithRows(a, pools, gate, roots, .empty_only);
    }
    pub fn inspectRootsWithRows(a: Allocator, pools: *const artifacts.Pools, gate: *const admission.Gate, roots: []const u32, row_policy: RowPolicy) Allocator.Error!Inspection {
        if (roots.len == 0 or gate.source_pools == null or gate.source_pools.? != pools or !gate.enabled) return .{ .reason = .owner, .stats = .{}, .plan = null };
        const snapshot = &pools.evaluator;
        if (snapshot.values.len == 0 or snapshot.value_evidence.len == 0 or snapshot.value_records.len == 0 or snapshot.values[0].kind != .scalar or snapshot.values[0].scalar != .unit or snapshot.values[0].len != 0 or snapshot.value_evidence[0] != 1 or snapshot.value_records[0] != 0 or snapshot.evidence.nodes.len <= 1 or !std.meta.eql(snapshot.evidence.nodes[1], evidence.Node{ .tag = .unit })) return .{ .reason = .bounds, .stats = .{}, .plan = null };
        const seen = try a.alloc(u8, pools.evaluator.values.len);
        defer a.free(seen);
        @memset(seen, 0);
        const semantic = try a.alloc(u8, pools.evaluator.evidence.nodes.len);
        defer a.free(semantic);
        @memset(semantic, 0);
        var check: Checker = .{ .allocator = a, .pools = pools, .gate = gate, .seen = seen, .semantic = semantic, .row_policy = row_policy };
        defer check.order.deinit(a);
        for (roots) |root| try check.value(root, 0);
        if (check.reason != .none) return .{ .reason = check.reason, .stats = check.stats, .plan = null };
        return .{ .reason = .none, .stats = check.stats, .plan = .{ .pools = pools, .gate = gate, .root = roots[0], .order = try check.order.toOwnedSlice(a), .stats = check.stats, .row_policy = row_policy } };
    }

    /// Exact existing dependency-root aliases are representation anchors, not
    /// type/call certificates. Both owners already evaluated these constants.
    /// A candidate graph is compared completely before any anchor is committed.
    fn anchorGlobals(self: *const Plan, g: anytype, graphs: *importer.Importer, semantic: []const u32, mapped: []u32, entry: u32) Error!void {
        const a = g.evaluator.allocator;
        const positions = try a.alloc(usize, self.pools.evaluator.values.len);
        defer a.free(positions);
        @memset(positions, std.math.maxInt(usize));
        for (self.order, 0..) |id, index| positions[id] = index;
        const candidate = try a.alloc(u32, positions.len);
        defer a.free(candidate);
        const inverse = try a.alloc(u32, g.evaluator.values.items.len);
        defer a.free(inverse);
        for (self.pools.modules) |pin| {
            if (pin.unit == entry) continue;
            for (pin.module.bodies[1..]) |body| {
                if (body.runtime or !self.gate.admits(.{ .unit = pin.unit, .binding = body.binding })) continue;
                const old_slot = self.pools.slots[self.pools.binding_offsets[pin.unit - 1] + body.binding];
                if (old_slot.state != 2 or old_slot.value == 0 or old_slot.value >= positions.len or positions[old_slot.value] == std.math.maxInt(usize)) continue;
                const slot = g.evaluator.slots[g.evaluator.binding_offsets[pin.unit - 1] + body.binding];
                if (slot.state != .complete) return error.Declined;
                @memset(candidate, 0);
                @memset(inverse, 0);
                for (mapped, 0..) |current, old| if (current != 0) {
                    inverse[current] = @intCast(old);
                };
                if (!try self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, old_slot.value, slot.value, 0, null)) return error.Declined;
                for (candidate, 0..) |current, old| if (current != 0) {
                    mapped[old] = current;
                };
            }
        }
    }
    fn matchesAnchor(self: *const Plan, g: anytype, graphs: *importer.Importer, positions: []const usize, semantic: []const u32, mapped: []const u32, candidate: []u32, inverse: []u32, old_id: u32, current: u32, depth: usize, inverse_ids: ?*std.ArrayList(u32)) Allocator.Error!bool {
        if (old_id == 0) return current == 0;
        if (depth >= 128 or old_id >= positions.len or positions[old_id] == std.math.maxInt(usize) or current == 0 or current >= g.evaluator.values.items.len) return false;
        if (mapped[old_id] != 0 and mapped[old_id] != current) return false;
        if (candidate[old_id] != 0) return candidate[old_id] == current;
        if (inverse[current] != 0 and inverse[current] != old_id) return false;
        const old = &self.pools.evaluator;
        const left = old.values[old_id];
        const right = g.evaluator.valueInfo(current);
        if (left.kind != right.kind or left.scalar != right.scalar or left.nominal != right.nominal or left.len != right.len or semantic[positions[old_id]] != g.evaluator.valueEvidence(current)) return false;
        if (left.kind == .closure) {
            const meta = old.closures[left.bits];
            const actual = g.evaluator.closureInfo(current);
            if (meta.unit != actual.unit or meta.identity != actual.identity or meta.applied != actual.applied or meta.origin != actual.origin or meta.ty != actual.ty or meta.mappings.len != actual.mappings.len or meta.row_mappings.len != actual.row_mappings.len) return false;
            for (old.type_mappings[meta.mappings.start..][0..meta.mappings.len], g.evaluator.type_mappings.items[actual.mappings.start..][0..actual.mappings.len]) |seed, target| {
                if (seed.variable != target.variable or (try graphs.importEvidence(g, seed.evidence)) != target.evidence) return false;
            }
            for (old.row_mappings[meta.row_mappings.start..][0..meta.row_mappings.len], g.evaluator.row_mappings.items[actual.row_mappings.start..][0..actual.row_mappings.len]) |seed, target| {
                if (seed.variable != target.variable) return false;
                const imported_row = if (seed.evidence == 0) @as(u32, 0) else (try graphs.importSemanticRow(g, seed.evidence)) orelse return false;
                if (imported_row != target.evidence) return false;
            }
        } else if (left.bits != right.bits) return false;
        const record = old.value_records[old_id];
        const names: []const u32 = if (record == 0) &.{} else old.field_names[old.record_layouts[record].start..][0..old.record_layouts[record].len];
        if (!std.mem.eql(u32, names, g.evaluator.recordFieldNames(current))) return false;
        candidate[old_id] = current;
        if (inverse[current] == 0) if (inverse_ids) |ids| ids.appendAssumeCapacity(current);
        inverse[current] = old_id;
        for (old.children[left.start..][0..left.len], g.evaluator.valueChildren(current)) |child, actual| if (!try self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, child, actual, depth + 1, inverse_ids)) return false;
        return true;
    }
    /// Every fallible graph conversion/reservation precedes publishing values.
    /// Semantic interning may retain valid facts on OOM, like the full importer;
    /// no value/header/slot or callable proof is partially published.
    pub fn matchInto(self: *const Plan, g: anytype, graphs: *importer.Importer, old_root: u32, current_root: u32, mapped: []u32) Error!bool {
        const a = g.evaluator.allocator;
        if (self.gate.source_pools == null or self.gate.source_pools.? != self.pools or graphs.old != self.pools or !graphs.enabled or g.evaluator.units.ptr != self.gate.units.ptr or g.evaluator.units.len != self.gate.units.len or graphs.unit_map.len != self.gate.units.len or graphs.units.ptr != self.gate.units.ptr or graphs.units.len != self.gate.units.len) return error.Declined;
        for (graphs.unit_map, 1..) |unit, index| if (unit != index) return error.Declined;
        for (graphs.symbol_map, 0..) |symbol, index| if (symbol != index) return error.Declined;
        if (mapped.len != self.pools.evaluator.values.len) return error.Declined;
        const positions = try a.alloc(usize, mapped.len);
        defer a.free(positions);
        @memset(positions, std.math.maxInt(usize));
        for (self.order, 0..) |id, index| positions[id] = index;
        const semantic = try a.alloc(u32, self.order.len);
        defer a.free(semantic);
        for (self.order, semantic) |id, *actual| actual.* = if (self.pools.evaluator.value_evidence[id] == 0) 0 else (try graphs.importEvidence(g, self.pools.evaluator.value_evidence[id])) orelse return false;
        const candidate = try a.alloc(u32, mapped.len);
        defer a.free(candidate);
        @memset(candidate, 0);
        const inverse = try a.alloc(u32, g.evaluator.values.items.len);
        defer a.free(inverse);
        @memset(inverse, 0);
        for (mapped, 0..) |current, old| if (current != 0) {
            if (current >= inverse.len) return false;
            inverse[current] = @intCast(old);
        };
        if (!try self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, old_root, current_root, 0, null)) return false;
        for (candidate, 0..) |current, old| if (current != 0) {
            mapped[old] = current;
        };
        return true;
    }
    pub fn matchIntoWithScratch(self: *const Plan, g: anytype, graphs: *importer.Importer, old_root: u32, current_root: u32, mapped: []u32, scratch: *QueryScratch) Error!bool {
        try scratch.bind(self, g);
        if (self.gate.source_pools == null or self.gate.source_pools.? != self.pools or graphs.old != self.pools or !graphs.enabled or graphs.unit_map.len != self.gate.units.len or graphs.units.ptr != self.gate.units.ptr or graphs.units.len != self.gate.units.len) return error.Declined;
        for (graphs.unit_map, 1..) |unit, index| if (unit != index) return error.Declined;
        for (graphs.symbol_map, 0..) |symbol, index| if (symbol != index) return error.Declined;
        if (mapped.len != self.pools.evaluator.values.len or mapped.ptr != scratch.anchors.items.ptr) return error.Declined;
        try scratch.grow(usize, &scratch.positions, mapped.len, std.math.maxInt(usize));
        try scratch.grow(u32, &scratch.candidate, mapped.len, 0);
        try scratch.grow(u32, &scratch.inverse, g.evaluator.values.items.len, 0);
        try scratch.semantic.resize(scratch.allocator, self.order.len);
        try scratch.inverse_ids.ensureUnusedCapacity(scratch.allocator, scratch.anchor_ids.items.len + self.order.len);
        try scratch.anchor_ids.ensureUnusedCapacity(scratch.allocator, self.order.len);
        scratch.stats.match_calls += 1;
        scratch.stats.plan_positions += self.order.len;
        scratch.stats.baseline_match_index_entries += mapped.len * 4 + g.evaluator.values.items.len;
        defer scratch.finishMatch(self.order);
        const positions = scratch.positions.items;
        const candidate = scratch.candidate.items;
        const inverse = scratch.inverse.items;
        const semantic = scratch.semantic.items;
        for (self.order, 0..) |id, index| positions[id] = index;
        for (self.order, semantic) |id, *actual| actual.* = if (self.pools.evaluator.value_evidence[id] == 0) 0 else (try graphs.importEvidence(g, self.pools.evaluator.value_evidence[id])) orelse return false;
        for (scratch.anchor_ids.items) |old| {
            const current = mapped[old];
            if (current >= inverse.len) return false;
            if (inverse[current] == 0) scratch.inverse_ids.appendAssumeCapacity(current);
            inverse[current] = old;
        }
        if (!try self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, old_root, current_root, 0, &scratch.inverse_ids)) return false;
        for (self.order) |old| if (candidate[old] != 0) {
            if (mapped[old] == 0) scratch.anchor_ids.appendAssumeCapacity(old);
            mapped[old] = candidate[old];
        };
        return true;
    }
    pub fn materialize(self: *const Plan, g: anytype) Error!eval.ValueId {
        return self.materializeWithGlobalAnchors(g, null);
    }
    pub fn materializeWithGlobalAnchors(self: *const Plan, g: anytype, entry: ?u32) Error!eval.ValueId {
        const mapped = try self.materializeMapped(g, entry, null);
        defer g.evaluator.allocator.free(mapped);
        return mapped[self.root];
    }
    /// Seeds are the correspondence proved by matchInto in this paired owner.
    pub const QueryStorage = struct { values_before: usize, values_added: usize, children_added: usize };
    pub fn materializeMapped(self: *const Plan, g: anytype, entry: ?u32, seeds: ?[]const u32) Error![]u32 {
        return self.materializeImpl(g, entry, seeds, null, null, null);
    }
    /// Preserve the ordinary query's exact cumulative value/child quotas.
    pub fn materializeReceiptMapped(self: *const Plan, g: anytype, seeds: []const u32, storage: QueryStorage) Error![]u32 {
        return self.materializeImpl(g, null, seeds, storage, null, null);
    }
    /// The exact-query caller retains this importer only within its one live
    /// Generator/Session. Full owner/maps/allocator checks still precede use.
    pub fn materializeReceiptMappedWithImporter(self: *const Plan, g: anytype, graphs: *importer.Importer, seeds: []const u32, storage: QueryStorage) Error![]u32 {
        return self.materializeImpl(g, null, seeds, storage, graphs, null);
    }
    /// Output borrows scratch anchors; the caller must not free it.
    pub fn materializeReceiptWithScratch(self: *const Plan, g: anytype, graphs: *importer.Importer, seeds: []const u32, storage: QueryStorage, scratch: *QueryScratch) Error![]u32 {
        try scratch.bind(self, g);
        if (seeds.ptr != scratch.anchors.items.ptr or seeds.len != scratch.anchors.items.len) return error.Declined;
        return self.materializeImpl(g, null, seeds, storage, graphs, scratch);
    }
    fn materializeImpl(self: *const Plan, g: anytype, entry: ?u32, seeds: ?[]const u32, storage: ?QueryStorage, paired: ?*importer.Importer, scratch: ?*QueryScratch) Error![]u32 {
        if (self.gate.source_pools == null or self.gate.source_pools.? != self.pools or !self.gate.enabled or g.evaluator.units.ptr != self.gate.units.ptr or g.evaluator.units.len != self.gate.units.len) return error.Declined;
        const a = g.evaluator.allocator;
        // Construct the importer inside this checked namespace instead of
        // accepting an unrelated caller's remap or previously bound generator.
        var owned: ?importer.Importer = null;
        defer if (owned) |*graphs| graphs.deinit();
        const graphs = paired orelse fresh: {
            owned = try importer.Importer.init(a, self.pools, self.gate.units, self.pools.identity.?.view(), self.gate.units.len);
            break :fresh &owned.?;
        };
        if (!graphs.enabled or graphs.old != self.pools or graphs.units.ptr != self.gate.units.ptr or graphs.units.len != self.gate.units.len or graphs.unit_map.len != self.gate.units.len or graphs.allocator.ptr != a.ptr or graphs.allocator.vtable != a.vtable) return error.Declined;
        if (graphs.generator_owner) |owner| if (owner != @intFromPtr(g)) return error.Declined;
        for (graphs.unit_map, self.gate.structural_units, graphs.stable, 1..) |mapped_unit, structural, *stable, unit| {
            // Inspection already proved the owner of every source value and
            // semantic identity used by this plan. An unrelated changed unit
            // remains unavailable to the importer without rejecting the plan.
            if (mapped_unit != unit) return error.Declined;
            stable.* = structural;
        }
        for (graphs.symbol_map, 0..) |mapped_symbol, symbol| if (mapped_symbol != symbol) return error.Declined;
        const old = &self.pools.evaluator;
        const mapped = if (scratch) |buffers| buffers.anchors.items else try a.alloc(u32, old.values.len);
        errdefer if (scratch == null) a.free(mapped);
        if (scratch == null) @memset(mapped, 0);
        if (seeds) |known| {
            if (known.len != mapped.len) return error.Declined;
            if (scratch == null) @memcpy(mapped, known);
        }
        const semantic = if (scratch) |buffers| block: {
            try buffers.semantic.resize(a, self.order.len);
            try buffers.types.resize(a, self.stats.type_maps);
            try buffers.rows.resize(a, self.stats.row_maps);
            try buffers.anchor_ids.ensureUnusedCapacity(a, self.order.len);
            break :block buffers.semantic.items;
        } else try a.alloc(u32, self.order.len);
        defer if (scratch == null) a.free(semantic);
        const maps = if (scratch) |buffers| buffers.types.items else try a.alloc(evidence.Mapping, self.stats.type_maps);
        defer if (scratch == null) a.free(maps);
        const rows = if (scratch) |buffers| buffers.rows.items else try a.alloc(evidence.RowMapping, self.stats.row_maps);
        defer if (scratch == null) a.free(rows);
        var type_index: usize = 0;
        var row_index: usize = 0;
        for (self.order, semantic) |id, *actual| {
            // Zero is an unsolved source hole, never an imported header.
            actual.* = if (old.value_evidence[id] == 0) 0 else (try graphs.importEvidence(g, old.value_evidence[id])) orelse return error.Declined;
            if (old.values[id].kind != .closure) continue;
            const meta = old.closures[old.values[id].bits];
            for (old.type_mappings[meta.mappings.start..][0..meta.mappings.len]) |mapping| {
                maps[type_index] = .{ .variable = mapping.variable, .evidence = (try graphs.importEvidence(g, mapping.evidence)) orelse return error.Declined };
                type_index += 1;
            }
            for (old.row_mappings[meta.row_mappings.start..][0..meta.row_mappings.len]) |mapping| {
                if (mapping.evidence != 0 and self.row_policy == .empty_only) return error.Declined;
                const imported_row = if (mapping.evidence == 0) @as(u32, 0) else (try graphs.importSemanticRow(g, mapping.evidence)) orelse return error.Declined;
                rows[row_index] = .{ .variable = mapping.variable, .evidence = imported_row };
                row_index += 1;
            }
        }
        const session = &g.evaluator;
        if (entry) |root_owner| try self.anchorGlobals(g, graphs, semantic, mapped, root_owner);
        var count: usize = 0;
        for (self.order) |id| if (mapped[id] == 0) {
            count += 1;
        };
        const positions = if (scratch) |buffers| block: {
            try buffers.grow(u32, &buffers.children, old.children.len, std.math.maxInt(u32));
            try buffers.grow(bool, &buffers.append_children, old.values.len, false);
            try buffers.child_ids.ensureUnusedCapacity(a, self.stats.children);
            buffers.stats.materializations += 1;
            buffers.stats.baseline_material_index_entries += old.values.len * 3 + old.children.len;
            break :block buffers.children.items;
        } else try a.alloc(u32, if (storage != null) old.children.len else 0);
        defer if (scratch == null) a.free(positions);
        if (scratch == null) @memset(positions, std.math.maxInt(u32));
        const append_children = if (scratch) |buffers| buffers.append_children.items else try a.alloc(bool, if (storage != null) old.values.len else 0);
        defer if (scratch == null) a.free(append_children);
        if (scratch == null) @memset(append_children, false);
        defer if (scratch) |buffers| buffers.finishChildren(self.order);
        var added_children: usize = 0;
        if (storage) |query| {
            if (count != query.values_added) return error.Declined;
            for (self.order) |id| {
                const info = old.values[id];
                if (mapped[id] == 0) {
                    if (id < query.values_before) return error.Declined;
                    continue;
                }
                if (mapped[id] >= session.values.items.len) return error.Declined;
                const current = session.valueInfo(mapped[id]);
                if (current.len != info.len) return error.Declined;
                for (positions[info.start..][0..info.len], 0..) |*position, index| {
                    const expected = current.start + @as(u32, @intCast(index));
                    if (position.* != std.math.maxInt(u32) and position.* != expected) return error.Declined;
                    if (position.* == std.math.maxInt(u32)) if (scratch) |buffers| buffers.child_ids.appendAssumeCapacity(info.start + @as(u32, @intCast(index)));
                    position.* = expected;
                }
            }
            for (self.order) |id| if (mapped[id] == 0) {
                const info = old.values[id];
                if (info.len == 0) continue;
                const span = positions[info.start..][0..info.len];
                if (span[0] == std.math.maxInt(u32)) {
                    for (span) |position| if (position != std.math.maxInt(u32)) return error.Declined;
                    if (!room(session.children.items.len, added_children + info.len)) return error.Declined;
                    const start: u32 = @intCast(session.children.items.len + added_children);
                    for (span, 0..) |*position, index| {
                        if (scratch) |buffers| buffers.child_ids.appendAssumeCapacity(info.start + @as(u32, @intCast(index)));
                        position.* = start + @as(u32, @intCast(index));
                    }
                    append_children[id] = true;
                    added_children += info.len;
                } else for (span, 0..) |position, index| if (position != span[0] + index) return error.Declined;
            };
            if (added_children != query.children_added) return error.Declined;
        }

        if (count > session.options.max_values -| session.values.items.len or self.stats.children > session.options.max_children -| session.children.items.len) return error.Declined;
        if (!room(session.values.items.len, self.order.len) or !room(session.children.items.len, if (storage != null) added_children else self.stats.children) or !room(session.closures.items.len, self.stats.closures) or !room(session.type_mappings.items.len, maps.len) or !room(session.row_mappings.items.len, rows.len) or !room(session.record_layouts.items.len, self.order.len) or !room(session.field_names.items.len, self.stats.fields)) return error.Declined;
        try session.values.ensureUnusedCapacity(a, self.order.len);
        try session.value_evidence.ensureUnusedCapacity(a, self.order.len);
        try session.value_records.ensureUnusedCapacity(a, self.order.len);
        try session.children.ensureUnusedCapacity(a, if (storage != null) added_children else self.stats.children);
        try session.closures.ensureUnusedCapacity(a, self.stats.closures);
        try session.demands.ensureUnusedCapacity(a, self.stats.closures);
        try session.type_mappings.ensureUnusedCapacity(a, maps.len);
        try session.row_mappings.ensureUnusedCapacity(a, rows.len);
        try session.record_layouts.ensureUnusedCapacity(a, self.order.len);
        try session.field_names.ensureUnusedCapacity(a, self.stats.fields);
        type_index = 0;
        row_index = 0;
        for (self.order, semantic) |id, actual| {
            if (mapped[id] != 0) {
                if (old.values[id].kind == .closure) {
                    const meta = old.closures[old.values[id].bits];
                    type_index += meta.mappings.len;
                    row_index += meta.row_mappings.len;
                }
                continue;
            }
            var info = old.values[id];
            const children = old.children[info.start..][0..info.len];
            info.start = if (storage != null and info.len != 0) positions[info.start] else @intCast(session.children.items.len);
            if (storage == null or append_children[id]) for (children) |child| session.children.appendAssumeCapacity(mapped[child]);
            if (info.kind == .closure) {
                var meta = old.closures[info.bits];
                const len = meta.mappings.len;
                meta.mappings.start = @intCast(session.type_mappings.items.len);
                session.type_mappings.appendSliceAssumeCapacity(maps[type_index..][0..len]);
                type_index += len;
                const row_len = meta.row_mappings.len;
                meta.row_mappings.start = @intCast(session.row_mappings.items.len);
                session.row_mappings.appendSliceAssumeCapacity(rows[row_index..][0..row_len]);
                row_index += row_len;
                info.bits = @intCast(session.closures.items.len);
                session.closures.appendAssumeCapacity(meta);
                session.demands.appendAssumeCapacity(.{});
            }
            var record: u32 = 0;
            if (old.value_records[id] != 0) {
                const fields = old.record_layouts[old.value_records[id]];
                record = @intCast(session.record_layouts.items.len);
                session.record_layouts.appendAssumeCapacity(.{ .start = @intCast(session.field_names.items.len), .len = fields.len });
                session.field_names.appendSliceAssumeCapacity(old.field_names[fields.start..][0..fields.len]);
            }
            if (scratch) |buffers| buffers.anchor_ids.appendAssumeCapacity(id);
            mapped[id] = @intCast(session.values.items.len);
            session.values.appendAssumeCapacity(info);
            session.value_evidence.appendAssumeCapacity(actual);
            session.value_records.appendAssumeCapacity(record);
        }
        return mapped;
    }
};

/// Observation only: repeated roots count their reachable values independently.
/// No execution or cache admission is changed, and target spellings are absent
/// from every admission rule. Fresh root spans identify the actual source root.
pub const RootObservation = struct {
    target: core.BindingRef = .{ .binding = 0 },
    span: core.Span = .{ .start = 0, .end = 0 },
    reason: Reason = .none,
    stats: Stats = .{},
};
pub const Probe = struct {
    enabled: bool = false,
    gate: bool = false,
    requests: usize = 0,
    admitted: usize = 0,
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
    root_kinds: [@typeInfo(eval.ValueKind).@"enum".field_names.len]usize = @splat(0),
    graph_values: usize = 0,
    graph_closures: usize = 0,
    fresh_count: usize = 0,
    fresh_truncated: usize = 0,
    fresh: [32]RootObservation = @splat(.{}),
};
pub fn observe(a: Allocator, pools: *const artifacts.Pools, gate: *const admission.Gate, cached_units: usize) Allocator.Error!Probe {
    var result: Probe = .{ .enabled = true, .gate = gate.enabled };
    for (pools.modules) |pin| for (pin.module.bodies[1..]) |body| {
        if (body.is_function or body.runtime) continue;
        const target: core.BindingRef = .{ .unit = pin.unit, .binding = body.binding };
        const found = try Plan.inspect(a, pools, gate, target);
        defer if (found.plan) |saved| {
            var owned = saved;
            owned.deinit(a);
        };
        result.requests += 1;
        result.reasons[@backingInt(found.reason)] += 1;
        if (found.plan) |plan| {
            result.admitted += 1;
            result.graph_values += plan.stats.values;
            result.graph_closures += plan.stats.closures;
            result.root_kinds[@backingInt(pools.evaluator.values[plan.root].kind)] += 1;
        }
        if (pin.unit > cached_units) {
            if (result.fresh_count < result.fresh.len) {
                result.fresh[result.fresh_count] = .{ .target = target, .span = body.span, .reason = found.reason, .stats = found.stats };
                result.fresh_count += 1;
            } else result.fresh_truncated += 1;
        }
    };
    return result;
}
