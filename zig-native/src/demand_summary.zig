//! Owned, conservative dynamic demand facts. Frozen Core ordinals are scoped
//! to the checked-body pins; no evaluator or inference state is retained.
const std = @import("std");
const core = @import("core.zig");
const queries = @import("semantic_query_table.zig");
const A = std.mem.Allocator;
pub const version: u32 = 1;
pub const Limits = struct { nodes: usize = 131072, bodies: usize = 256, iterations: usize = 32, depth: usize = 256 };
pub const Outcome = enum { never, once, repeated, unknown, escaping };
pub const Scope = struct { branch: core.Id = 0, loop: core.Id = 0, boundary: core.Id = 0, capture: core.Id = 0 };
pub const Fact = struct {
    count: u8 = 0,
    unknown: bool = false,
    escaping: bool = false,
    pub fn outcome(self: Fact) Outcome {
        if (self.escaping) return .escaping;
        if (self.unknown) return .unknown;
        if (self.count == 0) return .never;
        if (self.count == 1) return .once;
        return .repeated;
    }
    fn sequence(left: Fact, right: Fact) Fact {
        return .{ .count = @min(2, left.count + right.count), .unknown = left.unknown or right.unknown, .escaping = left.escaping or right.escaping };
    }
    fn join(left: Fact, right: Fact) Fact {
        return .{ .count = @max(left.count, right.count), .unknown = left.unknown or right.unknown, .escaping = left.escaping or right.escaping };
    }
};
pub const Demand = struct { latent_type: u32 = 0, latent_row: u32 = 0, binding: core.BindingId, creation: core.Id = 0, scope: Scope = .{}, parameter: ?u32 = null, fact: Fact = .{} };
pub const Site = struct { demand: u32, node: core.Id, scope: Scope };
pub const Alias = struct { binding: core.BindingId, demand: u32, scope: Scope };
pub const Capture = struct { closure: core.Id, binding: core.BindingId, latent_type: u32 };
pub const Summary = struct {
    demands: []Demand = &.{},
    sites: []Site = &.{},
    aliases: []Alias = &.{},
    captures: []Capture = &.{},
    exhausted: bool = false,
    pub fn deinit(self: *Summary, a: A) void {
        a.free(self.demands);
        a.free(self.sites);
        a.free(self.aliases);
        a.free(self.captures);
        self.* = .{};
    }
    pub fn clone(self: *const Summary, a: A) A.Error!Summary {
        var result: Summary = .{ .exhausted = self.exhausted };
        errdefer result.deinit(a);
        result.demands = try a.dupe(Demand, self.demands);
        result.sites = try a.dupe(Site, self.sites);
        result.aliases = try a.dupe(Alias, self.aliases);
        result.captures = try a.dupe(Capture, self.captures);
        return result;
    }
    pub fn parameter(self: *const Summary, index: usize) Fact {
        for (self.demands) |demand| if (demand.parameter == @as(u32, @intCast(index))) return demand.fact;
        return .{ .unknown = true };
    }
};
pub const Key = struct {
    target: core.BindingRef,
    /// Complete checked body header, interpreted under the enclosing Core pin.
    /// Exact projection admission covers its reachable graph and captures.
    body: ?core.Body = null,
    schema: u32 = version,
    limits: Limits = .{},
    pub fn deinit(_: *Key, _: A) void {}
};
pub const Dependencies = struct {
    /// Exact checked-body admission validates these ordinals, captures and
    /// frozen latent effect rows against the retained immutable Core pins.
    bodies: []const core.BindingRef,
    lease: ?*Lease = null,
    const Lease = struct { references: usize = 1, allocator: A, bodies: []core.BindingRef };
    fn initOwned(a: A, bodies: []core.BindingRef) A.Error!Dependencies {
        errdefer a.free(bodies);
        const lease = try a.create(Lease);
        lease.* = .{ .allocator = a, .bodies = bodies };
        return .{ .bodies = bodies, .lease = lease };
    }
    fn clone(self: Dependencies, a: A) A.Error!Dependencies {
        if (self.lease) |lease| {
            lease.references += 1;
            return self;
        }
        return initOwned(a, try a.dupe(core.BindingRef, self.bodies));
    }
    pub fn deinit(self: *Dependencies, a: A) void {
        if (self.lease) |lease| {
            lease.references -= 1;
            if (lease.references == 0) {
                lease.allocator.free(lease.bodies);
                lease.allocator.destroy(lease);
            }
        } else a.free(self.bodies);
        self.* = .{ .bodies = &.{} };
    }
};
const Adapter = struct {
    pub const kind: queries.Kind = .demand_summary;
    pub const Key = ThisModuleKey;
    pub const Dependencies = ThisModuleDependencies;
    pub const Result = Summary;
    pub fn fingerprint(key: ThisModuleKey) u64 {
        return (@as(u64, key.target.unit) << 32) | key.target.binding;
    }
    pub fn complete(record: Table.Record) bool {
        return record.key.schema == version and record.key.body != null and record.dependencies.bodies.len != 0;
    }
    pub fn bytes(record: Table.Record) usize {
        const result = record.value;
        return @sizeOf(ThisModuleKey) + record.dependencies.bodies.len * @sizeOf(core.BindingRef) + result.demands.len * @sizeOf(Demand) + result.sites.len * @sizeOf(Site) + result.aliases.len * @sizeOf(Alias) + result.captures.len * @sizeOf(Capture);
    }
};
const ThisModuleKey = Key;
const ThisModuleDependencies = Dependencies;
pub const Table = queries.Table(Adapter);
pub fn fingerprint(key: ThisModuleKey) u64 {
    return Adapter.fingerprint(key);
}
pub fn keyFor(units: []const core.Module, target: core.BindingRef, limits: Limits) Key {
    var key: Key = .{ .target = target, .limits = limits };
    if (target.unit != 0 and target.unit <= units.len) {
        const module = &units[target.unit - 1];
        if (target.binding < module.bindings.len) if (module.body(target.binding)) |body| {
            key.body = body.*;
        };
    }
    return key;
}
pub fn insert(a: A, table: *Table, key: Key, dependencies: Dependencies, summary: Summary) A.Error!?u32 {
    var builder = Table.begin(a, key);
    defer builder.abort();
    builder.read(dependencies);
    builder.stage(summary);
    var candidate = builder.complete() orelse return null;
    defer candidate.abort();
    const prepared = try table.prepare(a, &candidate) orelse return null;
    return table.publish(prepared, &candidate).position;
}
pub fn copyRecord(a: A, record: *const Table.Record) A.Error!Analysis {
    var summary = try record.value.clone(a);
    errdefer summary.deinit(a);
    return .{ .summary = summary, .dependencies = try record.dependencies.clone(a) };
}
pub fn retain(a: A, table: *Table, previous: *const Table, gate: anytype, counters: *@import("work_counters.zig").Counters) A.Error!void {
    var remaining = table.limits.lookup_work;
    var validated: std.AutoHashMapUnmanaged(usize, bool) = .empty;
    defer validated.deinit(a);
    for (previous.records.items) |*record| {
        if (remaining == 0) break;
        remaining -= 1;
        if (record.key.schema != version) continue;
        var admitted: ?bool = null;
        if (record.dependencies.lease) |lease| admitted = validated.get(@intFromPtr(lease));
        if (admitted == null) {
            admitted = true;
            for (record.dependencies.bodies) |dependency| {
                if (remaining == 0) {
                    admitted = false;
                    break;
                }
                remaining -= 1;
                counters.demand_summary_dependency_checks += 1;
                if (!gate.body(dependency)) {
                    admitted = false;
                    break;
                }
            }
            if (record.dependencies.lease) |lease| try validated.put(a, @intFromPtr(lease), admitted.?);
        }
        if (!admitted.?) continue;
        var copy = try copyRecord(a, record);
        defer copy.deinit(a);
        if (try copy.publish(a, table, record.key) == null) break;
        counters.demand_summary_imports += 1;
    }
}
pub const Analysis = struct {
    summary: Summary,
    dependencies: Dependencies,
    pub fn publish(self: *Analysis, a: A, table: *Table, key: Key) A.Error!?u32 {
        const summary = self.summary;
        const dependencies = self.dependencies;
        self.* = .{ .summary = .{}, .dependencies = .{ .bodies = &.{} } };
        return insert(a, table, key, dependencies, summary);
    }
    pub fn deinit(self: *Analysis, a: A) void {
        self.summary.deinit(a);
        self.dependencies.deinit(a);
    }
};
const Entry = struct { target: core.BindingRef, summary: Summary = .{} };
const Graph = struct {
    a: A,
    units: []const core.Module,
    limits: Limits,
    entries: std.ArrayList(Entry) = .empty,
    targets: std.AutoHashMapUnmanaged(core.BindingRef, usize) = .empty,
    remaining: usize,
    discovering: bool = true,
    edges: std.ArrayList(struct { source: u32, target: u32 }) = .empty,
    edge_index: std.AutoHashMapUnmanaged(u64, void) = .empty,
    counters: *@import("work_counters.zig").Counters,
    exhausted: bool = false,
    fn finishDiscovery(self: *Graph) void {
        self.discovering = false;
    }
    fn module(self: *const Graph, unit: u32) ?*const core.Module {
        if (unit == 0 or unit > self.units.len) return null;
        return &self.units[unit - 1];
    }
    fn entry(self: *Graph, target: core.BindingRef) A.Error!?usize {
        if (self.targets.get(target)) |index| return index;
        const module_ = self.module(target.unit) orelse return null;
        if (target.binding >= module_.bindings.len or module_.body(target.binding) == null) return null;
        if (!self.discovering or self.entries.items.len >= self.limits.bodies) {
            self.exhausted = true;
            return null;
        }
        try self.targets.ensureUnusedCapacity(self.a, 1);
        try self.entries.append(self.a, .{ .target = target });
        self.targets.putAssumeCapacity(target, self.entries.items.len - 1);
        return self.entries.items.len - 1;
    }
};
const Walk = struct {
    graph: *Graph,
    module: *const core.Module,
    demands: std.ArrayList(Demand) = .empty,
    sites: std.ArrayList(Site) = .empty,
    aliases: std.ArrayList(Alias) = .empty,
    captures: std.ArrayList(Capture) = .empty,
    binding_demands: std.AutoHashMapUnmanaged(core.BindingId, u32) = .empty,
    creations: std.AutoHashMapUnmanaged(core.Id, u32) = .empty,
    entry_index: u32,
    fn deinit(self: *Walk) void {
        const a = self.graph.a;
        self.demands.deinit(a);
        self.sites.deinit(a);
        self.aliases.deinit(a);
        self.captures.deinit(a);
        self.binding_demands.deinit(a);
        self.creations.deinit(a);
    }
    fn unknown(self: *Walk) void {
        for (self.demands.items) |*item| item.fact.unknown = true;
    }
    fn demand(self: *const Walk, id: core.Id) ?u32 {
        if (id == 0 or self.module.node(id).tag != .reference) return null;
        const ref = self.module.reference(id);
        if (ref.unit != 0 and ref.unit != self.module.unit) return null;
        return self.binding_demands.get(ref.binding);
    }
    fn add(self: *Walk, binding: u32, creation: u32, parameter_: ?u32, scope: Scope, ty: u32) A.Error!void {
        if (binding != 0) {
            if (self.binding_demands.contains(binding)) return;
            try self.binding_demands.put(self.graph.a, binding, @intCast(self.demands.items.len));
        }
        try self.demands.append(self.graph.a, .{ .binding = binding, .creation = creation, .parameter = parameter_, .scope = scope, .latent_type = ty, .latent_row = self.module.types.node(ty).c });
    }
    fn noteCreation(self: *Walk, id: core.Id, scope: Scope, fact: Fact) A.Error!void {
        if (self.creations.get(id)) |index| {
            self.demands.items[index].fact = Fact.join(self.demands.items[index].fact, fact);
            return;
        }
        try self.creations.put(self.graph.a, id, @intCast(self.demands.items.len));
        const ty = self.module.node(id).ty;
        try self.demands.append(self.graph.a, .{ .binding = 0, .creation = id, .scope = scope, .fact = fact, .latent_type = ty, .latent_row = self.module.types.node(ty).c });
        const closure = self.module.suspension(id);
        for (self.module.suspensionCaptures(id)) |binding| try self.captures.append(self.graph.a, .{ .closure = id, .binding = binding, .latent_type = closure.function_type });
    }
    fn escape(self: *Walk, id: core.Id, scope: Scope, depth: usize) A.Error!void {
        if (self.demand(id)) |index| {
            self.demands.items[index].fact.escaping = true;
            return;
        }
        if (id != 0 and (self.module.node(id).tag == .closure or self.module.node(id).tag == .suspend_)) {
            if (self.module.node(id).tag == .suspend_) try self.noteCreation(id, scope, .{ .escaping = true });
            const closure = self.module.closures[self.module.node(id).a];
            for (self.module.extra[closure.captures.start..][0..closure.captures.len]) |binding| {
                try self.captures.append(self.graph.a, .{ .closure = id, .binding = binding, .latent_type = closure.function_type });
                if (self.binding_demands.get(binding)) |index| self.demands.items[index].fact.escaping = true;
            }
            return;
        }
        try self.visit(id, scope, depth);
    }
    fn force(self: *Walk, id: core.Id, source: core.Id, scope: Scope, depth: usize) A.Error!void {
        if (self.demand(id)) |index| {
            const creation = self.demands.items[index];
            var count: u8 = 1;
            if (scope.loop != 0 and creation.scope.loop != scope.loop) count = 2;
            self.demands.items[index].fact = Fact.sequence(creation.fact, .{ .count = count });
            try self.sites.append(self.graph.a, .{ .demand = index, .node = source, .scope = scope });
            if (creation.creation != 0 and creation.fact.count == 0) {
                var evaluation = scope;
                evaluation.loop = creation.scope.loop;
                evaluation.capture = creation.creation;
                try self.visit(self.module.suspension(creation.creation).body, evaluation, depth + 1);
            }
            return;
        }
        if (id != 0 and self.module.node(id).tag == .suspend_) {
            var child = scope;
            child.capture = id;
            try self.visit(self.module.suspension(id).body, child, depth + 1);
            return;
        }
        self.unknown();
        try self.visit(id, scope, depth + 1);
    }
    fn branch(self: *Walk, arms: []const core.Id, scope: Scope, depth: usize) A.Error!void {
        const a = self.graph.a;
        const before = try a.dupe(Demand, self.demands.items);
        defer a.free(before);
        const joined = try a.alloc(Fact, before.len);
        defer a.free(joined);
        @memset(joined, .{});
        for (arms) |arm| {
            for (before, self.demands.items[0..before.len]) |value, *item| item.fact = value.fact;
            try self.visit(arm, scope, depth + 1);
            for (joined, self.demands.items[0..before.len]) |*fact, item| fact.* = Fact.join(fact.*, item.fact);
        }
        for (joined, self.demands.items[0..before.len]) |fact, *item| item.fact = fact;
    }
    fn visit(self: *Walk, id: core.Id, scope: Scope, depth: usize) A.Error!void {
        if (id == 0) return;
        if (depth >= self.graph.limits.depth or self.graph.remaining == 0) {
            self.graph.exhausted = true;
            self.unknown();
            return;
        }
        self.graph.remaining -= 1;
        self.graph.counters.demand_summary_nodes += 1;
        const n = self.module.node(id);
        switch (n.tag) {
            .constant, .panic, .constructor_function, .primitive_function, .type_constructor, .operation_value => {},
            .reference => if (self.demand(id)) |index| {
                self.demands.items[index].fact.escaping = true;
            },
            .force => try self.force(n.a, id, scope, depth),
            .bind => {
                if (self.demand(n.b)) |index| {
                    try self.binding_demands.put(self.graph.a, n.a, index);
                    try self.aliases.append(self.graph.a, .{ .binding = n.a, .demand = index, .scope = scope });
                } else if (self.module.node(n.b).tag == .suspend_) {
                    try self.add(n.a, n.b, null, scope, self.module.node(n.b).ty);
                    const closure = self.module.suspension(n.b);
                    for (self.module.suspensionCaptures(n.b)) |binding| try self.captures.append(self.graph.a, .{ .closure = n.b, .binding = binding, .latent_type = closure.function_type });
                } else try self.visit(n.b, scope, depth + 1);
            },
            .if_value, .if_stmt => {
                try self.visit(n.a, scope, depth + 1);
                var child = scope;
                child.branch = id;
                try self.branch(&.{ n.b, n.c }, child, depth);
            },
            .logical => {
                try self.visit(n.a, scope, depth + 1);
                var child = scope;
                child.branch = id;
                try self.branch(&.{ n.b, 0 }, child, depth);
            },
            .block, .suite => for (self.module.children(id)) |child| try self.visit(child, scope, depth + 1),
            .return_ => try self.escape(n.a, scope, depth + 1),
            .product, .record, .array, .array_op => for (self.module.children(id)) |child| try self.escape(child, scope, depth + 1),
            .construct => try self.escape(n.b, scope, depth + 1),
            .project => try self.visit(n.a, scope, depth + 1),
            .scalar => {
                if (n.c != 0) self.unknown();
                try self.visit(n.a, scope, depth + 1);
                try self.visit(n.b, scope, depth + 1);
            },
            .closure, .suspend_ => try self.escape(id, scope, depth + 1),
            .loop => {
                const loop = self.module.loopInfo(id);
                try self.visit(loop.first, scope, depth + 1);
                try self.visit(loop.end, scope, depth + 1);
                var child = scope;
                child.loop = id;
                for (self.module.loopCarries(id)) |carry| {
                    if (self.binding_demands.get(carry.incoming)) |index| {
                        try self.binding_demands.put(self.graph.a, carry.iteration, index);
                        try self.binding_demands.put(self.graph.a, carry.outgoing, index);
                        self.demands.items[index].fact.unknown = true;
                    }
                }
                try self.visit(loop.body, child, depth + 1);
            },
            .break_ => for (self.module.breakValues(id)) |child| try self.escape(child, scope, depth + 1),
            .call => {
                const call = self.module.call(id);
                var target = call.target;
                if (target.unit == 0) target.unit = self.module.unit;
                self.graph.counters.demand_summary_edges += 1;
                const entry_ = try self.graph.entry(target);
                if (entry_) |callee_index| {
                    const edge_key = (@as(u64, self.entry_index) << 32) | @as(u32, @intCast(callee_index));
                    const edge = try self.graph.edge_index.getOrPut(self.graph.a, edge_key);
                    if (!edge.found_existing) try self.graph.edges.append(self.graph.a, .{ .source = self.entry_index, .target = @intCast(callee_index) });
                }
                var callee: ?*const core.Body = null;
                if (self.graph.module(target.unit)) |unit| if (target.binding < unit.bindings.len) {
                    callee = unit.body(target.binding);
                };
                for (call.arguments, 0..) |argument, i| {
                    if (self.graph.discovering and self.module.node(argument).tag == .suspend_) {
                        try self.visit(self.module.suspension(argument).body, scope, depth + 1);
                        continue;
                    }
                    if (entry_ == null or callee == null or i >= callee.?.parameters.len) {
                        try self.escape(argument, scope, depth + 1);
                        self.unknown();
                        continue;
                    }
                    const unit = self.graph.module(target.unit).?;
                    const parameter_ = unit.bodyParameters(callee.?)[i];
                    if (unit.types.node(parameter_.ty).tag != .demand) {
                        try self.escape(argument, scope, depth + 1);
                        continue;
                    }
                    var fact: Fact = .{};
                    if (self.graph.entries.items[entry_.?].summary.demands.len != 0) fact = self.graph.entries.items[entry_.?].summary.parameter(i);
                    if (self.module.node(argument).tag == .suspend_) try self.noteCreation(argument, scope, fact);
                    if (fact.escaping or fact.unknown) {
                        try self.escape(argument, scope, depth + 1);
                        if (fact.unknown) self.unknown();
                        continue;
                    }
                    if (fact.count != 0) {
                        try self.force(argument, id, scope, depth + 1);
                        if (fact.count > 1) try self.force(argument, id, scope, depth + 1);
                    }
                }
                if (callee != null and call.arguments.len != callee.?.parameters.len) self.unknown();
            },
            .match => {
                for (self.module.matchInputs(id)) |input| try self.visit(input, scope, depth + 1);
                var child = scope;
                child.branch = id;
                var arms: std.ArrayList(core.Id) = .empty;
                defer arms.deinit(self.graph.a);
                for (self.module.matchArms(id)) |arm| {
                    // Guards can fall through and run more than once; retaining
                    // their effects in the prefix is a conservative may-count.
                    try self.visit(arm.guard, child, depth + 1);
                    try arms.append(self.graph.a, arm.body);
                    for (self.module.armRows(arm)) |row| for (self.module.rowPatterns(row)) |pattern| if (self.module.types.node(self.module.pattern(pattern).ty).tag == .demand) {
                        self.unknown();
                    };
                }
                try self.branch(arms.items, child, depth);
            },
            .handle => {
                var child = scope;
                child.boundary = id;
                try self.visit(n.a, child, depth + 1);
                try self.visit(n.b, child, depth + 1);
                self.unknown(); // cancellation can retry an unfinished force
            },
            .effect_provider => {
                var child = scope;
                child.boundary = id;
                try self.visit(n.a, child, depth + 1);
                try self.escape(n.b, child, depth + 1);
            },
            .state_provider => {
                var child = scope;
                child.boundary = id;
                try self.visit(n.a, child, depth + 1);
                try self.visit(n.b, child, depth + 1);
                try self.visit(n.c, child, depth + 1);
            },
            .request_loop => {
                var child = scope;
                child.boundary = id;
                child.loop = id;
                const info = self.module.requestLoopInfo(id);
                try self.escape(info.computation, child, depth + 1);
                for (self.module.requestArms(id)) |arm| try self.escape(arm.callback, child, depth + 1);
                try self.visit(info.completion_body, child, depth + 1);
                self.unknown();
            },
            else => self.unknown(),
        }
    }
    fn run(self: *Walk, body: *const core.Body) A.Error!Summary {
        for (self.module.bodyParameters(body), 0..) |parameter_, i| if (self.module.types.node(parameter_.ty).tag == .demand) try self.add(parameter_.binding, 0, @intCast(i), .{}, parameter_.ty);
        try self.visit(body.root, .{}, 0);
        var result: Summary = .{};
        errdefer result.deinit(self.graph.a);
        result.demands = try self.demands.toOwnedSlice(self.graph.a);
        result.sites = try self.sites.toOwnedSlice(self.graph.a);
        result.aliases = try self.aliases.toOwnedSlice(self.graph.a);
        result.captures = try self.captures.toOwnedSlice(self.graph.a);
        return result;
    }
};
fn analyzeEntry(graph: *Graph, index: usize) A.Error!Summary {
    const ref = graph.entries.items[index].target;
    const module = graph.module(ref.unit).?;
    var walk: Walk = .{ .graph = graph, .module = module, .entry_index = @intCast(index) };
    defer walk.deinit();
    return walk.run(module.body(ref.binding).?);
}
const Components = struct {
    offsets: []u32,
    targets: []u32,
    indices: []?u32,
    low: []u32,
    active: []bool,
    stack: std.ArrayList(u32) = .empty,
    members: std.ArrayList(u32) = .empty,
    recursive: std.ArrayList(bool) = .empty,
    groups: std.ArrayList(core.List) = .empty,
    next: u32 = 0,
    fn init(a: A, graph: *const Graph) A.Error!Components {
        const n = graph.entries.items.len;
        var self: Components = .{ .offsets = &.{}, .targets = &.{}, .indices = &.{}, .low = &.{}, .active = &.{} };
        errdefer self.deinit(a);
        self.offsets = try a.alloc(u32, n + 1);
        @memset(self.offsets, 0);
        self.targets = try a.alloc(u32, graph.edges.items.len);
        self.indices = try a.alloc(?u32, n);
        @memset(self.indices, null);
        self.low = try a.alloc(u32, n);
        self.active = try a.alloc(bool, n);
        @memset(self.active, false);
        for (graph.edges.items) |edge| self.offsets[edge.source + 1] += 1;
        for (1..self.offsets.len) |i| self.offsets[i] += self.offsets[i - 1];
        const cursors = try a.dupe(u32, self.offsets);
        defer a.free(cursors);
        for (graph.edges.items) |edge| {
            self.targets[cursors[edge.source]] = edge.target;
            cursors[edge.source] += 1;
        }
        for (0..n) |i| if (self.indices[i] == null) try self.visit(a, @intCast(i));
        return self;
    }
    fn deinit(self: *Components, a: A) void {
        a.free(self.offsets);
        a.free(self.targets);
        a.free(self.indices);
        a.free(self.low);
        a.free(self.active);
        self.stack.deinit(a);
        self.members.deinit(a);
        self.recursive.deinit(a);
        self.groups.deinit(a);
    }
    fn visit(self: *Components, a: A, node: u32) A.Error!void {
        self.indices[node] = self.next;
        self.low[node] = self.next;
        self.next += 1;
        try self.stack.append(a, node);
        self.active[node] = true;
        var self_edge = false;
        for (self.targets[self.offsets[node]..self.offsets[node + 1]]) |target| {
            if (target == node) self_edge = true;
            if (self.indices[target] == null) {
                try self.visit(a, target);
                self.low[node] = @min(self.low[node], self.low[target]);
            } else if (self.active[target]) self.low[node] = @min(self.low[node], self.indices[target].?);
        }
        if (self.low[node] != self.indices[node].?) return;
        const start: u32 = @intCast(self.members.items.len);
        while (self.stack.pop()) |member| {
            self.active[member] = false;
            try self.members.append(a, member);
            try self.recursive.append(a, self_edge);
            if (member == node) break;
        }
        const len: u32 = @intCast(self.members.items.len - start);
        try self.groups.append(a, .{ .start = start, .len = len });
    }
};

pub fn analyze(a: A, units: []const core.Module, target: core.BindingRef, limits: Limits, counters: *@import("work_counters.zig").Counters) A.Error!Analysis {
    return analyzeCached(a, units, target, limits, counters, null);
}
/// The optional destination belongs to the unpublished backend capture.
/// All component facts become visible only when that enclosing capture succeeds.
pub fn analyzeCached(a: A, units: []const core.Module, target: core.BindingRef, limits: Limits, counters: *@import("work_counters.zig").Counters, destination: ?*Table) A.Error!Analysis {
    counters.demand_summary_builds += 1;
    var graph: Graph = .{ .a = a, .units = units, .limits = limits, .remaining = limits.nodes, .counters = counters };
    defer {
        for (graph.entries.items) |*entry_| entry_.summary.deinit(a);
        graph.entries.deinit(a);
        graph.edges.deinit(a);
        graph.edge_index.deinit(a);
        graph.targets.deinit(a);
    }
    _ = try graph.entry(target) orelse return .{ .summary = .{ .exhausted = true }, .dependencies = .{ .bodies = try a.dupe(core.BindingRef, &.{target}) } };
    // Discover call edges before scheduling components. This pass never
    // publishes demand facts; deferred forwarding bodies are visited only to
    // discover their checked dependencies.
    var discovered: usize = 0;
    while (discovered < graph.entries.items.len and !graph.exhausted) : (discovered += 1) {
        var result = try analyzeEntry(&graph, discovered);
        result.deinit(a);
    }
    graph.finishDiscovery();
    var components = try Components.init(a, &graph);
    defer components.deinit(a);
    // Tarjan publishes dependency components before their callers. Each
    // recursive component gets its own monotone budget; long acyclic forwarding
    // chains therefore cost one body pass rather than one whole-graph pass per hop.
    for (components.groups.items) |group| {
        var converged = false;
        for (0..limits.iterations) |_| {
            counters.demand_summary_iterations += 1;
            var changed = false;
            for (components.members.items[group.start..][0..group.len]) |index| {
                const summary = try analyzeEntry(&graph, index);
                const previous = &graph.entries.items[index].summary;
                if (previous.demands.len != summary.demands.len) changed = true;
                for (summary.demands, 0..) |*item, i| if (i < previous.demands.len) {
                    item.fact = Fact.join(previous.demands[i].fact, item.fact);
                    if (!std.meta.eql(item.fact, previous.demands[i].fact)) changed = true;
                };
                previous.deinit(a);
                previous.* = summary;
                if (graph.exhausted) break;
            }
            if (graph.exhausted) break;
            if (group.len == 1 and !components.recursive.items[group.start]) {
                converged = true;
                break;
            }
            if (!changed) {
                converged = true;
                break;
            }
        }
        if (!converged) {
            counters.demand_summary_declines += 1;
            for (components.members.items[group.start..][0..group.len]) |index| {
                graph.entries.items[index].summary.exhausted = true;
                for (graph.entries.items[index].summary.demands) |*item| item.fact.unknown = true;
            }
        }
    }
    if (graph.exhausted) for (graph.entries.items) |*entry_| {
        entry_.summary.exhausted = true;
        for (entry_.summary.demands) |*item| item.fact.unknown = true;
    };
    const bodies = try a.alloc(core.BindingRef, graph.entries.items.len);
    for (bodies, graph.entries.items) |*dependency, entry_| dependency.* = entry_.target;
    var dependencies = try Dependencies.initOwned(a, bodies);
    errdefer dependencies.deinit(a);
    if (destination) |table| {
        for (graph.entries.items[1..]) |*entry_| {
            const key = keyFor(units, entry_.target, limits);
            var cursor = table.candidates(fingerprint(key), .oldest_first);
            var found = false;
            while (cursor.next()) |position| if (std.meta.eql(table.records.items[position].key, key)) {
                found = true;
                break;
            };
            if (found) continue;
            var child = try entry_.summary.clone(a);
            const child_dependencies = dependencies.clone(a) catch |err| {
                child.deinit(a);
                return err;
            };
            _ = try insert(a, table, key, child_dependencies, child);
        }
    }
    const summary = graph.entries.items[0].summary;
    graph.entries.items[0].summary = .{};
    for (summary.demands) |demand_| switch (demand_.fact.outcome()) {
        .never => counters.demand_summary_never += 1,
        .once => counters.demand_summary_once += 1,
        .repeated => counters.demand_summary_repeated += 1,
        .unknown => counters.demand_summary_unknown += 1,
        .escaping => counters.demand_summary_escaping += 1,
    };
    return .{ .summary = summary, .dependencies = dependencies };
}
